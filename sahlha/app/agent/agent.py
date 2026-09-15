"""Single Sahlha learning agent: explicit state-machine runtime.

Flow per phase:
  SKILL_EXTRACTION: retrieve_lesson -> LLM splits lesson into skills (persisted)
  SKILL_EXPLANATION: per skill, retrieve skill material -> LLM writes grounded explanation
  QUESTION_GENERATION: per skill, retrieve skill material -> LLM/fallback structured gen
      -> validate -> save_questions (one bank per skill) -> WAITING_FOR_TEACHER
  (teacher approves/rejects each bank via API — explicit workflow boundary, never auto-bypassed)
  ASSESSMENT: get_approved_questions + get_student_history -> select_questions (exactly 4)
  EVALUATION: evaluate_answer -> record_attempt -> update_student_memory -> ADAPTATION
"""
from __future__ import annotations

from sqlalchemy.orm import Session

from sahlha.app.agent.llm import (
    complete_json,
    fallback_explanation,
    fallback_lesson_explanation,
    fallback_skills,
    generate_questions_llm,
)
from sahlha.app.agent.prompts import (
    build_lesson_explanation_prompt,
    build_question_prompt,
    build_skill_explanation_prompt,
    build_skill_extraction_prompt,
)
from sahlha.app.agent.schemas import LessonExplanationModel, SkillExplanation, SkillList
from sahlha.app.agent.state import AgentState, Phase
from sahlha.app.agent.tools import assessment_tools, question_tools, rag_tools, skill_tools, student_tools
from sahlha.app.database.repositories import repositories as repo


