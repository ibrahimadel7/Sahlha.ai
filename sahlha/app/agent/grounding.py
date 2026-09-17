"""Deterministic RAG-grounding layer for structured agent outputs.

This module is the application-side enforcement that an LLM ``is_grounded: true``
flag can never provide. It operates ONLY on the existing RAG representation:

- Retrieval goes through ``sahlha.app.agent.tools.rag_tools`` which returns the
  real chunk dicts from ``sahlha.app.rag.vectorstore._hit``:
  ``{document_id, course_id, lesson_id, skill_id, page, chunk_id (=DocumentChunk.id),
  chunk_index, text, score}``.
- No parallel representation is introduced. Callers pass the SAME ``chunks``
  list they retrieved for generation into the attach/validate helpers below,
  so no duplicate retrieval / embedding / DB work happens here.

Three-stage contract enforced by the agent::

    LLM generation (raw Pydantic schema)
      -> attach_*_evidence (deterministic provenance, reuses ``chunks``)
      -> schema validation (strict Grounded* Pydantic models)
      -> grounding validation (this module: refs exist, belong to the current
         material, evidence present, instructional relevance, no metadata skills)

Bounded retry policy (implemented in ``agent.py``, constants here):
- Skills: LLM attempt -> validate -> on total failure, ONE fallback attempt.
  No further retries; empty result is an explicit failure state.
- Questions: LLM attempt -> critique filter -> grounding filter -> ONE
  deterministic top-up with the same ``chunks``. No LLM re-prompt loops.

All failures return machine-readable ``reasons`` so the agent can log them in
``trace`` (observable) instead of silently accepting bad output.
"""
from __future__ import annotations

import re

# Bounded regeneration: callers must not loop. One deterministic second chance.
MAX_SKILL_RETRIES = 1
MAX_QUESTION_TOPUPS = 1

_WORD_RE = re.compile(r"[^a-zA-Z ]")


def _significant_terms(text: str) -> set[str]:
    """Words longer than 4 chars, lowercased. Shared with critique logic."""
    return {w for w in _WORD_RE.sub(" ", text or "").lower().split() if len(w) > 4}


def _chunk_index_by_id(chunks: list[dict]) -> dict[str, dict]:
    return {c.get("chunk_id", ""): c for c in (chunks or []) if c.get("chunk_id")}


def _instructional_vocab(chunks: list[dict]) -> set[str]:
    """Vocabulary from instructional sentences only (metadata excluded).

    Reuses the project's existing incidental-content guard so names/dates that
    ARE the lesson topic are kept, while 'Prepared by X / School / page N'
    lines are excluded.
    """
    try:
        from sahlha.app.agent.llm import _instructional_sentences as _instr
    except Exception:  # pragma: no cover - import-time safety
        _instr = None
    vocab: set[str] = set()
    if _instr is None:
        for c in chunks or []:
            vocab |= _significant_terms(c.get("text", ""))
        return vocab
    for c in chunks or []:
        try:
            for sent, _sk in _instr([c]):
                vocab |= _significant_terms(sent)
        except Exception:
            vocab |= _significant_terms(c.get("text", ""))
    return vocab


def _full_vocab(chunks: list[dict]) -> set[str]:
    vocab: set[str] = set()
    for c in chunks or []:
        vocab |= _significant_terms(c.get("text", ""))
    return vocab


def _is_metadata_question(text: str) -> bool:
    try:
        from sahlha.app.agent.llm import _METADATA_QUESTION_RE as _rx
    except Exception:
        return False
    return bool(_rx.search(text or ""))


def _is_incidental(text: str) -> bool:
    try:
        from sahlha.app.agent.llm import _is_incidental_sentence as _fn
    except Exception:
        return False
    try:
        return bool(_fn(text or ""))
    except Exception:
        return False


