"""Platform business logic: materials, learning path, help, progress, analytics.

Thin routes call into here; the AI loop itself stays in agent/tools/services.
"""
from __future__ import annotations
from sahlha.app.agent.tools import audio_tools, image_tools

from sqlalchemy.orm import Session

from sahlha.app.agent.agent import SahlhaAgent
from sahlha.app.agent.state import AgentState
from sahlha.app.agent.tools import question_tools, quality_tools
from sahlha.app.config import settings
from sahlha.app.database import models as m
from sahlha.app.database.repositories import platform as prepo
from sahlha.app.database.repositories import repositories as repo
from sahlha.app.rag import ingestion
from sahlha.app.services import mapping, mastery, profiles
from sahlha.app.services import services as legacy


# ---------------------------------------------------------------- materials
ALLOWED_EXTS = {e.strip() for e in settings.allowed_extensions.split(",") if e.strip()}


def validate_upload(filename: str, size: int) -> str:
    suffix = "." + filename.rsplit(".", 1)[-1].lower() if "." in filename else ""
    if suffix not in ALLOWED_EXTS:
        raise ValueError(f"Unsupported file type '{suffix or '?'}'. "
                         f"Supported: {', '.join(sorted(ALLOWED_EXTS))}")
    if size <= 0:
        raise ValueError("The file is empty.")
    if size > settings.max_upload_mb * 1024 * 1024:
        raise ValueError(f"File is larger than {settings.max_upload_mb} MB.")
    return suffix


def create_material_record(db: Session, *, uploader: m.User, title: str, filename: str,
                           classroom_id: str | None = None,
                           child_student_id: str | None = None) -> m.LearningMaterial:
    if uploader.role == "teacher":
        if not classroom_id:
            raise ValueError("classroom_id is required for teacher uploads")
        room = prepo.get_classroom(db, classroom_id)
        if room is None or room.teacher_id != uploader.id:
            raise ValueError("Classroom not found")
        return prepo.create_material(db, uploader_id=uploader.id, source_type="teacher",
                                     scope="official", title=title or filename,
                                     original_filename=filename, classroom_id=classroom_id)
    if uploader.role == "parent":
        if not child_student_id:
            raise ValueError("child_student_id is required for parent uploads")
        if not prepo.is_linked(db, uploader.id, child_student_id):
            raise ValueError("Child not found")
        return prepo.create_material(db, uploader_id=uploader.id, source_type="parent",
                                     scope="supplementary", title=title or filename,
                                     original_filename=filename,
                                     child_student_id=child_student_id)
    raise ValueError("Only teachers and parents can upload materials")


def process_material(db: Session, mat: m.LearningMaterial, file_bytes: bytes, *, background_tasks=None) -> dict:
    """Run OCR/RAG ingestion for a platform material (uses the existing pipeline)."""
    course_id, lesson_id = mapping.scope_for_material(mat)
    prepo.set_material_status(db, mat, "processing")
    try:
        result = ingestion.ingest_upload(
            db, file_bytes=file_bytes, filename=mat.original_filename or "upload",
            course_id=course_id, lesson_id=lesson_id, skill_id="general",
            defer_index=background_tasks is not None)
    except Exception as exc:
        db.rollback()
        prepo.set_material_status(db, mat, "failed", f"Could not read this file: {exc}")
        raise ValueError(f"Could not read this file: {exc}")
    if result.get("chunk_count", 0) == 0:
        method = str(result.get("method", ""))
        if method.startswith(("ocr:unavailable", "ocr:failed")):
            message = "This scan needs text recognition (OCR), which is unavailable or timed out. Try a searchable PDF or a smaller scan."
            prepo.set_material_status(db, mat, "failed", message)
            raise ValueError(message)
        prepo.set_material_status(db, mat, "failed",
                                  "No readable text was found. The file may be empty or unsupported.")
        raise ValueError("No readable text was found. The file may be empty or unsupported.")
    method = str(result.get("method", ""))
    if method.startswith("ocr:unavailable") or method.startswith("ocr:failed"):
        mat.document_id = result["document_id"]
        prepo.set_material_status(db, mat, "failed",
                                  "This scan needs text recognition (OCR), which is unavailable right now.")
        raise ValueError("This scan needs text recognition (OCR), which is unavailable right now.")
    mat.document_id = result["document_id"]
    mat.quality_signals = quality_tools.lesson_quality(db, course_id, lesson_id)
    db.commit()
    if not mat.title or mat.title == mat.original_filename or mat.title.lower() in {"lesson", "upload", "document", "untitled"}:
        mat.title = result["title"]
    if background_tasks is None:
        prepo.set_material_status(db, mat, "processed")
    else:
        prepo.set_material_status(db, mat, "processing", "Indexing lesson content")
        background_tasks.add_task(index_material, db.get_bind(), mat.id)
    return result


