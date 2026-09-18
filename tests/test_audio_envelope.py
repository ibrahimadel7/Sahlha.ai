"""Lip-sync envelopes: energy follows real loudness, timed pauses at sentences."""
import io
import math
import struct
import wave

from sahlha.app.audio import envelope as env


def _make_wav(frames: bytes, *, nchannels=1, sampwidth=2, framerate=24000) -> bytes:
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(nchannels)
        w.setsampwidth(sampwidth)
        w.setframerate(framerate)
        w.writeframes(frames)
    return buf.getvalue()


def _tone(seconds: float, *, hz: float = 440.0, amp: int = 12000, framerate=24000) -> bytes:
    return b"".join(
        struct.pack("<h", int(amp * math.sin(2 * math.pi * hz * t / framerate)))
        for t in range(int(seconds * framerate))
    )


def test_energy_opens_on_tone_closes_in_silence():
    sr = 24000
    data = _make_wav(_tone(1.0) + b"\x00\x00" * sr + _tone(1.0))
    levels = env.energy_levels_from_wav(data, 30)
    assert len(levels) == 30
    assert all(0.0 <= v <= 1.0 for v in levels)
    assert sum(levels[0:9]) / 9 > 0.5
    assert sum(levels[11:19]) / 9 < 0.15
    assert sum(levels[21:29]) / 9 > 0.5


def test_energy_scales_with_loudness():
    data = _make_wav(_tone(1.0, amp=12000) + _tone(1.0, amp=2000))
    levels = env.energy_levels_from_wav(data, 20)
    loud = sum(levels[0:9]) / 9
    quiet = sum(levels[11:19]) / 9
    assert loud > quiet + 0.2


def test_energy_silence_file_is_closed_mouth():
    levels = env.energy_levels_from_wav(_make_wav(b"\x00\x00" * 2400))
    assert levels == [0.0] * env.ENVELOPE_BUCKETS


def test_energy_rejects_non_wav():
    assert env.energy_levels_from_wav(b"ID3\x04\x00fake mp3 bytes" * 10) is None
    assert env.energy_levels_from_wav(b"") is None
    assert env.energy_levels_from_wav(b"RIFFtooshort") is None


def test_energy_handles_stereo_and_8bit():
    # Stereo tone: interleave two identical channels.
    mono = _tone(0.5)
    samples = struct.unpack("<%dh" % (len(mono) // 2), mono)
    stereo = b"".join(struct.pack("<hh", s, s) for s in samples)
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(24000)
        w.writeframes(stereo)
    levels = env.energy_levels_from_wav(buf.getvalue(), 10)
    assert sum(levels) / len(levels) > 0.5
    buf8 = io.BytesIO()
    with wave.open(buf8, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(1)
        w.setframerate(8000)
        w.writeframes(bytes(128 + int(60 * math.sin(i / 8)) for i in range(8000)))
    assert sum(env.energy_levels_from_wav(buf8.getvalue(), 10)) > 0


def test_timed_pauses_at_sentence_ends():
    levels = env.timed_levels_for_text(
        "Hello world. How are you today? Let us learn fractions together now."
    )
    assert len(levels) == env.ENVELOPE_BUCKETS
    closed = sum(1 for v in levels if v < 0.05) / len(levels)
    assert 0.10 < closed < 0.40
    # Speech spans stay clearly open on average.
    assert sum(levels) / len(levels) > 0.4


def test_timed_empty_text_is_closed():
    assert env.timed_levels_for_text("") == [0.0] * env.ENVELOPE_BUCKETS


def test_levels_for_file_prefers_energy_for_wav(tmp_path):
    wav = tmp_path / "a.wav"
    wav.write_bytes(_make_wav(_tone(0.5)))
    levels, kind = env.levels_for_audio_file(str(wav), "Hello world.")
    assert kind == "energy"
    assert len(levels) == env.ENVELOPE_BUCKETS
    assert sum(levels) / len(levels) > 0.5


def test_levels_for_file_falls_back_to_timed_for_mp3(tmp_path):
    mp3 = tmp_path / "a.mp3"
    mp3.write_bytes(b"\xff\xfb\x90\xc4" + b"\x00" * 4096)
    levels, kind = env.levels_for_audio_file(str(mp3), "Hello world. How are you?")
    assert kind == "timed"
    assert len(levels) == env.ENVELOPE_BUCKETS
    assert any(v < 0.05 for v in levels)  # sentence pause present
    assert any(v > 0.5 for v in levels)  # speech present


def test_payload_roundtrip_validation():
    payload = env.envelope_payload([0.0, 0.5, 1.0] * 100, "energy")
    assert payload["version"] == env.ENVELOPE_VERSION
    assert payload["buckets"] == 300
    assert env.valid_envelope_payload(payload)
    assert not env.valid_envelope_payload({"version": 999, "kind": "energy",
                                           "levels": [0.5] * 300})
    assert not env.valid_envelope_payload({"version": 1, "kind": "energy",
                                           "levels": [0.5] * 5})
    assert not env.valid_envelope_payload({"version": 1, "kind": "energy",
                                           "levels": [2.0] * 300})


class _StubSkill:
    name = "Halves"
    explanation = "One half is one part of two equal parts. Two halves make a whole."


def _seed_cached_wav(monkeypatch, tmp_path):
    """Point the audio dir at tmp and pre-seed the skill's WAV (cache HIT)."""
    from sahlha.app.agent.tools import audio_tools
    from sahlha.app.audio import speech
    from sahlha.app.config import settings

    monkeypatch.setattr(settings, "audio_dir", str(tmp_path))
    monkeypatch.setattr(audio_tools.repo, "get_skill",
                        lambda *args, **kwargs: _StubSkill())
    speech_text = speech.build_skill_speech(_StubSkill.name, _StubSkill.explanation)
    with open(audio_tools.expected_path(speech_text, None, "wav"), "wb") as fh:
        fh.write(_make_wav(_tone(0.5) + b"\x00\x00" * 12000 + _tone(0.5)))
    return audio_tools


def test_skill_envelope_energy_from_cached_audio(monkeypatch, tmp_path, db_session):
    audio_tools = _seed_cached_wav(monkeypatch, tmp_path)
    result = audio_tools.skill_envelope(db_session, course_id="c", lesson_id="l",
                                        skill_id="s")
    assert result["kind"] == "energy"
    assert len(result["levels"]) == env.ENVELOPE_BUCKETS
    assert result["cached"] is False
    # Second call serves the .env.json cache without recomputing.
    again = audio_tools.skill_envelope(db_session, course_id="c", lesson_id="l",
                                       skill_id="s")
    assert again["cached"] is True
    assert again["levels"] == result["levels"]
    assert list(tmp_path.glob("*.env.json")) != []


def test_skill_envelope_missing_skill_is_404(monkeypatch, tmp_path, db_session):
    import pytest as _pytest

    from sahlha.app.agent.tools import audio_tools
    from sahlha.app.config import settings

    monkeypatch.setattr(settings, "audio_dir", str(tmp_path))
    monkeypatch.setattr(audio_tools.repo, "get_skill", lambda *a, **k: None)
    with _pytest.raises(ValueError):
        audio_tools.skill_envelope(db_session, course_id="c", lesson_id="l",
                                   skill_id="nope")
