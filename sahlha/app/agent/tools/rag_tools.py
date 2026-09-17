"""RAG tools — the ONLY way the agent touches retrieval."""
from __future__ import annotations

from sqlalchemy.orm import Session

from sahlha.app.rag import retriever


def retrieve_lesson(db: Session, course_id: str, lesson_id: str, top_k: int = 5) -> list[dict]:
    """Retrieve chunks for a specific lesson."""
    return retriever.retrieve_lesson(db, course_id, lesson_id, top_k=top_k)


def retrieve_skill_material(db: Session, skill_id: str, top_k: int = 5,
                            course_id: str | None = None,
                            lesson_id: str | None = None) -> list[dict]:
    """Retrieve chunks for a specific skill (scoped when course/lesson given)."""
    return retriever.retrieve_skill(db, skill_id, top_k=top_k,
                                    course_id=course_id, lesson_id=lesson_id)


def retrieve_relevant_material(db: Session, query: str, top_k: int = 5,
                               course_id: str | None = None, lesson_id: str | None = None,
                               skill_id: str | None = None) -> list[dict]:
    """Free-form semantic search with optional filters."""
    return retriever.retrieve(db, query, top_k=top_k, course_id=course_id,
                              lesson_id=lesson_id, skill_id=skill_id)
