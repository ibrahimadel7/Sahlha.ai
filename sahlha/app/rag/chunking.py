"""Sentence-aware chunker with overlap (never splits mid-sentence).

Packs whole sentences up to ~chunk_size chars; consecutive chunks overlap by
repeating trailing sentences (~chunk_overlap chars). Falls back to hard splits
for pathological (sentence-free) text.
"""
from __future__ import annotations

import re

from sahlha.app.rag.text import split_sentences


def clean_text(text: str) -> str:
    lines = [ln.strip() for ln in text.splitlines()]
    lines = [ln for ln in lines if ln]
    return re.sub(r"\s+", " ", " ".join(lines)).strip()


def _sentences(text: str) -> list[str]:
    parts = split_sentences(text)
    return parts or ([text] if text else [])


def chunk_text(text: str, *, chunk_size: int = 800, chunk_overlap: int = 120,
               course_id: str = "general", lesson_id: str = "lesson_1",
               skill_id: str = "general", document_id: str = "", page: int = 0,
               start_index: int = 0) -> list[dict]:
    text = clean_text(text)
    if not text:
        return []
    sentences = _sentences(text)
    # Hard-split any monster sentence so no chunk explodes.
    split: list[str] = []
    for s in sentences:
        while len(s) > chunk_size:
            split.append(s[:chunk_size])
            s = s[chunk_size:]
        split.append(s)
    sentences = [s for s in split if s]

    chunks: list[dict] = []
    idx = start_index
    cur: list[str] = []
    cur_len = 0
    for s in sentences:
        if cur and cur_len + 1 + len(s) > chunk_size:
            chunks.append(_make(cur, idx, course_id, lesson_id, skill_id, document_id, page))
            idx += 1
            # Overlap: carry trailing sentences covering ~chunk_overlap chars.
            carry: list[str] = []
            carry_len = 0
            for prev in reversed(cur):
                if carry_len >= chunk_overlap:
                    break
                carry.insert(0, prev)
                carry_len += len(prev) + 1
            cur, cur_len = carry, carry_len
        cur.append(s)
        cur_len += len(s) + 1
    if cur and (not chunks or " ".join(cur) != chunks[-1]["text"]):
        chunks.append(_make(cur, idx, course_id, lesson_id, skill_id, document_id, page))
    return chunks


def _make(sentences: list[str], idx: int, course_id: str, lesson_id: str,
          skill_id: str, document_id: str, page: int) -> dict:
    return {
        "document_id": document_id,
        "course_id": course_id,
        "lesson_id": lesson_id,
        "skill_id": skill_id,
        "page": page,
        "chunk_index": idx,
        "text": " ".join(sentences).strip(),
        # Platform compat defaults (chunk_blocks schema expects these).
        "section": "",
        "section_id": "",
        "type": "paragraph",
        "block_metadata": {},
    }


def sentence_chunks(text: str, size: int = 800, overlap: int = 120) -> list[str]:
    """Platform compat: plain sentence strings (no metadata)."""
    return [c["text"] for c in chunk_text(text, chunk_size=size, chunk_overlap=overlap,
                                          course_id="general", lesson_id="lesson_1",
                                          skill_id="general", document_id="", page=0)]


def chunk_blocks(blocks, *, chunk_size: int = 800, chunk_overlap: int = 120,
                 course_id: str = "general", lesson_id: str = "lesson_1",
                 skill_id: str = "general", document_id: str = "") -> list[dict]:
    """Platform compat: chunk pre-segmented DocumentBlocks via chunk_text.

    Full block-aware splitting lives in pr-1; this preserves correct
    persistence (section/type defaults) without forking the tested packer.
    """
    out: list[dict] = []
    idx = 0
    for b in (blocks or []):
        text = getattr(b, "text", "") if not isinstance(b, dict) else (b.get("text", "") or "")
        page = getattr(b, "page", 0) if not isinstance(b, dict) else (b.get("page", 0) or 0)
        section = getattr(b, "section", "") if not isinstance(b, dict) else (b.get("section", "") or "")
        if not (text or "").strip():
            continue
        for c in chunk_text(text, chunk_size=chunk_size, chunk_overlap=chunk_overlap,
                            course_id=course_id, lesson_id=lesson_id,
                            skill_id=skill_id, document_id=document_id, page=page or 0):
            if section:
                c["section"] = section
            c["chunk_index"] = idx
            idx += 1
            out.append(c)
    return out
