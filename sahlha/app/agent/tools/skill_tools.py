"""Skill tools — the agent builds skills only through here.

Chain: skill tool -> explanation tool -> audio/image tools.
The agent generates the *content* (skill split, explanation text); this layer owns
persistence and fans out to the explanation tool, which fans out to media tools.
"""
from __future__ import annotations

from sqlalchemy.orm import Session

from sahlha.app.agent.tools import explanation_tools
from sahlha.app.database.repositories import repositories as repo


def register_skill(db: Session, *, course_id: str, lesson_id: str, skill_data: dict) -> dict:
    """Persist one extracted skill (no explanation yet)."""
    row = repo.upsert_skill(db, course_id=course_id, lesson_id=lesson_id,
                            skill_id=skill_data["skill_id"],
                            name=skill_data.get("name", skill_data["skill_id"]),
                            description=skill_data.get("description", ""),
                            key_concepts=skill_data.get("key_concepts", []))
    return _to_dict(row)


def setup_skill(db: Session, *, course_id: str, lesson_id: str,
                skill_id: str, explanation_text: str) -> dict:
    """Attach an explanation to a skill via the explanation tool.

    This is the chain: skill tool -> explanation tool -> audio + image tools.
    Returns the full skill bundle including media statuses.
    """
    res = explanation_tools.explain_skill(db, course_id=course_id, lesson_id=lesson_id,
                                          skill_id=skill_id, explanation_text=explanation_text)
    row = repo.get_skill(db, course_id=course_id, lesson_id=lesson_id, skill_id=skill_id)
    return {**_to_dict(row), "media": res["media"]}


def skill_media(db: Session, *, course_id: str, lesson_id: str, skill_id: str) -> dict:
    """(Re)generate missing media for an explained skill via the explanation tool."""
    return explanation_tools.ensure_skill_media(db, course_id=course_id,
                                                lesson_id=lesson_id, skill_id=skill_id)


def _to_dict(s) -> dict:
    import os as _os

    from sahlha.app.agent.tools import audio_tools as _audio_tools

    has_audio = _os.path.exists(_audio_tools.expected_path(
        _audio_tools.skill_audio_text(s.name or "", s.explanation or "")))
    return {"id": s.id, "course_id": s.course_id, "lesson_id": s.lesson_id,
            "skill_id": s.skill_id, "name": s.name, "description": s.description,
            "explanation": s.explanation, "key_concepts": s.key_concepts or [],
            "has_image": bool(getattr(s, "image_path", "")),
            "image_alt": getattr(s, "image_alt", "") or "",
            "has_audio": has_audio}
