"""Groq text-to-speech provider (Orpheus English voices) + OpenRouter fallback.

Interface: `synthesize(text, voice=None) -> (bytes, voice_used)`.
Text is first run through the deterministic speech pipeline
(`audio/speech.py`: normalization + natural segmentation) so raw markdown,
code and lists are never read aloud literally. Long text is segmented into
natural speech units and stitched. Swappable behind this module.
"""
from __future__ import annotations

import io
import os
import time
import wave


def tts_available() -> bool:
    try:
        from sahlha.app.config import settings
        groq_key = settings.groq_api_key or os.getenv("GROQ_API_KEY", "")
        or_key = settings.openrouter_api_key or os.getenv("OPENROUTER_API_KEY", "")
    except Exception:
        groq_key = os.getenv("GROQ_API_KEY", "")
        or_key = os.getenv("OPENROUTER_API_KEY", "")
    return bool(groq_key or or_key)


def _get_openrouter_tts_key() -> str:
    try:
        from sahlha.app.config import settings
        return settings.openrouter_api_key or os.getenv("OPENROUTER_API_KEY", "")
    except Exception:
        return os.getenv("OPENROUTER_API_KEY", "")


def _is_retryable_tts_error(exc: Exception) -> bool:
    msg = str(exc).lower()
    status = getattr(exc, "status_code", None)
    if status is None and hasattr(exc, "response") and getattr(exc, "response", None) is not None:
        status = getattr(exc.response, "status_code", None)
    if status is None:
        import re as _re2
        m = _re2.search(r"error code:\s*(\d+)", msg)
        if m:
            try:
                status = int(m.group(1))
            except Exception:
                pass
    if status is not None:
        if status == 429 or 500 <= status <= 599:
            return True
        if 400 <= status < 500 and status != 408:
            return False
    retry_phrases = ["rate limit", "quota", "exhausted", "overloaded", "unavailable", "timeout", "timed out", "connection", "429", "5xx"]
    if any(p in msg for p in retry_phrases):
        if "invalid api key" in msg or "unauthorized" in msg:
            return False
        return True
    return False


def _is_wav(data: bytes) -> bool:
    return data.startswith(b"RIFF")


def sniff_audio_format(data: bytes) -> str:
    """Detect actual audio container from magic bytes (not extension/MIME).

    Returns "wav", "mp3" or "unknown". Groq returns WAV, OpenRouter returns MP3
    (or PCM converted to WAV), so callers must sniff instead of assuming WAV.
    """
    if not data or len(data) < 4:
        return "unknown"
    if data.startswith(b"RIFF"):
        return "wav"
    if data.startswith(b"ID3"):
        return "mp3"
    if len(data) >= 2 and data[0] == 0xFF and (data[1] & 0xE0) == 0xE0:
        return "mp3"
    return "unknown"


def audio_mime_for_bytes(data: bytes) -> str:
    """MIME type matching the actual bytes (for FileResponse / blob playback)."""
    return "audio/mpeg" if sniff_audio_format(data) == "mp3" else "audio/wav"


def normalize_wav(data: bytes) -> bytes:
    """Rewrite a WAV with a clean header.

    Groq streams WAVs with placeholder RIFF sizes (nframes=2**31-1), which makes
    browsers show a broken duration and refuse to play single-chunk audio.
    Re-encoding through the wave module fixes the header without touching PCM.
    Non-WAV input raises ValueError; unparseable WAV is returned as-is.
    """
    if not _is_wav(data):
        raise ValueError("not a WAV file")
    try:
        with wave.open(io.BytesIO(data), "rb") as r:
            nchannels = r.getnchannels()
            sampwidth = r.getsampwidth()
            framerate = r.getframerate()
            # getnframes() may be a streaming placeholder (2**31-1); readframes
            # returns whatever bytes are actually present.
            frames = r.readframes(r.getnframes())
    except Exception:
        return data
    if not frames:
        return data
    out = io.BytesIO()
    with wave.open(out, "wb") as w:
        w.setnchannels(nchannels)
        w.setsampwidth(sampwidth)
        w.setframerate(framerate)
        w.writeframes(frames)
    return out.getvalue()


