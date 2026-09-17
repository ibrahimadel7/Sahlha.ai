"""RAG-improvement regression suite: proves each major spec fix."""
from __future__ import annotations

import io

from sahlha.app.agent import llm as llm_mod
from sahlha.app.agent.agent import SahlhaAgent
from sahlha.app.agent.state import AgentState
from sahlha.app.agent.tools import content_tools, critique_tools
from sahlha.app.agent.tools import question_tools
from sahlha.app.config import settings
from sahlha.app.database.repositories import repositories as repo
from sahlha.app.rag import ingestion, ocr, vectorstore
from sahlha.app.rag.chunking import chunk_blocks
from sahlha.app.rag.document import DocumentBlock, text_blocks
from sahlha.app.rag.textnorm import multilingual_tokens


def _ingest(db, text, course="c", lesson="l", filename="lesson.txt"):
    return ingestion.ingest_upload(db, file_bytes=text.encode(), filename=filename,
                                   course_id=course, lesson_id=lesson, defer_index=True)


# ---------------------------------------------------------------- 1. skills
def test_skill_merge_across_chunks_no_duplicates(db_session):
    text = ("# Photosynthesis\nPhotosynthesis converts light into chemical energy. "
            "Chlorophyll absorbs light energy in green plants.\n\n"
            "# Photosynthesis Continued\nPhotosynthesis produces chemical energy from sunlight. "
            "Chlorophyll is essential for photosynthesis in plants.")
    _ingest(db_session, text, lesson="merge")
    mapped, chunks = content_tools.build_content_map(db_session, "c", "merge")
    assert len(chunks) >= 2
    # Same concept split across chunks must consolidate to one skill.
    out = SahlhaAgent(db_session, AgentState()).extract_skills(
        course_id="c", lesson_id="merge", force=True)
    names = [s["name"].lower() for s in out["skills"]]
    photo = [n for n in names if "photosynth" in n]
    assert len(photo) == 1, f"cross-chunk topic must merge, got {names}"


def test_two_different_concepts_stay_separate(db_session):
    text = ("# While Loops\nA while loop repeats instructions while a condition is true. "
            "The loop stops when the condition is false.\n\n"
            "# Photosynthesis\nPhotosynthesis converts light into chemical energy. "
            "Chlorophyll absorbs light energy in green plants.")
    _ingest(db_session, text, lesson="two")
    out = SahlhaAgent(db_session, AgentState()).extract_skills(
        course_id="c", lesson_id="two", force=True)
    assert len(out["skills"]) >= 2


def test_repeated_headings_no_duplicate_and_apparatus_ignored(db_session):
    text = ("Table of Contents\nPhotosynthesis .... 1\nCell Structure .... 2\n\n"
            "# Photosynthesis\nPhotosynthesis converts light into chemical energy with chlorophyll.\n\n"
            "# Photosynthesis\nPhotosynthesis produces chemical energy from sunlight in plants.\n\n"
            "Bibliography\nSmith 2020. Jones 2021.")
    _ingest(db_session, text, lesson="dup")
    out = SahlhaAgent(db_session, AgentState()).extract_skills(
        course_id="c", lesson_id="dup", force=True)
    names = [s["name"].lower() for s in out["skills"]]
    assert len(names) == len(set(names)), f"duplicates: {names}"
    assert not any("bibliograph" in n or "content" in n for n in names)
    assert any("photosynth" in n for n in names)


def test_long_lesson_beyond_old_six_cap(db_session):
    text = "\n\n".join(
        f"# Topic {i}\nTopic {i} is an independently defined concept with supporting lesson details "
        f"and examples for topic {i}." for i in range(12))
    _ingest(db_session, text, lesson="long")
    out = SahlhaAgent(db_session, AgentState()).extract_skills(
        course_id="c", lesson_id="long", force=True)
    assert len(out["skills"]) > 6, "dynamic cap must allow >6 for long lessons"
    assert any("11" in s["name"] for s in out["skills"]), "later concepts must survive"
    # Explicit cap is still respected.
    out2 = SahlhaAgent(db_session, AgentState()).extract_skills(
        course_id="c", lesson_id="long", max_skills=4, force=True)
    assert len(out2["skills"]) <= 4


