"""Platform tests: auth, RBAC, classrooms, materials, banks, assessment, mastery."""
from __future__ import annotations

from tests.conftest import SAMPLE_TEXT


def _register(client, name, email, password, role):
    r = client.post("/auth/register", json={"name": name, "email": email,
                                            "password": password, "role": role})
    assert r.status_code == 201, r.text
    return r.json()


def _login(client, email, password):
    r = client.post("/auth/login", json={"email": email, "password": password})
    assert r.status_code == 200, r.text
    return r.json()


def _auth(token):
    return {"Authorization": f"Bearer {token}"}


def _setup_teacher_student(client):
    t = _register(client, "Sara", "sara@t.com", "secret12", "teacher")
    s = _register(client, "Youssef", "youssef@s.com", "secret12", "student")
    room = client.post("/classrooms", json={"name": "Grade 5-A", "subject": "Math",
                                            "grade_level": "5"},
                       headers=_auth(t["token"])).json()
    joined = client.post("/classrooms/join", json={"join_code": room["join_code"]},
                         headers=_auth(s["token"]))
    assert joined.status_code == 200
    return t, s, room


def _upload(client, token, filename="lesson.txt", text=SAMPLE_TEXT, **form):
    files = {"file": (filename, text.encode(), "text/plain")}
    return client.post("/materials/upload", files=files, data=form,
                       headers=_auth(token))


def _material_flow(client, t, room):
    up = _upload(client, t["token"], classroom_id=room["id"], title="Fractions")
    assert up.status_code == 201, up.text
    mat = up.json()["material"]
    assert mat["status"] == "processing"
    mat = client.get(f"/materials/{mat['id']}", headers=_auth(t["token"])).json()
    assert mat["status"] == "processed"
    ex = client.post(f"/materials/{mat['id']}/extract-skills", headers=_auth(t["token"]))
    assert ex.status_code == 200, ex.text
    assert len(ex.json()["skills"]) >= 1
    gen = client.post(f"/materials/{mat['id']}/generate-banks",
                      json={"n_questions": 5}, headers=_auth(t["token"]))
    assert gen.status_code == 200, gen.text
    return mat


# ---- auth ----
def test_register_login_me_hashing(client, db_session):
    out = _register(client, "A", "a@x.com", "secret12", "student")
    assert out["user"]["email"] == "a@x.com"
    assert "token" in out and out["token"]
    # password is hashed, never plaintext
    from sahlha.app.database.repositories import platform as prepo

    user = prepo.get_user_by_email(db_session, "a@x.com")
    assert user.password_hash != "secret12" and user.password_hash.startswith("pbkdf2$")
    me = client.get("/auth/me", headers=_auth(out["token"]))
    assert me.status_code == 200 and me.json()["role"] == "student"
    bad = client.post("/auth/login", json={"email": "a@x.com", "password": "wrongpass"})
    assert bad.status_code == 401
    dup = client.post("/auth/register", json={"name": "B", "email": "a@x.com",
                                              "password": "secret12", "role": "student"})
    assert dup.status_code == 409
    assert client.get("/auth/me").status_code == 401
    assert client.get("/auth/me", headers=_auth("bogus")).status_code == 401


def test_role_restrictions(client):
    t = _register(client, "T", "t@x.com", "secret12", "teacher")
    s = _register(client, "S", "s@x.com", "secret12", "student")
    p = _register(client, "P", "p@x.com", "secret12", "parent")
    # student cannot create classroom
    r = client.post("/classrooms", json={"name": "X"}, headers=_auth(s["token"]))
    assert r.status_code == 403
    # teacher cannot join classroom
    r = client.post("/classrooms/join", json={"join_code": "AAAA"}, headers=_auth(t["token"]))
    assert r.status_code == 403
    # parent cannot list classrooms
    assert client.get("/classrooms", headers=_auth(p["token"])).status_code == 403
    # student cannot see teacher overview
    assert client.get("/teacher/overview", headers=_auth(s["token"])).status_code == 403


