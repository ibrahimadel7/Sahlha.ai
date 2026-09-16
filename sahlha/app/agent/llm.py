"""LLM client: Groq (OpenAI-compatible API) when a key is configured, else fallback.

The fallback generator is grounded (builds questions from retrieved chunks via
templates) so the full loop works offline. When GROQ_API_KEY is set, real
LLM structured generation is used via Groq's OpenAI-compatible endpoint.
Set GROQ_MODEL to pick the model (default: openai/gpt-oss-120b).
"""
from __future__ import annotations

import json
import os
import re


def _resolve_provider() -> tuple[str, str, str]:
    """Returns (provider_name, api_key, model). provider is 'groq', 'openai', 'openrouter' or ''."""
    try:
        from sahlha.app.config import settings

        groq_key = settings.groq_api_key or os.getenv("GROQ_API_KEY", "")
        if groq_key:
            return "groq", groq_key, os.getenv("GROQ_MODEL", settings.groq_model)
        # OpenRouter as backup when Groq absent
        or_key = settings.openrouter_api_key or os.getenv("OPENROUTER_API_KEY", "")
        if or_key:
            return "openrouter", or_key, os.getenv("OPENROUTER_MODEL", settings.openrouter_model)
        oai_key = settings.openai_api_key or os.getenv("OPENAI_API_KEY", "")
        if oai_key:
            return "openai", oai_key, settings.openai_model
    except Exception:
        if os.getenv("GROQ_API_KEY"):
            return "groq", os.getenv("GROQ_API_KEY", ""), os.getenv("GROQ_MODEL", "openai/gpt-oss-120b")
        if os.getenv("OPENROUTER_API_KEY"):
            return "openrouter", os.getenv("OPENROUTER_API_KEY", ""), os.getenv("OPENROUTER_MODEL", "openai/gpt-4o-mini")
        if os.getenv("OPENAI_API_KEY"):
            return "openai", os.getenv("OPENAI_API_KEY", ""), "gpt-4o-mini"
    return "", "", ""


def llm_available() -> bool:
    provider, _, _ = _resolve_provider()
    return bool(provider)


def _get_openrouter_key() -> str:
    try:
        from sahlha.app.config import settings

        return settings.openrouter_api_key or os.getenv("OPENROUTER_API_KEY", "")
    except Exception:
        return os.getenv("OPENROUTER_API_KEY", "")


def _is_retryable_llm_error(exc: Exception) -> bool:
    """Only retry on provider/quota/rate-limit/transient failures, not on programming errors."""
    msg = str(exc).lower()
    # Model-not-found (404) or JSON validation failure should failover to backup provider
    if "model" in msg and ("does not exist" in msg or "model_not_found" in msg or "not found" in msg and "model" in msg):
        return True
    if "failed to validate json" in msg or "json_validate_failed" in msg or "decommissioned" in msg:
        return True
    # Explicit non-retryable signals (bad request, auth, not found, validation)
    non_retry = ["invalid api key", "unauthorized", "forbidden", "invalid_request", "validation"]
    # Check status code if present
    status = getattr(exc, "status_code", None)
    if status is None and hasattr(exc, "response") and getattr(exc, "response", None) is not None:
        status = getattr(exc.response, "status_code", None)
    if status is None:
        m = re.search(r"error code:\s*(\d+)", msg)
        if m:
            try:
                status = int(m.group(1))
            except Exception:
                pass
    if status is not None:
        if status == 429 or 500 <= status <= 599:
            return True
        if status == 404 and "model" in msg:
            return True  # deprecated/missing model → try OpenRouter
        if 400 <= status < 500:
            # 429 already handled; others are client errors → not retryable
            # except 408 timeout which is retryable
            if status == 408:
                return True
            return False
    # String-based retry signals
    retry_phrases = [
        "rate limit", "rate_limit", "quota", "exhausted", "overloaded", "unavailable",
        "timeout", "timed out", "connection", "temporarily", "try again", "capacity",
        "over capacity", "5xx", "provider", "429",
        "model_not_found", "does not exist", "decommissioned", "failed to validate json", "json_validate_failed",
    ]
    if any(p in msg for p in retry_phrases):
        # But exclude non-retryable that also contains retry phrase? Already handled
        if any(nr in msg for nr in non_retry):
            return False
        return True
    return False


