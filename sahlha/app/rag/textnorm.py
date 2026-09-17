"""Multilingual text normalization + tokenization for lexical retrieval.

Preserves Arabic words, Latin words, snake_case/code identifiers and meaningful
numbers. Normalizes Arabic conservatively (no aggressive stemming).
"""
from __future__ import annotations

import re
import unicodedata

# Arabic diacritics + tatweel
_AR_DIACRITICS = re.compile(r"[\u0610-\u061A\u064B-\u065F\u06D6-\u06ED\u0640]")
_ALEF_VARIANTS = str.maketrans({"أ": "ا", "إ": "ا", "آ": "ا", "ٱ": "ا"})
_TA_MARBUTA = str.maketrans({"ة": "ه"})
_ALEF_MAQSURA = str.maketrans({"ى": "ي"})

# Minimal multilingual stop list (safe across EN/AR). TF-IDF must NOT use the
# sklearn English stop list globally, which harms Arabic/mixed retrieval.
_MULTILINGUAL_STOP = frozenset({
    "the", "and", "this", "that", "with", "from", "lesson", "material",
    "which", "what", "question", "answer", "based", "complete", "statement",
    "من", "في", "على", "إلى", "عن", "أن", "إن", "هو", "هي", "هذا", "هذه",
    "ذلك", "التي", "الذي", "مع", "بين", "كما", "قد", "لم", "لن", "ما", "لا",
})

_TOKEN_RE = re.compile(
    r"[A-Za-z_][A-Za-z0-9_]*"  # Latin / snake_case / code identifiers
    r"|[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF]+"  # Arabic words
    r"|\d+(?:[.,]\d+)?",  # numbers (keep decimals)
    re.UNICODE,
)


def normalize_text(text: str) -> str:
    """Conservative normalization for EN/AR/mixed/code."""
    if not text:
        return ""
    text = unicodedata.normalize("NFKC", text)
    text = _AR_DIACRITICS.sub("", text)
    text = text.translate(_ALEF_VARIANTS)
    # Normalize whitespace only; keep code punctuation for the tokenizer.
    text = re.sub(r"\s+", " ", text).strip()
    return text


def normalize_token(token: str) -> str:
    """Per-token normalization (lowercase Latin, conservative Arabic)."""
    if not token:
        return token
    # Latin identifiers: case-insensitive.
    if re.match(r"^[A-Za-z_]", token):
        return token.lower()
    # Arabic: normalize alef already done; fold ta-marbuta/alef-maqsura
    # conservatively to improve recall without stemming technical terms.
    token = token.translate(_TA_MARBUTA).translate(_ALEF_MAQSURA)
    return token


def multilingual_tokens(text: str, *, drop_stop: bool = True) -> list[str]:
    """Tokenize preserving Arabic, Latin/code identifiers and numbers."""
    norm = normalize_text(text)
    tokens = [normalize_token(t) for t in _TOKEN_RE.findall(norm)]
    tokens = [t for t in tokens if t and len(t) >= 1]
    if drop_stop:
        tokens = [t for t in tokens if t.lower() not in _MULTILINGUAL_STOP]
    return tokens


def multilingual_tokenizer(text: str) -> list[str]:
    """Top-level tokenizer for sklearn (must be picklable)."""
    return multilingual_tokens(text, drop_stop=True)
