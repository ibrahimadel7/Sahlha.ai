from __future__ import annotations

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from sahlha.app.database.database import get_db
from sahlha.app.schemas.api import ExtractSkillsRequest, GenerateBankRequest, LessonBanksRequest
from sahlha.app.services import services as svc

from sahlha.app.api.deps import require_teacher

router = APIRouter(prefix="/agent", tags=["agent"])


@router.post("/generate-question-bank")
def generate_bank(req: GenerateBankRequest, db: Session = Depends(get_db),
                  _teacher: None = Depends(require_teacher)):
    return svc.generate_bank(db, course_id=req.course_id, lesson_id=req.lesson_id,
                             skill_id=req.skill_id, teacher_feedback=req.teacher_feedback,
                             n_questions=req.n_questions)


@router.post("/extract-skills")
def extract_skills(req: ExtractSkillsRequest, db: Session = Depends(get_db),
                   _teacher: None = Depends(require_teacher)):
    """Agent splits the lesson into skills (agent decides how many), each with an explanation."""
    return svc.extract_skills(db, course_id=req.course_id, lesson_id=req.lesson_id,
                              max_skills=req.max_skills, force=req.force)


@router.get("/skills")
def list_skills(course_id: str = "general", lesson_id: str = "lesson_1",
                skill_id: str | None = None, db: Session = Depends(get_db)):
    """Student/teacher-facing: read skills with their agent-written explanations."""
    return svc.list_skills(db, course_id=course_id, lesson_id=lesson_id, skill_id=skill_id)


@router.post("/explain-lesson")
def explain_lesson(course_id: str = "general", lesson_id: str = "lesson_1",
                   force: bool = False, db: Session = Depends(get_db),
                   _teacher: None = Depends(require_teacher)):
    """Agent writes (or returns) the overview explanation for a whole lesson."""
    return svc.explain_lesson(db, course_id=course_id, lesson_id=lesson_id, force=force)


@router.get("/lesson")
def get_lesson(course_id: str = "general", lesson_id: str = "lesson_1",
               db: Session = Depends(get_db)):
    """Student study bundle: lesson overview + per-skill explanations."""
    return svc.get_lesson(db, course_id=course_id, lesson_id=lesson_id)


@router.post("/generate-lesson-banks")
def generate_lesson_banks(req: LessonBanksRequest, db: Session = Depends(get_db),
                          _teacher: None = Depends(require_teacher)):
    """One question bank per skill of the lesson (each bank approved independently)."""
    return svc.generate_lesson_banks(db, course_id=req.course_id, lesson_id=req.lesson_id,
                                     teacher_feedback=req.teacher_feedback,
                                     n_questions=req.n_questions)
