"""Audio tools — the ONLY way the agent turns explanations into speech.

Tools resolve the explanation text from the DB, synthesize via the TTS provider,
and cache the WAV on disk keyed by content hash. The LLM never touches audio bytes.
"""
from __future__ import annotations

import hashlib
import logging
import os
import re
import tempfile
import threading
import time

from sqlalchemy.orm import Session

from sahlha.app.audio import tts
from sahlha.app.database.repositories import repositories as repo

logger = logging.getLogger(__name__)

_VOICE_RE = re.compile(r"[^A-Za-z0-9 _-]")

# Per-key locks so concurrent first requests for the same explanation
# synthesize once instead of firing N identical TTS calls.
_key_locks: dict[str, threading.Lock] = {}
_key_locks_guard = threading.Lock()


def _lock_for(key: str) -> threading.Lock:
    with _key_locks_guard:
        lock = _key_locks.get(key)
        if lock is None:
            lock = threading.Lock()
            _key_locks[key] = lock
        return lock


def sanitize_voice(voice: str | None) -> str | None:
    """Keep the TTS voice a short, safe token (pure — unit tested).

    The value is interpolated into the cache key and forwarded to the TTS
    provider, so overlong/garbage input must never reach either. Returns
    None when no usable voice was supplied (caller falls back to default).
    """
    if voice is None:
        return None
    cleaned = _VOICE_RE.sub("", voice.strip())[:64].strip()
    return cleaned or None


def _voice_used(voice: str | None) -> str:
    from sahlha.app.config import settings

    return sanitize_voice(voice) or os.getenv("GROQ_TTS_VOICE", settings.groq_tts_voice)


def _speech_speed() -> float:
    from sahlha.app.config import settings

    try:
        return float(settings.groq_tts_speed or 1.0)
    except Exception:
        return 1.0


def normalized_speech(text: str) -> str:
    """Speakable text for cache keys + provider calls (idempotent)."""
    try:
        from sahlha.app.audio import speech as _speech

        out = _speech.normalize_for_speech(text or "")
        if out:
            return out
    except Exception:
        pass
    return (text or "").strip()


def _cache_digest(normalized: str, voice_used: str) -> str:
    """v3 digest: normalized speech + provider models + voice + speed + format/rate.

    Keyed by *speakable* text (not raw markdown) so a formatting edit that
    does not change speech reuses audio, while any voice/model/speed change
    correctly misses. The digest intentionally excludes the container so wav
    and mp3 share one hash — callers probe both.

    v3 adds the OpenRouter container + PCM sample rate: audio cached while
    44100 Hz Fish PCM was mislabeled as 24000 Hz (deep + slow) must NOT be
    reused once the format/rate fix lands.
    """
    from sahlha.app.config import settings

    import os as _os

    speed = _speech_speed()
    tts_format = (_os.getenv("OPENROUTER_TTS_FORMAT", settings.openrouter_tts_format) or "mp3").lower()
    try:
        tts_rate = str(int(_os.getenv("OPENROUTER_TTS_SAMPLE_RATE", str(settings.openrouter_tts_sample_rate))))
    except Exception:
        tts_rate = str(settings.openrouter_tts_sample_rate)
    base = f"v3|{settings.groq_tts_model}|{settings.openrouter_tts_model}|{voice_used}|{speed}|{tts_format}|{tts_rate}|{normalized}"
    return hashlib.sha1(base.encode()).hexdigest()[:16]


def _legacy_digest(text: str, voice_used: str) -> str:
    from sahlha.app.config import settings

    return hashlib.sha1(f"{settings.groq_tts_model}|{voice_used}|{text}".encode()).hexdigest()[:16]


def expected_path(text: str, voice: str | None = None, ext: str = "wav") -> str:
    """Deterministic cache path for a text (lets callers check has_audio w/o synth).

    ext selects the container ("wav" default for backward compat, "mp3" for the
    OpenRouter fallback). The digest intentionally excludes ext so both
    containers share one hash — _cached_or_synth probes both.
    """
    from sahlha.app.config import settings

    v = _voice_used(voice)
    digest = _cache_digest(normalized_speech(text), v)
    ext = (ext or "wav").lstrip(".").lower() or "wav"
    if ext not in ("wav", "mp3"):
        ext = "wav"
    return os.path.join(settings.audio_dir, f"{digest}.{ext}")


