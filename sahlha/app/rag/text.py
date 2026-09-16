"""Shared plain-text helpers (single home for sentence splitting).

Four modules previously each rolled their own `re.split(r"(?<=[.!?])\\s+")`
(chunking, llm fallbacks, TTS chunking). Behavior here is byte-identical to the
old copies; callers keep their own signatures and only delegate the split.
"""
from __future__ import annotations

import re

_SENTENCE_SPLIT = re.compile(r"(?<=[.!?])\s+")


def split_sentences(text: str) -> list[str]:
    """Split text into non-empty stripped sentences (pure)."""
    return [s.strip() for s in _SENTENCE_SPLIT.split(text or "") if s.strip()]


def long_sentences(texts: list[str], min_words: int = 6) -> list[str]:
    """Flatten chunk dicts/texts into sentences with at least `min_words` words."""
    out: list[str] = []
    for t in texts:
        body = t.get("text", "") if isinstance(t, dict) else t
        for s in split_sentences(body):
            if len(s.split()) >= min_words:
                out.append(s)
    return out
