"""Question quality gate: deterministic checks + bounded semantic verification.

Source-completion questions are EMERGENCY FALLBACK only, not normal output.
Conceptual MCQs go through semantic verification whenever an LLM provider is
configured; offline they pass deterministically only if grounded.
"""
import re
from sahlha.app.agent.schemas import QuestionList
from sahlha.app.agent.llm import fallback_questions, complete_json, llm_available, temperature_for
from sahlha.app.agent.prompts import SEMANTIC_VERIFIER_SYSTEM
from sahlha.app.config import settings


class InsufficientEvidenceError(ValueError):
    """The source cannot support the requested practice questions."""


def _terms(text):
    stop = {"the", "and", "this", "that", "with", "from", "lesson", "material", "statement", "based", "complete", "which", "what", "question", "answer"}
    return {t for t in re.findall(r"\w+", text.lower()) if len(t) > 2 and t not in stop}


def critique_question(question, context_chunks, skill_id):
    """Deterministic gate only. Semantic entailment is verified separately."""
    try:
        q = dict(question, skill_id=skill_id)
        validated = QuestionList(questions=[q]).questions[0]
        if not validated.question.strip() or any(not option.strip() for option in validated.options):
            return False, "empty required field"
        if validated.type == "multiple_choice" and len(set(o.strip().lower() for o in validated.options)) != 4:
            return False, "duplicate options"
        ids = {c.get('chunk_id') for c in context_chunks if c.get('chunk_id')}
        cited = set(validated.evidence_chunk_ids)
        if ids and (not cited or not cited <= ids):
            return False, "missing or out-of-scope evidence"
        evidence = [c for c in context_chunks if not ids or c.get('chunk_id') in cited]
        objectives = {c.get('learning_objective') for c in evidence if c.get('learning_objective')}
        if objectives and validated.learning_objective not in objectives:
            return False, "question does not identify the skill objective"
        source_text = ' '.join(c.get('text', '') for c in evidence)
        normalize = lambda value: ' '.join(str(value).lower().split())
        source_normalized = normalize(source_text)
        answer = validated.options[validated.correct_answer] if validated.type == 'multiple_choice' else str(validated.correct_answer)
        if '_____' in validated.question and normalize(answer) not in source_normalized:
            return False, "correct answer is not supported by cited evidence"
        if any(re.search(r'unrelated|never mentioned|explicitly contradicts', o, re.I) for o in validated.options):
            return False, "noneducational distractor"
        quote = validated.verification.get('source_quote', '')
        if quote and normalize(quote) not in source_normalized:
            return False, "fabricated source quote"
        if '_____' in validated.question:
            if not validated.question.startswith('Complete the source statement with the exact lesson term: '):
                return False, "unsupported completion framing"
            stem = validated.question.split(': ', 1)[-1]
            if normalize(stem.replace('_____', answer, 1)) not in source_normalized:
                return False, "answer does not reconstruct a cited statement"
            if any(normalize(stem.replace('_____', option, 1)) in source_normalized
                   for option in validated.options if option != answer):
                return False, "multiple answers supported"
            if validated.difficulty != 'easy':
                return False, "source recall difficulty must be easy"
        # Conceptual MCQs are NOT rejected here for lacking verbatim lexical
        # support; semantic verification (when an LLM is configured) decides
        # entailment. Offline they must still pass the grounding check below.
        source = _terms(source_text)
        content = _terms(validated.question)
        if not content or len(source & content) < min(2, len(content)) or len(source & content) / len(content) < 0.15:
            return False, "not grounded in curriculum"
        return True, "valid"
    except (ValueError, TypeError):
        return False, "invalid question shape"


def verify_question_semantically(question, review_context):
    """Bounded semantic verifier: answerable, entailed, distractors wrong, one answer.

    Returns (valid: bool, review: dict with checks+provider). Never rewrites.
    Raises when the provider is unavailable so callers fall back safely.
    """
    result, provider = complete_json(
        SEMANTIC_VERIFIER_SYSTEM,
        str({"question": question, "context": review_context}),
        temperature=temperature_for("semantic_verifier"),
        task="semantic_verifier")
    required = {'answerable', 'answer_supported', 'distractors_incorrect',
                'unambiguous', 'clear', 'difficulty', 'objective'}
    checks = result.get('checks', {}) if isinstance(result, dict) else {}
    # 'grounded' is informational; required set stays compatible with older prompts.
    valid = result.get('valid') is True and all(checks.get(k) is True for k in required)
    return valid, {'checks': checks, 'provider': provider}


def critique_and_top_up(questions, context_chunks, skill_id, count, feedback="", *, allow_partial=False):
    if not any(c.get("text", "").strip() for c in context_chunks):
        raise InsufficientEvidenceError("No curriculum context is available. Process the lesson before generating questions.")
    kept, rejected = [], []
    seen = set()
    verifier_on = settings.semantic_verification_enabled or settings.enable_llm_critique
    verified_count = 0
    for question in questions:
        if not isinstance(question, dict):
            rejected.append('invalid question object')
            continue
        ok, reason = critique_question(question, context_chunks, skill_id)
        review = {}
        method = 'source_completion' if '_____' in question.get('question', '') else 'conceptual'
        key = ' '.join(question.get('question', '').lower().split())
        if key in seen:
            ok, reason = False, 'duplicate question'
        if ok and method == 'conceptual' and verifier_on and (llm_available() or settings.enable_llm_critique):
            try:
                cited = set(question.get('evidence_chunk_ids', []))
                review_context = [c for c in context_chunks if not c.get('chunk_id') or c['chunk_id'] in cited]
                valid, review = verify_question_semantically(question, review_context)
                ok = valid
                if not ok:
                    reason = "LLM critique rejected"
                else:
                    verified_count += 1
            except Exception:
                # Verifier provider unavailable: do not trust unverifiable
                # conceptual MCQs when an LLM was expected; discard for top-up.
                ok, reason = False, 'Semantic verifier unavailable'
        if ok:
            seen.add(key)
            final_method = ('source_completion' if '_____' in question.get('question', '')
                            else ('llm_verified' if review else 'deterministic'))
            kept.append(dict(question, skill_id=skill_id, verification={
                **question.get('verification', {}), **review, 'passed': True,
                'method': final_method}))
        else:
            rejected.append(reason)
    missing = max(0, count - len(kept))
    retained = len(kept)
    replacements = fallback_questions(context_chunks, skill_id, count + retained, feedback) if missing else []
    replaced = 0
    for question in replacements:
        if len(kept) >= count:
            break
        ok, _ = critique_question(question, context_chunks, skill_id)
        key = ' '.join(question.get('question', '').lower().split())
        if ok and key not in seen:
            seen.add(key)
            replaced += 1
            kept.append(dict(question, skill_id=skill_id, verification={
                **question.get('verification', {}), 'passed': True, 'method': 'source_completion'}))
    if not kept or (len(kept) < count and not allow_partial):
        raise InsufficientEvidenceError("Not enough grounded questions could be created from this material. Add more lesson content or re-extract the skills.")
    return kept[:count], {"retained": min(count, retained), "rejected": rejected,
                          "replacements": replaced, "target": count,
                          "generated": min(count, len(kept)), "shortfall": max(0, count - len(kept)),
                          "semantic_verified": verified_count,
                          "fallback_replacements": replaced}
