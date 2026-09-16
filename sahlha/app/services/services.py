"""Business logic lives here; routes stay thin. All DB writes happen here."""
from __future__ import annotations

from sqlalchemy.orm import Session

from sahlha.app.agent.agent import SahlhaAgent
from sahlha.app.agent.state import AgentState
from sahlha.app.agent.tools import question_tools
from sahlha.app.database.repositories import repositories as repo
from sahlha.app.rag import ingestion


def upload_and_process(db: Session, *, file_bytes: bytes, filename: str,
                       course_id: str, lesson_id: str, skill_id: str,
                       eager: bool = True) -> dict:
    return ingestion.ingest_upload(db, file_bytes=file_bytes, filename=filename,
                                   course_id=course_id, lesson_id=lesson_id,
                                   skill_id=skill_id, eager=eager)


def generate_bank(db: Session, *, course_id: str, lesson_id: str, skill_id: str,
                  teacher_feedback: str = "", n_questions: int = 8) -> dict:
    agent = SahlhaAgent(db, AgentState())
    return agent.generate_question_bank(course_id=course_id, lesson_id=lesson_id, skill_id=skill_id,
                                        teacher_feedback=teacher_feedback, n_questions=n_questions)


def extract_skills(db: Session, *, course_id: str, lesson_id: str,
                   n_skills: int | None = None, max_skills: int = 6, force: bool = False,
                   include_media: bool = False) -> dict:
    """Agent splits the lesson into skills AND writes an explanation per skill.

    Also ensures the whole-lesson overview explanation exists.

    Media (audio/images) is deferred by default: explanations are persisted
    immediately and media generates lazily on demand via /audio + /images (both UIs
    already fetch media per skill when the student opens it). Pass
    include_media=True to block on media generation (used by media tests).
    """
    agent = SahlhaAgent(db, AgentState())
    out = agent.extract_skills(course_id=course_id, lesson_id=lesson_id,
                               max_skills=n_skills if n_skills is not None else max_skills,
                               force=force)
    explained = agent.explain_skills(course_id=course_id, lesson_id=lesson_id,
                                     force=force or out.get("backend") != "existing",
                                     include_media=include_media)
    lesson = agent.explain_lesson(course_id=course_id, lesson_id=lesson_id, force=force,
                                  include_media=include_media)
    return {"skills": explained["skills"], "lesson": lesson["lesson"],
            "extraction_backend": out.get("backend"), "trace": lesson["trace"]}


def explain_lesson(db: Session, *, course_id: str, lesson_id: str, force: bool = False) -> dict:
    """Agent writes (or returns) the overview explanation for a whole lesson."""
    return SahlhaAgent(db, AgentState()).explain_lesson(course_id=course_id,
                                                        lesson_id=lesson_id, force=force)


def get_lesson(db: Session, *, course_id: str, lesson_id: str) -> dict:
    """Student-facing study bundle: lesson overview + per-skill explanations."""
    row = repo.get_lesson_explanation(db, course_id=course_id, lesson_id=lesson_id)
    return {"lesson": ({"id": row.id, "course_id": row.course_id, "lesson_id": row.lesson_id,
                        "title": row.title, "explanation": row.explanation,
                        "key_concepts": row.key_concepts or []} if row else None),
            "skills": list_skills(db, course_id=course_id, lesson_id=lesson_id)}


def _skill_has_audio(s) -> bool:
    from sahlha.app.agent.tools import audio_tools as _audio_tools

    try:
        return _audio_tools.has_cached_audio(
            _audio_tools.skill_audio_text(s.name or "", s.explanation or ""))
    except Exception:
        import os as _os

        return _os.path.exists(_audio_tools.expected_path(
            _audio_tools.skill_audio_text(s.name or "", s.explanation or "")))


def list_skills(db: Session, *, course_id: str, lesson_id: str,
                skill_id: str | None = None) -> list[dict]:
    rows = repo.list_skills(db, course_id=course_id, lesson_id=lesson_id)
    if skill_id:
        rows = [s for s in rows if s.skill_id == skill_id]
    return [{"id": s.id, "course_id": s.course_id, "lesson_id": s.lesson_id, "skill_id": s.skill_id,
             "name": s.name, "description": s.description, "explanation": s.explanation,
             "key_concepts": s.key_concepts or [], "has_image": bool(s.image_path),
             "image_alt": s.image_alt or "", "has_audio": _skill_has_audio(s)}
            for s in rows]


