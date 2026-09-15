"""Provider fallback: Groq → OpenRouter → deterministic (LLM) and Groq TTS → OpenRouter TTS.

All tests are hermetic — no live API calls (monkeypatched).
"""
import io
import wave

import pytest

from sahlha.app.config import settings


def _make_wav(frames: bytes = b"\x01\x02" * 100) -> bytes:
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(22050)
        w.writeframes(frames)
    return buf.getvalue()


# ---------- LLM ----------

def test_llm_groq_succeeds_openrouter_not_called(monkeypatch):
    from sahlha.app.agent import llm

    monkeypatch.setattr(settings, "groq_api_key", "groq-key")
    monkeypatch.setattr(settings, "openrouter_api_key", "or-key")
    monkeypatch.setattr(settings, "groq_model", "llama-3.3-70b-versatile")
    monkeypatch.setattr(settings, "openrouter_model", "openai/gpt-4o-mini")
    called = {"or": False}

    def fake_groq(s, u, api_key, model):
        return '[{"skill_id":"x","type":"multiple_choice","question":"Q?","options":["a","b","c","d"],"correct_answer":0,"explanation":"e","difficulty":"easy"}]', "groq"

    def fake_or(s, u):
        called["or"] = True
        raise AssertionError("OpenRouter should not be called when Groq succeeds")

    monkeypatch.setattr(llm, "_call_groq", fake_groq)
    monkeypatch.setattr(llm, "_call_openrouter", fake_or)

    out, backend = llm.generate_questions_llm("sys", "user", [{"text": "lesson", "skill_id": "x"}], "x", 1, "")
    assert backend == "groq"
    assert not called["or"]
    assert out[0]["question"] == "Q?"


def test_llm_groq_rate_limit_falls_back_to_openrouter(monkeypatch):
    from sahlha.app.agent import llm

    monkeypatch.setattr(settings, "groq_api_key", "groq-key")
    monkeypatch.setattr(settings, "openrouter_api_key", "or-key")

    def fake_groq(s, u, api_key, model):
        raise RuntimeError("Error code: 429 - Rate limit reached for model")

    def fake_or(s, u):
        return '[{"skill_id":"x","type":"multiple_choice","question":"OR Q?","options":["a","b","c","d"],"correct_answer":1,"explanation":"e","difficulty":"medium"}]', "openrouter"

    monkeypatch.setattr(llm, "_call_groq", fake_groq)
    monkeypatch.setattr(llm, "_call_openrouter", fake_or)

    out, backend = llm.generate_questions_llm("sys", "user", [{"text": "lesson", "skill_id": "x"}], "x", 1, "")
    assert backend == "openrouter"
    assert out[0]["question"] == "OR Q?"


def test_llm_groq_and_openrouter_fail_uses_deterministic(monkeypatch):
    from sahlha.app.agent import llm

    monkeypatch.setattr(settings, "groq_api_key", "groq-key")
    monkeypatch.setattr(settings, "openrouter_api_key", "or-key")

    def fake_groq(s, u, api_key, model):
        raise RuntimeError("Error code: 503 - Service unavailable")

    def fake_or(s, u):
        raise RuntimeError("Error code: 500 - Provider failure")

    monkeypatch.setattr(llm, "_call_groq", fake_groq)
    monkeypatch.setattr(llm, "_call_openrouter", fake_or)

    out, backend = llm.generate_questions_llm("sys", "user", [{"text": "some lesson content here.", "skill_id": "x"}], "x", 2, "")
    assert backend.startswith("fallback")
    assert len(out) == 2


def test_llm_no_openrouter_key_uses_deterministic(monkeypatch):
    from sahlha.app.agent import llm

    monkeypatch.setattr(settings, "groq_api_key", "groq-key")
    monkeypatch.setattr(settings, "openrouter_api_key", "")

    def fake_groq(s, u, api_key, model):
        raise RuntimeError("Error code: 429 - Rate limit")

    monkeypatch.setattr(llm, "_call_groq", fake_groq)
    # Ensure _call_openrouter would fail if called — it shouldn't be
    monkeypatch.setattr(llm, "_call_openrouter", lambda s, u: (_ for _ in ()).throw(AssertionError("should not be called without key")))

    out, backend = llm.generate_questions_llm("sys", "user", [{"text": "content", "skill_id": "x"}], "x", 1, "")
    assert backend.startswith("fallback")


