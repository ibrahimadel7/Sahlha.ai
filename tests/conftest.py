"""Shared pytest fixtures: isolated SQLite DB per test module run."""
from __future__ import annotations

import os
import tempfile

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

os.environ.setdefault("OPENAI_API_KEY", "")

from sahlha.app.database.database import Base, get_db  # noqa: E402


@pytest.fixture(autouse=True)
def _no_external_keys(monkeypatch):
    """Hermetic tests: external providers are opt-in per test via mocks.

    Settings loads the developer's real .env at import; without this, tests would
    spend real API calls (auto media generation) and become order-dependent.
    """
    from sahlha.app.config import settings as _s

    monkeypatch.setattr(_s, "groq_api_key", "")
    monkeypatch.setattr(_s, "openrouter_api_key", "")
    monkeypatch.setattr(_s, "openai_api_key", "")
    monkeypatch.setattr(_s, "pexels_api_key", "")
    monkeypatch.delenv("GROQ_API_KEY", raising=False)
    monkeypatch.delenv("OPENROUTER_API_KEY", raising=False)
    monkeypatch.delenv("OPENAI_API_KEY", raising=False)
    monkeypatch.delenv("PEXELS_API_KEY", raising=False)


@pytest.fixture()
def db_session():
    from sahlha.app.database import models  # noqa: F401  (register)

    tmp = tempfile.NamedTemporaryFile(suffix=".db", delete=False)
    tmp.close()
    engine = create_engine(f"sqlite:///{tmp.name}", connect_args={"check_same_thread": False})
    Base.metadata.create_all(bind=engine)
    Session = sessionmaker(bind=engine, autoflush=False, autocommit=False)
    session = Session()
    try:
        yield session
    finally:
        session.close()
        engine.dispose()
        try:
            os.unlink(tmp.name)
        except PermissionError:
            pass  # Windows: SQLite handle may linger; temp file is harmless


@pytest.fixture()
def client(db_session):
    from sahlha.app.main import app

    def _override():
        try:
            yield db_session
        finally:
            pass

    app.dependency_overrides[get_db] = _override
    with TestClient(app) as c:
        yield c
    app.dependency_overrides.clear()


SAMPLE_TEXT = (
    "Python elif lesson. The elif keyword means else-if. It lets a program test multiple "
    "conditions in order. If the first if condition is false, Python checks the elif condition. "
    "Only the first true branch executes. An optional else runs when nothing matches. "
    "Example: if score >= 90 grade A elif score >= 80 grade B else grade C."
)
