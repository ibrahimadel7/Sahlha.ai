"""Streamlit test client for the Sahlha MVP loop (NOT production UI)."""
from __future__ import annotations

import os

import requests
import streamlit as st

API = os.getenv("SAHLHA_API", "http://127.0.0.1:8000")

st.set_page_config(page_title="Sahlha MVP — Test Client", layout="wide")
st.title("Sahlha AI — MVP Test Client")


def _api_error(resp) -> str:
    """Human-readable error from a requests response (JSON detail or raw text)."""
    try:
        data = resp.json()
        if isinstance(data, dict) and "detail" in data:
            return str(data["detail"])
    except Exception:
        pass
    return (resp.text or f"HTTP {resp.status_code}")[:500]


def api_post(path: str, *, json=None, data=None, files=None, timeout=60):
    """POST helper: returns (ok, payload). Never raises on HTTP errors."""
    try:
        r = requests.post(f"{API}{path}", json=json, data=data, files=files, timeout=timeout)
    except requests.exceptions.Timeout:
        return False, f"Request timed out after {timeout}s — try a smaller file or retry."
    except Exception as exc:
        return False, f"Request failed: {exc}"
    if r.status_code != 200:
        return False, _api_error(r)
    try:
        return True, r.json()
    except Exception:
        return False, "Backend returned non-JSON response"


def api_get(path: str, *, params=None, timeout=30):
    """GET helper: returns (ok, payload). Never raises on HTTP errors."""
    try:
        r = requests.get(f"{API}{path}", params=params, timeout=timeout)
    except requests.exceptions.Timeout:
        return False, f"Request timed out after {timeout}s"
    except Exception as exc:
        return False, f"Request failed: {exc}"
    if r.status_code != 200:
        return False, _api_error(r)
    try:
        return True, r.json()
    except Exception:
        return False, "Backend returned non-JSON response"

for key in ("last_bank", "assessment", "debug", "progress", "study_bundle",
            "lesson_overview", "skill_asm", "studied"):
    st.session_state.setdefault(key, None)
# Normalize legacy None -> dict for the new bundle keys
for k in ("skill_asm", "studied"):
    if st.session_state.get(k) is None:
        st.session_state[k] = {}
if st.session_state.get("study_bundle") is None:
    st.session_state["study_bundle"] = {"lesson": None, "skills": []}

tab_teacher, tab_student, tab_debug = st.tabs(["👩‍🏫 Teacher", "🧑‍🎓 Student", "🛠️ Debug"])

