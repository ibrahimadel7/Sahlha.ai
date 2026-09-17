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

from sqlalchemy.orm import Session

from sahlha.app.audio import tts
from sahlha.app.database.repositories import repositories as repo

logger = logging.getLogger(__name__)

_VOICE_RE = re.compile(r"[^A-Za-z0-9 _-]")


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

    return voice or os.getenv("GROQ_TTS_VOICE", settings.groq_tts_voice)


def expected_path(text: str, voice: str | None = None, ext: str = "wav") -> str:
    """Deterministic cache path for a text (lets callers check has_audio w/o synth).

    ext selects the container ("wav" default for backward compat, "mp3" for the
    OpenRouter fallback). The digest intentionally excludes ext so both
    containers share one hash — _cached_or_synth probes both.
    """
    from sahlha.app.config import settings

    v = _voice_used(voice)
    digest = hashlib.sha1(f"{settings.groq_tts_model}|{v}|{text}".encode()).hexdigest()[:16]
    ext = (ext or "wav").lstrip(".").lower() or "wav"
    if ext not in ("wav", "mp3"):
        ext = "wav"
    return os.path.join(settings.audio_dir, f"{digest}.{ext}")


def _cache_candidates(text: str, voice: str | None) -> list[str]:
    """Both possible cache files for one text (wav + mp3 share the digest)."""
    return [expected_path(text, voice, "wav"), expected_path(text, voice, "mp3")]


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


def _cached_or_synth(text: str, voice: str | None) -> tuple[str, str, bool]:
    from sahlha.app.config import settings

    os.makedirs(settings.audio_dir, exist_ok=True)
    voice_used = _voice_used(voice)
    # Serve from either container; also self-heal old mislabeled/broken files.
    for candidate in _cache_candidates(text, voice_used):
        if os.path.exists(candidate):
            fixed = _repair_cached_file(candidate)
            # Repair may have moved .wav → .mp3; re-probe the other candidate too.
            if fixed != candidate and os.path.exists(fixed):
                return fixed, voice_used, True
            if os.path.exists(candidate):
                return candidate, voice_used, True
            # Fall through: the file was moved — check the sibling below.
            for sibling in _cache_candidates(text, voice_used):
                if os.path.exists(sibling):
                    return _repair_cached_file(sibling), voice_used, True
    try:
        wav, synth_voice = tts.synthesize(text, voice)
    except (ValueError, RuntimeError):
        raise
    except Exception as exc:
        # Never leak provider internals/secrets to clients — calm 503 downstream.
        logger.warning("TTS synthesis failed: %s", type(exc).__name__)
        raise RuntimeError("Audio is unavailable right now.") from exc
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
    path = expected_path(text, voice_used, ext)
    # Re-check after synthesis: concurrent request may have populated cache.
    if os.path.exists(path):
        return path, synth_voice, True
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
    return path, synth_voice, False


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
    """Speech audio for one skill's agent-written explanation."""
    skill = repo.get_skill(db, course_id=course_id, lesson_id=lesson_id, skill_id=skill_id)
    if skill is None:
        raise ValueError(f"Skill {skill_id} not found in {course_id}/{lesson_id}")
    if not skill.explanation:
        raise ValueError(f"Skill {skill_id} has no explanation yet — run extract-skills first")
    text = skill_audio_text(skill.name, skill.explanation)
    path, voice_used, cached = _cached_or_synth(text, voice)
    try:
        repo.set_media(db, skill, audio_path=path)
    except Exception:
        pass
    return _audio_result(path, voice_used, cached,
                         {"skill_id": skill_id, "chars": len(text)})


def lesson_explanation_to_audio(db: Session, *, course_id: str, lesson_id: str,
                                voice: str | None = None) -> dict:
    """Speech audio for the whole-lesson overview explanation."""
    row = repo.get_lesson_explanation(db, course_id=course_id, lesson_id=lesson_id)
    if row is None or not row.explanation:
        raise ValueError(f"Lesson {course_id}/{lesson_id} has no explanation yet — run explain-lesson first")
    text = f"{row.title}. {row.explanation}" if row.title else row.explanation
    path, voice_used, cached = _cached_or_synth(text, voice)
    try:
        repo.set_media(db, row, audio_path=path)
    except Exception:
        pass
    return _audio_result(path, voice_used, cached,
                         {"lesson_id": lesson_id, "chars": len(text)})


def valid_audio_file(path: str) -> bool:
    import wave
    try:
        with wave.open(path, "rb") as stream:
            return stream.getnframes() > 0 and bool(stream.readframes(1))
    except (OSError, EOFError, wave.Error, AttributeError):
        return False
