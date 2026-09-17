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
    return [{"skill_id": p.skill_id, "course_id": getattr(p, "course_id", "general") or "general",
             "lesson_id": getattr(p, "lesson_id", "lesson_1") or "lesson_1",
             "total": p.total_attempts, "correct": p.correct_attempts,
             "accuracy": p.accuracy} for p in rows]


def update_student_memory(db: Session, *, student_id: str, skill_id: str, correct: bool,
                          course_id: str = "general", lesson_id: str = "lesson_1",
                          commit: bool = True, skill_row_id: str | None = None) -> dict:
    # Normalize '' (platform) to general/lesson_1 (legacy) so history never splits.
    course_id = (course_id or "general") or "general"
    lesson_id = (lesson_id or "lesson_1") or "lesson_1"
    try:
        perf = repo.upsert_skill_performance(db, student_id=student_id, skill_id=skill_id,
                                             correct=correct, course_id=course_id, lesson_id=lesson_id,
                                             commit=commit, skill_row_id=skill_row_id)
    except TypeError:
        # Older repo without skill_row_id/commit — fall back.
        try:
            perf = repo.upsert_skill_performance(db, student_id=student_id, skill_id=skill_id,
                                                 correct=correct, course_id=course_id,
                                                 lesson_id=lesson_id, commit=commit)
        except TypeError:
            perf = repo.upsert_skill_performance(db, student_id=student_id, skill_id=skill_id,
                                                 correct=correct, course_id=course_id,
                                                 lesson_id=lesson_id)
    return {"skill_id": perf.skill_id, "total": perf.total_attempts,
            "correct": perf.correct_attempts, "accuracy": perf.accuracy}

ensure_student = repo.get_or_create_student


def update_memory_for_question(db, *, student_id, question, correct):
    bank = repo.get_bank(db, question.question_bank_id)
    if bank is None:
        raise ValueError("Question context is unavailable")
    skill = repo.get_skill(db, course_id=bank.course_id, lesson_id=bank.lesson_id, skill_id=question.skill_id)
    return update_student_memory(db, student_id=student_id, skill_id=question.skill_id, correct=correct,
        course_id=bank.course_id, lesson_id=bank.lesson_id, skill_row_id=skill.id if skill else None)
