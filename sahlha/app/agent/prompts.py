"""Prompts owned by the LLM side (reasoning/generation). App logic stays in tools/services."""
QUESTION_SYSTEM = """You are Sahlha. Generate a question bank GROUNDED ONLY in the context.
- Answerable only from context; no invented facts.
- Mix easy/medium/hard; 4 options, correct_answer is 0-based index.
- Cover different key concepts; follow teacher feedback if any.
Return ONLY JSON array of {skill_id, type:"multiple_choice", question, options[4], correct_answer, explanation, difficulty}.
"""

QUESTION_USER_TEMPLATE = """Course: {course_id}\nLesson: {lesson_id}\nSkill: {skill_id}\nTeacher feedback (may be empty): {feedback}\n\n--- RETRIEVED LESSON CONTEXT ---\n{context}\n--- END CONTEXT ---\n\nGenerate {n} questions as a JSON array."""


def build_question_prompt(*, course_id: str, lesson_id: str, skill_id: str,
                          context_chunks: list[dict], feedback: str = "", n: int = 8) -> tuple[str, str]:
    from sahlha.app.config import settings

    # Token-optimized: 6000 chars ≈ 1500 tokens vs 3000 before; 4 chunks of 800 = 3200 chars fits comfortably
    context = "\n\n".join(f"[chunk {c.get('chunk_id', i)} | skill={c.get('skill_id')}] {c.get('text', '')}"
                          for i, c in enumerate(context_chunks)) or "(no context retrieved)"
    user = QUESTION_USER_TEMPLATE.format(course_id=course_id, lesson_id=lesson_id,
                                         skill_id=skill_id, feedback=(feedback or "(none)")[:500],
                                         context=context[:settings.llm_skill_context_chars], n=n)
    return QUESTION_SYSTEM, user


SKILL_EXTRACTION_SYSTEM = """You are Sahlha. Split lesson into skills (one per topic).
- You decide count (up to max); grounded in context; independently learnable/testable.
- skill_id: snake_case slug; key_concepts: 3-6 phrases from material.
Return ONLY JSON: {"skills": [{"skill_id": ..., "name": ..., "description": ..., "key_concepts": [...]}]}.
"""

SKILL_EXTRACTION_USER_TEMPLATE = """Course: {course_id}\nLesson: {lesson_id}\nMaximum skills (upper bound only — you decide the actual number from the topics): {max_skills}\n\n--- LESSON CONTEXT ---\n{context}\n--- END CONTEXT ---"""

SKILL_EXPLANATION_SYSTEM = """You are Sahlha. Write 150-300 word student explanation of ONE skill, grounded ONLY in context.
Structure: intro, how it works, example from material, common mistake.
Return ONLY JSON: {"explanation": "..."}.
"""

SKILL_EXPLANATION_USER_TEMPLATE = """Course: {course_id}\nLesson: {lesson_id}\nSkill: {name} ({skill_id})\nDescription: {description}\nKey concepts: {concepts}\n\n--- SKILL MATERIAL ---\n{context}\n--- END MATERIAL ---"""


def build_skill_extraction_prompt(*, course_id: str, lesson_id: str,
                                  context_chunks: list[dict], max_skills: int = 6) -> tuple[str, str]:
    from sahlha.app.config import settings

    context = "\n\n".join(f"[chunk {c.get('chunk_id', i)}] {c.get('text', '')}"
                          for i, c in enumerate(context_chunks)) or "(no context retrieved)"
    return SKILL_EXTRACTION_SYSTEM, SKILL_EXTRACTION_USER_TEMPLATE.format(
        course_id=course_id, lesson_id=lesson_id, max_skills=max_skills, context=context[:settings.llm_max_context_chars])


def build_skill_explanation_prompt(*, course_id: str, lesson_id: str, skill: dict,
                                   context_chunks: list[dict]) -> tuple[str, str]:
    from sahlha.app.config import settings

    context = "\n\n".join(f"[chunk {c.get('chunk_id', i)}] {c.get('text', '')}"
                          for i, c in enumerate(context_chunks)) or "(no context retrieved)"
    return SKILL_EXPLANATION_SYSTEM, SKILL_EXPLANATION_USER_TEMPLATE.format(
        course_id=course_id, lesson_id=lesson_id, name=skill.get("name", skill.get("skill_id")),
        skill_id=skill.get("skill_id"), description=skill.get("description", ""),
        concepts=", ".join(skill.get("key_concepts", [])), context=context[:settings.llm_skill_context_chars])


LESSON_EXPLANATION_SYSTEM = """You are Sahlha. Write lesson overview grounded ONLY in context.
Structure: what lesson is about (2-3s), main ideas in order, how skills connect, outcome. Plus 4-8 key_concepts.
Return ONLY JSON: {"title": "...", "explanation": "...", "key_concepts": [...]}.
"""

LESSON_EXPLANATION_USER_TEMPLATE = """Course: {course_id}\nLesson: {lesson_id}\nSkills in this lesson: {skills}\n\n--- LESSON MATERIAL ---\n{context}\n--- END MATERIAL ---"""


def build_lesson_explanation_prompt(*, course_id: str, lesson_id: str,
                                    context_chunks: list[dict],
                                    skill_names: list[str] | None = None) -> tuple[str, str]:
    from sahlha.app.config import settings

    context = "\n\n".join(f"[chunk {c.get('chunk_id', i)}] {c.get('text', '')}"
                          for i, c in enumerate(context_chunks)) or "(no context retrieved)"
    return LESSON_EXPLANATION_SYSTEM, LESSON_EXPLANATION_USER_TEMPLATE.format(
        course_id=course_id, lesson_id=lesson_id,
        skills=", ".join(skill_names or []) or "(skills not extracted yet)",
        context=context[:settings.llm_max_context_chars])


CRITIQUE_SYSTEM = """You are Sahlha critic. For each question judge: grounded (answerable only from material?), answer_correct, issue (1 sentence or "").
Return ONLY JSON: {"verdicts": [{"index":0,"grounded":true,"answer_correct":true,"issue":""}]} one per question in order.
"""

CRITIQUE_USER_TEMPLATE = """--- LESSON MATERIAL ---\n{context}\n--- END MATERIAL ---\n\n--- DRAFTED QUESTIONS (JSON) ---\n{questions}\n--- END QUESTIONS ---"""


def build_critique_prompt(*, context_chunks: list[dict], questions: list[dict]) -> tuple[str, str]:
    import json as _json

    from sahlha.app.config import settings

    context = "\n\n".join(f"[chunk {c.get('chunk_id', i)}] {c.get('text', '')}"
                          for i, c in enumerate(context_chunks)) or "(no context retrieved)"
    # Critique disabled by default — keep prompt short when enabled
    return CRITIQUE_SYSTEM, CRITIQUE_USER_TEMPLATE.format(
        context=context[:settings.llm_skill_context_chars], questions=_json.dumps(questions)[:6000])