# ---- classrooms ----
def test_classroom_crud_and_join(client):
    t, s, room = _setup_teacher_student(client)
    assert room["join_code"] and len(room["join_code"]) == 8
    # duplicate enrollment is idempotent
    again = client.post("/classrooms/join", json={"join_code": room["join_code"]},
                        headers=_auth(s["token"]))
    assert again.json()["already_enrolled"] is True
    bad = client.post("/classrooms/join", json={"join_code": "NOPE1234"},
                      headers=_auth(s["token"]))
    assert bad.status_code == 404
    # teacher updates classroom
    upd = client.patch(f"/classrooms/{room['id']}", json={"name": "Grade 5-B"},
                       headers=_auth(t["token"]))
    assert upd.json()["name"] == "Grade 5-B"
    # teacher sees students
    studs = client.get(f"/classrooms/{room['id']}/students", headers=_auth(t["token"]))
    assert len(studs.json()) == 1
    # another teacher cannot access
    t2 = _register(client, "T2", "t2@x.com", "secret12", "teacher")
    assert client.get(f"/classrooms/{room['id']}", headers=_auth(t2["token"])).status_code == 404
    assert client.patch(f"/classrooms/{room['id']}", json={"name": "H"},
                        headers=_auth(t2["token"])).status_code == 404


def test_cross_classroom_isolation(client):
    t, s, room = _setup_teacher_student(client)
    s2 = _register(client, "S2", "s2@x.com", "secret12", "student")
    assert client.get(f"/classrooms/{room['id']}", headers=_auth(s2["token"])).status_code == 404
    assert client.get("/student/learning-path",
                      params={"classroom_id": room["id"]},
                      headers=_auth(s2["token"])).status_code == 404


# ---- parent linking ----
def test_parent_linking(client):
    t, s, room = _setup_teacher_student(client)
    me = client.get("/student/profile", headers=_auth(s["token"])).json()
    assert me["link_code"]
    p = _register(client, "Dad", "dad@x.com", "secret12", "parent")
    link = client.post("/parent/link-child", json={"link_code": me["link_code"]},
                       headers=_auth(p["token"]))
    assert link.status_code == 201
    dup = client.post("/parent/link-child", json={"link_code": me["link_code"]},
                      headers=_auth(p["token"]))
    assert dup.json()["already_linked"] is True
    bad = client.post("/parent/link-child", json={"link_code": "BADCODE1"},
                      headers=_auth(p["token"]))
    assert bad.status_code == 404
    kids = client.get("/parent/children", headers=_auth(p["token"])).json()
    assert len(kids) == 1 and kids[0]["id"] == s["user"]["id"]
    # unlinked parent cannot access
    p2 = _register(client, "Mom", "mom@x.com", "secret12", "parent")
    r = client.get(f"/parent/children/{s['user']['id']}/progress",
                   headers=_auth(p2["token"]))
    assert r.status_code == 404


# ---- materials + AI integration ----
def test_teacher_material_flow(client):
    t, s, room = _setup_teacher_student(client)
    mat = _material_flow(client, t, room)
    # skills listed for student (enrolled)
    skills = client.get(f"/materials/{mat['id']}/skills", headers=_auth(s["token"]))
    assert skills.status_code == 200 and len(skills.json()) >= 1
    # student sees material; outsider student does not
    s2 = _register(client, "S2", "s2b@x.com", "secret12", "student")
    assert client.get(f"/materials/{mat['id']}", headers=_auth(s2["token"])).status_code == 404
    # unsupported extension rejected
    bad = _upload(client, t["token"], filename="evil.exe", text="x",
                  classroom_id=room["id"])
    assert bad.status_code == 422


def test_parent_supplementary_separation(client):
    t, s, room = _setup_teacher_student(client)
    p = _register(client, "Dad", "dad2@x.com", "secret12", "parent")
    me = client.get("/student/profile", headers=_auth(s["token"])).json()
    client.post("/parent/link-child", json={"link_code": me["link_code"]},
                headers=_auth(p["token"]))
    up = _upload(client, p["token"], child_student_id=s["user"]["id"], title="Extra")
    assert up.status_code == 201
    mat = up.json()["material"]
    assert mat["scope"] == "supplementary" and mat["classroom_id"] is None
    # teacher classroom materials do NOT include supplementary
    official = client.get("/materials", params={"classroom_id": room["id"]},
                          headers=_auth(t["token"])).json()
    assert all(m["id"] != mat["id"] for m in official)
    # child can study supplementary; teacher cannot see it
    assert client.get(f"/materials/{mat['id']}", headers=_auth(s["token"])).status_code == 200
    # parent upload for unlinked child rejected
    s2 = _register(client, "S2", "s2c@x.com", "secret12", "student")
    bad = _upload(client, p["token"], child_student_id=s2["user"]["id"])
    assert bad.status_code == 404