def _best_chunks_for_terms(terms: set[str], chunks: list[dict], k: int = 2) -> list[dict]:
    """Rank chunks by instructional-term overlap (deterministic, no retrieval)."""
    if not chunks or not terms:
        return []
    try:
        from sahlha.app.agent.llm import _instructional_sentences as _instr
    except Exception:
        _instr = None

    scored: list[tuple[int, int]] = []
    for idx, c in enumerate(chunks):
        if _instr is not None:
            try:
                instr_text = " ".join(s for s, _ in _instr([c]))
            except Exception:
                instr_text = c.get("text", "")
        else:
            instr_text = c.get("text", "")
        overlap = len(terms & _significant_terms(instr_text))
        # Tie-break by retriever score then stable index (deterministic).
        scored.append((overlap, idx))
    scored.sort(key=lambda t: (-t[0], t[1]))
    # Keep chunks with real overlap; if none overlap, keep the top-1 so the
    # caller gets an explicit grounding failure instead of a missing-ref failure.
    # The validator will reject it as ungrounded (observable, not silent).
    top = [chunks[i] for _, i in scored[:k]]
    if scored and scored[0][0] >= 2:
        return [c for c, (ov, _) in zip(top, scored[:k]) if ov >= 1] or top[:1]
    return top[:1] if top else []


def _evidence_sentences_for_terms(terms: set[str], chunk: dict, k: int = 2) -> list[str]:
    """Pick up to k instructional sentences from chunk sharing terms."""
    from sahlha.app.rag.text import split_sentences as _split

    cands: list[tuple[int, str]] = []
    for s in _split(chunk.get("text", "")):
        if len(s.split()) < 6 or _is_incidental(s):
            continue
        cands.append((len(terms & _significant_terms(s)), s))
    cands.sort(key=lambda t: (-t[0], t[1]))
    return [s[:320] for ov, s in cands[:k] if ov >= 1] or (
        [cands[0][1][:320]] if cands else []
    )


# ---------------------------------------------------------------------------
# Evidence attachment (deterministic provenance, no LLM, no retrieval)
# ---------------------------------------------------------------------------

def attach_skill_evidence(raw_skills: list[dict], chunks: list[dict]) -> list[dict]:
    """Fill ``learning_objective`` / ``source_chunk_ids`` / ``source_evidence``.

    The LLM prompt is intentionally untouched: the model returns the raw skill
    contract and the application deterministically maps each skill back to the
    SAME retrieved chunks used for generation. Missing fields are filled so the
    strict schema can validate them; invalid mappings are left for
    :func:`validate_skill_grounding` to reject with reasons.
    """
    out: list[dict] = []
    for s in raw_skills or []:
        s = dict(s or {})
        if not s.get("learning_objective"):
            desc = (s.get("description") or "").strip()
            name = (s.get("name") or s.get("skill_id") or "").strip()
            s["learning_objective"] = desc if len(desc) >= 10 else (
                f"Understand {name}".strip() or "Understand the lesson concept."
            )
        if not s.get("source_chunk_ids") or not s.get("source_evidence"):
            skill_text = " ".join([
                str(s.get("name", "")),
                str(s.get("description", "")),
                str(s.get("learning_objective", "")),
                " ".join(s.get("key_concepts", []) or []),
            ])
            terms = _significant_terms(skill_text)
            best = _best_chunks_for_terms(terms, chunks or [], k=2)
            if not s.get("source_chunk_ids"):
                s["source_chunk_ids"] = [c.get("chunk_id", "") for c in best if c.get("chunk_id")]
            if not s.get("source_evidence"):
                ev: list[str] = []
                for c in best:
                    ev.extend(_evidence_sentences_for_terms(terms, c, k=1))
                s["source_evidence"] = ev[:2]
        out.append(s)
    return out


