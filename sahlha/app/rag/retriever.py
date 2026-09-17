"""Retriever: filtered semantic search returning chunk metadata + text."""
from __future__ import annotations

from sqlalchemy.orm import Session

from sahlha.app.rag import vectorstore


def retrieve(db: Session, query: str, *, top_k: int = 5,
             course_id: str | None = None, lesson_id: str | None = None,
             skill_id: str | None = None) -> list[dict]:
    return vectorstore.search(db, query, top_k=top_k,
                              course_id=course_id, lesson_id=lesson_id, skill_id=skill_id)


def retrieve_lesson(db: Session, course_id: str, lesson_id: str, top_k: int = 5) -> list[dict]:
    results = retrieve(db, f"lesson {lesson_id} course {course_id} overview key concepts",
                    top_k=top_k, course_id=course_id, lesson_id=lesson_id)
    if results:
        return results
    # Overview retrieval is a scoped curriculum read, never a global search.
    from sahlha.app.database.repositories import repositories as repo
    return [{"chunk_id": c.id, "document_id": c.document_id, "course_id": c.course_id,
             "lesson_id": c.lesson_id, "skill_id": c.skill_id, "page": c.page,
             "chunk_index": c.chunk_index, "text": c.text, "score": 0.0}
            for c in repo.get_chunks(db, course_id=course_id, lesson_id=lesson_id)[:top_k]]


def retrieve_skill(db: Session, skill_id: str, top_k: int = 5,
                   course_id: str | None = None, lesson_id: str | None = None) -> list[dict]:
    """Skill-scoped retrieval. When course/lesson are supplied the scope is
    strict (no cross-lesson leakage). The unscoped variant is legacy and
    should be avoided for student-facing selection."""
    return retrieve(db, f"skill {skill_id} definition examples usage",
                    top_k=top_k, course_id=course_id, lesson_id=lesson_id, skill_id=skill_id)
