"""Relational schema for the Sahlha learning platform.

Legacy AI-loop tables (documents, skills, question banks, assessments, ...) are
preserved. Platform tables (users, classrooms, materials, profiles, ...) are added,
plus additive scoping columns on existing tables (see database._ensure_columns for
the SQLite migration of pre-existing databases).
"""
import datetime
import secrets
import uuid

from sqlalchemy import JSON, Boolean, DateTime, Float, ForeignKey, Integer, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from sahlha.app.database.database import Base


def _uid() -> str:
    return uuid.uuid4().hex[:12]


def _now() -> datetime.datetime:
    return datetime.datetime.now(datetime.timezone.utc)


def _link_code() -> str:
    alphabet = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"  # readable, no confusables
    return "".join(secrets.choice(alphabet) for _ in range(8))


# ----------------------------------------------------------------------------
# Platform: users / roles
# ----------------------------------------------------------------------------
class User(Base):
    __tablename__ = "users"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uid)
    name: Mapped[str] = mapped_column(String(256), default="")
    email: Mapped[str] = mapped_column(String(320), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(512), default="")
    role: Mapped[str] = mapped_column(String(16), default="student")  # teacher|student|parent
    active: Mapped[bool] = mapped_column(Boolean, default=True)
    # Parent-link code (only meaningful for students; unique when set).
    link_code: Mapped[str] = mapped_column(String(16), default="")
    created_at: Mapped[datetime.datetime] = mapped_column(DateTime, default=_now)
    updated_at: Mapped[datetime.datetime] = mapped_column(DateTime, default=_now, onupdate=_now)


class Classroom(Base):
    __tablename__ = "classrooms"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uid)
    teacher_id: Mapped[str] = mapped_column(String(32), ForeignKey("users.id"), index=True)
    name: Mapped[str] = mapped_column(String(256), default="")
    subject: Mapped[str] = mapped_column(String(128), default="")
    grade_level: Mapped[str] = mapped_column(String(64), default="")
    join_code: Mapped[str] = mapped_column(String(16), unique=True, index=True, default=_link_code)
    created_at: Mapped[datetime.datetime] = mapped_column(DateTime, default=_now)
    updated_at: Mapped[datetime.datetime] = mapped_column(DateTime, default=_now, onupdate=_now)


class ClassroomEnrollment(Base):
    __tablename__ = "classroom_enrollments"
    __table_args__ = (UniqueConstraint("classroom_id", "student_id", name="uq_enrollment"),)

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uid)
    classroom_id: Mapped[str] = mapped_column(String(32), ForeignKey("classrooms.id"), index=True)
    student_id: Mapped[str] = mapped_column(String(32), ForeignKey("users.id"), index=True)
    joined_at: Mapped[datetime.datetime] = mapped_column(DateTime, default=_now)


class ParentStudentLink(Base):
    __tablename__ = "parent_student_links"
    __table_args__ = (UniqueConstraint("parent_id", "student_id", name="uq_parent_student"),)

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uid)
    parent_id: Mapped[str] = mapped_column(String(32), ForeignKey("users.id"), index=True)
    student_id: Mapped[str] = mapped_column(String(32), ForeignKey("users.id"), index=True)
    created_at: Mapped[datetime.datetime] = mapped_column(DateTime, default=_now)


