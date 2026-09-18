"""Deterministic speech-preparation pipeline.

student-facing explanation -> speech normalization -> speech segmentation -> TTS

No LLM calls. All transforms are deterministic so the same explanation always
produces the same speakable text (and therefore the same cache key).

Goals (per TTS audit):
- never read markdown / code fences / JSON / metadata aloud literally
- headings become spoken sentences, lists become flowing speech
- code blocks are NOT read as prose; the code stays on screen
- technical terms keep their meaning (tiny symbol layer only where TTS
  would otherwise spell punctuation literally)
- segmentation respects paragraphs / teaching sections, never mid-sentence
"""
from __future__ import annotations

import re

# Placeholder spoken where a fenced code block stood. The code itself remains
# visually available to the student; TTS only carries the explanation around it.
CODE_PLACEHOLDER = "The code example is shown on screen."

_ABBREVIATIONS = ("e.g.", "i.e.", "etc.", "Mr.", "Mrs.", "Ms.", "Dr.", "vs.")

# Minimal symbol layer: only tokens TTS would otherwise spell out literally
# ("hashtag", "C plus plus" misreads, "%" silence). NOT a pronunciation dict.
_TECH_REPLACEMENTS: tuple[tuple[re.Pattern, str], ...] = (
    (re.compile(r"C\+\+"), "C plus plus"),
    (re.compile(r"C#"), "C sharp"),
    (re.compile(r"\.NET\b"), "dot net"),
    (re.compile(r"\be\.g\.", re.IGNORECASE), "for example"),
    (re.compile(r"\bi\.e\.", re.IGNORECASE), "that is"),
    (re.compile(r"\betc\.", re.IGNORECASE), "and so on"),
)

_FENCE_RE = re.compile(r"```.*?```", re.DOTALL)
_INLINE_CODE_RE = re.compile(r"`([^`\n]+)`")
_IMAGE_RE = re.compile(r"!\[([^\]]*)\]\([^)]*\)")
_LINK_RE = re.compile(r"\[([^\]]+)\]\([^)]*\)")
_HTML_RE = re.compile(r"<[^>]+>")
_BOLD_RE = re.compile(r"(\*\*|__)(.+?)\1")
_ITALIC_RE = re.compile(r"(?<!\w)[*_]([^*_\n]+)[*_](?!\w)")
_HEADING_RE = re.compile(r"^\s*#{1,6}\s*(.+?)\s*$")
_QUOTE_RE = re.compile(r"^\s*>\s?")
_HR_RE = re.compile(r"^\s*(---|\*\*\*|___)\s*$")
_LIST_RE = re.compile(r"^\s*(?:[-*+]\s+|\d+[.)]\s+)(.+?)\s*$")
_TABLE_SEP_RE = re.compile(r"^\s*\|?[\s:|-]+\|?[\s:|.-]*$")
_TERMINAL_RE = re.compile(r"[.!?؟]$")


def _protect_abbreviations(text: str) -> tuple[str, dict[str, str]]:
    """Hide abbreviation periods so sentence splitting never cuts inside them."""
    protected = text
    mapping: dict[str, str] = {}
    for i, abbr in enumerate(_ABBREVIATIONS):
        token = f"\x00ABBR{i}\x00"
        if abbr in protected:
            mapping[token] = abbr
            protected = protected.replace(abbr, token)
    # Decimals: 3.14 must not split.
    protected = re.sub(r"(?<=\d)\.(?=\d)", "\x00DOT\x00", protected)
    mapping["\x00DOT\x00"] = "."
    return protected, mapping


def _restore_protected(text: str, mapping: dict[str, str]) -> str:
    for token, original in mapping.items():
        text = text.replace(token, original)
    return text


def split_speech_sentences(text: str) -> list[str]:
    """Sentence split aware of abbreviations, decimals and Arabic punctuation.

    Pure — splits on . ! ? ؟ followed by whitespace + a sentence start
    (letter/digit/quote/paren, Latin or Arabic). Never splits mid-word.
    """
    text = (text or "").strip()
    if not text:
        return []
    protected, mapping = _protect_abbreviations(text)
    # Split on terminal punctuation + whitespace when the next char plausibly
    # starts a new sentence (avoids splitting "v1.2 release" style fragments).
    parts = re.split(r"(?<=[.!?؟])\s+(?=[\"'“”'\(\[\u0600-\u06FFA-Za-z0-9])", protected)
    out = [_restore_protected(p.strip(), mapping) for p in parts if p.strip()]
    return out


