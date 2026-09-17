"""Skill tools — the agent builds skills only through here.

Chain: skill tool -> explanation tool -> audio/image tools.
The agent generates the *content* (skill split, explanation text); this layer owns
persistence and fans out to the explanation tool, which fans out to media tools.
"""
from __future__ import annotations

from sqlalchemy.orm import Session

from sahlha.app.agent.tools import explanation_tools
from sahlha.app.database.repositories import repositories as repo


def register_skill(db: Session, *, course_id: str, lesson_id: str, skill_data: dict | None = None,
                   skill: dict | None = None) -> dict:
    """Persist one extracted skill (no explanation yet), including RAG provenance."""
    # Compat: pr-1 callers pass `skill=`, ours pass `skill_data=`.
    data = skill_data if skill_data is not None else (skill or {})
    row = repo.upsert_skill(db, course_id=course_id, lesson_id=lesson_id,
                            skill_id=data["skill_id"],
                            name=data.get("name", data["skill_id"]),
                            description=data.get("description", ""),
                            key_concepts=data.get("key_concepts", []),
                            learning_objective=data.get("learning_objective", ""),
                            source_chunk_ids=data.get("source_chunk_ids", []),
                            source_evidence=data.get("source_evidence", []))
    return _to_dict(row)


def setup_skill(db: Session, *, course_id: str, lesson_id: str,
                skill_id: str, explanation_text: str, include_media: bool = True) -> dict:
    """Attach an explanation to a skill via the explanation tool.

    This is the chain: skill tool -> explanation tool -> audio + image tools.
    With include_media=False the explanation is persisted immediately and media is
    left for lazy on-demand generation (fast path for bulk flows like extract-skills).
    Returns the full skill bundle including media statuses.
    """
    res = explanation_tools.explain_skill(db, course_id=course_id, lesson_id=lesson_id,
                                          skill_id=skill_id, explanation_text=explanation_text,
                                          include_media=include_media)
    row = repo.get_skill(db, course_id=course_id, lesson_id=lesson_id, skill_id=skill_id)
    return {**_to_dict(row), "media": res["media"]}


def skill_media(db: Session, *, course_id: str, lesson_id: str, skill_id: str) -> dict:
    """(Re)generate missing media for an explained skill via the explanation tool."""
    return explanation_tools.ensure_skill_media(db, course_id=course_id,
                                                lesson_id=lesson_id, skill_id=skill_id)


def _to_dict(s) -> dict:
    from sahlha.app.agent.tools import audio_tools as _audio_tools

    # Same probe as services.list_skills: either container (wav/mp3) counts,
    # so the flag agrees no matter which TTS provider synthesized the audio.
    has_audio = _audio_tools.has_cached_audio(
        _audio_tools.skill_audio_text(s.name or "", s.explanation or ""))
    return {"id": s.id, "course_id": s.course_id, "lesson_id": s.lesson_id,
            "skill_id": s.skill_id, "name": s.name, "description": s.description,
            "explanation": s.explanation, "key_concepts": s.key_concepts or [],
            "learning_objective": getattr(s, "learning_objective", "") or "",
            "source_chunk_ids": list(getattr(s, "source_chunk_ids", None) or []),
            "source_evidence": list(getattr(s, "source_evidence", None) or []),
            "has_image": bool(getattr(s, "image_path", "")),
            "image_alt": getattr(s, "image_alt", "") or "",
            "has_audio": has_audio}


def serialize_skill(row) -> dict:
    """Platform compat: superset of _to_dict with pr-1 enrichment fields (defaults)."""
    base = _to_dict(row)
    for k in ("prerequisites", "misconceptions", "difficulty", "source_section_ids",
              "evidence_chunk_ids", "learning_content"):
        base.setdefault(k, getattr(row, k, [] if "ids" in k or k in ("prerequisites", "misconceptions") else ({} if k in ("learning_content",) else "")))
    # pr-1 media validators (valid_*_file) if available, else keep bool flags.
    try:
        from sahlha.app.agent.tools.image_tools import valid_image_file as _vimg
        base["has_image"] = bool(_vimg(getattr(row, "image_path", "") or ""))
    except Exception:
        pass
    try:
        from sahlha.app.agent.tools.audio_tools import valid_audio_file as _vaud
        base["has_audio"] = bool(_vaud(getattr(row, "audio_path", "") or "") or base.get("has_audio"))
    except Exception:
        pass
    return base


def list_skills(db: Session, *, course_id: str, lesson_id: str):
    return repo.list_skills(db, course_id=course_id, lesson_id=lesson_id)


get_skill = repo.get_skill