# ---- question bank lifecycle ----
def test_bank_lifecycle_and_security(client):
    t, s, room = _setup_teacher_student(client)
    mat = _material_flow(client, t, room)
    banks = client.get("/teacher/banks", params={"material_id": mat["id"]},
                       headers=_auth(t["token"])).json()
    assert banks and all(b["status"] == "pending_review" for b in banks)
    bank_id = banks[0]["id"]
    # pending bank cannot be assessed
    start = client.post("/student/assessments/start",
                        json={"classroom_id": room["id"], "material_id": mat["id"]},
                        headers=_auth(s["token"]))
    assert start.status_code == 400
    # teacher reviews with correct answers visible
    detail = client.get(f"/teacher/banks/{bank_id}", headers=_auth(t["token"])).json()
    assert "correct_answer" in detail["questions"][0]
    qid = detail["questions"][0]["id"]
    # edit question
    edited = client.patch(f"/teacher/banks/{bank_id}/questions/{qid}",
                          json={"difficulty": "easy"}, headers=_auth(t["token"])).json()
    assert edited["difficulty"] == "easy"
    # regenerate one question
    regen = client.post(f"/teacher/banks/{bank_id}/questions/{qid}/regenerate",
                        json={"feedback": "Make this easier."},
                        headers=_auth(t["token"]))
    assert regen.status_code == 200
    # reject one question
    remaining = client.delete(f"/teacher/banks/{bank_id}/questions/{qid}",
                              headers=_auth(t["token"])).json()["remaining"]
    assert remaining == len(detail["questions"]) - 1
    # approve whole bank
    ap = client.post(f"/teacher/banks/{bank_id}/approve", headers=_auth(t["token"]))
    assert ap.json()["status"] == "approved"
    # rejected bank cannot be assessed
    bank2 = banks[1]["id"] if len(banks) > 1 else None
    if bank2:
        client.post(f"/teacher/banks/{bank2}/reject", params={"feedback": "no"},
                    headers=_auth(t["token"]))
    # student assessment works now; correct answers hidden
    start = client.post("/student/assessments/start",
                        json={"classroom_id": room["id"], "material_id": mat["id"], "skill_id": detail["skill_id"]},
                        headers=_auth(s["token"]))
    assert start.status_code == 200, start.text
    payload = start.json()
    assert payload["questions"]
    assert all("correct_answer" not in q for q in payload["questions"])
    # submit all-correct using teacher-visible answers
    detail = client.get(f"/teacher/banks/{bank_id}", headers=_auth(t["token"])).json()
    answers = {q["id"]: q["correct_answer"] for q in detail["questions"]
               if q["id"] in {x["id"] for x in payload["questions"]}}
    sub = client.post(f"/student/assessments/{payload['assessment_id']}/submit",
                      json={"answers": answers}, headers=_auth(s["token"]))
    assert sub.status_code == 200
    assert sub.json()["score"] == 1.0
    # grades + mastery visible
    grades = client.get("/student/grades", headers=_auth(s["token"])).json()
    assert len(grades) == 1 and grades[0]["score"] == 1.0
    # another student's assessment cannot be submitted
    s2 = _register(client, "S2", "s2d@x.com", "secret12", "student")
    client.post("/classrooms/join", json={"join_code": room["join_code"]},
                headers=_auth(s2["token"]))
    st2 = client.post("/student/assessments/start",
                      json={"classroom_id": room["id"], "material_id": mat["id"], "skill_id": detail["skill_id"]},
                      headers=_auth(s2["token"])).json()
    forbidden = client.post(f"/student/assessments/{st2['assessment_id']}/submit",
                            json={"answers": {}}, headers=_auth(s["token"]))
    assert forbidden.status_code == 403


def test_regenerate_bank_new_version(client):
    t, s, room = _setup_teacher_student(client)
    mat = _material_flow(client, t, room)
    banks = client.get("/teacher/banks", params={"material_id": mat["id"]},
                       headers=_auth(t["token"])).json()
    bank_id = banks[0]["id"]
    client.post(f"/teacher/banks/{bank_id}/reject", params={"feedback": "try again"},
                headers=_auth(t["token"]))
    new = client.post(f"/teacher/banks/{bank_id}/regenerate",
                      json={"teacher_feedback": "simpler", "n_questions": 4},
                      headers=_auth(t["token"]))
    assert new.status_code == 201
    assert new.json()["question_bank_id"] != bank_id
    detail = client.get(f"/teacher/banks/{new.json()['question_bank_id']}",
                        headers=_auth(t["token"])).json()
    assert detail["status"] == "pending_review" and detail["version"] == 2
    # old version preserved
    old = client.get(f"/teacher/banks/{bank_id}", headers=_auth(t["token"])).json()
    assert old["status"] == "rejected"