def extract_material_skills(db: Session, mat: m.LearningMaterial, *, force: bool = False) -> dict:
    if mat.processing_status not in {"processed", "skills_ready", "banks_ready"}:
        raise ValueError("Material processing must finish before extracting skills")
    course_id, lesson_id = mapping.scope_for_material(mat)
    out = legacy.extract_skills(db, course_id=course_id, lesson_id=lesson_id, force=force)
    mat.quality_signals = quality_tools.lesson_quality(db, course_id, lesson_id)
    prepo.set_material_status(db, mat, "skills_ready", f"{len(out['skills'])} skills")
    return out


def generate_material_banks(db: Session, mat: m.LearningMaterial, *, teacher: m.User,
                            teacher_feedback: str = "", n_questions: int = 10) -> dict:
    """One bank per skill; stamps platform ownership on each new bank."""
    if mat.processing_status not in {"processed", "skills_ready", "banks_ready"}:
        raise ValueError("Material processing must finish before generating questions")
    course_id, lesson_id = mapping.scope_for_material(mat)
    before = {b.id for b in repo.list_banks(db, lesson_id=lesson_id)}
    out = legacy.generate_lesson_banks(db, course_id=course_id, lesson_id=lesson_id,
                                       teacher_feedback=teacher_feedback,
                                       n_questions=n_questions)
    for b in repo.list_banks(db, lesson_id=lesson_id):
        if b.id not in before and mat.scope == "official":
            b.teacher_id = teacher.id
            b.classroom_id = mat.classroom_id
            b.material_id = mat.id
    db.commit()
    mat.quality_signals = quality_tools.lesson_quality(db, course_id, lesson_id)
    generated = sum(b['num_questions'] for b in out['banks'])
    detail = f"Created {generated} questions for review."
    if any(b.get('shortfall', 0) for b in out['banks']):
        detail += " Some skills have fewer questions because their source content is short."
    skipped = out.get('skipped_skills', [])
    if skipped:
        names = ', '.join(s['name'] or s['skill_id'] for s in skipped)
        detail += f" No questions for: {names}. Re-extract skills or add more lesson content."
    prepo.set_material_status(db, mat, "banks_ready", detail)
    return out


def material_to_dict(db: Session, mat: m.LearningMaterial) -> dict:
    course_id, lesson_id = mapping.scope_for_material(mat)
    skills = repo.list_skills(db, course_id=course_id, lesson_id=lesson_id)
    banks = repo.list_banks(db, lesson_id=lesson_id)
    approved = sum(1 for b in banks if b.status == "approved")
    return {"id": mat.id, "title": mat.title, "filename": mat.original_filename,
            "scope": mat.scope, "source_type": mat.source_type,
            "classroom_id": mat.classroom_id, "child_student_id": mat.child_student_id,
            "status": mat.processing_status, "status_detail": mat.status_detail,
            "quality_signals": mat.quality_signals or {},
            "document_id": mat.document_id, "num_skills": len(skills),
            "num_banks": len(banks), "approved_banks": approved,
            "created_at": mat.created_at.isoformat() if mat.created_at else None}


# ------------------------------------------------------------------ skills
def skill_dict(db: Session, course_id: str, lesson_id: str, row) -> dict:
    banks = repo.scoped_banks(db, course_id=course_id, lesson_id=lesson_id, skill_id=row.skill_id)
    latest = repo.latest_approved_banks(db, course_id=course_id, lesson_id=lesson_id, skill_id=row.skill_id)
    approved = [b for b in banks if b.status == "approved"]
    pending = [b for b in banks if b.status == "pending_review"]
    latest_ids = {b.id for b in latest}
    latest_count = len(repo.get_latest_approved_questions(db, course_id=course_id, lesson_id=lesson_id, skill_id=row.skill_id))
    return {"id": row.id, "course_id": row.course_id, "lesson_id": row.lesson_id,
            "skill_id": row.skill_id, "name": row.name, "description": row.description,
            "explanation": row.explanation, "key_concepts": row.key_concepts or [],
            "has_image": image_tools.valid_image_file(row.image_path), "image_alt": row.image_alt or "",
            "has_audio": audio_tools.valid_audio_file(row.audio_path),
            "approved_questions": latest_count,
            "active_bank_ids": sorted(latest_ids),
            "bank_status": ("approved" if approved else "pending" if pending
                            else ("rejected" if banks else "none"))}


def update_skill(db: Session, row, **fields) -> dict:
    if any(key in fields and fields[key] is not None and fields[key] != getattr(row, key) for key in ("name", "explanation")):
        row.audio_path = ""
    for key in ("name", "description", "key_concepts", "explanation"):
        if key in fields and fields[key] is not None:
            setattr(row, key, fields[key])
    import datetime

    row.updated_at = datetime.datetime.utcnow()
    db.commit()
    db.refresh(row)
    return {"id": row.id, "skill_id": row.skill_id, "name": row.name,
            "description": row.description, "key_concepts": row.key_concepts or [],
            "explanation": row.explanation}


