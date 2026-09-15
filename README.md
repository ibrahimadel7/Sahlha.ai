# Sahlha AI — Learning-Loop MVP

First functional prototype proving the **Sahlha learning loop end-to-end**:
upload → OCR → RAG → **agent splits lesson into skills (one per topic — the agent decides
how many), writes a lesson overview and an explanation per skill** →
**one 10-question bank per skill** → teacher approves each bank →
student studies, then is assessed (**4 questions picked from EACH bank**, or one
skill's 4 when a `skill_id` is given — **skill = explanation + exercise**) →
attempts stored → memory updated → next assessment adapts.

> LLM provider: **Groq primary → OpenRouter backup → deterministic fallback** (`GROQ_API_KEY` + `GROQ_MODEL`, default `llama-3.3-70b-versatile`; backup `OPENROUTER_API_KEY` + `OPENROUTER_MODEL` default `openai/gpt-4o-mini` via `https://openrouter.ai/api/v1`). Without any key the agent uses a **grounded deterministic fallback generator** so the whole loop still works offline.
> TTS provider: **Groq Orpheus → OpenRouter TTS → non-fatal skip** (`canopylabs/orpheus-v1-english` voice `troy`; backup `OPENROUTER_TTS_MODEL` default `openai/gpt-4o-mini-tts` voice `alloy` via `POST /api/v1/audio/speech`). See `.env.example`.

## 1. Final project structure

```text
sahlha/
└── app/
    ├── main.py                    # FastAPI entrypoint (thin routers only)
    ├── config.py                  # settings (Groq keys, chunking, top-k, n=4)
    ├── api/
    │   ├── routes_documents.py    # POST /documents/upload, POST /documents/{id}/process
    │   ├── routes_agent.py        # POST /agent/generate-question-bank
    │   ├── routes_teacher.py      # GET pending, GET bank, POST approve/reject
    │   └── routes_assessment.py   # POST start/submit, GET student performance
    ├── agent/
    │   ├── agent.py               # SahlhaAgent state-machine runtime (ONE agent)
    │   ├── state.py               # AgentState (typed, serializable) + Phase enum
    │   ├── prompts.py             # LLM prompts: questions + skill extraction + explanations
    │   ├── schemas.py             # GeneratedQuestion / QuestionList / ExtractedSkill / SkillExplanation
    │   ├── llm.py                 # Groq client + grounded fallback generators
    │   └── tools/
    │       ├── rag_tools.py       # retrieve_lesson / retrieve_skill_material / retrieve_relevant_material
    │       ├── question_tools.py  # save_questions / get_question_bank / get_approved_questions
    │       ├── student_tools.py   # history / failed / skill performance / update memory
    │       └── assessment_tools.py# select_questions / evaluate_answer / record_attempt
    ├── rag/
    │   ├── ingestion.py           # bytes → extract → chunk → persist → reindex
    │   ├── ocr.py                 # extract_document_text() interface (text vs scanned)
    │   ├── chunking.py            # overlapping char chunker + cleaner
    │   ├── embeddings.py          # TF-IDF embedding model (swappable)
    │   ├── vectorstore.py         # cosine search abstraction (swappable for FAISS/Chroma)
    │   └── retriever.py           # filtered semantic retrieval
    ├── database/
    │   ├── database.py            # engine/session, init_db (app owns transactions)
    │   ├── models.py              # Document, DocumentChunk, QuestionBank, Question,
    │                              # Student, Assessment, StudentAttempt, StudentSkillPerformance
    │   └── repositories/          # ONLY layer (besides services) touching the ORM
    ├── schemas/api.py             # FastAPI request models
    └── services/services.py       # business logic (routes stay thin)
streamlit_app.py                   # test client: teacher / student / debug tabs
tests/                             # test_rag, test_questions, test_assessment, test_api_loop
data/                              # sqlite db, uploads, vectorizer (gitignored)
```

## 2. Agent architecture

One `SahlhaAgent` (`sahlha/app/agent/agent.py`) — an explicit **state machine** over
`AgentState`, not a free-form while-loop:

```text
SKILL_EXTRACTION → SKILL_EXPLANATION → QUESTION_GENERATION (per skill)
→ (teacher boundary) → WAITING_FOR_TEACHER
→ ASSESSMENT → EVALUATION → ADAPTATION
```

- `extract_skills()`: `retrieve_lesson()` → Groq returns skills JSON (validated via
  `SkillList`) → persisted in `skills` (idempotent unless `force=True`). The agent decides
  the number of skills (one per lesson topic); `max_skills` is only a safety cap.
- `explain_skills()`: per skill, skill-focused retrieval → Groq writes a grounded
  student-facing explanation → **skill tool → explanation tool → audio + image tools**
  (one call yields explanation + picture + speech; media recorded under `media`, never
  fatal). Stored on the skill row.
- `explain_lesson()`: one grounded overview (title + explanation + key concepts) for the
  whole lesson → stored in `lesson_explanations` (idempotent; runs inside skill extraction too).
  Same chain for the lesson audio (explanation tool → audio tool).

## 2b. Feedback loops (agent architecture)

Three closed loops; the LLM reasons, the app enforces:

1. **Generation self-critique** — every draft bank passes `critique_questions`
   (Groq verdicts, or a deterministic term-overlap gate offline): ungrounded or
   mis-answered drafts are dropped and topped up with grounded replacements. Logged in trace.
2. **Teacher flags** — `POST /teacher/questions/{id}/flag` marks one bad question with a
   reason. Flagged questions are **excluded from all future selections**, and their reasons
   are **auto-appended to the next generation's feedback** for that skill (no retyping).
   `GET /teacher/flags` lists them.
3. **Mastery review** — each submit returns `skills_needing_review` (<50% in that
   assessment); `skill-progress` exposes persistent `needs_review` per skill. Students
   re-study flagged skills; teachers see where explanations/banks are failing.
- `generate_lesson_banks()`: one `generate_question_bank()` per skill (10 questions each) — skill-focused
  retrieval → Groq generates **structured JSON** → `QuestionList` validation →
  `save_questions()` → phase `WAITING_FOR_TEACHER`. The bank's `skill_id` is enforced
  app-side on every question row.
- `start_assessment()`: approved questions + student history → memory-aware
  `select_questions()` (**exactly 4 from EACH approved bank**, so every skill is covered;
  failed-retry → weak skills → unseen → difficulty balance runs inside each bank)
  → `Assessment` row created. The response also carries
  `lesson_explanation` (whole-lesson overview) plus `skill_explanations` — so the student
  **studies the lesson, then the skills, before the exercise**. Correct answers never leave the server.
- `submit_assessment()`: per-question `evaluate_answer()` → `record_attempt()` →
  `update_student_memory()` → phase `ADAPTATION`.
- Every phase transition and tool call is appended to `state.trace` (shown in the Streamlit debug tab).

## 3. Tool list & responsibilities

| Tool | Responsibility |
|---|---|
| `retrieve_lesson(course, lesson)` | RAG chunks for one lesson (with doc/course/lesson/skill/page/chunk metadata) |
| `retrieve_skill_material(skill)` | RAG chunks for one skill |
| `retrieve_relevant_material(query, filters)` | free-form semantic search with optional filters |
| `register_skill` / `setup_skill` (skill tools) | persist a skill; attach its explanation **via the explanation tool** |
| `explain_skill` / `explain_lesson` (explanation tools) | persist explanation text, then **call audio + image tools** (media never fails the explanation) |
| `skill_explanation_to_audio` / `lesson_explanation_to_audio` | Groq Orpheus speech, cached by content hash |
| `fetch_skill_image` | Pexels picture from skill context (name + key concepts), cached on disk |
| `save_questions(...)` | **validate** LLM JSON (Pydantic) then persist new `pending_review` version |
| `get_question_bank(bank_id)` | full bank + questions (teacher review) |
| `get_approved_questions(filters)` | only `approved` banks' questions (assessment pool) |
| `get_student_history(student)` | past attempts (capped, no full-history prompt dumps) |
| `get_failed_questions(student)` | question IDs answered incorrectly |
| `get_student_skill_performance(student)` | per-skill accuracy rows |
| `update_student_memory(...)` | upsert skill counters after each attempt |
| `select_questions(...)` | deterministic: failed-retry → weak skills (<0.6) → unseen → difficulty balance; **exactly 4** |
| `evaluate_answer(question, answer)` | structured `{question_id, correct, student_answer, correct_answer, skill_id}` |
| `record_attempt(...)` | one `StudentAttempt` row per answer (never just a score) |

The agent **never** touches the DB/vector store directly — only through these tools.

## 4. Database schema (SQLite)

- `documents(id, filename, course_id, lesson_id, skill_id, status, char_count, chunk_count, created_at)`
- `document_chunks(id, document_id, course_id, lesson_id, skill_id, page, chunk_index, text)`
- `skills(id, course_id, lesson_id, skill_id[slug, unique per lesson], name, description, explanation, key_concepts[JSON], created_at, updated_at)`
- `lesson_explanations(id, course_id, lesson_id[unique], title, explanation, key_concepts[JSON], created_at, updated_at)`
- `question_banks(id, course_id, lesson_id, skill_id, version, status[pending_review|approved|rejected], teacher_feedback, created_at, updated_at)` — versions append-only, never overwritten
- `questions(id, question_bank_id, skill_id, question_type, question_text, options[JSON], correct_answer[JSON], explanation, difficulty, created_at)`
- `students(id, name, created_at)`
- `assessments(id, student_id, question_bank_id, question_ids[JSON], status, score, created_at)`
- `student_attempts(id, student_id, question_id, assessment_id, answer[JSON], correct, timestamp)`
- `student_skill_performance(id, student_id, skill_id, total_attempts, correct_attempts, accuracy, last_updated)` — unique `(student_id, skill_id)`

## 5. RAG architecture

```text
upload bytes → extract_document_text() → clean → sentence-aware chunks (overlap)
→ persist chunks → encode dense vectors (MiniLM-L6-v2, cached to disk)
→ MMR cosine search (+ score floor with top-k backoff)
```

- `embeddings.py`: dense semantic vectors first (384-d, normalized); TF-IDF fallback
  keeps the loop working offline. Backend recorded in the vector cache; corpus/backend
  changes trigger rebuilds, otherwise the cache is reused.
- `chunking.py`: packs whole sentences (never mid-sentence cuts) with trailing-sentence
  overlap between consecutive chunks.
- `vectorstore.py`: cosine search over 3× candidates → MMR (λ=0.7) diversity →
  calibrated score floor (paraphrase ≈0.09, junk ≈0.02) with backoff so the agent is
  never starved of context. Proven by `tests/test_rag_proper.py`: a paraphrase with
  (almost) no shared keywords still retrieves the right material.

- `ocr.py` is a provider interface: native text for pdf/docx/txt; text-thin PDFs and
  images go through **real Tesseract OCR** (this machine: Tesseract 5.4 + Poppler via
  winget; elsewhere `winget install UB-Mannheim.TesseractOCR oschwartz10612.Poppler`,
  or set `TESSERACT_CMD`/`POPPLER_PATH`). Every result reports `is_scanned` + `method`,
  and `tests/test_ocr.py` proves scanned PNG/PDFs are actually read.
- Every retrieved chunk carries `document_id, course_id, lesson_id, skill_id, page, chunk_id, text, score`.
- Generation is **grounded**: only retrieved chunks enter the prompt; fallback generator builds
  stems from chunk sentences. Full documents are never pasted into prompts.

## 6. API endpoints

```text
POST /documents/upload
POST /documents/{id}/process
POST /agent/extract-skills            (lesson → agent-decided skills + explanations + lesson overview)
GET  /agent/skills?course_id&lesson_id[&skill_id]
POST /agent/explain-lesson             (whole-lesson overview explanation)
GET  /agent/lesson                     (study bundle: lesson overview + skill explanations)
POST /agent/generate-question-bank    (single skill)
POST /agent/generate-lesson-banks     (one bank per skill)
GET  /teacher/question-banks/pending
GET  /teacher/question-banks/{id}
POST /teacher/question-banks/{id}/approve
POST /teacher/question-banks/{id}/reject        (JSON {feedback} → next version uses it)
POST /teacher/questions/{qid}/flag              (JSON {reason} → excluded + feeds regeneration)
GET  /teacher/flags
POST /assessment/start                 (optional skill_id → that skill's 4-question exercise)
POST /assessment/{id}/submit
GET  /students/{id}/performance
GET  /students/{id}/skill-progress?course_id&lesson_id   (per-skill explanation+exercise status)
GET  /audio/skill?course_id&lesson_id&skill_id[&voice]   (WAV speech of a skill's explanation)
GET  /audio/lesson?course_id&lesson_id[&voice]           (WAV speech of the lesson overview)
GET  /images/skill?course_id&lesson_id&skill_id          (JPEG picture related to the skill)
GET  /health
```

## 7. Run FastAPI

```powershell
pip install -r requirements.txt
copy .env.example .env   # add GROQ_API_KEY to enable the real LLM; optional
python -m uvicorn sahlha.app.main:app --reload --port 8000
```

## 8. Run Streamlit

```powershell
$env:SAHLHA_API = "http://127.0.0.1:8000"
streamlit run streamlit_app.py
```

## 9. Test the complete loop

```powershell
python -m pytest tests/ -q   # 11 tests: RAG, generation, approve, reject→v2, assessment×4,
                             # memory-adapts, HTTP loop, skill extraction+explanations,
                             # one-bank-per-skill, skill banks approve+assess, skill HTTP endpoints
```

Manual loop in Streamlit: **Teacher** tab → upload file → Extract skills (agent decides the
count; review explanations) → Generate 10-question banks (one per skill) → approve each →
**Student** tab → load the lesson's skills → per skill: read its explanation →
start its 4-question exercise → submit → progress bar tracks completed skills →
**Debug** tab shows phases/tool calls).