# ---------------- Teacher ----------------
with tab_teacher:
    st.header("1. Upload material → RAG ingestion")
    course_id = st.text_input("course_id", "python_101", key="t_course")
    lesson_id = st.text_input("lesson_id", "elif_lesson", key="t_lesson")
    skill_id = st.text_input("skill_id", "python_elif", key="t_skill")
    up = st.file_uploader("Educational file (pdf/txt/docx/image)", type=["pdf", "txt", "md", "docx", "png", "jpg", "jpeg"])
    if st.button("Upload + Process", disabled=up is None):
        if up is None:
            st.warning("Please select a file first.")
            st.stop()
        files = {"file": (up.name or "upload.bin", up.getvalue())}
        # Upload can include OCR + chunking; allow 5 min before we surface a timeout.
        # Backend now returns fast (index warms in background), so 300s is a safety net.
        with st.spinner("Uploading and ingesting… (OCR for scanned PDFs can take ~30s)"):
            ok, data = api_post("/documents/upload",
                                data={"course_id": course_id, "lesson_id": lesson_id, "skill_id": skill_id},
                                files=files, timeout=300)
        if not ok:
            if "timed out" in str(data).lower() or "Timeout" in str(data):
                st.error(f"Upload timed out: {data}. Try a smaller file (<10MB) or plain TXT for no-OCR fast path. PDFs with many scanned pages are slower.")
            else:
                st.error(data)
        else:
            st.success(f"Ingested {data.get('chunk_count', 0)} chunks via {data.get('method')} ({data.get('char_count', 0)} chars).")
            st.json(data)
            st.session_state.debug = {"upload": data}

    st.header("2. Agent splits lesson into skills (+ explanations)")
    st.caption("The agent decides how many skills (one per topic). The slider is only an upper bound.")
    n_sk = st.slider("max_skills (upper bound, hard cap 6)", 1, 6, 6)
    c1, c2 = st.columns(2)
    if c1.button("Extract skills"):
        with st.spinner("Agent is splitting the lesson into skills…"):
            ok, data = api_post("/agent/extract-skills",
                                json={"course_id": course_id, "lesson_id": lesson_id,
                                      "max_skills": n_sk}, timeout=180)
        if not ok:
            st.error(data)
        else:
            st.json({k: v for k, v in data.items() if k not in ("trace", "skills")})
            st.session_state.debug = data
    if c2.button("Reload skills"):
        ok, skills = api_get("/agent/skills",
                             params={"course_id": course_id, "lesson_id": lesson_id}, timeout=30)
        if not ok:
            st.error(skills)
        else:
            st.session_state.skills = skills
    for s in (st.session_state.debug or {}).get("skills", []) if isinstance(st.session_state.debug, dict) else []:
        with st.expander(f"Skill: {s['name']} (`{s['skill_id']}`)"):
            st.write(s.get("description", ""))
            st.markdown("**Explanation:**")
            st.write(s.get("explanation", "") or "_pending_")
            st.caption(f"concepts: {', '.join(s.get('key_concepts', []))}")
    if st.session_state.get("skills"):
        for s in st.session_state.skills:
            with st.expander(f"Skill: {s['name']} (`{s['skill_id']}`)"):
                st.write(s.get("description", ""))
                st.markdown("**Explanation:**")
                st.write(s.get("explanation", "") or "_pending_")

    st.header("3. Generate one question bank per skill (10 questions each)")
    feedback = st.text_area("Teacher feedback for (re)generation (optional)", "")
    n_q = st.slider("questions per skill bank", 4, 15, 10)
    if st.button("Generate banks for all skills"):
        with st.spinner("Agent is generating one bank per skill…"):
            ok, data = api_post("/agent/generate-lesson-banks",
                                json={"course_id": course_id, "lesson_id": lesson_id,
                                      "teacher_feedback": feedback, "n_questions": n_q}, timeout=300)
        if not ok:
            st.error(data)
        else:
            st.json({"lesson_id": data.get("lesson_id"), "num_skills": data.get("num_skills"),
                     "banks": [{k: v for k, v in b.items() if k != "trace"} for b in data.get("banks", [])]})
            st.session_state.debug = data

    st.header("4. Review pending banks (human-in-the-loop, per skill)")
    if st.button("Refresh pending"):
        ok, pending = api_get("/teacher/question-banks/pending",
                              params={"limit": 100}, timeout=30)
        if not ok:
            st.error(pending)
        else:
            st.session_state.pending = pending
    for b in st.session_state.get("pending", []) or []:
        with st.expander(f"Bank {b['id']} v{b['version']} — {b['course_id']}/{b['lesson_id']} / `{b['skill_id']}`"):
            ok, detail = api_get(f"/teacher/question-banks/{b['id']}", timeout=30)
            if not ok:
                st.error(detail)
                continue
            for q in detail.get("questions", []):
                st.markdown(f"**Q ({q['difficulty']}, {q['skill_id']})**: {q['question']}")
                st.write({i: o for i, o in enumerate(q["options"])})
                st.caption(f"correct={q['correct_answer']} | {q['explanation']}")
                fc1, fc2 = st.columns([3, 1])
                flag_reason = fc1.text_input("Flag reason (optional)", key=f"flag_{q['id']}",
                                            placeholder="e.g. wrong answer, not in material…")
                if fc2.button("🚩 Flag", key=f"flagbtn_{q['id']}"):
                    ok, res = api_post(f"/teacher/questions/{q['id']}/flag",
                                       json={"reason": flag_reason}, timeout=30)
                    if not ok:
                        st.error(res)
                    else:
                        st.success(f"Flagged {q['id'][:8]} — excluded from future assessments.")
            c1, c2 = st.columns(2)
            if c1.button("✅ Approve", key=f"ap_{b['id']}"):
                ok, res = api_post(f"/teacher/question-banks/{b['id']}/approve", timeout=30)
                if not ok:
                    st.error(res)
                else:
                    st.success(f"Approved bank {b['id'][:8]} v{res.get('version')}.")
            rej_fb = st.text_input("Rejection feedback", key=f"rj_{b['id']}")
            if c2.button("❌ Reject", key=f"rjbtn_{b['id']}"):
                ok, res = api_post(f"/teacher/question-banks/{b['id']}/reject",
                                   json={"feedback": rej_fb}, timeout=30)
                if not ok:
                    st.error(res)
                else:
                    st.warning(f"Rejected bank {b['id'][:8]} — regenerate that skill's bank to get v{res.get('version', 0) + 1}.")

