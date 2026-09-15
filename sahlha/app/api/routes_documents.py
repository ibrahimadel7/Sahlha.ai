"""POST /documents/upload, POST /documents/{id}/process (re-process = re-ingest not needed; process is part of upload)."""
from __future__ import annotations

from fastapi import APIRouter, BackgroundTasks, Depends, File, Form, HTTPException, UploadFile
from sqlalchemy.orm import Session

from sahlha.app.database.database import SessionLocal, get_db
from sahlha.app.services import services as svc

router = APIRouter(prefix="/documents", tags=["documents"])


def _background_warm_index() -> None:
    """Rebuild vectors off the request thread so upload stays snappy."""
    try:
        from sahlha.app.rag import vectorstore

        db = SessionLocal()
        try:
            vectorstore.rebuild_index(db)
        finally:
            db.close()
    except Exception:
        pass  # next search will fallback to keyword ranking


@router.post("/upload")
def upload_document(course_id: str = Form("general"), lesson_id: str = Form("lesson_1"),
                    skill_id: str = Form("general"), file: UploadFile = File(...),
                    background_tasks: BackgroundTasks = None,
                    db: Session = Depends(get_db)):
    # file.file.read can block for large uploads; cap at 25MB already enforced in ingestion
    data = file.file.read()
    try:
        result = svc.upload_and_process(db, file_bytes=data, filename=file.filename or "upload.txt",
                                        course_id=course_id, lesson_id=lesson_id, skill_id=skill_id,
                                        eager=False)
    except ValueError as exc:
        raise HTTPException(400, str(exc))
    # Warm the dense index in background — don't block the 200 response.
    # Tests call ingestion directly with eager=True, so they still get a synchronous build.
    if background_tasks is not None and result.get("chunk_count", 0) > 0:
        background_tasks.add_task(_background_warm_index)
    return result


@router.post("/{doc_id}/process")
def process_document(doc_id: str, db: Session = Depends(get_db)):
    from sahlha.app.database.repositories import repositories as repo

    doc = repo.get_document(db, doc_id)
    if not doc:
        raise HTTPException(404, f"Document {doc_id} not found")
    chunks = repo.get_chunks(db, document_id=doc_id)
    return {"document_id": doc_id, "status": doc.status, "chunk_count": len(chunks)}