class LearningMaterial(Base):
    """Platform-level material record wrapping one AI-loop Document.

    scope=official  -> teacher classroom curriculum (course_id=class:{classroom_id})
    scope=supplementary -> parent-uploaded support for one child (child:{student_id})
    lesson_id for the AI loop is always this row's id.
    """

    __tablename__ = "learning_materials"

    quality_signals: Mapped[dict] = mapped_column(JSON, default=dict)

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uid)
    uploader_id: Mapped[str] = mapped_column(String(32), ForeignKey("users.id"), index=True)
    source_type: Mapped[str] = mapped_column(String(16), default="teacher")  # teacher|parent
    classroom_id: Mapped[str | None] = mapped_column(String(32), ForeignKey("classrooms.id"), nullable=True, index=True)
    child_student_id: Mapped[str | None] = mapped_column(String(32), ForeignKey("users.id"), nullable=True, index=True)
    title: Mapped[str] = mapped_column(String(512), default="")
    original_filename: Mapped[str] = mapped_column(String(512), default="")
    document_id: Mapped[str | None] = mapped_column(String(32), ForeignKey("documents.id"), nullable=True)
    scope: Mapped[str] = mapped_column(String(16), default="official")  # official|supplementary
    processing_status: Mapped[str] = mapped_column(String(32), default="uploaded")
    # uploaded|processing|processed|skills_ready|banks_ready|failed
    status_detail: Mapped[str] = mapped_column(Text, default="")
    created_at: Mapped[datetime.datetime] = mapped_column(DateTime, default=_now)
    updated_at: Mapped[datetime.datetime] = mapped_column(DateTime, default=_now, onupdate=_now)


class StudentLearningProfile(Base):
    """How Sahlha should currently support one student.

    seed = self-reported onboarding answers; observed = rule-based behaviour signals.
    NEVER a medical profile — support preferences only.
    """

    __tablename__ = "student_learning_profiles"

    student_id: Mapped[str] = mapped_column(String(32), ForeignKey("users.id"), primary_key=True)
    onboarding_completed: Mapped[bool] = mapped_column(Boolean, default=False)
    reading_support: Mapped[str] = mapped_column(String(64), default="")
    focus_support: Mapped[str] = mapped_column(String(64), default="")
    instruction_support: Mapped[str] = mapped_column(String(64), default="")
    presentation_support: Mapped[str] = mapped_column(String(64), default="")
    practice_support: Mapped[str] = mapped_column(String(64), default="")
    session_preference: Mapped[str] = mapped_column(String(64), default="")
    learning_confidence: Mapped[str] = mapped_column(String(64), default="")
    raw_answers: Mapped[dict] = mapped_column(JSON, default=dict)
    observed_settings: Mapped[dict] = mapped_column(JSON, default=dict)
    support_retry_count: Mapped[int] = mapped_column(Integer, default=0)
    support_hint_count: Mapped[int] = mapped_column(Integer, default=0)
    updated_at: Mapped[datetime.datetime] = mapped_column(DateTime, default=_now, onupdate=_now)


class Document(Base):
    __tablename__ = "documents"

    blocks: Mapped[list] = mapped_column(JSON, default=list)
    extraction_quality: Mapped[dict] = mapped_column(JSON, default=dict)

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uid)
    filename: Mapped[str] = mapped_column(String(512))
    course_id: Mapped[str] = mapped_column(String(128), default="general")
    lesson_id: Mapped[str] = mapped_column(String(128), default="lesson_1")
    skill_id: Mapped[str] = mapped_column(String(128), default="general")
    status: Mapped[str] = mapped_column(String(32), default="uploaded")  # uploaded|processed|failed
    char_count: Mapped[int] = mapped_column(Integer, default=0)
    chunk_count: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime.datetime] = mapped_column(DateTime, default=_now)


class DocumentChunk(Base):
    __tablename__ = "document_chunks"

    section: Mapped[str] = mapped_column(Text, default="")
    section_id: Mapped[str] = mapped_column(Text, default="")
    type: Mapped[str] = mapped_column(Text, default="")
    block_metadata: Mapped[dict] = mapped_column(JSON, default=dict)

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uid)
    document_id: Mapped[str] = mapped_column(String(32), ForeignKey("documents.id"))
    course_id: Mapped[str] = mapped_column(String(128), default="general")
    lesson_id: Mapped[str] = mapped_column(String(128), default="lesson_1")
    skill_id: Mapped[str] = mapped_column(String(128), default="general")
    page: Mapped[int] = mapped_column(Integer, default=0)
    chunk_index: Mapped[int] = mapped_column(Integer, default=0)
    text: Mapped[str] = mapped_column(Text)


