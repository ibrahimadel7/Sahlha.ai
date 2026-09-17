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

from concurrent.futures import ThreadPoolExecutor

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
from sahlha.app.agent.schemas import (
    GeneratedQuestion,
    GroundedQuestion,
    GroundedSkillList,
    LessonExplanationModel,
    SkillExplanation,
    SkillList,
)
from sahlha.app.agent.state import AgentState, Phase
from sahlha.app.agent.tools import assessment_tools, question_tools, rag_tools, skill_tools, student_tools
from sahlha.app.database.repositories import repositories as repo


def _generate_bank_draft(job: dict) -> tuple[list[dict], str, dict, list[dict]]:
    """Worker-thread half of bank generation: LLM generation + critique (pure, no DB access).

    Thread-safe: touches only the per-skill `job` dict and module-level LLM clients.
    Returns (questions, backend, crit_info, verdicts).
    """
    from sahlha.app.agent.llm import critique_questions as _critique
    from sahlha.app.agent.prompts import build_critique_prompt as _crit_prompt
    from sahlha.app.config import settings as _s

    questions, backend = generate_questions_llm(
        job["system"], job["user"], job["chunks"], job["skill_id"],
        job["n_questions"], job["effective_feedback"])
    # App-side control: the bank's skill is authoritative (one bank per skill).
    for q in questions:
        q["skill_id"] = job["skill_id"]
    # FEEDBACK LOOP 1 — self-critique: deterministic by default (saves ~50% tokens).
    # LLM critique is opt-in via ENABLE_LLM_CRITIQUE=1 for high-stakes banks.
    if _s.enable_llm_critique and len(questions) >= 4:
        csys, cuser = _crit_prompt(context_chunks=job["chunks"], questions=questions)
        verdicts, crit_backend = _critique(csys, cuser, questions, job["chunks"])
    else:
        from sahlha.app.agent.llm import fallback_critique as _fc

        verdicts, crit_backend = _fc(questions, job["chunks"]), "deterministic"
    # A verdict fails when ungrounded, wrong answer, OR pedagogically irrelevant
    # (e.g. metadata/trivia). Missing 'relevant' defaults to True for backwards compat.
    bad = {v["index"] for v in verdicts
           if not (v.get("grounded", True) and v.get("answer_correct", True)
                   and v.get("relevant", True))}
    crit_info = {"backend": crit_backend, "dropped": sorted(bad),
                 "issues": [v["issue"] for v in verdicts if v["issue"]]}
    return questions, backend, crit_info, verdicts


