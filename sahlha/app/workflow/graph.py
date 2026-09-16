"""Teacher content pipeline as a LangGraph StateGraph.

```text
retrieve → extract_skills → explain_lesson → generate_banks → teacher_review
                                                                    │
                                                             (interrupt: pause
                                                              for teacher)
                                                                    ↓
                                                            apply_decision
                                                              ↙        ↘
                                                    reject+retries   approve/done
                                                      left → generate    → END
```

`teacher_review` pauses via `interrupt()` — the run's checkpoint persists the
full state, so the teacher can decide minutes later and `decide()` resumes the
same run (regeneration reuses prior feedback automatically).
"""
from __future__ import annotations

from langgraph.checkpoint.memory import MemorySaver
from langgraph.graph import END, START, StateGraph

from sahlha.app.workflow import nodes as N
from sahlha.app.workflow.state import MAX_REGENERATIONS, SahlhaWorkflowState

_checkpointer = MemorySaver()
_graph = None


def _route_start(state: SahlhaWorkflowState) -> str:
    # Empty material fails fast with status=failed instead of running the pipeline.
    if state.get("status") == "failed":
        return "failed"
    return "extract"


def _route_apply(state: SahlhaWorkflowState) -> str:
    decision = state.get("teacher_decision") or {}
    if decision.get("action") == "approve":
        return "done"
    if state.get("regeneration_attempts", 0) >= MAX_REGENERATIONS:
        return "exhausted"
    return "regenerate"


def _mark_exhausted(state: SahlhaWorkflowState) -> dict:
    return {"status": "needs_teacher",
            "trace": [{"event": "workflow:regeneration_exhausted",
                       "detail": {"attempts": state.get("regeneration_attempts", 0),
                                  "max": MAX_REGENERATIONS}}]}


def build_graph():
    builder = StateGraph(SahlhaWorkflowState)
    builder.add_node("retrieve", N.retrieve_node)
    builder.add_node("extract_skills", N.extract_node)
    builder.add_node("explain_lesson", N.lesson_node)
    builder.add_node("generate_banks", N.generate_node)
    builder.add_node("teacher_review", N.teacher_review_node)
    builder.add_node("apply_decision", N.apply_decision_node)
    builder.add_node("mark_exhausted", _mark_exhausted)

    builder.add_edge(START, "retrieve")
    builder.add_conditional_edges("retrieve", _route_start,
                                  {"extract": "extract_skills", "failed": END})
    builder.add_edge("extract_skills", "explain_lesson")
    builder.add_edge("explain_lesson", "generate_banks")
    builder.add_edge("generate_banks", "teacher_review")
    builder.add_edge("teacher_review", "apply_decision")
    builder.add_conditional_edges("apply_decision", _route_apply,
                                  {"regenerate": "generate_banks",
                                   "done": END,
                                   "exhausted": "mark_exhausted"})
    builder.add_edge("mark_exhausted", END)
    return builder.compile(checkpointer=_checkpointer)


def get_graph():
    global _graph
    if _graph is None:
        _graph = build_graph()
    return _graph


def checkpointer() -> MemorySaver:
    return _checkpointer