class SahlhaAgent:
    def __init__(self, db: Session, state: AgentState | None = None):
        self.db = db
        self.state = state or AgentState()

    # ---------- SKILL EXTRACTION + EXPLANATION ----------
    def extract_skills(self, *, course_id: str, lesson_id: str, max_skills: int = 6,
                       force: bool = False, n_skills: int | None = None) -> dict:
        """Split a lesson into skills (one per topic; the AGENT decides how many).

        Idempotent unless force=True. `max_skills` is only an upper-bound safety cap.
        `n_skills` is a deprecated alias kept for backwards compatibility.
        """
        if n_skills is not None:
            max_skills = n_skills
        st = self.state
        st.course_id, st.lesson_id = course_id, lesson_id
        st.transition(Phase.SKILL_EXTRACTION)
        if not force:
            existing = repo.list_skills(self.db, course_id=course_id, lesson_id=lesson_id)
            if existing:
                skills = [self._skill_to_dict(s) for s in existing]
                st.skills = skills
                st.log("skills:existing", {"count": len(skills)})
                return {"skills": skills, "backend": "existing", "trace": st.trace}

        chunks = rag_tools.retrieve_lesson(self.db, course_id, lesson_id, top_k=5)
        st.log("tool:retrieve_lesson", {"num_chunks": len(chunks)})
        system, user = build_skill_extraction_prompt(course_id=course_id, lesson_id=lesson_id,
                                                     context_chunks=chunks, max_skills=max_skills)
        try:
            data, backend = complete_json(system, user)
            validated = SkillList(skills=data["skills"] if isinstance(data, dict) else data).skills
            raw = [s.model_dump() for s in validated]
        except RuntimeError:
            raw, backend = fallback_skills(chunks, lesson_id, max_skills), "fallback(no-api-key)"
        except Exception as exc:
            raw, backend = fallback_skills(chunks, lesson_id, max_skills), f"fallback(llm-error: {exc})"
        st.log("llm:extract_skills", {"backend": backend, "count": len(raw)})

        skills = []
        for s in raw[: max(1, max_skills)]:
            # Skill tool persists; explanation/media come later via setup_skill.
            skills.append(skill_tools.register_skill(self.db, course_id=course_id,
                                                     lesson_id=lesson_id, skill_data=s))
        st.skills = skills
        return {"skills": skills, "backend": backend, "trace": st.trace}

    def explain_skills(self, *, course_id: str, lesson_id: str, force: bool = False) -> dict:
        """Agent writes a grounded explanation for every skill of the lesson."""
        st = self.state
        st.transition(Phase.SKILL_EXPLANATION)
        rows = repo.list_skills(self.db, course_id=course_id, lesson_id=lesson_id)
        out = []
        for row in rows:
            if row.explanation and not force:
                # Chain: skill tool -> explanation tool -> audio/image tools (fills gaps).
                skill = self._skill_to_dict(row)
                skill["media"] = skill_tools.skill_media(self.db, course_id=course_id,
                                                         lesson_id=lesson_id, skill_id=row.skill_id)
                st.log("media:skill", {"skill_id": row.skill_id, "media": skill["media"]})
                out.append(skill)
                continue
            skill = self._skill_to_dict(row)
            chunks = rag_tools.retrieve_relevant_material(
                self.db, f"{skill['name']} {skill['description']} {' '.join(skill['key_concepts'])}",
                top_k=3, course_id=course_id, lesson_id=lesson_id)
            system, user = build_skill_explanation_prompt(course_id=course_id, lesson_id=lesson_id,
                                                          skill=skill, context_chunks=chunks)
            try:
                data, backend = complete_json(system, user)
                text = SkillExplanation(explanation=(data.get("explanation") if isinstance(data, dict) else data)).explanation
            except RuntimeError:
                text, backend = fallback_explanation(skill, chunks), "fallback(no-api-key)"
            except Exception as exc:
                text, backend = fallback_explanation(skill, chunks), f"fallback(llm-error: {exc})"
            st.log("llm:explain_skill", {"skill_id": skill["skill_id"], "backend": backend})
            # Chain: skill tool -> explanation tool -> audio + image tools.
            bundle = skill_tools.setup_skill(self.db, course_id=course_id, lesson_id=lesson_id,
                                             skill_id=skill["skill_id"], explanation_text=text)
            st.log("media:skill", {"skill_id": skill["skill_id"], "media": bundle["media"]})
            out.append(bundle)
        st.skills = out
        return {"skills": out, "trace": st.trace}

    def explain_lesson(self, *, course_id: str, lesson_id: str, force: bool = False) -> dict:
        """Agent writes one grounded overview explanation for the whole lesson.

        Persistence + audio fan-out go through the explanation tool:
        explanation tool -> audio tool.
        """
        from sahlha.app.agent.tools import explanation_tools as _expl_tools

        st = self.state
        st.transition(Phase.LESSON_EXPLANATION)
        if not force:
            existing = repo.get_lesson_explanation(self.db, course_id=course_id, lesson_id=lesson_id)
            if existing and existing.explanation:
                st.log("lesson_explanation:existing", {"lesson_id": lesson_id})
                lesson = self._lesson_to_dict(existing)
                lesson["media"] = _expl_tools.ensure_lesson_media(self.db, course_id=course_id,
                                                                  lesson_id=lesson_id)
                st.log("media:lesson", {"lesson_id": lesson_id, "media": lesson["media"]})
                return {"lesson": lesson, "backend": "existing", "trace": st.trace}
        chunks = rag_tools.retrieve_lesson(self.db, course_id, lesson_id, top_k=5)
        skill_names = [s.name or s.skill_id for s in
                       repo.list_skills(self.db, course_id=course_id, lesson_id=lesson_id)]
        system, user = build_lesson_explanation_prompt(course_id=course_id, lesson_id=lesson_id,
                                                       context_chunks=chunks,
                                                       skill_names=skill_names)
        try:
            data, backend = complete_json(system, user)
            validated = LessonExplanationModel(**(data if isinstance(data, dict) else {}))
            payload = validated.model_dump()
        except RuntimeError:
            payload = fallback_lesson_explanation(chunks, course_id, lesson_id, skill_names)
            backend = "fallback(no-api-key)"
        except Exception as exc:
            payload = fallback_lesson_explanation(chunks, course_id, lesson_id, skill_names)
            backend = f"fallback(llm-error: {exc})"
        st.log("llm:explain_lesson", {"backend": backend, "lesson_id": lesson_id})
        # Chain: explanation tool persists + calls the audio tool.
        res = _expl_tools.explain_lesson(self.db, course_id=course_id, lesson_id=lesson_id,
                                         title=payload.get("title", ""),
                                         explanation_text=payload.get("explanation", ""),
                                         key_concepts=payload.get("key_concepts", []))
        lesson = {**res["lesson"], "media": res["media"]}
        st.log("media:lesson", {"lesson_id": lesson_id, "media": lesson["media"]})
        return {"lesson": lesson, "backend": backend, "trace": st.trace}

    @staticmethod
    def _lesson_to_dict(row) -> dict:
        return {"id": row.id, "course_id": row.course_id, "lesson_id": row.lesson_id,
                "title": row.title, "explanation": row.explanation,
                "key_concepts": row.key_concepts or []}

    def generate_lesson_banks(self, *, course_id: str, lesson_id: str,
                              teacher_feedback: str = "", n_questions: int = 6) -> dict:
        """One question bank per skill of the lesson (skills extracted/explained first if missing)."""
        st = self.state
        if not repo.list_skills(self.db, course_id=course_id, lesson_id=lesson_id):
            self.extract_skills(course_id=course_id, lesson_id=lesson_id)
            self.explain_skills(course_id=course_id, lesson_id=lesson_id)
        banks = []
        for row in repo.list_skills(self.db, course_id=course_id, lesson_id=lesson_id):
            banks.append(self.generate_question_bank(
                course_id=course_id, lesson_id=lesson_id, skill_id=row.skill_id,
                teacher_feedback=teacher_feedback, n_questions=n_questions))
        return {"lesson_id": lesson_id, "num_skills": len(banks), "banks": banks, "trace": st.trace}

    @staticmethod
    def _skill_to_dict(s) -> dict:
        from sahlha.app.agent.tools import skill_tools as _skill_tools

        return _skill_tools._to_dict(s)

    # ---------- QUESTION GENERATION (per skill) ----------
    def generate_question_bank(self, *, course_id: str, lesson_id: str, skill_id: str,
                               teacher_feedback: str = "", n_questions: int = 8,
                               student_id: str = "", teacher_id: str = "teacher_1") -> dict:
        st = self.state
        st.course_id, st.lesson_id, st.skill_id = course_id, lesson_id, skill_id
        st.student_id, st.teacher_id = student_id, teacher_id
        st.transition(Phase.QUESTION_GENERATION)

        # Skill-focused retrieval: prefer chunks for this skill, back off to the lesson.
        chunks = rag_tools.retrieve_relevant_material(self.db, f"{skill_id} {lesson_id} key concepts examples",
                                                      top_k=4, course_id=course_id,
                                                      lesson_id=lesson_id, skill_id=skill_id)
        if not chunks:
            chunks = rag_tools.retrieve_lesson(self.db, course_id, lesson_id, top_k=4)
        st.retrieved_context = chunks
        st.log("tool:retrieve_skill_material", {"skill_id": skill_id, "num_chunks": len(chunks),
                                                "chunk_ids": [c.get("chunk_id") for c in chunks]})

        # FEEDBACK LOOP 2 — prior teacher flags on this skill steer the new version.
        prior_flags = repo.get_flag_reasons_for_skill(self.db, course_id=course_id,
                                                      lesson_id=lesson_id, skill_id=skill_id)
        if prior_flags:
            teacher_feedback = (teacher_feedback + "\nPrior teacher flags to avoid repeating: "
                                + " | ".join(dict.fromkeys(prior_flags))).strip()
            st.log("feedback:prior_flags", {"count": len(prior_flags)})

        system, user = build_question_prompt(course_id=course_id, lesson_id=lesson_id,
                                             skill_id=skill_id, context_chunks=chunks,
                                             feedback=teacher_feedback, n=n_questions)
        questions, backend = generate_questions_llm(system, user, chunks, skill_id, n_questions, teacher_feedback)
        st.log("llm:generate_questions", {"backend": backend, "num_questions": len(questions)})
        # App-side control: the bank's skill is authoritative (one bank per skill).
        for q in questions:
            q["skill_id"] = skill_id

        # FEEDBACK LOOP 1 — self-critique: deterministic by default (saves ~50% tokens).
        # LLM critique is opt-in via ENABLE_LLM_CRITIQUE=1 for high-stakes banks.
        from sahlha.app.agent.llm import critique_questions as _critique
        from sahlha.app.agent.prompts import build_critique_prompt as _crit_prompt
        from sahlha.app.config import settings as _s

        if _s.enable_llm_critique and len(questions) >= 4:
            csys, cuser = _crit_prompt(context_chunks=chunks, questions=questions)
            verdicts, crit_backend = _critique(csys, cuser, questions, chunks)
        else:
            from sahlha.app.agent.llm import fallback_critique as _fc

            verdicts, crit_backend = _fc(questions, chunks), "deterministic"
        bad = {v["index"] for v in verdicts if not (v["grounded"] and v["answer_correct"])}
        st.log("llm:critique_questions",
               {"backend": crit_backend, "dropped": sorted(bad),
                "issues": [v["issue"] for v in verdicts if v["issue"]]})
        questions = [q for i, q in enumerate(questions) if i not in bad]
        if len(questions) < n_questions:
            from sahlha.app.agent.llm import fallback_questions as _fallback_q

            top_up = _fallback_q(chunks, skill_id, n_questions - len(questions), teacher_feedback)
            for q in top_up:
                q["skill_id"] = skill_id
            questions.extend(top_up)
            st.log("feedback:top_up", {"added": len(top_up)})

        saved = question_tools.save_questions(self.db, course_id=course_id, lesson_id=lesson_id,
                                              skill_id=skill_id, questions=questions,
                                              teacher_feedback=teacher_feedback)
        st.log("tool:save_questions", saved)
        st.transition(Phase.WAITING_FOR_TEACHER)
        return {**saved, "backend": backend, "trace": st.trace,
                "retrieved_chunks": len(chunks)}

    # ---------- ASSESSMENT ----------
    def start_assessment(self, *, student_id: str, course_id: str | None = None,
                         lesson_id: str | None = None, skill_id: str | None = None) -> dict:
        st = self.state
        st.student_id = student_id
        st.transition(Phase.ASSESSMENT)
        repo.get_or_create_student(self.db, student_id)

        approved = question_tools.get_approved_questions(self.db, course_id=course_id,
                                                         lesson_id=lesson_id, skill_id=skill_id)
        st.log("tool:get_approved_questions", {"count": len(approved)})
        history = student_tools.get_student_history(self.db, student_id)
        perf = student_tools.get_student_skill_performance(self.db, student_id)
        st.student_memory = {"history_count": len(history), "performance": perf,
                             "failed": student_tools.get_failed_questions(self.db, student_id)}
        st.log("tool:get_student_history", st.student_memory)

        selected, meta = assessment_tools.select_questions(self.db, student_id=student_id,
                                                           course_id=course_id, lesson_id=lesson_id,
                                                           skill_id=skill_id)
        st.log("tool:select_questions", meta)
        st.current_question_ids = [q["id"] for q in selected]
        bank_id = selected[0]["bank_id"] if selected else ""
        # Multi-bank lineage: resolve dominant (course, lesson) BEFORE persisting,
        # so the assessment row records what was actually tested.
        from collections import Counter as _Counter

        _pairs = []
        for q in selected:
            _bank = repo.get_bank(self.db, q["bank_id"]) if q.get("bank_id") else None
            if _bank is not None:
                _pairs.append((_bank.course_id, _bank.lesson_id))
        _course, _lesson = (_Counter(_pairs).most_common(1)[0][0] if _pairs
                            else (course_id or "general", lesson_id or "lesson_1"))
        assessment = repo.create_assessment(self.db, student_id=student_id,
                                            question_bank_id=bank_id,
                                            question_ids=st.current_question_ids,
                                            course_id=_course, lesson_id=_lesson)
        # Study-before-exercise: attach each covered skill's agent-written explanation.
        # Resolved via the question's bank (course/lesson) so the right skill row is used.
        explanations: list[dict] = []
        seen_skills: set[str] = set()
        for q in selected:
            skid = q["skill_id"]
            if skid in seen_skills:
                continue
            seen_skills.add(skid)
            row = None
            bank = repo.get_bank(self.db, q["bank_id"]) if q.get("bank_id") else None
            if bank is not None:
                row = repo.get_skill(self.db, course_id=bank.course_id,
                                     lesson_id=bank.lesson_id, skill_id=skid)
            row = row or repo.get_skill_by_slug(self.db, skid)
            if row is not None:
                explanations.append({"skill_id": row.skill_id, "name": row.name,
                                     "description": row.description,
                                     "explanation": row.explanation,
                                     "key_concepts": row.key_concepts or []})
            else:
                explanations.append({"skill_id": skid, "name": skid, "description": "",
                                     "explanation": "", "key_concepts": []})
        st.log("tool:get_skill_explanations", {"skills": [e["skill_id"] for e in explanations]})
        # Lesson overview first: most common (course, lesson) among the selected banks.
        from collections import Counter

        pairs = []
        for q in selected:
            bank = repo.get_bank(self.db, q["bank_id"]) if q.get("bank_id") else None
            if bank is not None:
                pairs.append((bank.course_id, bank.lesson_id))
        lesson_explanation: dict | None = None
        if pairs:
            top_course, top_lesson = Counter(pairs).most_common(1)[0][0]
            row = repo.get_lesson_explanation(self.db, course_id=top_course, lesson_id=top_lesson)
            if row is not None and row.explanation:
                lesson_explanation = self._lesson_to_dict(row)
        st.log("tool:get_lesson_explanation",
               {"lesson": f"{top_course}/{top_lesson}" if pairs else None,
                "found": lesson_explanation is not None})
        # Student-facing payload must NOT include correct answers
        public = [{k: q[k] for k in ("id", "bank_id", "skill_id", "type", "question", "options", "difficulty")
                   if k in q} for q in selected]
        return {"assessment_id": assessment.id, "student_id": student_id,
                "questions": public, "lesson_explanation": lesson_explanation,
                "skill_explanations": explanations,
                "selection_meta": meta, "trace": st.trace}

    # ---------- EVALUATION ----------
    def submit_assessment(self, *, assessment_id: str, answers: dict[str, object]) -> dict:
        st = self.state
        st.transition(Phase.EVALUATION)
        assessment = repo.get_assessment(self.db, assessment_id)
        if not assessment:
            raise ValueError(f"Assessment {assessment_id} not found")
        if assessment.status == "submitted":
            raise ValueError(f"Assessment {assessment_id} already submitted")
        st.current_answers = answers
        results: list[dict] = []
        for qid in assessment.question_ids:
            q = self.db.get(repo.m.Question, qid)
            if not q:
                continue
            qdict = {"id": q.id, "skill_id": q.skill_id, "type": q.question_type,
                     "correct_answer": q.correct_answer}
            res = assessment_tools.evaluate_answer(qdict, answers.get(qid))
            assessment_tools.record_attempt(self.db, student_id=assessment.student_id,
                                            question_id=qid, assessment_id=assessment_id,
                                            answer=answers.get(qid), correct=res["correct"])
            # Scoped memory: resolve (course, lesson) from the question's bank so the
            # same skill slug in two lessons never shares counters.
            _qbank = repo.get_bank(self.db, q.question_bank_id) if q.question_bank_id else None
            _cc = _qbank.course_id if _qbank else (getattr(assessment, "course_id", None) or "general")
            _ll = _qbank.lesson_id if _qbank else (getattr(assessment, "lesson_id", None) or "lesson_1")
            student_tools.update_student_memory(self.db, student_id=assessment.student_id,
                                                skill_id=q.skill_id, correct=res["correct"],
                                                course_id=_cc, lesson_id=_ll)
            st.log("tool:record_attempt", {"question_id": qid, "correct": res["correct"]})
            results.append(res)
        correct = sum(1 for r in results if r["correct"])
        assessment.status = "submitted"
        assessment.score = correct / len(results) if results else 0.0
        self.db.commit()
        # FEEDBACK LOOP 3 — mastery signals: skills below 50% in this assessment need review
        # (re-study the explanation; teacher sees the same signal in skill-progress).
        by_skill: dict[str, list[bool]] = {}
        for r in results:
            by_skill.setdefault(r["skill_id"], []).append(r["correct"])
        skills_needing_review = sorted(
            skid for skid, vals in by_skill.items() if sum(vals) / len(vals) < 0.5)
        st.log("feedback:mastery", {"skills_needing_review": skills_needing_review})
        st.assessment_result = {"assessment_id": assessment_id, "score": assessment.score,
                                "correct": correct, "total": len(results), "results": results,
                                "skills_needing_review": skills_needing_review}
        st.transition(Phase.ADAPTATION)
        perf = student_tools.get_student_skill_performance(self.db, assessment.student_id)
        return {**st.assessment_result, "skill_performance": perf, "trace": st.trace}
