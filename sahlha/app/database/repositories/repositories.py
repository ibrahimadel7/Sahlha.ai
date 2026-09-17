"""Repository helpers. Only place besides services that touches the ORM directly.

The agent/LLM must NEVER import these — it goes through tools.
"""
from __future__ import annotations

import datetime

from sqlalchemy import desc, select, update, func, or_
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, joinedload

from sahlha.app.database import models as m


def _utcnow() -> datetime.datetime:
    return datetime.datetime.now(datetime.timezone.utc)


# ---- Documents ----
def create_document(db: Session, *, filename: str, course_id: str, lesson_id: str, skill_id: str) -> m.Document:
    doc = m.Document(filename=filename, course_id=course_id, lesson_id=lesson_id, skill_id=skill_id)
    db.add(doc)
    db.commit()
    db.refresh(doc)
    return doc


def get_document(db: Session, doc_id: str) -> m.Document | None:
    return db.get(m.Document, doc_id)


def mark_document_processed(db: Session, doc: m.Document, *, char_count: int, chunk_count: int) -> None:
    doc.status = "processed"
    doc.char_count = char_count
    doc.chunk_count = chunk_count
    db.commit()


def add_chunks(db: Session, chunks: list[dict]) -> int:
    for c in chunks:
        db.add(m.DocumentChunk(**c))
    db.commit()
    return len(chunks)


def get_chunks(db: Session, *, course_id: str | None = None, lesson_id: str | None = None,
               skill_id: str | None = None, document_id: str | None = None) -> list[m.DocumentChunk]:
    q = select(m.DocumentChunk)
    if course_id is not None:
        q = q.where(m.DocumentChunk.course_id == course_id)
    if lesson_id is not None:
        q = q.where(m.DocumentChunk.lesson_id == lesson_id)
    if skill_id is not None:
        q = q.where(m.DocumentChunk.skill_id == skill_id)
    if document_id is not None:
        q = q.where(m.DocumentChunk.document_id == document_id)
    return list(db.execute(q.order_by(m.DocumentChunk.document_id, m.DocumentChunk.chunk_index)).scalars().all())


# ---- Lesson explanations ----
def upsert_lesson_explanation(db: Session, *, course_id: str, lesson_id: str,
                               title: str = "", explanation: str = "",
                               key_concepts: list | None = None,
                               category: str | None = None) -> m.LessonExplanation:
    q = select(m.LessonExplanation).where(m.LessonExplanation.course_id == course_id,
                                          m.LessonExplanation.lesson_id == lesson_id)
    row = db.execute(q).scalars().first()
    if row is None:
        row = m.LessonExplanation(course_id=course_id, lesson_id=lesson_id)
        db.add(row)
        db.flush()
    if title:
        row.title = title
    if explanation:
        if row.explanation != explanation or (title and row.title != title):
            row.audio_path = ""
        row.explanation = explanation
    if key_concepts is not None:
        row.key_concepts = key_concepts
    if category is not None:
        row.category = category
    row.updated_at = _utcnow()
    db.commit()
    db.refresh(row)
    return row


def get_lesson_explanation(db: Session, *, course_id: str, lesson_id: str) -> m.LessonExplanation | None:
    q = select(m.LessonExplanation).where(m.LessonExplanation.course_id == course_id,
                                          m.LessonExplanation.lesson_id == lesson_id)
    return db.execute(q).scalars().first()


# ---- Skills ----
def upsert_skill(db: Session, *, course_id: str, lesson_id: str, skill_id: str,
                 name: str = "", description: str = "", key_concepts: list | None = None,
                 learning_objective: str = "",
                 source_chunk_ids: list | None = None,
                 source_evidence: list | None = None,
                 educational_metadata: dict | None = None) -> m.Skill:
    q = select(m.Skill).where(m.Skill.course_id == course_id, m.Skill.lesson_id == lesson_id,
                              m.Skill.skill_id == skill_id)
    skill = db.execute(q).scalars().first()
    if skill is None:
        skill = m.Skill(course_id=course_id, lesson_id=lesson_id, skill_id=skill_id)
        db.add(skill)
        db.flush()
    skill.extraction_active = True
    if name:
        skill.name = name
    if description:
        skill.description = description
    if key_concepts is not None:
        skill.key_concepts = key_concepts
    if learning_objective:
        skill.learning_objective = learning_objective
    if source_chunk_ids is not None:
        skill.source_chunk_ids = list(source_chunk_ids)
    if source_evidence is not None:
        skill.source_evidence = list(source_evidence)
    for field, value in (educational_metadata or {}).items():
        if field in {"learning_objective", "prerequisites", "misconceptions", "difficulty", "source_section_ids", "evidence_chunk_ids", "learning_content"}:
            setattr(skill, field, value)
    skill.updated_at = _utcnow()
    db.commit()
    db.refresh(skill)
    return skill