def _cache_candidates(text: str, voice: str | None) -> list[str]:
    """Both possible cache files for one text (wav + mp3 share the digest)."""
    from sahlha.app.config import settings

    v = _voice_used(voice)
    normalized = normalized_speech(text)
    digest = _cache_digest(normalized, v)
    candidates = [
        os.path.join(settings.audio_dir, f"{digest}.wav"),
        os.path.join(settings.audio_dir, f"{digest}.mp3"),
    ]
    # Backward compat: reuse audio cached under the pre-normalization key so
    # existing deployments do not regenerate everything after the upgrade.
    legacy = _legacy_digest(text, v)
    if legacy != digest:
        candidates.append(os.path.join(settings.audio_dir, f"{legacy}.wav"))
        candidates.append(os.path.join(settings.audio_dir, f"{legacy}.mp3"))
    # Legacy callers sometimes pass already-normalized speech while the cache
    # holds the raw-text digest (and vice versa): probe both normalizations.
    if normalized != (text or "").strip():
        legacy_norm = _legacy_digest(normalized, v)
        for d in (legacy_norm,):
            if d not in (digest, legacy):
                candidates.append(os.path.join(settings.audio_dir, f"{d}.wav"))
                candidates.append(os.path.join(settings.audio_dir, f"{d}.mp3"))
    return candidates


def has_cached_audio(text: str, voice: str | None = None) -> bool:
    """True when either container is cached (honest has_audio flag)."""
    return any(os.path.exists(p) for p in _cache_candidates(text, voice))


def skill_audio_text(name: str, explanation: str) -> str:
    return f"{name}. {explanation}"


def _repair_cached_file(path: str) -> str:
    """Repair a cached audio file in place; returns the (possibly moved) path.

    - A `.wav` file holding MP3 bytes (old OpenRouter cache) is renamed to `.mp3`.
    - A WAV with placeholder streaming sizes is re-encoded with a clean header.
    Repairs are best-effort: failures return the original path untouched.
    """
    try:
        if not os.path.exists(path):
            return path
        with open(path, "rb") as fh:
            data = fh.read()
        if not data:
            return path
        # Mislabeled MP3 → move to the .mp3 sibling so MIME/extension agree.
        if path.lower().endswith(".wav") and tts.sniff_audio_format(data) == "mp3":
            mp3_path = path[:-4] + ".mp3"
            try:
                if os.path.exists(mp3_path):
                    os.remove(path)
                else:
                    os.replace(path, mp3_path)
                return mp3_path
            except OSError:
                return path
        # Broken WAV header → normalize in place.
        if path.lower().endswith(".wav") and tts.is_broken_wav(data):
            try:
                fixed = tts.normalize_wav(data)
                if fixed != data:
                    with open(path, "wb") as fh:
                        fh.write(fixed)
            except Exception:
                pass
            return path
    except Exception:
        pass
    return path


def _sniff_path_media(path: str) -> tuple[str, str]:
    """(extension_format, mime) for a cache file, sniffed from bytes."""
    try:
        with open(path, "rb") as fh:
            head = fh.read(16)
        fmt = tts.sniff_audio_format(head)
    except Exception:
        fmt = "unknown"
    if fmt == "mp3":
        return "mp3", "audio/mpeg"
    return "wav", "audio/wav"


