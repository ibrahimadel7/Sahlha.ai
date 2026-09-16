"""LangGraph teacher content workflow: run → (pause) → decide → resume/finish."""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from sahlha.app.api.deps import require_teacher
from sahlha.app.database.database import get_db
from sahlha.app.schemas.api import WorkflowDecideRequest, WorkflowRunRequest
from sahlha.app.services import services as svc

router = APIRouter(prefix="/workflow", tags=["workflow"])


@router.post("/content/run")
def run_content(req: WorkflowRunRequest, db: Session = Depends(get_db),
                _teacher: None = Depends(require_teacher)):
    """Run retrieve → extract → explain → generate, then pause for teacher review.

    Returns `thread_id` + snapshot (status `waiting_for_teacher` when banks are ready).
    """
    try:
        return svc.run_content_workflow(
            db, course_id=req.course_id, lesson_id=req.lesson_id,
            teacher_feedback=req.teacher_feedback, n_questions=req.n_questions,
            max_skills=req.max_skills, force=req.force, include_media=req.include_media)
    except ValueError as exc:
        raise HTTPException(400, str(exc))


@router.get("/content/state")
def workflow_state(thread_id: str, db: Session = Depends(get_db)):
    """Current snapshot of a workflow run (paused, finished, or failed)."""
    try:
        return svc.workflow_snapshot(db, thread_id=thread_id)
    except ValueError as exc:
        msg = str(exc)
        raise HTTPException(404 if "not found" in msg else 400, msg)


@router.post("/content/decide")
def workflow_decide(req: WorkflowDecideRequest, db: Session = Depends(get_db),
                    _teacher: None = Depends(require_teacher)):
    """Approve (finish) or reject (regenerate with feedback, up to 3 tries) a paused run."""
    try:
        return svc.teacher_decide(db, thread_id=req.thread_id,
                                  action=req.action, feedback=req.feedback)
    except ValueError as exc:
        msg = str(exc)
        raise HTTPException(404 if "not found" in msg else 400, msg)