def test_consolidation_prompt_and_dynamic_cap_units():
    small_map = {"domain": "science", "sections": [
        {"section_id": f"s{i}", "heading": f"Topic {i}",
         "summary": [f"Topic {i} is taught with examples."],
         "chunk_ids": [f"c{i}"]} for i in range(2)]}
    small_chunks = [{"chunk_id": f"c{i}", "course_id": "c", "lesson_id": "l",
                     "section_id": f"s{i}", "text": "x " * 500} for i in range(2)]
    assert content_tools.dynamic_skill_cap(small_map, small_chunks, 2) <= 6
    cmap = {"domain": "science", "sections": [
        {"section_id": f"s{i}", "heading": f"Topic {i}",
         "summary": [f"Topic {i} is taught with examples."],
         "chunk_ids": [f"c{i}"]} for i in range(10)]}
    chunks = [{"chunk_id": f"c{i}", "course_id": "c", "lesson_id": "l",
               "section_id": f"s{i}", "text": "x " * 500} for i in range(10)]
    assert content_tools.dynamic_skill_cap(cmap, chunks, 16) > 6
    assert content_tools.dynamic_skill_cap(cmap, chunks, 2, explicit_max=3) == 3
    from sahlha.app.agent.prompts import build_skill_consolidation_prompt
    system, user = build_skill_consolidation_prompt(
        course_id="c", lesson_id="l", content_map=cmap,
        candidates=[{"skill_id": "a", "name": "A",
                     "evidence_chunk_ids": ["c0"], "source_section_ids": ["s0"]}],
        max_skills=8)
    assert "WHOLE-LESSON" in system or "consolidat" in system.lower()
    assert "c0" in user and "s0" in user


# ---------------------------------------------------------- 2. bank versioning
def _bank(db, skill, texts, status="approved", lesson="banked", course="c"):
    repo.upsert_skill(db, course_id=course, lesson_id=lesson, skill_id=skill, name=skill.title())
    records = [dict(skill_id=skill, question_type="multiple_choice",
                    question_text=t, options=["a", "b", "c", "d"],
                    correct_answer=0, difficulty="easy") for t in texts]
    row = repo.create_bank(db, course_id=course, lesson_id=lesson, skill_id=skill,
                           questions=records)
    repo.set_bank_status(db, row, status)
    return row


def test_latest_bank_only_selection_and_history(db_session):
    repo.get_or_create_student(db_session, "s1")
    v1 = _bank(db_session, "loops", [f"v1 question {i} about loops" for i in range(6)])
    v2 = _bank(db_session, "loops", [f"v2 question {i} about loops" for i in range(6)])
    assert (v1.version, v2.version) == (1, 2)
    latest = repo.latest_approved_banks(db_session, course_id="c", lesson_id="banked")
    assert len(latest) == 1 and latest[0].id == v2.id
    pool = repo.get_latest_approved_questions(db_session, course_id="c", lesson_id="banked")
    assert {q.question_bank_id for q in pool} == {v2.id}
    # History still loads v1 questions.
    assert repo.get_question(db_session, repo.get_questions(db_session, v1.id)[0].id) is not None
    # New assessment uses only v2.
    from sahlha.app.agent.tools import assessment_tools
    selected, _ = assessment_tools.select_questions(
        db_session, student_id="s1", course_id="c", lesson_id="banked", skill_id="loops")
    assert selected and {q["bank_id"] for q in selected} == {v2.id}
    # Flagged v2 question excluded.
    repo.flag_question(db_session, selected[0]["id"], "bad")
    selected2, _ = assessment_tools.select_questions(
        db_session, student_id="s1", course_id="c", lesson_id="banked", skill_id="loops")
    assert selected[0]["id"] not in {q["id"] for q in selected2}
    # Old assessment referencing v1 still evaluates.
    old_q = repo.get_questions(db_session, v1.id)[0]
    assert assessment_tools.evaluate_answer(
        {"id": old_q.id, "skill_id": "loops", "type": "multiple_choice",
         "correct_answer": 0}, 0)["correct"]