def test_teacher_bank_ownership(client):
    t, s, room = _setup_teacher_student(client)
    mat = _material_flow(client, t, room)
    banks = client.get("/teacher/banks", params={"material_id": mat["id"]},
                       headers=_auth(t["token"])).json()
    t2 = _register(client, "T2", "t2b@x.com", "secret12", "teacher")
    assert client.get(f"/teacher/banks/{banks[0]['id']}",
                      headers=_auth(t2["token"])).status_code == 404
    assert client.post(f"/teacher/banks/{banks[0]['id']}/approve",
                       headers=_auth(t2["token"])).status_code == 404


# ---- learning path / skills / profile ----
def test_learning_path_profile_mastery(client):
    t, s, room = _setup_teacher_student(client)
    mat = _material_flow(client, t, room)
    banks = client.get("/teacher/banks", params={"material_id": mat["id"]},
                       headers=_auth(t["token"])).json()
    for b in banks:
        client.post(f"/teacher/banks/{b['id']}/approve", headers=_auth(t["token"]))
    # onboarding
    prof = client.post("/student/profile", json={"answers": {
        "reading": "hard", "focus": "short", "instructions": "steps",
        "presentation": "listen", "practice": "practice_more",
        "session": "short", "confidence": "sometimes"}}, headers=_auth(s["token"])).json()
    assert prof["onboarding_completed"] is True
    assert "Shorter explanations with audio currently help." in " ".join(
        client.get("/student/profile", headers=_auth(s["token"])).json()["support_summary"])
    # home + path
    home = client.get("/student/home", headers=_auth(s["token"])).json()
    assert home["classrooms"][0]["current"] is not None
    path = client.get("/student/learning-path", params={"classroom_id": room["id"]},
                      headers=_auth(s["token"])).json()
    assert path["units"][0]["skills"]
    skid = path["units"][0]["skills"][0]["skill_id"]
    assert path["units"][0]["skills"][0]["state"] == "not_started"
    # skill bundle + help
    bundle = client.get(f"/student/skills/{skid}",
                        params={"material_id": mat["id"], "classroom_id": room["id"]},
                        headers=_auth(s["token"])).json()
    assert bundle["explanation"] and bundle["position"] == 1
    helpb = client.get(f"/student/skills/{skid}/help",
                       params={"material_id": mat["id"], "classroom_id": room["id"],
                               "kind": "steps"},
                       headers=_auth(s["token"])).json()
    assert helpb["steps"]
    # full-correct assessment -> mastered
    start = client.post("/student/assessments/start",
                        json={"classroom_id": room["id"], "material_id": mat["id"],
                              "skill_id": skid}, headers=_auth(s["token"])).json()
    skill_bank = next(b for b in banks if b["skill_id"] == skid)
    detail = client.get(f"/teacher/banks/{skill_bank['id']}",
                        headers=_auth(t["token"])).json()
    amap = {q["id"]: q["correct_answer"] for q in detail["questions"]}
    sub = client.post(f"/student/assessments/{start['assessment_id']}/submit",
                      json={"answers": {q["id"]: amap[q["id"]] for q in start["questions"]}},
                      headers=_auth(s["token"])).json()
    assert sub["mastery_states"][skid] == "mastered"
    path2 = client.get("/student/learning-path", params={"classroom_id": room["id"]},
                       headers=_auth(s["token"])).json()
    assert path2["units"][0]["skills"][0]["state"] == "mastered"
    # teacher sees updated mastery
    mastery_view = client.get(f"/teacher/classrooms/{room['id']}/mastery",
                              headers=_auth(t["token"])).json()
    assert mastery_view["students"][0]["summary"]["mastered"] >= 1


def test_weak_skill_adaptation(client):
    t, s, room = _setup_teacher_student(client)
    mat = _material_flow(client, t, room)
    banks = client.get("/teacher/banks", params={"material_id": mat["id"]},
                       headers=_auth(t["token"])).json()
    for b in banks:
        client.post(f"/teacher/banks/{b['id']}/approve", headers=_auth(t["token"]))
    skid = banks[0]["skill_id"]
    start = client.post("/student/assessments/start",
                        json={"classroom_id": room["id"], "material_id": mat["id"],
                              "skill_id": skid}, headers=_auth(s["token"])).json()
    # submit all wrong
    sub = client.post(f"/student/assessments/{start['assessment_id']}/submit",
                      json={"answers": {q["id"]: "___wrong___" for q in start["questions"]}},
                      headers=_auth(s["token"])).json()
    assert sub["score"] == 0.0
    assert sub["mastery_states"][skid] == "needs_practice"
    # next selection retries failed questions
    start2 = client.post("/student/assessments/start",
                         json={"classroom_id": room["id"], "material_id": mat["id"],
                               "skill_id": skid}, headers=_auth(s["token"])).json()
    first_ids = {q["id"] for q in start["questions"]}
    second_ids = {q["id"] for q in start2["questions"]}
    assert first_ids & second_ids  # failed-retry adaptation preserved


