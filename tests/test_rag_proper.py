"""Proper RAG: semantic (not just lexical) retrieval, sentence-safe chunks, cached index."""
import os

import pytest

from sahlha.app.rag import chunking, ingestion, retriever, vectorstore
from sahlha.app.rag.embeddings import dense_available, get_embeddings
from tests.conftest import SAMPLE_TEXT

LONG = ("Python conditionals steer decisions in code. " * 2 +
        "The if statement runs a block only when its condition holds true. " * 2 +
        "Elif means else if and tests a further condition when earlier ones fail. " * 2 +
        "Only the first satisfied branch ever executes its block. " * 2 +
        "A trailing else covers every remaining case. " * 2)


def test_chunks_never_split_mid_sentence():
    chunks = chunking.chunk_text(LONG, chunk_size=200, chunk_overlap=60)
    assert len(chunks) >= 2, "text must produce multiple chunks"
    for c in chunks:
        assert c["text"][-1] in ".!?", f"chunk cut mid-sentence: …{c['text'][-40:]}"
    # Overlap: neighbours share content instead of hard cuts
    assert any(set(chunks[i]["text"].split()) & set(chunks[i + 1]["text"].split())
               for i in range(len(chunks) - 1))


def test_rebuild_caches_vectors(db_session, tmp_path, monkeypatch):
    from sahlha.app import config as _cfg

    monkeypatch.setattr(_cfg.settings, "vectorizer_path", str(tmp_path / "vec.pkl"))
    ingestion.ingest_upload(db_session, file_bytes=LONG.encode(), filename="c.txt",
                            course_id="rc", lesson_id="rl", skill_id="rs")
    cache = vectorstore._cache_path()
    assert os.path.exists(cache), "rebuild must persist the vector cache"
    before = os.path.getmtime(cache)
    hits = retriever.retrieve(db_session, "branching choices", top_k=2)
    assert hits and all("score" in h for h in hits)
    assert os.path.getmtime(cache) == before, "second search must reuse cache, not rebuild"


@pytest.mark.skipif(not dense_available(), reason="dense model unavailable; skipping semantic check")
def test_semantic_paraphrase_retrieval(db_session):
    """A paraphrase with almost no shared keywords must still find the elif material."""
    ingestion.ingest_upload(db_session, file_bytes=(SAMPLE_TEXT * 2).encode(),
                            filename="elif.txt", course_id="sem", lesson_id="sem_l",
                            skill_id="sem_s")
    assert get_embeddings().name.startswith("dense")
    hits = retriever.retrieve(db_session, "how to pick one path among several options",
                              top_k=3)
    assert hits, "semantic search returned nothing"
    assert "elif" in hits[0]["text"].lower(), f"top hit missed the topic: {hits[0]['text'][:120]}"
    assert hits[0]["score"] > 0.05
