"""Pydantic schemas for the Sahlha platform APIs (auth, classrooms, ...)."""
from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, EmailStr, Field, field_validator

Role = Literal["teacher", "student", "parent"]


class RegisterRequest(BaseModel):
    name: str = Field(min_length=1, max_length=256)
    email: EmailStr
    password: str = Field(min_length=6, max_length=128)
    role: Role


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class UserOut(BaseModel):
    id: str
    name: str
    email: str
    role: str
    link_code: str = ""


class AuthResponse(BaseModel):
    token: str
    user: UserOut


class UpdateProfileRequest(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=256)


class CreateClassroomRequest(BaseModel):
    name: str = Field(min_length=1, max_length=256)
    subject: str = Field(default="", max_length=128)
    grade_level: str = Field(default="", max_length=64)


class UpdateClassroomRequest(BaseModel):
    name: str | None = None
    subject: str | None = None
    grade_level: str | None = None


class JoinClassroomRequest(BaseModel):
    join_code: str = Field(min_length=1, max_length=16)


class LinkChildRequest(BaseModel):
    link_code: str = Field(min_length=1, max_length=16)


class GenerateBanksRequest(BaseModel):
    teacher_feedback: str = ""
    n_questions: int = Field(default=10, ge=4, le=15)


class EditQuestionRequest(BaseModel):
    question_text: str | None = None
    options: list[str] | None = None
    correct_answer: int | str | None = None
    explanation: str | None = None
    difficulty: str | None = None
    question_type: str | None = None


class RegenerateQuestionRequest(BaseModel):
    feedback: str = ""


class RegenerateBankRequest(BaseModel):
    teacher_feedback: str = ""
    n_questions: int = Field(default=10, ge=4, le=15)


class UpdateSkillRequest(BaseModel):
    name: str | None = None
    description: str | None = None
    key_concepts: list[str] | None = None
    explanation: str | None = None


class CreateSkillRequest(BaseModel):
    skill_id: str = Field(min_length=1, max_length=128)
    name: str = ""
    description: str = ""
    key_concepts: list[str] = Field(default_factory=list)


class LearningProfileRequest(BaseModel):
    answers: dict[str, str] = Field(default_factory=dict)


class SupportSignalRequest(BaseModel):
    signal: str

    @field_validator("signal")
    @classmethod
    def _known_signal(cls, value: str) -> str:
        from sahlha.app.services.profiles import KNOWN_SIGNALS

        cleaned = (value or "").strip()
        if cleaned not in KNOWN_SIGNALS:
            raise ValueError(f"Unknown support signal: {cleaned[:64]!r}")
        return cleaned


class StartPlatformAssessmentRequest(BaseModel):
    checkpoint: bool = False
    classroom_id: str | None = None
    material_id: str | None = None
    skill_id: str | None = None
    child_scope: bool = False  # student practicing supplementary material


class SubmitPlatformAssessmentRequest(BaseModel):
    answers: dict[str, object] = Field(default_factory=dict)
    support_signals: list[str] = Field(default_factory=list)


class CheckAnswerRequest(BaseModel):
    question_id: str
    answer: object | None = None


class FlagQuestionRequest(BaseModel):
    reason: str = Field(min_length=1, max_length=2000)

    @field_validator("reason")
    @classmethod
    def nonblank(cls, value):
        if not value.strip():
            raise ValueError("A flag reason is required")
        return value.strip()
