"""FastAPI entrypoint. Thin routes; logic lives in services/agent/tools."""
from __future__ import annotations

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from sahlha.app.api import (routes_agent, routes_assessment, routes_audio, routes_auth,
                            routes_catalog, routes_classrooms, routes_documents, routes_images,
                            routes_materials, routes_parent, routes_student, routes_teacher,
                            routes_teacher_platform, routes_workflow)
from sahlha.app.config import settings
from sahlha.app.database.database import init_db


@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    # Warm embedding backend off-thread so first upload doesn't pay cold-start cost
    try:
        if getattr(settings, "embedding_warmup", True):
            from threading import Thread
            from sahlha.app.rag.embeddings import get_embeddings
            Thread(target=get_embeddings, name="embedding-warmup", daemon=True).start()
        else:
            import threading

            from sahlha.app.rag.embeddings import get_embeddings

            threading.Thread(target=get_embeddings, daemon=True).start()
    except Exception:
        pass
    yield


app = FastAPI(title="Sahlha AI Learning Platform", lifespan=lifespan)

# Mobile development: emulator / physical device / Flutter web. Credentials are
# bearer tokens (Flutter secure storage), not cookies — origins stay explicit.
# Detached HTML/JS testing frontend is served same-origin at /app (no CORS needed).
_origins = ["http://localhost:3000", "http://127.0.0.1:3000",
            "http://localhost:8080", "http://127.0.0.1:8080",
            "http://localhost:8081", "http://127.0.0.1:8081",
            "http://localhost:5000", "http://127.0.0.1:5000"]
try:
    _extra = (getattr(settings, "cors_extra_origins", "") or "").strip()
except Exception:
    _extra = ""
if _extra:
    if _extra.strip() == "*":
        _origins = ["*"]
    else:
        _origins += [o.strip() for o in _extra.split(",") if o.strip()]
app.add_middleware(
    CORSMiddleware,
    allow_origins=_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
# Platform APIs (authenticated, RBAC-enforced).
app.include_router(routes_auth.router)
app.include_router(routes_classrooms.router)
app.include_router(routes_materials.router)
app.include_router(routes_student.router)
app.include_router(routes_teacher_platform.router)
app.include_router(routes_parent.router)
# Legacy AI-loop APIs (kept working during transition; Streamlit dev tool + existing tests use them).
# Mounted unconditionally so both mobile platform and legacy clients work. Gate via
# LEGACY_DEV_API_ENABLED only when legacy clients are retired.
app.include_router(routes_documents.router)
app.include_router(routes_agent.router)
app.include_router(routes_teacher.router)
app.include_router(routes_assessment.router)
app.include_router(routes_audio.router)
app.include_router(routes_images.router)
app.include_router(routes_catalog.router)
app.include_router(routes_workflow.router)

# Serve the detached testing frontend at /app (if frontend/ exists)
try:
    import pathlib
    _frontend_dir = pathlib.Path(__file__).resolve().parents[2] / "frontend"
    if _frontend_dir.is_dir():
        app.mount("/app", StaticFiles(directory=str(_frontend_dir), html=True), name="frontend")
except Exception:
    pass


@app.get("/")
def root():
    return {"service": "sahlha", "status": "ok"}


@app.get("/health")
def health():
    """Liveness + non-secret availability flags.

    Reports only booleans (TTS/image configured) so operators can verify
    `.env` keys are loaded without ever logging or exposing secret values.
    """
    from sahlha.app.audio import tts as tts_mod
    from sahlha.app.images import pexels as pexels_mod
    from sahlha.app.agent.llm import llm_available
    from sahlha.app.config import settings as _settings

    try:
        from sahlha.app.rag import embeddings as _emb
        _dense_available = bool(_emb.get_embeddings().dense)
    except Exception:
        _dense_available = False
    try:
        from sentence_transformers import CrossEncoder as _CE  # noqa: F401
        _reranker_available = True
    except Exception:
        _reranker_available = False
    from sahlha.app.rag.ocr import discover_tesseract
    return {"ok": True, "tts_configured": tts_mod.tts_available(),
            "images_configured": pexels_mod.pexels_available(),
            "llm_configured": llm_available(),
            "dense_embeddings_enabled": bool(_settings.dense_embeddings_enabled),
            "dense_embeddings_available": _dense_available,
            "reranker_enabled": bool(_settings.reranker_enabled),
            "reranker_available": bool(_reranker_available),
            "ocr_available": bool(discover_tesseract())}
