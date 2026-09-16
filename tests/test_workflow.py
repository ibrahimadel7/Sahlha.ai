"""LangGraph teacher content workflow: run → pause → approve/reject → resume."""
from sahlha.app.services import services as svc
from tests.conftest import SAMPLE_TEXT


def _ingest(db_session, course="wf_c", lesson="wf_lesson"):
    from sahlha.app.rag import ingestion

    return ingestion.ingest_upload(
        db_session, file_bytes=(SAMPLE_TEXT * 3).encode(), filename="elif.txt",
        course_id=course, lesson_id=lesson, skill_id="general", eager=True)


def test_workflow_run_pauses_for_teacher(db_session):
    _ingest(db_session)
    snap = svc.run_content_workflow(db_session, course_id="wf_c", lesson_id="wf_lesson",
                                    n_questions=4)
    assert snap["status"] == "waiting_for_teacher"
    assert snap["waiting_on"] == ["teacher_review"]
    assert len(snap["skills"]) >= 1
    assert all(s["has_explanation"] for s in snap["skills"])
    assert snap["lesson"] and snap["lesson"]["has_explanation"]
    assert len(snap["banks"]) == len(snap["skills"])
    assert all(b["status"] == "pending_review" and b["num_questions"] == 4
               for b in snap["banks"])
    events = [t["event"] for t in snap["trace"]]
    assert events[:5] == ["workflow:start", "workflow:retrieved", "workflow:extracted",
                          "workflow:lesson_explained", "workflow:banks_generated"]


def test_workflow_approve_finishes_and_banks_assessable(db_session):
    _ingest(db_session)
    snap = svc.run_content_workflow(db_session, course_id="wf_c", lesson_id="wf_lesson",
                                    n_questions=4)
    done = svc.teacher_decide(db_session, thread_id=snap["thread_id"], action="approve")
    assert done["status"] == "approved"
    assert all(b["status"] == "approved" for b in done["banks"])
    # Same banks flow into the classic deterministic assessment path (interop).
    started = svc.start_assessment(db_session, student_id="wf_s1",
                                   course_id="wf_c", lesson_id="wf_lesson")
    assert len(started["questions"]) == 4 * len(done["banks"])
    answers = {q["id"]: 0 for q in started["questions"]}
    sub = svc.submit_assessment(db_session, assessment_id=started["assessment_id"],
                                answers=answers)
    assert sub["total"] == len(started["questions"])


def test_workflow_reject_regenerates_new_version(db_session):
    _ingest(db_session)
    snap = svc.run_content_workflow(db_session, course_id="wf_c", lesson_id="wf_lesson",
                                    n_questions=4)
    v1 = [b["question_bank_id"] for b in snap["banks"]]
    rej = svc.teacher_decide(db_session, thread_id=snap["thread_id"],
                             action="reject", feedback="make them harder")
    assert rej["status"] == "waiting_for_teacher"
    assert rej["regeneration_attempts"] == 1
    assert rej["teacher_decision"]["action"] == "reject"
    v2 = [b["question_bank_id"] for b in rej["banks"]]
    assert set(v1).isdisjoint(v2)  # append-only versions, never overwritten
    assert all(b["version"] == 2 for b in rej["banks"])
    # Old versions are rejected, not left pending.
    from sahlha.app.database.repositories import repositories as repo
    assert all(repo.get_bank(db_session, bid).status == "rejected" for bid in v1)
    done = svc.teacher_decide(db_session, thread_id=snap["thread_id"], action="approve")
    assert done["status"] == "approved"


def test_workflow_reject_exhaustion_needs_teacher(db_session):
    _ingest(db_session)
    snap = svc.run_content_workflow(db_session, course_id="wf_c", lesson_id="wf_lesson",
                                    n_questions=4)
    tid = snap["thread_id"]
    for i in range(3):
        snap = svc.teacher_decide(db_session, thread_id=tid, action="reject",
                                  feedback=f"try {i}")
    assert snap["status"] == "needs_teacher"
    assert snap["regeneration_attempts"] == 3
    try:
        svc.teacher_decide(db_session, thread_id=tid, action="approve")
        raise AssertionError("decide after finish should fail")
    except ValueError as exc:
        assert "not waiting" in str(exc)


def test_workflow_no_material_fails_gracefully(db_session):
    snap = svc.run_content_workflow(db_session, course_id="wf_c", lesson_id="nope_missing")
    assert snap["status"] == "failed"
    assert "No material" in snap["error"]


def test_workflow_invalid_input(db_session):
    _ingest(db_session)
    for bad in ("", "  "):
        try:
            svc.run_content_workflow(db_session, course_id=bad, lesson_id="wf_lesson")
            raise AssertionError("empty course should fail")
        except ValueError:
            pass
    snap = svc.run_content_workflow(db_session, course_id="wf_c", lesson_id="wf_lesson",
                                    n_questions=4)
    try:
        svc.teacher_decide(db_session, thread_id=snap["thread_id"], action="maybe")
        raise AssertionError("bad action should fail")
    except ValueError:
        pass
    try:
        svc.workflow_snapshot(db_session, thread_id="missing-thread")
        raise AssertionError("unknown thread should fail")
    except ValueError as exc:
        assert "not found" in str(exc)


def test_workflow_http_endpoints(client):
    up = client.post("/documents/upload", files={"file": ("elif.txt", SAMPLE_TEXT * 3)},
                     data={"course_id": "wf_http", "lesson_id": "wf_http_lesson"})
    assert up.status_code == 200, up.text
    lesson = up.json()["lesson_id"]
    run = client.post("/workflow/content/run",
                      json={"course_id": "wf_http", "lesson_id": lesson, "n_questions": 4})
    assert run.status_code == 200, run.text
    assert run.json()["status"] == "waiting_for_teacher"
    tid = run.json()["thread_id"]
    assert len(run.json()["banks"]) >= 1

    st = client.get("/workflow/content/state", params={"thread_id": tid})
    assert st.status_code == 200 and st.json()["status"] == "waiting_for_teacher"

    rej = client.post("/workflow/content/decide",
                      json={"thread_id": tid, "action": "reject", "feedback": "harder"})
    assert rej.status_code == 200, rej.text
    assert rej.json()["regeneration_attempts"] == 1

    ap = client.post("/workflow/content/decide",
                     json={"thread_id": tid, "action": "approve"})
    assert ap.status_code == 200, ap.text
    assert ap.json()["status"] == "approved"

    again = client.post("/workflow/content/decide",
                        json={"thread_id": tid, "action": "approve"})
    assert again.status_code == 400
    missing = client.get("/workflow/content/state", params={"thread_id": "nope"})
    assert missing.status_code == 404