def delete_skill(db: Session, row) -> None:
    db.delete(row)
    db.commit()


# --------------------------------------------------------------- questions
def edit_question(db: Session, bank: m.QuestionBank, question_id: str, fields: dict) -> dict:
    if bank.status == "approved":
        raise ValueError("Approved bank history is preserved. Regenerate a new bank version before editing questions.")
    q = db.get(m.Question, question_id)
    if q is None or q.question_bank_id != bank.id:
        raise ValueError("Question not found")
    allowed = {"question_text", "options", "correct_answer", "explanation",
               "difficulty", "question_type"}
    repo.update_question(db, q, **{k: v for k, v in fields.items() if k in allowed and v is not None})
    return question_to_dict_teacher(q)


def remove_question(db: Session, bank: m.QuestionBank, question_id: str) -> dict:
    if bank.status == "approved":
        raise ValueError("Approved bank history is preserved. Regenerate a new bank version before editing questions.")
    q = db.get(m.Question, question_id)
    if q is None or q.question_bank_id != bank.id:
        raise ValueError("Question not found")
    repo.delete_question(db, q)
    return {"removed": question_id, "remaining": len(repo.get_questions(db, bank.id))}


def regenerate_question(db: Session, bank: m.QuestionBank, question_id: str,
                        feedback: str = "") -> dict:
    """Replace ONE question with a freshly generated one (stays pending review).

    Strictly evidence-scoped: uses the same skill_evidence() source logic as
    normal bank generation. Never widens skill -> lesson -> global silently.
    """
    from sahlha.app.agent.llm import generate_questions_llm
    from sahlha.app.agent.prompts import build_question_prompt
    from sahlha.app.agent.schemas import QuestionList
    from sahlha.app.agent.tools import content_tools

    if bank.status == "approved":
        raise ValueError("Approved bank history is preserved. Regenerate a new bank version before editing questions.")
    q = db.get(m.Question, question_id)
    if q is None or q.question_bank_id != bank.id:
        raise ValueError("Question not found")
    skill_row = repo.get_skill(db, course_id=bank.course_id, lesson_id=bank.lesson_id,
                               skill_id=bank.skill_id)
    objective = (skill_row.learning_objective if skill_row and skill_row.learning_objective
                 else f'Explain {bank.skill_id.replace("_", " ")}.')
    query = f"{bank.skill_id} {objective} {skill_row.name if skill_row else ''}".strip()
    chunks = content_tools.skill_evidence(db, course_id=bank.course_id, lesson_id=bank.lesson_id,
                                          skill_id=bank.skill_id, query=query, top_k=8)
    for chunk in chunks:
        chunk.setdefault('learning_objective', objective)
    if not chunks:
        raise ValueError("No source evidence is available within this skill scope. "
                         "Re-extract skills or upload more detailed lesson content.")
    # Strict scope assertion: every cited chunk must belong to the exact scope.
    for chunk in chunks:
        if not (chunk.get("course_id") == bank.course_id
                and chunk.get("lesson_id") == bank.lesson_id):
            raise ValueError("Evidence scope violation during regeneration.")
    reasons = repo.get_flag_reasons_for_skill(db, course_id=bank.course_id, lesson_id=bank.lesson_id, skill_id=bank.skill_id)
    if reasons:
        feedback += "\nPrevious teacher feedback to avoid:\n" + "\n".join(reasons)
    key_concepts = list(skill_row.key_concepts or []) if skill_row else []
    misconceptions = list(skill_row.misconceptions or []) if skill_row else []
    system, user = build_question_prompt(
        course_id=bank.course_id, lesson_id=bank.lesson_id, skill_id=bank.skill_id,
        context_chunks=chunks,
        feedback=feedback or "Generate a different question on the same skill.",
        n=3, objective=objective, key_concepts=key_concepts,
        misconceptions=misconceptions)
    generated, backend = generate_questions_llm(system, user, chunks, bank.skill_id, 3,
                                                feedback or "different question")
    from sahlha.app.agent.tools.critique_tools import critique_and_top_up
    generated, _ = critique_and_top_up(generated, chunks, bank.skill_id, 3, feedback)
    validated = QuestionList(questions=generated).questions
    record = validated[0].to_record()
    record["skill_id"] = bank.skill_id
    repo.update_question(db, q, **record)
    if bank.status != "pending_review":
        repo.set_bank_status(db, bank, "pending_review")
    return {"question": question_to_dict_teacher(q), "backend": backend}


