"""Graph nodes: thin orchestration over the existing agent/tools/services layers.

Each node borrows the request's DB session from a ContextVar (set by the service
wrapper around `graph.invoke`, same thread — nodes never receive the session via
graph state because sessions are not serializable and must not enter checkpoints).

Nodes reuse `SahlhaAgent` exactly like `services/` does today, then project only
small JSON summaries into workflow state. No RAG/DB/LLM logic is duplicated here.
"""
from __future__ import annotations

from contextvars import ContextVar
from typing import Any

from sqlalchemy.orm import Session

_db: ContextVar[Session | None] = ContextVar("workflow_db", default=None)


def _db_session() -> Session:
    db = _db.get()
    if db is None:
        raise RuntimeError("Workflow invoked without a DB session (service bug)")
    return db


def _agent():
    from sahlha.app.agent.agent import SahlhaAgent
    from sahlha.app.agent.state import AgentState

    return SahlhaAgent(_db_session(), AgentState())


def retrieve_node(state: dict) -> dict:
    """Verify lesson material exists (stages below re-retrieve scoped context themselves)."""
    from sahlha.app.agent.tools import rag_tools

    db = _db_session()
    chunks = rag_tools.retrieve_lesson(db, state["course_id"], state["lesson_id"], top_k=5)
    if not chunks:
        return {"status": "failed",
                "error": (f"No material found for {state['course_id']}/{state['lesson_id']}. "
                          "Upload a document first."),
                "trace": [{"event": "workflow:retrieve_empty",
                           "detail": {"course_id": state["course_id"],
                                      "lesson_id": state["lesson_id"]}}]}
    return {"num_chunks": len(chunks),
            "trace": [{"event": "workflow:retrieved",
                       "detail": {"num_chunks": len(chunks)}}]}


def extract_node(state: dict) -> dict:
    """Extract skills + write per-skill explanations (reuses agent, incl. LLM fan-out)."""
    agent = _agent()
    out = agent.extract_skills(course_id=state["course_id"], lesson_id=state["lesson_id"],
                               max_skills=state.get("max_skills", 6),
                               force=state.get("force", False))
    explained = agent.explain_skills(course_id=state["course_id"], lesson_id=state["lesson_id"],
                                     force=state.get("force", False) or out.get("backend") != "existing",
                                     include_media=state.get("include_media", False))
    skills = [{"skill_id": s["skill_id"], "name": s.get("name", ""),
               "has_explanation": bool(s.get("explanation"))} for s in explained["skills"]]
    return {"skills": skills,
            "trace": [{"event": "workflow:extracted",
                       "detail": {"count": len(skills), "backend": out.get("backend")}}]}


def lesson_node(state: dict) -> dict:
    """Write the whole-lesson overview explanation."""
    agent = _agent()
    out = agent.explain_lesson(course_id=state["course_id"], lesson_id=state["lesson_id"],
                               force=state.get("force", False),
                               include_media=state.get("include_media", False))
    lesson = out["lesson"]
    return {"lesson": {"lesson_id": state["lesson_id"], "title": lesson.get("title", ""),
                       "has_explanation": bool(lesson.get("explanation"))},
            "trace": [{"event": "workflow:lesson_explained",
                       "detail": {"backend": out.get("backend")}}]}


def _bank_summary(b: dict) -> dict:
    return {"question_bank_id": b["question_bank_id"], "skill_id": b.get("skill_id", ""),
            "version": b.get("version", 1), "status": b.get("status", "pending_review"),
            "num_questions": b.get("num_questions", 0), "backend": b.get("backend", "")}


