"""Lesson categories — the contextual guardrail for skill image retrieval.

Flow: RAG retrieves lesson context -> the lesson is classified ONCE into one
of these broad educational categories -> the category id is persisted on the
lesson row -> every skill image query for that lesson combines
``category + lesson topic + skill + skill explanation``.

The classifier is deliberately deterministic (signal-word scoring, no LLM, no
network): classification happens once per lesson and is reused by all of its
skills, so per-image cost stays zero. Ambiguous words (``python``, ``mouse``,
``java``, ``virus``, ``bug``) are intentionally NOT signals anywhere — the
category is decided by the surrounding domain vocabulary, which is exactly
what lets the same word resolve differently per lesson.

Pure module: no imports from the app, so the agent, the image tool, and the
query builder can all share it without import cycles.
"""
from __future__ import annotations

import re

#: Small, practical taxonomy for educational material. ``anchor`` is the short
#: search term the category contributes to an image query (NOT a depiction —
#: the skill itself stays the subject). ``signals`` are discriminative
#: domain-vocabulary phrases; generic words (energy, power, data, ...) and
#: ambiguous words (python, mouse, ...) are excluded on purpose.
CATEGORIES: tuple[dict, ...] = (
    {"id": "mathematics", "label": "Mathematics", "anchor": "mathematics",
     "signals": ["algebra", "geometry", "calculus", "equation", "theorem",
                 "fraction", "probability", "statistics", "trigonometry",
                 "arithmetic", "polynomial", "matrix", "derivative",
                 "integral", "logarithm", "prime number"]},
    {"id": "physics", "label": "Physics", "anchor": "physics",
     "signals": ["electron", "proton", "neutron", "nucleus", "quantum",
                 "photon", "velocity", "acceleration", "gravity", "newton",
                 "circuit", "voltage", "current", "resistor", "magnetism",
                 "magnetic", "thermodynamics", "relativity", "momentum",
                 "kinetic", "atom", "atomic"]},
    {"id": "chemistry", "label": "Chemistry", "anchor": "chemistry",
     "signals": ["molecule", "compound", "reaction", "acid", "periodic table",
                 "element", "catalyst", "oxidation", "reduction", "mixture",
                 "solution", "polymer", "hydrocarbon", "chemical bond"]},
    {"id": "biology", "label": "Biology", "anchor": "biology",
     "signals": ["cell", "organism", "species", "habitat", "ecosystem",
                 "photosynthesis", "mitochondria", "organelle", "chlorophyll",
                 "chloroplast", "evolution", "dna", "gene", "tissue", "organ",
                 "enzyme", "bacteria", "reptile", "mammal", "rodent", "snake",
                 "constrictor", "prey", "venom", "plant", "animal", "flower",
                 "root", "leaf", "seed", "blood", "muscle", "bone", "lung",
                 "heart", "respiration"]},
    {"id": "computer_science", "label": "Computer Science / Programming",
     "anchor": "programming",
     "signals": ["computer", "hardware", "software", "programming", "program",
                 "code", "coding", "algorithm", "variable", "function", "loop",
                 "data type", "database", "debug", "syntax", "keyboard",
                 "screen", "click", "device"]},
    {"id": "geography", "label": "Geography", "anchor": "geography",
     "signals": ["volcano", "earthquake", "river", "mountain", "continent",
                 "climate", "map", "country", "ocean", "desert", "erosion",
                 "geology", "rock", "glacier", "island"]},
    {"id": "history", "label": "History", "anchor": "history",
     "signals": ["war", "empire", "century", "ancient", "revolution", "king",
                 "queen", "civilization", "colony", "independence", "medieval",
                 "president", "battle", "treaty", "archaeology"]},
    {"id": "language", "label": "Language / Literature", "anchor": "literature",
     "signals": ["grammar", "poem", "poetry", "novel", "essay", "verb", "noun",
                 "adjective", "metaphor", "literature", "author", "playwright",
                 "shakespeare", "stanza"]},
    {"id": "arts", "label": "Arts", "anchor": "art",
     "signals": ["painting", "sculpture", "music", "drawing", "melody",
                 "artist", "gallery", "theater", "dance", "song", "instrument"]},
    {"id": "general_science", "label": "General Science", "anchor": "science",
     "signals": ["experiment", "hypothesis", "laboratory", "observation",
                 "scientific", "scientist"]},
    {"id": "other", "label": "Other", "anchor": "",
     "signals": []},
)

_BY_ID = {c["id"]: c for c in CATEGORIES}

OTHER = _BY_ID["other"]

#: Words that must never decide a category (kept here as a guard so future
#: signal additions stay honest — see tests).
_AMBIGUOUS = {"python", "mouse", "mice", "java", "virus", "viruses", "bug", "bugs"}


def get(category_id: str) -> dict:
    """Taxonomy record for an id (falls back to ``Other``)."""
    rec = _BY_ID.get((category_id or "").strip().lower())
    if rec is None:
        return {"id": "other", "label": "Other", "anchor": ""}
    return {"id": rec["id"], "label": rec["label"], "anchor": rec["anchor"]}


def anchor_for(value) -> str:
    """Search anchor for a category id or classification record ("" for Other)."""
    if isinstance(value, dict):
        if value.get("anchor"):
            return str(value["anchor"])
        return get(str(value.get("category_id", ""))).get("anchor", "")
    return get(str(value or "")).get("anchor", "")


def _tokens(text: str) -> list[str]:
    return re.findall(r"[a-z0-9]+", (text or "").lower())


def _signal_hits(text: str, signal: str) -> int:
    """Occurrences of a signal phrase (plural-insensitive, capped)."""
    words = _tokens(text)
    parts = _tokens(signal)
    if not parts:
        return 0
    n = 0
    for i in range(len(words) - len(parts) + 1):
        window = words[i:i + len(parts)]
        if all(w == p or w == p + "s" or (p.endswith("s") and w == p[:-1])
               for w, p in zip(window, parts)):
            n += 1
            if n >= 3:
                break
    return n


def classify_lesson(*, lesson_id: str = "", course_id: str = "",
                    text: str = "", title: str = "",
                    key_concepts: list | None = None) -> dict:
    """Classify a lesson into the taxonomy (pure — no LLM, no network).

    Scores signal-phrase hits over the RAG lesson text plus the humanized
    ids, title, and key concepts. Returns a structured record
    ``{category_id, label, anchor, scores}``. Zero total signal hits (or a
    tie at zero) yields ``other``; ties otherwise resolve in taxonomy order
    (deterministic).
    """
    blob_parts = [re.sub(r"[_-]+", " ", str(lesson_id or "")),
                  re.sub(r"[_-]+", " ", str(course_id or "")),
                  str(title or ""),
                  " ".join(str(c) for c in (key_concepts or [])),
                  str(text or "")]
    blob = " ".join(p for p in blob_parts if p)
    scores: dict[str, int] = {}
    for cat in CATEGORIES:
        scores[cat["id"]] = sum(_signal_hits(blob, s) for s in cat["signals"])
    best_id = "other"
    best_score = 0
    for cat in CATEGORIES:
        if cat["id"] == "other":
            continue
        if scores[cat["id"]] > best_score:
            best_id, best_score = cat["id"], scores[cat["id"]]
    rec = get(best_id)
    return {"category_id": rec["id"], "label": rec["label"],
            "anchor": rec["anchor"], "scores": scores}
