"""Centralized mastery rules. Thresholds live in settings — not scattered."""
from __future__ import annotations

from sahlha.app.config import settings

NOT_STARTED = "not_started"
NEEDS_PRACTICE = "needs_practice"
DEVELOPING = "developing"
MASTERED = "mastered"


def mastery_state(*, attempted: int, accuracy: float | None) -> str:
    if not attempted:
        return NOT_STARTED
    acc = accuracy or 0.0
    if acc >= settings.mastery_mastered_min and attempted >= settings.mastery_min_attempts:
        return MASTERED
    if acc >= settings.mastery_developing_min:
        return DEVELOPING
    return NEEDS_PRACTICE


def summarize(states: list[str]) -> dict:
    counts = {NOT_STARTED: 0, NEEDS_PRACTICE: 0, DEVELOPING: 0, MASTERED: 0}
    for s in states:
        counts[s] = counts.get(s, 0) + 1
    return counts
