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
    return retrieve(db, f"lesson {lesson_id} course {course_id} overview key concepts",
                    top_k=top_k, course_id=course_id, lesson_id=lesson_id)