class SahlhaAgent:
    def __init__(self, db: Session, state: AgentState | None = None):
        self.db = db
        self.state = state or AgentState()

    # ---------- SKILL EXTRACTION + EXPLANATION ----------
    def extract_skills(self, *, course_id: str, lesson_id: str, max_skills: int = 6,
                       force: bool = False, n_skills: int | None = None) -> dict:
        """Split a lesson into skills (one per topic; the AGENT decides how many).

        Mandatory RAG flow (no parallel raw-text path):
          retrieve_lesson -> generate (LLM or deterministic fallback, SAME chunks)
          -> attach evidence (SAME chunks, no re-retrieval)
          -> schema validation -> grounding validation -> persist accepted.

        Empty retrieval is an explicit failure state (no fabrication). Total
        grounding failure triggers ONE bounded fallback attempt, never a loop.
        Idempotent unless force=True. `max_skills` is only an upper-bound cap.
        `n_skills` is a deprecated alias kept for backwards compatibility.
        """
        from sahlha.app.agent import grounding as _g

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

        # Single retrieval for this workflow; reused by generation + validation.
        chunks = rag_tools.retrieve_lesson(self.db, course_id, lesson_id, top_k=5)
        st.log("tool:retrieve_lesson", {
            "num_chunks": len(chunks),
            "chunk_ids": [c.get("chunk_id") for c in chunks],
        })
        if not chunks:
            st.log("validation:empty_retrieval", {
                "course_id": course_id, "lesson_id": lesson_id,
                "error": "no RAG chunks for lesson; refusing to fabricate skills",
            })
            st.skills = []
            return {"skills": [], "backend": "empty-retrieval", "trace": st.trace,
                    "status": "failed",
                    "error": f"No material found for {course_id}/{lesson_id}. Upload a document first.",
                    "dropped": [], "retrieved_chunks": 0}

        # Lesson classification (once per lesson, reused by every skill image):
        # deterministic, from THE SAME retrieved chunks — no extra retrieval,
        # no LLM call. The category id is persisted on the lesson row so the
        # image tool receives it instead of rediscovering it per skill.
        from sahlha.app.lesson_categories import classify_lesson as _classify
        lesson_category = _classify(
            lesson_id=lesson_id, course_id=course_id,
            text=" ".join(c.get("text", "") for c in chunks)[:6000])
        try:
            repo.upsert_lesson_explanation(self.db, course_id=course_id, lesson_id=lesson_id,
                                           category=lesson_category["category_id"])
        except Exception as exc:
            # Classification must never break extraction; the image tool falls
            # back to on-the-fly classification. Logged, never silent.
            st.log("lesson:classify_persist_failed", {"error": str(exc)[:200]})
        st.log("lesson:classify", {"category": lesson_category["category_id"],
                                   "scores": {k: v for k, v in
                                              lesson_category["scores"].items() if v}})

        system, user = build_skill_extraction_prompt(course_id=course_id, lesson_id=lesson_id,
                                                     context_chunks=chunks, max_skills=max_skills)
        try:
            data, backend = complete_json(system, user)
            validated = SkillList(skills=data["skills"] if isinstance(data, dict) else data).skills
            raw = [s.model_dump() for s in validated]
        except RuntimeError:
            raw, backend = fallback_skills(chunks, lesson_id, max_skills), "fallback(no-api-key)"
        except Exception as exc:
            # Schema failure (malformed LLM JSON) also fails soft to the grounded
            # fallback once here; per-item grounding below handles the rest.
            st.log("validation:schema_failed", {"stage": "skill_raw", "error": str(exc)[:500]})
            raw, backend = fallback_skills(chunks, lesson_id, max_skills), f"fallback(llm-error: {exc})"
        st.log("llm:extract_skills", {"backend": backend, "count": len(raw)})

        accepted, rejected = self._ground_skills(raw, chunks, course_id, lesson_id)
        # Bounded retry: if the LLM path grounded nothing, try the deterministic
        # fallback once (same chunks, no extra retrieval). No further loops.
        if not accepted and not backend.startswith("fallback"):
            st.log("validation:skill_grounding_empty", {
                "backend": backend, "dropped": rejected,
                "retry": "fallback-once",
            })
            fb_raw = fallback_skills(chunks, lesson_id, max_skills)
            accepted, rejected = self._ground_skills(fb_raw, chunks, course_id, lesson_id)
            if accepted:
                backend = f"{backend}+fallback-retry"
        if rejected:
            st.log("validation:skill_grounding", {
                "accepted": len(accepted), "dropped": rejected,
            })

        skills = []
        for s in accepted[: max(1, max_skills)]:
            # Skill tool persists provenance; explanation/media come later.
            skills.append(skill_tools.register_skill(self.db, course_id=course_id,
                                                     lesson_id=lesson_id, skill_data=s))
        st.skills = skills
        out: dict = {"skills": skills, "backend": backend, "trace": st.trace,
                     "dropped": rejected, "retrieved_chunks": len(chunks)}
        if not skills:
            out["status"] = "failed"
            out["error"] = "No grounded skills could be extracted from the retrieved material."
        return out

    @staticmethod
    def _ground_skills(raw: list[dict], chunks: list[dict],
                       course_id: str, lesson_id: str) -> tuple[list[dict], list[dict]]:
        """Enrich raw skills with evidence (same chunks) then schema+grounding validate."""
        from sahlha.app.agent import grounding as _g

        enriched = _g.attach_skill_evidence(raw or [], chunks or [])
        # Strict schema first: missing/wrong-typed grounding fields fail here.
        strict: list[dict] = []
        rejected: list[dict] = []
        for s in enriched:
            try:
                strict.append(GroundedSkillList(skills=[s]).skills[0].model_dump())
            except Exception as exc:
                rejected.append({"skill_id": (s or {}).get("skill_id", "?"),
                                 "reasons": [f"schema: {exc}"]})
        accepted, ground_rejected = _g.partition_skills(strict, chunks or [], course_id, lesson_id)
        return accepted, rejected + ground_rejected

    def explain_skills(self, *, course_id: str, lesson_id: str, force: bool = False,
                       include_media: bool = True) -> dict:
        """Agent writes a grounded explanation for every skill of the lesson.

        With include_media=False explanations are persisted immediately and audio/images
        are left for lazy on-demand generation (fast path for bulk flows like extract-skills).
        """
        st = self.state
        st.transition(Phase.SKILL_EXPLANATION)
        rows = repo.list_skills(self.db, course_id=course_id, lesson_id=lesson_id)
        out = []
        # Phase 1 (main thread — owns the DB session): retrieval + prompt building.
        jobs: list[tuple] = []
        for row in rows:
            if row.explanation and not force:
                # Chain: skill tool -> explanation tool -> audio/image tools (fills gaps).
                skill = self._skill_to_dict(row)
                if include_media:
                    skill["media"] = skill_tools.skill_media(self.db, course_id=course_id,
                                                             lesson_id=lesson_id, skill_id=row.skill_id)
                else:
                    skill["media"] = {"image": {"status": "skipped", "reason": "deferred"},
                                      "audio": {"status": "skipped", "reason": "deferred"}}
                st.log("media:skill", {"skill_id": row.skill_id, "media": skill["media"]})
                out.append(skill)
                continue
            skill = self._skill_to_dict(row)
            chunks = rag_tools.retrieve_relevant_material(
                self.db, f"{skill['name']} {skill['description']} {' '.join(skill['key_concepts'])}",
                top_k=3, course_id=course_id, lesson_id=lesson_id)
            system, user = build_skill_explanation_prompt(course_id=course_id, lesson_id=lesson_id,
                                                          skill=skill, context_chunks=chunks)
            jobs.append((skill, chunks, system, user))
        # Phase 2 (worker threads — pure network LLM calls, no DB access): fan out so
        # N skills cost ~1 LLM round-trip instead of N sequential ones (~5s each).
        if jobs:
            def _generate(job: tuple) -> tuple:
                skill, chunks, system, user = job
                try:
                    data, backend = complete_json(system, user)
                    text = SkillExplanation(explanation=(data.get("explanation") if isinstance(data, dict) else data)).explanation
                except RuntimeError:
                    text, backend = fallback_explanation(skill, chunks), "fallback(no-api-key)"
                except Exception as exc:
                    text, backend = fallback_explanation(skill, chunks), f"fallback(llm-error: {exc})"
                return skill, text, backend

            with ThreadPoolExecutor(max_workers=min(6, len(jobs))) as pool:
                generated = list(pool.map(_generate, jobs))
        else:
            generated = []
        # Phase 3 (main thread): persist, then reassemble in skill order.
        by_id: dict[str, dict] = {s["skill_id"]: s for s in out}
        for skill, text, backend in generated:
            st.log("llm:explain_skill", {"skill_id": skill["skill_id"], "backend": backend})
            # Chain: skill tool -> explanation tool -> audio + image tools.
            bundle = skill_tools.setup_skill(self.db, course_id=course_id, lesson_id=lesson_id,
                                             skill_id=skill["skill_id"], explanation_text=text,
                                             include_media=include_media)
            st.log("media:skill", {"skill_id": skill["skill_id"], "media": bundle["media"]})
            by_id[skill["skill_id"]] = bundle
        out = [by_id[row.skill_id] for row in rows]
        st.skills = out
        return {"skills": out, "trace": st.trace}

    def explain_lesson(self, *, course_id: str, lesson_id: str, force: bool = False,
                       include_media: bool = True) -> dict:
        """Agent writes one grounded overview explanation for the whole lesson.

        Persistence + audio fan-out go through the explanation tool:
        explanation tool -> audio tool.
        With include_media=False the overview is persisted immediately and audio is
        left for lazy on-demand generation (fast path for bulk flows like extract-skills).
        """
        from sahlha.app.agent.tools import explanation_tools as _expl_tools

        st = self.state
        st.transition(Phase.LESSON_EXPLANATION)
        if not force:
            existing = repo.get_lesson_explanation(self.db, course_id=course_id, lesson_id=lesson_id)
            if existing and existing.explanation:
                st.log("lesson_explanation:existing", {"lesson_id": lesson_id})
                lesson = self._lesson_to_dict(existing)
                if include_media:
                    lesson["media"] = _expl_tools.ensure_lesson_media(self.db, course_id=course_id,
                                                                      lesson_id=lesson_id)
                else:
                    lesson["media"] = {"audio": {"status": "skipped", "reason": "deferred"}}
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
                                         key_concepts=payload.get("key_concepts", []),
                                         include_media=include_media)
        lesson = {**res["lesson"], "media": res["media"]}
        st.log("media:lesson", {"lesson_id": lesson_id, "media": lesson["media"]})
        return {"lesson": lesson, "backend": backend, "trace": st.trace}

    @staticmethod
    def _lesson_to_dict(row) -> dict:
        return {"id": row.id, "course_id": row.course_id, "lesson_id": row.lesson_id,
                "title": row.title, "explanation": row.explanation,
                "key_concepts": row.key_concepts or [],
                "category": getattr(row, "category", "") or ""}

    def generate_lesson_banks(self, *, course_id: str, lesson_id: str,
                              teacher_feedback: str = "", n_questions: int = 6) -> dict:
        """One question bank per skill of the lesson (skills extracted/explained first if missing)."""
        st = self.state
        if not repo.list_skills(self.db, course_id=course_id, lesson_id=lesson_id):
            self.extract_skills(course_id=course_id, lesson_id=lesson_id)
            # Banks don't need media: persist explanations now, audio/images fill in lazily.
            self.explain_skills(course_id=course_id, lesson_id=lesson_id, include_media=False)
        rows = repo.list_skills(self.db, course_id=course_id, lesson_id=lesson_id)
        # Phase 1 (main thread — owns the DB session): per-skill retrieval + prompt building.
        jobs = [self._prepare_bank_job(course_id=course_id, lesson_id=lesson_id,
                                       skill_id=row.skill_id, teacher_feedback=teacher_feedback,
                                       n_questions=n_questions) for row in rows]
        for job in jobs:
            st.log("tool:retrieve_skill_material",
                   {"skill_id": job["skill_id"], "num_chunks": len(job["chunks"]),
                    "chunk_ids": [c.get("chunk_id") for c in job["chunks"]]})
            if job["prior_flag_count"]:
                st.log("feedback:prior_flags", {"count": job["prior_flag_count"]})
        # Phase 2 (worker threads — pure LLM/critique calls, no DB access): fan out so
        # N skills cost ~1 LLM round-trip instead of N sequential ones (~5s each live).
        if jobs:
            with ThreadPoolExecutor(max_workers=min(6, len(jobs))) as pool:
                drafts = list(pool.map(_generate_bank_draft, jobs))
        else:
            drafts = []
        # Phase 3 (main thread): critique + schema + grounding (same chunks,
        # no re-retrieval) + persist in skill order (deterministic).
        banks = []
        for job, (questions, backend, crit_info, verdicts) in zip(jobs, drafts):
            st.course_id, st.lesson_id, st.skill_id = course_id, lesson_id, job["skill_id"]
            st.transition(Phase.QUESTION_GENERATION)
            st.retrieved_context = job["chunks"]
            st.log("llm:generate_questions", {"backend": backend, "num_questions": len(questions)})
            st.log("llm:critique_questions", crit_info)
            if not job["chunks"]:
                st.log("validation:empty_retrieval", {
                    "skill_id": job["skill_id"],
                    "error": "no RAG chunks; refusing to fabricate questions",
                })
                backend = "empty-retrieval"
                ground_info: dict = {"dropped_critique": [], "dropped_schema": [],
                                     "dropped_grounding": [], "topped_up": 0}
                questions = []
            else:
                questions, ground_info = self._finalize_bank_questions(job, questions, verdicts)
            saved = question_tools.save_questions(
                self.db, course_id=course_id, lesson_id=lesson_id, skill_id=job["skill_id"],
                questions=questions, teacher_feedback=job["effective_feedback"])
            st.log("tool:save_questions", saved)
            st.transition(Phase.WAITING_FOR_TEACHER)
            banks.append({**saved, "backend": backend, "trace": st.trace,
                          "retrieved_chunks": len(job["chunks"]),
                          "grounding": ground_info})
        return {"lesson_id": lesson_id, "num_skills": len(banks), "banks": banks, "trace": st.trace}

    @staticmethod
    def _skill_to_dict(s) -> dict:
        from sahlha.app.agent.tools import skill_tools as _skill_tools

        return _skill_tools._to_dict(s)

    # ---------- QUESTION GENERATION (per skill) ----------
    def _prepare_bank_job(self, *, course_id: str, lesson_id: str, skill_id: str,
                          teacher_feedback: str = "", n_questions: int = 8) -> dict:
        """Main-thread half of bank generation: retrieval + feedback + prompt (owns the DB session)."""
        # Skill-focused retrieval: prefer chunks for this skill, back off to the lesson.
        chunks = rag_tools.retrieve_relevant_material(self.db, f"{skill_id} {lesson_id} key concepts examples",
                                                      top_k=4, course_id=course_id,
                                                      lesson_id=lesson_id, skill_id=skill_id)
        if not chunks:
            chunks = rag_tools.retrieve_lesson(self.db, course_id, lesson_id, top_k=4)

        # FEEDBACK LOOP 2 — prior teacher flags on this skill steer the new version.
        prior_flags = repo.get_flag_reasons_for_skill(self.db, course_id=course_id,
                                                      lesson_id=lesson_id, skill_id=skill_id)
        effective_feedback = teacher_feedback
        if prior_flags:
            effective_feedback = (teacher_feedback + "\nPrior teacher flags to avoid repeating: "
                                  + " | ".join(dict.fromkeys(prior_flags))).strip()

        system, user = build_question_prompt(course_id=course_id, lesson_id=lesson_id,
                                             skill_id=skill_id, context_chunks=chunks,
                                             feedback=effective_feedback, n=n_questions)
        return {"skill_id": skill_id, "chunks": chunks, "system": system, "user": user,
                "effective_feedback": effective_feedback,
                "prior_flag_count": len(prior_flags), "n_questions": n_questions}

    def _top_up_bank_questions(self, job: dict, questions: list[dict],
                               verdicts: list[dict]) -> list[dict]:
        """Apply critique verdicts; top up dropped items with grounded replacements.

        Thin wrapper kept for backwards compat: full pipeline (critique +
        schema + RAG grounding, one bounded top-up reusing job['chunks']) lives
        in _finalize_bank_questions. No extra retrieval happens here.
        """
        questions, _info = self._finalize_bank_questions(job, questions, verdicts)
        return questions

    def _finalize_bank_questions(
        self, job: dict, questions: list[dict], verdicts: list[dict]
    ) -> tuple[list[dict], dict]:
        """Critique filter -> schema filter -> RAG grounding -> ONE top-up.

        All steps reuse ``job['chunks']`` (the single retrieval for this bank).
        Returns (accepted_questions, info{dropped_critique, dropped_schema,
        dropped_grounding, topped_up}).
        """
        from sahlha.app.agent import grounding as _g
        from sahlha.app.agent.llm import fallback_questions as _fallback_q

        st = self.state
        course_id = st.course_id
        lesson_id = st.lesson_id
        skill_id = job["skill_id"]
        chunks = job["chunks"] or []

        bad = {v["index"] for v in verdicts
               if not (v.get("grounded", True) and v.get("answer_correct", True)
                       and v.get("relevant", True))}
        kept = [q for i, q in enumerate(questions or []) if i not in bad]
        dropped_critique = sorted(bad)

        # Stage A: raw schema per-item (malformed LLM output is dropped, not saved).
        raw_valid: list[dict] = []
        dropped_schema: list[dict] = []
        for i, q in enumerate(kept):
            try:
                dump = GeneratedQuestion(**(q or {})).model_dump()
            except Exception as exc:
                dropped_schema.append({"index": i, "reasons": [f"schema: {exc}"]})
                continue
            # Per-item duplicate-options check (list-level QuestionList also
            # enforces this at save time; here we isolate the bad item).
            if dump.get("type") == "multiple_choice":
                lowered = [str(o or "").strip().lower() for o in dump.get("options", [])]
                if len(set(lowered)) != len(lowered):
                    dropped_schema.append({"index": i, "reasons": ["schema: duplicate options"]})
                    continue
            raw_valid.append(dump)
        # Bank-level exact duplicates: keep first, drop rest (observable).
        # Rotation variants (same stem, different option order) are allowed.
        def _qkey(q: dict) -> tuple:
            norm = " ".join(str(q.get("question", "")).strip().lower().split())
            opts = tuple(str(o or "").strip().lower() for o in (q.get("options", []) or []))
            return (norm, opts, str(q.get("correct_answer")))

        _seen: set[tuple] = set()
        _deduped: list[dict] = []
        for q in raw_valid:
            key = _qkey(q)
            if key in _seen:
                dropped_schema.append({"skill_id": q.get("skill_id", "?"),
                                       "reasons": ["schema: duplicate question in bank"]})
                continue
            _seen.add(key)
            _deduped.append(q)
        raw_valid = _deduped

        # Stage B: deterministic provenance + strict schema + RAG grounding.
        enriched = _g.attach_question_evidence(raw_valid, chunks)
        strict_valid: list[dict] = []
        for q in enriched:
            try:
                strict_valid.append(GroundedQuestion(**q).model_dump())
            except Exception as exc:
                dropped_schema.append({"skill_id": q.get("skill_id", "?"),
                                       "reasons": [f"grounded-schema: {exc}"]})
        valid_skills = {skill_id}
        accepted, dropped_grounding = _g.partition_questions(
            strict_valid, chunks, valid_skills, course_id, lesson_id)

        # Bounded regeneration: ONE deterministic top-up with the SAME chunks.
        topped_up = 0
        if len(accepted) < job["n_questions"] and chunks:
            need = job["n_questions"] - len(accepted)
            top_up = _fallback_q(chunks, skill_id, need, job["effective_feedback"])
            for q in top_up:
                q["skill_id"] = skill_id
            # Validate top-ups through the same pipeline (no further top-ups).
            tu_raw: list[dict] = []
            for q in top_up:
                try:
                    tu_raw.append(GeneratedQuestion(**q).model_dump())
                except Exception as exc:
                    dropped_schema.append({"skill_id": skill_id,
                                           "reasons": [f"topup-schema: {exc}"]})
            tu_enriched = _g.attach_question_evidence(tu_raw, chunks)
            tu_strict: list[dict] = []
            for q in tu_enriched:
                try:
                    tu_strict.append(GroundedQuestion(**q).model_dump())
                except Exception as exc:
                    dropped_schema.append({"skill_id": skill_id,
                                           "reasons": [f"topup-grounded-schema: {exc}"]})
            tu_accepted, tu_rejected = _g.partition_questions(
                tu_strict, chunks, valid_skills, course_id, lesson_id)
            dropped_grounding.extend(tu_rejected)
            # Final bank-level exact-dedup across original + top-up.
            def _qkey2(q: dict) -> tuple:
                norm = " ".join(str(q.get("question", "")).strip().lower().split())
                opts = tuple(str(o or "").strip().lower() for o in (q.get("options", []) or []))
                return (norm, opts, str(q.get("correct_answer")))

            _have = {_qkey2(q) for q in accepted}
            _before = len(accepted)
            for q in tu_accepted[:need]:
                key = _qkey2(q)
                if key in _have:
                    dropped_schema.append({"skill_id": skill_id,
                                           "reasons": ["schema: duplicate question in bank (top-up)"]})
                    continue
                _have.add(key)
                accepted.append(q)
            topped_up = len(accepted) - _before
            if topped_up:
                st.log("feedback:top_up", {"added": topped_up})

        info = {"dropped_critique": dropped_critique,
                "dropped_schema": dropped_schema,
                "dropped_grounding": dropped_grounding,
                "topped_up": topped_up}
        if dropped_schema:
            st.log("validation:question_schema", {"dropped": dropped_schema})
        if dropped_grounding:
            st.log("validation:question_grounding", {"dropped": dropped_grounding})
        return accepted, info

    def generate_question_bank(self, *, course_id: str, lesson_id: str, skill_id: str,
                               teacher_feedback: str = "", n_questions: int = 8,
                               student_id: str = "", teacher_id: str = "teacher_1") -> dict:
        st = self.state
        st.course_id, st.lesson_id, st.skill_id = course_id, lesson_id, skill_id
        st.student_id, st.teacher_id = student_id, teacher_id
        st.transition(Phase.QUESTION_GENERATION)

        job = self._prepare_bank_job(course_id=course_id, lesson_id=lesson_id, skill_id=skill_id,
                                     teacher_feedback=teacher_feedback, n_questions=n_questions)
        st.retrieved_context = job["chunks"]
        st.log("tool:retrieve_skill_material", {"skill_id": skill_id, "num_chunks": len(job["chunks"]),
                                                "chunk_ids": [c.get("chunk_id") for c in job["chunks"]]})
        if job["prior_flag_count"]:
            st.log("feedback:prior_flags", {"count": job["prior_flag_count"]})

        if not job["chunks"]:
            st.log("validation:empty_retrieval", {
                "skill_id": skill_id,
                "error": "no RAG chunks for skill/lesson; refusing to fabricate questions",
            })
            saved = question_tools.save_questions(
                self.db, course_id=course_id, lesson_id=lesson_id, skill_id=skill_id,
                questions=[], teacher_feedback=job["effective_feedback"])
            st.log("tool:save_questions", saved)
            st.transition(Phase.WAITING_FOR_TEACHER)
            return {**saved, "backend": "empty-retrieval", "trace": st.trace,
                    "retrieved_chunks": 0, "status": "failed",
                    "error": "No retrieved material for this skill; bank is empty.",
                    "grounding": {"dropped_critique": [], "dropped_schema": [],
                                  "dropped_grounding": [], "topped_up": 0}}

        questions, backend, crit_info, verdicts = _generate_bank_draft(job)
        st.log("llm:generate_questions", {"backend": backend, "num_questions": len(questions)})
        # App-side control: the bank's skill is authoritative (one bank per skill).
        for q in questions:
            q["skill_id"] = skill_id
        st.log("llm:critique_questions", crit_info)
        questions, ground_info = self._finalize_bank_questions(job, questions, verdicts)

        saved = question_tools.save_questions(self.db, course_id=course_id, lesson_id=lesson_id,
                                              skill_id=skill_id, questions=questions,
                                              teacher_feedback=job["effective_feedback"])
        st.log("tool:save_questions", saved)
        st.transition(Phase.WAITING_FOR_TEACHER)
        out: dict = {**saved, "backend": backend, "trace": st.trace,
                     "retrieved_chunks": len(job["chunks"]), "grounding": ground_info}
        if not questions:
            out["status"] = "failed"
            out["error"] = "All drafted questions failed grounding validation; bank is empty."
        return out

    # ---------- ASSESSMENT ----------
    def start_assessment(self, *, student_id: str, course_id: str | None = None,
                         lesson_id: str | None = None, skill_id: str | None = None) -> dict:
        st = self.state
        st.student_id = student_id
        st.transition(Phase.ASSESSMENT)
        repo.get_or_create_student(self.db, student_id)

        history = student_tools.get_student_history(self.db, student_id)
        perf = student_tools.get_student_skill_performance(self.db, student_id)
        st.student_memory = {"history_count": len(history), "performance": perf,
                             "failed": student_tools.get_failed_questions(self.db, student_id)}
        st.log("tool:get_student_history", st.student_memory)

        # select_questions loads the approved pool once (no duplicate query here).
        selected, meta = assessment_tools.select_questions(self.db, student_id=student_id,
                                                           course_id=course_id, lesson_id=lesson_id,
                                                           skill_id=skill_id)
        # Strict boundary: selection must be duplicate-free with valid ids.
        _ids = [q.get("id", "") for q in selected]
        if len(set(_ids)) != len(_ids) or any(not i for i in _ids):
            raise ValueError("Invalid question selection: duplicate or missing question ids")
        if any(not q.get("bank_id") or not q.get("skill_id") for q in selected):
            raise ValueError("Invalid question selection: missing bank_id/skill_id")
        st.log("tool:get_approved_questions", {"count": meta.get("pool_size", len(selected))})
        st.log("tool:select_questions", meta)
        st.current_question_ids = [q["id"] for q in selected]
        bank_id = selected[0]["bank_id"] if selected else ""
        # Multi-bank lineage: resolve dominant (course, lesson) BEFORE persisting,
        # so the assessment row records what was actually tested. Banks are loaded
        # once (not once per question per loop).
        bank_map = {b.id: b for b in repo.get_banks_by_ids(
            self.db, [q["bank_id"] for q in selected if q.get("bank_id")])}

        def _bank_of(q: dict):
            return bank_map.get(q.get("bank_id", ""))

        from collections import Counter as _Counter

        _pairs = [(b.course_id, b.lesson_id) for q in selected
                  if (_b := _bank_of(q)) is not None for b in [_b]]
        _course, _lesson = (_Counter(_pairs).most_common(1)[0][0] if _pairs
                            else (course_id or "general", lesson_id or "lesson_1"))
        assessment = repo.create_assessment(self.db, student_id=student_id,
                                            question_bank_id=bank_id,
                                            question_ids=st.current_question_ids,
                                            course_id=_course, lesson_id=_lesson)
        # Study-before-exercise: attach each covered skill's agent-written explanation.
        # Resolved via the question's bank (course/lesson) so the right skill row is used.
        # One skill lookup per distinct skill (not per question), slug fallback preserved.
        skill_cache: dict[tuple[str, str, str], object | None] = {}
        explanations: list[dict] = []
        seen_skills: set[str] = set()
        for q in selected:
            skid = q["skill_id"]
            if skid in seen_skills:
                continue
            seen_skills.add(skid)
            bank = _bank_of(q)
            row = None
            if bank is not None:
                key = (bank.course_id, bank.lesson_id, skid)
                if key not in skill_cache:
                    skill_cache[key] = repo.get_skill(self.db, course_id=bank.course_id,
                                                      lesson_id=bank.lesson_id, skill_id=skid)
                row = skill_cache[key]
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
        lesson_explanation: dict | None = None
        if _pairs:
            top_course, top_lesson = _Counter(_pairs).most_common(1)[0][0]
            row = repo.get_lesson_explanation(self.db, course_id=top_course, lesson_id=top_lesson)
            if row is not None and row.explanation:
                lesson_explanation = self._lesson_to_dict(row)
        st.log("tool:get_lesson_explanation",
               {"lesson": f"{top_course}/{top_lesson}" if _pairs else None,
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
        from sahlha.app.agent.schemas import SubmittedAnswers

        st = self.state
        st.transition(Phase.EVALUATION)
        assessment = repo.get_assessment(self.db, assessment_id)
        if not assessment:
            raise ValueError(f"Assessment {assessment_id} not found")
        if assessment.status == "submitted":
            raise ValueError(f"Assessment {assessment_id} already submitted")
        # Strict boundary: malformed submissions fail fast (observable 400/404),
        # never silently accepted. Missing answers are allowed (scored incorrect);
        # unknown question ids are rejected.
        try:
            clean_answers = SubmittedAnswers(answers=dict(answers or {})).answers
        except Exception as exc:
            raise ValueError(f"Invalid answer submission: {exc}") from exc
        expected = set(assessment.question_ids or [])
        unknown = sorted(set(clean_answers) - expected)
        if unknown:
            raise ValueError(f"Unknown question ids in submission: {unknown}")
        st.current_answers = clean_answers
        answers = clean_answers
        # Batch-load the assessment's questions + their banks up front: per-question
        # lookups plus a commit per row previously caused N commits and an expiry
        # cascade of re-SELECTs (measured: 17 commits / ~90 statements for 8 Qs).
        q_map = {q.id: q for q in repo.get_questions_by_ids(self.db, assessment.question_ids)}
        bank_map = {b.id: b for b in repo.get_banks_by_ids(
            self.db, [q.question_bank_id for q in q_map.values() if q.question_bank_id])}
        results: list[dict] = []
        for qid in assessment.question_ids:
            q = q_map.get(qid)
            if not q:
                continue
            qdict = {"id": q.id, "skill_id": q.skill_id, "type": q.question_type,
                     "correct_answer": q.correct_answer}
            res = assessment_tools.evaluate_answer(qdict, answers.get(qid))
            assessment_tools.record_attempt(self.db, student_id=assessment.student_id,
                                            question_id=qid, assessment_id=assessment_id,
                                            answer=answers.get(qid), correct=res["correct"],
                                            commit=False)
            # Scoped memory: resolve (course, lesson) from the question's bank so the
            # same skill slug in two lessons never shares counters.
            _qbank = bank_map.get(q.question_bank_id) if q.question_bank_id else None
            _cc = _qbank.course_id if _qbank else (getattr(assessment, "course_id", None) or "general")
            _ll = _qbank.lesson_id if _qbank else (getattr(assessment, "lesson_id", None) or "lesson_1")
            student_tools.update_student_memory(self.db, student_id=assessment.student_id,
                                                skill_id=q.skill_id, correct=res["correct"],
                                                course_id=_cc, lesson_id=_ll, commit=False)
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
