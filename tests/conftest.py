"""Shared pytest fixtures: isolated SQLite DB per test module run."""
from __future__ import annotations

import os
import tempfile

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

os.environ.setdefault("OPENAI_API_KEY", "")

# Never load real credentials or mutate the user's database during tests.
_test_root = tempfile.TemporaryDirectory(prefix="sahlha-suite-", ignore_cleanup_errors=True)
for _key in ("GROQ_API_KEY", "OPENAI_API_KEY", "OPENROUTER_API_KEY", "PEXELS_API_KEY"):
    os.environ[_key] = ""
os.environ["DATABASE_URL"] = "sqlite:///" + os.path.join(_test_root.name, "lifespan.db")
os.environ["DENSE_EMBEDDINGS_ENABLED"] = "false"
os.environ["EMBEDDING_WARMUP"] = "false"
os.environ["LEGACY_DEV_API_ENABLED"] = "true"

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
        db_session.expire_all()
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


@pytest.fixture(autouse=True)
def isolated_providers_and_files(monkeypatch, tmp_path):
    from sahlha.app.config import settings
    from sahlha.app.rag import embeddings
    for name in ("groq_api_key", "openai_api_key", "openrouter_api_key", "pexels_api_key"):
        monkeypatch.setattr(settings, name, "")
    for name in ("audio_dir", "image_dir", "upload_dir"):
        monkeypatch.setattr(settings, name, str(tmp_path / name))
    monkeypatch.setattr(settings, "vectorizer_path", str(tmp_path / "tfidf.pkl"))
    monkeypatch.setattr(settings, "vector_cache_path", str(tmp_path / "vectors.npz"))
    monkeypatch.setattr(embeddings, "_embeddings", None)


def pytest_sessionfinish(session, exitstatus):
    from sahlha.app.database.database import engine
    engine.dispose()