def regenerate_bank(db: Session, bank: m.QuestionBank, *, teacher_feedback: str = "",
                    n_questions: int = 10) -> dict:
    """Create a NEW pending version of this bank (history preserved, never overwritten)."""
    agent = SahlhaAgent(db, AgentState())
    out = agent.generate_question_bank(course_id=bank.course_id, lesson_id=bank.lesson_id,
                                       skill_id=bank.skill_id,
                                       teacher_feedback=teacher_feedback or bank.teacher_feedback,
                                       n_questions=n_questions)
    new_bank = repo.get_bank(db, out["question_bank_id"])
    if new_bank is not None:
        new_bank.teacher_id = bank.teacher_id
        new_bank.classroom_id = bank.classroom_id
        new_bank.material_id = bank.material_id
        db.commit()
    return out


def question_to_dict_teacher(q: m.Question) -> dict:
    return {"id": q.id, "skill_id": q.skill_id, "type": q.question_type,
            "question": q.question_text, "options": q.options,
            "correct_answer": q.correct_answer, "explanation": q.explanation,
            "difficulty": q.difficulty}


def question_to_dict_student(q: dict) -> dict:
    """Strip correct answers — evaluation is server-side only."""
    return {k: q[k] for k in ("id", "bank_id", "skill_id", "type", "question",
                              "options", "difficulty") if k in q}


# ------------------------------------------------------------ learning path
def _attempts_by_skill(db: Session, student_id: str, course_id: str,
                       lesson_id: str) -> dict[str, list]:
    approved = repo.get_approved_questions(db, course_id=course_id, lesson_id=lesson_id)
    q_to_skill = {q.id: q.skill_id for q in approved}
    per_skill: dict[str, list] = {}
    for a in repo.get_attempts(db, student_id, limit=10000):
        skid = q_to_skill.get(a.question_id)
        if skid:
            per_skill.setdefault(skid, []).append(a)
    return per_skill


def skill_states_for_lesson(db: Session, *, student_id: str, course_id: str,
                            lesson_id: str) -> list[dict]:
    per_skill = _attempts_by_skill(db, student_id, course_id, lesson_id)
    perf_rows = {p.skill_id: p for p in repo.get_skill_performance(
        db, student_id, course_id=course_id, lesson_id=lesson_id)}
    # Readiness/counts use ONLY the latest active approved bank per skill.
    latest_questions = repo.get_latest_approved_questions(db, course_id=course_id, lesson_id=lesson_id)
    out = []
    for row in repo.list_skills(db, course_id=course_id, lesson_id=lesson_id):
        atts = per_skill.get(row.skill_id, [])
        correct = sum(1 for a in atts if a.correct)
        accuracy = (correct / len(atts)) if atts else None
        perf = perf_rows.get(row.skill_id)
        if perf is not None and perf.total_attempts:
            accuracy = perf.accuracy
            attempted = perf.total_attempts
        else:
            attempted = len(atts)
        usable = [q for q in latest_questions if q.skill_id == row.skill_id]
        bank_questions = len(usable)
        ready = bank_questions >= settings.assessment_num_questions
        out.append({"id": row.id, "skill_id": row.skill_id, "name": row.name,
                    "description": row.description, "explanation": bool(row.explanation),
                    "attempted": attempted, "correct": correct if not perf else perf.correct_attempts,
                    "accuracy": accuracy, "state": mastery.mastery_state(
                        attempted=attempted, accuracy=accuracy),
                    "exercise_ready": ready,
                    "bank_questions": bank_questions,
                    "practice_questions": settings.assessment_num_questions if ready else 0})
    return out


def learning_path(db: Session, *, student_id: str, classroom_id: str | None = None,
                  child_scope: bool = False) -> dict:
    """Ordered units (materials) -> skills with completed/current/upcoming/locked."""
    units: list[dict] = []
    if classroom_id:
        materials = prepo.list_classroom_materials(db, classroom_id)
        course_id = mapping.course_for_classroom(classroom_id)
    elif child_scope:
        materials = prepo.list_supplementary_materials(db, student_id)
        course_id = mapping.course_for_child(student_id)
    else:
        materials = []
        course_id = "general"
    for mat in materials:
        skills = skill_states_for_lesson(db, student_id=student_id, course_id=course_id,
                                         lesson_id=mat.id)
        units.append({"material_id": mat.id, "title": mat.title, "status": mat.processing_status,
                      "skills": skills,
                      "summary": mastery.summarize([s["state"] for s in skills])})
    # Current = first non-mastered skill with content ready; earlier units completed.
    current = None
    for unit in units:
        for skill in unit["skills"]:
            if skill["state"] != mastery.MASTERED and skill["exercise_ready"]:
                current = {"material_id": unit["material_id"], "skill_id": skill["skill_id"],
                           "name": skill["name"]}
                break
        if current:
            break
    if current is None:  # fall back to first skill that has an explanation to study
        for unit in units:
            for skill in unit["skills"]:
                if skill["state"] != mastery.MASTERED and skill["explanation"]:
                    current = {"material_id": unit["material_id"], "skill_id": skill["skill_id"],
                               "name": skill["name"]}
                    break
            if current:
                break
    all_states = [s["state"] for u in units for s in u["skills"]]
    return {"units": units, "current": current, "summary": mastery.summarize(all_states),
            "total_skills": len(all_states),
            "mastered": sum(1 for s in all_states if s == mastery.MASTERED)}