def generate_node(state: dict) -> dict:
    """Generate one bank per skill (parallel LLM fan-out inside the agent).

    Regeneration runs only regenerate non-approved skills: a skill whose latest
    bank is already approved keeps it (never silently supersede an approval).
    """
    from sahlha.app.agent.agent import SahlhaAgent
    from sahlha.app.agent.state import AgentState
    from sahlha.app.database.repositories import repositories as repo

    db = _db_session()
    course_id, lesson_id = state["course_id"], state["lesson_id"]
    attempts = state.get("regeneration_attempts", 0)
    feedback = state.get("teacher_feedback", "")
    if attempts and (dec := state.get("teacher_decision") or {}).get("feedback"):
        feedback = ((feedback + "\n" + dec["feedback"]).strip() if feedback
                    else dec["feedback"])

    if attempts:
        # Regeneration: keep approved skills untouched, rebuild the rest skill-by-skill
        # so approved banks are never superseded by a new pending version.
        kept = [b for b in state.get("banks", []) if b.get("status") == "approved"]
        kept_skills = {b["skill_id"] for b in kept}
        fresh: list[dict[str, Any]] = list(kept)
        redone: list[str] = []
        for skill in state.get("skills", []):
            skid = skill["skill_id"]
            if skid in kept_skills:
                continue
            agent = SahlhaAgent(db, AgentState())
            saved = agent.generate_question_bank(
                course_id=course_id, lesson_id=lesson_id, skill_id=skid,
                teacher_feedback=feedback, n_questions=state.get("n_questions", 10))
            saved["skill_id"] = skid
            fresh.append(_bank_summary(saved))
            redone.append(skid)
        # Refresh kept statuses (teacher may have approved via the classic endpoints mid-run).
        by_id = {b["question_bank_id"]: b for b in fresh}
        for bank in repo.list_banks(db, status="approved", limit=10000):
            if bank.id in by_id:
                by_id[bank.id]["status"] = "approved"
        return {"banks": fresh, "teacher_feedback": feedback,
                "trace": [{"event": "workflow:regenerated",
                           "detail": {"redone": redone, "kept": sorted(kept_skills),
                                      "attempt": attempts}}]}

    agent = SahlhaAgent(db, AgentState())
    out = agent.generate_lesson_banks(course_id=course_id, lesson_id=lesson_id,
                                      teacher_feedback=feedback,
                                      n_questions=state.get("n_questions", 10))
    banks = []
    for b in out["banks"]:
        # generate_lesson_banks returns per-skill payloads; recover skill from its trace/bank row.
        summary = _bank_summary(b)
        banks.append(summary)
    # Attach skill_ids from the skill list in order (generate_lesson_banks covers every skill).
    skill_ids = [s["skill_id"] for s in state.get("skills", [])] or \
        [s.skill_id for s in repo.list_skills(db, course_id=course_id, lesson_id=lesson_id)]
    for summary, skid in zip(banks, skill_ids):
        summary.setdefault("skill_id", skid)
        if not summary["skill_id"]:
            summary["skill_id"] = skid
    ordered = sorted(banks, key=lambda b: skill_ids.index(b["skill_id"]) if b["skill_id"] in skill_ids else 0)
    return {"banks": ordered,
            "trace": [{"event": "workflow:banks_generated",
                       "detail": {"count": len(ordered)}}]}


def teacher_review_node(state: dict) -> dict:
    """Human-in-the-loop gate: pause for a teacher approve/reject decision.

    On first execution raises `interrupt(...)` with the pending-bank summary.
    LangGraph re-executes this node on resume; the second run receives the
    teacher's decision as the interrupt's return value.
    """
    from langgraph.types import interrupt

    from sahlha.app.database.repositories import repositories as repo

    db = _db_session()
    # Fresh read: the teacher may have used the classic per-bank endpoints meanwhile.
    live: dict[str, str] = {}
    for b in state.get("banks", []):
        row = repo.get_bank(db, b["question_bank_id"])
        live[b["question_bank_id"]] = row.status if row else "missing"
    pending = [{"question_bank_id": bid, "skill_id": b.get("skill_id", ""),
                "version": b.get("version", 1), "status": live.get(bid, "?")}
               for b in state.get("banks", []) for bid in [b["question_bank_id"]]]

    decision = interrupt({
        "prompt": f"Approve or reject {len(pending)} question bank(s) "
                  f"for {state['course_id']}/{state['lesson_id']}?",
        "pending_banks": pending,
    })
    action = (decision or {}).get("action", "")
    feedback = (decision or {}).get("feedback", "")
    if action not in ("approve", "reject"):
        raise ValueError(f"Teacher decision must be approve|reject, got {action!r}")
    return {"teacher_decision": {"action": action, "feedback": feedback or ""},
            "status": "running",
            "trace": [{"event": "workflow:teacher_decision",
                       "detail": {"action": action}}]}


def apply_decision_node(state: dict) -> dict:
    """Enforce the teacher's decision via the same repo calls the classic endpoints use."""
    from sahlha.app.database.repositories import repositories as repo

    db = _db_session()
    decision = state.get("teacher_decision") or {}
    action = decision.get("action")
    feedback = decision.get("feedback", "")
    bank_ids = [b["question_bank_id"] for b in state.get("banks", [])]
    banks = list(state.get("banks", []))

    if action == "approve":
        approved: list[str] = []
        for b in banks:
            row = repo.get_bank(db, b["question_bank_id"])
            if row is None:
                continue
            if row.status != "approved":
                repo.set_bank_status(db, row, "approved")
            b["status"] = "approved"
            approved.append(b["question_bank_id"])
        return {"banks": banks, "status": "approved",
                "trace": [{"event": "workflow:approved", "detail": {"banks": approved}}]}

    # reject → mark this run's banks rejected (skip ones already approved elsewhere),
    # count the attempt; the router decides regenerate vs give up.
    attempts = state.get("regeneration_attempts", 0) + 1
    rejected: list[str] = []
    for b in banks:
        row = repo.get_bank(db, b["question_bank_id"])
        if row is None or row.status == "approved":
            continue
        repo.set_bank_status(db, row, "rejected", feedback)
        b["status"] = "rejected"
        rejected.append(b["question_bank_id"])
    return {"banks": banks, "regeneration_attempts": attempts, "status": "running",
            "trace": [{"event": "workflow:rejected",
                       "detail": {"banks": rejected, "attempt": attempts,
                                  "feedback": feedback[:200]}}]}