def _call_groq(system: str, user: str, api_key: str, model: str) -> tuple[str, str]:
    """Single Groq attempt. Raises on failure."""
    try:
        from groq import Groq  # native SDK when installed

        # Explicit timeout: SDK defaults would otherwise stall the request for minutes.
        # max_retries=1: on 429/5xx fail fast to the OpenRouter backup instead of
        # burning time on SDK-internal backoff (Groq TPD quotas exhaust quickly).
        client = Groq(api_key=api_key, timeout=60, max_retries=1)
        resp = client.chat.completions.create(
            model=model,
            messages=[{"role": "system", "content": system}, {"role": "user", "content": user}],
            temperature=0.4,
            max_tokens=2000,
            response_format={"type": "json_object"},
        )
        return resp.choices[0].message.content or "{}", "groq"
    except ImportError:
        pass  # fall through to OpenAI-compatible client
    from openai import OpenAI

    from sahlha.app.config import settings as _s

    base_url = os.getenv("GROQ_BASE_URL", _s.groq_base_url)
    client = OpenAI(api_key=api_key, base_url=base_url, timeout=60, max_retries=1)
    resp = client.chat.completions.create(
        model=model,
        messages=[{"role": "system", "content": system}, {"role": "user", "content": user}],
        temperature=0.4,
        max_tokens=2000,
        response_format={"type": "json_object"},
    )
    return resp.choices[0].message.content or "{}", "groq"


def _call_openrouter(system: str, user: str) -> tuple[str, str]:
    """Single OpenRouter attempt (OpenAI-compatible). Raises on failure."""
    from openai import OpenAI

    from sahlha.app.config import settings

    api_key = _get_openrouter_key()
    if not api_key:
        raise RuntimeError("OPENROUTER_API_KEY not configured")
    model = os.getenv("OPENROUTER_MODEL", settings.openrouter_model)
    base_url = os.getenv("OPENROUTER_BASE_URL", settings.openrouter_base_url)
    client = OpenAI(api_key=api_key, base_url=base_url, timeout=60, max_retries=1)
    resp = client.chat.completions.create(
        model=model,
        messages=[{"role": "system", "content": system}, {"role": "user", "content": user}],
        temperature=0.4,
        max_tokens=2000,
        response_format={"type": "json_object"},
    )
    return resp.choices[0].message.content or "{}", "openrouter"


def _call_llm(system: str, user: str) -> tuple[str, str]:
    """Calls Groq → (on retryable failure) OpenRouter. Single failover, no loop."""
    provider, api_key, model = _resolve_provider()
    # Primary: Groq
    if provider == "groq":
        try:
            return _call_groq(system, user, api_key, model)
        except Exception as exc:
            if _is_retryable_llm_error(exc) and _get_openrouter_key():
                # One failover to OpenRouter
                return _call_openrouter(system, user)
            raise
    # If no Groq but OpenRouter configured, use it directly (Groq unavailable)
    if provider == "openrouter":
        return _call_openrouter(system, user)
    # Fallback for legacy openai provider
    if provider == "openai":
        from openai import OpenAI

        from sahlha.app.config import settings

        kwargs: dict = {"api_key": api_key, "timeout": 60, "max_retries": 1}
        if settings.openai_base_url:
            kwargs["base_url"] = settings.openai_base_url
        client = OpenAI(**kwargs)
        resp = client.chat.completions.create(
            model=model or settings.openai_model,
            messages=[{"role": "system", "content": system}, {"role": "user", "content": user}],
            temperature=0.4,
            max_tokens=2000,
            response_format={"type": "json_object"},
        )
        return resp.choices[0].message.content or "{}", "openai"
    # No provider at all — let caller trigger deterministic fallback via llm_available check
    raise RuntimeError("no-llm-configured")


def _extract_json_array(text: str) -> list:
    text = text.strip()
    try:
        data = json.loads(text)
        if isinstance(data, list):
            return data
        if isinstance(data, dict):
            for key in ("questions", "question_bank", "items", "data"):
                if isinstance(data.get(key), list):
                    return data[key]
            return [data]
    except Exception:
        pass
    m = re.search(r"\[.*\]", text, re.DOTALL)
    if m:
        return json.loads(m.group(0))
    raise ValueError("LLM did not return parseable JSON")