def skill_bundle(db: Session, *, student_id: str, course_id: str, lesson_id: str,
                 skill_id: str) -> dict:
    row = repo.get_skill(db, course_id=course_id, lesson_id=lesson_id, skill_id=skill_id)
    if row is None:
        raise ValueError("Skill not found")
    skills = repo.list_skills(db, course_id=course_id, lesson_id=lesson_id)
    idx = next((i for i, s in enumerate(skills) if s.skill_id == skill_id), 0)
    states = {s["skill_id"]: s for s in skill_states_for_lesson(
        db, student_id=student_id, course_id=course_id, lesson_id=lesson_id)}
    prof = prepo.get_profile(db, student_id)
    explanation = row.explanation or ""
    # Light presentation adaptation from the profile (short + calm by default).
    if prof is not None and prof.reading_support == "short_chunks_audio":
        explanation = _shorten(explanation)
    learning_content = row.learning_content or {}
    visual_type = (learning_content.get("visual_type") or "none") if isinstance(learning_content, dict) else "none"
    visual_spec = (learning_content.get("visual_spec") or {}) if isinstance(learning_content, dict) else {}
    playground = (learning_content.get("playground") or {}) if isinstance(learning_content, dict) else {}
    return {"skill_id": row.skill_id, "name": row.name, "description": row.description,
            "explanation": explanation, "key_concepts": row.key_concepts or [],
            "learning_objective": row.learning_objective or "",
            "prerequisites": row.prerequisites or [],
            "misconceptions": row.misconceptions or [],
            "difficulty": row.difficulty or "",
            "source_section_ids": row.source_section_ids or [],
            "evidence_chunk_ids": row.evidence_chunk_ids or [],
            "learning_content": learning_content,
            "visual_type": visual_type, "visual_spec": visual_spec, "playground": playground,
            "has_image": image_tools.valid_image_file(row.image_path), "image_alt": row.image_alt or "",
            "has_audio": audio_tools.valid_audio_file(row.audio_path),
            "position": idx + 1, "total": len(skills),
            "state": states.get(skill_id, {}).get("state", mastery.NOT_STARTED),
            "exercise_ready": states.get(skill_id, {}).get("exercise_ready", False),
            "help_order": profiles.help_order_for(prof)}


def _shorten(text: str, max_chars: int = 600) -> str:
    if len(text) <= max_chars:
        return text
    cut = text[:max_chars]
    for sep in (". ", ".\n", "\n"):
        i = cut.rfind(sep)
        if i > max_chars // 2:
            return cut[:i + 1].strip()
    return cut.strip() + "…"


# ------------------------------------------------------------------ help me
def help_for_skill(db: Session, *, student_id: str, course_id: str, lesson_id: str,
                   skill_id: str, kind: str) -> dict:
    """Progressive support: simpler -> example -> steps -> visual/word. Deterministic."""
    row = repo.get_skill(db, course_id=course_id, lesson_id=lesson_id, skill_id=skill_id)
    if row is None:
        raise ValueError("Skill not found")
    base = row.explanation or row.description or ""
    if kind == "simpler":
        profiles.record_support_signal(db, student_id, "simpler_helped")
        return {"kind": kind, "title": "A simpler way to see it",
                "body": _shorten(base, 420)}
    if kind == "steps":
        import re

        parts = [p.strip() for p in re.split(r"(?<=[.!?])\s+", base) if p.strip()][:5]
        steps = [f"Step {i + 1}: {p}" for i, p in enumerate(parts)] or [base]
        profiles.record_support_signal(db, student_id, "step_helped")
        return {"kind": kind, "title": "Broken into steps", "steps": steps}
    if kind == "example":
        profiles.record_support_signal(db, student_id, "example_helped")
        example = (row.description or "") + ("\n\n" + base[:400] if base else "")
        return {"kind": kind, "title": "An example first", "body": example.strip()}
    if kind == "visual":
        profiles.record_support_signal(db, student_id, "visual_helped")
        return {"kind": kind, "title": "Picture help",
                "has_image": image_tools.valid_image_file(row.image_path), "image_alt": row.image_alt or "",
            "has_audio": audio_tools.valid_audio_file(row.audio_path),
                "key_concepts": row.key_concepts or [],
                "body": "Look at the picture and the key ideas below, one at a time."}
    if kind == "word":
        return {"kind": kind, "title": "Explain a word",
                "body": "Pick a word from the lesson and ask your teacher — or try Read Aloud first.",
                "key_concepts": row.key_concepts or []}
    if kind == "read_aloud":
        profiles.record_support_signal(db, student_id, "audio_used")
        return {"kind": kind, "title": "Read aloud",
                "body": "Use the Read Aloud button to listen to this skill."}
    raise ValueError("Unknown help type")


