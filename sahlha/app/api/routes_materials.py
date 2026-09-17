"""Material upload/process/skills/banks for teachers (official) and parents (supp)."""
from __future__ import annotations

from fastapi import BackgroundTasks, APIRouter, Depends, File, Form, HTTPException, UploadFile, status
from sqlalchemy.orm import Session

from sahlha.app.auth import deps
from sahlha.app.config import settings
from sahlha.app.database import models as m
from sahlha.app.database.database import get_db
from sahlha.app.database.repositories import platform as prepo
from sahlha.app.database.repositories import repositories as repo
from sahlha.app.schemas.platform import CreateSkillRequest, GenerateBanksRequest, UpdateSkillRequest
from sahlha.app.services import mapping
from sahlha.app.services import platform as plat

router = APIRouter(prefix="/materials", tags=["materials"])


def _can_view(user: m.User, db: Session, mat: m.LearningMaterial) -> bool:
    if user.role == "teacher":
        room = prepo.get_classroom(db, mat.classroom_id) if mat.classroom_id else None
        return (mat.scope == "official" and room is not None and room.teacher_id == user.id)
    if user.role == "student":
        return ((mat.scope == "official" and mat.classroom_id
                 and prepo.is_enrolled(db, mat.classroom_id, user.id))
                or (mat.scope == "supplementary" and mat.child_student_id == user.id))
    if user.role == "parent":
        return mat.scope == "supplementary" and bool(
            mat.child_student_id and prepo.is_linked(db, user.id, mat.child_student_id))
    return False


def _can_manage(user: m.User, mat: m.LearningMaterial) -> bool:
    # Teachers manage their official materials; parents manage their supplementary ones.
    return mat.uploader_id == user.id


def _get_owned(material_id: str, user: m.User, db: Session) -> m.LearningMaterial:
    mat = prepo.get_material(db, material_id)
    if mat is None or not _can_manage(user, mat):
        raise HTTPException(404, "Material not found")
    return mat


def _get_visible(material_id: str, user: m.User, db: Session) -> m.LearningMaterial:
    mat = prepo.get_material(db, material_id)
    if mat is None or not _can_view(user, db, mat):
        raise HTTPException(404, "Material not found")
    return mat


@router.post("/upload", status_code=status.HTTP_201_CREATED)
def upload_material(background_tasks: BackgroundTasks, title: str = Form(""), classroom_id: str | None = Form(None),
                          child_student_id: str | None = Form(None),
                          file: UploadFile = File(...),
                          user: m.User = Depends(deps.current_user),
                          db: Session = Depends(get_db)):
    if user.role not in ("teacher", "parent"):
        raise HTTPException(403, "Only teachers and parents can upload materials")
    # Run blocking document processing in FastAPI's worker thread, and bound reads.
    data = file.file.read(settings.max_upload_mb * 1024 * 1024 + 1)
    try:
        plat.validate_upload(file.filename or "upload", len(data))
    except ValueError as exc:
        raise HTTPException(422, str(exc))
    try:
        mat = plat.create_material_record(db, uploader=user, title=title,
                                          filename=file.filename or "upload",
                                          classroom_id=classroom_id or None,
                                          child_student_id=child_student_id or None)
    except ValueError as exc:
        raise HTTPException(404, str(exc))
    try:
        result = plat.process_material(db, mat, data, background_tasks=background_tasks)
    except ValueError as exc:
        return {"material": plat.material_to_dict(db, mat), "error": str(exc)}
    return {"material": plat.material_to_dict(db, mat),
            "document_id": result["document_id"], "chunk_count": result["chunk_count"]}


@router.get("")
def list_materials(classroom_id: str | None = None, child_student_id: str | None = None,
                   user: m.User = Depends(deps.current_user),
                   db: Session = Depends(get_db)):
    out: list[m.LearningMaterial] = []
    if user.role == "teacher":
        rooms = ([prepo.get_classroom(db, classroom_id)] if classroom_id
                 else prepo.list_teacher_classrooms(db, user.id))
        for room in rooms:
            if room and room.teacher_id == user.id:
                out.extend(prepo.list_classroom_materials(db, room.id))
    elif user.role == "student":
        rooms = ([prepo.get_classroom(db, classroom_id)] if classroom_id
                 else prepo.list_student_classrooms(db, user.id))
        for room in rooms:
            if room and prepo.is_enrolled(db, room.id, user.id):
                out.extend(prepo.list_classroom_materials(db, room.id))
        out.extend(prepo.list_supplementary_materials(db, user.id))
    elif user.role == "parent":
        if child_student_id:
            deps.linked_student(child_student_id, user, db)  # raises unless linked
            kids = [child_student_id]
        else:
            kids = [c.id for c in prepo.list_linked_children(db, user.id)]
        for kid in kids:
            out.extend(prepo.list_supplementary_materials(db, kid))
    return [plat.material_to_dict(db, m) for m in out
            if _can_view(user, db, m)]


