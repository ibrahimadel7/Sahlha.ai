"""Transparent quality signals; absence of questions is not a failing score."""
from sqlalchemy import select
from sahlha.app.database import models as m
from sahlha.app.database.repositories import repositories as repo
from sahlha.app.agent.pedagogy import instructional_views
from sahlha.app.agent.tools.content_tools import chunk_record


def lesson_quality(db, course_id, lesson_id):
    chunks = repo.get_chunks(db, course_id=course_id, lesson_id=lesson_id)
    views, roles = instructional_views([chunk_record(c) for c in chunks])
    eligible = {c['chunk_id'] for c in views}
    chunks = [c for c in chunks if c.id in eligible]
    skills = repo.list_skills(db, course_id=course_id, lesson_id=lesson_id)
    documents = db.execute(select(m.Document).where(m.Document.course_id == course_id,
                           m.Document.lesson_id == lesson_id)).scalars().all()
    ids = {c.id for c in chunks}
    covered = {i for s in skills for i in (s.evidence_chunk_ids or []) if i in ids}
    sections = {c.section_id for c in chunks}
    covered_sections = {c.section_id for c in chunks if c.id in covered}
    warnings = [w for d in documents for w in (d.extraction_quality or {}).get('warnings', [])]
    content_map = db.execute(select(m.LessonContentMap).where(m.LessonContentMap.course_id == course_id,
        m.LessonContentMap.lesson_id == lesson_id)).scalar_one_or_none()
    if content_map:
        warnings.extend(content_map.content.get('warnings', []))
    duplicate_pairs = sum(a.learning_objective.strip().lower() == b.learning_objective.strip().lower()
                          for index, a in enumerate(skills) for b in skills[index+1:] if a.learning_objective)
    if duplicate_pairs:
        warnings.append(f'{duplicate_pairs} pairs of skills have overlapping objectives.')
    if skills and len(covered) < len(ids):
        warnings.append('Some source chunks are not covered by skill evidence.')
    questions = db.execute(select(m.Question).join(m.QuestionBank).where(
        m.QuestionBank.course_id == course_id, m.QuestionBank.lesson_id == lesson_id)).scalars().all()
    grounded = sum(bool(q.evidence_chunk_ids) and set(q.evidence_chunk_ids) <= ids and
                   (q.verification or {}).get('passed') is True for q in questions)
    # Method-aware ratios (None when not measurable; never invented).
    methods = [(q.verification or {}).get('method', '') for q in questions]
    semantic = sum(1 for v in methods if v in ('llm_verified', 'llm'))
    fallback_q = sum(1 for v in methods if v == 'source_completion')
    deterministic = sum(1 for v in methods if v == 'deterministic')
    # Fallback content: skills whose structured content was never generated
    # (empty learning_content). Conservative and documented; None when no skills.
    fallback_content_count = sum(1 for s in skills if not (s.learning_content or {}).get('core_idea'))
    ocr_warning_count = sum(1 for w in warnings if 'OCR' in w or 'ocr' in w.lower())
    low_conf_pages: list[int] = []
    for d in documents:
        conf = (d.extraction_quality or {}).get('ocr_confidence') or {}
        low_conf_pages.extend(conf.get('low_confidence_pages', []) or [])
    # Active bank health: skills with a latest approved bank holding enough questions.
    from sahlha.app.config import settings as _settings
    try:
        latest_banks = repo.latest_approved_banks(db, course_id=course_id, lesson_id=lesson_id)
        latest_questions = repo.get_latest_approved_questions(db, course_id=course_id, lesson_id=lesson_id)
        from collections import Counter as _Counter
        counts = _Counter(q.question_bank_id for q in latest_questions)
        healthy = sum(1 for b in latest_banks if counts.get(b.id, 0) >= _settings.assessment_num_questions)
        bank_health = (healthy / len(latest_banks)) if latest_banks else None
        superseded = len(repo.scoped_banks(db, course_id=course_id, lesson_id=lesson_id, status="approved")) - len(latest_banks)
    except Exception:
        bank_health, superseded = None, None
    return {'extraction_quality': min(((d.extraction_quality or {}).get('quality_indicator', 1)
                                      for d in documents), default=0),
        'skill_coverage': len(covered_sections) / max(1, len(sections)) if skills else None,
        'evidence_coverage': len(covered) / max(1, len(ids)) if skills else None,
        'duplicate_skill_rate': duplicate_pairs / max(1, len(skills) * (len(skills)-1) / 2),
        'question_grounding_quality': grounded / len(questions) if questions else None,
        'semantic_question_ratio': (semantic / len(questions)) if questions else None,
        'fallback_question_ratio': (fallback_q / len(questions)) if questions else None,
        'deterministic_question_ratio': (deterministic / len(questions)) if questions else None,
        'fallback_content_ratio': (fallback_content_count / len(skills)) if skills and fallback_content_count is not None else (None if not skills else 0.0),
        'ocr_warning_count': ocr_warning_count,
        'low_confidence_pages': sorted(set(low_conf_pages)),
        'active_bank_version_health': bank_health,
        'superseded_bank_versions': superseded,
        'noninstructional_chunks': sum(not r['included'] for r in roles),
        'warnings': list(dict.fromkeys(warnings))}
