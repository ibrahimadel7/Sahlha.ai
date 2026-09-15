"""Embeddings: dense semantic vectors first, TF-IDF fallback when unavailable.

`DenseEmbeddingModel` (MiniLM-L6-v2, 384-d, L2-normalized) is the primary backend.
`TfidfEmbeddingModel` keeps the pipeline working offline / without torch.
Callers use `get_embeddings()` which returns whichever backend initialized.
A sentence-transformer/remote-embedding backend can replace this module wholesale.
"""
from __future__ import annotations

import os
import pickle

import numpy as np

DENSE_MODEL_NAME = "sentence-transformers/all-MiniLM-L6-v2"


class DenseEmbeddingModel:
    name = "dense:" + DENSE_MODEL_NAME

    def __init__(self) -> None:
        from sentence_transformers import SentenceTransformer

        self._model = SentenceTransformer(DENSE_MODEL_NAME)

    def encode(self, texts: list[str]) -> np.ndarray:
        return np.asarray(
            self._model.encode(texts, normalize_embeddings=True, show_progress_bar=False),
            dtype=np.float32)


class TfidfEmbeddingModel:
    name = "tfidf"

    def __init__(self) -> None:
        from sahlha.app.config import settings

        self._path = settings.vectorizer_path
        self.vectorizer = None

    def fit(self, texts: list[str]):
        from sklearn.feature_extraction.text import TfidfVectorizer

        self.vectorizer = TfidfVectorizer(max_features=5000, ngram_range=(1, 2),
                                          stop_words="english")
        mat = self.vectorizer.fit_transform(texts)
        os.makedirs(os.path.dirname(os.path.abspath(self._path)), exist_ok=True)
        with open(self._path, "wb") as fh:
            pickle.dump(self.vectorizer, fh)
        return mat

    def load(self) -> bool:
        if os.path.exists(self._path):
            with open(self._path, "rb") as fh:
                self.vectorizer = pickle.load(fh)
            return True
        return False

    def encode(self, texts: list[str]) -> np.ndarray:
        from sklearn.preprocessing import normalize

        if self.vectorizer is None and not self.load():
            self.fit(texts)
        assert self.vectorizer is not None
        return normalize(self.vectorizer.transform(texts)).toarray().astype(np.float32)


_embeddings = None


def get_embeddings():
    """Dense unless the model can't load (offline/no torch) — then TF-IDF."""
    global _embeddings
    if _embeddings is not None:
        return _embeddings
    try:
        _embeddings = DenseEmbeddingModel()
    except Exception:
        _embeddings = TfidfEmbeddingModel()
    return _embeddings


def dense_available() -> bool:
    try:
        DenseEmbeddingModel()
        return True
    except Exception:
        return False
