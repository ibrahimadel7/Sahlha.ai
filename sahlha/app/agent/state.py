"""Explicit typed agent state. Serializable; not just conversation history."""
from __future__ import annotations

from enum import Enum
from typing import Any

from pydantic import BaseModel, Field


class Phase(str, Enum):
    SKILL_EXTRACTION = "SKILL_EXTRACTION"
    SKILL_EXPLANATION = "SKILL_EXPLANATION"
    LESSON_EXPLANATION = "LESSON_EXPLANATION"
    QUESTION_GENERATION = "QUESTION_GENERATION"
    WAITING_FOR_TEACHER = "WAITING_FOR_TEACHER"
    ASSESSMENT = "ASSESSMENT"
    EVALUATION = "EVALUATION"
    ADAPTATION = "ADAPTATION"


class AgentState(BaseModel):
    student_id: str = ""
    teacher_id: str = "teacher_1"
    course_id: str = "general"
    lesson_id: str = "lesson_1"
    skill_id: str = "general"

    current_phase: Phase = Phase.QUESTION_GENERATION

    retrieved_context: list[dict[str, Any]] = Field(default_factory=list)

    skills: list[dict[str, Any]] = Field(default_factory=list)  # extracted lesson skills

    current_question_ids: list[str] = Field(default_factory=list)
    current_answers: dict[str, Any] = Field(default_factory=dict)

    student_memory: dict[str, Any] = Field(default_factory=dict)
    assessment_result: dict[str, Any] = Field(default_factory=dict)

    # Debug trace: every tool call + agent decision (surfaced in the Debug tab)
    trace: list[dict[str, Any]] = Field(default_factory=list)

    def log(self, event: str, detail: Any = None) -> None:
        self.trace.append({"event": event, "detail": detail})

    def transition(self, to: Phase) -> None:
        """Validated phase transition: sets current_phase + logs it once."""
        self.current_phase = to
        self.log("phase", to.value if isinstance(to, Phase) else to)

    model_config = {"use_enum_values": True}