class LessonExplanation(Base):
    """Agent-written overview of a whole lesson (one per lesson).

    Shown to the student first, before the per-skill explanations and the exercise.
    """
    __tablename__ = "lesson_explanations"
    __table_args__ = (UniqueConstraint("course_id", "lesson_id", name="uq_lesson_explanation"),)

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uid)
    course_id: Mapped[str] = mapped_column(String(128), default="general")
    lesson_id: Mapped[str] = mapped_column(String(128), default="lesson_1")
    title: Mapped[str] = mapped_column(String(256), default="")
    explanation: Mapped[str] = mapped_column(Text, default="")
    key_concepts: Mapped[list] = mapped_column(JSON, default=list)
    # Broad educational category id (see sahlha/app/lesson_categories.py),
    # classified once per lesson from RAG context; reused as the guardrail
    # for every skill image query of the lesson.
    category: Mapped[str] = mapped_column(String(64), default="")
    image_url: Mapped[str] = mapped_column(String(1024), default="")
    image_path: Mapped[str] = mapped_column(String(1024), default="")
    image_alt: Mapped[str] = mapped_column(String(512), default="")
    audio_path: Mapped[str] = mapped_column(String(1024), default="")
    created_at: Mapped[datetime.datetime] = mapped_column(DateTime, default=_now)
    updated_at: Mapped[datetime.datetime] = mapped_column(DateTime, default=_now, onupdate=_now)


class Skill(Base):
    """A skill extracted by the agent from a lesson.

    Each skill gets an agent-written explanation and its own question bank(s).
    Provenance (learning_objective + source_* refs) records the RAG evidence
    the skill was grounded in; additive columns, never a redesign.
    """
    __tablename__ = "skills"
    __table_args__ = (UniqueConstraint("course_id", "lesson_id", "skill_id", name="uq_lesson_skill"),)

    extraction_active: Mapped[bool] = mapped_column(Boolean, default=True)
    prerequisites: Mapped[list] = mapped_column(JSON, default=list)
    misconceptions: Mapped[list] = mapped_column(JSON, default=list)
    difficulty: Mapped[str] = mapped_column(Text, default="")
    source_section_ids: Mapped[list] = mapped_column(JSON, default=list)
    evidence_chunk_ids: Mapped[list] = mapped_column(JSON, default=list)
    learning_content: Mapped[dict] = mapped_column(JSON, default=dict)

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uid)
    course_id: Mapped[str] = mapped_column(String(128), default="general")
    lesson_id: Mapped[str] = mapped_column(String(128), default="lesson_1")
    skill_id: Mapped[str] = mapped_column(String(128))  # agent-generated slug, e.g. python_elif_basics
    name: Mapped[str] = mapped_column(String(256), default="")
    description: Mapped[str] = mapped_column(Text, default="")
    explanation: Mapped[str] = mapped_column(Text, default="")  # agent-written, grounded in lesson chunks
    key_concepts: Mapped[list] = mapped_column(JSON, default=list)
    learning_objective: Mapped[str] = mapped_column(Text, default="")
    source_chunk_ids: Mapped[list] = mapped_column(JSON, default=list)
    source_evidence: Mapped[list] = mapped_column(JSON, default=list)
    image_url: Mapped[str] = mapped_column(String(1024), default="")  # Pexels source page
    image_path: Mapped[str] = mapped_column(String(1024), default="")  # local cached file
    image_alt: Mapped[str] = mapped_column(String(512), default="")
    audio_path: Mapped[str] = mapped_column(String(1024), default="")
    created_at: Mapped[datetime.datetime] = mapped_column(DateTime, default=_now)
    updated_at: Mapped[datetime.datetime] = mapped_column(DateTime, default=_now, onupdate=_now)