def list_skills(db: Session, *, course_id: str, lesson_id: str) -> list[m.Skill]:
    q = select(m.Skill).where(m.Skill.course_id == course_id, m.Skill.lesson_id == lesson_id, m.Skill.extraction_active.is_(True))
    return list(db.execute(q).scalars().all())


def get_skill(db: Session, *, course_id: str, lesson_id: str, skill_id: str) -> m.Skill | None:
    q = select(m.Skill).where(m.Skill.course_id == course_id, m.Skill.lesson_id == lesson_id,
                              m.Skill.skill_id == skill_id)
    return db.execute(q).scalars().first()


def get_skill_by_slug(db: Session, skill_id: str) -> m.Skill | None:
    """Lesson-agnostic lookup (slugs embed the lesson, e.g. cond_lesson__condition)."""
    q = select(m.Skill).where(m.Skill.skill_id == skill_id).limit(1)
    return db.execute(q).scalars().first()


def set_skill_explanation(db: Session, skill: m.Skill, explanation: str) -> None:
    if skill.explanation != explanation:
        skill.audio_path = ""
    skill.explanation = explanation
    skill.updated_at = _utcnow()
    db.commit()


# ---- Question banks ----
def next_bank_version(db: Session, *, course_id: str, lesson_id: str, skill_id: str) -> int:
    q = (
        select(m.QuestionBank)
        .where(m.QuestionBank.course_id == course_id, m.QuestionBank.lesson_id == lesson_id,
               m.QuestionBank.skill_id == skill_id)
        .order_by(desc(m.QuestionBank.version))
        .limit(1)
    )
    latest = db.execute(q).scalars().first()
    return (latest.version + 1) if latest else 1


def create_bank(db: Session, *, course_id: str, lesson_id: str, skill_id: str,
                questions: list[dict], teacher_feedback: str = "",
                teacher_id: str | None = None, classroom_id: str | None = None,
                material_id: str | None = None) -> m.QuestionBank:
    from sqlalchemy.exc import IntegrityError

    # Prefer atomic counter when table exists (platform), else version retry (legacy).
    try:
        from sqlalchemy import update as _update
        key = dict(course_id=course_id, lesson_id=lesson_id, skill_id=skill_id)
        counter = db.get(m.BankVersionCounter, (course_id, lesson_id, skill_id))
        if counter is not None or True:
            try:
                if counter is None:
                    with db.begin_nested():
                        db.add(m.BankVersionCounter(**key, version=next_bank_version(db, **key) - 1))
                        db.flush()
                version = db.execute(_update(m.BankVersionCounter).where(
                    m.BankVersionCounter.course_id == course_id, m.BankVersionCounter.lesson_id == lesson_id,
                    m.BankVersionCounter.skill_id == skill_id).values(version=m.BankVersionCounter.version + 1)
                    .returning(m.BankVersionCounter.version)).scalar_one()
                bank = m.QuestionBank(**key, version=version, status="pending_review", teacher_feedback=teacher_feedback,
                                      teacher_id=teacher_id, classroom_id=classroom_id, material_id=material_id)
                db.add(bank)
                db.flush()
                for qd in questions:
                    db.add(m.Question(question_bank_id=bank.id, **qd))
                db.commit()
                db.refresh(bank)
                return bank
            except Exception:
                db.rollback()
                pass
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
    for _attempt in range(3):
        version = next_bank_version(db, course_id=course_id, lesson_id=lesson_id, skill_id=skill_id)
        bank = m.QuestionBank(course_id=course_id, lesson_id=lesson_id, skill_id=skill_id,
                              version=version, status="pending_review", teacher_feedback=teacher_feedback,
                              teacher_id=teacher_id, classroom_id=classroom_id, material_id=material_id)
        db.add(bank)
        try:
            db.flush()
        except IntegrityError:
            # Concurrent creator won this version — recompute and retry.
            db.rollback()
            continue
        for qd in questions:
            db.add(m.Question(question_bank_id=bank.id, **qd))
        try:
            db.commit()
        except IntegrityError:
            db.rollback()
            continue
        db.refresh(bank)
        return bank
    raise ValueError("Could not allocate a unique bank version (concurrent generation)")