def _cached_or_synth_with_metrics(
    text: str, voice: str | None
) -> tuple[str, str, bool, dict]:
    """Cache lookup + synthesis with latency metrics (no sensitive text logged)."""
    from sahlha.app.config import settings

    os.makedirs(settings.audio_dir, exist_ok=True)
    voice = sanitize_voice(voice)
    voice_used = _voice_used(voice)
    speech_text = normalized_speech(text)
    if not speech_text:
        raise ValueError("Nothing to synthesize: empty text")
    digest = _cache_digest(speech_text, voice_used)
    lock = _lock_for(f"{digest}")
    wall_start = time.perf_counter()
    metrics: dict = {"cache": "miss", "chars": len(speech_text)}
    def _usable_hit(candidate: str) -> str | None:
        """Repaired + validated cache file, or None (corrupt files are dropped)."""
        fixed = _repair_cached_file(candidate)
        target = fixed if os.path.exists(fixed) else (candidate if os.path.exists(candidate) else None)
        if target is None:
            return None
        try:
            if valid_audio_file(target):
                return target
        except Exception:
            return None
        # Corrupt cache (e.g. truncated write, error page): drop it so this
        # request re-synthesizes instead of serving broken audio forever.
        try:
            os.remove(target)
        except OSError:
            pass
        logger.info("tts corrupt cache dropped hash=%s file=%s", digest[:8],
                    os.path.basename(target))
        return None

    with lock:
        # Serve from either container; also self-heal old mislabeled/broken files.
        for candidate in _cache_candidates(text, voice_used):
            if os.path.exists(candidate):
                hit = _usable_hit(candidate)
                if hit is not None:
                    metrics.update({"cache": "hit", "total_ms": round((time.perf_counter() - wall_start) * 1000.0, 2)})
                    return hit, voice_used, True, metrics
                # Repair may have moved .wav → .mp3; re-probe the siblings.
                for sibling in _cache_candidates(text, voice_used):
                    if os.path.exists(sibling):
                        hit = _usable_hit(sibling)
                        if hit is not None:
                            metrics.update({"cache": "hit", "total_ms": round((time.perf_counter() - wall_start) * 1000.0, 2)})
                            return hit, voice_used, True, metrics
        synth_start = time.perf_counter()
        try:
            # Honor monkeypatched `tts.synthesize` in tests; use the metrics
            # variant only for the real provider path.
            synth_fn = tts.synthesize
            if (getattr(synth_fn, "__name__", "") == "synthesize"
                    and "sahlha.app.audio.tts" in getattr(synth_fn, "__module__", "")
                    and hasattr(tts, "synthesize_with_metrics")):
                wav, synth_voice, synth_metrics = tts.synthesize_with_metrics(speech_text, voice)
            else:
                wav, synth_voice = synth_fn(speech_text, voice)
                synth_metrics = {"tts_request_ms": round((time.perf_counter() - synth_start) * 1000.0, 2)}
        except (ValueError, RuntimeError):
            raise
        except Exception as exc:
            # Never leak provider internals/secrets to clients — calm 503 downstream.
            logger.warning("TTS synthesis failed: %s", type(exc).__name__)
            raise RuntimeError("Audio is unavailable right now.") from exc
        metrics.update({k: v for k, v in (synth_metrics or {}).items() if k != "cache"})
        try:
            fmt = tts.sniff_audio_format(wav)
        except Exception:
            fmt = "wav"
        ext = "mp3" if fmt == "mp3" else "wav"
        # Normalize fresh WAVs so cached files are always browser-playable.
        if ext == "wav":
            try:
                wav = tts.normalize_wav(wav)
            except Exception:
                pass
            try:
                if hasattr(tts, "valid_wav") and not tts.valid_wav(wav):
                    raise RuntimeError("Audio is unavailable right now.")
            except RuntimeError:
                raise
            except Exception:
                pass
        else:
            if len(wav) < 128:
                raise RuntimeError("Audio is unavailable right now.")
        path = expected_path(text, voice_used, ext)
        # Re-check after synthesis: concurrent request may have populated cache.
        if os.path.exists(path):
            metrics.update({"cache": "hit", "duplicate_request": True,
                            "total_ms": round((time.perf_counter() - wall_start) * 1000.0, 2)})
            logger.info("tts cache race dedup hash=%s ext=%s", digest[:8], ext)
            return path, synth_voice, True, metrics
        import tempfile as _tf
        fd, tmp_path = _tf.mkstemp(dir=settings.audio_dir, suffix=f".{ext}.part")
        try:
            with os.fdopen(fd, "wb") as fh:
                fh.write(wav)
            os.replace(tmp_path, path)
        except BaseException:
            try:
                os.unlink(tmp_path)
            except OSError:
                pass
            raise
        metrics.update({"cache": "miss",
                        "total_ms": round((time.perf_counter() - wall_start) * 1000.0, 2)})
        try:
            logger.info("tts synth hash=%s chars=%d chunks=%s provider=%s prepare_ms=%s tts_ms=%s total_ms=%s",
                        digest[:8], metrics.get("chars"), metrics.get("chunks"),
                        metrics.get("provider"), metrics.get("speech_prepare_ms"),
                        metrics.get("tts_request_ms"), metrics.get("total_ms"))
        except Exception:
            pass
        return path, synth_voice, False, metrics


def _cached_or_synth(text: str, voice: str | None) -> tuple[str, str, bool]:
    path, voice_used, cached, _ = _cached_or_synth_with_metrics(text, voice)
    return path, voice_used, cached