def test_llm_groq_non_retryable_does_not_fallback(monkeypatch):
    from sahlha.app.agent import llm

    monkeypatch.setattr(settings, "groq_api_key", "groq-key")
    monkeypatch.setattr(settings, "openrouter_api_key", "or-key")

    def fake_groq(s, u, api_key, model):
        raise RuntimeError("Error code: 400 - Invalid request: bad json")

    called = {"or": False}

    def fake_or(s, u):
        called["or"] = True
        return "[]", "openrouter"

    monkeypatch.setattr(llm, "_call_groq", fake_groq)
    monkeypatch.setattr(llm, "_call_openrouter", fake_or)

    out, backend = llm.generate_questions_llm("sys", "user", [{"text": "x", "skill_id": "x"}], "x", 1, "")
    # Non-retryable should go straight to deterministic, not OpenRouter
    assert not called["or"]
    assert backend.startswith("fallback")


def test_llm_openrouter_direct_when_no_groq_key(monkeypatch):
    from sahlha.app.agent import llm

    monkeypatch.setattr(settings, "groq_api_key", "")
    monkeypatch.setattr(settings, "openrouter_api_key", "or-key")
    monkeypatch.delenv("GROQ_API_KEY", raising=False)

    def fake_or(s, u):
        return '{"skills": [{"skill_id":"s1","name":"N","description":"D","key_concepts":["a"]}]}', "openrouter"

    monkeypatch.setattr(llm, "_call_openrouter", fake_or)

    # complete_json should use OpenRouter when Groq absent
    data, backend = llm.complete_json("sys", "user")
    assert backend == "openrouter"


# ---------- TTS ----------

def test_tts_groq_succeeds_not_call_openrouter(monkeypatch):
    from sahlha.app.audio import tts

    monkeypatch.setattr(settings, "groq_api_key", "groq-key")
    monkeypatch.setattr(settings, "openrouter_api_key", "or-key")
    wav = _make_wav()

    monkeypatch.setattr(tts, "_synthesize_chunk", lambda text, api_key, model, voice: wav)
    monkeypatch.setattr(tts, "_synthesize_chunk_openrouter", lambda *a, **kw: (_ for _ in ()).throw(AssertionError("should not be called")))

    out, voice = tts.synthesize("hello world", voice="troy")
    assert out == wav


def test_tts_groq_fails_fallback_openrouter(monkeypatch):
    from sahlha.app.audio import tts

    monkeypatch.setattr(settings, "groq_api_key", "groq-key")
    monkeypatch.setattr(settings, "openrouter_api_key", "or-key")
    wav = _make_wav(b"\x03\x04" * 50)

    def fake_groq_chunk(*a, **kw):
        raise RuntimeError("Error code: 429 - Rate limit")

    monkeypatch.setattr(tts, "_synthesize_chunk", fake_groq_chunk)
    monkeypatch.setattr(tts, "_synthesize_chunk_openrouter", lambda text, api_key, model, voice: wav)

    out, voice = tts.synthesize("hello world")
    # Should succeed via OpenRouter (wav path → stitch returns same wav for single chunk)
    assert out == wav


def test_tts_both_fail_raises(monkeypatch):
    from sahlha.app.audio import tts

    monkeypatch.setattr(settings, "groq_api_key", "groq-key")
    monkeypatch.setattr(settings, "openrouter_api_key", "or-key")

    monkeypatch.setattr(tts, "_synthesize_chunk", lambda *a, **kw: (_ for _ in ()).throw(RuntimeError("Error code: 503 - unavailable")))
    monkeypatch.setattr(tts, "_synthesize_chunk_openrouter", lambda *a, **kw: (_ for _ in ()).throw(RuntimeError("Error code: 500 - fail")))

    with pytest.raises(RuntimeError):
        tts.synthesize("hello")


def test_tts_openrouter_direct_when_no_groq(monkeypatch):
    from sahlha.app.audio import tts

    monkeypatch.setattr(settings, "groq_api_key", "")
    monkeypatch.setattr(settings, "openrouter_api_key", "or-key")
    monkeypatch.delenv("GROQ_API_KEY", raising=False)
    wav = _make_wav()

    monkeypatch.setattr(tts, "_synthesize_chunk_openrouter", lambda text, api_key, model, voice: wav)

    out, voice = tts.synthesize("hello")
    assert out == wav
    assert voice == "alloy"  # OpenRouter default