def get_bank(db: Session, bank_id: str) -> m.QuestionBank | None:
    return db.get(m.QuestionBank, bank_id)


def get_banks_by_ids(db: Session, bank_ids: list[str]) -> list[m.QuestionBank]:
    """One query for many banks (avoids per-question lookups in assessment flows)."""
    ids = [bid for bid in dict.fromkeys(bank_ids) if bid]
    if not ids:
        return []
    q = select(m.QuestionBank).where(m.QuestionBank.id.in_(ids))
    return list(db.execute(q).scalars().all())


def list_banks(db: Session, *, status: str | None = None, limit: int = 100,
               teacher_id: str | None = None, classroom_id: str | None = None,
               material_id: str | None = None, skill_id: str | None = None,
               lesson_id: str | None = None, course_id: str | None = None) -> list[m.QuestionBank]:
    q = select(m.QuestionBank).order_by(desc(m.QuestionBank.created_at))
    if status:
        q = q.where(m.QuestionBank.status == status)
    if teacher_id:
        q = q.where(m.QuestionBank.teacher_id == teacher_id)
    if classroom_id:
        q = q.where(m.QuestionBank.classroom_id == classroom_id)
    if material_id:
        q = q.where(m.QuestionBank.material_id == material_id)
    if skill_id:
        q = q.where(m.QuestionBank.skill_id == skill_id)
    if lesson_id:
        q = q.where(m.QuestionBank.lesson_id == lesson_id)
    if course_id:
        q = q.where(m.QuestionBank.course_id == course_id)
    if limit:
        q = q.limit(limit)
    return list(db.execute(q).scalars().all())


def update_question(db: Session, question: m.Question, **fields) -> m.Question:
    for key, value in fields.items():
        if hasattr(question, key):
            setattr(question, key, value)
    db.commit()
    db.refresh(question)
    return question


def delete_question(db: Session, question: m.Question) -> None:
    # Preserve attempt and feedback history while removing the question from use.
    question.retired = True
    db.commit()


def set_bank_status(db: Session, bank: m.QuestionBank, status: str, feedback: str = "") -> None:
    bank.status = status
    if feedback:
        bank.teacher_feedback = feedback
    bank.updated_at = _utcnow()
    db.commit()


def get_questions(db: Session, bank_id: str) -> list[m.Question]:
    q = select(m.Question).where(m.Question.question_bank_id == bank_id, m.Question.retired.is_(False))
    return list(db.execute(q).scalars().all())


def get_questions_by_ids(db: Session, question_ids: list[str]) -> list[m.Question]:
    """One query for many questions (submit loads the whole assessment at once)."""
    ids = [qid for qid in dict.fromkeys(question_ids) if qid]
    if not ids:
        return []
    q = select(m.Question).where(m.Question.id.in_(ids))
    return list(db.execute(q).scalars().all())


def get_approved_questions(db: Session, *, course_id: str | None = None,
                           lesson_id: str | None = None, skill_id: str | None = None) -> list[m.Question]:
    q = select(m.Question).options(joinedload(m.Question.bank)).join(m.QuestionBank, m.Question.question_bank_id == m.QuestionBank.id).where(
        m.QuestionBank.status == "approved", m.Question.retired.is_(False),
        ~m.Question.id.in_(select(m.QuestionFeedback.question_id).where(m.QuestionFeedback.kind == "flag")))
    if course_id:
        q = q.where(m.QuestionBank.course_id == course_id)
    if lesson_id:
        q = q.where(m.QuestionBank.lesson_id == lesson_id)
    if skill_id:
        q = q.where(m.QuestionBank.skill_id == skill_id)
    return list(db.execute(q).scalars().all())


# ---- Question feedback loop ----
def flag_question(db: Session, *, question_id: str, reason: str = "", teacher_id: str | None = None) -> m.QuestionFeedback:
    from sahlha.app.database import models as _m

    if db.get(_m.Question, question_id) is None:
        raise ValueError(f"Question {question_id} not found")
    if not (reason or "").strip():
        # Legacy callers allow empty reason; platform requires non-empty.
        # Accept empty for backward compat (teacher UI validates separately).
        pass
    try:
        fb = m.QuestionFeedback(question_id=question_id, kind="flag", reason=reason, teacher_id=teacher_id)
    except Exception:
        fb = m.QuestionFeedback(question_id=question_id, kind="flag", reason=reason)
    db.add(fb)
    db.commit()
    db.refresh(fb)
    return fb


