"""Structured-output + RAG grounding layer.

Covers the task's required cases using the REAL RAG pipeline (ingestion ->
retrieve_lesson -> agent), never a parallel representation:

1. valid: educational retrieval -> skills pass schema + grounding
2. irrelevant metadata: teacher/school/page never becomes a skill
3. unsupported skill: evidence cannot support it -> rejected
4. invalid structured output: missing/wrong types -> schema rejects
5. invalid question: bad skill ref / malformed options -> rejected
6. RAG source mismatch: chunk from another lesson -> rejected
7. empty retrieval: no fabrication
8. regeneration: bounded retry path (fallback-once / top-up-once, no loops)
"""
from __future__ import annotations

import pytest

from sahlha.app.agent import grounding as g
from sahlha.app.agent.agent import SahlhaAgent
from sahlha.app.agent.schemas import (
    EvaluationRecord,
    GeneratedQuestion,
    GroundedQuestion,
    GroundedSkill,
    QuestionList,
    SkillList,
    SubmittedAnswers,
)
from sahlha.app.agent.state import AgentState
from sahlha.app.rag import ingestion, retriever
from sahlha.app.services import services as svc

PHOTO_TEXT = (
    "Teacher: Ahmed Hassan\n\n"
    "Photosynthesis is the process by which plants convert light energy into chemical energy. "
    "Chlorophyll in the leaves absorbs light energy from the sun. "
    "Carbon dioxide enters the leaves and water is absorbed by the roots. "
    "Glucose is produced as food and oxygen is released into the air. "
    "Prepared by Ahmed Hassan, Al-Noor School, page 4."
)

ELIF_TEXT = (
    "Python elif lesson. The elif keyword means else-if. It lets a program test multiple "
    "conditions in order. If the first if condition is false, Python checks the elif condition. "
    "Only the first true branch executes. An optional else runs when nothing matches. "
    "Example: if score >= 90 grade A elif score >= 80 grade B else grade C."
)


def _seed_photo(db_session, course="sci", lesson="photo"):
    return ingestion.ingest_upload(
        db_session, file_bytes=PHOTO_TEXT.encode(), filename="photo.txt",
        course_id=course, lesson_id=lesson, skill_id="general")


def _chunks(db_session, course="sci", lesson="photo"):
    return retriever.retrieve_lesson(db_session, course, lesson, top_k=5)


# 1. Valid case -------------------------------------------------------------
def test_valid_rag_grounded_skills(db_session):
    _seed_photo(db_session)
    chunks = _chunks(db_session)
    assert chunks, "RAG must retrieve educational content"
    assert any("photosynthesis" in c["text"].lower() for c in chunks)
    # Real chunk shape (existing representation, not invented).
    assert {"chunk_id", "document_id", "course_id", "lesson_id", "text"} <= set(chunks[0])

    out = svc.extract_skills(db_session, course_id="sci", lesson_id="photo", max_skills=3)
    skills = out["skills"]
    assert skills, "valid material must yield skills"
    for s in skills:
        # Every accepted skill carries valid RAG evidence.
        assert s["source_chunk_ids"], "skill must reference retrieval"
        assert s["source_evidence"], "skill must carry evidence"
        assert s["learning_objective"], "skill must carry a learning objective"
        ok, reasons = g.validate_skill_grounding(s, chunks, "sci", "photo")
        assert ok, f"grounding must pass: {reasons}"
        # Strict schema passes.
        GroundedSkill(**{k: s[k] for k in (
            "skill_id", "name", "description", "key_concepts",
            "learning_objective", "source_chunk_ids", "source_evidence")})
    # Retrieval was the evidence source (no raw-text bypass): chunk ids match.
    retrieved_ids = {c["chunk_id"] for c in chunks}
    assert any(set(s["source_chunk_ids"]) <= retrieved_ids for s in skills)


# 2. Irrelevant metadata ----------------------------------------------------
def test_teacher_name_never_becomes_skill(db_session):
    _seed_photo(db_session)
    out = svc.extract_skills(db_session, course_id="sci", lesson_id="photo", max_skills=4)
    blob = " ".join(
        f"{s['skill_id']} {s['name']} {s['description']} {' '.join(s.get('key_concepts', []))}"
        for s in out["skills"]).lower()
    assert "ahmed" not in blob, "teacher name must not become a skill"
    assert "al-noor" not in blob and "al_noor" not in blob
    # Skills are about the curriculum topic.
    assert any("photosynth" in s["name"].lower() or "photosynth" in s["description"].lower()
               or "light" in s["description"].lower() or "chlorophyll" in s["description"].lower()
               for s in out["skills"])


