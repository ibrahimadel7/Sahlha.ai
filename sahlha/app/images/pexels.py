"""Pexels image-search provider (one related image per skill).

Interface: `fetch_related_image(query) -> {bytes, source_url, alt, photographer}`.
Swappable behind this module.
"""
from __future__ import annotations

import os
import re

PEXELS_SEARCH_URL = "https://api.pexels.com/v1/search"


def pexels_available() -> bool:
    try:
        from sahlha.app.config import settings
        key = settings.pexels_api_key or os.getenv("PEXELS_API_KEY", "")
    except Exception:
        key = os.getenv("PEXELS_API_KEY", "")
    return bool(key)


def _STOPWORDS() -> set[str]:
    return {
        # Generic English function words (never visual).
        "a", "an", "the", "and", "or", "for", "to", "of", "in", "on", "with",
        "that", "this", "these", "those", "it", "its", "into", "through",
        "is", "are", "was", "were", "be", "been", "being", "as", "at", "by",
        "from", "which", "what", "when", "where", "how", "why",
        "can", "could", "should", "would", "will", "may", "might", "must",
        "do", "does", "did", "done", "have", "has", "had", "having",
        "not", "no", "yes", "if", "else", "then", "than", "too", "very",
        "more", "most", "some", "such", "only", "also", "just", "about",
        "both", "each", "other", "later", "used", "use", "using",
        # Pronouns (never visual).
        "i", "we", "you", "he", "she", "they", "them", "him", "her",
        "my", "mine", "our", "ours", "your", "yours", "his", "their", "theirs",
        # Generic verbs that describe pedagogy, not something to depict
        # ("store values", "move through", "produce energy", "converts light").
        # The nouns around them carry the visual meaning.
        "store", "stores", "stored", "storing",
        "move", "moves", "moved", "moving",
        "produce", "produces", "produced", "producing",
        "convert", "converts", "converted", "converting",
        "make", "makes", "made", "making",
        "take", "takes", "took", "taken",
        "give", "gives", "gave", "given",
        # Generic course/lesson filler (carries no visual meaning).
        "introduction", "intro", "overview", "lesson", "basics", "basic",
        "fundamentals", "fundamental", "concepts", "concept", "chapter",
        "unit", "guide", "study", "learn", "learning", "course", "topic",
        "topics", "class", "module", "part",
        "example", "examples", "include", "includes", "included", "including",
    }


def _keywords(text: str, *, max_words: int) -> list[str]:
    """Split text into meaningful keywords: order-preserving, case-preserving.

    Drops stopwords / single chars / pure digits, de-duplicates
    case-insensitively. Pure helper so photo queries stay short and visual.
    """
    if not text:
        return []
    stop = _STOPWORDS()
    out: list[str] = []
    seen: set[str] = set()
    for tok in re.split(r"[^A-Za-z0-9+#-]+", text or ""):
        tok = tok.strip(" ,.-_+#")
        if len(tok) < 2 or tok.isdigit():
            continue
        if tok.lower() in stop:
            continue
        if tok.lower() in seen:
            continue
        seen.add(tok.lower())
        out.append(tok)
        if len(out) >= max_words:
            break
    return out


def _clean_skill_name(name: str) -> str:
    """Strip "(lesson)" style suffixes the extractor appends to skill names."""
    cleaned = re.sub(r"\(.*?\)", "", name or "").strip()
    return re.sub(r"\s+", " ", cleaned).strip(" ,.-")