def is_broken_wav(data: bytes) -> bool:
    """True when a WAV header carries placeholder sizes (needs normalize_wav)."""
    if not _is_wav(data):
        return False
    try:
        with wave.open(io.BytesIO(data), "rb") as r:
            nframes = r.getnframes()
            # Placeholder sentinels observed from streaming TTS providers.
            if nframes >= 2**30:
                return True
            # Cross-check header frame count against actual byte length.
            expected = len(data) - 44
            actual_frames = nframes * r.getnchannels() * r.getsampwidth()
            if abs(actual_frames - expected) > max(1024, expected // 10):
                return True
    except Exception:
        return True
    return False


def valid_wav(data: bytes) -> bool:
    """Platform compat: True when bytes are a playable non-broken WAV."""
    try:
        return _is_wav(data) and not is_broken_wav(data)
    except Exception:
        return False


def retryable_provider_error(exc: Exception) -> bool:
    """Platform compat alias."""
    return _is_retryable_tts_error(exc)


def _pcm_to_wav(pcm: bytes, framerate: int = 24000, nchannels: int = 1, sampwidth: int = 2) -> bytes:
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(nchannels)
        w.setsampwidth(sampwidth)
        w.setframerate(framerate)
        w.writeframes(pcm)
    return buf.getvalue()


def _openrouter_sample_rate() -> int:
    """Configured PCM sample rate (Hz) for wrapping raw OpenRouter PCM as WAV.

    Fish Audio (the default OpenRouter TTS model) returns 44100 Hz PCM by
    default; OpenAI TTS returns 24000 Hz. Wrapping 44100 Hz bytes with a
    24000 Hz header plays back at ~0.54x speed — deep and slow. The setting
    (OPENROUTER_TTS_SAMPLE_RATE) must match the provider's actual rate.
    """
    try:
        from sahlha.app.config import settings as _s

        raw = os.getenv("OPENROUTER_TTS_SAMPLE_RATE", str(_s.openrouter_tts_sample_rate))
        rate = int(str(raw).strip() or "44100")
    except Exception:
        rate = 44100
    if rate < 8000 or rate > 48000:
        rate = 44100
    return rate


def _parse_pcm_rate(content_type: str | None) -> int | None:
    """Parse `rate=` from an `audio/pcm;rate=44100;channels=1` Content-Type.

    OpenRouter returns the true PCM rate in the response header — the only
    reliable source when models differ (Fish 44100 vs OpenAI 24000).
    """
    if not content_type:
        return None
    try:
        import re as _re

        m = _re.search(r"rate\s*=\s*(\d+)", content_type)
        if m:
            rate = int(m.group(1))
            if 8000 <= rate <= 48000:
                return rate
    except Exception:
        pass
    return None


def _response_content_type(resp) -> str | None:
    """Best-effort Content-Type from an OpenAI SDK binary response."""
    try:
        r = getattr(resp, "response", None)
        headers = getattr(r, "headers", None) if r is not None else getattr(resp, "headers", None)
        if headers:
            try:
                return headers.get("content-type")
            except Exception:
                try:
                    return headers.get("Content-Type")
                except Exception:
                    return None
    except Exception:
        pass
    return None


def split_for_tts(text: str, max_chars: int = 900) -> list[str]:
    """Sentence-aware splitter (pure — unit tested).

    Delegates to the speech pipeline so chunk boundaries are natural speech
    units (paragraph → sentences). Overlong single sentences split at word
    boundaries, never mid-word. Keeps the legacy signature for callers/tests.
    """
    from sahlha.app.audio import speech as _speech

    try:
        from sahlha.app.config import settings as _settings

        target = int(getattr(_settings, "tts_target_chars", 550) or 550)
    except Exception:
        target = 550
    normalized = _speech.normalize_for_speech(text)
    if not normalized:
        normalized = (text or "").strip()
    if not normalized:
        return [text[:max_chars]]
    try:
        return _speech.segment_for_speech(
            normalized, target_chars=min(target, max_chars), max_chars=max_chars
        )
    except Exception:
        # Never break synthesis because of segmentation: legacy packing.
        from sahlha.app.rag.text import split_sentences

        sentences = split_sentences(normalized)
        chunks, current = [], ""
        for s in sentences:
            if len(s) > max_chars:
                if current:
                    chunks.append(current)
                    current = ""
                # Word-boundary hard split (never mid-word).
                words, buf = s.split(), ""
                for w in words:
                    cand = f"{buf} {w}".strip()
                    if len(cand) > max_chars and buf:
                        chunks.append(buf)
                        buf = w
                    else:
                        buf = cand
                if buf:
                    chunks.append(buf)
            elif len(current) + len(s) + 1 <= max_chars:
                current = f"{current} {s}".strip()
            else:
                chunks.append(current)
                current = s
        if current:
            chunks.append(current)
        return chunks or [normalized[:max_chars]]


def stitch_wavs(wavs: list[bytes]) -> bytes:
    """Concatenate WAV blobs with identical params into one WAV (pure — unit tested).

    Single-chunk input is normalized (clean RIFF header) so short explanations
    play in browsers — Groq streams placeholder sizes otherwise.
    """
    if len(wavs) == 1:
        only = wavs[0]
        if _is_wav(only):
            try:
                return normalize_wav(only)
            except Exception:
                return only
        return only
    readers = [wave.open(io.BytesIO(w), "rb") for w in wavs]
    params = readers[0].getparams()
    for r in readers[1:]:
        if (r.getnchannels(), r.getsampwidth(), r.getframerate()) != \
           (params.nchannels, params.sampwidth, params.framerate):
            raise ValueError("TTS chunks have mismatched audio params; cannot stitch")
    out = io.BytesIO()
    with wave.open(out, "wb") as w:
        w.setnchannels(params.nchannels)
        w.setsampwidth(params.sampwidth)
        w.setframerate(params.framerate)
        for r in readers:
            w.writeframes(r.readframes(r.getnframes()))
    return out.getvalue()


def _tts_speed(which: str) -> float:
    """Provider-level speech rate (no text hacks). Calm default 1.0."""
    try:
        from sahlha.app.config import settings as _s

        raw = _s.groq_tts_speed if which == "groq" else _s.openrouter_tts_speed
        speed = float(raw or 1.0)
    except Exception:
        speed = 1.0
    return min(4.0, max(0.25, speed))


def _synthesize_chunk(text: str, *, api_key: str, model: str, voice: str) -> bytes:
    from groq import Groq

    # Explicit timeout: fail fast to the OpenRouter backup instead of hanging.
    # max_retries=0: don't burn time on SDK-internal backoff when throttled.
    client = Groq(api_key=api_key, timeout=30, max_retries=0)
    kwargs: dict = dict(model=model, voice=voice, input=text,
                        response_format="wav")
    # Groq supports provider-level speed (0.25-4.0); calm default from settings.
    try:
        kwargs["speed"] = _tts_speed("groq")
    except Exception:
        pass
    resp = client.audio.speech.create(**kwargs)
    # Groq SDK returns HttpxBinaryResponseContent with .read()
    if hasattr(resp, "read"):
        data = resp.read()
    elif hasattr(resp, "content"):
        data = resp.content  # type: ignore[attr-defined]
    else:
        data = bytes(resp)  # fallback
    if not data:
        raise RuntimeError("Groq TTS returned empty audio")
    return data


def _openrouter_candidates(model: str) -> list[str]:
    """Configured model + at most one documented fallback (bounded cost)."""
    candidates = [model]
    # Single documented fallback; voxtral kept out to bound worst-case calls.
    # A second fallback doubles per-chunk cost without evidence it helps.
    fallback = "openai/gpt-4o-mini-tts-2025-12-15"
    if fallback != model:
        candidates.append(fallback)
    return candidates


def _openrouter_format_order() -> tuple[str, ...]:
    """Configured container first (default mp3 — self-describing rate).

    MP3 carries its own sample rate so it always plays at normal speed.
    Raw PCM has no header: wrapping it with the wrong rate plays deep+slow
    (Fish 44100 Hz labeled as 24000 Hz = 0.54x). Prefer MP3 unless the
    operator explicitly opts into PCM with a matching OPENROUTER_TTS_SAMPLE_RATE.
    """
    try:
        from sahlha.app.config import settings as _s

        preferred = (os.getenv("OPENROUTER_TTS_FORMAT", _s.openrouter_tts_format) or "mp3").lower()
    except Exception:
        preferred = "mp3"
    if preferred == "pcm":
        return ("pcm", "mp3")
    return ("mp3", "pcm")


def _synthesize_chunk_openrouter(text: str, *, api_key: str, model: str, voice: str) -> bytes:
    from openai import OpenAI

    from sahlha.app.config import settings as _s

    base_url = os.getenv("OPENROUTER_BASE_URL", _s.openrouter_base_url)
    client = OpenAI(api_key=api_key, base_url=base_url, timeout=30, max_retries=0)
    # OpenRouter TTS per docs: response_format only mp3|pcm (wav is invalid → ZodError).
    # Bounded: configured model + one fallback; configured format first
    # (default mp3 — plays at normal speed everywhere; pcm only when the
    # operator matches OPENROUTER_TTS_SAMPLE_RATE to the provider).
    # Max 4 calls per chunk, no retry loops.
    candidates = _openrouter_candidates(model)
    last_exc: Exception | None = None
    for cand in candidates:
        for fmt in _openrouter_format_order():
            try:
                kwargs: dict = dict(model=cand, voice=voice, input=text, response_format=fmt)
                try:
                    kwargs["speed"] = _tts_speed("openrouter")
                except Exception:
                    pass
                resp = client.audio.speech.create(**kwargs)
                if hasattr(resp, "read"):
                    data = resp.read()
                elif hasattr(resp, "content"):
                    data = resp.content  # type: ignore[attr-defined]
                else:
                    data = bytes(resp)
                if data:
                    # Normalize pcm → wav for consistent stitching. The true
                    # rate comes from the response Content-Type
                    # (audio/pcm;rate=44100) when present, else the configured
                    # OPENROUTER_TTS_SAMPLE_RATE. Never hardcode 24000: Fish
                    # PCM at 44100 wrapped as 24000 plays deep + slow.
                    if fmt == "pcm" and not data.startswith(b"RIFF"):
                        rate = _parse_pcm_rate(_response_content_type(resp)) or _openrouter_sample_rate()
                        return _pcm_to_wav(data, framerate=rate)
                    return data
            except Exception as exc:
                last_exc = exc
                # If model does not exist (400) try next candidate; for rate-limit/5xx bubble up
                msg = str(exc).lower()
                if "does not exist" in msg or "provider returned 404" in msg:
                    break  # try next model
                continue
        # if we broke due to model not exist, continue to next candidate
        if last_exc and "does not exist" in str(last_exc).lower():
            continue
    raise RuntimeError(f"OpenRouter TTS failed for all formats/models: {last_exc}")


# Back-compat alias: older tests patch/call `_openrouter_chunk(text, voice?)`.
# Keeps working with legacy positional (text, voice) by filling api_key/model
# from settings, and honors the configured format order (pcm default).
def _openrouter_chunk(text: str, voice: str | None = None, *args,
                      api_key: str | None = None, model: str | None = None,
                      **kwargs) -> bytes:
    from sahlha.app.config import settings as _s

    # Legacy positional second arg may be the voice ("alloy").
    if args and voice is None and isinstance(args[0], str):
        voice = args[0]
    resolved_voice = voice or os.getenv("OPENROUTER_TTS_VOICE", _s.openrouter_tts_voice)
    resolved_model = model or os.getenv("OPENROUTER_TTS_MODEL", _s.openrouter_tts_model)
    resolved_key = api_key or _get_openrouter_tts_key() or "test-key"
    return _synthesize_chunk_openrouter(text, api_key=resolved_key,
                                        model=resolved_model, voice=resolved_voice)


def _prepare_speech_text(text: str) -> tuple[str, float]:
    """Normalize raw explanation -> speakable text + prepare latency (ms)."""
    from sahlha.app.audio import speech as _speech

    start = time.perf_counter()
    try:
        normalized = _speech.normalize_for_speech(text)
    except Exception:
        normalized = (text or "").strip()
    prepare_ms = (time.perf_counter() - start) * 1000.0
    return normalized, prepare_ms


def synthesize_with_metrics(
    text: str, voice: str | None = None
) -> tuple[bytes, str, dict]:
    """Like synthesize() but also returns latency/provider metrics (no text)."""
    from sahlha.app.config import settings

    raw = (text or "").strip()
    if not raw:
        raise ValueError("Nothing to synthesize: empty text")
    normalized, prepare_ms = _prepare_speech_text(raw)
    if not normalized:
        raise ValueError("Nothing to synthesize: empty text")
    groq_key = settings.groq_api_key or os.getenv("GROQ_API_KEY", "")
    or_key = _get_openrouter_tts_key()
    if not groq_key and not or_key:
        raise RuntimeError("TTS needs GROQ_API_KEY or OPENROUTER_API_KEY (and accepted model terms).")

    total_start = time.perf_counter()
    metrics: dict = {
        "speech_prepare_ms": round(prepare_ms, 2),
        "chars": len(normalized),
        "chunks": 0,
        "provider": "",
        "cache": "miss",
    }

    # ---------- Try Groq first ----------
    if groq_key:
        try:
            from groq import Groq  # noqa: F401
        except ImportError as exc:
            # No Groq SDK — fall through to OpenRouter if available
            if not or_key:
                raise RuntimeError("Groq TTS needs the 'groq' package (pip install groq).") from exc
        else:
            voice_groq = voice or os.getenv("GROQ_TTS_VOICE", settings.groq_tts_voice)
            # Map an explicit OpenRouter voice back to Groq default: alloy is
            # meaningless to Orpheus, so fall back to troy instead of failing.
            if voice_groq == "alloy":
                voice_groq = os.getenv("GROQ_TTS_VOICE", settings.groq_tts_voice)
            chunks = split_for_tts(normalized, settings.groq_tts_max_chars)
            metrics["chunks"] = len(chunks)
            req_start = time.perf_counter()
            try:
                wavs = [_synthesize_chunk(c, api_key=groq_key, model=settings.groq_tts_model, voice=voice_groq) for c in chunks]
                out = stitch_wavs(wavs)
                metrics.update({
                    "tts_request_ms": round((time.perf_counter() - req_start) * 1000.0, 2),
                    "total_generation_ms": round((time.perf_counter() - total_start) * 1000.0 + prepare_ms, 2),
                    "provider": "groq",
                })
                return out, voice_groq, metrics
            except Exception as exc:
                metrics["tts_request_ms"] = round((time.perf_counter() - req_start) * 1000.0, 2)
                if not _is_retryable_tts_error(exc) or not or_key:
                    raise RuntimeError(f"Groq TTS request failed: {exc}") from exc
                groq_err = exc
            else:
                groq_err = None
            # Fall through to OpenRouter
            if or_key:
                pass
            else:
                raise RuntimeError(f"Groq TTS request failed: {groq_err}") from groq_err

    # ---------- Fallback / direct OpenRouter ----------
    if or_key:
        groq_err = locals().get("groq_err", None)
        try:
            from sahlha.app.config import settings as _s2

            model = os.getenv("OPENROUTER_TTS_MODEL", _s2.openrouter_tts_model)
            # Use explicit voice if provided, else OpenRouter default (alloy).
            # Groq's troy is not valid for OpenRouter voices: map troy -> alloy
            # unless the caller explicitly asked for troy on OpenRouter.
            voice_or = voice or os.getenv("OPENROUTER_TTS_VOICE", _s2.openrouter_tts_voice)
            if voice_or == "troy":
                voice_or = os.getenv("OPENROUTER_TTS_VOICE", _s2.openrouter_tts_voice)
            chunks = split_for_tts(normalized, _s2.groq_tts_max_chars)
            metrics["chunks"] = len(chunks)
            req_start = time.perf_counter()
            # Resolve the chunk fn dynamically so tests patching the legacy
            # `_openrouter_chunk` name still intercept OpenRouter synthesis.
            chunk_fn = globals().get("_synthesize_chunk_openrouter")
            legacy = globals().get("_openrouter_chunk")
            if legacy is not None and legacy is not chunk_fn:
                # A test (or caller) patched the legacy alias: honor it.
                import inspect as _inspect

                try:
                    src = _inspect.getsource(legacy)
                    is_alias = "_synthesize_chunk_openrouter" in src
                except Exception:
                    is_alias = True
                if not is_alias:
                    chunk_fn = legacy
            wavs = [chunk_fn(c, api_key=or_key, model=model, voice=voice_or) for c in chunks]
            # Stitch by actual container: WAV chunks are re-encoded with a clean
            # header, MP3 chunks are byte-joined. Never serve MP3 as WAV.
            if wavs and all(_is_wav(w) for w in wavs):
                out = stitch_wavs(wavs)
            elif wavs and all(sniff_audio_format(w) == "mp3" for w in wavs):
                out = b"".join(wavs)
            else:
                try:
                    out = stitch_wavs(wavs)
                except Exception:
                    # Mixed/unknown containers — join raw; callers sniff the MIME.
                    out = b"".join(wavs)
            metrics.update({
                "tts_request_ms": round((time.perf_counter() - req_start) * 1000.0, 2),
                "total_generation_ms": round((time.perf_counter() - total_start) * 1000.0 + prepare_ms, 2),
                "provider": "openrouter",
                "fallback": bool(groq_key and groq_err is not None),
            })
            return out, voice_or, metrics
        except Exception as exc2:
            if groq_key:
                raise RuntimeError(f"TTS failed (Groq: {locals().get('groq_err')} ; OpenRouter: {exc2})") from exc2
            raise RuntimeError(f"OpenRouter TTS request failed: {exc2}") from exc2

    raise RuntimeError("TTS unavailable")


def synthesize(text: str, voice: str | None = None) -> tuple[bytes, str]:
    """Returns (audio_bytes, voice_used). Groq → OpenRouter → error."""
    out, voice_used, _ = synthesize_with_metrics(text, voice=voice)
    return out, voice_used