def _audio_result(path: str, voice_used: str, cached: bool, extra: dict) -> dict:
    fmt, mime = _sniff_path_media(path)
    stem = os.path.basename(path)
    for suffix in (".wav", ".mp3"):
        if stem.lower().endswith(suffix):
            stem = stem[: -len(suffix)]
            break
    return {"audio_id": stem, "path": path, "format": fmt, "media_type": mime,
            "voice": voice_used, "cached": cached, **extra}


def skill_explanation_to_audio(db: Session, *, course_id: str, lesson_id: str,
                               skill_id: str, voice: str | None = None) -> dict:
    """Speech audio for one skill's agent-written explanation.

    Only finalized student-facing explanations reach TTS (callers raise when
    the explanation is missing). The raw text is normalized deterministically
    before cache lookup + synthesis so markdown/code never reach the voice.
    """
    from sahlha.app.audio import speech as _speech

    skill = repo.get_skill(db, course_id=course_id, lesson_id=lesson_id, skill_id=skill_id)
    if skill is None:
        raise ValueError(f"Skill {skill_id} not found in {course_id}/{lesson_id}")
    if not skill.explanation:
        raise ValueError(f"Skill {skill_id} has no explanation yet — run extract-skills first")
    raw_text = skill_audio_text(skill.name, skill.explanation)
    speech_text = _speech.build_skill_speech(skill.name or "", skill.explanation or "")
    if not speech_text:
        raise ValueError(f"Skill {skill_id} has no speakable explanation")
    path, voice_used, cached, metrics = _cached_or_synth_with_metrics(speech_text, voice)
    try:
        repo.set_media(db, skill, audio_path=path)
    except Exception:
        pass
    result = _audio_result(path, voice_used, cached,
                           {"skill_id": skill_id, "chars": len(speech_text)})
    result["metrics"] = metrics
    # Keep the raw length honest for callers that budget by explanation size.
    result["raw_chars"] = len(raw_text)
    return result


def lesson_explanation_to_audio(db: Session, *, course_id: str, lesson_id: str,
                                voice: str | None = None) -> dict:
    """Speech audio for the whole-lesson overview explanation."""
    from sahlha.app.audio import speech as _speech

    row = repo.get_lesson_explanation(db, course_id=course_id, lesson_id=lesson_id)
    if row is None or not row.explanation:
        raise ValueError(f"Lesson {course_id}/{lesson_id} has no explanation yet — run explain-lesson first")
    raw_text = f"{row.title}. {row.explanation}" if row.title else row.explanation
    speech_text = _speech.build_lesson_speech(row.title or "", row.explanation or "")
    if not speech_text:
        raise ValueError(f"Lesson {course_id}/{lesson_id} has no speakable explanation")
    path, voice_used, cached, metrics = _cached_or_synth_with_metrics(speech_text, voice)
    try:
        repo.set_media(db, row, audio_path=path)
    except Exception:
        pass
    result = _audio_result(path, voice_used, cached,
                           {"lesson_id": lesson_id, "chars": len(speech_text)})
    result["metrics"] = metrics
    result["raw_chars"] = len(raw_text)
    return result


def prefetch_next_skill_audio(db: Session, *, course_id: str, lesson_id: str,
                              current_skill_id: str, voice: str | None = None) -> bool:
    """Best-effort background warm of the likely-next skill's audio.

    Only runs for finalized explanations (missing/draft content is skipped, so
    rejected banks and intermediate outputs never spend TTS budget). Never
    raises: prefetch must never break the current request.
    """
    try:
        skills = repo.list_skills(db, course_id=course_id, lesson_id=lesson_id)
        ids = [s.skill_id for s in skills]
        if current_skill_id not in ids:
            return False
        nxt = ids[ids.index(current_skill_id) + 1] if ids.index(current_skill_id) + 1 < len(ids) else None
        if not nxt:
            return False
        nxt_row = repo.get_skill(db, course_id=course_id, lesson_id=lesson_id, skill_id=nxt)
        if nxt_row is None or not (nxt_row.explanation or "").strip():
            return False
        from sahlha.app.audio import speech as _speech

        speech_text = _speech.build_skill_speech(nxt_row.name or "", nxt_row.explanation or "")
        if not speech_text or has_cached_audio(speech_text, voice):
            return True
        # Only prefetch modest sizes: huge lessons stay on-demand (cost guard).
        if len(speech_text) > 6000:
            return False
        _cached_or_synth(speech_text, voice)
        return True
    except Exception:
        return False