def test_teacher_student_progress_and_parent_view(client):
    t, s, room = _setup_teacher_student(client)
    mat = _material_flow(client, t, room)
    banks = client.get("/teacher/banks", params={"material_id": mat["id"]},
                       headers=_auth(t["token"])).json()
    client.post(f"/teacher/banks/{banks[0]['id']}/approve", headers=_auth(t["token"]))
    start = client.post("/student/assessments/start",
                        json={"classroom_id": room["id"], "material_id": mat["id"], "skill_id": banks[0]["skill_id"]},
                        headers=_auth(s["token"])).json()
    client.post(f"/student/assessments/{start['assessment_id']}/submit",
                json={"answers": {}}, headers=_auth(s["token"]))
    detail = client.get(f"/teacher/classrooms/{room['id']}/students/{s['user']['id']}",
                        headers=_auth(t["token"]))
    assert detail.status_code == 200 and detail.json()["grades"]
    ov = client.get("/teacher/overview", headers=_auth(t["token"])).json()
    assert ov["num_students"] == 1 and ov["needing_support"]
    # parent view
    me = client.get("/student/profile", headers=_auth(s["token"])).json()
    p = _register(client, "Dad", "dad3@x.com", "secret12", "parent")
    client.post("/parent/link-child", json={"link_code": me["link_code"]},
                headers=_auth(p["token"]))
    prog = client.get(f"/parent/children/{s['user']['id']}/progress",
                      headers=_auth(p["token"])).json()
    assert prog["classrooms"] and prog["recent_activity"]
    pg = client.get(f"/parent/children/{s['user']['id']}/grades",
                    headers=_auth(p["token"])).json()
    assert len(pg) == 1


def test_mastery_scoped_per_lesson(client, db_session):
    """Same skill slug in two lessons must not share mastery."""
    from sahlha.app.database.repositories import repositories as repo

    repo.get_or_create_student(db_session, "stu-scope", "Scope")
    repo.upsert_skill_performance(db_session, student_id="stu-scope", skill_id="fractions",
                                  correct=True, course_id="class:A", lesson_id="matA")
    repo.upsert_skill_performance(db_session, student_id="stu-scope", skill_id="fractions",
                                  correct=False, course_id="class:B", lesson_id="matB")
    scoped = repo.get_skill_performance(db_session, "stu-scope", course_id="class:A",
                                        lesson_id="matA")
    assert len(scoped) == 1 and scoped[0].accuracy == 1.0
    scoped_b = repo.get_skill_performance(db_session, "stu-scope", course_id="class:B",
                                          lesson_id="matB")
    assert len(scoped_b) == 1 and scoped_b[0].accuracy == 0.0


def test_check_answer_locks_attempt(client):
    t, s, room = _setup_teacher_student(client)
    mat = _material_flow(client, t, room)
    banks = client.get("/teacher/banks", params={"material_id": mat["id"]},
                       headers=_auth(t["token"])).json()
    client.post(f"/teacher/banks/{banks[0]['id']}/approve",
                headers=_auth(t["token"]))
    start = client.post("/student/assessments/start",
                        json={"classroom_id": room["id"], "material_id": mat["id"], "skill_id": banks[0]["skill_id"]},
                        headers=_auth(s["token"])).json()
    qid = start["questions"][0]["id"]
    assert "correct_answer" not in start["questions"][0]
    # check with a wrong answer -> immediate honest feedback, attempt locked
    chk = client.post(f"/student/assessments/{start['assessment_id']}/check",
                      json={"question_id": qid, "answer": 999},
                      headers=_auth(s["token"])).json()
    assert chk["correct"] is False and chk["locked"] is True
    # submit cannot overwrite the locked attempt
    detail = client.get(f"/teacher/banks/{banks[0]['id']}",
                        headers=_auth(t["token"])).json()
    amap = {q["id"]: q["correct_answer"] for q in detail["questions"]}
    sub = client.post(f"/student/assessments/{start['assessment_id']}/submit",
                      json={"answers": {q["id"]: amap[q["id"]]
                                        for q in start["questions"]}},
                      headers=_auth(s["token"])).json()
    first = next(r for r in sub["results"] if r["question_id"] == qid)
    assert first["correct"] is False  # locked wrong answer stands
