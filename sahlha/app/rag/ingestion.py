"""Ingestion: bytes -> extract -> clean -> chunk -> persist -> reindex."""
from __future__ import annotations

import os

from sqlalchemy.orm import Session

from sahlha.app.config import settings
from sahlha.app.database.repositories import repositories as repo
from sahlha.app.rag import vectorstore
from sahlha.app.rag.chunking import chunk_text
from sahlha.app.rag.ocr import extract_document_text


def _safe_filename(filename: str, doc_id: str) -> str:
    """Strip directories, control chars; cap length. Prevents path traversal."""
    import re

    base = os.path.basename(filename or "upload.bin").strip() or "upload.bin"
    base = re.sub(r"[^A-Za-z0-9._-]+", "_", base).strip("._") or "upload.bin"
    return f"{doc_id}_{base[:120]}"


def _extract_lesson_id(filename: str, text: str, provided: str) -> str:
    """Auto-extract lesson_id from PDF when user leaves it as default.

    Priority: explicit user value (not 'lesson_1'/'general') → PDF metadata title → first
    meaningful line of extracted text → filename stem. Slugified to snake_case.
    """
    import re

    provided = (provided or "").strip()
    if provided and provided not in ("lesson_1", "general", "lesson1"):
        return re.sub(r"[^a-z0-9]+", "_", provided.lower()).strip("_") or "lesson_1"
    # Try filename stem
    stem = os.path.splitext(os.path.basename(filename or ""))[0].strip()
    # Try first meaningful line of text (often the title)
    first_line = ""
    for line in (text or "").splitlines():
        line = line.strip()
        if len(line) >= 3 and len(line.split()) >= 2:
            # Skip generic headers like "Page 1"
            if re.match(r"^(page\s*\d+|table of contents)$", line, re.I):
                continue
            first_line = line
            break
    candidate = first_line or stem or provided or "lesson_1"
    # Take up to first 6 words, slugify
    words = re.sub(r"[^A-Za-z0-9 ]+", " ", candidate).strip().split()
    slug = "_".join(w.lower() for w in words[:6] if len(w) > 1)
    slug = re.sub(r"[^a-z0-9]+", "_", slug.lower()).strip("_")
    # Fallback to filename slug
    if not slug or len(slug) < 3:
        slug = re.sub(r"[^a-z0-9]+", "_", stem.lower()).strip("_") or "lesson_1"
    return slug[:80]


def ingest_upload(db: Session, *, file_bytes: bytes, filename: str,
                  course_id: str = "general", lesson_id: str = "lesson_1",
                  skill_id: str = "general", eager: bool = True) -> dict:
    if len(file_bytes) > 25 * 1024 * 1024:
        raise ValueError("File too large (max 25MB)")
    # Extract text first so we can auto-derive lesson_id from PDF content when user left it default
    extracted = extract_document_text(file_bytes, filename)
    if not extracted.text.strip():
        raise ValueError("Empty file: no extractable text found (upload a non-empty pdf/txt/docx/image)")
    # Auto-extract lesson_id from PDF if user didn't provide a meaningful one
    lesson_id = _extract_lesson_id(filename, extracted.text, lesson_id)
    course_id = (course_id or "general").strip() or "general"
    # Slugify course_id as well (keep user value if explicit)
    import re as _re2
    course_id = _re2.sub(r"[^a-z0-9]+", "_", course_id.lower()).strip("_") or "general"
    doc = repo.create_document(db, filename=os.path.basename(filename or "upload.bin")[:255],
                               course_id=course_id,
                               lesson_id=lesson_id, skill_id=skill_id)
    os.makedirs(settings.upload_dir, exist_ok=True)
    with open(os.path.join(settings.upload_dir, _safe_filename(filename, doc.id)), "wb") as fh:
        fh.write(file_bytes)

    # extracted already available; reuse
    chunks = chunk_text(extracted.text, chunk_size=settings.chunk_size,
                        chunk_overlap=settings.chunk_overlap, course_id=course_id,
                        lesson_id=lesson_id, skill_id=skill_id, document_id=doc.id)
    if chunks:
        repo.add_chunks(db, chunks)
    repo.mark_document_processed(db, doc, char_count=len(extracted.text), chunk_count=len(chunks))
    if chunks and eager:
        try:
            vectorstore.rebuild_index(db)
        except Exception:
            pass  # retrieval falls back to keyword ranking when eager rebuild fails
    # When eager=False the HTTP route schedules a background warmup so the upload
    # returns fast even with 1000s of chunks or a cold dense model (~5s load).
    return {
        "document_id": doc.id,
        "filename": doc.filename,
        "course_id": course_id,
        "lesson_id": lesson_id,
        "skill_id": skill_id,
        "method": extracted.method,
        "is_scanned": extracted.is_scanned,
        "num_pages": extracted.num_pages,
        "char_count": len(extracted.text),
        "chunk_count": len(chunks),
        "text_preview": extracted.text[:500],
    }
