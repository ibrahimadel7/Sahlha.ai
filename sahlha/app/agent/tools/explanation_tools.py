"""Explanation tools — persist explanations, then fan out to media tools.

Chain: explanation tool -> audio tool (+ image tool for skills).
Media failures are recorded as skipped and NEVER fail the explanation.
"""
from __future__ import annotations

from sqlalchemy.orm import Session

from sahlha.app.agent.tools import audio_tools, image_tools
from sahlha.app.database.repositories import repositories as repo


def _deferred_media() -> dict:
    """Placeholder shape when media generation is deferred (filled lazily on demand)."""
    reason = "deferred — generated on demand via /audio + /images endpoints"
    return {"image": {"status": "skipped", "reason": reason},
            "audio": {"status": "skipped", "reason": reason}}


def explain_skill(db: Session, *, course_id: str, lesson_id: str,
                  skill_id: str, explanation_text: str, include_media: bool = True) -> dict:
    """Persist one skill's explanation, then call audio + image tools for it.

    With include_media=False the explanation is persisted immediately and media is
    left for lazy on-demand generation (fast path for bulk flows like extract-skills).
    """
    skill = repo.get_skill(db, course_id=course_id, lesson_id=lesson_id, skill_id=skill_id)
    if skill is None:
        raise ValueError(f"Skill {skill_id} not found in {course_id}/{lesson_id}")
    repo.set_skill_explanation(db, skill, explanation_text)
    if not include_media:
        return {"skill_id": skill_id, "explanation": explanation_text,
                "media": _deferred_media()}
    return {"skill_id": skill_id, "explanation": explanation_text,
            "media": ensure_skill_media(db, course_id=course_id, lesson_id=lesson_id,
                                        skill_id=skill_id)}


def ensure_skill_media(db: Session, *, course_id: str, lesson_id: str,
                       skill_id: str) -> dict:
    """Call image + audio tools for an already-explained skill (idempotent)."""
    media: dict = {"image": {"status": "skipped"}, "audio": {"status": "skipped"}}
    try:
        res = image_tools.fetch_skill_image(db, course_id=course_id,
                                            lesson_id=lesson_id, skill_id=skill_id)
        media["image"] = {"status": "cached" if res["cached"] else "generated",
                          "source_url": res.get("source_url", "")}
    except Exception as exc:
        media["image"] = {"status": "skipped", "reason": str(exc)[:500]}
    try:
        res = audio_tools.skill_explanation_to_audio(db, course_id=course_id,
                                                     lesson_id=lesson_id, skill_id=skill_id)
        media["audio"] = {"status": "cached" if res["cached"] else "generated",
                          "voice": res.get("voice", "")}
    except Exception as exc:
        # Full chain: Groq 429 → OpenRouter attempt → combined error (was truncated at 160)
        media["audio"] = {"status": "skipped", "reason": str(exc)[:500]}
    return media


def explain_lesson(db: Session, *, course_id: str, lesson_id: str, title: str = "",
                   explanation_text: str = "", key_concepts: list | None = None,
                   include_media: bool = True) -> dict:
    """Persist the lesson overview, then call the audio tool for it.

    With include_media=False the overview is persisted immediately and audio is
    left for lazy on-demand generation (fast path for bulk flows like extract-skills).
    """
    row = repo.upsert_lesson_explanation(db, course_id=course_id, lesson_id=lesson_id,
                                         title=title, explanation=explanation_text,
                                         key_concepts=key_concepts)
    lesson = {"id": row.id, "course_id": row.course_id, "lesson_id": row.lesson_id,
              "title": row.title, "explanation": row.explanation,
              "key_concepts": row.key_concepts or []}
    if not include_media:
        return {"lesson_id": lesson_id,
                "media": {"audio": {"status": "skipped",
                                    "reason": "deferred — generated on demand via /audio endpoint"}},
                "lesson": lesson}
    try:
        res = audio_tools.lesson_explanation_to_audio(db, course_id=course_id,
                                                      lesson_id=lesson_id)
        media = {"audio": {"status": "cached" if res["cached"] else "generated",
                           "voice": res.get("voice", "")}}
    except Exception as exc:
        media = {"audio": {"status": "skipped", "reason": str(exc)[:500]}}
    return {"lesson_id": lesson_id, "media": media, "lesson": lesson}


def ensure_lesson_media(db: Session, *, course_id: str, lesson_id: str) -> dict:
    """(Re)generate missing audio for an explained lesson (idempotent)."""
    try:
        res = audio_tools.lesson_explanation_to_audio(db, course_id=course_id,
                                                      lesson_id=lesson_id)
        return {"audio": {"status": "cached" if res["cached"] else "generated",
                          "voice": res.get("voice", "")}}
    except Exception as exc:
        return {"audio": {"status": "skipped", "reason": str(exc)[:500]}}
