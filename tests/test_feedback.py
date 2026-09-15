"""Feedback loops: critique gate, teacher flags, mastery review signals."""
from sahlha.app.agent.llm import critique_questions, fallback_critique
from sahlha.app.agent.prompts import build_critique_prompt
from sahlha.app.database.repositories import repositories as repo
from sahlha.app.rag import ingestion
from sahlha.app.services import services as svc
from tests.conftest import SAMPLE_TEXT

TEXT = (SAMPLE_TEXT + " ") * 2


def _skill_bank(db_session, n_questions=6):
    ingestion.ingest_upload(db_session, file_bytes=TEXT.encode(), filename="elif.txt",
                            course_id="fb", lesson_id="fl", skill_id="fs")
    svc.extract_skills(db_session, course_id="fb", lesson_id="fl", max_skills=1)
    skills = svc.list_skills(db_session, course_id="fb", lesson_id="fl")
    bank = svc.generate_bank(db_session, course_id="fb", lesson_id="fl",
                             skill_id=skills[0]["skill_id"], n_questions=n_questions)
    return skills[0]["skill_id"], bank["question_bank_id"]


def test_fallback_critique_drops_ungrounded():
    chunks = [{"text": SAMPLE_TEXT}]
    good = {"type": "multiple_choice", "question": "What does the elif keyword mean in Python?",
            "options": ["a", "b", "c", "d"], "correct_answer": 1}
    bad = {"type": "multiple_choice", "question": "Who won the 1998 underwater basket championship?",
           "options": ["a", "b", "c", "d"], "correct_answer": 0}
    verdicts = fallback_critique([good, bad], chunks)
    assert verdicts[0]["grounded"] and verdicts[0]["answer_correct"]
    assert not verdicts[1]["grounded"] and verdicts[1]["issue"]
    # Bad index is also caught
    off = dict(good, correct_answer=9)
    assert fallback_critique([off], chunks)[0]["answer_correct"] is False


def test_generation_keeps_bank_full_after_critique(db_session):
    _, bank_id = _skill_bank(db_session, n_questions=6)
    detail = svc.bank_detail(db_session, bank_id)
    assert len(detail["questions"]) == 6, "critique drops must be topped up to requested size"


def test_flag_excludes_from_selection_and_feeds_regeneration(db_session):
    skid, bank_id = _skill_bank(db_session, n_questions=6)
    qids = [q["id"] for q in svc.bank_detail(db_session, bank_id)["questions"]]
    svc.flag_question(db_session, question_id=qids[0], reason="correct answer is wrong")
    svc.approve_bank(db_session, bank_id)

    started = svc.start_assessment(db_session, student_id="fb_s1", student_name="FB",
                                   course_id="fb", lesson_id="fl", skill_id=skid)
    selected = [q["id"] for q in started["questions"]]
    assert qids[0] not in selected, "flagged question must never resurface"
    assert started["selection_meta"]["flagged_excluded"] == 1

    # Regeneration auto-ingests the flag reason as feedback (no teacher retyping)
    v2 = svc.generate_bank(db_session, course_id="fb", lesson_id="fl",
                           skill_id=skid, n_questions=4)
    assert v2["version"] == 2
    bank2 = repo.get_bank(db_session, v2["question_bank_id"])
    assert "correct answer is wrong" in bank2.teacher_feedback


def test_mastery_review_signals(db_session):
    skid, bank_id = _skill_bank(db_session, n_questions=4)
    svc.approve_bank(db_session, bank_id)
    started = svc.start_assessment(db_session, student_id="fb_s2", student_name="FB2",
                                   course_id="fb", lesson_id="fl", skill_id=skid)
    res = svc.submit_assessment(db_session, assessment_id=started["assessment_id"],
                                answers={q["id"]: "totally wrong xyz" for q in started["questions"]})
    assert skid in res["skills_needing_review"]
    prog = svc.skill_progress(db_session, student_id="fb_s2", course_id="fb", lesson_id="fl")
    row = next(s for s in prog["skills"] if s["skill_id"] == skid)
    assert row["needs_review"] is True and row["accuracy"] == 0.0


def test_http_flag_endpoints(client):
    from tests.conftest import SAMPLE_TEXT as ST

    client.post("/documents/upload", files={"file": ("elif.txt", ST * 2)},
                data={"course_id": "hc", "lesson_id": "hl", "skill_id": "hs"})
    skills = client.post("/agent/extract-skills",
                         json={"course_id": "hc", "lesson_id": "hl", "max_skills": 1}).json()["skills"]
    bank = client.post("/agent/generate-question-bank",
                       json={"course_id": "hc", "lesson_id": "hl",
                             "skill_id": skills[0]["skill_id"], "n_questions": 4}).json()
    detail = client.get(f"/teacher/question-banks/{bank['question_bank_id']}").json()
    qid = detail["questions"][0]["id"]
    flag = client.post(f"/teacher/questions/{qid}/flag", json={"reason": "unclear stem"})
    assert flag.status_code == 200, flag.text
    flags = client.get("/teacher/flags").json()
    assert any(f["question_id"] == qid for f in flags)
    missing = client.post("/teacher/questions/nope/flag", json={"reason": "x"})
    assert missing.status_code == 404
    assert callable(build_critique_prompt) and callable(critique_questions)