class QuestionBank(Base):
    __tablename__ = "question_banks"
    __table_args__ = (UniqueConstraint("course_id", "lesson_id", "skill_id", "version",
                                      name="uq_bank_skill_version"),)
    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uid)
    course_id: Mapped[str] = mapped_column(String(128), default="general")
    lesson_id: Mapped[str] = mapped_column(String(128), default="lesson_1")
    skill_id: Mapped[str] = mapped_column(String(128), default="general")
    version: Mapped[int] = mapped_column(Integer, default=1)
    status: Mapped[str] = mapped_column(String(32), default="pending_review")
    # pending_review | approved | rejected
    teacher_feedback: Mapped[str] = mapped_column(Text, default="")
    # Platform ownership (nullable so legacy rows stay valid).
    teacher_id: Mapped[str | None] = mapped_column(String(32), ForeignKey("users.id"), nullable=True, index=True)
    classroom_id: Mapped[str | None] = mapped_column(String(32), ForeignKey("classrooms.id"), nullable=True, index=True)
    material_id: Mapped[str | None] = mapped_column(String(32), ForeignKey("learning_materials.id"), nullable=True, index=True)
    created_at: Mapped[datetime.datetime] = mapped_column(DateTime, default=_now)
    updated_at: Mapped[datetime.datetime] = mapped_column(DateTime, default=_now, onupdate=_now)

    questions: Mapped[list["Question"]] = relationship("Question", back_populates="bank", cascade="all, delete-orphan")


class Question(Base):
    __tablename__ = "questions"

    evidence_chunk_ids: Mapped[list] = mapped_column(JSON, default=list)
    learning_objective: Mapped[str] = mapped_column(Text, default="")
    tested_concept: Mapped[str] = mapped_column(Text, default="")
    verification: Mapped[dict] = mapped_column(JSON, default=dict)

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uid)
    question_bank_id: Mapped[str] = mapped_column(String(32), ForeignKey("question_banks.id"))
    skill_id: Mapped[str] = mapped_column(String(128), default="general")
    question_type: Mapped[str] = mapped_column(String(32), default="multiple_choice")
    question_text: Mapped[str] = mapped_column(Text)
    options: Mapped[list] = mapped_column(JSON, default=list)
    correct_answer: Mapped[int | str] = mapped_column(JSON, default=0)
    explanation: Mapped[str] = mapped_column(Text, default="")
    difficulty: Mapped[str] = mapped_column(String(32), default="medium")
    # RAG provenance: Question -> Skill -> retrieved chunks. Additive only.
    source_chunk_ids: Mapped[list] = mapped_column(JSON, default=list)
    source_evidence: Mapped[list] = mapped_column(JSON, default=list)
    retired: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime.datetime] = mapped_column(DateTime, default=_now)

    bank: Mapped[QuestionBank] = relationship("QuestionBank", back_populates="questions")


class Student(Base):
    __tablename__ = "students"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uid)
    name: Mapped[str] = mapped_column(String(256), default="Student")
    email: Mapped[str | None] = mapped_column(String(320), nullable=True, unique=True, default=None)
    role: Mapped[str] = mapped_column(String(32), default="student")
    created_at: Mapped[datetime.datetime] = mapped_column(DateTime, default=_now)


class Assessment(Base):
    __tablename__ = "assessments"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uid)
    student_id: Mapped[str] = mapped_column(String(32), ForeignKey("students.id"))
    question_bank_id: Mapped[str] = mapped_column(String(32), ForeignKey("question_banks.id"))
    # Multi-bank lineage: an assessment spans N banks (one per skill), so we store
    # the dominant course/lesson explicitly instead of inferring from one bank.
    # Defaults general/lesson_1 (legacy) — platform '' normalized on write.
    course_id: Mapped[str] = mapped_column(String(128), default="general")
    lesson_id: Mapped[str] = mapped_column(String(128), default="lesson_1")
    selection_meta: Mapped[dict] = mapped_column(JSON, default=dict)
    question_ids: Mapped[list] = mapped_column(JSON, default=list)
    status: Mapped[str] = mapped_column(String(32), default="started")  # started|submitted
    score: Mapped[float] = mapped_column(Float, default=0.0)
    created_at: Mapped[datetime.datetime] = mapped_column(DateTime, default=_now)


