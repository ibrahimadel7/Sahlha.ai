"""POST /auth/register, POST /auth/login, GET /auth/me, PATCH /auth/me."""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from sahlha.app.auth import deps
from sahlha.app.auth.security import create_access_token, hash_password, verify_password
from sahlha.app.database import models as m
from sahlha.app.database.database import get_db
from sahlha.app.database.repositories import platform as prepo
from sahlha.app.schemas.platform import (AuthResponse, LoginRequest, RegisterRequest,
                                         UpdateProfileRequest, UserOut)

router = APIRouter(prefix="/auth", tags=["auth"])


def _out(user: m.User) -> UserOut:
    return UserOut(id=user.id, name=user.name, email=user.email, role=user.role,
                   link_code=user.link_code if user.role == "student" else "")


@router.post("/register", response_model=AuthResponse, status_code=status.HTTP_201_CREATED)
def register(req: RegisterRequest, db: Session = Depends(get_db)):
    if prepo.get_user_by_email(db, req.email):
        raise HTTPException(status.HTTP_409_CONFLICT, "Email is already registered")
    try:
        pw_hash = hash_password(req.password)
    except ValueError as exc:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, str(exc))
    user = prepo.create_user(db, name=req.name, email=req.email,
                             password_hash=pw_hash, role=req.role)
    return AuthResponse(token=create_access_token(user_id=user.id, role=user.role),
                        user=_out(user))


@router.post("/login", response_model=AuthResponse)
def login(req: LoginRequest, db: Session = Depends(get_db)):
    user = prepo.get_user_by_email(db, req.email)
    if user is None or not verify_password(req.password, user.password_hash):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid email or password")
    if not user.active:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Account is disabled")
    return AuthResponse(token=create_access_token(user_id=user.id, role=user.role),
                        user=_out(user))


@router.get("/me", response_model=UserOut)
def me(user: m.User = Depends(deps.current_user)):
    return _out(user)


@router.patch("/me", response_model=UserOut)
def update_me(req: UpdateProfileRequest, user: m.User = Depends(deps.current_user),
              db: Session = Depends(get_db)):
    if req.name:
        user.name = req.name.strip()
        db.commit()
        db.refresh(user)
    return _out(user)