def _clean_inline(text: str) -> str:
    text = _IMAGE_RE.sub(lambda m: m.group(1).strip(), text)
    text = _LINK_RE.sub(lambda m: m.group(1).strip(), text)
    text = _HTML_RE.sub(" ", text)
    text = _BOLD_RE.sub(lambda m: m.group(2), text)
    text = _ITALIC_RE.sub(lambda m: m.group(1), text)
    text = _INLINE_CODE_RE.sub(lambda m: m.group(1).replace("_", " ").strip(), text)
    return text


def _apply_tech_replacements(text: str) -> str:
    for pattern, replacement in _TECH_REPLACEMENTS:
        text = pattern.sub(replacement, text)
    # "50%" -> "50 percent" (keep numbers meaningful in speech).
    text = re.sub(r"(?<=\d)\s*%", " percent", text)
    # Prose ampersand -> "and" (code blocks already removed above).
    text = re.sub(r"\s*&\s*", " and ", text)
    return text


def _join_list_items(items: list[str]) -> str:
    items = [i.strip().rstrip(".,;:").strip() for i in items if i.strip()]
    items = [i for i in items if i]
    if not items:
        return ""
    if len(items) == 1:
        return items[0] + "."
    if len(items) == 2:
        return f"{items[0]} and {items[1]}."
    return ", ".join(items[:-1]) + f", and {items[-1]}."


def normalize_for_speech(raw: str) -> str:
    """Convert a student-facing explanation into speakable plain text.

    Deterministic + idempotent: running it twice yields the same output.
    Preserves educational meaning, terminology, examples and emphasis.
    """
    text = (raw or "").replace("\r\n", "\n").replace("\r", "\n").strip()
    if not text:
        return ""
    # Code fences first: speak the explanation around the code, never the code.
    # Collapse consecutive fences into one placeholder so three snippets do not
    # repeat the same line three times.
    text = _FENCE_RE.sub(f"\n\n{CODE_PLACEHOLDER}\n\n", text)
    text = re.sub(
        r"(?:\s*" + re.escape(CODE_PLACEHOLDER) + r"\s*){2,}",
        f"\n\n{CODE_PLACEHOLDER}\n\n",
        text,
    )

    lines = text.split("\n")
    out_lines: list[str] = []
    pending_list: list[str] = []

    def flush_list() -> None:
        nonlocal pending_list
        if not pending_list:
            return
        joined = _join_list_items(pending_list)
        pending_list = []
        if not joined:
            return
        # Attach to a preceding "Key concepts:" style lead-in so it sounds
        # like one intentional explanation instead of a document readout.
        if out_lines and out_lines[-1].rstrip().endswith(":"):
            lead = out_lines.pop().rstrip()
            # "Key concepts:" + "a, b, and c." -> "Key concepts include a, b, and c."
            lead = re.sub(r":\s*$", "", lead)
            out_lines.append(f"{lead} include {joined}")
        else:
            out_lines.append(joined)

    for raw_line in lines:
        line = raw_line.strip()
        if not line:
            flush_list()
            out_lines.append("")  # paragraph break
            continue
        if _HR_RE.match(line):
            flush_list()
            continue
        # Tables: separator rows carry no meaning; cell pipes become commas.
        if _TABLE_SEP_RE.match(line) and "|" in line:
            continue
        if "|" in line and line.count("|") >= 2:
            flush_list()
            cells = [c.strip() for c in line.strip("|").split("|")]
            cells = [_clean_inline(c).strip(":- ") for c in cells if c.strip(":- ")]
            if cells:
                out_lines.append(", ".join(cells) + ".")
            continue
        m_list = _LIST_RE.match(raw_line)
        if m_list:
            pending_list.append(_clean_inline(m_list.group(1)))
            continue
        flush_list()
        m_head = _HEADING_RE.match(line)
        if m_head:
            heading = _clean_inline(m_head.group(1)).strip().rstrip(":").strip()
            if heading:
                if not _TERMINAL_RE.search(heading):
                    heading += "."
                out_lines.append(heading)
            continue
        line = _QUOTE_RE.sub("", raw_line).strip()
        line = _clean_inline(line)
        out_lines.append(line)

    flush_list()

    # Re-assemble preserving paragraph breaks, then tech replacements.
    paragraphs: list[str] = []
    buf: list[str] = []
    for ln in out_lines:
        if not ln:
            if buf:
                paragraphs.append(" ".join(buf))
                buf = []
            continue
        buf.append(ln)
    if buf:
        paragraphs.append(" ".join(buf))

    cleaned_paras: list[str] = []
    for para in paragraphs:
        para = _apply_tech_replacements(para)
        # Strip leftover markdown litter but keep speech punctuation.
        para = re.sub(r"[#*_~`>]+", " ", para)
        para = re.sub(r"[ \t]+", " ", para).strip()
        para = re.sub(r"\s+([,.!?؟;:])", r"\1", para)
        if para:
            # Paragraphs without terminal punctuation get one so the voice
            # pauses naturally instead of rushing into the next paragraph.
            if not _TERMINAL_RE.search(para):
                para += "."
            cleaned_paras.append(para)

    result = "\n\n".join(cleaned_paras)
    result = re.sub(r"\n{3,}", "\n\n", result).strip()
    result = re.sub(r"[ \t]{2,}", " ", result)
    return result


