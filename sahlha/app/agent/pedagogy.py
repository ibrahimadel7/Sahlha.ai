"""Identify instructional evidence without confusing document apparatus with topics.

Raw source text is retained in storage. These views are for discovery/generation,
and retain original chunk IDs so every decision can be inspected.
"""
import re
from collections import defaultdict

DISCOVERY_VERSION = 2


def normalized(text):
    return ' '.join(text.lower().strip(' #\t\n:').split())


ROLE_HEADINGS = {
    'navigation': r'(?:table of )?contents|index|subject index|list of (?:figures|tables)',
    'author_info': r'about (?:the )?(?:authors?|writers?|contributors?)|author biographies|contributors?|credits|acknowledg(?:e)?ments',
    'publication': r'copyright (?:notice|page)|publication (?:details|information)|imprint|disclaimer|licen[cs]ing information|funding',
    'references': r'references|bibliography|further reading',
    'prerequisites': r'assumed knowledge|prerequisites?|prior knowledge|before you begin',
}
GENERIC_HEADINGS = {'content', 'introduction', 'motivation', 'overview', 'summary', 'examples',
                    'example', 'exercises', 'exercise', 'activities', 'answers', 'solutions',
                    'learning objectives', 'learning outcomes', 'objectives'}
PUBLICATION = re.compile(r'©|\ball rights reserved\b|\bisbn\b|creative commons|'
    r'\b(?:work|publication|book|material) is licen[cs]ed\b|\blicen[cs]ed under\b|'
    r'\b(?:views|opinions) expressed\b|represent the views of|'
    r'\bfunded by\b|\b(?:cover|layout) design\b|\btypesetting\b|'
    r'\bpublished by\b|creativecommons\.org', re.I)
DIRECTORY_ROW = re.compile(r'^.{2,100}?(?:\.{2,}|\s{3,})\s*\d+(?:\s*[-–,]\s*\d+)*\s*$')
PAGE_HEADER = re.compile(r'^(?:\{?\d+\}?\s*)?a guide for teachers(?:\s*\{?\d+\}?)?$|'
    r'^the improving mathematics education in schools.*(?:project|\{\d+\})$', re.I)
PAGE_FOOTER = re.compile(r'^(?:pg\.?|page)\s*\d+\s+(?:https?://|www\.)', re.I)


def heading_role(heading):
    title = normalized(heading)
    return next((role for role, pattern in ROLE_HEADINGS.items() if re.fullmatch(pattern, title)), None)


def topic_name(name):
    """Topic labels must name a concept, not a document role or sentence fragment."""
    title = normalized(name)
    if not title or heading_role(title) or title in GENERIC_HEADINGS or PUBLICATION.search(name) or PAGE_HEADER.search(title):
        return False
    if re.match(r'^(?:https?://|www\.|\d+$)', title):
        return False
    if re.match(r'^(?:this|these|that|those|we|it|they|he|she|there|here|becomes|being)$', title):
        return False
    if re.match(r'^(?:the views|this |these |we |it |they |for example|necessarily |on behalf|the use of|the fact that|at this |of |being |becomes |for |on the )', title):
        return False
    if re.search(r'\b(?:such as|we (?:say|write|call)|can be|is called|answers questions)\b', title):
        return False
    return len(title.split()) <= 12


def has_instruction(text, heading=''):
    """A label/list alone is not evidence that a concept is taught."""
    body = text.strip()
    lines = body.splitlines()
    if lines and normalized(lines[0]) == normalized(heading):
        body = '\n'.join(lines[1:]).strip()
    words = re.findall(r'\w+', body)
    if len(words) < 5:
        return False
    if re.search(r'\b(?:is|are|means|refers|defined|because|therefore|using|use|calculate|find|'
                 r'repeat\w*|explain\w*|represent\w*|convert\w*|absorb\w*|produce\w*|'
                 r'control\w*|runs?|executes?|when|allows?|helps?|describes?|can|has|have|was|were)\b', body, re.I):
        return True
    return bool(re.search(r'[.!?。؟]', body) and len(words) >= 7 or
                re.search(r'(?:\d\s*[+×*/=]|\b(?:for|while|def)\s+.+:)', body))


def instructional_views(chunks):
    """Classify with page context, then remove apparatus from mixed chunks.

    In particular a copyright paragraph broken into several fake headings must
    still be recognized as a publication page, not several learning topics.
    """
    pages = defaultdict(list)
    for chunk in chunks:
        pages[(chunk.get('document_id', ''), chunk.get('page', 0))].append(chunk)
    page_roles = {}
    for key, group in pages.items():
        combined = '\n'.join(c['text'] for c in group)
        lines = [line.strip() for line in combined.splitlines() if line.strip()]
        roles = [heading_role(line) for line in lines]
        if sum(bool(DIRECTORY_ROW.match(line)) for line in lines) >= max(3, len(lines) * .45):
            page_roles[key] = 'navigation'
        elif 'author_info' in roles:
            page_roles[key] = 'author_info'
        elif len(PUBLICATION.findall(combined)) >= 2 and not any(
                has_instruction(c['text'], c.get('section', '')) and not PUBLICATION.search(c['text'])
                for c in group):
            page_roles[key] = 'publication'
    result, decisions = [], []
    for chunk in chunks:
        role = heading_role(chunk.get('section', ''))
        lines = chunk['text'].splitlines()
        first = next((line.strip() for line in lines if line.strip()), '')
        role = heading_role(first) or role
        page_role = page_roles.get((chunk.get('document_id', ''), chunk.get('page', 0)))
        # A complete, independently explained topic can share a page with credits.
        explicit_topic = topic_name(first) and first == chunk.get('section', '').strip() and has_instruction(chunk['text'], first)
        if page_role == 'author_info' and re.search(r'\b(?:born|authors?|writers?|professor|university|published|degrees?)\b', chunk['text'], re.I):
            explicit_topic = False
        if page_role and not (explicit_topic and not PUBLICATION.search(chunk['text'])):
            role = page_role
        if role:
            decisions.append({'chunk_id': chunk.get('chunk_id'), 'role': role, 'included': False})
            continue
        kept = []
        # Join wrapped prose within paragraphs, retaining code/math lines.
        for paragraph in re.split(r'\n\s*\n', chunk['text']):
            if PUBLICATION.search(paragraph):
                # Mixed prose: retain instructional sentences outside the notice.
                sentences = re.split(r'(?<=[.!?])\s+', paragraph)
                paragraph = ' '.join(s for s in sentences if not PUBLICATION.search(s))
            for line in paragraph.splitlines():
                clean = line.strip()
                if not clean or PAGE_HEADER.match(clean) or PAGE_FOOTER.match(clean) or DIRECTORY_ROW.match(line) or re.fullmatch(r'(?:https?://\S+|\{?\d+\}?)', clean):
                    continue
                kept.append(line)
        text = '\n'.join(kept).strip()
        included = has_instruction(text, chunk.get('section', ''))
        decisions.append({'chunk_id': chunk.get('chunk_id'), 'role': 'instruction' if included else 'label_or_fragment', 'included': included})
        if included:
            section = chunk.get('section', '')
            if not topic_name(section):
                section = ''
            result.append(dict(chunk, text=text, section=section, content_role='instruction'))
    return result, decisions
