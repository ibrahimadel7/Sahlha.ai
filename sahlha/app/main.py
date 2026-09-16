"""FastAPI entrypoint. Thin routes; logic lives in services/agent/tools."""
from __future__ import annotations

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from sahlha.app.api import routes_agent, routes_assessment, routes_audio, routes_catalog, routes_documents, routes_images, routes_teacher, routes_workflow
from sahlha.app.database.database import init_db


@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    # Warm embedding backend off-thread so first upload doesn't pay cold-start cost
    try:
        import threading

        from sahlha.app.rag.embeddings import get_embeddings

        threading.Thread(target=get_embeddings, daemon=True).start()
    except Exception:
        pass
    yield


app = FastAPI(title="Sahlha AI Learning Agent (MVP)", lifespan=lifespan)
# CORS for the detached HTML/JS testing frontend (and any local dev UI)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
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
    return {"service": "sahlha-mvp", "status": "ok"}


@app.get("/health")
def health():
    return {"ok": True}