# --- Deterministic incidental-content guard (shared by fallbacks + critique) ---
# Conservative: a sentence is incidental only when it LOOKS like document metadata/
# admin text. Instructional sentences that merely contain a name/date/place are kept
# (over-filtering guard: names/dates/places are valid when they ARE the lesson topic).
_INCIDENTAL_RE = re.compile(
    r"(prepared\s+by|written\s+by|authored\s+by|teacher\s*:|instructor\s*:|author\s*:|"
    r"\bschool\b|\buniversity\b|\bcollege\b|\binstitute\b|\bacademy\b|"
    r"page\s*\d+|\bp\.?\s*\d+\b|table\s+of\s+contents|\breferences?\b|\bbibliography\b|"
    r"all\s+rights\s+reserved|copyright\s*©|submitted\s+(by|to)|roll\s*(no|number)|"
    r"\bdate\s*:)",
    re.IGNORECASE,
)
_METADATA_QUESTION_RE = re.compile(
    r"(who\s+(prepared|wrote|authored|teaches?)|teacher'?s?\s+name|author'?s?\s+name|"
    r"which\s+school|school'?s?\s+name|university\s+name|what\s+page|which\s+page|"
    r"page\s+number|reference\s+(list|number)|\bprepared\s+by\b)",
    re.IGNORECASE,
)


def _is_incidental_sentence(sent: str) -> bool:
    """True only for probable document-metadata/admin sentences.

    Requires a metadata marker AND (short length OR no instructional signal) so a
    genuine lesson sentence like 'Einstein, born in 1879, proposed relativity' is kept:
    it has instructional verbs/content beyond the marker. Pure 'Prepared by Ahmed Hassan.'
    or 'Al-Noor School, page 4.' lines are dropped.
    """
    s = (sent or "").strip()
    if not s:
        return True
    if not _INCIDENTAL_RE.search(s):
        return False
    words = s.split()
    # Short metadata lines are almost always incidental.
    if len(words) <= 20:
        return True
    # Longer lines: keep when they carry instructional signal (concept verbs).
    instructional = re.search(
        r"\b(is|are|means?|defines?|explains?|describes?|causes?|converts?|controls?|"
        r"executes?|runs?|checks?|tests?|uses?|requires?|produces?|process|example|because|"
        r"when|if\b)", s, re.IGNORECASE)
    return not bool(instructional)


def _instructional_sentences(context_chunks: list[dict]) -> list[tuple[str, object]]:
    """(sentence, skill) pairs with incidental/metadata sentences removed."""
    from sahlha.app.rag.text import split_sentences as _split_sentences

    out: list[tuple[str, object]] = []
    for c in context_chunks:
        for s in _split_sentences(c.get("text", "")):
            if len(s.split()) >= 6 and not _is_incidental_sentence(s):
                out.append((s, c.get("skill_id")))
    return out


def fallback_questions(context_chunks: list[dict], skill_id: str, n: int = 8,
                       feedback: str = "") -> list[dict]:
    """Deterministic grounded generator: builds MCQs from instructional sentences only.

    Incidental/metadata sentences are skipped so document metadata never becomes a
    question. If the material exists but is ALL incidental, returns [] (insufficient
    instructional context) instead of inventing metadata questions. If there are no
    usable sentences at all (empty/short input), keeps the legacy generic placeholder
    so the offline loop never breaks on near-empty retrieval.
    """
    from sahlha.app.rag.text import split_sentences as _split_sentences

    usable: list[tuple[str, object]] = []
    for c in context_chunks:
        for s in _split_sentences(c.get("text", "")):
            if len(s.split()) >= 6:
                usable.append((s, c.get("skill_id") or skill_id))
    sentences = [(s, sk) for s, sk in usable if not _is_incidental_sentence(s)]
    if not sentences:
        if usable:
            return []  # material exists but is all metadata -> refuse, don't launder it
        sentences = [("The lesson introduces key concepts and examples.", skill_id)]

    wants_hard = "hard" in feedback.lower() or "difficult" in feedback.lower() or "practical" in feedback.lower()
    difficulties = (["medium", "hard", "medium", "hard"] if wants_hard else ["easy", "medium", "easy", "medium", "hard", "medium"])
    out: list[dict] = []
    for i in range(n):
        sent, sk = sentences[i % len(sentences)]
        words = sent.split()
        # Blank-out a keyword for the stem
        keyword = max([w.strip(",.;:()\"'") for w in words if len(w) > 4], key=len, default="concept")
        stem = sent.replace(keyword, "_____", 1) if keyword in sent else sent
        question = f"Based on the lesson, complete the statement: {stem}"
        correct = f"{keyword} — as stated in the lesson"
        distractors = [
            "It is unrelated to the lesson topic",
            "The lesson explicitly contradicts this",
            "This is never mentioned in the material",
        ]
        options = [correct] + distractors
        # Deterministic rotation so correct index varies
        rot = i % 4
        options = options[rot:] + options[:rot]
        out.append({
            "skill_id": sk,
            "type": "multiple_choice",
            "question": question,
            "options": options,
            "correct_answer": options.index(correct),
            "explanation": f"Grounded in lesson text: \"{sent[:160]}\"",
            "difficulty": difficulties[i % len(difficulties)],
        })
    return out


