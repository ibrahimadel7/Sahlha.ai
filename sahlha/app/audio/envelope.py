"""Lip-sync envelopes: mouth-openness levels over normalized utterance time.

Two signals, one client contract:
- WAV (Groq PCM or OpenRouter pcm wrapped as WAV): TRUE speech-energy
  envelope from PCM RMS. The mouth opens with actual loudness and closes in
  real pauses — sample-accurate sync with the words being said.
- MP3 / unknown (no MP3 decoder on either side): word-timed envelope built
  from the same speakable text sent to TTS. Words are laid over normalized
  time by character weight with explicit pause spans after sentence
  punctuation; the mouth flutters per word syllable and fully closes between
  sentences. Approximate, but locked to playback position.

Both return ``ENVELOPE_BUCKETS`` levels in [0, 1] over FRACTIONS of total
duration, so the client maps ``position / duration -> index`` with one rule
and needs no per-format bookkeeping:

    i = clamp(floor(position_sec / duration_sec * N), 0, N - 1)

The envelope is keyed by the same content digest as the audio, so it is as
cacheable as the audio itself. Pure stdlib (no numpy/ffmpeg) so synthesis
workers never gain heavy deps. Never raises for bad input: WAV parse errors
fall back to the timed envelope, empty text yields a closed mouth.
"""
from __future__ import annotations

import math
import re
import struct

ENVELOPE_VERSION = 1
ENVELOPE_BUCKETS = 300

# Sentence stops read as real pauses; commas as short breaths. Weights are in
# "character units" at ~14 chars/sec TTS: a period pauses ~0.5s, a comma ~0.25s.
_SENTENCE_PAUSE_WEIGHT = 7.0
_COMMA_PAUSE_WEIGHT = 3.0

_WORD_RE = re.compile(r"\S+")
_SENTENCE_END_RE = re.compile(r"[.!?…]+$")
_COMMA_END_RE = re.compile(r"[,;:]+$")


def _clamp01(value: float) -> float:
    if value < 0.0:
        return 0.0
    if value > 1.0:
        return 1.0
    return value


def _smooth(levels: list[float]) -> list[float]:
    """One pass of [0.25, 0.5, 0.25] neighbor averaging (ends duplicated)."""
    if len(levels) < 3:
        return list(levels)
    out = [0.0] * len(levels)
    out[0] = 0.75 * levels[0] + 0.25 * levels[1]
    for i in range(1, len(levels) - 1):
        out[i] = 0.25 * levels[i - 1] + 0.5 * levels[i] + 0.25 * levels[i + 1]
    out[-1] = 0.25 * levels[-2] + 0.75 * levels[-1]
    return out


def _resample_average(levels: list[float], n: int) -> list[float]:
    """Average fine buckets down (or stretch) to exactly ``n`` buckets."""
    if not levels or n <= 0:
        return [0.0] * max(n, 0)
    if len(levels) == n:
        return list(levels)
    out: list[float] = []
    for j in range(n):
        start = j * len(levels) / n
        end = (j + 1) * len(levels) / n
        lo, hi = int(start), int(end)
        if hi <= lo:
            out.append(levels[min(lo, len(levels) - 1)])
            continue
        total = sum(levels[lo:hi])
        # Fractional edges keep energy honest when the ratio is not integral.
        if lo > start:
            total += levels[lo - 1] * (lo - start) if lo > 0 else 0.0
        if hi < end and hi < len(levels):
            total += levels[hi] * (end - hi)
        out.append(total / (end - start))
    return out


