"""Full-lesson mapping and evidence validation, independent of ranked retrieval."""
import hashlib
import json
import re

from sahlha.app.agent.pedagogy import DISCOVERY_VERSION, instructional_views, topic_name, has_instruction
from sqlalchemy import select
from sahlha.app.database import models as m
from sahlha.app.database.repositories import repositories as repo


def chunk_record(c):
    return {"chunk_id": c.id, "document_id": c.document_id, "course_id": c.course_id,
            "lesson_id": c.lesson_id, "skill_id": c.skill_id, "page": c.page,
            "section": c.section, "section_id": c.section_id or f'{c.document_id}:legacy:{c.chunk_index}',
            "type": c.type or 'paragraph', "chunk_index": c.chunk_index, "text": c.text}


def ordered_lesson(db, course_id, lesson_id):
    return [chunk_record(c) for c in repo.get_chunks(db, course_id=course_id, lesson_id=lesson_id)]


def build_content_map(db, course_id, lesson_id):
    source_chunks = ordered_lesson(db, course_id, lesson_id)
    chunks, decisions = instructional_views(source_chunks)
    sections = []
    for c in chunks:
        sentences = [s.strip() for s in re.split(r'(?<=[.!?])\s+|\n\n', c['text']) if s.strip()]
        source_blocks = []
        document = repo.get_document(db, c['document_id'])
        if document:
            source_blocks = [b for b in (document.blocks or []) if b.get('page') == c['page']
                             and b.get('text', '') in c['text']]
        sections.append({'section_id': c['section_id'], 'heading': c['section'],
            'page': c['page'], 'chunk_ids': [c['chunk_id']], 'summary': sentences,
            'definitions': [s for s in sentences if re.search(r'\b(is|means|defined|refers)\b', s)],
            'examples': [s for s in sentences if re.search(r'\b(example|instance)\b', s, re.I)],
            'code_examples': [b['text'] for b in source_blocks if b['type'] == 'code'] or ([c['text']] if c['type'] == 'code' else []),
            'formulas': [s for s in sentences if re.search(r'[=∑∫√]', s)],
            'tables': [b['text'] for b in source_blocks if b['type'] == 'table'] or ([c['text']] if c['type'] == 'table' else []),
            'important_facts': sentences, 'concepts': []})
    text = ' '.join(c['text'] for c in chunks).lower()
    domains = {'programming': ('python', 'loop', 'variable', 'code', 'elif', 'function', 'دالة', 'حلقة', 'شرط'),
               'math': ('equation', 'fraction', 'algebra', 'number', 'multiplication', 'معادلة', 'كسر', 'جبر', 'عدد', 'ضرب', 'قيمة'),
               'science': ('cell', 'photosynthesis', 'energy', 'organism', 'خلية', 'تمثيل', 'ضوئي', 'طاقة', 'كائن'),
               'biology': ('cell', 'organelle', 'nucleus', 'mitochondria', 'membrane', 'خلية', 'عضية', 'نواة', 'غشاء'),
               'chemistry': ('atom', 'molecule', 'reaction', 'element', 'compound', 'ذرة', 'جزيء', 'تفاعل', 'عنصر', 'مركب'),
               'history': ('empire', 'war', 'century', 'revolution', 'kingdom', 'إمبراطورية', 'حرب', 'قرن', 'ثورة', 'مملكة', 'تاريخ'),
               'geography': ('latitude', 'longitude', 'continent', 'river', 'map', 'خط عرض', 'خط طول', 'قارة', 'نهر', 'خريطة'),
               'language': ('grammar', 'sentence', 'verb', 'noun', 'قواعد', 'جملة', 'فعل', 'اسم', 'لغة'),
               'physics': ('force', 'velocity', 'energy', 'motion', 'قوة', 'سرعة', 'طاقة', 'حركة')}
    scores = {k: sum(len(re.findall(r'\b'+re.escape(w)+r'\w*\b', text)) + text.count(w) * 0.5 for w in words) for k, words in domains.items()}
    domain = max(scores, key=scores.get) if any(scores.values()) else 'general'
    payload = {'title': next((c['section'] for c in chunks if c['section']), lesson_id.replace('_', ' ')),
               'sections': sections, 'domain': domain, 'chunk_count': len(chunks),
               'discovery_version': DISCOVERY_VERSION, 'source_chunk_count': len(source_chunks),
               'content_roles': decisions,
               'source_fingerprint': hashlib.sha256(json.dumps(source_chunks, sort_keys=True, ensure_ascii=False).encode()).hexdigest()}
    row = db.execute(select(m.LessonContentMap).where(m.LessonContentMap.course_id == course_id,
                        m.LessonContentMap.lesson_id == lesson_id)).scalar_one_or_none()
    if row is None:
        row = m.LessonContentMap(course_id=course_id, lesson_id=lesson_id)
        db.add(row)
    elif row.content.get('discovery_version') == DISCOVERY_VERSION and row.content.get('source_fingerprint') == payload['source_fingerprint']:
        return row.content, chunks
    for field in ('definitions', 'examples', 'code_examples', 'formulas', 'tables', 'important_facts', 'concepts'):
        payload[field] = [item for section in sections for item in section[field]]
    row.content = payload
    db.commit()
    return payload, chunks