def _lesson_domain_words(ctx: dict) -> list[str]:
    """Visual domain qualifier from the LESSON side only.

    Uses the lesson title + lesson key concepts (+ ids as a last resort).
    Deliberately ignores full lesson body text: the body mentions incidental
    objects (lamps, batteries, snakes-as-examples) that must not leak into
    the query. The domain's only job is to disambiguate the skill
    ("python" the language vs the snake, computer mouse vs animal mouse).
    """
    title = (ctx.get("lesson_title") or ctx.get("lesson_topic")
             or ctx.get("subject") or ctx.get("topic") or "")
    key_concepts = list(ctx.get("lesson_key_concepts")
                        or ctx.get("lesson_concepts") or [])[:4]
    lesson_expl = (ctx.get("lesson_explanation") or "")
    words: list[str] = []
    seen: set[str] = set()

    def _add(cands: list[str]) -> None:
        for w in cands:
            if w.lower() not in seen:
                seen.add(w.lower())
                words.append(w)

    _add(_keywords(title, max_words=4))
    for kc in key_concepts:
        _add(_keywords(str(kc), max_words=3))
        if len(words) >= 6:
            break
    if not words and lesson_expl:
        # Lesson overview exists but no title/concepts yet: a couple of
        # overview keywords still beat nothing.
        _add(_keywords(lesson_expl, max_words=3))
    if not words:
        # Last resort: humanize the ids ("python_programming" -> programming).
        for raw in (ctx.get("lesson_id", ""), ctx.get("course_id", "")):
            human = re.sub(r"[_-]+", " ", str(raw or "")).strip()
            _add(_keywords(human, max_words=3))
            if words:
                break
    return words[:6]


def build_image_query(skill: dict) -> str:
    """Category-aware photo query: SKILL is the subject, CATEGORY guards meaning.

    Considers the full context the image tool provides (all keys optional
    except the legacy ``name``/``skill_id``/``key_concepts`` triple):

    * skill side: ``name`` + ``key_concepts`` (primary) + ``description`` /
      ``explanation`` / ``learning_objective`` (supplement, capped).
    * lesson side: ``lesson_category`` (structured record or id from
      ``sahlha/app/lesson_categories.py`` — contributes its search anchor) +
      ``lesson_title`` / ``lesson_key_concepts`` as the topic qualifier
      (see :func:`_lesson_domain_words`).

    The anchor resolves ambiguity WITHOUT deciding the picture: Biology +
    mitochondria still depicts mitochondria, Biology + snake depicts a snake —
    the category only rules out unrelated interpretations (snake for a
    programming lesson, lamp for an electron skill). The query stays short
    (photo search works best with a few visual terms) and carries no
    hardcoded word→image mapping.

    Pure — unit tested, no network, no LLM.
    """
    ctx = skill or {}
    name = _clean_skill_name(ctx.get("name", ""))
    raw_concepts = list(ctx.get("key_concepts", []) or [])[:3]

    # --- Skill core: the visual subject (what the picture must depict). ---
    # De-duplication is exact-case so a title word ("Elif") never eats its
    # concept phrase ("elif keyword"); a single-word concept that adds nothing
    # but casing ("variables" when the name already has "Variables") is
    # skipped, while words inside multi-word phrases are kept intact so the
    # phrase still matches as a unit.
    skill_words: list[str] = []
    seen_exact: set[str] = set()
    seen_lower: set[str] = set()

    def _add_skill(cands: list[str]) -> None:
        for w in cands:
            if w not in seen_exact:
                seen_exact.add(w)
                seen_lower.add(w.lower())
                skill_words.append(w)

    _add_skill(_keywords(name, max_words=6))
    for kc in raw_concepts:
        words = _keywords(str(kc), max_words=3)
        if len(words) == 1 and words[0].lower() in seen_lower:
            continue
        _add_skill(words)
    # Skill explanation/description supplements the core when the name is a
    # full sentence ("Variables store values ...") or vague ("Introduction"):
    # a few extra content words, never the whole text.
    if len(skill_words) < 4:
        for extra in (ctx.get("description", ""), ctx.get("learning_objective", ""),
                      (ctx.get("explanation", "") or "")[:400]):
            _add_skill(_keywords(str(extra or ""), max_words=4))
            if len(skill_words) >= 6:
                break
    skill_words = skill_words[:8]

    # --- Lesson side: category anchor first (guardrail), then topic. ---
    # Compared case-insensitively so the lesson never repeats the skill.
    # The anchor (e.g. "programming", "physics", "biology") rules out
    # unrelated interpretations; the skill words above still pick the subject.
    from sahlha.app.lesson_categories import anchor_for as _anchor_for

    lesson_words: list[str] = []
    for w in _keywords(_anchor_for(ctx.get("lesson_category")), max_words=2):
        if w.lower() not in seen_lower:
            seen_lower.add(w.lower())
            lesson_words.append(w)
    for w in _lesson_domain_words(ctx):
        if w.lower() not in seen_lower:
            seen_lower.add(w.lower())
            lesson_words.append(w)
    lesson_words = lesson_words[:5]

    query_words = skill_words + lesson_words
    query = re.sub(r"\s+", " ", " ".join(query_words)).strip(" ,.-")
    if not query:
        return str(ctx.get("skill_id", "") or "education")
    return query[:120] or str(ctx.get("skill_id", "") or "education")


