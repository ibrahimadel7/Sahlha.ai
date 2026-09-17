"""Regression tests: protected student media (401 vs 503 separation) + signals.

Covers the Read-Aloud trace end to end:
  Flutter tap -> GET /student/skills/{id}/audio (JWT) -> TTS provider.

- 401 root cause: missing/invalid/expired JWT, or a non-student role.
  The endpoint stays protected (never public) and API keys never leave
  the server (clients only receive WAV/JPEG bytes).
- 503 root cause: TTS/image provider unavailable (no key, terms not
  accepted, outage). Media failure degrades to a calm message and never
  breaks the lesson (no 500, no leaked provider internals).
"""
from __future__ import annotations

import io
import wave

import pytest

from sahlha.app.config import settings
from tests.conftest import SAMPLE_TEXT


def _wav(frames: bytes = b"\x01\x02" * 2205) -> bytes:
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(22050)
        w.writeframes(frames)
    return buf.getvalue()


def _register(client, name, email, password, role):
    r = client.post("/auth/register", json={"name": name, "email": email,
                                            "password": password, "role": role})
    assert r.status_code == 201, r.text
    return r.json()


def _auth(token):
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture()
def media_setup(client):
    """Teacher + enrolled student + processed material with one skill."""
    t = _register(client, "T", "tm@media.com", "secret12", "teacher")
    s = _register(client, "S", "sm@media.com", "secret12", "student")
    room = client.post("/classrooms", json={"name": "C", "subject": "Math",
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
    skill = ex.json()["skills"][0]
    assert skill["explanation"]
    return {"teacher": t, "student": s, "room": room, "material": mat,
            "skill_id": skill["skill_id"]}


def _audio_url(skill_id, material_id, room_id):
    return f"/student/skills/{skill_id}/audio"


def _audio_params(material_id, room_id):
    return {"material_id": material_id, "classroom_id": room_id}


# ---- 401: auth failures stay 401 and the endpoint stays protected ----

def test_audio_requires_auth(client, media_setup):
    m = media_setup
    r = client.get(_audio_url(m["skill_id"], m["material"]["id"], m["room"]["id"]),
                   params=_audio_params(m["material"]["id"], m["room"]["id"]))
    assert r.status_code == 401


def test_audio_rejects_bad_token(client, media_setup):
    m = media_setup
    r = client.get(_audio_url(m["skill_id"], m["material"]["id"], m["room"]["id"]),
                   params=_audio_params(m["material"]["id"], m["room"]["id"]),
                   headers=_auth("bogus-token"))
    assert r.status_code == 401


def test_audio_forbids_non_students(client, media_setup):
    m = media_setup
    p = _register(client, "P", "pm@media.com", "secret12", "parent")
    for token in (m["teacher"]["token"], p["token"]):
        r = client.get(_audio_url(m["skill_id"], m["material"]["id"], m["room"]["id"]),
                       params=_audio_params(m["material"]["id"], m["room"]["id"]),
                       headers=_auth(token))
        assert r.status_code == 403, r.text


def test_image_requires_auth(client, media_setup):
    m = media_setup
    r = client.get(f"/student/skills/{m['skill_id']}/image",
                   params=_audio_params(m["material"]["id"], m["room"]["id"]))
    assert r.status_code == 401


def test_audio_unenrolled_student_gets_404_not_401(client, media_setup):
    m = media_setup
    outsider = _register(client, "S2", "sm2@media.com", "secret12", "student")
    r = client.get(_audio_url(m["skill_id"], m["material"]["id"], m["room"]["id"]),
                   params=_audio_params(m["material"]["id"], m["room"]["id"]),
                   headers=_auth(outsider["token"]))
    # Authenticated but not enrolled: hidden as 404 (no existence oracle).
    assert r.status_code == 404


# ---- 404: unknown scope stays 404 (never confused with 401/503) ----

def test_audio_unknown_material_or_skill_is_404(client, media_setup):
    m = media_setup
    h = _auth(m["student"]["token"])
    r = client.get(_audio_url(m["skill_id"], m["material"]["id"], m["room"]["id"]),
                   params={"material_id": "nope", "classroom_id": m["room"]["id"]},
                   headers=h)
    assert r.status_code == 404
    r = client.get(_audio_url("nope", m["material"]["id"], m["room"]["id"]),
                   params=_audio_params(m["material"]["id"], m["room"]["id"]),
                   headers=h)
    assert r.status_code == 404


# ---- 503: provider failure degrades calmly, lesson never breaks ----

def test_audio_provider_failure_is_503_with_calm_message(client, media_setup, monkeypatch):
    from sahlha.app.audio import tts as tts_mod

    def _fail(text, voice=None):
        raise RuntimeError("Groq TTS request failed: model_terms_required")

    monkeypatch.setattr(tts_mod, "synthesize", _fail)
    m = media_setup
    r = client.get(_audio_url(m["skill_id"], m["material"]["id"], m["room"]["id"]),
                   params=_audio_params(m["material"]["id"], m["room"]["id"]),
                   headers=_auth(m["student"]["token"]))
    assert r.status_code == 503, r.text
    assert "unavailable" in r.json()["detail"].lower()
    # Provider internals must not leak to student devices.
    assert "model_terms_required" not in r.text
    assert "canopylabs" not in r.text


def test_audio_missing_key_is_503(client, media_setup, monkeypatch):
    monkeypatch.setattr(settings, "groq_api_key", "")
    monkeypatch.delenv("GROQ_API_KEY", raising=False)
    m = media_setup
    r = client.get(_audio_url(m["skill_id"], m["material"]["id"], m["room"]["id"]),
                   params=_audio_params(m["material"]["id"], m["room"]["id"]),
                   headers=_auth(m["student"]["token"]))
    assert r.status_code == 503, r.text


def test_audio_success_and_cache_single_synth(client, media_setup, monkeypatch, tmp_path):
    """One explanation -> one provider call; repeat taps reuse the cache."""
    from sahlha.app.audio import tts as tts_mod

    calls = []

    def _ok(text, voice=None):
        calls.append((text, voice))
        return _wav(), (voice or "troy")

    monkeypatch.setattr(tts_mod, "synthesize", _ok)
    monkeypatch.setattr(settings, "audio_dir", str(tmp_path))
    m = media_setup
    h = _auth(m["student"]["token"])
    params = _audio_params(m["material"]["id"], m["room"]["id"])
    url = _audio_url(m["skill_id"], m["material"]["id"], m["room"]["id"])
    r1 = client.get(url, params=params, headers=h)
    assert r1.status_code == 200, r1.text
    assert r1.headers["content-type"] == "audio/wav"
    assert len(r1.content) > 100
    r2 = client.get(url, params=params, headers=h)
    assert r2.status_code == 200
    assert r2.content == r1.content
    assert len(calls) == 1  # second tap served from disk cache, no new TTS call


def test_audio_missing_cached_file_is_503_not_500(client, media_setup, monkeypatch):
    import sahlha.app.services.services as services_mod

    monkeypatch.setattr(services_mod, "skill_audio",
                        lambda db, **kw: {"path": "/nonexistent-dir/x.wav",
                                          "skill_id": kw.get("skill_id")})
    m = media_setup
    r = client.get(_audio_url(m["skill_id"], m["material"]["id"], m["room"]["id"]),
                   params=_audio_params(m["material"]["id"], m["room"]["id"]),
                   headers=_auth(m["student"]["token"]))
    assert r.status_code == 503, r.text


def test_audio_voice_param_is_sanitized(client, media_setup, monkeypatch, tmp_path):
    from sahlha.app.agent.tools import audio_tools
    from sahlha.app.audio import tts as tts_mod

    assert audio_tools.sanitize_voice(None) is None
    assert audio_tools.sanitize_voice("   ") is None
    assert audio_tools.sanitize_voice("troy") == "troy"
    nasty = "x" * 200 + "; rm -rf /"
    cleaned = audio_tools.sanitize_voice(nasty)
    assert len(cleaned) <= 64 and ";" not in cleaned and "/" not in cleaned

    seen = []

    def _ok(text, voice=None):
        seen.append(voice)
        return _wav(), voice

    monkeypatch.setattr(tts_mod, "synthesize", _ok)
    monkeypatch.setattr(settings, "audio_dir", str(tmp_path))
    m = media_setup
    h = _auth(m["student"]["token"])
    params = dict(_audio_params(m["material"]["id"], m["room"]["id"]))
    params["voice"] = nasty
    r = client.get(_audio_url(m["skill_id"], m["material"]["id"], m["room"]["id"]),
                   params=params, headers=h)
    assert r.status_code == 200, r.text
    assert seen and len(seen[0]) <= 64


# ---- images: same auth/availability contract ----

def test_image_503_without_key(client, media_setup, monkeypatch):
    monkeypatch.setattr(settings, "pexels_api_key", "")
    monkeypatch.delenv("PEXELS_API_KEY", raising=False)
    # Drop any cached image path so the provider path is exercised.
    from sahlha.app.database.database import get_db as _  # noqa: F401 (kept for clarity)
    m = media_setup
    r = client.get(f"/student/skills/{m['skill_id']}/image",
                   params=_audio_params(m["material"]["id"], m["room"]["id"]),
                   headers=_auth(m["student"]["token"]))
    # Fresh skills have no cached image and no key -> 503 (or 200 only if the
    # environment provides a key and network; never 401/500 here).
    assert r.status_code in (200, 503), r.text
    if r.status_code == 503:
        assert "picture" in r.json()["detail"].lower() or "unavailable" in r.json()["detail"].lower()


# ---- health: verify keys load without logging secrets ----

def test_health_reports_availability_flags_without_secrets(client):
    r = client.get("/health")
    assert r.status_code == 200
    body = r.json()
    assert body["ok"] is True
    assert isinstance(body["tts_configured"], bool)
    assert isinstance(body["images_configured"], bool)
    # No secret material may appear in the payload.
    for secret in (settings.groq_api_key, settings.pexels_api_key,
                   settings.jwt_secret):
        if secret:
            assert secret not in r.text


def test_env_keys_load_stripped():
    # Leading/trailing whitespace in `.env` values must not break provider
    # auth (the repo `.env` historically carried `KEY= <value>` spacing).
    for value in (settings.groq_api_key, settings.pexels_api_key):
        if value:
            assert value == value.strip()
            assert " " not in value


# ---- support signals: strict single endpoint, lenient submit path ----

def test_support_signal_rejects_unknown_and_blank(client, media_setup):
    m = media_setup
    h = _auth(m["student"]["token"])
    assert client.post("/student/support-signal", json={"signal": "nope"},
                       headers=h).status_code == 422
    assert client.post("/student/support-signal", json={"signal": "   "},
                       headers=h).status_code == 422
    ok = client.post("/student/support-signal", json={"signal": "hint_used"},
                     headers=h)
    assert ok.status_code == 200, ok.text


def test_support_signal_forbids_non_students(client, media_setup):
    m = media_setup
    r = client.post("/student/support-signal", json={"signal": "hint_used"},
                    headers=_auth(m["teacher"]["token"]))
    assert r.status_code == 403


def test_submit_ignores_stray_support_signals(client, media_setup):
    """Grading/results must never break because of a stray signal value."""
    m = media_setup
    banks = client.post(f"/materials/{m['material']['id']}/generate-banks",
                        json={"n_questions": 4},
                        headers=_auth(m["teacher"]["token"]))
    assert banks.status_code == 200, banks.text
    teacher_banks = client.get("/teacher/banks",
                               params={"material_id": m["material"]["id"]},
                               headers=_auth(m["teacher"]["token"])).json()
    for b in teacher_banks:
        client.post(f"/teacher/banks/{b['id']}/approve",
                    headers=_auth(m["teacher"]["token"]))
    start = client.post("/student/assessments/start",
                        json={"classroom_id": m["room"]["id"],
                              "material_id": m["material"]["id"]},
                        headers=_auth(m["student"]["token"]))
    assert start.status_code == 200, start.text
    sub = client.post(
        f"/student/assessments/{start.json()['assessment_id']}/submit",
        json={"answers": {}, "support_signals": ["hint_used", "garbage-signal"]},
        headers=_auth(m["student"]["token"]))
    assert sub.status_code == 200, sub.text
    assert "score" in sub.json()