def save_mapped_topics(db, course_id, lesson_id, content_map, candidates, warnings):
    payload = dict(content_map)
    payload['skills_version'] = DISCOVERY_VERSION
    payload['concepts'] = list(dict.fromkeys(s['name'] for s in candidates))
    payload['warnings'] = warnings
    payload['sections'] = [dict(section, concepts=list(dict.fromkeys(s['name'] for s in candidates
        if set(section['chunk_ids']) & set(s.get('evidence_chunk_ids', []))))) for section in payload['sections']]
    row = db.execute(select(m.LessonContentMap).where(m.LessonContentMap.course_id == course_id,
                        m.LessonContentMap.lesson_id == lesson_id)).scalar_one()
    row.content = payload
    db.commit()


def overview_sections(content_map):
    """One source-grounded summary per section for overview generation.

    A long lesson is not silently truncated to its first few chunks.
    Callers use an extractive overview if the complete map exceeds the prompt budget.
    """
    return [{'chunk_id': ','.join(s['chunk_ids']), 'text':
             (s['heading'] + ': ' if s['heading'] else '') +
             ' '.join(s['summary'][:1]) +
             (' Topics: ' + ', '.join(s['concepts']) + '.' if s.get('concepts') else '')}
            for s in content_map['sections']]


_TOPICS = [
    ('Boolean Conditions', r'\b(?:boolean|true|false|comparison operators?)\b'),
    ('While Loop Fundamentals', r'\bwhile\b'),
    ('For Loops', r'\bfor loops?\b|\bfor\s+\w+\s+in\b'),
    ('Loop Control and Termination', r'\b(?:break|continue|termination|infinite loop)\b'),
    ('Conditional Branching', r'\b(?:if|elif|else|conditional|branches)\b'),
    ('Code Indentation', r'\bindentation\b'),
    ('Loop Fundamentals', r'\b(?:loop|loops|looping|iteration)\b'),
]

# Concept recognizers for the offline path. They require instructional evidence,
# not just occurrences in an index or prerequisite list. The LLM path remains
# domain-independent and applies the same evidence/role validation.
_MATH_TOPICS = [
    ('Multiplication as Repeated Addition', r'\brepeated addition\b'),
    ('Multiplication Applications', r'\b(?:applications|cost|boxes|rolls)\b'),
    ('Array Models of Multiplication', r'\bar\s*rays?\b'),
    ('Commutative Property of Multiplication', r'\bcommutativ\w*\b'),
    ('Multiplication by Skip Counting', r'\bskip[\s\-‑]*counting\b'),
    ('Area Models of Multiplication', r'\barea model\b|\bmultiplication by area\b'),
    ('Multiplication Facts and Tables', r'\bmultiplication (?:facts|tables?)\b|\btimes tables?\b'),
    ('Distributive Property of Multiplication', r'\bdistributiv\w*\b'),
    ('Associative Property of Multiplication', r'\bassociativ\w*\b'),
    ('Multi-digit Multiplication', r'\b(?:multiple|multi)[\s\-‑]*digit\b|\blong multiplication\b'),
]