## 10b. Audio explanations (Groq TTS → OpenRouter fallback)

New tool pair `skill_explanation_to_audio` / `lesson_explanation_to_audio`
(`sahlha/app/agent/tools/audio_tools.py`) turns stored explanations into speech via
Groq's Orpheus English TTS (`canopylabs/orpheus-v1-english`, `sahlha/app/audio/tts.py`):
long text is split sentence-aware, each chunk synthesized, and the WAVs stitched.
Files are cached in `data/audio/` by content hash. The student UI has a 🔊 **Listen**
button per skill. Requires `GROQ_API_KEY` **and** accepting the model terms in the Groq
console — without them the endpoints return `503` (there is no offline TTS fallback).
**Backup:** when Groq TTS fails (rate-limit/quota/5xx/timeout) and `OPENROUTER_API_KEY` is set,
the same `tts.synthesize()` automatically retries via OpenRouter `POST /api/v1/audio/speech`
(model `openai/gpt-4o-mini-tts` voice `alloy` by default, configurable via
`OPENROUTER_TTS_MODEL`/`OPENROUTER_TTS_VOICE`). Both providers share the same chunking,
stitching and hash cache; if both fail the existing non-fatal `skipped → 503` behavior is preserved.

## 10c. Skill images (Pexels)

Tool `fetch_skill_image` (`sahlha/app/agent/tools/image_tools.py`) builds a query from the
skill's context (name + key concepts) and fetches one landscape picture via the Pexels API
(`sahlha/app/images/pexels.py`), cached in `data/images/` and recorded on the skill row
(`image_url`/`image_path`/`image_alt`; added to existing DBs by a startup migration).
The student UI shows the picture above each explanation. Set `PEXELS_API_KEY` in `.env`
(free at https://www.pexels.com/api/) — without it `GET /images/skill` returns `503`.

## 10. Known limitations & next steps

- Embeddings are TF-IDF (offline-friendly) — swap `embeddings.py`/`vectorstore.py` for
  sentence-transformers + FAISS/Chroma when ready; interfaces are isolated.
- OCR for scanned PDFs needs `tesseract` binary + `pdf2image`; otherwise text is best-effort.
- No auth (single teacher/student IDs), no pagination, SQLite only — all intentional for the MVP.
- Next: real auth, richer question types (short answer grading via LLM), spaced-repetition
  scheduling on top of `StudentSkillPerformance`, and analytics over `student_attempts`.
