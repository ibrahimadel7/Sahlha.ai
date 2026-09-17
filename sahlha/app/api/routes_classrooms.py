"""Classroom system: teacher CRUD + join codes + enrollment."""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from sahlha.app.auth import deps
from sahlha.app.database import models as m
from sahlha.app.database.database import get_db
from sahlha.app.database.repositories import platform as prepo
from sahlha.app.schemas.platform import (CreateClassroomRequest, JoinClassroomRequest,
                                         UpdateClassroomRequest)

router = APIRouter(prefix="/classrooms", tags=["classrooms"])


def _out(room: m.Classroom, *, students: int | None = None) -> dict:
    payload = {"id": room.id, "teacher_id": room.teacher_id, "name": room.name,
               "subject": room.subject, "grade_level": room.grade_level,
               "join_code": room.join_code}
    if students is not None:
        payload["num_students"] = students
    return payload


@router.post("", status_code=status.HTTP_201_CREATED)
def create_classroom(req: CreateClassroomRequest,
                     teacher: m.User = Depends(deps.require_teacher),
                     db: Session = Depends(get_db)):
    room = prepo.create_classroom(db, teacher_id=teacher.id, name=req.name,
                                  subject=req.subject, grade_level=req.grade_level)
    return _out(room, students=0)


@router.get("")
def list_classrooms(user: m.User = Depends(deps.current_user),
                    db: Session = Depends(get_db)):
    if user.role == "teacher":
        rooms = prepo.list_teacher_classrooms(db, user.id)
    elif user.role == "student":
        rooms = prepo.list_student_classrooms(db, user.id)
    else:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Not allowed")
    return [_out(r, students=len(prepo.list_enrolled_students(db, r.id))) for r in rooms]


@router.get("/{classroom_id}")
def get_classroom(classroom_id: str, user: m.User = Depends(deps.current_user),
                  db: Session = Depends(get_db)):
    room = prepo.get_classroom(db, classroom_id)
    if room is None:
        raise HTTPException(404, "Classroom not found")
    if user.role == "teacher" and room.teacher_id != user.id:
        raise HTTPException(404, "Classroom not found")
    if user.role == "student" and not prepo.is_enrolled(db, classroom_id, user.id):
        raise HTTPException(404, "Classroom not found")
    if user.role == "parent":
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Not allowed")
    students = prepo.list_enrolled_students(db, room.id)
    payload = _out(room, students=len(students))
    if user.role == "teacher":
        payload["students"] = [{"id": s.id, "name": s.name} for s in students]
    return payload


@router.patch("/{classroom_id}")
def update_classroom(classroom_id: str, req: UpdateClassroomRequest,
                     room: m.Classroom = Depends(deps.teacher_classroom),
                     db: Session = Depends(get_db)):
    if req.name is not None:
        room.name = req.name.strip()
    if req.subject is not None:
        room.subject = req.subject.strip()
    if req.grade_level is not None:
        room.grade_level = req.grade_level.strip()
    db.commit()
    return _out(room)


@router.post("/join")
def join_classroom(req: JoinClassroomRequest,
                   student: m.User = Depends(deps.require_student),
                   db: Session = Depends(get_db)):
    room = prepo.get_classroom_by_join_code(db, req.join_code)
    if room is None:
        raise HTTPException(404, "Invalid join code")
    already = prepo.is_enrolled(db, room.id, student.id)
    prepo.enroll(db, classroom_id=room.id, student_id=student.id)
    return {"classroom": _out(room), "already_enrolled": already}


@router.get("/{classroom_id}/students")
def classroom_students(room: m.Classroom = Depends(deps.teacher_classroom),
                       db: Session = Depends(get_db)):
    return [{"id": s.id, "name": s.name}
            for s in prepo.list_enrolled_students(db, room.id)]
