"""Lesson categories: taxonomy sanity, classification, category-aware queries,
and stored-category passthrough into the existing image tool (mocked HTTP)."""
from sahlha.app.agent.tools import image_tools
from sahlha.app.config import settings
from sahlha.app.database.repositories import repositories as repo
from sahlha.app.images import pexels
from sahlha.app.lesson_categories import (
    _AMBIGUOUS,
    CATEGORIES,
    anchor_for,
    classify_lesson,
    get,
)
from sahlha.app.rag import ingestion

FAKE_JPEG = b"\xff\xd8\xff" + b"\x00" * 2048

CASES = [
    # (lesson_id, lesson text, expected category)
    ("python_programming",
     "Introduction to Python programming, including variables, data types, loops, and functions. "
     "A variable stores a value that a program can use later.",
     "computer_science"),
    ("snakes",
     "Snakes, their habitats, behavior, and ecological role. Pythons are large "
     "constrictor snakes living in tropical habitats.",
     "biology"),
    ("electricity",
     "Electricity, electric charge, current, voltage, and circuits. Electrons are "
     "negatively charged particles that move through conductors. Lamps are one application.",
     "physics"),
    ("cells",
     "Cell structure and the functions of organelles. The mitochondria produce "
     "energy for the cell through respiration.",
     "biology"),
    ("computer_basics",
     "Computer basics: hardware and input devices. The computer mouse is moved "
     "by hand to click icons and drag windows on screen.",
     "computer_science"),
    ("mammals",
     "Small mammals: mice and their habitats. Mice are small rodents that live "
     "in fields and eat seeds.",
     "biology"),
    ("photosynthesis",
     "Photosynthesis in plants. Chlorophyll in chloroplasts captures light energy "
     "to convert water and carbon dioxide into glucose.",
     "biology"),
    ("volcanoes",
     "Volcanoes and plate tectonics. Magma rises through cracks in rock and "
     "eruptions build mountains. Shield and stratovolcanoes.",
     "geography"),
]


def test_taxonomy_is_small_and_structured():
    ids = [c["id"] for c in CATEGORIES]
    assert len(ids) == len(set(ids)) == len(CATEGORIES) <= 12
    for c in CATEGORIES:
        assert c["label"] and isinstance(c["anchor"], str)
        assert isinstance(c["signals"], list)
    assert get("nope")["id"] == "other" and anchor_for("nope") == ""
    assert anchor_for({"category_id": "physics"}) == "physics"
    assert anchor_for({"category_id": "other", "anchor": ""}) == ""


def test_ambiguous_words_are_never_signals():
    for c in CATEGORIES:
        assert not (_AMBIGUOUS & set(c["signals"])), c["id"]


def test_required_lessons_classify_correctly():
    for lesson_id, text, expected in CASES:
        rec = classify_lesson(lesson_id=lesson_id, text=text)
        assert rec["category_id"] == expected, (lesson_id, rec)
        assert rec["label"] and (rec["anchor"] or expected == "other")


def test_same_word_different_lesson_different_category():
    prog = classify_lesson(lesson_id="python_programming", text=CASES[0][1])
    snake = classify_lesson(lesson_id="snakes", text=CASES[1][1])
    assert prog["category_id"] == "computer_science"
    assert snake["category_id"] == "biology"
    cmouse = classify_lesson(lesson_id="computer_basics", text=CASES[4][1])
    amouse = classify_lesson(lesson_id="mammals", text=CASES[5][1])
    assert cmouse["category_id"] == "computer_science"
    assert amouse["category_id"] == "biology"


def test_category_anchor_guards_query_but_skill_stays_subject():
    q = pexels.build_image_query({
        "name": "The mitochondria produce energy for the cell.",
        "skill_id": "m", "key_concepts": ["mitochondria", "organelles"],
        "lesson_category": {"category_id": "biology", "label": "Biology", "anchor": "biology"},
        "lesson_title": "Cell structure and the functions of organelles",
        "lesson_key_concepts": ["cell structure", "organelles"]})
    assert "mitochondria" in q.split()[0].lower() or q.lower().startswith("mitochondria")
    assert "biology" in q.lower()
    assert "power plant" not in q.lower() and "battery" not in q.lower()

    q = pexels.build_image_query({
        "name": "Variables store values that programs can use.",
        "skill_id": "v", "key_concepts": ["variables", "data types"],
        "lesson_category": "computer_science",
        "lesson_title": "Introduction to Python programming"})
    assert "programming" in q.lower() and "snake" not in q.lower()

    # Legacy callers without any category still work.
    q = pexels.build_image_query({"name": "Elif Branches (cond_lesson)",
                                  "skill_id": "cond_lesson__elif",
                                  "key_concepts": ["elif keyword", "conditions", "branching"]})
    assert "Elif" in q and "elif keyword" in q


