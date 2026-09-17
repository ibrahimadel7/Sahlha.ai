import sys
from types import SimpleNamespace

import numpy as np
import pytest

from sahlha.app.config import settings
from sahlha.app.database.repositories import repositories as repo
from sahlha.app.rag import embeddings, vectorstore
from sahlha.app.rag.chunking import chunk_text, sentence_chunks


class DenseFake:
    dense = True
    backend = 'dense:test'
    def __init__(self):
        self.encoded = []
    def embed(self, texts):
        self.encoded.extend(texts)
        result = np.zeros((len(texts), 384), dtype=np.float32)
        for i, text in enumerate(texts):
            result[i, 0 if any(w in text.lower() for w in ('repeat', 'loop', 'iteration')) else 1] = 1
        return result
    fit = embed
    def embed_query(self, query):
        return self.embed([query])


def corpus(db, n=5, lesson='one'):
    doc = repo.create_document(db, filename='a.txt', course_id='course', lesson_id=lesson, skill_id='loops')
    repo.add_chunks(db, [dict(document_id=doc.id, course_id='course', lesson_id=lesson,
                             skill_id='loops', text=f'Loops repeat instructions {i}.', chunk_index=i) for i in range(n)])
    return doc


def test_sentence_boundaries_and_metadata():
    text = 'First sentence stays complete. Second sentence stays complete. Third sentence stays complete.'
    chunks = chunk_text(text, chunk_size=65, chunk_overlap=32, course_id='c', lesson_id='l', page=3, document_id='d')
    assert all(c['text'].endswith('.') and len(c['text']) <= 65 for c in chunks)
    assert chunks[1]['text'].startswith('Second sentence')
    assert all(c['course_id'] == 'c' and c['page'] == 3 for c in chunks)
    assert sentence_chunks('x' * 100, 30, 5) == ['x' * 30, 'x' * 30, 'x' * 30, 'x' * 10]


def test_dense_contract_and_normalization(monkeypatch):
    calls = {}
    class Model:
        def __init__(self, name): calls['name'] = name
        def encode(self, texts, **kwargs):
            calls.update(kwargs)
            return np.ones((len(texts), 384)) / np.sqrt(384)
    monkeypatch.setitem(sys.modules, 'sentence_transformers', SimpleNamespace(SentenceTransformer=Model))
    dense = embeddings.DenseEmbeddingModel()
    values = dense.embed(['loop'])
    assert values.shape == (1, 384)
    assert np.isclose(np.linalg.norm(values[0]), 1)
    assert calls['normalize_embeddings'] is True
    assert calls['name'] == settings.embedding_model


def test_failed_dense_load_uses_tfidf(monkeypatch):
    monkeypatch.setattr(settings, 'dense_embeddings_enabled', True)
    monkeypatch.setattr(embeddings, 'DenseEmbeddingModel', lambda: (_ for _ in ()).throw(ImportError('torch')))
    assert isinstance(embeddings.get_embeddings(), embeddings.TfidfEmbeddingModel)
    assert not embeddings.dense_available()


def test_cache_incremental_content_changes_and_order(db_session, monkeypatch):
    fake = DenseFake()
    monkeypatch.setattr(embeddings, '_embeddings', fake)
    doc = corpus(db_session)
    vectorstore.rebuild_index(db_session)
    assert len(fake.encoded) == 5
    vectorstore.rebuild_index(db_session)
    assert len(fake.encoded) == 5
    repo.add_chunks(db_session, [dict(document_id=doc.id, course_id='course', lesson_id='one', skill_id='loops', text='New loop statement.', chunk_index=5)])
    vectorstore.rebuild_index(db_session)
    assert fake.encoded[-1] == 'New loop statement.' and len(fake.encoded) == 6
    rows = repo.get_chunks(db_session)
    rows[0].text = 'Changed curriculum sentence.'
    db_session.commit()
    vectorstore.rebuild_index(db_session)
    assert fake.encoded[-1] == rows[0].text and len(fake.encoded) == 7
    with np.load(settings.vector_cache_path, allow_pickle=False) as data:
        assert data['ids'].tolist() == [c.id for c in repo.get_chunks(db_session)]
        assert data['backend'].item() == fake.backend
        assert data['vectors'][0, 1] == 1
    fake.backend = 'dense:new-model'
    vectorstore.rebuild_index(db_session)
    assert len(fake.encoded) == 13


def test_semantic_retrieval_scope_mmr_and_score_backoff(db_session, monkeypatch):
    fake = DenseFake()
    monkeypatch.setattr(embeddings, '_embeddings', fake)
    corpus(db_session, 1)
    corpus(db_session, 1, 'other')
    result = vectorstore.search(db_session, 'iteration', course_id='course', lesson_id='one', skill_id='loops')
    assert len(result) == 1 and result[0]['lesson_id'] == 'one'
    assert not vectorstore.search(db_session, 'iteration', course_id='other')
    assert not vectorstore.search(db_session, 'iteration', course_id='course', lesson_id='missing')
    vectors = np.array([[1, 0], [1, 0], [0, 1]], dtype=float)
    assert vectorstore.mmr_select(vectors, np.array([1, .99, .8]), 2) == [0, 2]
    monkeypatch.setattr(fake, 'embed_query', lambda _: np.array([[.049] + [0] * 383]))
    assert vectorstore.search(db_session, 'unmatched', course_id='course', lesson_id='one')
    monkeypatch.setattr(fake, 'embed_query', lambda _: np.zeros((1, 384)))
    assert not vectorstore.search(db_session, 'unmatched', course_id='course', lesson_id='one')


def test_real_dense_paraphrase_when_available():
    try:
        model = embeddings.DenseEmbeddingModel()
    except Exception as exc:
        pytest.skip(f'Optional dense integration unavailable: {type(exc).__name__}')
    docs = model.embed(['A loop repeats a sequence of instructions.', 'A plant absorbs sunlight to make food.'])
    scores = docs @ model.embed_query('How does iteration execute the same steps again?')[0]
    assert scores[0] > scores[1]
