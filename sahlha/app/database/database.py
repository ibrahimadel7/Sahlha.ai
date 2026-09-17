"""SQLAlchemy engine / session factory. Application owns all transactions."""
import os
from pathlib import Path

from sqlalchemy import create_engine
from sqlalchemy.orm import declarative_base, sessionmaker

from sahlha.app.config import settings

DEMO_STUDENT_ID = "demo_student"
DEMO_STUDENT_NAME = "Demo Student"
DEMO_STUDENT_EMAIL = "student@demo.sahlha.ai"
DEMO_STUDENT_ROLE = "student"

connect_args = {"check_same_thread": False} if settings.database_url.startswith("sqlite") else {}
engine = create_engine(settings.database_url, connect_args=connect_args, future=True)
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False, future=True)

Base = declarative_base()


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def init_db() -> None:
    from sahlha.app.database import models  # noqa: F401  (register models)

    # SQLite creates the database file, but not its parent directories.
    if engine.dialect.name == "sqlite":
        database = engine.url.database
        if database and database != ":memory:" and not engine.url.query.get("uri"):
            Path(database).parent.mkdir(parents=True, exist_ok=True)

    Base.metadata.create_all(bind=engine)
    _ensure_columns()
    seed_demo_student()


def _ensure_columns() -> None:
    """Lightweight additive migration for SQLite (create_all won't ALTER existing tables).

    Additive only: new tables are created by create_all; here we add columns to
    tables that already exist from an older version. The legacy performance
    uniqueness constraint uses a transactional copy with the original table retained.
    """
    from sqlalchemy import inspect, text

    if engine.dialect.name != "sqlite":
        return
    wanted: dict[str, list[tuple[str, str]]] = {
        "lesson_explanations": [("category", "VARCHAR(64)"),
                                ("audio_path", "VARCHAR(1024) DEFAULT ''"),
                                ("image_url", "VARCHAR(1024) DEFAULT ''"),
                                ("image_path", "VARCHAR(1024) DEFAULT ''"), ("image_alt", "VARCHAR(512) DEFAULT ''")],
        "skills": [("image_url", "VARCHAR(1024)"), ("image_path", "VARCHAR(1024)"),
                   ("image_alt", "VARCHAR(512)"), ("audio_path", "VARCHAR(1024) DEFAULT ''"),
                   ("learning_objective", "TEXT"), ("source_chunk_ids", "JSON"),
                   ("source_evidence", "JSON")],
        "questions": [("source_chunk_ids", "JSON"), ("source_evidence", "JSON"),
                      ("retired", "BOOLEAN NOT NULL DEFAULT 0")],
        "assessments": [("course_id", "VARCHAR(128)"), ("lesson_id", "VARCHAR(128)"),
                        ("selection_meta", "JSON DEFAULT '{}' ")],
        "student_skill_performance": [("course_id", "VARCHAR(128)"), ("lesson_id", "VARCHAR(128)"),
                                      ("skill_row_id", "VARCHAR(32)")],
        "students": [("email", "VARCHAR(320)"), ("role", "VARCHAR(32)")],
        "question_banks": [("teacher_id", "VARCHAR(32)"), ("classroom_id", "VARCHAR(32)"),
                           ("material_id", "VARCHAR(32)")],
    }
    additions = {
        "documents": {"blocks": "JSON DEFAULT '[]'", "extraction_quality": "JSON DEFAULT '{}'"},
        "document_chunks": {"section": "TEXT DEFAULT ''", "section_id": "TEXT DEFAULT ''", "type": "TEXT DEFAULT 'paragraph'", "block_metadata": "JSON DEFAULT '{}'"},
        "skills": {"extraction_active": "BOOLEAN NOT NULL DEFAULT 1", "learning_objective": "TEXT DEFAULT ''", "prerequisites": "JSON DEFAULT '[]'", "misconceptions": "JSON DEFAULT '[]'", "difficulty": "TEXT DEFAULT ''", "source_section_ids": "JSON DEFAULT '[]'", "evidence_chunk_ids": "JSON DEFAULT '[]'", "learning_content": "JSON DEFAULT '{}'"},
        "questions": {"evidence_chunk_ids": "JSON DEFAULT '[]'", "learning_objective": "TEXT DEFAULT ''", "tested_concept": "TEXT DEFAULT ''", "verification": "JSON DEFAULT '{}'"},
        "learning_materials": {"quality_signals": "JSON DEFAULT '{}'"},
    }
    for table, columns in additions.items():
        wanted.setdefault(table, []).extend(columns.items())
    with engine.connect() as conn:
        for table, cols in wanted.items():
            if not inspect(conn).has_table(table):
                continue
            existing = {row[1] for row in conn.execute(text(f"PRAGMA table_info({table})"))}
            for name, ddl in cols:
                if name not in existing:
                    conn.execute(text(f"ALTER TABLE {table} ADD COLUMN {name} {ddl}"))
            conn.commit()
        # Backfill pre-migration NULLs/'' so scoped lookups never miss legacy rows.
        # Normalize '' (platform) to general/lesson_1 (legacy) for consistent history.
        for table in ("assessments", "student_skill_performance"):
            if not inspect(conn).has_table(table):
                continue
            conn.execute(text(f"UPDATE {table} SET course_id='general' WHERE course_id IS NULL OR course_id=''"))
            conn.execute(text(f"UPDATE {table} SET lesson_id='lesson_1' WHERE lesson_id IS NULL OR lesson_id=''"))
            conn.commit()
        if inspect(conn).has_table("students"):
            conn.execute(text("UPDATE students SET role='student' WHERE role IS NULL"))
            conn.commit()


