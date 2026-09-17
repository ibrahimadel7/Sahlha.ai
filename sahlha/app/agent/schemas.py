"""Structured schemas for LLM output validation (Pydantic)."""
from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field, field_validator


class GeneratedQuestion(BaseModel):
    evidence_chunk_ids: list[str] = Field(default_factory=list)
    learning_objective: str = ""
    tested_concept: str = ""
    verification: dict = Field(default_factory=dict)
    skill_id: str = "general"
    type: Literal["multiple_choice", "short_answer"] = "multiple_choice"
    question: str = Field(min_length=1)
    options: list[str] = Field(default_factory=list)
    correct_answer: int | str = 0
    explanation: str = ""
    difficulty: Literal["easy", "medium", "hard"] = "medium"
    # RAG provenance (filled deterministically by the app from the SAME
    # retrieved chunks used for generation; see grounding.attach_*_evidence).
    # Optional on the raw LLM contract for backwards compat; required on
    # GroundedQuestion below.
    source_chunk_ids: list[str] = Field(default_factory=list)
    source_evidence: list[str] = Field(default_factory=list)

    @field_validator("question")
    @classmethod
    def _question_non_empty(cls, v: str) -> str:
        if not str(v or "").strip():
            raise ValueError("question text must be non-empty")
        return str(v).strip()

    @field_validator("skill_id")
    @classmethod
    def _skill_non_empty(cls, v: str) -> str:
        if not str(v or "").strip():
            raise ValueError("skill_id must be non-empty")
        return str(v).strip()

    def to_record(self) -> dict:
        return {
            "evidence_chunk_ids": self.evidence_chunk_ids,
            "learning_objective": self.learning_objective,
            "tested_concept": self.tested_concept,
            "verification": self.verification,
            "skill_id": self.skill_id,
            "question_type": self.type,
            "question_text": self.question,
            "options": self.options,
            "correct_answer": self.correct_answer,
            "explanation": self.explanation,
            "difficulty": self.difficulty,
            "source_chunk_ids": list(self.source_chunk_ids or []),
            "source_evidence": list(self.source_evidence or []),
        }


class QuestionList(BaseModel):
    questions: list[GeneratedQuestion]

    @field_validator("questions")
    @classmethod
    def validate_mcq(cls, qs):
        # Exact duplicates (same stem + same options + same answer) are never
        # valid. Rotation variants from the deterministic fallback (same stem,
        # different option order) are allowed: they test the same fact without
        # positional bias, per the existing generator design.
        seen: set[tuple] = set()
        for q in qs:
            if q.type == "multiple_choice":
                if len(q.options) != 4:
                    raise ValueError(f"MCQ must have exactly 4 options, got {len(q.options)}: {q.question[:60]}")
                if isinstance(q.correct_answer, bool) or not isinstance(q.correct_answer, int) or not (0 <= q.correct_answer <= 3):
                    raise ValueError(f"correct_answer must be 0-3 for MCQ: {q.question[:60]}")
                stripped = [str(o or "").strip() for o in q.options]
                if any(not o for o in stripped):
                    raise ValueError(f"MCQ options must be non-empty: {q.question[:60]}")
                lowered = [o.lower() for o in stripped]
                if len(set(lowered)) != len(lowered):
                    raise ValueError(f"MCQ options must be unique (duplicate found): {q.question[:60]}")
            norm = " ".join(str(q.question or "").strip().lower().split())
            key = (norm, tuple(str(o or "").strip().lower() for o in q.options),
                   str(q.correct_answer))
            if key in seen:
                raise ValueError(f"duplicate question in bank: {q.question[:60]}")
            seen.add(key)
        return qs


class ExtractedSkill(BaseModel):
    learning_objective: str = ""
    prerequisites: list[str] = Field(default_factory=list)
    misconceptions: list[str] = Field(default_factory=list)
    difficulty: Literal["easy", "medium", "hard"] = "medium"
    source_section_ids: list[str] = Field(default_factory=list)
    evidence_chunk_ids: list[str] = Field(default_factory=list)
    skill_id: str
    name: str = ""
    description: str = ""
    key_concepts: list[str] = Field(default_factory=list)
    # RAG provenance. Optional on the raw contract (app fills via
    # grounding.attach_skill_evidence); required on GroundedSkill.
    learning_objective: str = ""
    source_chunk_ids: list[str] = Field(default_factory=list)
    source_evidence: list[str] = Field(default_factory=list)

    @field_validator("skill_id")
    @classmethod
    def slugify(cls, v: str) -> str:
        import re

        slug = re.sub(r"[^a-z0-9]+", "_", v.lower()).strip("_")
        if not slug:
            raise ValueError("skill_id must not be empty")
        return slug

    @field_validator("name")
    @classmethod
    def _name_non_empty(cls, v: str) -> str:
        if not str(v or "").strip():
            raise ValueError("skill name must be non-empty")
        return str(v).strip()

    @field_validator("description")
    @classmethod
    def _desc_non_empty(cls, v: str) -> str:
        if not str(v or "").strip():
            raise ValueError("skill description must be non-empty")
        return str(v).strip()


