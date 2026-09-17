"""FastAPI auth dependencies: current user, role guards, ownership guards."""
from __future__ import annotations

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from sahlha.app.auth.security import decode_access_token
from sahlha.app.database import models as m
from sahlha.app.database.database import get_db
from sahlha.app.database.repositories import platform as prepo

_bearer = HTTPBearer(auto_error=False)

_UNAUTH = HTTPException(status.HTTP_401_UNAUTHORIZED, "Not authenticated")
_FORBID = HTTPException(status.HTTP_403_FORBIDDEN, "Not allowed")


def current_user(creds: HTTPAuthorizationCredentials | None = Depends(_bearer),
                 db: Session = Depends(get_db)) -> m.User:
    if creds is None or not creds.credentials:
        raise _UNAUTH
    try:
        payload = decode_access_token(creds.credentials)
        user_id = payload.get("sub")
    except jwt.ExpiredSignatureError:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Session expired")
    except jwt.InvalidTokenError:
        raise _UNAUTH
    if not user_id:
        raise _UNAUTH
    user = db.get(m.User, user_id)
    if user is None or not user.active:
        raise _UNAUTH
    return user


def _role_guard(role: str):
    def guard(user: m.User = Depends(current_user)) -> m.User:
        if user.role != role:
            raise _FORBID
        return user

    return guard


require_teacher = _role_guard("teacher")
require_student = _role_guard("student")
require_parent = _role_guard("parent")


def teacher_classroom(classroom_id: str, teacher: m.User = Depends(require_teacher),
                      db: Session = Depends(get_db)) -> m.Classroom:
    room = prepo.get_classroom(db, classroom_id)
    if room is None or room.teacher_id != teacher.id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Classroom not found")
    return room


def enrolled_classroom(classroom_id: str, student: m.User = Depends(require_student),
                       db: Session = Depends(get_db)) -> m.Classroom:
    room = prepo.get_classroom(db, classroom_id)
    if room is None or not prepo.is_enrolled(db, classroom_id, student.id):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Classroom not found")
    return room


def linked_student(student_id: str, parent: m.User = Depends(require_parent),
                   db: Session = Depends(get_db)) -> m.User:
    child = db.get(m.User, student_id)
    if child is None or child.role != "student" or not prepo.is_linked(db, parent.id, student_id):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Child not found")
    return child