def segment_for_speech(
    normalized: str, *, target_chars: int = 550, max_chars: int = 900
) -> list[str]:
    """Pack normalized speech into natural units (paragraph → sentences).

    Preferred boundaries: paragraph, then several related sentences.
    Never splits mid-sentence except for a single overlong sentence, which is
    cut at a word boundary (never mid-word, never inside technical tokens).
    """
    text = (normalized or "").strip()
    if not text:
        return []
    if max_chars < 50:
        max_chars = 50
    target_chars = max(50, min(target_chars, max_chars))

    paragraphs = [p.strip() for p in re.split(r"\n{2,}", text) if p.strip()]
    chunks: list[str] = []
    current = ""

    def push_current() -> None:
        nonlocal current
        if current.strip():
            chunks.append(current.strip())
        current = ""

    def hard_split_words(sentence: str) -> list[str]:
        """Split one overlong sentence at word boundaries (never mid-word)."""
        words = sentence.split()
        parts: list[str] = []
        buf = ""
        for w in words:
            candidate = f"{buf} {w}".strip()
            if len(candidate) > max_chars and buf:
                parts.append(buf)
                buf = w
            else:
                buf = candidate
        if buf:
            parts.append(buf)
        # A single pathological token longer than max_chars: slice it rather
        # than emitting an oversized chunk (last resort, still seeks a pause).
        final: list[str] = []
        for part in parts:
            if len(part) <= max_chars:
                final.append(part)
            else:
                for i in range(0, len(part), max_chars):
                    final.append(part[i : i + max_chars])
        return final or [sentence[:max_chars]]

    for para in paragraphs:
        sentences = split_speech_sentences(para)
        if not sentences:
            continue
        # A paragraph that already fits is one natural speech unit.
        if len(para) <= target_chars and len(para) <= max_chars:
            if len(current) + len(para) + 1 <= target_chars:
                current = f"{current} {para}".strip()
            else:
                push_current()
                current = para
            continue
        for sent in sentences:
            if len(sent) > max_chars:
                push_current()
                chunks.extend(hard_split_words(sent))
                continue
            if not current:
                current = sent
            elif len(current) + len(sent) + 1 <= target_chars:
                current = f"{current} {sent}"
            elif len(current) + len(sent) + 1 <= max_chars and (
                current.count(".") + current.count("؟") < 3
            ):
                # Few related sentences may share a chunk up to max_chars so
                # teaching sections stay together instead of fragmenting.
                current = f"{current} {sent}"
            else:
                push_current()
                current = sent
        # Paragraph break: prefer not to glue unrelated sections together.
        # Keep current open only when it is still a small fragment.
        if len(current) > target_chars // 2:
            push_current()

    push_current()
    return chunks or [text[:max_chars]]


def build_skill_speech(name: str, explanation: str) -> str:
    """Full pipeline for one skill: name + explanation -> speakable text."""
    name = (name or "").strip().rstrip(".")
    combined = f"{name}. {explanation}" if name else (explanation or "")
    return normalize_for_speech(combined)


def build_lesson_speech(title: str, explanation: str) -> str:
    title = (title or "").strip().rstrip(".")
    combined = f"{title}. {explanation}" if title else (explanation or "")
    return normalize_for_speech(combined)