class StudentAttempt(Base):
    __tablename__ = "student_attempts"
    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uid)
    student_id: Mapped[str] = mapped_column(String(32), ForeignKey("students.id"))
    question_id: Mapped[str] = mapped_column(String(32), ForeignKey("questions.id"))
    assessment_id: Mapped[str] = mapped_column(String(32), ForeignKey("assessments.id"))
    answer: Mapped[int | str | None] = mapped_column(JSON, default=None)
    correct: Mapped[bool] = mapped_column(default=False)
    timestamp: Mapped[datetime.datetime] = mapped_column(DateTime, default=_now)


class StudentSkillPerformance(Base):
    __tablename__ = "student_skill_performance"
    # Scoped uniqueness is authoritative: the same skill slug may repeat across
    # lessons/classrooms. (Pre-platform databases may still carry the legacy
    # unscoped uq_student_skill constraint or uq_student_skill_scoped; code
    # defensively merges in that case — see database._ensure_columns.)
    __table_args__ = (UniqueConstraint("student_id", "course_id", "lesson_id", "skill_id",
                                       name="uq_student_scoped_skill"),)

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uid)
    student_id: Mapped[str] = mapped_column(String(32), ForeignKey("students.id"), index=True)
    skill_id: Mapped[str] = mapped_column(String(128))
    # Proper scoping: the same skill slug may occur across lessons/classrooms.
    # Defaults general/lesson_1 — platform '' normalized on write.
    course_id: Mapped[str] = mapped_column(String(128), default="general")
    lesson_id: Mapped[str] = mapped_column(String(128), default="lesson_1")
    skill_row_id: Mapped[str | None] = mapped_column(String(32), ForeignKey("skills.id"), nullable=True)
    total_attempts: Mapped[int] = mapped_column(Integer, default=0)
    correct_attempts: Mapped[int] = mapped_column(Integer, default=0)
    accuracy: Mapped[float] = mapped_column(Float, default=0.0)
    last_updated: Mapped[datetime.datetime] = mapped_column(DateTime, default=_now, onupdate=_now)


class QuestionFeedback(Base):
    """Teacher feedback loop: item-level flags on questions (append-only).

    Flagged questions are excluded from future assessments, and their reasons
    are fed back into the next generation for the same skill.
    """
    __tablename__ = "question_feedback"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uid)
    question_id: Mapped[str] = mapped_column(String(32), ForeignKey("questions.id"), index=True)
    teacher_id: Mapped[str | None] = mapped_column(String(32), ForeignKey("users.id"), nullable=True)
    kind: Mapped[str] = mapped_column(String(32), default="flag")  # flag
    reason: Mapped[str] = mapped_column(Text, default="")
    created_at: Mapped[datetime.datetime] = mapped_column(DateTime, default=_now)


class BankVersionCounter(Base):
    __tablename__ = "bank_version_counters"
    course_id: Mapped[str] = mapped_column(String(128), primary_key=True)
    lesson_id: Mapped[str] = mapped_column(String(128), primary_key=True)
    skill_id: Mapped[str] = mapped_column(String(128), primary_key=True)
    version: Mapped[int] = mapped_column(Integer, default=0)


class LessonContentMap(Base):
    __tablename__ = "lesson_content_maps"
    __table_args__ = (UniqueConstraint("course_id", "lesson_id", name="uq_content_map_scope"),)
    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uid)
    course_id: Mapped[str] = mapped_column(String(128), index=True)
    lesson_id: Mapped[str] = mapped_column(String(128), index=True)
    content: Mapped[dict] = mapped_column(JSON, default=dict)
