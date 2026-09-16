"""Assessment tools: deterministic selection + evaluation + attempt recording.

The LLM reasons over memory; THIS module controls IDs, scoring, persistence.
"""
from __future__ import annotations

from sqlalchemy.orm import Session

from sahlha.app.config import settings
from sahlha.app.database.repositories import repositories as repo


def select_questions(db: Session, *, student_id: str, course_id: str | None = None,
                     lesson_id: str | None = None, skill_id: str | None = None,
                     n_per_bank: int | None = None) -> tuple[list[dict], dict]:
    """Select exactly `n_per_bank` questions from EACH approved question bank.

    Banks are per-skill, so the assessment covers every skill with the same
    memory-aware heuristics applied inside each bank:
    1. Questions previously failed by this student (retry, if still approved)
    2. Questions in weak skills (accuracy < 0.6)
    3. Unseen questions
    4. Fill remainder, balancing difficulty, avoiding repetition within assessment.
    """
    from sahlha.app.agent.tools import question_tools, student_tools

    n_per_bank = n_per_bank or settings.assessment_num_questions
    pool = question_tools.get_approved_questions(db, course_id=course_id, lesson_id=lesson_id, skill_id=skill_id)
    if not pool:
        scope = "/".join([p for p in (course_id, lesson_id, skill_id) if p]) or "global pool"
        raise ValueError(f"No approved questions found for '{scope}'. Approve a bank first.")
    # FEEDBACK LOOP 2 (enforcement): teacher-flagged questions never resurface.
    flagged = repo.get_flagged_question_ids(db)
    pool = [q for q in pool if q["id"] not in flagged]
    if not pool:
        raise ValueError("All approved questions were excluded by teacher flags. Unflag or regenerate a bank.")
    # Group pool by bank (stable order) — one selection round per bank.
    banks: dict[str, list[dict]] = {}
    for q in pool:
        banks.setdefault(q["bank_id"], []).append(q)

    history = student_tools.get_student_history(db, student_id)
    failed_ids = set(student_tools.get_failed_questions(db, student_id))
    seen_ids = {h["question_id"] for h in history}
    # Scope weak-skill memory to the requested lesson when given; otherwise global
    # (preserves single-lesson MVP behavior while preventing cross-lesson collisions).
    perf = {p["skill_id"]: p["accuracy"] for p in student_tools.get_student_skill_performance(
        db, student_id, course_id=course_id, lesson_id=lesson_id)}
    weak_skills = {s for s, acc in perf.items() if acc is not None and acc < 0.6}

    selected: list[dict] = []
    rationale: list[str] = []
    per_bank: dict[str, int] = {}

    def _take(group: list[dict], cands: list[dict], reason: str):
        taken = {s["id"] for s in group}
        for q in cands:
            if len(group) >= n_per_bank:
                break
            if q["id"] not in taken:
                group.append(q)
                taken.add(q["id"])
                rationale.append(f"{q['id']} (bank={q['bank_id']}, {q['skill_id']}/{q['difficulty']}): {reason}")

    for bank_id, group_pool in banks.items():
        if len(group_pool) < n_per_bank:
            skid = group_pool[0].get("skill_id", "?") if group_pool else "?"
            raise ValueError(
                f"Bank {bank_id} (skill '{skid}') has only {len(group_pool)} approved "
                f"unflagged questions, need {n_per_bank} per bank. Regenerate or unflag.")
        by_id = {q["id"]: q for q in group_pool}
        group: list[dict] = []
        _take(group, [by_id[i] for i in failed_ids if i in by_id], "retry previously failed")
        _take(group, [q for q in group_pool if q["skill_id"] in weak_skills], "targets weak skill")
        _take(group, [q for q in group_pool if q["id"] not in seen_ids], "unseen question")
        have = {q["difficulty"] for q in group}
        for diff in ("easy", "medium", "hard"):
            if len(group) >= n_per_bank:
                break
            if diff not in have:
                _take(group, [q for q in group_pool if q["difficulty"] == diff],
                      f"balances difficulty ({diff})")
        _take(group, group_pool, "fill remainder")
        selected.extend(group[:n_per_bank])
        per_bank[bank_id] = len(group[:n_per_bank])

    # Coverage: when a lesson is requested, surface skills with zero approved
    # unflagged questions so the UI can warn instead of silently testing a subset.
    covered_skills = sorted({q["skill_id"] for q in selected})
    missing_skills: list[str] = []
    if course_id and lesson_id and not skill_id:
        try:
            lesson_skills = [s.skill_id for s in repo.list_skills(
                db, course_id=course_id, lesson_id=lesson_id)]
            pool_skills = {q["skill_id"] for q in pool}
            missing_skills = sorted(set(lesson_skills) - pool_skills)
        except Exception:
            missing_skills = []

    return selected, {"rationale": rationale, "weak_skills": sorted(weak_skills),
                      "failed_retried": sorted(failed_ids & {s["id"] for s in selected}),
                      "per_bank": per_bank, "n_per_bank": n_per_bank,
                      "pool_size": len(pool),
                      "flagged_excluded": len(flagged),
                      "covered_skills": covered_skills, "missing_skills": missing_skills}


def evaluate_answer(question: dict, student_answer) -> dict:
    """Structured per-question evaluation."""
    correct_answer = question["correct_answer"]
    if question.get("type") == "multiple_choice":
        try:
            correct = int(student_answer) == int(correct_answer)
        except (TypeError, ValueError):
            correct = str(student_answer).strip() == str(correct_answer).strip()
    else:
        norm = lambda v: str(v or "").strip().lower()
        correct = norm(student_answer) == norm(correct_answer) or norm(correct_answer) in norm(student_answer)
    return {"question_id": question["id"], "correct": correct, "student_answer": student_answer,
            "correct_answer": correct_answer, "skill_id": question.get("skill_id", "general")}


def record_attempt(db: Session, *, student_id: str, question_id: str, assessment_id: str,
                   answer, correct: bool, commit: bool = True) -> dict:
    att = repo.record_attempt(db, student_id=student_id, question_id=question_id,
                              assessment_id=assessment_id, answer=answer, correct=correct,
                              commit=commit)
    return {"attempt_id": att.id, "correct": att.correct}