def attach_question_evidence(questions: list[dict], chunks: list[dict]) -> list[dict]:
    """Fill per-question ``source_chunk_ids`` / ``source_evidence`` deterministically."""
    out: list[dict] = []
    for q in questions or []:
        q = dict(q or {})
        if not q.get("source_chunk_ids") or not q.get("source_evidence"):
            qterms = _significant_terms(
                f"{q.get('question', '')} {' '.join(q.get('options', []) or [])} {q.get('explanation', '')}"
            )
            best = _best_chunks_for_terms(qterms, chunks or [], k=1)
            if not q.get("source_chunk_ids"):
                q["source_chunk_ids"] = [c.get("chunk_id", "") for c in best if c.get("chunk_id")]
            if not q.get("source_evidence"):
                ev: list[str] = []
                for c in best:
                    ev.extend(_evidence_sentences_for_terms(qterms, c, k=1))
                q["source_evidence"] = ev[:1]
        out.append(q)
    return out


# ---------------------------------------------------------------------------
# Grounding validation (application truth, never an LLM boolean)
# ---------------------------------------------------------------------------

def validate_skill_grounding(
    skill: dict, chunks: list[dict], course_id: str, lesson_id: str
) -> tuple[bool, list[str]]:
    """Check one enriched skill against the SAME retrieved chunks.

    Returns (ok, reasons). ``ok`` is True only when every check passes:
    refs exist, belong to (course_id, lesson_id), evidence is present and
    quoted from the cited chunks, and the skill is educationally relevant
    (instructional overlap, not incidental metadata).
    """
    reasons: list[str] = []
    skill = skill or {}
    by_id = _chunk_index_by_id(chunks or [])

    if not chunks:
        return False, ["empty retrieval: no RAG evidence available; refusing to fabricate skills"]

    refs = skill.get("source_chunk_ids", []) or []
    ev = skill.get("source_evidence", []) or []
    if not refs:
        reasons.append("missing source_chunk_ids: skill has no RAG references")
    if not ev or not any(str(e or "").strip() for e in ev):
        reasons.append("missing source_evidence: skill has no quoted evidence")

    for cid in refs:
        hit = by_id.get(cid, None)
        if hit is None:
            reasons.append(f"unknown source_chunk_id: {cid!r} not in current retrieval")
            continue
        if hit.get("course_id") != course_id or hit.get("lesson_id") != lesson_id:
            reasons.append(
                f"source mismatch: chunk {cid!r} belongs to "
                f"{hit.get('course_id')}/{hit.get('lesson_id')}, "
                f"not {course_id}/{lesson_id}"
            )

    # Evidence must come from the cited chunks (normalized substring OR term overlap).
    for snippet in [str(e or "") for e in ev if str(e or "").strip()]:
        norm = re.sub(r"\s+", " ", snippet.strip().lower())
        found = False
        for cid in refs:
            hit = by_id.get(cid)
            if not hit:
                continue
            hay = re.sub(r"\s+", " ", (hit.get("text", "") or "").lower())
            if norm and (norm in hay or len(_significant_terms(snippet) & _significant_terms(hay)) >= 2):
                found = True
                break
        if not found:
            reasons.append(f"evidence not supported by cited chunks: {snippet[:80]!r}")
            break  # one evidence failure is enough to reject

    # Relevance: instructional overlap, never metadata.
    skill_text = " ".join([
        str(skill.get("name", "")),
        str(skill.get("description", "")),
        str(skill.get("learning_objective", "")),
        " ".join(skill.get("key_concepts", []) or []),
    ])
    sterms = _significant_terms(skill_text)
    instr = _instructional_vocab(chunks or [])
    if len(sterms & instr) < 2:
        # Distinguish metadata skills ("Identify the teacher") from merely weak ones.
        if _is_metadata_question(skill_text) or _is_incidental(skill_text):
            reasons.append("irrelevant: skill tests incidental document metadata, not the learning objective")
        else:
            reasons.append("ungrounded: skill shares <2 significant terms with instructional content")

    loterms = _significant_terms(str(skill.get("learning_objective", "")))
    if len(loterms & instr) < 2:
        reasons.append("unsupported learning_objective: not entailed by retrieved instructional content")

    return (not reasons), reasons