def generate_lesson_banks(db: Session, *, course_id: str, lesson_id: str,
                          teacher_feedback: str = "", n_questions: int = 10) -> dict:
    """One question bank (n_questions each) per skill of the lesson."""
    agent = SahlhaAgent(db, AgentState())
    return agent.generate_lesson_banks(course_id=course_id, lesson_id=lesson_id,
                                       teacher_feedback=teacher_feedback, n_questions=n_questions)


def approve_bank(db: Session, bank_id: str) -> dict:
    bank = repo.get_bank(db, bank_id)
    if not bank:
        raise ValueError("Question bank not found")
    repo.set_bank_status(db, bank, "approved")
    return {"id": bank.id, "status": "approved", "version": bank.version}


def reject_bank(db: Session, bank_id: str, feedback: str = "") -> dict:
    bank = repo.get_bank(db, bank_id)
    if not bank:
        raise ValueError("Question bank not found")
    repo.set_bank_status(db, bank, "rejected", feedback)
    return {"id": bank.id, "status": "rejected", "version": bank.version, "feedback": feedback}


def start_assessment(db: Session, *, student_id: str, student_name: str = "Student",
                     course_id: str | None = None, lesson_id: str | None = None,
                     skill_id: str | None = None) -> dict:
    sid = (student_id or "").strip()
    if not sid:
        raise ValueError("student_id is required")
    repo.get_or_create_student(db, sid, (student_name or "Student").strip() or "Student")
    agent = SahlhaAgent(db, AgentState())
    return agent.start_assessment(student_id=sid, course_id=course_id,
                                  lesson_id=lesson_id, skill_id=skill_id)


def submit_assessment(db: Session, *, assessment_id: str, answers: dict) -> dict:
    agent = SahlhaAgent(db, AgentState())
    return agent.submit_assessment(assessment_id=assessment_id, answers=answers)


def student_performance(db: Session, student_id: str, student_name: str = "Student") -> dict:
    sid = (student_id or "").strip()
    if not sid:
        raise ValueError("student_id is required")
    # Auto-create on first read so a fresh student_id never 404s in the
    # Student tab ("Load my skills" / "Load performance" run before any
    # assessment exists). Matches start_assessment's get-or-create behavior.
    student = repo.get_or_create_student(db, sid, (student_name or "Student").strip() or "Student")
    attempts = repo.get_attempts(db, sid)
    perf = repo.get_skill_performance(db, sid)
    return {
        "student_id": student.id, "name": student.name,
        "attempts": [{"question_id": a.question_id, "assessment_id": a.assessment_id,
                      "answer": a.answer, "correct": a.correct,
                      "timestamp": a.timestamp.isoformat()} for a in attempts],
        "failed_questions": [a.question_id for a in attempts if not a.correct],
        "skill_performance": [{"skill_id": p.skill_id, "total": p.total_attempts,
                               "correct": p.correct_attempts, "accuracy": p.accuracy} for p in perf],
    }


def pending_banks(db: Session, limit: int = 100) -> list[dict]:
    return [{"id": b.id, "course_id": b.course_id, "lesson_id": b.lesson_id,
             "skill_id": b.skill_id, "version": b.version, "status": b.status,
             "feedback": b.teacher_feedback,
             "num_questions": len(repo.get_questions(db, b.id))} for b in repo.list_banks(db, status="pending_review", limit=limit)]


def bank_detail(db: Session, bank_id: str) -> dict | None:
    return question_tools.get_question_bank(db, bank_id)


def flag_question(db: Session, *, question_id: str, reason: str = "") -> dict:
    """Teacher flags one question: excluded from future assessments, reason feeds regeneration."""
    try:
        fb = repo.flag_question(db, question_id=question_id, reason=reason)
    except ValueError as exc:
        raise ValueError(str(exc))
    return {"question_id": fb.question_id, "kind": fb.kind, "reason": fb.reason,
            "created_at": fb.created_at.isoformat()}


def list_flags(db: Session, limit: int = 100) -> list[dict]:
    return [{"question_id": f.question_id, "kind": f.kind, "reason": f.reason,
             "created_at": f.created_at.isoformat()} for f in repo.list_flags(db, limit)]