# 3. Unsupported skill ------------------------------------------------------
def test_unsupported_skill_rejected(db_session):
    _seed_photo(db_session)
    chunks = _chunks(db_session)
    fake = {
        "skill_id": "quantum_entanglement",
        "name": "Explain quantum entanglement",
        "description": "Quantum entanglement links distant particles instantly.",
        "learning_objective": "Understand quantum entanglement across distant particles.",
        "key_concepts": ["quantum", "entanglement"],
        "source_chunk_ids": [chunks[0]["chunk_id"]],
        "source_evidence": ["Quantum entanglement links distant particles instantly."],
    }
    ok, reasons = g.validate_skill_grounding(fake, chunks, "sci", "photo")
    assert not ok
    assert any("ungrounded" in r or "not supported" in r or "unsupported" in r for r in reasons)


# 4. Invalid structured output ----------------------------------------------
def test_invalid_structured_output_rejected():
    import pydantic

    # Missing skill_id.
    with pytest.raises(pydantic.ValidationError):
        SkillList(skills=[{"name": "No id", "description": "Missing skill_id field here."}])
    # Wrong types.
    with pytest.raises(pydantic.ValidationError):
        GeneratedQuestion(question="Q?", options="not-a-list", correct_answer=0)  # type: ignore[arg-type]
    # MCQ must have exactly 4 options.
    with pytest.raises(pydantic.ValidationError):
        QuestionList(questions=[{"skill_id": "s", "type": "multiple_choice",
                                 "question": "What is photosynthesis?",
                                 "options": ["a", "b", "c"], "correct_answer": 0,
                                 "explanation": "e", "difficulty": "easy"}])
    # Grounded skill requires provenance.
    with pytest.raises(pydantic.ValidationError):
        GroundedSkill(skill_id="x", name="X skill", description="A proper description here.",
                      learning_objective="Learn X properly today.",
                      source_chunk_ids=[], source_evidence=[])
    # Grounded question requires explanation + provenance.
    with pytest.raises(pydantic.ValidationError):
        GroundedQuestion(skill_id="s", type="multiple_choice",
                         question="What is photosynthesis?",
                         options=["a", "b", "c", "d"], correct_answer=0,
                         explanation="", difficulty="easy",
                         source_chunk_ids=["c1"], source_evidence=["ev"])
    # Student submission boundary.
    with pytest.raises(pydantic.ValidationError):
        SubmittedAnswers(answers={"q1": 9})
    rec = EvaluationRecord(question_id="q1", correct=True, student_answer=1,
                           correct_answer=1, skill_id="s")
    assert rec.correct is True


# 5. Invalid question --------------------------------------------------------
def test_invalid_question_rejected(db_session):
    _seed_photo(db_session)
    chunks = _chunks(db_session)
    cid = chunks[0]["chunk_id"]

    # References a nonexistent skill.
    q = {"skill_id": "nope_missing", "type": "multiple_choice",
         "question": "What role does light energy play in photosynthesis?",
         "options": ["a", "b", "c", "d"], "correct_answer": 0,
         "explanation": "Supported by the lesson.",
         "difficulty": "easy",
         "source_chunk_ids": [cid], "source_evidence": [chunks[0]["text"][:200]]}
    ok, reasons = g.validate_question_grounding(q, chunks, {"real_skill"}, "sci", "photo")
    assert not ok and any("nonexistent" in r for r in reasons)

    # Malformed options: duplicates.
    with pytest.raises(Exception):
        QuestionList(questions=[{"skill_id": "s", "type": "multiple_choice",
                                 "question": "What is photosynthesis?",
                                 "options": ["same", "same", "c", "d"],
                                 "correct_answer": 0, "explanation": "e",
                                 "difficulty": "easy"}])
    # Malformed options: bad correct index.
    with pytest.raises(Exception):
        QuestionList(questions=[{"skill_id": "s", "type": "multiple_choice",
                                 "question": "What is photosynthesis?",
                                 "options": ["a", "b", "c", "d"],
                                 "correct_answer": 9, "explanation": "e",
                                 "difficulty": "easy"}])
    # Duplicate questions in one bank.
    dup = {"skill_id": "s", "type": "multiple_choice",
           "question": "What is photosynthesis?",
           "options": ["a", "b", "c", "d"], "correct_answer": 0,
           "explanation": "e", "difficulty": "easy"}
    with pytest.raises(Exception):
        QuestionList(questions=[dup, dict(dup)])


# 6. RAG source mismatch ------------------------------------------------------
def test_rag_source_mismatch_rejected(db_session):
    _seed_photo(db_session, course="sci", lesson="photo")
    ingestion.ingest_upload(db_session, file_bytes=ELIF_TEXT.encode(), filename="elif.txt",
                            course_id="py", lesson_id="elif_lesson", skill_id="general")
    chunks_a = retriever.retrieve_lesson(db_session, "sci", "photo", top_k=5)
    chunks_b = retriever.retrieve_lesson(db_session, "py", "elif_lesson", top_k=5)
    assert chunks_a and chunks_b
    foreign_id = chunks_b[0]["chunk_id"]
    assert foreign_id not in {c["chunk_id"] for c in chunks_a}

    skill = {"skill_id": "photo_basics", "name": "Photosynthesis basics",
             "description": "Photosynthesis converts light energy.",
             "learning_objective": "Explain how photosynthesis converts light energy.",
             "key_concepts": ["photosynthesis"],
             "source_chunk_ids": [foreign_id],
             "source_evidence": [chunks_b[0]["text"][:200]]}
    ok, reasons = g.validate_skill_grounding(skill, chunks_a, "sci", "photo")
    assert not ok
    assert any("unknown" in r or "mismatch" in r for r in reasons)