# ---------------------------------------------------------- 3. verification
def test_conceptual_survives_verifier_and_rejection_removes(db_session, monkeypatch):
    context = [{"chunk_id": "a", "text": "Chlorophyll absorbs light energy in green plants. Photosynthesis produces chemical energy from sunlight.",
                "learning_objective": "Explain photosynthesis."}]
    q = {"question": "Which pigment absorbs light energy in green plants?",
         "type": "multiple_choice", "options": ["Chlorophyll", "Hemoglobin", "Insulin", "Keratin"],
         "correct_answer": 0, "difficulty": "easy",
         "evidence_chunk_ids": ["a"], "learning_objective": "Explain photosynthesis.",
         "tested_concept": "chlorophyll", "verification": {"source_quote": "Chlorophyll absorbs light energy in green plants."}}
    assert critique_tools.critique_question(q, context, "sci")[0]
    monkeypatch.setattr(settings, "semantic_verification_enabled", True)
    monkeypatch.setattr(llm_mod, "_resolve_provider", lambda: ("groq", "k", "m"))
    checks = {k: True for k in ["answerable", "answer_supported", "distractors_incorrect",
                                "unambiguous", "clear", "difficulty", "objective"]}
    monkeypatch.setattr(critique_tools, "complete_json",
                        lambda *a, **k: ({"valid": True, "checks": checks}, "groq"))
    kept, _ = critique_tools.critique_and_top_up([q], context, "sci", 1)
    assert kept and kept[0]["verification"]["method"] in ("llm_verified", "llm")
    bad_checks = dict(checks, answer_supported=False)
    monkeypatch.setattr(critique_tools, "complete_json",
                        lambda *a, **k: ({"valid": False, "checks": bad_checks}, "groq"))
    kept2, meta = critique_tools.critique_and_top_up([q], context, "sci", 1, allow_partial=True)
    # Rejected conceptual is topped up with safe fallback, never kept as-is.
    assert all("_____" in r["question"] for r in kept2) or meta["rejected"]


def test_offline_fallback_still_source_completion(db_session, monkeypatch):
    monkeypatch.setattr(llm_mod, "_resolve_provider", lambda: ("", "", ""))
    context = [{"chunk_id": "a", "text": "Chlorophyll absorbs light energy in green plants. Photosynthesis produces chemical energy from sunlight."}]
    out, backend = llm_mod.generate_questions_llm("s", "u", context, "sci", 2, "")
    assert backend.startswith("fallback") and all("_____" in q["question"] for q in out)


# ---------------------------------------------------------- 4. regeneration scope
def test_regeneration_strict_skill_scope(db_session):
    _ingest(db_session, ("Photosynthesis is the process plants use to convert light into chemical energy. "
                         "Chlorophyll is a pigment that absorbs light energy in green plants. "
                         "Photosynthesis produces chemical energy from sunlight for growth."),
            lesson="regen")
    SahlhaAgent(db_session, AgentState()).extract_skills(course_id="c", lesson_id="regen", force=True)
    skills = repo.list_skills(db_session, course_id="c", lesson_id="regen")
    assert skills
    bank = SahlhaAgent(db_session, AgentState()).generate_question_bank(
        course_id="c", lesson_id="regen", skill_id=skills[0].skill_id, n_questions=2,
        allow_partial=True)
    row = repo.get_bank(db_session, bank["question_bank_id"])
    qid = repo.get_questions(db_session, row.id)[0].id
    from sahlha.app.services import platform as plat
    out = plat.regenerate_question(db_session, row, qid, feedback="different")
    assert out["question"]["id"] == qid
    # Evidence of the regenerated question must be within the skill scope.
    qrow = repo.get_question(db_session, qid)
    skill = repo.get_skill(db_session, course_id="c", lesson_id="regen",
                           skill_id=skills[0].skill_id)
    assert set(qrow.evidence_chunk_ids or []) <= set(skill.evidence_chunk_ids or [])


# ---------------------------------------------------------- 5. student payload
def test_student_skill_payload_has_learning_content(client, db_session):
    from tests.test_platform import _setup_teacher_student, _material_flow, _auth
    teacher, student, room = _setup_teacher_student(client)
    material = _material_flow(client, teacher, room)
    skills = client.get(f"/materials/{material['id']}/skills",
                        headers=_auth(teacher["token"])).json()
    assert skills
    payload = client.get(f"/student/skills/{skills[0]['skill_id']}",
                         params={"material_id": material["id"], "classroom_id": room["id"]},
                         headers=_auth(student["token"])).json()
    for field in ("learning_objective", "misconceptions", "learning_content",
                  "visual_type", "visual_spec", "playground"):
        assert field in payload, f"missing {field}"
    for legacy in ("name", "description", "explanation", "key_concepts",
                   "state", "position", "help_order"):
        assert legacy in payload