def fallback_topics(chunks):
    candidates = []
    chunks, _ = instructional_views(chunks)
    for c in chunks:
        text = c['text']
        programming = re.search(r'\b(?:python|programming|code|loops?|elif|indentation|boolean|if statement)\b', text, re.I)
        topics = [(name, pattern) for name, pattern in _TOPICS if programming and re.search(pattern, text, re.I)]
        if not programming and re.search(r'\bmultiplication\b|\bmultiply\w*\b', text, re.I):
            topics.extend((name, pattern) for name, pattern in _MATH_TOPICS if re.search(pattern, text, re.I))
        if any(n in {'While Loop Fundamentals', 'For Loops'} for n, _ in topics):
            topics = [(n, p) for n, p in topics if n != 'Loop Fundamentals']
        if not topics and topic_name(c.get('section', '')) and has_instruction(text, c.get('section', '')):
            topics = [(c['section'], re.escape(c['section']))]
        if not topics:
            sentences = re.split(r'(?<=[.!?])\s+|\n', text)
            for sentence in sentences:
                # Use the subject of a definition, not the most frequent isolated token.
                match = re.match(r'^\s*([\w][\w ,()-]{2,70}?)\s+(?:is|are|means|refers to|describes|uses|helps|allows)\b', sentence, re.I)
                if match and topic_name(match.group(1)):
                    topics.append((match.group(1).strip().title(), re.escape(match.group(1))))
            if not topics and topic_name(c.get('section', '')) and has_instruction(text, c.get('section', '')):
                topics = [(c['section'], re.escape(c['section']))]
        for name, pattern in topics:
            facts = [s.strip() for s in re.split(r'(?<=[.!?])\s+|\n', text) if re.search(pattern, s, re.I)]
            description = ' '.join(facts) or text
            candidates.append({'skill_id': re.sub(r'\W+', '_', name.lower()).strip('_'),
                'name': name, 'description': description[:1000],
                'learning_objective': f'Explain {name.lower()} using the lesson examples.',
                'key_concepts': [name], 'prerequisites': [], 'misconceptions': [], 'difficulty': 'medium',
                'source_section_ids': [c.get('section_id', '')], 'evidence_chunk_ids': [c.get('chunk_id', '')]})
    return candidates


def validate_skills(candidates, chunks, max_skills):
    chunks, _ = instructional_views(chunks)
    evidence = {c['chunk_id']: c for c in chunks}
    accepted, warnings = [], []
    garbage = {'false', 'true', 'looping', 'loops', 'example', 'output', 'lesson basics', 'introduction'}
    for raw in candidates:
        skill = dict(raw)
        name = skill.get('name', '').strip()
        ids = list(dict.fromkeys(skill.get('evidence_chunk_ids') or []))
        if not topic_name(name) or name.lower() in garbage or not ids or any(i not in evidence for i in ids):
            warnings.append(f'Rejected vague or unsupported skill: {name}')
            continue
        source = ' '.join(evidence[i]['text'] for i in ids).lower()
        terms = set(re.findall(r'\w{3,}', name.lower())) - {'fundamentals', 'basics', 'introduction', 'conditions', 'control', 'and'}
        supported_alias = any(name == topic and re.search(pattern, source, re.I) for topic, pattern in _TOPICS + _MATH_TOPICS)
        if terms and not supported_alias and sum(t.rstrip('s') in source for t in terms) / len(terms) < .75:
            warnings.append(f'Rejected unsupported topic: {name}')
            continue
        skill['source_section_ids'] = list(dict.fromkeys(evidence[i]['section_id'] for i in ids))
        skill['evidence_chunk_ids'] = ids
        skill['learning_objective'] = skill.get('learning_objective') or f'Explain {name.lower()}.'
        key = set(re.findall(r'\w+', name.lower())) - {'fundamentals', 'basics', 'introduction', 'to', 'continued', 'part', 'overview'}
        duplicate = next((s for s in accepted if s['skill_id'] == skill['skill_id'] or
            len(key & s['_key']) / max(1, len(key | s['_key'])) >= .5 or
            (key and (key <= s['_key'] or s['_key'] <= key)) or
            s['learning_objective'].strip().lower() == skill['learning_objective'].strip().lower()), None)
        if duplicate:
            duplicate['evidence_chunk_ids'] = list(dict.fromkeys(duplicate['evidence_chunk_ids'] + ids))
            duplicate['source_section_ids'] = list(dict.fromkeys(duplicate['source_section_ids'] + skill['source_section_ids']))
            continue
        skill['_key'] = key
        accepted.append(skill)
    accepted.sort(key=lambda s: min(list(evidence).index(i) for i in s['evidence_chunk_ids']))
    if len(accepted) > max_skills:
        warnings.append(f'{len(accepted)-max_skills} supported topics exceed the skill limit; increase max_skills for complete coverage.')
    for s in accepted:
        s.pop('_key', None)
    return accepted[:max_skills], warnings