def _parse_wav(data: bytes) -> tuple[int, int, int, int, bytes] | None:
    """Return (audio_format, channels, sample_rate, bits_per_sample, pcm).

    ``audio_format`` 1 = integer PCM, 3 = float32. Returns None when the bytes
    are not a parseable WAV (callers fall back to the timed envelope).
    """
    if len(data) < 12 or data[0:4] != b"RIFF" or data[8:12] != b"WAVE":
        return None
    fmt: tuple[int, int, int, int] | None = None
    pcm: bytes | None = None
    offset = 12
    size = len(data)
    while offset + 8 <= size:
        chunk_id = data[offset:offset + 4]
        chunk_size = struct.unpack_from("<I", data, offset + 4)[0]
        body = offset + 8
        # Guard corrupt sizes: clamp to what is actually present.
        available = max(0, min(chunk_size, size - body))
        if chunk_id == b"fmt " and available >= 16 and fmt is None:
            audio_format, channels, sample_rate = struct.unpack_from("<HHI", data, body)
            _, _, bits = struct.unpack_from("<IHH", data, body + 8)
            fmt = (audio_format, channels, sample_rate, bits)
        elif chunk_id == b"data" and pcm is None:
            pcm = data[body:body + available]
        offset = body + chunk_size + (chunk_size & 1)
    if fmt is None or pcm is None:
        return None
    audio_format, channels, sample_rate, bits = fmt
    if channels < 1 or sample_rate <= 0:
        return None
    if audio_format not in (1, 3):
        return None
    if audio_format == 3 and bits != 32:
        return None
    if audio_format == 1 and bits not in (8, 16, 24, 32):
        return None
    return audio_format, channels, sample_rate, bits, pcm


def _decode_frame(
    pcm: bytes, frame_pos: int, channels: int, audio_format: int, bits: int
) -> float:
    """Mono mix of one frame as float in [-1, 1] (clamped, never raises)."""
    total = 0.0
    if audio_format == 3:  # float32 LE
        for ch in range(channels):
            off = frame_pos + ch * 4
            if off + 4 > len(pcm):
                break
            (sample,) = struct.unpack_from("<f", pcm, off)
            if sample != sample:  # NaN guard
                sample = 0.0
            total += max(-1.0, min(1.0, sample))
        return total / max(1, channels)
    width = bits // 8
    for ch in range(channels):
        off = frame_pos + ch * width
        if off + width > len(pcm):
            break
        raw = pcm[off:off + width]
        if bits == 8:
            total += (raw[0] - 128) / 128.0
        elif bits == 16:
            total += int.from_bytes(raw, "little", signed=True) / 32768.0
        elif bits == 24:
            total += int.from_bytes(raw, "little", signed=True) / 8388608.0
        else:  # 32-bit int
            total += int.from_bytes(raw, "little", signed=True) / 2147483648.0
    return max(-1.0, min(1.0, total / max(1, channels)))