# ---------------------------------------------------------- 6. multilingual
def test_multilingual_tokens_and_scoped_retrieval(db_session):
    tokens = multilingual_tokens("Photosynthesis light_energy 3.5 test_case")
    assert "light_energy" in tokens and "test_case" in tokens
    _ingest(db_session, "Photosynthesis converts light into chemical energy for plants.",
            lesson="en", filename="en.txt")
    _ingest(db_session, "Al-Khwarizmi explained algebra and equations in detail for students.",
            lesson="ar", filename="ar.txt")
    found_en = vectorstore.search(db_session, "photosynthesis light energy",
                                  course_id="c", lesson_id="en")
    assert found_en and found_en[0]["lesson_id"] == "en"
    found_ar = vectorstore.search(db_session, "algebra equations Khwarizmi",
                                  course_id="c", lesson_id="ar")
    assert found_ar and found_ar[0]["lesson_id"] == "ar"
    # No cross-lesson leakage.
    assert all(c["lesson_id"] == "en" for c in found_en)
    assert "retrieval_stages" in found_en[0] and "retrieval_sources" in found_en[0]


# ---------------------------------------------------------- 7. OCR
def test_ocr_quality_selective_and_warnings():
    good = ("A clean native lesson explains fractions as equal parts of a whole. "
            "Students learn numerators and denominators with examples.")
    score, reasons = ocr.assess_page_quality(good)
    assert score >= 0.6 and not reasons
    bad_score, bad_reasons = ocr.assess_page_quality("a b c d e f g \x00\x00 xyz")
    assert bad_score < 0.65 and bad_reasons


def test_ocr_mixed_pdf_only_poor_pages(monkeypatch):
    from pypdf import PdfReader, PdfWriter
    from tests.test_upload_edges import text_pdf
    writer = PdfWriter()
    for text in ("A clean native lesson explains fractions as equal parts of a whole with examples.",
                 "x"):
        writer.add_page(PdfReader(io.BytesIO(text_pdf(text))).pages[0])
    data = io.BytesIO()
    writer.write(data)
    calls = []

    def scan(payload, suffix):
        calls.append(1)
        return "Recovered denominators and numerators.", "ocr:tesseract"

    monkeypatch.setattr(ocr, "_try_ocr_images", scan)
    result = ocr.extract_document_text(data.getvalue(), "mixed.pdf")
    assert calls == [1] and result.num_pages == 2
    # Poor page was OCRed (selective), good page kept natively.
    assert result.method == "hybrid:pypdf+tesseract"
    assert "Recovered" in result.text and "clean native" in result.text


# ---------------------------------------------------------- 8. chunking
def test_chunk_overlap_and_structure_splits():
    text = ("Sentence one explains photosynthesis clearly. " * 6 + "\n\n"
            + "Second paragraph explains chlorophyll in green plants. " * 6)
    blocks = text_blocks(text)
    chunks = chunk_blocks(blocks, document_id="d", chunk_size=200, chunk_overlap=60)
    assert len(chunks) >= 2
    overlap_found = any(c["block_metadata"].get("has_overlap") for c in chunks[1:])
    assert overlap_found, "adjacent prose chunks must overlap"
    assert all(c["section_id"] and c["chunk_index"] is not None for c in chunks)
    assert len({c["chunk_index"] for c in chunks}) == len(chunks)
    code = chunk_blocks([DocumentBlock(1, 0, "code", "x" * 2000)],
                        chunk_size=100, chunk_overlap=10)
    assert all(len(c["text"]) <= 400 for c in code)
    assert "".join(c["text"] for c in code) == "x" * 2000
    assert code[-1]["block_metadata"]["continuation"]
    table_text = "\n".join(f"row{i}\tvalue{i}" for i in range(20))
    table = chunk_blocks([DocumentBlock(1, 0, "table", table_text)],
                         chunk_size=100, chunk_overlap=10)
    assert all("\n" in c["text"] or len(c["text"]) <= 400 for c in table)