def dynamic_skill_cap(content_map, chunks, candidate_count: int,
                      explicit_max: int | None = None) -> int:
    """Dynamic soft cap: small lessons ~6, medium ~10-14, large up to hard cap.

    If the caller explicitly supplies max_skills, it is always respected.
    Otherwise capacity grows with instructional sections/chunks/length/candidates.
    Never forces every lesson toward the maximum.
    """
    from sahlha.app.config import settings
    hard = max(1, settings.skill_discovery_hard_cap)
    soft_min = max(1, settings.skill_discovery_min_cap)
    if explicit_max is not None:
        return max(1, min(int(explicit_max), hard))
    sections = len(content_map.get("sections", []) or [])
    n_chunks = len(chunks or [])
    total_chars = sum(len((c.get("text") or "")) for c in (chunks or []))
    candidates = int(candidate_count or 0)
    cap = soft_min
    if n_chunks >= 6 or sections >= 4 or candidates >= 8 or total_chars > 8000:
        cap = 12
    if n_chunks >= 10 or sections >= 7 or candidates >= 12 or total_chars > 18000:
        cap = 14
    if n_chunks >= 16 or sections >= 10 or candidates >= 16 or total_chars > 35000:
        cap = hard
    return max(soft_min, min(cap, hard))


def consolidate_skills(content_map, candidates, chunks, max_skills: int):
    """WHOLE-LESSON consolidation (Stage B): merge section proposals globally.

    Uses a bounded LLM consolidator when a provider is configured; otherwise
    falls back to deterministic validate_skills merging. Always validates
    deterministically afterwards and references only real section/chunk IDs.
    Returns (final_skills, warnings, backend_label).
    """
    from sahlha.app.agent.schemas import SkillList
    warnings: list[str] = []
    if not candidates:
        return [], ["No candidate topics to consolidate."], "fallback(no-candidates)"
    # Deterministic pre-validation keeps the consolidator input clean.
    pre, pre_warnings = validate_skills(candidates, chunks, max(1, max_skills * 2))
    warnings.extend(pre_warnings)
    working = pre or candidates
    try:
        from sahlha.app.agent.llm import complete_json, llm_available
        from sahlha.app.agent.prompts import build_skill_consolidation_prompt
        if not llm_available():
            raise RuntimeError("no-llm-configured")
        # Consolidation needs course/lesson context; recover from content chunks.
        course_id = (chunks[0].get("course_id") if chunks else "general")
        lesson_id = (chunks[0].get("lesson_id") if chunks else "lesson_1")
        system, user = build_skill_consolidation_prompt(
            course_id=course_id, lesson_id=lesson_id,
            content_map=content_map, candidates=working, max_skills=max_skills)
        data, provider = complete_json(system, user, task="skill_consolidation")
        raw_list = data.get("skills") if isinstance(data, dict) else data
        validated = SkillList(skills=raw_list or []).skills
        merged = [item.model_dump() for item in validated]
        final, post_warnings = validate_skills(merged, chunks, max(1, max_skills))
        warnings.extend(post_warnings)
        if not final:
            # Consolidator dropped everything: keep deterministic pre-merge.
            final, fallback_warnings = validate_skills(working, chunks, max(1, max_skills))
            warnings.extend(fallback_warnings + ["Consolidator returned no usable skills; kept section proposals."])
            return final, warnings, provider + "+consolidation-fallback"
        return final, warnings, provider + "+consolidation"
    except Exception as exc:
        final, fallback_warnings = validate_skills(working, chunks, max(1, max_skills))
        warnings.extend(fallback_warnings)
        return final, warnings, f"fallback({type(exc).__name__})"


def retire_superseded_skills(db, course_id, lesson_id, active_ids):
    """Retain old rows and their assessment history, hide superseded topics."""
    for skill in db.execute(select(m.Skill).where(m.Skill.course_id == course_id,
                             m.Skill.lesson_id == lesson_id)).scalars():
        skill.extraction_active = skill.skill_id in active_ids
    db.commit()


def skill_evidence(db, *, course_id, lesson_id, skill_id, query=None, top_k=8):
    skill = repo.get_skill(db, course_id=course_id, lesson_id=lesson_id, skill_id=skill_id)
    chunks, _ = instructional_views(ordered_lesson(db, course_id, lesson_id))
    if skill and skill.evidence_chunk_ids:
        ids = set(skill.evidence_chunk_ids)
        chunks = [c for c in chunks if c['chunk_id'] in ids]
    else:
        # Legacy explicitly tagged chunks stay strictly scoped.
        chunks = [c for c in chunks if c['skill_id'] == skill_id]
    if query and chunks:
        from sahlha.app.rag.vectorstore import search
        ranked = search(db, query, top_k=top_k, course_id=course_id, lesson_id=lesson_id, skill_id=skill_id)
        allowed = {c['chunk_id'] for c in chunks}
        clean = {c['chunk_id']: c for c in chunks}
        ranked = [dict(c, text=clean[c['chunk_id']]['text']) for c in ranked if c['chunk_id'] in allowed]
        if ranked:
            return ranked
        # Explicit evidence read when a query has no term match; never widen scope.
        return [dict(c, retrieval_source='skill_evidence') for c in chunks[:top_k]]
    return chunks