def skill_audio(db: Session, *, course_id: str, lesson_id: str,
                skill_id: str, voice: str | None = None) -> dict:
    from sahlha.app.agent.tools import audio_tools

    return audio_tools.skill_explanation_to_audio(db, course_id=course_id, lesson_id=lesson_id,
                                                  skill_id=skill_id, voice=voice)


def lesson_audio(db: Session, *, course_id: str, lesson_id: str,
                 voice: str | None = None) -> dict:
    from sahlha.app.agent.tools import audio_tools

    return audio_tools.lesson_explanation_to_audio(db, course_id=course_id,
                                                   lesson_id=lesson_id, voice=voice)


def skill_image(db: Session, *, course_id: str, lesson_id: str,
                skill_id: str, force: bool = False) -> dict:
    from sahlha.app.agent.tools import image_tools

    return image_tools.fetch_skill_image(db, course_id=course_id, lesson_id=lesson_id,
                                         skill_id=skill_id, force=force)


def list_students(db: Session, limit: int = 100) -> list[dict]:
    return [{"id": s.id, "name": s.name, "created_at": s.created_at.isoformat()} for s in repo.list_students(db, limit=limit)]


def list_courses(db: Session) -> list[str]:
    """Distinct course_ids that have any content (for catalog dropdowns)."""
    return repo.list_courses(db)


def list_lessons(db: Session, course_id: str | None = None) -> list[dict]:
    """Distinct lessons, optionally filtered by course."""
    return repo.list_lessons(db, course_id=course_id)


def catalog_tree(db: Session) -> list[dict]:
    """Full tree: [{course_id, lessons: [...]}] for catalog dropdowns."""
    return [{"course_id": cid, "lessons": repo.list_lessons(db, course_id=cid)}
            for cid in repo.list_courses(db)]


# ---------- LangGraph teacher content workflow ----------
def run_content_workflow(db: Session, *, course_id: str, lesson_id: str,
                         teacher_feedback: str = "", n_questions: int = 10,
                         max_skills: int = 6, force: bool = False,
                         include_media: bool = False) -> dict:
    """Run the teacher content pipeline as a LangGraph workflow.

    Runs retrieve → extract → explain → generate, then pauses at the teacher
    gate (`interrupt`). Returns a snapshot including `thread_id`; the teacher
    resumes with `teacher_decide()`. Classic per-bank endpoints keep working
    on the same banks independently.
    """
    import uuid

    from sahlha.app.workflow import nodes as _nodes
    from sahlha.app.workflow.graph import get_graph
    from sahlha.app.workflow.state import initial_state

    course_id = (course_id or "").strip()
    lesson_id = (lesson_id or "").strip()
    if not course_id or not lesson_id:
        raise ValueError("course_id and lesson_id are required")
    thread_id = f"content:{course_id}:{lesson_id}:{uuid.uuid4().hex[:8]}"
    config = {"configurable": {"thread_id": thread_id}}
    token = _nodes._db.set(db)
    try:
        get_graph().invoke(initial_state(
            course_id=course_id, lesson_id=lesson_id,
            teacher_feedback=teacher_feedback or "", n_questions=n_questions,
            max_skills=max_skills, force=force, include_media=include_media), config)
    finally:
        _nodes._db.reset(token)
    return workflow_snapshot(db, thread_id=thread_id)


def workflow_snapshot(db: Session, *, thread_id: str) -> dict:
    """Current state of a workflow run (works paused, finished, or failed)."""
    from sahlha.app.workflow.graph import get_graph

    thread_id = (thread_id or "").strip()
    if not thread_id:
        raise ValueError("thread_id is required")
    config = {"configurable": {"thread_id": thread_id}}
    snap = get_graph().get_state(config)
    values = dict(snap.values or {})
    if not values:
        raise ValueError(f"Workflow {thread_id} not found")
    pending = list(snap.next or ())
    status = "waiting_for_teacher" if pending else values.get("status", "unknown")
    return {
        "thread_id": thread_id,
        "status": status,
        "waiting_on": pending,
        "course_id": values.get("course_id", ""),
        "lesson_id": values.get("lesson_id", ""),
        "num_chunks": values.get("num_chunks", 0),
        "skills": values.get("skills", []),
        "lesson": values.get("lesson"),
        "banks": values.get("banks", []),
        "teacher_decision": values.get("teacher_decision", {}),
        "regeneration_attempts": values.get("regeneration_attempts", 0),
        "error": values.get("error", ""),
        "trace": values.get("trace", []),
    }