class SkillList(BaseModel):
    skills: list[ExtractedSkill]

    @field_validator("skills")
    @classmethod
    def _unique_ids(cls, skills):
        seen: set[str] = set()
        for s in skills:
            if s.skill_id in seen:
                raise ValueError(f"duplicate skill_id in list: {s.skill_id}")
            seen.add(s.skill_id)
        return skills


class GroundedSkill(ExtractedSkill):
    """Strict post-retrieval contract: every accepted skill carries RAG evidence.

    Raw LLM output is validated as ExtractedSkill first, enriched with
    grounding.attach_skill_evidence (same chunks, no re-retrieval), then
    validated here. Missing/empty grounding fields are schema failures.
    """

    learning_objective: str = Field(min_length=10)
    source_chunk_ids: list[str] = Field(min_length=1)
    source_evidence: list[str] = Field(min_length=1)

    @field_validator("learning_objective")
    @classmethod
    def _lo_non_empty(cls, v: str) -> str:
        if not str(v or "").strip():
            raise ValueError("learning_objective must be non-empty")
        return str(v).strip()

    @field_validator("source_chunk_ids")
    @classmethod
    def _refs_non_empty(cls, v: list[str]) -> list[str]:
        cleaned = [str(c or "").strip() for c in (v or []) if str(c or "").strip()]
        if not cleaned:
            raise ValueError("source_chunk_ids must contain at least one chunk id")
        return cleaned

    @field_validator("source_evidence")
    @classmethod
    def _ev_non_empty(cls, v: list[str]) -> list[str]:
        cleaned = [str(e or "").strip() for e in (v or []) if str(e or "").strip()]
        if not cleaned:
            raise ValueError("source_evidence must contain at least one evidence snippet")
        return cleaned


class GroundedSkillList(BaseModel):
    skills: list[GroundedSkill]

    @field_validator("skills")
    @classmethod
    def _unique_ids(cls, skills):
        seen: set[str] = set()
        for s in skills:
            if s.skill_id in seen:
                raise ValueError(f"duplicate skill_id in grounded list: {s.skill_id}")
            seen.add(s.skill_id)
        return skills


class GroundedQuestion(GeneratedQuestion):
    """Strict post-retrieval contract: Question -> Skill -> RAG evidence."""

    explanation: str = Field(min_length=1)
    source_chunk_ids: list[str] = Field(min_length=1)
    source_evidence: list[str] = Field(min_length=1)

    @field_validator("explanation")
    @classmethod
    def _expl_required(cls, v: str) -> str:
        if not str(v or "").strip():
            raise ValueError("explanation is required for grounded questions")
        return str(v).strip()

    @field_validator("source_chunk_ids")
    @classmethod
    def _refs_required(cls, v: list[str]) -> list[str]:
        cleaned = [str(c or "").strip() for c in (v or []) if str(c or "").strip()]
        if not cleaned:
            raise ValueError("source_chunk_ids is required for grounded questions")
        return cleaned

    @field_validator("source_evidence")
    @classmethod
    def _ev_required(cls, v: list[str]) -> list[str]:
        cleaned = [str(e or "").strip() for e in (v or []) if str(e or "").strip()]
        if not cleaned:
            raise ValueError("source_evidence is required for grounded questions")
        return cleaned


class GroundedQuestionList(BaseModel):
    questions: list[GroundedQuestion]

    @field_validator("questions")
    @classmethod
    def _no_duplicates(cls, qs):
        # Same exact-duplicate rule as QuestionList (rotation variants allowed).
        seen: set[tuple] = set()
        for q in qs:
            norm = " ".join(str(q.question or "").strip().lower().split())
            key = (norm, tuple(str(o or "").strip().lower() for o in q.options),
                   str(q.correct_answer))
            if key in seen:
                raise ValueError(f"duplicate question in grounded bank: {q.question[:60]}")
            seen.add(key)
        return qs


class SubmittedAnswers(BaseModel):
    """Strict boundary for student answer submission (assessment submit)."""

    answers: dict[str, int | str]

    @field_validator("answers")
    @classmethod
    def _validate_answers(cls, v: dict) -> dict:
        if not isinstance(v, dict) or not v:
            raise ValueError("answers must be a non-empty mapping of question_id -> answer")
        if len(v) > 200:
            raise ValueError("too many answers in one submission")
        for k, ans in v.items():
            if not str(k or "").strip():
                raise ValueError("answer keys (question ids) must be non-empty")
            if isinstance(ans, bool):
                raise ValueError(f"answer for {k!r} must be int 0-3 or non-empty string")
            if isinstance(ans, int):
                if not (0 <= ans <= 3):
                    raise ValueError(f"MCQ answer for {k!r} must be 0-3")
            elif isinstance(ans, str):
                if not ans.strip():
                    raise ValueError(f"answer for {k!r} must be non-empty")
            else:
                raise ValueError(f"answer for {k!r} must be int 0-3 or string")
        return v


class EvaluationRecord(BaseModel):
    """Structured per-question evaluation result (agent boundary)."""

    question_id: str = Field(min_length=1)
    correct: bool
    student_answer: int | str | None = None
    correct_answer: int | str
    skill_id: str = "general"


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
    # Pedagogical relevance: False for metadata/trivia questions even when grounded.
    # Defaults True so older LLM outputs without this field keep working.
    relevant: bool = True
    issue: str = ""


class CritiqueResult(BaseModel):
    verdicts: list[CritiqueVerdict]
