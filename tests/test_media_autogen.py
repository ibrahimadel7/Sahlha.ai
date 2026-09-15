"""Explanation call auto-produces image + audio (mocked providers; graceful skip w/o keys)."""
import os

from sahlha.app.agent.agent import SahlhaAgent
from sahlha.app.agent.state import AgentState
from sahlha.app.audio import tts
from sahlha.app.config import settings
from sahlha.app.images import pexels
from sahlha.app.rag import ingestion
from sahlha.app.services import services as svc
from tests.conftest import SAMPLE_TEXT

FAKE_WAV = b"RIFF" + b"\x00" * 2048
FAKE_JPEG = b"\xff\xd8\xff" + b"\x00" * 2048


def _seed(db_session):
    ingestion.ingest_upload(db_session, file_bytes=(SAMPLE_TEXT * 2).encode(),
                            filename="elif.txt", course_id="mc", lesson_id="ml", skill_id="ms")


def _mock_media(monkeypatch, tmp_path):
    monkeypatch.setattr(settings, "audio_dir", str(tmp_path / "audio"))
    monkeypatch.setattr(settings, "image_dir", str(tmp_path / "images"))
    monkeypatch.setattr(settings, "groq_api_key", "test-key")
    monkeypatch.setattr(settings, "pexels_api_key", "test-key")
    monkeypatch.setattr(tts, "synthesize", lambda text, voice=None: (FAKE_WAV, voice or "v"))
    monkeypatch.setattr(pexels, "fetch_related_image",
                        lambda query: {"bytes": FAKE_JPEG, "page_url": "https://pexels.com/p/1",
                                       "alt": "alt", "photographer": "P"})


def test_explain_skills_autogenerates_media(db_session, monkeypatch, tmp_path):
    _mock_media(monkeypatch, tmp_path)
    _seed(db_session)
    agent = SahlhaAgent(db_session, AgentState())
    agent.extract_skills(course_id="mc", lesson_id="ml", max_skills=2)
    out = agent.explain_skills(course_id="mc", lesson_id="ml")
    assert out["skills"], "expected skills"
    for s in out["skills"]:
        assert s["explanation"]
        assert s["media"]["image"]["status"] == "generated", s["media"]
        assert s["media"]["audio"]["status"] == "generated", s["media"]
    imgs = os.listdir(tmp_path / "images")
    auds = os.listdir(tmp_path / "audio")
    assert len(imgs) == len(out["skills"]) and all(f.endswith(".jpg") for f in imgs)
    assert len(auds) == len(out["skills"]) and all(f.endswith(".wav") for f in auds)
    listed = svc.list_skills(db_session, course_id="mc", lesson_id="ml")
    assert all(s["has_image"] and s["has_audio"] for s in listed)


def test_explain_skills_survives_without_keys(db_session, monkeypatch):
    _seed(db_session)
    monkeypatch.setattr(settings, "groq_api_key", "")
    monkeypatch.setattr(settings, "pexels_api_key", "")
    monkeypatch.delenv("GROQ_API_KEY", raising=False)
    monkeypatch.delenv("PEXELS_API_KEY", raising=False)
    out = svc.extract_skills(db_session, course_id="mc", lesson_id="ml", max_skills=2)
    for s in out["skills"]:
        assert s["explanation"], "explanation must succeed without media keys"
        assert s["media"]["image"]["status"] == "skipped"
        assert s["media"]["audio"]["status"] == "skipped"
    assert out["lesson"]["explanation"]
    assert out["lesson"]["media"]["audio"]["status"] == "skipped"


def test_explain_lesson_autogenerates_audio(db_session, monkeypatch, tmp_path):
    _mock_media(monkeypatch, tmp_path)
    _seed(db_session)
    out = svc.explain_lesson(db_session, course_id="mc", lesson_id="ml")
    assert out["lesson"]["explanation"]
    assert out["lesson"]["media"]["audio"]["status"] == "generated"
    assert os.listdir(tmp_path / "audio"), "lesson wav must be written"


def test_tool_chain_skill_explains_then_media(db_session, monkeypatch, tmp_path):
    """skill tool -> explanation tool -> audio/image tools, in that order."""
    _mock_media(monkeypatch, tmp_path)
    _seed(db_session)
    from sahlha.app.agent.tools import audio_tools, explanation_tools, image_tools, skill_tools

    calls: list[str] = []
    real_explain = explanation_tools.explain_skill
    real_audio = audio_tools.skill_explanation_to_audio
    real_image = image_tools.fetch_skill_image

    def spy_explain(*a, **k):
        calls.append("explanation")
        return real_explain(*a, **k)

    def spy_audio(*a, **k):
        calls.append("audio")
        return real_audio(*a, **k)

    def spy_image(*a, **k):
        calls.append("image")
        return real_image(*a, **k)

    monkeypatch.setattr(explanation_tools, "explain_skill", spy_explain)
    monkeypatch.setattr(audio_tools, "skill_explanation_to_audio", spy_audio)
    monkeypatch.setattr(image_tools, "fetch_skill_image", spy_image)

    agent = SahlhaAgent(db_session, AgentState())
    skills = agent.extract_skills(course_id="mc", lesson_id="ml", max_skills=1)["skills"]
    bundle = skill_tools.setup_skill(db_session, course_id="mc", lesson_id="ml",
                                     skill_id=skills[0]["skill_id"],
                                     explanation_text="Mocked explanation text for chain.")
    assert bundle["explanation"] == "Mocked explanation text for chain."
    assert bundle["media"]["image"]["status"] == "generated"
    assert bundle["media"]["audio"]["status"] == "generated"
    assert calls[0] == "explanation", "skill tool must call explanation first"
    assert sorted(calls[1:]) == ["audio", "image"], "explanation must fan out to media tools"