def get_flagged_question_ids(db: Session) -> set[str]:
    q = select(m.QuestionFeedback.question_id).where(m.QuestionFeedback.kind == "flag")
    return {row[0] for row in db.execute(q).all()}


def get_flag_reasons_for_skill(db: Session, *, course_id: str, lesson_id: str,
                               skill_id: str) -> list[str]:
    """Reasons from flags on any version of this skill's banks (feeds regeneration)."""
    from sahlha.app.database import models as _m

    q = (select(m.QuestionFeedback.reason)
         .join(_m.Question, m.QuestionFeedback.question_id == _m.Question.id)
         .join(_m.QuestionBank, _m.Question.question_bank_id == _m.QuestionBank.id)
         .where(_m.QuestionBank.course_id == course_id, _m.QuestionBank.lesson_id == lesson_id,
                _m.Question.skill_id == skill_id, m.QuestionFeedback.kind == "flag"))
    return [r for (r,) in db.execute(q).all() if r]


def list_flags(db: Session, limit: int = 100, bank_id: str | None = None) -> list[m.QuestionFeedback]:
    if bank_id:
        query = select(m.QuestionFeedback).join(m.Question, m.Question.id == m.QuestionFeedback.question_id)
        query = query.where(m.Question.question_bank_id == bank_id)
        return list(db.scalars(query.order_by(m.QuestionFeedback.created_at)))
    q = (select(m.QuestionFeedback).order_by(desc(m.QuestionFeedback.created_at)).limit(limit))
    return list(db.execute(q).scalars().all())


def latest_approved_banks(db: Session, *, course_id: str | None = None,
                          lesson_id: str | None = None,
                          skill_id: str | None = None) -> list[m.QuestionBank]:
    """Latest ACTIVE approved bank version per (course_id, lesson_id, skill_id).

    History is preserved in the database; older approved versions become
    historical/superseded for future selection purely by this query-time policy.
    Historical assessments keep referencing their original question IDs via
    get_question()/get_assessment() and are unaffected.
    """
    banks = scoped_banks(db, course_id=course_id, lesson_id=lesson_id,
                         skill_id=skill_id, status="approved")
    latest: dict[tuple[str, str, str], m.QuestionBank] = {}
    for b in banks:
        key = (b.course_id, b.lesson_id, b.skill_id)
        current = latest.get(key)
        if current is None or (b.version, str(b.created_at), str(b.id)) > (
                current.version, str(current.created_at), str(current.id)):
            latest[key] = b
    return sorted(latest.values(), key=lambda b: (b.course_id, b.lesson_id, b.skill_id))


def get_latest_approved_questions(db: Session, *, course_id: str | None = None,
                                  lesson_id: str | None = None,
                                  skill_id: str | None = None) -> list[m.Question]:
    """Questions from the latest approved bank version per skill scope only.

    Flagged and retired questions are still excluded. Older approved versions
    remain in history but never leak into new student-facing selection.
    """
    banks = latest_approved_banks(db, course_id=course_id, lesson_id=lesson_id, skill_id=skill_id)
    if not banks:
        return []
    allowed = {b.id for b in banks}
    flagged = set(db.scalars(select(m.QuestionFeedback.question_id).where(
        m.QuestionFeedback.kind == "flag")))
    q = select(m.Question).options(joinedload(m.Question.bank)).where(
        m.Question.question_bank_id.in_(allowed),
        m.Question.retired.is_(False))
    rows = list(db.execute(q).scalars().all())
    return [r for r in rows if r.id not in flagged]


# ---- Students / attempts ----
def get_or_create_student(db: Session, student_id: str | None, name: str = "Student") -> m.Student:
    sid = (student_id or "").strip() or None
    clean_name = (name or "").strip() or "Student"
    if sid:
        s = db.get(m.Student, sid)
        if s:
            return s
        s = m.Student(id=sid, name=clean_name)
    else:
        s = m.Student(name=clean_name)
    db.add(s)
    db.commit()
    db.refresh(s)
    return s


def get_student(db: Session, student_id: str) -> m.Student | None:
    sid = (student_id or "").strip()
    if not sid:
        return None
    return db.get(m.Student, sid)


def list_students(db: Session, limit: int = 100) -> list[m.Student]:
    q = select(m.Student).order_by(desc(m.Student.created_at)).limit(limit)
    return list(db.execute(q).scalars().all())