# ---------------------------------------------------------------- assessments
def start_platform_assessment(db: Session, *, student: m.User, classroom_id: str | None,
                              material_id: str | None, skill_id: str | None,
                              child_scope: bool = False, checkpoint: bool = False) -> dict:
    from sahlha.app.database.repositories import repositories as r

    r.get_or_create_student(db, student.id, student.name)
    course_id = lesson_id = None
    if material_id:
        mat = prepo.get_material(db, material_id)
        if mat is None:
            raise ValueError("Material not found")
        if mat.scope == "official":
            if not classroom_id or mat.classroom_id != classroom_id:
                raise ValueError("Material does not belong to this classroom")
            if not prepo.is_enrolled(db, classroom_id, student.id):
                raise PermissionError("Not enrolled in this classroom")
        elif mat.child_student_id != student.id:
            raise PermissionError("Not allowed")
        course_id, lesson_id = mapping.scope_for_material(mat)
    elif classroom_id:
        if not prepo.is_enrolled(db, classroom_id, student.id):
            raise PermissionError("Not enrolled in this classroom")
        course_id = mapping.course_for_classroom(classroom_id)
    elif child_scope:
        course_id = mapping.course_for_child(student.id)
    if not course_id:
        raise ValueError("Choose a classroom or material before starting practice")
    if checkpoint and (not material_id or skill_id):
        raise ValueError("Quick Checks require a material and mixed skills")
    out = legacy.start_assessment(db, student_id=student.id, student_name=student.name,
                                  course_id=course_id, lesson_id=lesson_id, skill_id=skill_id, learned_only=checkpoint)
    return {k: v for k, v in out.items() if k not in {"trace", "selection_meta"}}


def check_platform_answer(db: Session, *, student: m.User, assessment_id: str,
                          question_id: str, answer) -> dict:
    """Immediate per-question feedback: evaluate, LOCK the attempt, update memory.

    The attempt is recorded at check time, so revealing the explanation (and the
    correct option for MCQs) afterwards cannot inflate the final grade.
    """
    from sahlha.app.agent.tools import assessment_tools, student_tools

    assessment = repo.get_assessment(db, assessment_id)
    if assessment is None:
        raise ValueError("Assessment not found")
    if assessment.student_id != student.id:
        raise PermissionError("Not allowed")
    if assessment.status != "started":
        raise ValueError("This assessment is already finished")
    if question_id not in (assessment.question_ids or []):
        raise ValueError("Question is not part of this assessment")
    q = db.get(m.Question, question_id)
    if q is None:
        raise ValueError("Question not found")
    existing = repo.get_attempt_for(db, assessment_id, question_id)
    if existing is not None:
        return {"question_id": question_id, "correct": existing.correct,
                "explanation": q.explanation or "", "locked": True,
                "correct_answer": q.correct_answer
                if q.question_type == "multiple_choice" else None}
    res = assessment_tools.evaluate_answer(
        {"id": q.id, "skill_id": q.skill_id, "type": q.question_type,
         "correct_answer": q.correct_answer}, answer)
    assessment_tools.record_attempt(db, student_id=student.id, question_id=question_id,
                                    assessment_id=assessment_id, answer=answer,
                                    correct=res["correct"])
    bank = repo.get_bank(db, q.question_bank_id) if q.question_bank_id else None
    skill_row = (repo.get_skill(db, course_id=bank.course_id, lesson_id=bank.lesson_id,
                                skill_id=q.skill_id) if bank else None)
    student_tools.update_student_memory(
        db, student_id=student.id, skill_id=q.skill_id, correct=res["correct"],
        course_id=bank.course_id if bank else "",
        lesson_id=bank.lesson_id if bank else "",
        skill_row_id=skill_row.id if skill_row else None)
    if not res["correct"]:
        profiles.record_support_signal(db, student.id, "retry")
    return {"question_id": question_id, "correct": res["correct"],
            "explanation": q.explanation or "", "locked": True,
            "correct_answer": q.correct_answer
            if q.question_type == "multiple_choice" else None}


def submit_platform_assessment(db: Session, *, student: m.User, assessment_id: str,
                               answers: dict, support_signals: list[str] | None = None) -> dict:
    assessment = repo.get_assessment(db, assessment_id)
    if assessment is None:
        raise ValueError("Assessment not found")
    if assessment.student_id != student.id:
        raise PermissionError("Not allowed")
    out = legacy.submit_assessment(db, assessment_id=assessment_id, answers=answers)
    # Dynamic profile: repeated struggle vs improvement.
    results = out.get("results", [])
    wrong = sum(1 for r in results if not r.get("correct"))
    if wrong >= 3:
        profiles.record_support_signal(db, student.id, "struggled")
    elif out.get("score", 0) is not None and float(out.get("score") or 0) >= 0.8:
        profiles.record_support_signal(db, student.id, "improved")
    for sig in support_signals or []:
        # Filter defensively: grading/results must never break because of a
        # stray signal value (the dedicated endpoint validates strictly).
        if sig in profiles.KNOWN_SIGNALS:
            profiles.record_support_signal(db, student.id, sig)
    # Attach friendly mastery states only within this assessment scope.
    states: dict[str, str] = {}
    for row in repo.get_skill_performance(db, student.id, course_id=assessment.course_id or None,
                                         lesson_id=assessment.lesson_id or None):
        states[row.skill_id] = mastery.mastery_state(attempted=row.total_attempts,
                                                     accuracy=row.accuracy)
    out["mastery_states"] = states
    out["skills_needing_review"] = [skill for skill, state in states.items() if state == mastery.NEEDS_PRACTICE]
    return {k: v for k, v in out.items() if k not in {"trace", "selection_meta"}}