# ---------------- Student ----------------
with tab_student:
    st.header("Learn skill by skill — each skill = explanation + exercise")
    sid = st.text_input("student_id", "student_1")
    sname = st.text_input("student_name", "Demo Student")
    sc, sl = st.columns(2)
    s_course = sc.text_input("course_id", "python_101", key="s_course")
    s_lesson = sl.text_input("lesson_id", "elif_lesson", key="s_lesson")
    if st.button("Load my skills"):
        ok, prog = api_get(f"/students/{sid}/skill-progress",
                           params={"course_id": s_course, "lesson_id": s_lesson}, timeout=30)
        if not ok:
            st.error(prog)
        else:
            st.session_state.progress = prog
            st.session_state.skill_asm = {}
            st.session_state.studied = {}
            # One study bundle (lesson overview + all skill explanations) instead of
            # one request per skill below — avoids N+1 fetches on every rerun.
            ok2, bundle = api_get("/agent/lesson",
                                  params={"course_id": s_course, "lesson_id": s_lesson}, timeout=30)
            st.session_state.study_bundle = bundle if ok2 else {"lesson": None, "skills": []}
            if ok2 and bundle.get("lesson", {}).get("explanation"):
                st.session_state.lesson_overview = bundle["lesson"]
    prog = st.session_state.get("progress") or {}
    bundle_skills = {s.get("skill_id"): s for s in (st.session_state.get("study_bundle") or {}).get("skills", [])}
    if (st.session_state.get("lesson_overview") or {}).get("explanation"):
        with st.expander("📚 Lesson overview — read first", expanded=False):
            st.write(st.session_state.lesson_overview.get("title", ""))
            st.write(st.session_state.lesson_overview.get("explanation", ""))
    if prog.get("skills"):
        st.progress(prog["completed"] / max(1, prog["total"]),
                    text=f"{prog['completed']}/{prog['total']} skills completed")
        for sk in prog["skills"]:
            status = "✅" if sk["completed"] else ("📖" if sk["has_explanation"] else "⏳")
            acc = f" — accuracy {sk['accuracy']:.0%}" if sk["accuracy"] is not None else ""
            with st.expander(f"{status} {sk['name']} (`{sk['skill_id']}`){acc}", expanded=False):
                bundled = bundle_skills.get(sk["skill_id"], {})
                expl = bundled.get("explanation", "") or ""
                if not expl:
                    # Fallback for bundles loaded before this fix or partially missing skills.
                    ok, det = api_get("/agent/skills",
                                      params={"course_id": s_course, "lesson_id": s_lesson,
                                              "skill_id": sk["skill_id"]}, timeout=30)
                    if ok and det:
                        bundled = det[0]
                        expl = bundled.get("explanation", "")
                st.markdown("**📖 Explanation — read this first:**")
                img_key = f"imgbytes_{s_course}_{s_lesson}_{sk['skill_id']}"
                if img_key not in st.session_state:
                    try:
                        ir = requests.get(
                            f"{API}/images/skill",
                            params={"course_id": s_course, "lesson_id": s_lesson,
                                    "skill_id": sk["skill_id"]}, timeout=120)
                        st.session_state[img_key] = ir.content if ir.status_code == 200 else None
                        if ir.status_code == 503:
                            st.info("🖼️ Skill images need PEXELS_API_KEY in the backend .env.")
                    except Exception:
                        st.session_state[img_key] = None
                if st.session_state.get(img_key):
                    st.image(st.session_state[img_key],
                             caption=bundled.get("image_alt", "") if bundled else "")
                st.write(expl or "_No explanation yet._")
                akey = f"audio_{s_course}_{s_lesson}_{sk['skill_id']}"
                if st.button("🔊 Listen to explanation", key=f"tts_{sk['skill_id']}",
                             disabled=not expl):
                    try:
                        ar = requests.get(
                            f"{API}/audio/skill",
                            params={"course_id": s_course, "lesson_id": s_lesson,
                                    "skill_id": sk["skill_id"]}, timeout=180)
                        if ar.status_code == 503:
                            st.warning("Audio needs GROQ_API_KEY (+ accepted TTS model terms). "
                                       "Add it to the backend .env and restart it.")
                        elif ar.status_code != 200:
                            st.error(ar.text[:300])
                        else:
                            st.session_state[akey] = ar.content
                    except Exception as exc:
                        st.error(f"Audio request failed: {exc}")
                if st.session_state.get(akey):
                    st.audio(st.session_state[akey], format="audio/wav")
                st.caption(f"Exercise bank: {sk['bank_questions']} approved questions | "
                           f"attempted: {sk['attempted']}")
                asm = (st.session_state.get("skill_asm") or {}).get(sk["skill_id"])
                if not sk["exercise_ready"]:
                    st.warning("Teacher hasn't approved this skill's bank yet.")
                elif asm is None:
                    if st.button("Start this skill's exercise (4 questions)",
                                 key=f"start_{sk['skill_id']}"):
                        with st.spinner("Picking your 4 questions…"):
                            ok, payload = api_post(
                                "/assessment/start",
                                json={"student_id": sid, "student_name": sname,
                                      "course_id": s_course, "lesson_id": s_lesson,
                                      "skill_id": sk["skill_id"]}, timeout=60)
                        if not ok:
                            st.error(payload)
                        else:
                            st.session_state.setdefault("skill_asm", {})[sk["skill_id"]] = payload
                            st.session_state.setdefault("studied", {})[sk["skill_id"]] = False
                            missing = (payload.get("selection_meta") or {}).get("missing_skills") or []
                            if missing:
                                st.warning("No approved bank yet for: " + ", ".join(missing))
                            st.rerun()
                else:
                    # Gate questions behind an explicit "I've read it" checkbox so students
                    # don't skip the explanation. The widget key is stable per skill.
                    st.session_state.setdefault("studied", {})[sk["skill_id"]] = st.checkbox(
                        "I've read the explanation — show my 4 questions",
                        value=st.session_state.get("studied", {}).get(sk["skill_id"], False),
                        key=f"studied_{sk['skill_id']}")
                    if st.session_state["studied"][sk["skill_id"]]:
                        # Collect answers — no default (index=None) so unanswered stays None.
                        # The format_func renders option text next to the radio index.
                        answers: dict[str, int | None] = {}
                        for q in asm["questions"]:
                            st.markdown(f"**{q['question']}**  `[{q['difficulty']}]`")
                            opts = list(q["options"])
                            choice = st.radio("Your answer:", list(range(len(opts))),
                                              format_func=lambda i, _o=opts: f"{i}. {_o[i]}",
                                              index=None,
                                              key=f"{asm['assessment_id']}_{q['id']}")
                            answers[q["id"]] = choice
                        # Surface coverage warnings returned by the backend (e.g. one skill's bank rejected).
                        missing = (asm.get("selection_meta") or {}).get("missing_skills") or []
                        if missing:
                            st.warning("Not all skills have an approved bank: " + ", ".join(missing))
                        if st.button("Submit this skill's answers", key=f"sub_{sk['skill_id']}"):
                            if any(v is None for v in answers.values()):
                                st.warning("Answer all 4 questions before submitting.")
                            else:
                                with st.spinner("Submitting…"):
                                    ok, res = api_post(f"/assessment/{asm['assessment_id']}/submit",
                                                       json={"answers": {k: int(v) for k, v in answers.items()}},
                                                       timeout=60)
                                if not ok:
                                    st.error(res)
                                else:
                                    st.json({k: v for k, v in res.items() if k != "trace"})
                                    if res.get("skills_needing_review"):
                                        st.warning("🔁 Review these skills (below 50%): "
                                                   + ", ".join(res["skills_needing_review"])
                                                   + " — re-study the explanation and retry.")
                                    else:
                                        st.success(f"Scored {res.get('correct', 0)}/{res.get('total', 0)}")
                                    st.session_state.debug = res
                                    st.session_state.get("skill_asm", {}).pop(sk["skill_id"], None)
                                    ok2, prog2 = api_get(f"/students/{sid}/skill-progress",
                                                         params={"course_id": s_course, "lesson_id": s_lesson},
                                                         timeout=30)
                                    if ok2:
                                        st.session_state.progress = prog2
                                    st.rerun()
    st.header("Stored performance / memory")
    if st.button("Load performance"):
        ok, perf = api_get(f"/students/{sid}/performance", timeout=30)
        if not ok:
            st.error(perf)
        else:
            st.json(perf)

# ---------------- Debug ----------------
with tab_debug:
    st.header("Developer / debug panel")
    dbg = st.session_state.debug
    if not dbg or not isinstance(dbg, dict):
        st.info("No agent run captured yet. Generate a bank or run an assessment first.")
    else:
        trace = dbg.get("trace", [])
        if trace:
            st.subheader("Agent phases + tool calls")
            for t in trace:
                evt = t.get('event', '?')
                det = t.get('detail')
                # Render dict details as JSON, strings verbatim
                if isinstance(det, dict):
                    st.write(f"`{evt}`")
                    st.json(det)
                else:
                    st.write(f"`{evt}` — {det}")
        for k in ("retrieved_chunks", "backend", "selection_meta", "skill_performance",
                  "score", "assessment_result", "extraction_backend"):
            if k in dbg:
                st.subheader(k)
                st.json(dbg[k])
        with st.expander("Full payload"):
            st.json(dbg)