def create_assessment(db: Session, *, student_id: str, question_bank_id: str, question_ids: list[str],
                      course_id: str = "general", lesson_id: str = "lesson_1",
                      selection_meta: dict | None = None) -> m.Assessment:
    # Normalize '' (platform) to general/lesson_1 for consistent history.
    course_id = (course_id or "general") or "general"
    lesson_id = (lesson_id or "lesson_1") or "lesson_1"
    a = m.Assessment(student_id=student_id, question_bank_id=question_bank_id,
                     question_ids=question_ids, status="started",
                     course_id=course_id, lesson_id=lesson_id,
                     selection_meta=selection_meta or {})
    db.add(a)
    db.commit()
    db.refresh(a)
    return a


def get_assessment(db: Session, assessment_id: str) -> m.Assessment | None:
    return db.get(m.Assessment, assessment_id)


def record_attempt(db: Session, *, student_id: str, question_id: str, assessment_id: str,
                   answer, correct: bool, commit: bool = True) -> m.StudentAttempt:
    att = m.StudentAttempt(student_id=student_id, question_id=question_id,
                           assessment_id=assessment_id, answer=answer, correct=correct)
    db.add(att)
    if commit:
        db.commit()
        db.refresh(att)
    else:
        db.flush()  # make the PK available; caller commits once for the whole batch
    return att


def get_attempts(db: Session, student_id: str, limit: int = 200) -> list[m.StudentAttempt]:
    q = (select(m.StudentAttempt).where(m.StudentAttempt.student_id == student_id)
         .order_by(desc(m.StudentAttempt.timestamp)).limit(limit))
    return list(db.execute(q).scalars().all())


def get_attempt_for(db: Session, assessment_id: str, question_id: str) -> m.StudentAttempt | None:
    q = select(m.StudentAttempt).where(
        m.StudentAttempt.assessment_id == assessment_id,
        m.StudentAttempt.question_id == question_id)
    return db.execute(q).scalars().first()


def get_failed_question_ids(db: Session, student_id: str) -> list[str]:
    q = select(m.StudentAttempt).where(m.StudentAttempt.student_id == student_id,
                                       m.StudentAttempt.correct.is_(False))
    return [a.question_id for a in db.execute(q).scalars().all()]


def upsert_skill_performance(db: Session, *, student_id: str, skill_id: str, correct: bool,
                             course_id: str = "general", lesson_id: str = "lesson_1",
                             commit: bool = True, skill_row_id: str | None = None) -> m.StudentSkillPerformance:
    # Normalize '' (platform) to general/lesson_1 for consistent history.
    course_id = (course_id or "general") or "general"
    lesson_id = (lesson_id or "lesson_1") or "lesson_1"
    q = select(m.StudentSkillPerformance).where(
        m.StudentSkillPerformance.student_id == student_id,
        m.StudentSkillPerformance.skill_id == skill_id,
        m.StudentSkillPerformance.course_id == course_id,
        m.StudentSkillPerformance.lesson_id == lesson_id)
    perf = db.execute(q).scalars().first()
    if perf is None:
        # Back-compat: adopt a legacy unscoped row (pre-scoping DBs) instead of
        # creating a duplicate that would split the student's history.
        legacy = db.execute(select(m.StudentSkillPerformance).where(
            m.StudentSkillPerformance.student_id == student_id,
            m.StudentSkillPerformance.skill_id == skill_id)).scalars().first()
        if legacy is not None and not getattr(legacy, "course_id", None):
            legacy.course_id = course_id
            legacy.lesson_id = lesson_id
            perf = legacy
    if perf is None:
        # Platform fallback: adopt ''-scoped legacy row when scopes match.
        try:
            legacy2 = db.scalar(select(m.StudentSkillPerformance).where(
                m.StudentSkillPerformance.student_id == student_id,
                m.StudentSkillPerformance.skill_id == skill_id,
                or_(m.StudentSkillPerformance.course_id == "", m.StudentSkillPerformance.course_id.is_(None)),
                or_(m.StudentSkillPerformance.lesson_id == "", m.StudentSkillPerformance.lesson_id.is_(None))))
            if legacy2 is not None:
                perf = legacy2
                perf.course_id = course_id
                perf.lesson_id = lesson_id
        except Exception:
            pass
    if perf is None:
        perf = m.StudentSkillPerformance(student_id=student_id, skill_id=skill_id,
                                         course_id=course_id, lesson_id=lesson_id,
                                         skill_row_id=skill_row_id)
        db.add(perf)
        db.flush()
    else:
        # Heal legacy rows: adopt scope once known (prevents cross-lesson collisions).
        if course_id and not perf.course_id:
            perf.course_id = course_id
        if lesson_id and not perf.lesson_id:
            perf.lesson_id = lesson_id
        if skill_row_id and not perf.skill_row_id:
            perf.skill_row_id = skill_row_id
    perf.total_attempts += 1
    if correct:
        perf.correct_attempts += 1
    perf.accuracy = perf.correct_attempts / perf.total_attempts if perf.total_attempts else 0.0
    perf.last_updated = _utcnow()
    if commit:
        db.commit()
        db.refresh(perf)
    else:
        db.flush()  # caller commits once for the whole batch (no expiry cascade)
    return perf