def student_grades(db: Session, student_id: str, classroom_id: str | None = None) -> list[dict]:
    from sqlalchemy import select

    q = select(m.Assessment).where(m.Assessment.student_id == student_id,
                                   m.Assessment.status == "submitted")
    rows = list(db.execute(q.order_by(m.Assessment.created_at.desc())).scalars().all())
    out = []
    for a in rows:
        bank = repo.get_bank(db, a.question_bank_id) if a.question_bank_id else None
        entry = {"id": a.id, "score": a.score, "num_questions": len(a.question_ids or []),
                 "created_at": a.created_at.isoformat() if a.created_at else None,
                 "course_id": a.course_id or (bank.course_id if bank else ""),
                 "lesson_id": a.lesson_id or (bank.lesson_id if bank else ""),
                 "skill_id": bank.skill_id if bank else "",
                 "classroom_id": mapping.classroom_id_from_course(a.course_id or (bank.course_id if bank else ""))}
        if classroom_id and entry["classroom_id"] != classroom_id:
            continue
        out.append(entry)
    return out


# ------------------------------------------------------------------ teacher
def classroom_mastery(db: Session, classroom_id: str) -> dict:
    students = prepo.list_enrolled_students(db, classroom_id)
    course_id = mapping.course_for_classroom(classroom_id)
    materials = prepo.list_classroom_materials(db, classroom_id)
    per_student = []
    skill_totals: dict[str, dict] = {}
    for s in students:
        states_all: list[str] = []
        per_skill = []
        for mat in materials:
            for sk in skill_states_for_lesson(db, student_id=s.id, course_id=course_id,
                                              lesson_id=mat.id):
                states_all.append(sk["state"])
                per_skill.append({"material_id": mat.id, "skill_id": sk["skill_id"],
                                  "name": sk["name"], "state": sk["state"],
                                  "accuracy": sk["accuracy"], "attempted": sk["attempted"]})
                agg = skill_totals.setdefault(sk["skill_id"], {"name": sk["name"],
                                                               "attempted": 0, "correct": 0,
                                                               "students": 0, "mastered": 0})
                agg["students"] += 1
                agg["attempted"] += sk["attempted"]
                if sk["state"] == mastery.MASTERED:
                    agg["mastered"] += 1
        grades = student_grades(db, s.id, classroom_id)
        per_student.append({"student_id": s.id, "name": s.name,
                            "summary": mastery.summarize(states_all),
                            "needs_support": mastery.NEEDS_PRACTICE in states_all,
                            "recent_score": grades[0]["score"] if grades else None,
                            "skills": per_skill})
    needing = [p for p in per_student if p["needs_support"]]
    skill_list = [{"skill_id": k, **v,
                   "mastery_rate": (v["mastered"] / v["students"]) if v["students"] else None}
                  for k, v in skill_totals.items()]
    skill_list.sort(key=lambda d: (d["mastery_rate"] is None, d["mastery_rate"] or 0))
    return {"classroom_id": classroom_id, "students": per_student,
            "needing_support": [{"student_id": p["student_id"], "name": p["name"]} for p in needing],
            "skill_performance": skill_list}


def student_progress_detail(db: Session, *, student_id: str, classroom_id: str) -> dict:
    course_id = mapping.course_for_classroom(classroom_id)
    materials = prepo.list_classroom_materials(db, classroom_id)
    units = []
    for mat in materials:
        skills = skill_states_for_lesson(db, student_id=student_id, course_id=course_id,
                                         lesson_id=mat.id)
        units.append({"material_id": mat.id, "title": mat.title, "skills": skills})
    prof = prepo.get_profile(db, student_id)
    grades = student_grades(db, student_id, classroom_id)
    attempts = repo.get_attempts(db, student_id, limit=20)
    return {"student_id": student_id, "units": units,
            "grades": grades[:10],
            "support_summary": profiles.support_summary(prof) if prof else [],
            "recent_activity": [{"question_id": a.question_id, "correct": a.correct,
                                 "timestamp": a.timestamp.isoformat() if a.timestamp else None}
                                for a in attempts]}


