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


def expected_path(text: str, voice: str | None = None) -> str:
    """Deterministic cache path for a text (lets callers check has_audio w/o synth)."""
    from sahlha.app.config import settings

    v = _voice_used(voice)
    digest = hashlib.sha1(f"{settings.groq_tts_model}|{v}|{text}".encode()).hexdigest()[:16]
    return os.path.join(settings.audio_dir, f"{digest}.wav")


def skill_audio_text(name: str, explanation: str) -> str:
    return f"{name}. {explanation}"


def _cached_or_synth(text: str, voice: str | None) -> tuple[str, str, bool]:
    from sahlha.app.config import settings

    os.makedirs(settings.audio_dir, exist_ok=True)
    voice_used = _voice_used(voice)
    path = expected_path(text, voice_used)
    if os.path.exists(path):
        return path, voice_used, True
    wav, voice_used = tts.synthesize(text, voice)
    with open(path, "wb") as fh:
        fh.write(wav)
    return path, voice_used, False


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
    return {"audio_id": os.path.basename(path).replace(".wav", ""), "path": path,
            "skill_id": skill_id, "voice": voice_used, "cached": cached,
            "chars": len(text)}


def lesson_explanation_to_audio(db: Session, *, course_id: str, lesson_id: str,
                                voice: str | None = None) -> dict:
    """Speech audio for the whole-lesson overview explanation."""
    row = repo.get_lesson_explanation(db, course_id=course_id, lesson_id=lesson_id)
    if row is None or not row.explanation:
        raise ValueError(f"Lesson {course_id}/{lesson_id} has no explanation yet — run explain-lesson first")
    text = f"{row.title}. {row.explanation}" if row.title else row.explanation
    path, voice_used, cached = _cached_or_synth(text, voice)
    return {"audio_id": os.path.basename(path).replace(".wav", ""), "path": path,
            "lesson_id": lesson_id, "voice": voice_used, "cached": cached,
            "chars": len(text)}
