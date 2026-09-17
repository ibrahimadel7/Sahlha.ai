"""Question-bank tools — persistence goes through here, never raw SQL from the LLM."""
from __future__ import annotations

from sqlalchemy.orm import Session

from sahlha.app.agent.schemas import QuestionList
from sahlha.app.database.repositories import repositories as repo


def save_questions(db: Session, *, course_id: str, lesson_id: str, skill_id: str,
                   questions: list[dict], teacher_feedback: str = "") -> dict:
    """Validate structured LLM output then persist as a new pending_review version.

    Structural validation (Pydantic QuestionList) rejects malformed output:
    missing fields, wrong types, bad MCQ shape, duplicate options/questions.
    RAG grounding is validated by the caller (agent) which owns the retrieved
    chunks; provenance fields persist when present so Question->Skill->RAG
    stays traceable. Empty lists are allowed (explicit failure state for empty
    retrieval) so failures are observable, never silently padded.
    """
    validated = QuestionList(questions=questions).questions  # rejects malformed output
    bank = repo.create_bank(db, course_id=course_id, lesson_id=lesson_id, skill_id=skill_id,
                            questions=[q.to_record() for q in validated],
                            teacher_feedback=teacher_feedback)
    return {"question_bank_id": bank.id, "version": bank.version, "status": bank.status,
            "num_questions": len(validated)}


def get_question_bank(db: Session, bank_id: str) -> dict | None:
    bank = repo.get_bank(db, bank_id)
    if not bank:
        return None
    return {"id": bank.id, "course_id": bank.course_id, "lesson_id": bank.lesson_id,
            "skill_id": bank.skill_id, "version": bank.version, "status": bank.status,
            "feedback": bank.teacher_feedback,
            "questions": [{"id": q.id, "skill_id": q.skill_id, "type": q.question_type,
                           "question": q.question_text, "options": q.options,
                           "correct_answer": q.correct_answer, "explanation": q.explanation,
                           "difficulty": q.difficulty,
                           "source_chunk_ids": list(getattr(q, "source_chunk_ids", None) or []),
                           "source_evidence": list(getattr(q, "source_evidence", None) or [])}
                          for q in repo.get_questions(db, bank.id)]}


def get_approved_questions(db: Session, *, course_id: str | None = None,
                           lesson_id: str | None = None, skill_id: str | None = None) -> list[dict]:
    rows = repo.get_approved_questions(db, course_id=course_id, lesson_id=lesson_id, skill_id=skill_id)
    return [{"id": q.id, "bank_id": q.question_bank_id, "skill_id": q.skill_id,
             "type": q.question_type, "question": q.question_text, "options": q.options,
             "correct_answer": q.correct_answer, "explanation": q.explanation,
             "difficulty": q.difficulty,
             "source_chunk_ids": list(getattr(q, "source_chunk_ids", None) or []),
             "source_evidence": list(getattr(q, "source_evidence", None) or [])} for q in rows]