def generate_questions_llm(system: str, user: str, context_chunks: list[dict],
                            skill_id: str, n: int, feedback: str = "") -> tuple[list[dict], str]:
    """Returns (questions, backend) where backend is 'groq'/'openai' or 'fallback'."""
    if llm_available():
        try:
            raw, provider = _call_llm(system, user)
            return _extract_json_array(raw), provider
        except Exception as exc:
            # Fail soft to grounded fallback so the loop never breaks
            return fallback_questions(context_chunks, skill_id, n, feedback), f"fallback(llm-error: {exc})"
    return fallback_questions(context_chunks, skill_id, n, feedback), "fallback(no-api-key)"


def complete_json(system: str, user: str) -> tuple[dict | list, str]:
    """Generic structured call. Returns (parsed_json, backend). Falls back raises-free? No:
    raises RuntimeError when no LLM is configured so callers can use grounded fallbacks."""
    if not llm_available():
        raise RuntimeError("no-llm-configured")
    try:
        raw, provider = _call_llm(system, user)
        text = raw.strip()
        try:
            return json.loads(text), provider
        except Exception:
            m = re.search(r"\{.*\}", text, re.DOTALL)
            if m:
                return json.loads(m.group(0)), provider
            raise ValueError("LLM did not return parseable JSON")
    except RuntimeError:
        raise
    except Exception as exc:
        raise RuntimeError(f"llm-error: {exc}") from exc


def _sentences(chunks: list[dict]) -> list[str]:
    from sahlha.app.rag.text import long_sentences as _long_sentences

    return _long_sentences(chunks)


def _top_terms(sentences: list[str], k: int = 6) -> list[str]:
    from collections import Counter

    stop = {"this", "that", "with", "from", "have", "will", "when", "what", "does", "uses",
            "using", "into", "such", "than", "then", "them", "they", "their", "about",
            "after", "also", "program", "example", "lesson",
            # Metadata terms must never become skill slugs/concepts.
            "prepared", "teacher", "author", "school", "university", "college",
            "institute", "academy", "reference", "references", "bibliography",
            "edited", "written", "authored", "submitted"}
    words: list[str] = []
    for s in sentences:
        for w in re.sub(r"[^a-zA-Z ]", "", s).lower().split():
            if len(w) > 4 and w not in stop:
                words.append(w)
    return [w for w, _ in Counter(words).most_common(k)]


