"""Student Learning Profile: onboarding mapping + deterministic adaptation.

Onboarding is an initial hypothesis ("currently appears helpful..."). Observed
behaviour (accuracy, retries, hint use, support-tool use) gradually updates the
observed_settings via simple rules — no ML in the prototype.
"""
from __future__ import annotations

from sqlalchemy.orm import Session

from sahlha.app.database import models as m
from sahlha.app.database.repositories import platform as prepo

# Signals the client may report. Unknown values are rejected at the schema
# layer (422) so duplicate/garbage traffic can never create junk profile rows.
KNOWN_SIGNALS = frozenset({
    "hint_used", "retry", "example_helped", "simpler_helped", "audio_used",
    "visual_helped", "step_helped", "struggled", "improved",
})


# ---- Onboarding answer -> support mapping (support language only, never medical) ----
READING = {"easy": "standard_text", "sometimes": "larger_text_breaks", "hard": "short_chunks_audio"}
FOCUS = {"long": "standard_sessions", "medium": "short_steps_checkins", "short": "one_task_short"}
INSTRUCTIONS = {"long_ok": "full_instructions", "steps": "step_by_step", "show_first": "example_first"}
PRESENTATION = {"read": "read_first", "listen": "audio_offered", "pictures": "visual_first"}
PRACTICE = {"try_first": "independent_first", "example_first": "example_first",
            "practice_more": "extra_repetition"}
SESSION = {"short": "short", "medium": "medium", "long": "long"}
CONFIDENCE = {"confident": "confident", "sometimes": "building", "nervous": "needs_encouragement"}


def apply_onboarding(db: Session, student_id: str, answers: dict) -> m.StudentLearningProfile:
    def pick(key: str, table: dict, default: str) -> str:
        return table.get(str(answers.get(key, "")).strip(), default)

    return prepo.upsert_profile(
        db, student_id,
        onboarding_completed=True,
        reading_support=pick("reading", READING, "standard_text"),
        focus_support=pick("focus", FOCUS, "standard_sessions"),
        instruction_support=pick("instructions", INSTRUCTIONS, "full_instructions"),
        presentation_support=pick("presentation", PRESENTATION, "read_first"),
        practice_support=pick("practice", PRACTICE, "independent_first"),
        session_preference=pick("session", SESSION, "medium"),
        learning_confidence=pick("confidence", CONFIDENCE, "building"),
        raw_answers=dict(answers),
    )


def profile_to_dict(prof: m.StudentLearningProfile | None) -> dict:
    if prof is None:
        return {"onboarding_completed": False, "supports": {}, "observed": {},
                "support_summary": []}
    supports = {
        "reading": prof.reading_support, "focus": prof.focus_support,
        "instructions": prof.instruction_support, "presentation": prof.presentation_support,
        "practice": prof.practice_support, "session": prof.session_preference,
        "confidence": prof.learning_confidence,
    }
    return {"onboarding_completed": prof.onboarding_completed, "supports": supports,
            "observed": prof.observed_settings or {},
            "support_summary": support_summary(prof),
            "hint_count": prof.support_hint_count, "retry_count": prof.support_retry_count}


_FRIENDLY = {
    "short_chunks_audio": "Shorter explanations with audio currently help.",
    "larger_text_breaks": "Larger text with breaks currently helps.",
    "one_task_short": "One task at a time currently helps.",
    "short_steps_checkins": "Short steps with check-ins currently help.",
    "step_by_step": "Step-by-step instructions work well.",
    "example_first": "Examples before independent practice help.",
    "extra_repetition": "Additional repetition currently helps.",
    "audio_offered": "Audio support currently appears helpful.",
    "visual_first": "Visual explanations currently appear helpful.",
    "short": "Short sessions are preferred.",
}


def support_summary(prof: m.StudentLearningProfile) -> list[str]:
    out = []
    for key in (prof.reading_support, prof.focus_support, prof.instruction_support,
                prof.presentation_support, prof.practice_support, prof.session_preference):
        if key in _FRIENDLY:
            out.append(_FRIENDLY[key])
    for key, value in (prof.observed_settings or {}).items():
        if value and key in _FRIENDLY and _FRIENDLY[key] not in out:
            out.append(_FRIENDLY[key])
    return out


def record_support_signal(db: Session, student_id: str, signal: str) -> m.StudentLearningProfile:
    """Update observed settings from behaviour signals.

    Signals: hint_used, retry, example_helped, simpler_helped, audio_used,
    visual_helped, step_helped, struggled (3+ wrong in a row), improved.
    Unknown signals are ignored (defensive: the assessment-submit path must
    never fail grading because of a stray signal value).
    """
    signal = (signal or "").strip()
    if signal not in KNOWN_SIGNALS:
        prof = prepo.get_profile(db, student_id)
        if prof is None:
            # Do not create junk profile rows for unknown signals.
            raise ValueError(f"Unknown support signal: {signal[:64]!r}")
        return prof
    prof = prepo.get_profile(db, student_id)
    observed = dict((prof.observed_settings or {})) if prof else {}
    if signal == "hint_used":
        observed["hints_helpful"] = observed.get("hints_helpful", 0) + 1
    elif signal == "retry":
        observed["retries"] = observed.get("retries", 0) + 1
    elif signal in ("struggled",):
        observed["needs_simpler"] = observed.get("needs_simpler", 0) + 1
        if observed["needs_simpler"] >= 3:
            observed["short_chunks_audio"] = True
            observed["step_by_step"] = True
    elif signal in ("example_helped",):
        observed["example_first"] = True
    elif signal in ("simpler_helped",):
        observed["short_chunks_audio"] = True
    elif signal in ("audio_used",):
        observed["audio_offered"] = True
    elif signal in ("visual_helped",):
        observed["visual_first"] = True
    elif signal in ("step_helped",):
        observed["step_by_step"] = True
    elif signal in ("improved",):
        observed["improving"] = observed.get("improving", 0) + 1
        if observed.get("needs_simpler", 0) > 0:
            observed["needs_simpler"] -= 1  # gradually return to expected difficulty
    fields: dict = {"observed_settings": observed}
    if prof is None:
        return prepo.upsert_profile(db, student_id, **fields)
    if signal == "hint_used":
        fields["support_hint_count"] = prof.support_hint_count + 1
    if signal == "retry":
        fields["support_retry_count"] = prof.support_retry_count + 1
    return prepo.upsert_profile(db, student_id, **fields)


def help_order_for(prof: m.StudentLearningProfile | None) -> list[str]:
    """Order Help-Me options by what currently appears helpful for this student."""
    base = ["simpler", "example", "read_aloud", "steps", "visual", "word"]
    if prof is None:
        return base
    score = {k: 0 for k in base}
    if prof.presentation_support == "audio_offered" or (prof.observed_settings or {}).get("audio_offered"):
        score["read_aloud"] += 2
    if prof.presentation_support == "visual_first" or (prof.observed_settings or {}).get("visual_first"):
        score["visual"] += 2
    if prof.instruction_support == "example_first" or (prof.observed_settings or {}).get("example_first"):
        score["example"] += 2
    if prof.instruction_support == "step_by_step" or (prof.observed_settings or {}).get("step_by_step"):
        score["steps"] += 2
    if prof.reading_support == "short_chunks_audio" or (prof.observed_settings or {}).get("short_chunks_audio"):
        score["simpler"] += 2
    return sorted(base, key=lambda k: -score[k])