def _api_key() -> str:
    from sahlha.app.config import settings

    key = settings.pexels_api_key or os.getenv("PEXELS_API_KEY", "")
    if not key:
        raise RuntimeError("Image search needs PEXELS_API_KEY in the backend .env.")
    return key


def search_pexels(query: str, *, per_page: int = 3) -> list[dict]:
    """Returns photo dicts {page_url, image_url, alt, photographer}."""
    import requests

    resp = requests.get(PEXELS_SEARCH_URL, headers={"Authorization": _api_key()},
                        params={"query": query, "per_page": per_page,
                                "orientation": "landscape", "size": "large"}, timeout=30)
    if resp.status_code == 401:
        raise RuntimeError("Pexels rejected the API key (401). Check PEXELS_API_KEY.")
    resp.raise_for_status()
    photos = resp.json().get("photos", [])
    return [{"page_url": p.get("url", ""), "image_url": (p.get("src") or {}).get("large", ""),
             "alt": p.get("alt", ""), "photographer": p.get("photographer", "")}
            for p in photos if (p.get("src") or {}).get("large")]


def _stem(word: str) -> str:
    """Light plural-insensitive stem so 'cells' matches 'cell'."""
    w = word.lower()
    if len(w) > 4:
        if w.endswith("ies"):
            return w[:-3] + "y"
        if w.endswith("ses"):
            return w[:-2]
        if w.endswith("s") and not w.endswith("ss"):
            return w[:-1]
    return w


def _best_photo(photos: list[dict], query: str) -> dict:
    """Pick the photo whose alt text best matches the query (light re-rank).

    Pexels ranks by its own relevance; when several candidates come back we
    prefer the one that literally depicts the queried concept. Scores the
    Dice coefficient over singular/plural-insensitive words (len>=3) — shared
    terms normalized by alt length, so a focused caption ("... cells under a
    microscope") beats a long generic one with the same single overlap.
    Exact ties keep Pexels' order so a zero-overlap result never demotes
    Pexels' own top pick.
    """
    qwords = {_stem(w) for w in re.split(r"[^a-z0-9]+", (query or "").lower()) if len(w) >= 3}
    if not qwords or len(photos) <= 1:
        return photos[0]
    best, best_score = photos[0], -1.0
    for p in photos:
        alt = {_stem(w) for w in re.split(r"[^a-z0-9]+", str(p.get("alt", "")).lower()) if len(w) >= 3}
        inter = len(qwords & alt)
        score = (2 * inter / (len(qwords) + len(alt))) if alt else 0.0
        if score > best_score:
            best, best_score = p, score
    return best


def fetch_related_image(query: str) -> dict:
    """Search + download the top result. Falls back to generic education image if specific query fails."""
    import requests

    photos = search_pexels(query)
    if not photos:
        # Fallback to generic education query
        for fallback in ["education technology", "learning", "school classroom"]:
            try:
                photos = search_pexels(fallback, per_page=3)
                if photos:
                    break
            except Exception:
                continue
    if not photos:
        raise ValueError(f"No Pexels images found for query: {query!r}")
    top = _best_photo(photos, query)
    dl = requests.get(top["image_url"], timeout=60)
    dl.raise_for_status()
    data = dl.content
    if len(data) < 1024 or not dl.headers.get("content-type", "").startswith("image/"):
        raise RuntimeError("Pexels download did not return a valid image.")
    return {"bytes": data, **top}