@router.get("/{material_id}")
def get_material(material_id: str, user: m.User = Depends(deps.current_user),
                 db: Session = Depends(get_db)):
    return plat.material_to_dict(db, _get_visible(material_id, user, db))


@router.post("/{material_id}/extract-skills")
def extract_skills(material_id: str, force: bool = False,
                   user: m.User = Depends(deps.current_user),
                   db: Session = Depends(get_db)):
    mat = _get_owned(material_id, user, db)
    try:
        return plat.extract_material_skills(db, mat, force=force)
    except ValueError as exc:
        raise HTTPException(400, str(exc))


@router.get("/{material_id}/skills")
def material_skills(material_id: str, user: m.User = Depends(deps.current_user),
                    db: Session = Depends(get_db)):
    mat = _get_visible(material_id, user, db)
    course_id, lesson_id = mapping.scope_for_material(mat)
    return [plat.skill_dict(db, course_id, lesson_id, s)
            for s in repo.list_skills(db, course_id=course_id, lesson_id=lesson_id)]


@router.post("/{material_id}/skills")
def add_skill(material_id: str, req: CreateSkillRequest,
              user: m.User = Depends(deps.current_user),
              db: Session = Depends(get_db)):
    mat = _get_owned(material_id, user, db)
    course_id, lesson_id = mapping.scope_for_material(mat)
    row = repo.upsert_skill(db, course_id=course_id, lesson_id=lesson_id,
                            skill_id=req.skill_id, name=req.name or req.skill_id,
                            description=req.description, key_concepts=req.key_concepts)
    return plat.skill_dict(db, course_id, lesson_id, row)


@router.patch("/{material_id}/skills/{skill_id}")
def edit_skill(material_id: str, skill_id: str, req: UpdateSkillRequest,
               user: m.User = Depends(deps.current_user),
               db: Session = Depends(get_db)):
    mat = _get_owned(material_id, user, db)
    course_id, lesson_id = mapping.scope_for_material(mat)
    row = repo.get_skill(db, course_id=course_id, lesson_id=lesson_id, skill_id=skill_id)
    if row is None:
        raise HTTPException(404, "Skill not found")
    return plat.update_skill(db, row, **req.model_dump(exclude_none=True))


@router.delete("/{material_id}/skills/{skill_id}", status_code=status.HTTP_204_NO_CONTENT)
def remove_skill(material_id: str, skill_id: str,
                 user: m.User = Depends(deps.current_user),
                 db: Session = Depends(get_db)):
    mat = _get_owned(material_id, user, db)
    course_id, lesson_id = mapping.scope_for_material(mat)
    row = repo.get_skill(db, course_id=course_id, lesson_id=lesson_id, skill_id=skill_id)
    if row is None:
        raise HTTPException(404, "Skill not found")
    plat.delete_skill(db, row)
    return None


@router.post("/{material_id}/generate-banks")
def generate_banks(material_id: str, req: GenerateBanksRequest,
                   teacher: m.User = Depends(deps.require_teacher),
                   db: Session = Depends(get_db)):
    mat = _get_owned(material_id, teacher, db)
    if mat.scope != "official":
        raise HTTPException(403, "Only official classroom materials have reviewable banks")
    try:
        return plat.generate_material_banks(db, mat, teacher=teacher,
                                            teacher_feedback=req.teacher_feedback,
                                            n_questions=req.n_questions)
    except ValueError as exc:
        raise HTTPException(400, str(exc))


@router.get("/{material_id}/banks")
def material_banks(material_id: str, user: m.User = Depends(deps.current_user),
                   db: Session = Depends(get_db)):
    mat = _get_visible(material_id, user, db)
    _, lesson_id = mapping.scope_for_material(mat)
    banks = repo.list_banks(db, lesson_id=lesson_id)
    # Students/parents never see bank contents here; only readiness.
    if user.role in ("student", "parent"):
        return [{"skill_id": b.skill_id, "version": b.version, "status": b.status,
                 "num_questions": len(repo.get_questions(db, b.id))} for b in banks]
    return [{"id": b.id, "skill_id": b.skill_id, "version": b.version, "status": b.status,
             "feedback": b.teacher_feedback,
             "num_questions": len(repo.get_questions(db, b.id))} for b in banks]
