"""LangGraph workflow state for the Sahlha teacher content pipeline.

Only JSON-serializable metadata lives here (ids, counts, statuses, decisions) —
never DB sessions, ORM rows, or full chunk texts. Heavy work (retrieval, LLM,
persistence) stays in the existing agent/tools/services layers; the graph only
orchestrates them and persists *decisions* across the human-in-the-loop pause.
"""
from __future__ import annotations

import operator
from typing import Annotated, Any, Literal

from typing_extensions import TypedDict


class SahlhaWorkflowState(TypedDict, total=False):
    # --- run inputs (set once at launch) ---
    course_id: str
    lesson_id: str
    teacher_feedback: str
    n_questions: int
    max_skills: int
    force: bool
    include_media: bool

    # --- pipeline metadata (filled by nodes) ---
    num_chunks: int
    skills: list[dict[str, Any]]  # [{skill_id, name, has_explanation}]
    lesson: dict[str, Any] | None  # {lesson_id, title, has_explanation}
    banks: list[dict[str, Any]]  # [{question_bank_id, skill_id, version, status, num_questions, backend}]

    # --- teacher gate ---
    teacher_decision: dict[str, Any]  # {action: approve|reject, feedback: str}
    regeneration_attempts: int

    # --- run bookkeeping ---
    status: str  # running | waiting_for_teacher | approved | needs_teacher | failed
    error: str
    trace: Annotated[list[dict[str, Any]], operator.add]


WorkflowStatus = Literal["running", "waiting_for_teacher", "approved", "needs_teacher", "failed"]

MAX_REGENERATIONS = 3


def initial_state(*, course_id: str, lesson_id: str, teacher_feedback: str = "",
                  n_questions: int = 10, max_skills: int = 6,
                  force: bool = False, include_media: bool = False) -> SahlhaWorkflowState:
    return {
        "course_id": course_id,
        "lesson_id": lesson_id,
        "teacher_feedback": teacher_feedback or "",
        "n_questions": n_questions,
        "max_skills": max_skills,
        "force": force,
        "include_media": include_media,
        "num_chunks": 0,
        "skills": [],
        "lesson": None,
        "banks": [],
        "teacher_decision": {},
        "regeneration_attempts": 0,
        "status": "running",
        "error": "",
        "trace": [{"event": "workflow:start",
                   "detail": {"course_id": course_id, "lesson_id": lesson_id}}],
    }
