"""Vector store: dense cosine search with MMR diversity + relevance backoff.

Chunks live in the relational DB (source of truth). Dense vectors are cached on
disk (ids + matrix + backend name) and rebuilt when the corpus or backend changes.
A FAISS/Chroma backend can replace this module behind the same `search` signature.

Pipeline: embed query -> cosine over filtered candidates -> MMR(λ=0.7) for
diversity -> drop near-irrelevant hits (score floor), backing off to plain top-k
when filtering would starve the agent of context.
"""
from __future__ import annotations

import os

import numpy as np
from sqlalchemy.orm import Session

from sahlha.app.database.repositories import repositories as repo
from sahlha.app.rag.embeddings import get_embeddings

MMR_LAMBDA = 0.7
MIN_SCORE = 0.05  # dense cosine floor (calibrated: paraphrase ~0.09, junk ~0.02)


def _cache_path() -> str:
    from sahlha.app.config import settings

    base = os.path.dirname(os.path.abspath(settings.vectorizer_path))
    os.makedirs(base, exist_ok=True)
    return os.path.join(base, "vectors.npz")


def rebuild_index(db: Session) -> int:
    """Full rebuild by default, but incremental for dense (encode only new chunks).

    Keeps upload fast: adding 5 chunks to a 1700-chunk corpus now encodes 5,
    not 1705 (40s -> 0.03s). TF-IDF still needs a full refit.
    """
    chunks = repo.get_chunks(db)
    if not chunks:
        return 0
    emb = get_embeddings()
    # TF-IDF must see all texts to refit the vocab
    if getattr(emb, "name", "") == "tfidf":
        texts = [c.text for c in chunks]
        emb.fit(texts)  # type: ignore[attr-defined]
        matrix = np.asarray(emb.encode(texts), dtype=np.float32)
        ids = np.array([c.id for c in chunks])
        np.savez(_cache_path(), ids=ids, matrix=matrix, backend=np.array([emb.name]))
        return len(chunks)

    # Dense: try incremental append
    cache = _cache_path()
    ids = [c.id for c in chunks]
    if os.path.exists(cache):
        try:
            z = np.load(cache, allow_pickle=True)
            if str(z["backend"][0]) == emb.name:
                cached_ids = [str(i) for i in z["ids"]]
                cached_mat = np.asarray(z["matrix"], dtype=np.float32)
                if set(cached_ids) == set(ids) and len(cached_ids) == len(ids):
                    return len(chunks)  # already warm
                if set(cached_ids).issubset(set(ids)):
                    # Only append missing
                    pos = {cid: i for i, cid in enumerate(cached_ids)}
                    missing_ids = [cid for cid in ids if cid not in pos]
                    if missing_ids and len(missing_ids) < len(ids) * 0.5:
                        id_to_text = {c.id: c.text for c in chunks}
                        missing_texts = [id_to_text[cid] for cid in missing_ids]
                        missing_mat = np.asarray(emb.encode(missing_texts), dtype=np.float32)
                        # Reassemble in original ids order
                        id_to_row = {cid: cached_mat[pos[cid]] for cid in cached_ids}
                        for cid, row in zip(missing_ids, missing_mat):
                            id_to_row[cid] = row
                        matrix = np.stack([id_to_row[cid] for cid in ids]).astype(np.float32)
                        np.savez(cache, ids=np.array(ids), matrix=matrix, backend=np.array([emb.name]))
                        return len(chunks)
        except Exception:
            pass  # fall through to full encode

    # Full dense encode (first build or large churn)
    texts = [c.text for c in chunks]
    matrix = np.asarray(emb.encode(texts), dtype=np.float32)
    np.savez(cache, ids=np.array(ids), matrix=matrix, backend=np.array([emb.name]))
    return len(chunks)


def _load_cache(ids: list[str]):
    emb = get_embeddings()
    if not os.path.exists(_cache_path()):
        return None, None
    try:
        z = np.load(_cache_path(), allow_pickle=True)
    except Exception:
        return None, None
    if str(z["backend"][0]) != emb.name:
        return None, None  # backend changed -> caller rebuilds
    cached_ids = [str(i) for i in z["ids"]]
    pos = {cid: k for k, cid in enumerate(cached_ids)}
    if any(cid not in pos for cid in ids):
        return None, None  # corpus changed -> caller rebuilds
    order = [pos[cid] for cid in ids]
    return emb, np.asarray(z["matrix"], dtype=np.float32)[order]


def _mmr(matrix: np.ndarray, q: np.ndarray, sims: np.ndarray, k: int) -> list[int]:
    selected: list[int] = []
    candidates = list(range(len(sims)))
    while candidates and len(selected) < k:
        if not selected:
            best = max(candidates, key=lambda i: float(sims[i]))
        else:
            sel_mat = matrix[selected]
            redund = (matrix[candidates] @ sel_mat.T).max(axis=1)
            scores = MMR_LAMBDA * sims[candidates] - (1 - MMR_LAMBDA) * redund
            best = candidates[int(np.argmax(scores))]
        selected.append(best)
        candidates.remove(best)
    return selected


def search(db: Session, query: str, *, top_k: int = 5,
           course_id: str | None = None, lesson_id: str | None = None,
           skill_id: str | None = None) -> list[dict]:
    from sahlha.app.config import settings

    top_k = top_k or settings.top_k_retrieval
    has_filters = bool(course_id or lesson_id or skill_id)
    chunks = repo.get_chunks(db, course_id=course_id or None, lesson_id=lesson_id or None,
                             skill_id=skill_id or None, document_id=None)
    if not chunks:
        # Scoped queries must not leak across lessons: return empty so callers
        # can fall back to the requested lesson (not the global corpus).
        # Only unfiltered queries may search globally.
        if has_filters:
            return []
        chunks = repo.get_chunks(db)  # fall back to global search
    if not chunks:
        return []
    ids = [c.id for c in chunks]
    emb, matrix = _load_cache(ids)
    if matrix is None:
        rebuild_index(db)
        emb, matrix = _load_cache(ids)
    if matrix is None:  # last resort: lexical overlap ranking
        q_terms = set(query.lower().split())
        sims = np.array([len(q_terms & set(c.text.lower().split())) for c in chunks],
                        dtype=float)
        order = np.argsort(-sims, kind="stable")[:top_k]
        picked = [(chunks[i], float(sims[i])) for i in order]
        return [_hit(c, s) for c, s in picked]

    q = np.asarray(emb.encode([query]), dtype=np.float32)[0]
    sims = (matrix @ q).astype(float)
    cand_k = min(len(chunks), max(top_k * 3, top_k))
    cand = list(np.argsort(-sims, kind="stable")[:cand_k])
    order = _mmr(matrix[cand], q, sims[cand], top_k)
    picked = [cand[i] for i in order]
    floor = MIN_SCORE if str(getattr(emb, "name", "")).startswith("dense") else -1.0
    kept = [i for i in picked if sims[i] >= floor] or picked[:1]
    return [_hit(chunks[i], float(sims[i])) for i in kept]


def _hit(c, score: float) -> dict:
    return {
        "document_id": c.document_id,
        "course_id": c.course_id,
        "lesson_id": c.lesson_id,
        "skill_id": c.skill_id,
        "page": c.page,
        "chunk_id": c.id,
        "chunk_index": c.chunk_index,
        "text": c.text,
        "score": score,
    }
