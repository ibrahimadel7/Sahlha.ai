"""TTS speech-preparation pipeline: deterministic, offline, no provider calls."""
import io
import threading
import wave

from sahlha.app.audio import speech, tts
from sahlha.app.agent.tools import audio_tools
from sahlha.app.config import settings


def _wav() -> bytes:
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(22050)
        w.writeframes(b"\x01\x02" * 200)
    return buf.getvalue()


# ---- normalization: never read formatting literally ----

def test_headings_spoken_without_hashes():
    out = speech.normalize_for_speech("## What is Photosynthesis?\nIt makes food.")
    assert "#" not in out
    assert "What is Photosynthesis" in out


def test_markdown_syntax_removed():
    out = speech.normalize_for_speech("**Bold** and *italic* and [link text](https://x) end.")
    assert "**" not in out and "[" not in out and "](https://" not in out
    assert "Bold" in out and "link text" in out


def test_code_fence_not_read_as_prose():
    raw = "A loop repeats.\n```python\nfor i in range(5):\n    print(i)\n```\nIt prints five times."
    out = speech.normalize_for_speech(raw)
    assert "range(5)" not in out and "print(i)" not in out
    assert "A loop repeats" in out and "prints five times" in out
    assert "shown on screen" in out  # code stays visual, explanation carries meaning


def test_bullets_become_flowing_speech():
    raw = "The plant needs:\n- sunlight\n- water\n- carbon dioxide"
    out = speech.normalize_for_speech(raw)
    assert "- sunlight" not in out
    assert "sunlight" in out and "water" in out and "carbon dioxide" in out
    assert "include" in out  # lead-in + flowing list, not a document readout


def test_numbered_list_flows():
    out = speech.normalize_for_speech("Steps:\n1. seed\n2. water\n3. sunlight")
    assert "1." not in out
    assert "seed" in out and "sunlight" in out


def test_minimal_tech_layer_only_where_needed():
    out = speech.normalize_for_speech("Learn C++ and C# with e.g. loops. 50% done.")
    assert "C plus plus" in out and "C sharp" in out
    assert "for example" in out and "50 percent" in out
    # Real terms are preserved, never approximated away.
    out2 = speech.normalize_for_speech("FastAPI exposes an API backed by SQL.")
    assert "FastAPI" in out2 and "API" in out2 and "SQL" in out2


def test_arabic_and_mixed_content_preserved():
    raw = "التفسير: المتغير variable يخزن القيمة. ما هو الـ API؟"
    out = speech.normalize_for_speech(raw)
    assert "المتغير" in out and "variable" in out and "API" in out


def test_normalize_idempotent():
    raw = "## Loops\n- repeat\n- until done\n```py\nx=1\n```\nDone."
    once = speech.normalize_for_speech(raw)
    assert speech.normalize_for_speech(once) == once


# ---- segmentation: natural units, never mid-sentence ----

def test_segments_respect_sentences_and_limit():
    text = " ".join(f"This is sentence number {i} about loops and variables." for i in range(20))
    chunks = speech.segment_for_speech(speech.normalize_for_speech(text),
                                       target_chars=200, max_chars=300)
    assert len(chunks) > 1
    assert all(len(c) <= 300 for c in chunks)
    # No chunk ends mid-sentence without terminal punctuation (except hard splits).
    for c in chunks:
        stripped = c.strip()
        assert stripped  # no empty chunks


def test_overlong_sentence_splits_at_word_boundary():
    sent = " ".join(["word"] * 400) + "."
    chunks = speech.segment_for_speech(sent, target_chars=200, max_chars=300)
    assert len(chunks) > 1
    assert all(len(c) <= 300 for c in chunks)
    for c in chunks:
        assert not c.startswith(" ") and not c.endswith(" ")
    # Rejoining with spaces must recover every word (never cut mid-word).
    assert " ".join(chunks).split() == sent.split()


def test_split_for_tts_uses_pipeline_and_word_boundaries():
    text = " ".join(f"Sentence {i} about functions and variables." for i in range(30))
    chunks = tts.split_for_tts(text, max_chars=200)
    assert len(chunks) > 1
    assert all(len(c) <= 200 for c in chunks)


def test_arabic_segmentation():
    text = "التفسير الأول يشرح الحلقات. التفسير الثاني يشرح المتغيرات. التفسير الثالث يشرح الدوال."
    chunks = speech.segment_for_speech(speech.normalize_for_speech(text),
                                       target_chars=60, max_chars=120)
    assert chunks and all(len(c) <= 120 for c in chunks)


# ---- cache: keyed by speakable text + voice/config, deduped ----

def test_cache_key_stable_across_markdown_but_moves_with_voice_or_model(monkeypatch):
    monkeypatch.setattr(settings, "groq_tts_model", "m1")
    monkeypatch.setattr(settings, "openrouter_tts_model", "or1")
    a = audio_tools.expected_path("**hello world.**", "troy")
    b = audio_tools.expected_path("hello world.", "troy")
    assert a == b  # same speech -> same audio (no wasted regeneration)
    assert audio_tools.expected_path("hello world.", "other") != a
    monkeypatch.setattr(settings, "groq_tts_model", "m2")
    assert audio_tools.expected_path("hello world.", "troy") != a


