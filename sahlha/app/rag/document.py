"""Portable document structure; no OCR or model dependency at import time."""
from dataclasses import dataclass, field
import re


@dataclass
class DocumentBlock:
    page: int
    order: int
    type: str
    text: str
    metadata: dict = field(default_factory=dict)


def text_blocks(text: str, page: int = 1) -> list[DocumentBlock]:
    """Conservative layout inference for text/PDF/OCR; retain indentation."""
    blocks, lines, kind, fenced = [], [], None, False

    def flush():
        if lines:
            blocks.append(DocumentBlock(page, len(blocks), kind or 'paragraph', '\n'.join(lines).rstrip()))
            lines.clear()

    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith('```'):
            flush()
            fenced = not fenced
            kind = 'code' if fenced else None
            continue
        if not stripped and not fenced:
            flush()
            kind = None
            continue
        next_kind = ('code' if fenced or re.match(r'^( {4}|\t)|^(def |class |for .+:|while .+:|if .+:|print\()', line)
                     else 'list' if re.match(r'^\s*(?:[-*•]|\d+[.)])\s+', line)
                     else 'table' if '\t' in line or stripped.count('|') >= 2
                     else 'formula' if re.search(r'[=∑∫√]', line) and len(stripped.split()) < 15
                     else 'heading' if stripped.startswith('#') or (len(stripped) < 100 and len(stripped.split()) <= 10 and not re.search(r'[.!?;]$', stripped))
                     else 'paragraph')
        if kind != next_kind or next_kind == 'heading':
            flush()
        kind = next_kind
        lines.append(line)
    flush()
    return blocks


def text_quality(text: str) -> float:
    chars = [c for c in text if not c.isspace()]
    if not chars:
        return 0.0
    bad = sum(c == '\ufffd' or (ord(c) < 32) for c in chars)
    words = re.findall(r'\w+', text, re.UNICODE)
    if not words:
        return 0.0
    if max(map(len, words)) > 80 or len(set(chars)) < 3 and len(chars) > 30:
        return .2
    singles = sum(len(w) == 1 for w in words) / len(words)
    return round(max(0.0, min(1.0, 1 - bad / len(chars) * 5 - max(0, singles - .5))), 3)
