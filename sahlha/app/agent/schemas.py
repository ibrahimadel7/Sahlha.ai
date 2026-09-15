"""Structured schemas for LLM output validation (Pydantic)."""
from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field, field_validator


class GeneratedQuestion(BaseModel):
    skill_id: str = "general"
    type: Literal["multiple_choice", "short_answer"] = "multiple_choice"
    question: str
    options: list[str] = Field(default_factory=list)
    correct_answer: int | str = 0
    explanation: str = ""
    difficulty: Literal["easy", "medium", "hard"] = "medium"

    def to_record(self) -> dict:
        return {
            "skill_id": self.skill_id,
            "question_type": self.type,
            "question_text": self.question,
            "options": self.options,
            "correct_answer": self.correct_answer,
            "explanation": self.explanation,
            "difficulty": self.difficulty,
        }


class QuestionList(BaseModel):
    questions: list[GeneratedQuestion]

    @field_validator("questions")
    @classmethod
    def validate_mcq(cls, qs):
        for q in qs:
            if q.type == "multiple_choice":
                if len(q.options) != 4:
                    raise ValueError(f"MCQ must have exactly 4 options, got {len(q.options)}: {q.question[:60]}")
                if not isinstance(q.correct_answer, int) or not (0 <= q.correct_answer <= 3):
                    raise ValueError(f"correct_answer must be 0-3 for MCQ: {q.question[:60]}")
        return qs


class ExtractedSkill(BaseModel):
    skill_id: str
    name: str = ""
    description: str = ""
    key_concepts: list[str] = Field(default_factory=list)

    @field_validator("skill_id")
    @classmethod
    def slugify(cls, v: str) -> str:
        import re

        slug = re.sub(r"[^a-z0-9]+", "_", v.lower()).strip("_")
        if not slug:
            raise ValueError("skill_id must not be empty")
        return slug


class SkillList(BaseModel):
    skills: list[ExtractedSkill]


class SkillExplanation(BaseModel):
    explanation: str

    @field_validator("explanation")
    @classmethod
    def non_empty(cls, v: str) -> str:
        if len(v.strip()) < 40:
            raise ValueError("explanation too short; must ground it in the material")
        return v.strip()


class LessonExplanationModel(BaseModel):
    title: str = ""
    explanation: str
    key_concepts: list[str] = Field(default_factory=list)

    @field_validator("explanation")
    @classmethod
    def non_empty(cls, v: str) -> str:
        if len(v.strip()) < 60:
            raise ValueError("lesson explanation too short; must ground it in the material")
        return v.strip()


class CritiqueVerdict(BaseModel):
    index: int = 0
    grounded: bool = True
    answer_correct: bool = True
    issue: str = ""


class CritiqueResult(BaseModel):
    verdicts: list[CritiqueVerdict]