def validate_question_grounding(
    question: dict,
    chunks: list[dict],
    valid_skill_ids: set[str],
    course_id: str,
    lesson_id: str,
) -> tuple[bool, list[str]]:
    """Check one enriched question: structure is assumed pre-validated by Pydantic.

    Covers: skill reference, source refs/existence/scope, evidence support,
    grounded (>=2 terms) and relevant (not metadata trivia + instructional >=2).
    """
    reasons: list[str] = []
    q = question or {}
    by_id = _chunk_index_by_id(chunks or [])

    skid = str(q.get("skill_id", "") or "")
    if not skid:
        reasons.append("missing skill_id")
    elif valid_skill_ids and skid not in valid_skill_ids:
        reasons.append(f"references nonexistent skill: {skid!r}")

    if not chunks:
        return False, reasons + ["empty retrieval: no RAG evidence available"]

    refs = q.get("source_chunk_ids", []) or []
    ev = q.get("source_evidence", []) or []
    if not refs:
        reasons.append("missing source_chunk_ids")
    if not ev or not any(str(e or "").strip() for e in ev):
        reasons.append("missing source_evidence")
    for cid in refs:
        hit = by_id.get(cid)
        if hit is None:
            reasons.append(f"unknown source_chunk_id: {cid!r} not in current retrieval")
        elif hit.get("course_id") != course_id or hit.get("lesson_id") != lesson_id:
            reasons.append(f"source mismatch: chunk {cid!r} not in {course_id}/{lesson_id}")

    for snippet in [str(e or "") for e in ev if str(e or "").strip()]:
        norm = re.sub(r"\s+", " ", snippet.strip().lower())
        found = any(
            norm and (
                norm in re.sub(r"\s+", " ", ((by_id.get(cid) or {}).get("text", "") or "").lower())
                or len(_significant_terms(snippet) & _significant_terms((by_id.get(cid) or {}).get("text", ""))) >= 2
            )
            for cid in refs if by_id.get(cid)
        )
        if not found:
            reasons.append(f"evidence not supported by cited chunks: {snippet[:80]!r}")
            break

    qtext = str(q.get("question", "") or "")
    qterms = _significant_terms(
        f"{qtext} {' '.join(q.get('options', []) or [])} {q.get('explanation', '')}"
    )
    if len(qterms & _full_vocab(chunks or [])) < 2:
        reasons.append("ungrounded: question shares <2 significant terms with retrieved material")
    if _is_metadata_question(qtext):
        reasons.append("irrelevant: question tests incidental document metadata")
    elif len(qterms & _instructional_vocab(chunks or [])) < 2:
        reasons.append("irrelevant: question not supported by instructional content")

    return (not reasons), reasons


def partition_skills(
    skills: list[dict], chunks: list[dict], course_id: str, lesson_id: str
) -> tuple[list[dict], list[dict]]:
    """Split enriched skills into (accepted, rejected[{skill, reasons}])."""
    accepted: list[dict] = []
    rejected: list[dict] = []
    for s in skills or []:
        ok, reasons = validate_skill_grounding(s, chunks or [], course_id, lesson_id)
        if ok:
            accepted.append(s)
        else:
            rejected.append({"skill_id": s.get("skill_id", "?"), "reasons": reasons})
    return accepted, rejected


def partition_questions(
    questions: list[dict],
    chunks: list[dict],
    valid_skill_ids: set[str],
    course_id: str,
    lesson_id: str,
) -> tuple[list[dict], list[dict]]:
    """Split enriched questions into (accepted, rejected[{index, reasons}])."""
    accepted: list[dict] = []
    rejected: list[dict] = []
    for i, q in enumerate(questions or []):
        ok, reasons = validate_question_grounding(q, chunks or [], valid_skill_ids, course_id, lesson_id)
        if ok:
            accepted.append(q)
        else:
            rejected.append({"index": i, "skill_id": q.get("skill_id", "?"), "reasons": reasons})
    return accepted, rejected
