"""Image tools — the ONLY way the agent attaches pictures to skills.

Full context chain (no extra LLM call — the agent already persisted everything):

    Full lesson (RAG chunks + lesson overview)
        -> lesson classified ONCE into a broad category (persisted on the lesson row)
        -> generated skill (name/description/concepts/explanation)
        -> category-aware visual concept -> photo query -> provider fetch.

The tool loads the lesson's STORED category (written by the agent right after
RAG retrieval) plus the lesson context (overview row + RAG chunks) and the
skill context, and hands the combined context to
``pexels.build_image_query``. The query therefore depicts the SKILL as
understood WITHIN the lesson's category (e.g. "python" the language vs the
snake), instead of reducing the skill to a bare title keyword.
The LLM never touches image bytes or API keys.
"""
from __future__ import annotations

import hashlib
import logging
import os

from sqlalchemy.orm import Session

from sahlha.app.database.repositories import repositories as repo
from sahlha.app.images import pexels
from sahlha.app.lesson_categories import classify_lesson, get as get_category


def _lesson_context(db: Session, *, course_id: str, lesson_id: str) -> dict:
    """Collect the lesson side of the image context (best-effort, never raises).

    Provides: the stored lesson category record (classifed once by the agent;
    computed on the fly ONLY for legacy rows that predate classification, then
    persisted so it is still once-per-lesson), lesson title/subject, lesson
    key concepts, lesson overview explanation, and a short excerpt of the
    retrieved lesson content (RAG chunks). The query builder uses the
    category anchor + title/concepts as the domain qualifier and ignores
    incidental nouns in the body text.
    """
    ctx: dict = {"course_id": course_id, "lesson_id": lesson_id,
                 "lesson_category": {"category_id": "other", "label": "Other",
                                     "anchor": ""},
                 "lesson_title": "", "lesson_key_concepts": [],
                 "lesson_explanation": "", "lesson_text": ""}
    try:
        row = repo.get_lesson_explanation(db, course_id=course_id, lesson_id=lesson_id)
        if row is not None:
            ctx["lesson_title"] = row.title or ""
            ctx["lesson_key_concepts"] = list(row.key_concepts or [])
            ctx["lesson_explanation"] = (row.explanation or "")[:2000]
            stored = (getattr(row, "category", "") or "").strip()
            if stored:
                rec = get_category(stored)
                ctx["lesson_category"] = {"category_id": rec["id"],
                                          "label": rec["label"],
                                          "anchor": rec["anchor"]}
    except Exception:
        pass
    try:
        chunks = repo.get_chunks(db, course_id=course_id, lesson_id=lesson_id)
        texts = [c.text for c in (chunks or []) if getattr(c, "text", "")]
        ctx["lesson_text"] = " ".join(texts)[:2000]
    except Exception:
        pass
    if ctx["lesson_category"]["category_id"] == "other" and (
            ctx["lesson_text"] or ctx["lesson_title"] or ctx["lesson_key_concepts"]):
        # Legacy row (or image requested before extraction finished): classify
        # from the same lesson context with the same pure function, then
        # persist it so later skills read the stored value.
        try:
            rec = classify_lesson(lesson_id=lesson_id, course_id=course_id,
                                  text=ctx["lesson_text"], title=ctx["lesson_title"],
                                  key_concepts=ctx["lesson_key_concepts"])
            ctx["lesson_category"] = {"category_id": rec["category_id"],
                                      "label": rec["label"], "anchor": rec["anchor"]}
            try:
                repo.upsert_lesson_explanation(db, course_id=course_id,
                                               lesson_id=lesson_id,
                                               category=rec["category_id"])
            except Exception:
                pass
        except Exception:
            pass
    return ctx

logger = logging.getLogger(__name__)


def fetch_skill_image(db: Session, *, course_id: str, lesson_id: str,
                      skill_id: str, force: bool = False) -> dict:
    """Fetch (or return cached) one related image for a skill. Raises on failure.

    Category-aware: the photo query is built from the lesson's persisted
    category (the contextual guardrail) + lesson topic combined with the
    skill context (name, description, explanation, key concepts, learning
    objective, RAG evidence) — never from the skill title alone.
    """
    from sahlha.app.config import settings

    skill = repo.get_skill(db, course_id=course_id, lesson_id=lesson_id, skill_id=skill_id)
    if skill is None:
        raise ValueError(f"Skill {skill_id} not found in {course_id}/{lesson_id}")
    return _fetch_for_row(db, skill, force=force)


def _fetch_for_row(db, skill, force=False):
    from sahlha.app.config import settings
    skill_id = getattr(skill, "skill_id", skill.lesson_id)
    course_id = getattr(skill, "course_id", "general") or "general"
    lesson_id = getattr(skill, "lesson_id", "lesson_1") or "lesson_1"
    if valid_image_file(skill.image_path) and not force:
        return {"skill_id": skill_id, "path": skill.image_path, "source_url": skill.image_url,
                "alt": skill.image_alt, "cached": True}
    lesson_ctx = _lesson_context(db, course_id=course_id, lesson_id=lesson_id)
    query = pexels.build_image_query({
        # Skill side: what the picture must depict.
        "name": skill.name, "skill_id": skill.skill_id,
        "key_concepts": skill.key_concepts or [],
        "description": skill.description or "",
        "explanation": (skill.explanation or "")[:2000],
        "learning_objective": getattr(skill, "learning_objective", "") or "",
        "source_evidence": list(getattr(skill, "source_evidence", None) or []),
        # Lesson side (incl. "lesson_category" record): the persisted
        # category + topic needed to understand the skill.
        **lesson_ctx,
    })
    try:
        found = pexels.fetch_related_image(query)
    except (ValueError, RuntimeError):
        raise
    except Exception as exc:
        # Network/provider failures must degrade to a calm 503, never a 500.
        logger.warning("Image fetch failed: %s", type(exc).__name__)
        raise RuntimeError("No picture is available right now.") from exc
    os.makedirs(settings.image_dir, exist_ok=True)
    digest = hashlib.sha1(found["bytes"]).hexdigest()[:16]
    path = os.path.join(settings.image_dir, f"{digest}.jpg".replace("/", "_"))
    # Atomic write so a concurrent reader never sees a half-written JPEG.
    import tempfile

    fd, tmp_path = tempfile.mkstemp(dir=settings.image_dir, suffix=".jpg.part")
    try:
        with os.fdopen(fd, "wb") as fh:
            fh.write(found["bytes"])
        os.replace(tmp_path, path)
    except BaseException:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise
    repo.set_media(db, skill, image_url=found["page_url"], image_path=path, image_alt=found["alt"])
    return {"skill_id": skill_id, "path": path, "source_url": found["page_url"],
            "alt": found["alt"], "photographer": found["photographer"],
            "query": query, "cached": False}


def valid_image_file(path):
    try:
        return bool(path and os.path.isfile(path) and os.path.getsize(path) >= 1024)
    except OSError:
        return False


def fetch_lesson_image(db, *, course_id, lesson_id, force=False):
    row = repo.get_lesson_explanation(db, course_id=course_id, lesson_id=lesson_id)
    if row is None:
        raise ValueError("Lesson explanation not found")
    return _fetch_for_row(db, row, force)