def valid_audio_file(path: str) -> bool:
    """True for playable WAV *or* MP3 cache files (sniffed, not by extension)."""
    import wave
    if not path:
        return False
    try:
        if not os.path.exists(path):
            return False
        if os.path.getsize(path) < 128:
            return False
        with open(path, "rb") as fh:
            head = fh.read(16)
        fmt = tts.sniff_audio_format(head)
        if fmt == "mp3":
            return True
        if fmt != "wav":
            # Unknown container: fall back to extension for very short headers.
            if not path.lower().endswith((".wav", ".mp3")):
                return False
            if path.lower().endswith(".mp3"):
                return True
        with wave.open(path, "rb") as stream:
            return stream.getnframes() > 0 and bool(stream.readframes(1))
    except (OSError, EOFError, wave.Error, AttributeError, ValueError):
        return False


def _envelope_for_speech(speech_text: str, voice: str | None) -> dict:
    """Lip-sync envelope for speakable text (cached ``<digest>.env.json``).

    Ensures the speech audio exists first (synthesizing on miss), so envelope
    errors match the audio endpoint: missing/unplayable audio raises the same
    ValueError/RuntimeError callers already map to 404/503. Returns
    ``{"levels": [...], "kind": "energy"|"timed", "cached": bool}``.
    """
    import json

    from sahlha.app.audio import envelope as _envelope
    from sahlha.app.config import settings

    os.makedirs(settings.audio_dir, exist_ok=True)
    voice_used = _voice_used(sanitize_voice(voice))
    digest = _cache_digest(normalized_speech(speech_text), voice_used)
    lock = _lock_for(f"{digest}|env")
    with lock:
        path = os.path.join(settings.audio_dir, f"{digest}.env.json")
        if os.path.exists(path):
            try:
                with open(path, "r", encoding="utf-8") as fh:
                    payload = json.load(fh)
                if _envelope.valid_envelope_payload(payload):
                    return {"levels": payload["levels"], "kind": payload["kind"],
                            "cached": True}
            except Exception:
                pass
            try:
                os.remove(path)
            except OSError:
                pass
        # Same audio the student hears (synthesizes on cache miss).
        audio_path, _, _ = _cached_or_synth(speech_text, voice)
        try:
            levels, kind = _envelope.levels_for_audio_file(audio_path, speech_text)
            payload = _envelope.envelope_payload(levels, kind)
        except Exception:
            payload = _envelope.envelope_payload(
                _envelope.timed_levels_for_text(""), "timed")
        fd, tmp_path = tempfile.mkstemp(dir=settings.audio_dir, suffix=".env.json.part")
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as fh:
                json.dump(payload, fh)
            os.replace(tmp_path, path)
        except BaseException:
            try:
                os.unlink(tmp_path)
            except OSError:
                pass
            raise
        return {"levels": payload["levels"], "kind": payload["kind"], "cached": False}


def skill_envelope(db: Session, *, course_id: str, lesson_id: str,
                   skill_id: str, voice: str | None = None) -> dict:
    """Lip-sync envelope for one skill's finalized explanation.

    Same text, voice and errors as :func:`skill_explanation_to_audio`: only
    finalized student-facing explanations reach the envelope, missing content
    raises ValueError and TTS failure raises RuntimeError.
    """
    from sahlha.app.audio import speech as _speech

    skill = repo.get_skill(db, course_id=course_id, lesson_id=lesson_id, skill_id=skill_id)
    if skill is None:
        raise ValueError(f"Skill {skill_id} not found in {course_id}/{lesson_id}")
    if not skill.explanation:
        raise ValueError(f"Skill {skill_id} has no explanation yet — run extract-skills first")
    speech_text = _speech.build_skill_speech(skill.name or "", skill.explanation or "")
    if not speech_text:
        raise ValueError(f"Skill {skill_id} has no speakable explanation")
    return _envelope_for_speech(speech_text, voice)


def lesson_envelope(db: Session, *, course_id: str, lesson_id: str,
                    voice: str | None = None) -> dict:
    """Lip-sync envelope for the whole-lesson overview explanation."""
    from sahlha.app.audio import speech as _speech

    row = repo.get_lesson_explanation(db, course_id=course_id, lesson_id=lesson_id)
    if row is None or not row.explanation:
        raise ValueError(f"Lesson {course_id}/{lesson_id} has no explanation yet — run explain-lesson first")
    speech_text = _speech.build_lesson_speech(row.title or "", row.explanation or "")
    if not speech_text:
        raise ValueError(f"Lesson {course_id}/{lesson_id} has no speakable explanation")
    return _envelope_for_speech(speech_text, voice)