def teacher_decide(db: Session, *, thread_id: str, action: str, feedback: str = "") -> dict:
    """Resume a paused workflow run with the teacher's approve/reject decision."""
    from langgraph.types import Command

    from sahlha.app.workflow import nodes as _nodes
    from sahlha.app.workflow.graph import get_graph

    thread_id = (thread_id or "").strip()
    if not thread_id:
        raise ValueError("thread_id is required")
    if action not in ("approve", "reject"):
        raise ValueError(f"action must be approve|reject, got {action!r}")
    config = {"configurable": {"thread_id": thread_id}}
    snap = get_graph().get_state(config)
    if not (snap.values or {}):
        raise ValueError(f"Workflow {thread_id} not found")
    if not snap.next:
        raise ValueError(f"Workflow {thread_id} is not waiting for a decision "
                         f"(status={snap.values.get('status', '?')})")
    token = _nodes._db.set(db)
    try:
        get_graph().invoke(Command(resume={"action": action, "feedback": feedback or ""}), config)
    finally:
        _nodes._db.reset(token)
    return workflow_snapshot(db, thread_id=thread_id)


def create_student(db: Session, *, student_id: str | None = None, name: str = "Student") -> dict:
    if not name or not name.strip():
        raise ValueError("Student name is required")
    name = name.strip()[:256]
    # Auto-generate id if not provided or empty
    sid = (student_id or "").strip() or None
    # If id provided and exists, return existing (idempotent for testing)
    if sid and repo.get_student(db, sid):
        s = repo.get_student(db, sid)
        return {"id": s.id, "name": s.name, "created_at": s.created_at.isoformat()}
    s = repo.get_or_create_student(db, student_id=sid, name=name)
    return {"id": s.id, "name": s.name, "created_at": s.created_at.isoformat()}


def skill_progress(db: Session, *, student_id: str, course_id: str, lesson_id: str,
                   student_name: str = "Student") -> dict:
    """Skill = explanation + exercise: per-skill study/exercise status for one student.

    completed = student has attempted at least one full 4-question exercise for the skill.
    Auto-creates unknown students so "Load my skills" works before the first assessment.
    """
    from sahlha.app.config import settings

    sid = (student_id or "").strip()
    if not sid:
        raise ValueError("student_id is required")
    student = repo.get_or_create_student(db, sid, (student_name or "Student").strip() or "Student")
    approved = repo.get_approved_questions(db, course_id=course_id, lesson_id=lesson_id)
    by_skill: dict[str, list] = {}
    for q in approved:
        by_skill.setdefault(q.skill_id, []).append(q)
    # Map the student's attempts onto skills via question -> bank -> skill.
    q_to_skill: dict[str, str] = {}
    for skill_id, questions in by_skill.items():
        for q in questions:
            q_to_skill[q.id] = skill_id
    per_skill_attempts: dict[str, list] = {}
    for a in repo.get_attempts(db, sid, limit=10000):
        skid = q_to_skill.get(a.question_id)
        if skid:
            per_skill_attempts.setdefault(skid, []).append(a)

    skills = []
    for s in repo.list_skills(db, course_id=course_id, lesson_id=lesson_id):
        atts = per_skill_attempts.get(s.skill_id, [])
        correct = sum(1 for a in atts if a.correct)
        bank_questions = len(by_skill.get(s.skill_id, []))
        skills.append({
            "skill_id": s.skill_id, "name": s.name, "description": s.description,
            "has_explanation": bool(s.explanation),
            "bank_questions": bank_questions,  # approved questions available
            "exercise_ready": bank_questions >= settings.assessment_num_questions,
            "attempted": len(atts), "correct": correct,
            "accuracy": (correct / len(atts)) if atts else None,
            "completed": len(atts) >= settings.assessment_num_questions,
            "needs_review": bool(atts) and (correct / len(atts)) < 0.5,  # feedback loop 3
        })
    done = sum(1 for s in skills if s["completed"])
    return {"student_id": student.id, "course_id": course_id, "lesson_id": lesson_id,
            "skills": skills, "completed": done, "total": len(skills)}
