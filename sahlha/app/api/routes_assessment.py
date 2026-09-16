from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from sahlha.app.database.database import get_db
from sahlha.app.schemas.api import CreateStudentRequest, StartAssessmentRequest, SubmitAssessmentRequest
from sahlha.app.services import services as svc

router = APIRouter(tags=["assessment"])


@router.post("/assessment/start")
def start(req: StartAssessmentRequest, db: Session = Depends(get_db)):
    try:
        return svc.start_assessment(db, student_id=req.student_id, student_name=req.student_name,
                                    course_id=req.course_id, lesson_id=req.lesson_id, skill_id=req.skill_id)
    except ValueError as exc:
        raise HTTPException(400, str(exc))


@router.post("/assessment/{assessment_id}/submit")
def submit(assessment_id: str, req: SubmitAssessmentRequest, db: Session = Depends(get_db)):
    try:
        return svc.submit_assessment(db, assessment_id=assessment_id, answers=req.answers)
    except ValueError as exc:
        msg = str(exc)
        # Double-submit is a client error (400); unknown id is 404.
        raise HTTPException(400 if "already submitted" in msg else 404, msg)


@router.get("/students/{student_id}/performance")
def performance(student_id: str, student_name: str = "Student", db: Session = Depends(get_db)):
    try:
        return svc.student_performance(db, student_id, student_name=student_name)
    except ValueError as exc:
        msg = str(exc)
        # Unknown id no longer 404s (auto-created); only bad input is 400.
        raise HTTPException(400 if "required" in msg else 404, msg)


@router.get("/students")
def list_students(limit: int = 100, db: Session = Depends(get_db)):
    return svc.list_students(db, limit=limit)


@router.post("/students")
def create_student(req: CreateStudentRequest, db: Session = Depends(get_db)):
    try:
        return svc.create_student(db, student_id=req.student_id, name=req.name)
    except ValueError as exc:
        raise HTTPException(400, str(exc))


@router.get("/students/{student_id}/skill-progress")
def skill_progress(student_id: str, course_id: str = "general", lesson_id: str = "lesson_1",
                   student_name: str = "Student", db: Session = Depends(get_db)):
    """Skill = explanation + exercise: per-skill study/exercise status."""
    try:
        return svc.skill_progress(db, student_id=student_id, course_id=course_id, lesson_id=lesson_id,
                                  student_name=student_name)
    except ValueError as exc:
        msg = str(exc)
        raise HTTPException(400 if "required" in msg else 404, msg)
