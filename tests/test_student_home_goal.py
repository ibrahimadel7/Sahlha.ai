"""Home daily-goal support: `recent_practiced_at` on classroom cards.

Minimal additive backend contract for the student home upgrade — the app
derives "practiced today" (daily goal) and comeback recency from real
submitted-practice timestamps, with no extra request.
"""
from __future__ import annotations

from datetime import datetime

from tests.conftest import SAMPLE_TEXT


def _register(client, name, email, password, role):
    r = client.post("/auth/register", json={"name": name, "email": email,
                                            "password": password, "role": role})
    assert r.status_code == 201, r.text
    return r.json()


def _auth(token):
    return {"Authorization": f"Bearer {token}"}


def _classroom_setup(client):
    t = _register(client, "T", "tg@x.com", "secret12", "teacher")
    s = _register(client, "S", "sg@x.com", "secret12", "student")
    room = client.post("/classrooms", json={"name": "Grade 5-A", "subject": "Math",
                                            "grade_level": "5"},
                       headers=_auth(t["token"])).json()
    joined = client.post("/classrooms/join", json={"join_code": room["join_code"]},
                         headers=_auth(s["token"]))
    assert joined.status_code == 200
    up = client.post("/materials/upload",
                     files={"file": ("l.txt", SAMPLE_TEXT.encode(), "text/plain")},
                     data={"classroom_id": room["id"], "title": "Frac"},
                     headers=_auth(t["token"]))
    assert up.status_code == 201, up.text
    mat = up.json()["material"]
    ex = client.post(f"/materials/{mat['id']}/extract-skills",
                     headers=_auth(t["token"]))
    assert ex.status_code == 200, ex.text
    gen = client.post(f"/materials/{mat['id']}/generate-banks",
                      json={"n_questions": 4}, headers=_auth(t["token"]))
    assert gen.status_code == 200, gen.text
    return t, s, room, mat


def test_home_card_reports_recent_practiced_at(client):
    t, s, room, mat = _classroom_setup(client)
    home = client.get("/student/home", headers=_auth(s["token"])).json()
    card = home["classrooms"][0]
    assert "recent_practiced_at" in card
    assert card["recent_practiced_at"] is None  # no practice yet

    banks = client.get("/teacher/banks", params={"material_id": mat["id"]},
                       headers=_auth(t["token"])).json()
    for b in banks:
        client.post(f"/teacher/banks/{b['id']}/approve", headers=_auth(t["token"]))
    start = client.post("/student/assessments/start",
                        json={"classroom_id": room["id"], "material_id": mat["id"]},
                        headers=_auth(s["token"]))
    assert start.status_code == 200, start.text
    sub = client.post(f"/student/assessments/{start.json()['assessment_id']}/submit",
                      json={"answers": {}}, headers=_auth(s["token"]))
    assert sub.status_code == 200

    home2 = client.get("/student/home", headers=_auth(s["token"])).json()
    practiced_at = home2["classrooms"][0]["recent_practiced_at"]
    assert practiced_at  # ISO timestamp of the latest submitted practice
    datetime.fromisoformat(practiced_at)  # parses cleanly on the client
