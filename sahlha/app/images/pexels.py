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


def build_image_query(skill: dict) -> str:
    """Query from the skill's context: name + key concepts (pure — unit tested)."""
    raw_name = skill.get("name", "")
    raw_concepts = list(skill.get("key_concepts", [])[:3])
    parts = [raw_name] + raw_concepts
    query = re.sub(r"\s+", " ", " ".join(p for p in parts if p)).strip(" ,.-")
    query = re.sub(r"\(.*?\)", "", query).strip()  # drop "(lesson)" style suffixes
    query = re.sub(r"\s+", " ", query).strip()
    if not query:
        return skill.get("skill_id", "education")
    # Disambiguate programming topics for the photo search ("python" the snake vs
    # the language) while KEEPING the skill-specific terms — a generic fallback
    # would give every code skill the same picture.
    text_blob = f"{raw_name} {' '.join(raw_concepts)}".lower()
    is_code = any(w in text_blob for w in ["python", "elif", "if else", "function", "loop", "code", "programming", "algorithm"])
    if is_code:
        query = re.sub(r"(?i)\bpython\b", "programming", query).strip()
        if not re.search(r"(?i)\b(programming|code|software|computer)\b", query):
            query = f"{query} programming code".strip()
    return query[:120] or skill.get("skill_id", "education")


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
    top = photos[0]
    dl = requests.get(top["image_url"], timeout=60)
    dl.raise_for_status()
    data = dl.content
    if len(data) < 1024 or not dl.headers.get("content-type", "").startswith("image/"):
        raise RuntimeError("Pexels download did not return a valid image.")
    return {"bytes": data, **top}