def get_skill_performance(db: Session, student_id: str, *,
                           course_id: str | None = None,
                           lesson_id: str | None = None) -> list[m.StudentSkillPerformance]:
    q = select(m.StudentSkillPerformance).where(m.StudentSkillPerformance.student_id == student_id)
    if course_id:
        q = q.where(m.StudentSkillPerformance.course_id == course_id)
    if lesson_id:
        q = q.where(m.StudentSkillPerformance.lesson_id == lesson_id)
    return list(db.execute(q).scalars().all())


# ---- Catalog: courses & lessons ----
def list_courses(db: Session) -> list[str]:
    """Distinct course_ids that have any content (documents, skills, lessons)."""
    courses: set[str] = set()
    for model in (m.Skill, m.Document, m.LessonExplanation, m.QuestionBank, m.DocumentChunk):
        try:
            for (cid,) in db.execute(select(model.course_id).distinct()).all():
                if cid:
                    courses.add(cid)
        except Exception:
            continue
    return sorted(courses)


def list_lessons(db: Session, course_id: str | None = None) -> list[dict]:
    """Distinct lessons, optionally filtered by course. Returns [{course_id, lesson_id, title, skill_count}]."""
    # Gather distinct (course_id, lesson_id) pairs from skills, documents, lessons
    pairs: set[tuple[str, str]] = set()
    for model in (m.Skill, m.Document, m.LessonExplanation, m.QuestionBank):
        try:
            q = select(model.course_id, model.lesson_id).distinct()
            if course_id:
                q = q.where(model.course_id == course_id)
            for cid, lid in db.execute(q).all():
                if cid and lid:
                    pairs.add((cid, lid))
        except Exception:
            continue
    # Enrich with title / skill count
    out: list[dict] = []
    for cid, lid in sorted(pairs):
        title = None
        try:
            row = db.execute(select(m.LessonExplanation).where(m.LessonExplanation.course_id == cid, m.LessonExplanation.lesson_id == lid)).scalars().first()
            if row and row.title:
                title = row.title
        except Exception:
            pass
        skill_count = 0
        try:
            skill_count = len(list_skills(db, course_id=cid, lesson_id=lid))
        except Exception:
            pass
        out.append({"course_id": cid, "lesson_id": lid, "title": title or lid, "skill_count": skill_count})
    return out


def set_media(db, row, **fields):
    for name in ("audio_path", "image_path", "image_url", "image_alt"):
        if name in fields:
            setattr(row, name, fields[name])
    db.commit()


def get_question(db, question_id):
    return db.get(m.Question, question_id)


def scoped_banks(db, *, course_id=None, lesson_id=None, skill_id=None, status=None):
    query = select(m.QuestionBank).order_by(m.QuestionBank.created_at, m.QuestionBank.id)
    for name, value in (("course_id", course_id), ("lesson_id", lesson_id), ("skill_id", skill_id), ("status", status)):
        if value:
            query = query.where(getattr(m.QuestionBank, name) == value)
    return list(db.scalars(query))


def scoped_skills(db, *, course_id=None, lesson_id=None, skill_id=None):
    query = select(m.Skill).where(m.Skill.extraction_active.is_(True))
    for name, value in (("course_id", course_id), ("lesson_id", lesson_id), ("skill_id", skill_id)):
        if value:
            query = query.where(getattr(m.Skill, name) == value)
    return list(db.scalars(query))


def study_rows(db, *, course_id, lesson_id):
    banks = latest_approved_banks(db, course_id=course_id, lesson_id=lesson_id)
    questions = get_latest_approved_questions(db, course_id=course_id, lesson_id=lesson_id)
    return get_lesson_explanation(db, course_id=course_id, lesson_id=lesson_id), list_skills(db, course_id=course_id, lesson_id=lesson_id), banks, questions


def finish_assessment(db, assessment, score):
    assessment.status = "submitted"
    assessment.score = score
    db.commit()
