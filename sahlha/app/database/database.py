"""SQLAlchemy engine / session factory. Application owns all transactions."""
import os

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

    Base.metadata.create_all(bind=engine)
    _ensure_columns()
    seed_demo_student()


def _ensure_columns() -> None:
    """Lightweight additive migration for SQLite (create_all won't ALTER existing tables)."""
    from sqlalchemy import inspect, text

    wanted: dict[str, list[tuple[str, str]]] = {
        "lesson_explanations": [("category", "VARCHAR(64)")],
        "skills": [("image_url", "VARCHAR(1024)"), ("image_path", "VARCHAR(1024)"),
                   ("image_alt", "VARCHAR(512)"),
                   ("learning_objective", "TEXT"), ("source_chunk_ids", "JSON"),
                   ("source_evidence", "JSON")],
        "questions": [("source_chunk_ids", "JSON"), ("source_evidence", "JSON")],
        "assessments": [("course_id", "VARCHAR(128)"), ("lesson_id", "VARCHAR(128)")],
        "student_skill_performance": [("course_id", "VARCHAR(128)"), ("lesson_id", "VARCHAR(128)")],
        "students": [("email", "VARCHAR(320)"), ("role", "VARCHAR(32)")],
    }
    with engine.connect() as conn:
        for table, cols in wanted.items():
            if not inspect(conn).has_table(table):
                continue
            existing = {row[1] for row in conn.execute(text(f"PRAGMA table_info({table})"))}
            for name, ddl in cols:
                if name not in existing:
                    conn.execute(text(f"ALTER TABLE {table} ADD COLUMN {name} {ddl}"))
            conn.commit()
        # Backfill pre-migration NULLs so scoped lookups never miss legacy rows.
        for table in ("assessments", "student_skill_performance"):
            if not inspect(conn).has_table(table):
                continue
            conn.execute(text(f"UPDATE {table} SET course_id='general' WHERE course_id IS NULL"))
            conn.execute(text(f"UPDATE {table} SET lesson_id='lesson_1' WHERE lesson_id IS NULL"))
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