def fallback_skills(context_chunks: list[dict], lesson_id: str, max_skills: int = 6) -> list[dict]:
    """Deterministic grounded splitter: one skill per ~2 INSTRUCTIONAL sentences.

    Incidental/metadata sentences are excluded so 'Prepared by X / School / page N'
    never becomes a skill. If nothing instructional remains, returns a single
    placeholder skill (insufficient context) rather than metadata skills.
    """
    sentences = [s for s in _sentences(context_chunks) if not _is_incidental_sentence(s)]
    if not sentences:
        return [{"skill_id": f"{lesson_id}_basics", "name": "Lesson basics",
                 "description": "Core concepts of the lesson.", "key_concepts": []}]
    k = max(1, min(max_skills, (len(sentences) + 1) // 2))
    size = max(1, (len(sentences) + k - 1) // k)
    out: list[dict] = []
    for i in range(k):
        part = sentences[i * size:(i + 1) * size]
        if not part:
            break
        terms = _top_terms(part)
        slug = re.sub(r"[^a-z0-9]+", "_", (terms[0] if terms else f"part{i + 1}").lower()).strip("_")
        out.append({
            "skill_id": f"{lesson_id}__{slug}"[:120],
            "name": f"{terms[0].capitalize() if terms else f'Part {i + 1}'} ({lesson_id})",
            "description": part[0][:220],
            "key_concepts": terms[:5],
        })
    return out


def fallback_explanation(skill: dict, context_chunks: list[dict]) -> str:
    """Grounded explanation composed from the skill's INSTRUCTIONAL sentences."""
    sentences = ([s for s in _sentences(context_chunks) if not _is_incidental_sentence(s)]
                 or _sentences([{"text": skill.get("description", "")}]))
    if not sentences:
        return (f"{skill.get('name', skill.get('skill_id'))}: key lesson concept. "
                "Review the uploaded material for details and examples.")
    intro = sentences[0]
    example = next((s for s in sentences[1:] if any(k in s.lower() for k in ("example", "e.g.", "for instance", ":", "if ", "when "))), None)
    extra = [s for s in sentences[1:4] if s != example]
    parts = [f"{skill.get('name', skill.get('skill_id'))}: {intro}"]
    if extra:
        parts.append("Key points: " + " ".join(extra))
    if example:
        parts.append(f"Example from the material: {example}")
    parts.append("Common mistake to avoid: confusing this with neighboring concepts — re-check the exact wording in the lesson.")
    return "\n\n".join(parts)


def fallback_lesson_explanation(context_chunks: list[dict], course_id: str, lesson_id: str,
                                 skill_names: list[str] | None = None) -> dict:
    """Grounded lesson overview composed from INSTRUCTIONAL sentences."""
    sentences = [s for s in _sentences(context_chunks) if not _is_incidental_sentence(s)]
    if not sentences:
        return {"title": lesson_id.replace("_", " ").title(),
                "explanation": (f"This lesson ({lesson_id}) introduces its key concepts step by step. "
                                "Study each skill below, then attempt the exercise."),
                "key_concepts": skill_names or []}
    terms = _top_terms(sentences, k=8)
    title = f"{terms[0].capitalize()} {terms[1] if len(terms) > 1 else 'basics'}" if terms else lesson_id
    about = " ".join(sentences[:2])
    ideas = " ".join(sentences[2:5])
    parts = [f"In this lesson: {about}"]
    if ideas:
        parts.append(f"Main ideas: {ideas}")
    if skill_names:
        parts.append("You will work through these skills in order: " + ", ".join(skill_names) + ".")
    parts.append("After studying each skill explanation below, you will be ready for the exercise.")
    return {"title": title, "explanation": "\n\n".join(parts), "key_concepts": terms[:8]}


def fallback_critique(questions: list[dict], context_chunks: list[dict]) -> list[dict]:
    """Deterministic quality gate: grounding + answer sanity + PEDAGOGICAL RELEVANCE.

    Grounding (necessary) = term overlap with full material. Relevance (sufficient) =
    not a metadata/trivia question AND overlap with INSTRUCTIONAL vocabulary.
    This enforces: presence in source is necessary but NOT sufficient.
    """
    vocab: set[str] = set()
    for c in context_chunks:
        for w in re.sub(r"[^a-zA-Z ]", "", c.get("text", "")).lower().split():
            if len(w) > 4:
                vocab.add(w)
    instructional_vocab: set[str] = set()
    for c in context_chunks:
        for s in _instructional_sentences([c]):
            for w in re.sub(r"[^a-zA-Z ]", "", s[0]).lower().split():
                if len(w) > 4:
                    instructional_vocab.add(w)
    verdicts = []
    for i, q in enumerate(questions):
        qtext = q.get("question", "")
        qterms = {w for w in re.sub(r"[^a-zA-Z ]", "", qtext).lower().split()
                  if len(w) > 4}
        overlap = len(qterms & vocab)
        grounded = overlap >= 2
        answer_ok = True
        if q.get("type") == "multiple_choice":
            ca = q.get("correct_answer")
            answer_ok = isinstance(ca, int) and 0 <= ca < len(q.get("options", []))
        # Relevance: metadata questions fail even when grounded.
        is_metadata_q = bool(_METADATA_QUESTION_RE.search(qtext))
        instr_overlap = len(qterms & instructional_vocab)
        relevant = (not is_metadata_q) and instr_overlap >= 2
        issue = ""
        if not grounded:
            issue = f"shares only {overlap} significant terms with the lesson material"
        elif not relevant:
            if is_metadata_q:
                issue = "tests incidental document metadata, not the learning objective"
            else:
                issue = (f"shares only {instr_overlap} terms with instructional content; "
                         f"pedagogically irrelevant trivia")
        elif not answer_ok:
            issue = "correct_answer index is out of range"
        verdicts.append({"index": i, "grounded": grounded, "answer_correct": answer_ok,
                         "relevant": relevant, "issue": issue})
    return verdicts


def critique_questions(system: str, user: str, questions: list[dict],
                       context_chunks: list[dict]) -> tuple[list[dict], str]:
    """Returns (verdicts, backend). Fails soft to the deterministic gate."""
    if llm_available():
        try:
            raw, provider = _call_llm(system, user)
            data = json.loads(raw.strip())
            items = data["verdicts"] if isinstance(data, dict) else data
            from sahlha.app.agent.schemas import CritiqueResult

            verdicts = [v.model_dump() for v in CritiqueResult(
                verdicts=[{**v, "index": idx} if "index" not in v else v
                          for idx, v in enumerate(items)]).verdicts]
            return verdicts, provider
        except Exception as exc:
            return fallback_critique(questions, context_chunks), f"fallback(llm-error: {exc})"
    return fallback_critique(questions, context_chunks), "fallback(no-api-key)"