def _should_seed_demo_student() -> bool:
    """Dev-only gate: seed unless explicitly production or opted out."""
    if os.getenv("SAHLHA_SEED_DEMO", "").strip() == "0":
        return False
    env = os.getenv("ENVIRONMENT", os.getenv("SAHLHA_ENV", os.getenv("APP_ENV", "development")))
    return env.strip().lower() != "production"


def seed_demo_student() -> None:
    """Idempotently ensure the default Demo Student exists (dev/testing only).

    Uses the existing Student row (fixed id + unique email) so all assessment
    history survives restarts. Safe to call on every init_db().
    """
    if not _should_seed_demo_student():
        return
    from sqlalchemy import select

    from sahlha.app.database import models

    with SessionLocal() as db:
        row = db.get(models.Student, DEMO_STUDENT_ID)
        if row is None:
            row = db.execute(
                select(models.Student).where(models.Student.email == DEMO_STUDENT_EMAIL)
            ).scalars().first()
        if row is not None:
            # Adopt legacy rows (e.g. created before email/role columns existed).
            updated = False
            if not getattr(row, "email", None):
                row.email = DEMO_STUDENT_EMAIL
                updated = True
            if not getattr(row, "role", None):
                row.role = DEMO_STUDENT_ROLE
                updated = True
            if updated:
                db.commit()
            return
        db.add(models.Student(id=DEMO_STUDENT_ID, name=DEMO_STUDENT_NAME,
                              email=DEMO_STUDENT_EMAIL, role=DEMO_STUDENT_ROLE))
        db.commit()

    try:
        _migrate_performance_constraint()
    except Exception:
        pass
    try:
        _backfill_assessment_scopes()
    except Exception:
        pass


def _migrate_performance_constraint():
    """SQLite cannot drop a UNIQUE constraint: copy transactionally, retaining rows.

    Only the old (student, skill) constraint is replaced. No learner data is reset.
    """
    from sqlalchemy import inspect, text
    from sahlha.app.database.models import StudentSkillPerformance
    from sqlalchemy.schema import CreateTable
    with engine.begin() as conn:
        constraints = inspect(conn).get_unique_constraints("student_skill_performance")
        legacy = any(set(c["column_names"]) == {"student_id", "skill_id"} for c in constraints)
        conn.execute(text("UPDATE student_skill_performance SET course_id = COALESCE(course_id, ''), lesson_id = COALESCE(lesson_id, '')"))
        if not legacy:
            return
        # Reproduce the mapped schema with a temporary name. All existing mapped fields survive.
        ddl = str(CreateTable(StudentSkillPerformance.__table__).compile(conn))
        ddl = ddl.replace("CREATE TABLE student_skill_performance", "CREATE TABLE student_skill_performance_scoped", 1)
        conn.execute(text(ddl))
        columns = ", ".join(c.name for c in StudentSkillPerformance.__table__.columns)
        conn.execute(text(f"INSERT INTO student_skill_performance_scoped ({columns}) SELECT {columns} FROM student_skill_performance"))
        conn.execute(text("ALTER TABLE student_skill_performance RENAME TO student_skill_performance_legacy_backup"))
        conn.execute(text("ALTER TABLE student_skill_performance_scoped RENAME TO student_skill_performance"))
        conn.execute(text("CREATE INDEX IF NOT EXISTS ix_scoped_performance_student_id ON student_skill_performance(student_id)"))


def _backfill_assessment_scopes():
    """Adopt scope only when every selected question agrees; never sample one bank."""
    import json
    from sqlalchemy import text
    with engine.begin() as conn:
        rows = conn.execute(text("SELECT id, question_ids FROM assessments WHERE COALESCE(course_id, '') = ''")).all()
        for aid, question_ids in rows:
            ids = json.loads(question_ids) if isinstance(question_ids, str) else question_ids
            if not ids:
                continue
            from sqlalchemy import select
            from sahlha.app.database.models import Question, QuestionBank
            pairs = conn.execute(select(Question.id, QuestionBank.course_id, QuestionBank.lesson_id)
                .join(QuestionBank, Question.question_bank_id == QuestionBank.id).where(Question.id.in_(ids))).all()
            if len(pairs) != len(set(ids)):
                continue
            courses, lessons = {r[1] for r in pairs}, {r[2] for r in pairs}
            conn.execute(text("UPDATE assessments SET course_id=:course, lesson_id=:lesson WHERE id=:id"),
                         {"id": aid, "course": next(iter(courses)) if len(courses) == 1 else "general",
                          "lesson": next(iter(lessons)) if len(courses) == len(lessons) == 1 else "lesson_1"})