# 7. Empty retrieval -----------------------------------------------------------
def test_empty_retrieval_no_fabrication(db_session):
    # Skills: explicit failure state, no rows created.
    agent = SahlhaAgent(db_session, AgentState())
    out = agent.extract_skills(course_id="missing", lesson_id="missing_lesson", force=True)
    assert out["skills"] == []
    assert out["backend"] == "empty-retrieval"
    assert out.get("status") == "failed"

    # Fallbacks refuse empty input directly.
    from sahlha.app.agent.llm import fallback_questions, fallback_skills

    assert fallback_skills([], "missing_lesson") == []
    assert fallback_questions([], "s", 4) == []

    # Questions: empty bank is observable, never padded with trivia.
    bank = agent.generate_question_bank(course_id="missing", lesson_id="missing_lesson",
                                        skill_id="s", n_questions=4)
    assert bank["num_questions"] == 0
    assert bank["backend"] == "empty-retrieval"


# 8. Regeneration (bounded) ------------------------------------------------------
def test_skill_regeneration_bounded(monkeypatch, db_session):
    """A metadata-only LLM draft is rejected; ONE fallback retry fixes it (no loop)."""
    _seed_photo(db_session)
    from sahlha.app.agent import llm as _llm

    calls = {"fallback": 0}
    real_fallback = _llm.fallback_skills

    def counting_fallback(chunks, lesson_id, max_skills=6):
        calls["fallback"] += 1
        return real_fallback(chunks, lesson_id, max_skills)

    # agent.py did `from ... import fallback_skills`, so patch both references.
    monkeypatch.setattr(_llm, "fallback_skills", counting_fallback)
    import sahlha.app.agent.agent as _agent_mod

    monkeypatch.setattr(_agent_mod, "fallback_skills", counting_fallback)

    # Force the LLM path with a bad (metadata) draft.
    monkeypatch.setattr("sahlha.app.agent.agent.complete_json",
                        lambda system, user: ({"skills": [
                            {"skill_id": "identify_ahmed_hassan",
                             "name": "Identify the teacher",
                             "description": "Teacher Ahmed Hassan prepared the lesson.",
                             "key_concepts": ["Ahmed Hassan"]}]}, "groq"))
    agent = SahlhaAgent(db_session, AgentState())
    out = agent.extract_skills(course_id="sci", lesson_id="photo", force=True)
    assert calls["fallback"] == 1, "exactly one bounded retry, no loop"
    assert out["skills"], "fallback retry must recover grounded skills"
    assert "fallback" in out["backend"]
    events = [t["event"] for t in out["trace"]]
    assert "validation:skill_grounding" in events or "validation:skill_grounding_empty" in events
    assert not any("ahmed" in s["skill_id"] for s in out["skills"])


def test_question_regeneration_single_topup(db_session):
    """Critique/grounding drops are topped up ONCE with the same chunks."""
    ingestion.ingest_upload(db_session, file_bytes=(ELIF_TEXT * 2).encode(),
                            filename="elif.txt", course_id="py",
                            lesson_id="elif_lesson", skill_id="general")
    agent = SahlhaAgent(db_session, AgentState())
    job = agent._prepare_bank_job(course_id="py", lesson_id="elif_lesson",
                                  skill_id="general", n_questions=4)
    assert job["chunks"], "needs retrieval"
    # Draft: one good + one metadata/trivia question.
    good = {"skill_id": "general", "type": "multiple_choice",
            "question": "When does the elif branch execute in Python?",
            "options": ["When earlier conditions fail and its own holds", "Never",
                        "Always first", "Only on errors"],
            "correct_answer": 0, "explanation": "Elif tests another condition.",
            "difficulty": "easy"}
    bad = {"skill_id": "general", "type": "multiple_choice",
           "question": "Who prepared the elif lesson?",
           "options": ["Mr Karim", "Nobody", "Python", "Elif"],
           "correct_answer": 0, "explanation": "Metadata.",
           "difficulty": "easy"}
    from sahlha.app.agent.llm import fallback_critique

    verdicts = fallback_critique([good, bad], job["chunks"])
    assert any(not v["relevant"] for v in verdicts), "critique must flag metadata"
    agent.state.course_id, agent.state.lesson_id = "py", "elif_lesson"
    final, info = agent._finalize_bank_questions(job, [good, bad], verdicts)
    assert info["topped_up"] >= 1, "one bounded top-up must replace the drop"
    assert all("Who prepared" not in q["question"] for q in final)
    assert len(final) <= job["n_questions"], "never exceed the request (no padding loop)"
