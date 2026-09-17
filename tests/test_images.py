"""Images: query building offline; fetch cached; endpoints degrade without a key."""
import pytest

from sahlha.app.agent.tools import image_tools
from sahlha.app.config import settings
from sahlha.app.images import pexels
from sahlha.app.rag import ingestion
from tests.conftest import SAMPLE_TEXT

FAKE_JPEG = b"\xff\xd8\xff" + b"\x00" * 2048


def test_build_image_query_from_skill_context():
    q = pexels.build_image_query({"name": "Elif Branches (cond_lesson)",
                                  "skill_id": "cond_lesson__elif",
                                  "key_concepts": ["elif keyword", "conditions", "branching"]})
    # Category-aware builder: skill stays subject, "(lesson)" suffix stripped.
    assert "Elif" in q and "elif keyword" in q
    assert "(" not in q  # "(cond_lesson)" suffix stripped
    assert pexels.build_image_query({"name": "", "skill_id": "x", "key_concepts": []}) == "x"
    # Code disambiguation comes from lesson category, not bare keywords:
    qc = pexels.build_image_query({"name": "Elif Branches",
                                   "skill_id": "c",
                                   "key_concepts": ["elif keyword"],
                                   "lesson_category": "computer_science",
                                   "lesson_title": "Python programming"})
    assert "programming" in qc.lower()


def _seed_skill(db_session, **kw):
    ingestion.ingest_upload(db_session, file_bytes=SAMPLE_TEXT.encode(), filename="elif.txt",
                            course_id="ic", lesson_id="il", skill_id="isk")
    from sahlha.app.services import services as svc

    skills = svc.extract_skills(db_session, course_id="ic", lesson_id="il", max_skills=1,
                                **kw)["skills"]
    return skills[0]["skill_id"]


class _FakeResp:
    def __init__(self, *, json_data=None, content=b"", content_type="image/jpeg", status=200):
        self._json = json_data or {}
        self.content = content
        self.headers = {"content-type": content_type}
        self.status_code = status

    def json(self):
        return self._json

    def raise_for_status(self):
        if self.status_code >= 400:
            raise RuntimeError(f"http {self.status_code}")


def _fake_get_factory(calls: list):
    def _fake(url, **kwargs):
        calls.append(url)
        if "api.pexels.com" in url:
            return _FakeResp(json_data={"photos": [{
                "url": "https://pexels.com/photo/1", "alt": "python code",
                "photographer": "P", "src": {"large": "https://images.pexels.com/1.jpg"}}]})
        return _FakeResp(content=FAKE_JPEG)
    return _fake


def test_fetch_skill_image_caches(db_session, monkeypatch, tmp_path):
    monkeypatch.setattr(settings, "pexels_api_key", "test-key")
    monkeypatch.setattr(settings, "image_dir", str(tmp_path))
    import requests

    calls: list = []
    monkeypatch.setattr(requests, "get", _fake_get_factory(calls))
    # Seeding with include_media=True auto-generates the image during extraction (2 calls).
    # (Default extract-skills defers media to lazy on-demand generation.)
    skid = _seed_skill(db_session, include_media=True)
    assert len(calls) == 2
    first = image_tools.fetch_skill_image(db_session, course_id="ic", lesson_id="il", skill_id=skid)
    assert first["cached"] is True, "auto-generated during extraction; must hit cache"
    assert len(calls) == 2, "cached call must not hit the network"
    import os

    assert os.path.exists(first["path"])
    forced = image_tools.fetch_skill_image(db_session, course_id="ic", lesson_id="il",
                                           skill_id=skid, force=True)
    assert forced["cached"] is False and os.path.exists(forced["path"])
    assert len(calls) == 4


def test_fetch_skill_image_no_results(db_session, monkeypatch):
    monkeypatch.setattr(settings, "pexels_api_key", "test-key")
    import requests

    monkeypatch.setattr(requests, "get", lambda url, **k: _FakeResp(json_data={"photos": []}))
    skid = _seed_skill(db_session)
    with pytest.raises(ValueError, match="No Pexels images"):
        image_tools.fetch_skill_image(db_session, course_id="ic", lesson_id="il", skill_id=skid)


def test_image_endpoint_degrades(client, monkeypatch):
    from tests.conftest import SAMPLE_TEXT as ST

    client.post("/documents/upload", files={"file": ("elif.txt", ST * 2)},
                data={"course_id": "jc", "lesson_id": "jl", "skill_id": "js"})
    skills = client.post("/agent/extract-skills",
                         json={"course_id": "jc", "lesson_id": "jl", "max_skills": 1}).json()["skills"]
    skid = skills[0]["skill_id"]
    monkeypatch.setattr(settings, "pexels_api_key", "")
    monkeypatch.delenv("PEXELS_API_KEY", raising=False)
    r = client.get("/images/skill", params={"course_id": "jc", "lesson_id": "jl", "skill_id": skid})
    assert r.status_code == 503, r.text
    missing = client.get("/images/skill", params={"course_id": "jc", "lesson_id": "jl",
                                                  "skill_id": "nope"})
    assert missing.status_code == 404


def test_image_endpoint_serves_file(client, monkeypatch, tmp_path):
    from tests.conftest import SAMPLE_TEXT as ST

    monkeypatch.setattr(settings, "pexels_api_key", "test-key")
    monkeypatch.setattr(settings, "image_dir", str(tmp_path))
    import requests

    monkeypatch.setattr(requests, "get", _fake_get_factory([]))
    client.post("/documents/upload", files={"file": ("elif.txt", ST * 2)},
                data={"course_id": "kc", "lesson_id": "kl", "skill_id": "ks"})
    skills = client.post("/agent/extract-skills",
                         json={"course_id": "kc", "lesson_id": "kl", "max_skills": 1}).json()["skills"]
    r = client.get("/images/skill", params={"course_id": "kc", "lesson_id": "kl",
                                            "skill_id": skills[0]["skill_id"]})
    assert r.status_code == 200, r.text
    assert r.headers["content-type"] == "image/jpeg"
    assert r.content[:3] == b"\xff\xd8\xff"
