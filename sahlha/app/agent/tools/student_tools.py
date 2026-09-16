"""Student-memory tools — read/update relational memory, never a vector summary as truth."""
from __future__ import annotations

from sqlalchemy.orm import Session

from sahlha.app.database.repositories import repositories as repo


def get_student_history(db: Session, student_id: str, limit: int = 200) -> list[dict]:
    return [{"question_id": a.question_id, "assessment_id": a.assessment_id,
             "answer": a.answer, "correct": a.correct,
             "timestamp": a.timestamp.isoformat()} for a in repo.get_attempts(db, student_id, limit)]


def get_failed_questions(db: Session, student_id: str) -> list[str]:
    return repo.get_failed_question_ids(db, student_id)


def get_student_skill_performance(db: Session, student_id: str, *,
                                  course_id: str | None = None,
                                  lesson_id: str | None = None) -> list[dict]:
    rows = repo.get_skill_performance(db, student_id, course_id=course_id, lesson_id=lesson_id)
    return [{"skill_id": p.skill_id, "course_id": getattr(p, "course_id", "general"),
             "lesson_id": getattr(p, "lesson_id", "lesson_1"),
             "total": p.total_attempts, "correct": p.correct_attempts,
             "accuracy": p.accuracy} for p in rows]


def update_student_memory(db: Session, *, student_id: str, skill_id: str, correct: bool,
                          course_id: str = "general", lesson_id: str = "lesson_1",
                          commit: bool = True) -> dict:
    perf = repo.upsert_skill_performance(db, student_id=student_id, skill_id=skill_id,
                                         correct=correct, course_id=course_id, lesson_id=lesson_id,
                                         commit=commit)
    return {"skill_id": perf.skill_id, "total": perf.total_attempts,
            "correct": perf.correct_attempts, "accuracy": perf.accuracy}
