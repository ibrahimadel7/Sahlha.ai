"""Teacher platform APIs: overview, scoped bank review, question editing,
regeneration, approval, classroom mastery, student progress.

Legacy /teacher/question-banks/* endpoints stay for backwards compatibility;
these endpoints add ownership scoping + full workflow.
"""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from sahlha.app.auth import deps
from sahlha.app.database import models as m
from sahlha.app.database.database import get_db
from sahlha.app.database.repositories import platform as prepo
from sahlha.app.database.repositories import repositories as repo
from sahlha.app.schemas.platform import (FlagQuestionRequest, EditQuestionRequest, RegenerateBankRequest,
                                         RegenerateQuestionRequest)
from sahlha.app.services import platform as plat
from sahlha.app.services import services as legacy

router = APIRouter(prefix="/teacher", tags=["teacher"])


def _owned_bank(bank_id: str, teacher: m.User, db: Session) -> m.QuestionBank:
    bank = repo.get_bank(db, bank_id)
    if bank is None:
        raise HTTPException(404, "Question bank not found")
    from sahlha.app.services import mapping
    classroom_id = bank.classroom_id or mapping.classroom_id_from_course(bank.course_id)
    if classroom_id:
        deps.teacher_classroom(classroom_id, teacher, db)
    if bank.course_id.startswith("child:") or (bank.teacher_id and bank.teacher_id != teacher.id):
        raise HTTPException(404, "Question bank not found")
    return bank


@router.get("/overview")
def overview(teacher: m.User = Depends(deps.require_teacher),
             db: Session = Depends(get_db)):
    return plat.teacher_overview(db, teacher.id)


@router.get("/banks")
def list_banks(status: str | None = None, classroom_id: str | None = None,
               material_id: str | None = None,
               teacher: m.User = Depends(deps.require_teacher),
               db: Session = Depends(get_db)):
    if classroom_id:
        deps.teacher_classroom(classroom_id, teacher, db)
    banks = repo.list_banks(db, status=status, teacher_id=teacher.id,
                            classroom_id=classroom_id, material_id=material_id)
    # Also include legacy unowned banks so old data stays reviewable.
    if not classroom_id and not material_id:
        banks = banks + [b for b in repo.list_banks(db, status=status) if not b.teacher_id and not b.course_id.startswith(("class:", "child:"))]
    return [{"id": b.id, "course_id": b.course_id, "lesson_id": b.lesson_id,
             "skill_id": b.skill_id, "version": b.version, "status": b.status,
             "feedback": b.teacher_feedback, "classroom_id": b.classroom_id,
             "material_id": b.material_id,
             "num_questions": len(repo.get_questions(db, b.id))} for b in banks]


@router.get("/banks/{bank_id}")
def bank_detail(bank_id: str, teacher: m.User = Depends(deps.require_teacher),
                db: Session = Depends(get_db)):
    return plat.bank_to_dict_teacher(db, _owned_bank(bank_id, teacher, db))


@router.post("/banks/{bank_id}/approve")
def approve_bank(bank_id: str, teacher: m.User = Depends(deps.require_teacher),
                 db: Session = Depends(get_db)):
    _owned_bank(bank_id, teacher, db)
    try:
        return legacy.approve_bank(db, bank_id)
    except ValueError as exc:
        raise HTTPException(404, str(exc))


@router.post("/banks/{bank_id}/reject")
def reject_bank(bank_id: str, feedback: str = "",
                teacher: m.User = Depends(deps.require_teacher),
                db: Session = Depends(get_db)):
    _owned_bank(bank_id, teacher, db)
    try:
        return legacy.reject_bank(db, bank_id, feedback)
    except ValueError as exc:
        raise HTTPException(404, str(exc))


@router.patch("/banks/{bank_id}/questions/{question_id}")
def edit_bank_question(bank_id: str, question_id: str, req: EditQuestionRequest,
                       teacher: m.User = Depends(deps.require_teacher),
                       db: Session = Depends(get_db)):
    bank = _owned_bank(bank_id, teacher, db)
    try:
        return plat.edit_question(db, bank, question_id, req.model_dump(exclude_none=True))
    except ValueError as exc:
        raise HTTPException(404, str(exc))


@router.delete("/banks/{bank_id}/questions/{question_id}")
def reject_bank_question(bank_id: str, question_id: str,
                         teacher: m.User = Depends(deps.require_teacher),
                         db: Session = Depends(get_db)):
    bank = _owned_bank(bank_id, teacher, db)
    try:
        return plat.remove_question(db, bank, question_id)
    except ValueError as exc:
        raise HTTPException(404, str(exc))


@router.post("/banks/{bank_id}/questions/{question_id}/regenerate")
def regenerate_bank_question(bank_id: str, question_id: str, req: RegenerateQuestionRequest,
                             teacher: m.User = Depends(deps.require_teacher),
                             db: Session = Depends(get_db)):
    bank = _owned_bank(bank_id, teacher, db)
    try:
        return plat.regenerate_question(db, bank, question_id, req.feedback)
    except ValueError as exc:
        raise HTTPException(404, str(exc))


@router.post("/banks/{bank_id}/regenerate", status_code=status.HTTP_201_CREATED)
def regenerate_whole_bank(bank_id: str, req: RegenerateBankRequest,
                          teacher: m.User = Depends(deps.require_teacher),
                          db: Session = Depends(get_db)):
    bank = _owned_bank(bank_id, teacher, db)
    return plat.regenerate_bank(db, bank, teacher_feedback=req.teacher_feedback,
                                n_questions=req.n_questions)


@router.get("/classrooms/{classroom_id}/mastery")
def classroom_mastery(room: m.Classroom = Depends(deps.teacher_classroom),
                      db: Session = Depends(get_db)):
    return plat.classroom_mastery(db, room.id)


@router.get("/classrooms/{classroom_id}/students/{student_id}")
def teacher_student_progress(classroom_id: str, student_id: str,
                             teacher: m.User = Depends(deps.require_teacher),
                             db: Session = Depends(get_db)):
    deps.teacher_classroom(classroom_id, teacher, db)
    if not prepo.is_enrolled(db, classroom_id, student_id):
        raise HTTPException(404, "Student not found")
    return plat.student_progress_detail(db, student_id=student_id, classroom_id=classroom_id)


@router.post("/banks/{bank_id}/questions/{question_id}/flag", status_code=201)
def flag_question(bank_id: str, question_id: str, req: FlagQuestionRequest,
                  teacher: m.User = Depends(deps.require_teacher), db: Session = Depends(get_db)):
    bank = _owned_bank(bank_id, teacher, db)
    try:
        return plat.flag_bank_question(db, bank, question_id, req.reason, teacher.id)
    except ValueError as exc:
        raise HTTPException(404, str(exc))


@router.get("/banks/{bank_id}/flags")
def list_flags(bank_id: str, teacher: m.User = Depends(deps.require_teacher), db: Session = Depends(get_db)):
    return plat.bank_flags(db, _owned_bank(bank_id, teacher, db))