def _seed(db_session, *, cid, lid, text, title, concepts, skill_id, name):
    ingestion.ingest_upload(db_session, file_bytes=text.encode(), filename=f"{lid}.txt",
                            course_id=cid, lesson_id=lid, skill_id="general", eager=False)
    repo.upsert_lesson_explanation(db_session, course_id=cid, lesson_id=lid,
                                   title=title, explanation=text,
                                   key_concepts=concepts)
    repo.upsert_skill(db_session, course_id=cid, lesson_id=lid, skill_id=skill_id,
                      name=name, description=name, key_concepts=[name.split()[0]],
                      learning_objective=name)
    sk = repo.get_skill(db_session, course_id=cid, lesson_id=lid, skill_id=skill_id)
    repo.set_skill_explanation(db_session, sk, name)


class _FakeResp:
    def __init__(self, *, json_data=None, content=b"", ctype="image/jpeg", status=200):
        self._json = json_data or {}
        self.content = content
        self.headers = {"content-type": ctype}
        self.status_code = status

    def json(self):
        return self._json

    def raise_for_status(self):
        if self.status_code >= 400:
            raise RuntimeError(f"http {self.status_code}")


def test_tool_uses_stored_category_without_recomputing(db_session, monkeypatch, tmp_path):
    monkeypatch.setattr(settings, "pexels_api_key", "test-key")
    monkeypatch.setattr(settings, "image_dir", str(tmp_path))
    _seed(db_session, cid="cc", lid="electricity", text=CASES[2][1],
          title="Electricity", concepts=["charge", "current"],
          skill_id="electricity__electrons", name="Electrons flow through conductors.")
    repo.upsert_lesson_explanation(db_session, course_id="cc", lesson_id="electricity",
                                   category="physics")
    seen = {}
    real_build = pexels.build_image_query
    monkeypatch.setattr(pexels, "build_image_query",
                        lambda ctx: (seen.update(ctx), real_build(ctx))[1])
    import requests
    queries = []

    def _fake(url, **kw):
        if "api.pexels.com" in url:
            queries.append((kw.get("params") or {}).get("query", ""))
            return _FakeResp(json_data={"photos": [{
                "url": "https://pexels.com/photo/1", "alt": "electric plug",
                "photographer": "P", "src": {"large": "https://images.pexels.com/1.jpg"}}]})
        return _FakeResp(content=FAKE_JPEG)
    monkeypatch.setattr(requests, "get", _fake)

    res = image_tools.fetch_skill_image(db_session, course_id="cc", lesson_id="electricity",
                                        skill_id="electricity__electrons", force=True)
    assert seen["lesson_category"]["category_id"] == "physics"
    assert "physics" in res["query"].lower()
    assert queries and queries[0] == res["query"]
    assert "lamp" not in res["query"].lower()


def test_tool_falls_back_for_legacy_row_without_category(db_session, monkeypatch, tmp_path):
    monkeypatch.setattr(settings, "pexels_api_key", "test-key")
    monkeypatch.setattr(settings, "image_dir", str(tmp_path))
    _seed(db_session, cid="cc", lid="snakes", text=CASES[1][1],
          title="Snakes", concepts=["habitats"],
          skill_id="snakes__pythons", name="Pythons are large constrictor snakes.")
    # Simulate a legacy row: category column emptied after creation.
    row = repo.get_lesson_explanation(db_session, course_id="cc", lesson_id="snakes")
    row.category = ""
    db_session.commit()
    import requests

    def _fake(url, **kw):
        if "api.pexels.com" in url:
            return _FakeResp(json_data={"photos": [{
                "url": "https://pexels.com/photo/1", "alt": "python snake",
                "photographer": "P", "src": {"large": "https://images.pexels.com/1.jpg"}}]})
        return _FakeResp(content=FAKE_JPEG)
    monkeypatch.setattr(requests, "get", _fake)
    res = image_tools.fetch_skill_image(db_session, course_id="cc", lesson_id="snakes",
                                        skill_id="snakes__pythons", force=True)
    assert "snake" in res["query"].lower() and "programming" not in res["query"].lower()
    # Fallback persists the category so the next skill reads the stored value.
    row2 = repo.get_lesson_explanation(db_session, course_id="cc", lesson_id="snakes")
    assert (row2.category or "") == "biology"


def test_agent_persists_category_at_extraction(db_session):
    ingestion.ingest_upload(db_session, file_bytes=CASES[0][1].encode(),
                            filename="python.txt", course_id="ac", lesson_id="python_programming",
                            skill_id="general", eager=False)
    from sahlha.app.agent.agent import SahlhaAgent
    from sahlha.app.agent.state import AgentState

    out = SahlhaAgent(db_session, AgentState()).extract_skills(
        course_id="ac", lesson_id="python_programming", max_skills=2, force=True)
    assert out["skills"]
    row = repo.get_lesson_explanation(db_session, course_id="ac", lesson_id="python_programming")
    assert row is not None and (row.category or "") == "computer_science"
    assert any(e.get("event") == "lesson:classify"
               and (e.get("detail") or {}).get("category") == "computer_science"
               for e in out["trace"])