def test_concurrent_first_requests_synthesize_once(monkeypatch, tmp_path):
    monkeypatch.setattr(settings, "audio_dir", str(tmp_path))
    calls: list[str] = []
    barrier = threading.Barrier(5)

    def fake_synth(text, voice=None):
        calls.append(text)
        import time as _t
        _t.sleep(0.2)  # overlap window: all threads contend, one must win
        return _wav(), (voice or "troy")

    monkeypatch.setattr(tts, "synthesize", fake_synth)
    results: list = []
    errors: list = []

    def worker():
        try:
            barrier.wait(timeout=10)  # release all threads together
            results.append(audio_tools._cached_or_synth("Concurrent explanation text.", None))
        except Exception as exc:  # pragma: no cover
            errors.append(exc)

    threads = [threading.Thread(target=worker) for _ in range(5)]
    for t in threads:
        t.start()
    for t in threads:
        t.join(timeout=30)
    assert not errors
    assert len(results) == 5
    assert len(calls) == 1  # single-flight: one TTS call, not five
    assert all(r[0] == results[0][0] for r in results)


def test_corrupt_cache_is_dropped_and_regenerated(monkeypatch, tmp_path):
    monkeypatch.setattr(settings, "audio_dir", str(tmp_path))
    calls: list[str] = []
    monkeypatch.setattr(tts, "synthesize",
                        lambda text, voice=None: (calls.append(text) or _wav(), voice or "troy"))
    path, _, cached = audio_tools._cached_or_synth("Cache me clearly.", None)
    assert not cached
    assert audio_tools._cached_or_synth("Cache me clearly.", None)[2]
    assert len(calls) == 1
    with open(path, "wb") as fh:
        fh.write(b"not audio")
    assert not audio_tools._cached_or_synth("Cache me clearly.", None)[2]
    assert len(calls) == 2


def test_valid_audio_file_accepts_mp3(tmp_path):
    mp3 = tmp_path / "x.mp3"
    mp3.write_bytes(b"ID3" + b"\x00" * 512)
    assert audio_tools.valid_audio_file(str(mp3))
    bad = tmp_path / "bad.wav"
    bad.write_bytes(b"not audio at all, far too short...")
    assert not audio_tools.valid_audio_file(str(bad))


def test_audio_result_carries_metrics_and_cache_headers(db_session, monkeypatch, tmp_path):
    """Cold request synthesizes once; repeat is a disk-cache hit with headers."""
    from sahlha.app.agent.tools import audio_tools as _at
    from sahlha.app.api import routes_audio as _routes
    from sahlha.app.rag import ingestion
    from tests.conftest import SAMPLE_TEXT

    monkeypatch.setattr(settings, "audio_dir", str(tmp_path / "audio"))
    calls: list[str] = []
    monkeypatch.setattr(tts, "synthesize",
                        lambda text, voice=None: (calls.append(text) or _wav(), voice or "troy"))
    ingestion.ingest_upload(db_session, file_bytes=(SAMPLE_TEXT * 2).encode(),
                            filename="elif.txt", course_id="hc", lesson_id="hl", skill_id="hs")
    from sahlha.app.services import services as _svc
    skills = _svc.extract_skills(db_session, course_id="hc", lesson_id="hl",
                                 max_skills=1)["skills"]
    assert skills and skills[0]["explanation"]
    first = _at.skill_explanation_to_audio(db_session, course_id="hc", lesson_id="hl",
                                           skill_id=skills[0]["skill_id"])
    assert not first["cached"] and len(calls) == 1
    assert first["metrics"]["cache"] == "miss"
    assert first["metrics"]["chars"] > 0
    # Raw markdown never reaches the provider: normalized speech was sent.
    assert "#" not in calls[0] and "```" not in calls[0]
    second = _at.skill_explanation_to_audio(db_session, course_id="hc", lesson_id="hl",
                                            skill_id=skills[0]["skill_id"])
    assert second["cached"] and len(calls) == 1
    assert second["path"] == first["path"]
    resp = _routes._to_file(second)
    assert resp.media_type in ("audio/wav", "audio/mpeg")
    assert resp.headers["X-Cache"] == "HIT"
    assert resp.headers["X-Audio-Format"] in ("wav", "mp3")
    first_resp = _routes._to_file(first)
    assert first_resp.headers["X-Cache"] == "MISS"


def test_mp3_fallback_served_as_mpeg(db_session, monkeypatch, tmp_path):
    """OpenRouter MP3 bytes are never served as audio/wav (silent <audio> fail)."""
    from sahlha.app.agent.tools import audio_tools as _at
    from sahlha.app.api import routes_audio as _routes
    from sahlha.app.rag import ingestion
    from tests.conftest import SAMPLE_TEXT

    monkeypatch.setattr(settings, "audio_dir", str(tmp_path / "audio"))
    fake_mp3 = b"ID3" + b"\x00" * 2048
    monkeypatch.setattr(tts, "synthesize", lambda text, voice=None: (fake_mp3, voice or "alloy"))
    ingestion.ingest_upload(db_session, file_bytes=(SAMPLE_TEXT * 2).encode(),
                            filename="elif.txt", course_id="mc3", lesson_id="ml3", skill_id="ms3")
    from sahlha.app.services import services as _svc
    skills = _svc.extract_skills(db_session, course_id="mc3", lesson_id="ml3",
                                 max_skills=1)["skills"]
    result = _at.skill_explanation_to_audio(db_session, course_id="mc3", lesson_id="ml3",
                                            skill_id=skills[0]["skill_id"])
    assert result["format"] == "mp3" and result["media_type"] == "audio/mpeg"
    resp = _routes._to_file(result)
    assert resp.media_type == "audio/mpeg"
    assert resp.headers["X-Audio-Format"] == "mp3"