# ---------------------------------------------------------- 9. repair
def test_structured_repair_bounded(monkeypatch):
    calls = []

    def fake_call(system, user, temperature=0.4):
        calls.append(system[:10])
        if len(calls) == 1:
            return "not json", "groq"
        return '{"skills": []}', "groq"

    monkeypatch.setattr(llm_mod, "_call_llm", fake_call)
    monkeypatch.setattr(llm_mod, "_resolve_provider", lambda: ("groq", "k", "m"))
    monkeypatch.setattr(llm_mod, "_alternate_provider", lambda: ("", "", ""))
    data, backend = llm_mod.complete_json("system", "user")
    assert data == {"skills": []} and "repair" in backend
    assert len(calls) == 2, "exactly one repair attempt"

    def always_bad(system, user, temperature=0.4):
        calls.append("bad")
        return "not json", "groq"

    monkeypatch.setattr(llm_mod, "_call_llm", always_bad)
    try:
        llm_mod.complete_json("system", "user")
        assert False, "must raise after bounded attempts"
    except RuntimeError:
        pass
    assert len(calls) <= 5, "no retry storms"


# ---------------------------------------------------------- 10. legacy compat
def test_legacy_progress_preserved_with_new_scoping(db_session):
    repo.get_or_create_student(db_session, "legacy_s")
    repo.upsert_skill(db_session, course_id="c", lesson_id="old", skill_id="loops", name="Loops")
    perf = repo.upsert_skill_performance(db_session, student_id="legacy_s",
                                         course_id="c", lesson_id="old",
                                         skill_id="loops", correct=True)
    assert perf.total_attempts == 1
    v1 = _bank(db_session, "loops", [f"legacy q {i}" for i in range(4)], lesson="old")
    repo.set_bank_status(db_session, v1, "approved")
    latest = repo.latest_approved_banks(db_session, course_id="c", lesson_id="old")
    assert latest and latest[0].id == v1.id
    assert repo.get_skill_performance(db_session, "legacy_s", course_id="c",
                                      lesson_id="old")[0].total_attempts == 1


# ---------------------------------------------------------- golden multilingual
GOLDEN_EXTRA = {
    "biology": "# Cell Structure\nCells contain specialized structures called organelles. The nucleus stores DNA and controls the cell.",
    "history": "# The Industrial Revolution\nThe Industrial Revolution brought manufacturing changes. Steam engines powered factories in the 1800s.",
    "geography": "# Latitude and Longitude\nLatitude measures north-south position. Longitude measures east-west position on maps.",
    "language": "# Sentence Structure\nA sentence has a subject and a verb. The subject performs the action of the verb.",
    "arabic": "# التمثيل الضوئي\nالتمثيل الضوئي هو العملية التي تستخدمها النباتات لتحويل الضوء إلى طاقة كيميائية. الكلوروفيل يمتص الضوء.",
    "mixed": "# Photosynthesis التمثيل الضوئي\nPhotosynthesis (التمثيل الضوئي) converts light into chemical energy. Chlorophyll الكلوروفيل absorbs light.",
}


def test_golden_extra_grounded(db_session):
    for lesson, text in GOLDEN_EXTRA.items():
        ingestion.ingest_upload(db_session, file_bytes=text.encode(), filename=f"{lesson}.md",
                                course_id="golden2", lesson_id=lesson, defer_index=True)
        mapped, chunks = content_tools.build_content_map(db_session, "golden2", lesson)
        assert chunks
        result = SahlhaAgent(db_session, AgentState()).extract_skills(
            course_id="golden2", lesson_id=lesson, force=True)
        assert result["skills"], lesson
        ids = {c["chunk_id"] for c in chunks}
        for skill in result["skills"]:
            assert set(skill["evidence_chunk_ids"]) <= ids, lesson


def test_quality_signals_present(db_session):
    _ingest(db_session, ("Photosynthesis is the process plants use to convert light into chemical energy. "
                         "Chlorophyll is a pigment that absorbs light energy in green plants. "
                         "Photosynthesis produces chemical energy from sunlight for growth."),
            lesson="qual")
    SahlhaAgent(db_session, AgentState()).extract_skills(course_id="c", lesson_id="qual", force=True)
    from sahlha.app.agent.tools import quality_tools
    q = quality_tools.lesson_quality(db_session, "c", "qual")
    for key in ("skill_coverage", "evidence_coverage", "duplicate_skill_rate",
                "question_grounding_quality", "semantic_question_ratio",
                "fallback_question_ratio", "ocr_warning_count",
                "active_bank_version_health"):
        assert key in q, f"missing {key}"


def test_health_flags_no_secrets(client):
    data = client.get("/health").json()
    for key in ("llm_configured", "dense_embeddings_enabled", "reranker_enabled", "ocr_available"):
        assert key in data and isinstance(data[key], bool)
    assert not any("key" in k.lower() and isinstance(v, str) and len(v) > 8
                   for k, v in data.items())
