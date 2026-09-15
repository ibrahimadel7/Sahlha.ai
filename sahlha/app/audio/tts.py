"""Groq text-to-speech provider (Orpheus English voices).

Interface: `synthesize(text, voice=None) -> bytes` (single WAV).
Long text is split sentence-aware and stitched. Swappable behind this module.
"""
from __future__ import annotations

import io
import os
import re
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


def _pcm_to_wav(pcm: bytes, framerate: int = 24000, nchannels: int = 1, sampwidth: int = 2) -> bytes:
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(nchannels)
        w.setsampwidth(sampwidth)
        w.setframerate(framerate)
        w.writeframes(pcm)
    return buf.getvalue()


def split_for_tts(text: str, max_chars: int = 900) -> list[str]:
    """Sentence-aware splitter (pure — unit tested)."""
    sentences = [s.strip() for s in re.split(r"(?<=[.!?])\s+", text.strip()) if s.strip()]
    chunks, current = [], ""
    for s in sentences:
        if len(s) > max_chars:
            if current:
                chunks.append(current)
                current = ""
            for i in range(0, len(s), max_chars):  # hard-split overlong sentence
                chunks.append(s[i:i + max_chars])
        elif len(current) + len(s) + 1 <= max_chars:
            current = f"{current} {s}".strip()
        else:
            chunks.append(current)
            current = s
    if current:
        chunks.append(current)
    return chunks or [text[:max_chars]]


def stitch_wavs(wavs: list[bytes]) -> bytes:
    """Concatenate WAV blobs with identical params into one WAV (pure — unit tested)."""
    if len(wavs) == 1:
        return wavs[0]
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


def _synthesize_chunk(text: str, *, api_key: str, model: str, voice: str) -> bytes:
    from groq import Groq

    client = Groq(api_key=api_key)
    resp = client.audio.speech.create(model=model, voice=voice, input=text,
                                      response_format="wav")
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


def _synthesize_chunk_openrouter(text: str, *, api_key: str, model: str, voice: str) -> bytes:
    from openai import OpenAI

    from sahlha.app.config import settings as _s

    base_url = os.getenv("OPENROUTER_BASE_URL", _s.openrouter_base_url)
    client = OpenAI(api_key=api_key, base_url=base_url)
    # OpenRouter TTS per docs: response_format only mp3|pcm (wav is invalid → ZodError).
    # Also try candidate models if the configured one is not available for this key/tier.
    candidates = [model]
    # Fallback list derived from OpenRouter docs: dated gpt-4o-mini-tts + voxtral
    for alt in ("openai/gpt-4o-mini-tts-2025-12-15", "mistralai/voxtral-mini-tts-2603"):
        if alt not in candidates:
            candidates.append(alt)
    last_exc: Exception | None = None
    for cand in candidates:
        for fmt in ("mp3", "pcm"):
            try:
                resp = client.audio.speech.create(model=cand, voice=voice, input=text, response_format=fmt)
                if hasattr(resp, "read"):
                    data = resp.read()
                elif hasattr(resp, "content"):
                    data = resp.content  # type: ignore[attr-defined]
                else:
                    data = bytes(resp)
                if data:
                    # Normalize pcm → wav for consistent stitching
                    if fmt == "pcm" and not data.startswith(b"RIFF"):
                        return _pcm_to_wav(data)
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


def synthesize(text: str, voice: str | None = None) -> tuple[bytes, str]:
    """Returns (audio_bytes, voice_used). Groq → OpenRouter → error."""
    from sahlha.app.config import settings

    text = (text or "").strip()
    if not text:
        raise ValueError("Nothing to synthesize: empty text")
    groq_key = settings.groq_api_key or os.getenv("GROQ_API_KEY", "")
    or_key = _get_openrouter_tts_key()
    if not groq_key and not or_key:
        raise RuntimeError("TTS needs GROQ_API_KEY or OPENROUTER_API_KEY (and accepted model terms).")

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
            chunks = split_for_tts(text, settings.groq_tts_max_chars)
            try:
                wavs = [_synthesize_chunk(c, api_key=groq_key, model=settings.groq_tts_model, voice=voice_groq) for c in chunks]
                return stitch_wavs(wavs), voice_groq
            except Exception as exc:
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
            # Use explicit voice if provided, else OpenRouter default (alloy)
            voice_or = voice or os.getenv("OPENROUTER_TTS_VOICE", _s2.openrouter_tts_voice)
            # Groq's troy not valid for OpenRouter; map to alloy if voice is troy and caller didn't explicitly set OpenRouter voice
            if voice is None and voice_or == _s2.openrouter_tts_voice:
                pass  # keep alloy
            chunks = split_for_tts(text, _s2.groq_tts_max_chars)
            wavs = [_synthesize_chunk_openrouter(c, api_key=or_key, model=model, voice=voice_or) for c in chunks]
            # Stitch: wav → wave, mp3 → byte join
            if wavs and all(_is_wav(w) for w in wavs):
                return stitch_wavs(wavs), voice_or
            try:
                return stitch_wavs(wavs), voice_or
            except Exception:
                # Likely mp3 chunks — simple concatenation is valid for MP3
                return b"".join(wavs), voice_or
        except Exception as exc2:
            if groq_key:
                raise RuntimeError(f"TTS failed (Groq: {locals().get('groq_err')} ; OpenRouter: {exc2})") from exc2
            raise RuntimeError(f"OpenRouter TTS request failed: {exc2}") from exc2

    raise RuntimeError("TTS unavailable")