def energy_levels_from_wav(data: bytes, n: int = ENVELOPE_BUCKETS) -> list[float] | None:
    """TRUE speech-energy envelope from WAV PCM, resampled to ``n`` buckets.

    Returns None when the bytes are not usable WAV (caller uses the timed
    envelope). An all-silence file honestly returns all zeros (closed mouth).
    """
    try:
        parsed = _parse_wav(data)
    except Exception:
        return None
    if parsed is None:
        return None
    audio_format, channels, sample_rate, bits, pcm = parsed
    bytes_per_frame = channels * (4 if audio_format == 3 else bits // 8)
    if bytes_per_frame <= 0:
        return None
    frames = len(pcm) // bytes_per_frame
    if frames <= 0:
        return None
    duration = frames / sample_rate
    # ~50 fine buckets/sec, bounded so huge files stay cheap.
    fine = max(1, min(1500, int(duration * 50) or 1))
    # At most ~500 decoded frames per fine bucket (strided): a 3-minute file
    # decodes <= 750k samples worst case.
    rms: list[float] = []
    for b in range(fine):
        start = (b * frames) // fine
        end = ((b + 1) * frames) // fine
        count = max(1, end - start)
        stride = max(1, count // 500)
        energy = 0.0
        taken = 0
        for f in range(start, end, stride):
            sample = _decode_frame(pcm, f * bytes_per_frame, channels, audio_format, bits)
            energy += sample * sample
            taken += 1
        rms.append(math.sqrt(energy / max(1, taken)))
    peak = max(rms) if rms else 0.0
    if peak < 1e-9:
        return [0.0] * n
    # Perceptual expansion (sqrt) + noise gate so breaths read as ~closed.
    gated = []
    for value in rms:
        level = math.sqrt(value / peak)
        gated.append(_clamp01((level - 0.10) / 0.90))
    return [_clamp01(v) for v in _resample_average(_smooth(gated), n)]


def _token_spans(text: str) -> list[tuple[str, float, int]]:
    """Split speakable text into ('word'|'pause', weight, syllables) spans."""
    spans: list[tuple[str, float, int]] = []
    for match in _WORD_RE.finditer(text):
        token = match.group(0)
        core = token.strip(".,!?…;:\"'“”‘’()[]{}-–—")
        syllables = max(1, min(4, (len(core) + 2) // 3)) if core else 1
        spans.append(("word", max(1.0, float(len(token))), syllables))
        if _SENTENCE_END_RE.search(token):
            spans.append(("pause", _SENTENCE_PAUSE_WEIGHT, 0))
        elif _COMMA_END_RE.search(token):
            spans.append(("pause", _COMMA_PAUSE_WEIGHT, 0))
    return spans


def timed_levels_for_text(text: str, n: int = ENVELOPE_BUCKETS) -> list[float]:
    """Word-timed envelope for MP3/unknown audio (position-locked approx).

    Words occupy time by character weight; sentence punctuation inserts real
    pause spans (level 0). Inside a word the mouth flutters ``syllables``
    times from a half-open floor (coarticulation: no popping to 0
    mid-sentence). Empty text returns all zeros.
    """
    spans = _token_spans(text or "")
    total = sum(weight for _, weight, _ in spans)
    if total <= 0:
        return [0.0] * n
    # Cumulative boundaries in normalized time.
    bounds: list[float] = [0.0]
    for _, weight, _ in spans:
        bounds.append(bounds[-1] + weight / total)
    out: list[float] = []
    span_idx = 0
    for j in range(n):
        f = (j + 0.5) / n
        while span_idx < len(spans) - 1 and f >= bounds[span_idx + 1]:
            span_idx += 1
        kind, _, syllables = spans[span_idx]
        if kind == "pause":
            out.append(0.0)
            continue
        start, end = bounds[span_idx], bounds[span_idx + 1]
        width = max(1e-9, end - start)
        u = _clamp01((f - start) / width)
        out.append(0.35 + 0.65 * abs(math.sin(math.pi * max(1, syllables) * u)))
    return [_clamp01(v) for v in out]


def levels_for_audio_file(path: str, speech_text: str, n: int = ENVELOPE_BUCKETS) -> tuple[list[float], str]:
    """Best envelope for a cached audio file. Never raises.

    WAV -> ("energy", true levels). Anything else (MP3/unknown/unreadable) ->
    ("timed", word-timed levels from ``speech_text``).
    """
    try:
        with open(path, "rb") as fh:
            head = fh.read(16)
        is_wav = head[:4] == b"RIFF"
        if is_wav:
            with open(path, "rb") as fh:
                data = fh.read()
            levels = energy_levels_from_wav(data, n)
            if levels is not None:
                return levels, "energy"
    except Exception:
        pass
    return timed_levels_for_text(speech_text, n), "timed"


def envelope_payload(levels: list[float], kind: str) -> dict:
    """Client contract JSON (compact 3-decimal levels)."""
    return {
        "version": ENVELOPE_VERSION,
        "kind": kind if kind in ("energy", "timed") else "timed",
        "buckets": len(levels),
        "levels": [round(_clamp01(v), 3) for v in levels],
    }


def valid_envelope_payload(payload: object) -> bool:
    """True when a cached envelope JSON is safe to serve."""
    if not isinstance(payload, dict):
        return False
    if payload.get("version") != ENVELOPE_VERSION:
        return False
    if payload.get("kind") not in ("energy", "timed"):
        return False
    levels = payload.get("levels")
    if not isinstance(levels, list) or not (20 <= len(levels) <= 1200):
        return False
    return all(isinstance(v, (int, float)) and 0.0 <= v <= 1.0 for v in levels)
