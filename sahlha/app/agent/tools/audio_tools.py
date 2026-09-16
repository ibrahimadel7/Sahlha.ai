"""Audio tools — the ONLY way the agent turns explanations into speech.

Tools resolve the explanation text from the DB, synthesize via the TTS provider,
and cache the WAV on disk keyed by content hash. The LLM never touches audio bytes.
"""
from __future__ import annotations

import hashlib
import os

from sqlalchemy.orm import Session

from sahlha.app.audio import tts
from sahlha.app.database.repositories import repositories as repo


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
    wav, synth_voice = tts.synthesize(text, voice)
    fmt = tts.sniff_audio_format(wav)
    ext = "mp3" if fmt == "mp3" else "wav"
    # Normalize fresh WAVs so cached files are always browser-playable.
    if ext == "wav":
        try:
            wav = tts.normalize_wav(wav)
        except Exception:
            pass
    path = expected_path(text, voice_used, ext)
    with open(path, "wb") as fh:
        fh.write(wav)
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
    return _audio_result(path, voice_used, cached,
                         {"lesson_id": lesson_id, "chars": len(text)})