# ------------------------------------------------------------------- parent
def child_progress(db: Session, *, child_id: str) -> dict:
    rooms = prepo.list_student_classrooms(db, child_id)
    classrooms = []
    for room in rooms:
        course_id = mapping.course_for_classroom(room.id)
        skills_all = []
        for mat in prepo.list_classroom_materials(db, room.id):
            skills_all.extend(skill_states_for_lesson(db, student_id=child_id,
                                                      course_id=course_id, lesson_id=mat.id))
        grades = student_grades(db, child_id, room.id)
        classrooms.append({"classroom_id": room.id, "name": room.name, "subject": room.subject,
                           "summary": mastery.summarize([s["state"] for s in skills_all]),
                           "skills": skills_all,
                           "recent_score": grades[0]["score"] if grades else None})
    supp = prepo.list_supplementary_materials(db, child_id)
    supp_states: list[str] = []
    for mat in supp:
        supp_states.extend(s["state"] for s in skill_states_for_lesson(
            db, student_id=child_id, course_id=mapping.course_for_child(child_id),
            lesson_id=mat.id))
    attempts = repo.get_attempts(db, child_id, limit=20)
    return {"student_id": child_id, "classrooms": classrooms,
            "supplementary_summary": mastery.summarize(supp_states),
            "recent_activity": [{"question_id": a.question_id, "correct": a.correct,
                                 "timestamp": a.timestamp.isoformat() if a.timestamp else None}
                                for a in attempts]}


def bank_to_dict_teacher(db: Session, bank: m.QuestionBank) -> dict:
    return {"id": bank.id, "course_id": bank.course_id, "lesson_id": bank.lesson_id,
            "skill_id": bank.skill_id, "version": bank.version, "status": bank.status,
            "feedback": bank.teacher_feedback, "classroom_id": bank.classroom_id,
            "material_id": bank.material_id, "teacher_id": bank.teacher_id,
            "questions": [question_to_dict_teacher(q) for q in repo.get_questions(db, bank.id)]}


def teacher_overview(db: Session, teacher_id: str) -> dict:
    rooms = prepo.list_teacher_classrooms(db, teacher_id)
    total_students = 0
    materials_count = 0
    pending = 0
    needing: list[dict] = []
    for room in rooms:
        students = prepo.list_enrolled_students(db, room.id)
        total_students += len(students)
        materials_count += len(prepo.list_classroom_materials(db, room.id))
        pending += len(repo.list_banks(db, status="pending_review", classroom_id=room.id))
        mdata = classroom_mastery(db, room.id)
        for p in mdata["needing_support"]:
            needing.append({"classroom_id": room.id, "classroom_name": room.name, **p})
    return {"classrooms": [{"id": r.id, "name": r.name, "subject": r.subject,
                            "grade_level": r.grade_level, "join_code": r.join_code} for r in rooms],
            "num_classrooms": len(rooms), "num_students": total_students,
            "num_materials": materials_count, "pending_banks": pending,
            "needing_support": needing[:20]}


def index_material(bind, material_id: str):
    """Worker owns a fresh session; status becomes processed only after indexing."""
    from sahlha.app.rag.vectorstore import rebuild_index
    with Session(bind=bind) as db:
        mat = prepo.get_material(db, material_id)
        if mat is None:
            return
        try:
            rebuild_index(db)
            prepo.set_material_status(db, mat, "processed")
        except Exception:
            db.rollback()
            prepo.set_material_status(db, mat, "failed", "Indexing failed. Please process this material again.")


def flag_bank_question(db, bank, question_id, reason, teacher_id):
    question = repo.get_question(db, question_id)
    if question is None or question.question_bank_id != bank.id:
        raise ValueError("Question not found")
    flag = repo.flag_question(db, question_id, reason, teacher_id)
    return {"id": flag.id, "question_id": flag.question_id, "kind": flag.kind, "reason": flag.reason}


def bank_flags(db, bank):
    return [{"id": f.id, "question_id": f.question_id, "kind": f.kind, "reason": f.reason,
             "created_at": f.created_at.isoformat()} for f in repo.list_flags(db, bank_id=bank.id)]


def study_bundle(db, *, course_id, lesson_id):
    from collections import Counter
    from sahlha.app.agent.tools.skill_tools import serialize_skill
    from sahlha.app.agent.tools.explanation_tools import serialize_lesson
    lesson, skills, banks, questions = repo.study_rows(db, course_id=course_id, lesson_id=lesson_id)
    counts = Counter(q.question_bank_id for q in questions)
    out = []
    for skill in skills:
        own = [b for b in banks if b.skill_id == skill.skill_id]
        out.append({**serialize_skill(skill), "exercise_ready": bool(own) and all(
            counts[b.id] >= settings.assessment_num_questions for b in own),
            "approved_questions": sum(counts[b.id] for b in own)})
    return {"lesson": serialize_lesson(lesson) if lesson else None, "skills": out}
