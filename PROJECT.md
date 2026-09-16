# Sahlha.ai — Project Documentation

> **Tagline:** Adaptive learning loop — upload → understand → explain → exercise → adapt.

`Sahlha.ai` is an MVP that proves a **closed learning loop end-to-end**: a teacher uploads lesson material, an AI agent autonomously splits the lesson into skills, writes grounded explanations + generates per-skill question banks (human-approved), and students study skill-by-skill with adaptive, memory-aware assessments that feed back into personalized learning.

- **Status:** Functional prototype / MVP — primary learning flow validated, no auth/pagination sharding (intentional).
- **Repo:** `D:\projects\Sahlha.ai`
- **LLM Provider:** Groq (`GROQ_API_KEY` + `GROQ_MODEL=llama-3.3-70b-versatile` via native `groq` SDK + OpenAI-compatible fallback). Without a key the whole loop works via deterministic grounded fallback generators — no mock.
- **Entry points:**
  - API: `sahlha/app/main.py` → `uvicorn sahlha.app.main:app --reload --port 8000`
  - Client: `frontend/index.html` (served at `/app/`) → Teacher / Student / Debug tabs

---

## 1. Vision & Learning Model

### Problem
Static e-learning = one-size content, no per-skill mastery, no adaptation. Teachers authoring banks manually is expensive and ungrounded.

### Solution — `skill = explanation + exercise`
Each **lesson** is decomposed by the agent into **N skills** (agent-decided count, one per topic). For every skill:

1.  A grounded, student-facing **explanation** (+ optional TTS audio + Pexels image).
2.  A **10-question bank** (teacher-approved).
3.  A **4-question adaptive exercise** (subset of that bank, memory-aware).

A lesson overview explanation is also generated for study-before-exercise flow.

### Closing the loop
```
Upload → OCR/Ingest → RAG index
       → [ Agent: extract skills → explain skills → explain lesson → generate banks ]
       → Teacher approves/rejects/flags (human-in-the-loop gate)
       → Student studies (lesson overview → per-skill explanation+media)
       → Adaptive assessment (4Q per skill, every skill covered)
       → Submit → evaluate → record attempts → update skill memory
       → Next assessment adapts: failed-retry → weak skills → unseen → difficulty balance
       → Mastery review (<50% skills flagged for re-study)
```

---

## 2. Tech Stack & Frameworks

| Layer | Choice | File | Notes |
|---|---|---|---|
| **Language** | Python 3.12+ | `requirements.txt:1` |  |
| **API** | FastAPI `>=0.110` + Uvicorn | `sahlha/app/main.py:27` | Thin routers, OpenAPI auto-docs |
| **DB ORM** | SQLAlchemy `>=2.0` | `sahlha/app/database/database.py` |  |
| **DB Engine** | SQLite (`data/sahlha.db`) | `sahlha/app/config.py:9` | File DB, WAL not required for MVP |
| **Validation** | Pydantic `>=2.6` + `pydantic-settings` | `sahlha/app/config.py:1` + `sahlha/app/agent/schemas.py` | `AgentState`, `QuestionList`, `SkillList`, `LessonExplanationModel`, `CritiqueResult` |
| **RAG Embeddings (primary)** | `sentence-transformers/all-MiniLM-L6-v2` (384-d, L2-norm) | `sahlha/app/rag/embeddings.py:18` | Dense semantic search, cached L2 rows |
| **RAG Embeddings (fallback)** | scikit-learn TF-IDF `max_features=5000, ngram(1,2)` | `sahlha/app/rag/embeddings.py:32` | Offline / no-torch path, corpus-fit |
| **Vector Search** | Custom `numpy` cosine + MMR `λ=0.7` + score floor + backoff | `sahlha/app/rag/vectorstore.py:21` | Swappable for FAISS/Chroma behind same `search()` |
| **OCR / Ingest** | `pypdf` + `python-docx` + `Pillow` + `pytesseract` + `pdf2image` + Poppler/Tesseract binaries | `sahlha/app/rag/ocr.py:1` | Text vs scanned auto-detect, real Tesseract 5.4 |
| **LLM – primary** | `groq>=0.11` native SDK → `llama-3.3-70b-versatile` | `sahlha/app/agent/llm.py:44` | `response_format={"type":"json_object"}`, 0.4 temp, 2000 tokens |
| **LLM – compat** | `openai>=1.30` OpenAI client @ `https://api.groq.com/openai/v1` | `sahlha/app/agent/llm.py:57` | Fallback when `groq` pkg absent |
| **LLM – offline** | Deterministic grounded fallback generators | `sahlha/app/agent/llm.py:109` | `fallback_questions/skills/explanation/lesson/critique` — never hallucinates |
| **TTS** | Groq Orpheus `canopylabs/orpheus-v1-english` (voice `troy`) | `sahlha/app/audio/tts.py` + `sahlha/app/config.py:25` | Chunked at 900 chars, WAV stitch, hash-cache `data/audio/` |
| **Images** | Pexels API (landscape photo per skill) | `sahlha/app/images/pexels.py` + `sahlha/app/agent/tools/image_tools.py` | Query=`name + key_concepts`, cache `data/images/`, `503` when no key |
| **Frontend** | Static HTML/CSS/JS (`frontend/index.html`, served at `/app/`) | `sahlha/app/main.py:46` | Teacher / Student / Debug tabs, not production UI |
| **HTTP client** | `requests` (app) + `httpx` (tests) | `requirements.txt:13` |  |
| **Testing** | `pytest>=8.0` | `tests/` | 11+ tests, full loop via `TestClient` |

### Configuration — `sahlha/app/config.py:5`

All settings are `BaseSettings` from `.env` (`extra="ignore"`):

```python
class Settings(BaseSettings):
    app_name, database_url, upload_dir, vectorizer_path
    groq_api_key / groq_model / groq_base_url   # primary LLM
    openai_api_key / openai_model / openai_base_url # fallback
    groq_tts_model, groq_tts_voice, groq_tts_max_chars=900, audio_dir
    pexels_api_key, image_dir
    chunk_size=800, chunk_overlap=120
    top_k_retrieval=5
    assessment_num_questions=4  # per approved bank → N*4 total
    llm_max_context_chars=6000   # token-optimized
    llm_skill_context_chars=4000
    enable_llm_critique=False    # deterministic critique default
```

Versioning: `vectorizer_path = ./data/tfidf_vectorizer.pkl`, vectors in adjacent `vectors.npz` (ids + matrix + backend tag).

---

## 3. Project Structure

```
Sahlha.ai/
├── sahlha/
│   ├── app/
│   │   ├── main.py                    # FastAPI app + lifespan (init_db + warm embeddings)  sahlha/app/main.py:12
│   │   ├── config.py                  # Settings singleton                                 sahlha/app/config.py:5
│   │   │
│   │   ├── api/                       # Thin HTTP layer — delegates to services, zero business logic
│   │   │   ├── routes_documents.py    # POST /documents/upload, POST /documents/{id}/process
│   │   │   ├── routes_agent.py        # POST /agent/extract-skills, /generate-*-banks, /explain-lesson, GET /skills, /lesson
│   │   │   ├── routes_teacher.py      # GET pending, GET bank, POST approve/reject, POST flag, GET flags
│   │   │   ├── routes_assessment.py   # POST /assessment/start, POST /assessment/{id}/submit, GET student/*
│   │   │   ├── routes_audio.py        # GET /audio/skill, GET /audio/lesson  (503 without GROQ_API_KEY)
│   │   │   └── routes_images.py       # GET /images/skill  (503 without PEXELS_API_KEY)
│   │   │
│   │   ├── agent/                     # Single state-machine agent
│   │   │   ├── agent.py               # SahlhaAgent runtime — 8 phases, trace-logged            sahlha/app/agent/agent.py:35
│   │   │   ├── state.py               # AgentState (Pydantic) + Phase enum (8 values)           sahlha/app/agent/state.py:11
│   │   │   ├── prompts.py             # Prompt builders: extraction, skill/lesson explanation, questions, critique
│   │   │   ├── schemas.py             # GeneratedQuestion, QuestionList, ExtractedSkill, SkillList, SkillExplanation, LessonExplanationModel, CritiqueResult
│   │   │   ├── llm.py                 # Groq client + 5 fallback generators + critique             sahlha/app/agent/llm.py:1
│   │   │   └── tools/                 # Agent-only DB/vector access (app never touches DB directly)
│   │   │       ├── rag_tools.py       # retrieve_lesson / retrieve_skill_material / retrieve_relevant_material
│   │   │       ├── skill_tools.py     # register_skill / setup_skill (+ explanation → audio+image chain)
│   │   │       ├── explanation_tools.py # explain_lesson / explain_skill (+ audio fan-out)
│   │   │       ├── audio_tools.py     # skill/lesson_explanation_to_audio (Groq Orpheus, hash cache)
│   │   │       ├── image_tools.py     # fetch_skill_image (Pexels, disk cache)
│   │   │       ├── question_tools.py  # save_questions / get_question_bank / get_approved_questions
│   │   │       ├── student_tools.py   # history / failed / skill performance / update memory
│   │   │       └── assessment_tools.py# select_questions (deterministic, 4 per bank) / evaluate_answer / record_attempt
│   │   │
│   │   ├── rag/                       # Retrieval-Augmented Generation
│   │   │   ├── ingestion.py           # bytes → extract → clean → chunk → persist → (re)index     sahlha/app/rag/ingestion.py:24
│   │   │   ├── ocr.py                 # extract_document_text() — pypdf/docx/txt vs scanned+tesseract sahlha/app/rag/ocr.py:101
│   │   │   ├── chunking.py            # Sentence-aware, overlapping char chunker + cleaner
│   │   │   ├── embeddings.py          # Dense (MiniLM) first, TF-IDF fallback                      sahlha/app/rag/embeddings.py:71
│   │   │   ├── vectorstore.py         # Cosine + MMR + floor + backoff, incremental dense cache   sahlha/app/rag/vectorstore.py:33
│   │   │   └── retriever.py           # Filtered semantic retrieval wrapper
│   │   │
│   │   ├── database/
│   │   │   ├── database.py            # engine / session / init_db (auto-migration for image cols)
│   │   │   ├── models.py              # 10 tables: Document, Chunk, Skill, LessonExplanation, Bank, Question, Student, Assessment, Attempt, SkillPerformance, QuestionFeedback
│   │   │   └── repositories/
│   │   │       └── repositories.py    # ONLY layer touching ORM (besides services) — CRUD + filters + flag/migration helpers
│   │   │
│   │   ├── services/
│   │   │   └── services.py            # Business logic: upload→ingest, extract/explain/generate, teacher approve/flow, assessment start/submit
│   │   │
│   │   ├── audio/
│   │   │   └── tts.py                 # Groq Orpheus: split 900-char chunks → synthesize → stitch WAV
│   │   │
│   │   ├── images/
│   │   │   └── pexels.py              # Pexels search: query → landscape photo → download → disk cache
│   │   │
│   │   └── schemas/
│   │       └── api.py                 # FastAPI request bodies (ExtractSkillsRequest, GenerateBankRequest, LessonBanksRequest, Approve/Reject/Flag)
│   │
│   └── __init__.py
│
├── frontend/
│   └── index.html                     # Test client (3 tabs, served at /app/)  frontend/index.html:1
│
├── tests/                             # pytest suite — see §9
│   ├── conftest.py
│   ├── test_rag.py / test_rag_proper.py
│   ├── test_questions.py
│   ├── test_assessment.py
│   ├── test_skills.py
│   ├── test_api_loop.py
│   ├── test_ocr.py
│   ├── test_audio.py / test_images.py / test_media_autogen.py / test_feedback.py
│   └── __init__.py
│
├── data/                              # gitignored at runtime — sqlite db, uploads/, vectorizer.pkl, vectors.npz, audio/, images/
│
├── requirements.txt                   # Pinned floors for all deps
├── .env.example                       # Template: GROQ_API_KEY, GROQ_MODEL, PEXELS_API_KEY, TESSERACT_CMD/POPPLER_PATH, DATABASE_URL
├── .env                               # Local secrets (gitignored)
├── .gitignore
├── LICENSE
├── README.md                          # Quick start + endpoint map
└── PROJECT.md                         # This file — detailed architecture
```

### How files map to concerns

- **Routes never touch ORM** — `sahlha/app/api/*.py` only validate requests and delegate to `sahlha/app/services/services.py`.
- **Services never embed or search vectors directly** — they call `agent/tools/*` which in turn use `rag/*` + `repositories`.
- **Agent never touches DB/vector directly** — only through its `tools/` facade, enforcing traceability and swap-ability.
- **`repositories` is the single ORM boundary** — enables clean DB swaps (SQLite → Postgres) without touching agent/service logic.

---

## 4. Architecture

### 4.1 Layered Architecture (onion)

```
┌──────────────────────────────────────────────┐
│  Presentation:  FastAPI routes (api/)        │  ← HTTP validation, OpenAPI, no logic
│                 Static SPA (frontend/)         │  ← teacher/student/debug UI at /app/
├──────────────────────────────────────────────┤
│  Application:   services/services.py         │  ← orchestration, transactions, status mapping
│                 agent/agent.py (SahlhaAgent) │  ← state-machine workflow, phase gating
├──────────────────────────────────────────────┤
│  Domain Tools:  agent/tools/*                │  ← typed contracts for RAG/Q-bank/student/assessment/skill/media
│                 rag/retriever.py             │  ← filtered semantic retrieval
├──────────────────────────────────────────────┤
│  Infrastructure: rag/embeddings.py           │  ← dense primary / TF-IDF fallback
│                  rag/vectorstore.py          │  ← cosine+MMR+floor cache
│                  rag/ocr.py+chunking.py      │  ← extraction + sentence-aware chunking
│                  audio/tts.py + images/pexels│  ← external media providers
│                  database/database.py        │  ← SQLAlchemy engine/session
├──────────────────────────────────────────────┤
│  Persistence:   database/models.py           │  ← 10 relational tables, JSON cols, unique constraints
│                 data/sahlha.db (SQLite)      │  ← WAL not needed for MVP single-writer
│                 data/vectors.npz + pkl       │  ← vector cache (backend-tagged)
│                 data/uploads|audio|images    │  ← binary artifacts, hash-cached
└──────────────────────────────────────────────┘
```

### 4.2 High-Level Data Flow

```
Teacher uploads file
        │
        ▼
┌─────────────────┐   extract_document_text()   ┌──────────────┐
│ documents/upload│ ─────────────────────────► │   OCR layer  │─ pypdf / docx / txt / tesseract+poppler
└────────┬────────┘                            └──────┬───────┘
         │                                            │ text + {is_scanned, method, pages}
         ▼                                            ▼
   chunk_text()  (sentence-aware, overlap 120/800)
         │
         ▼
   persist Document + DocumentChunk rows  ──►  vectorstore.rebuild_index()
                                                      │  dense? incremental append : TF-IDF refit
                                                      ▼
                                               vectors.npz cache (ids, matrix, backend)

         ──────── Agent pipeline ─────────
         │
         ├─► extract_skills()              retrieve_lesson(top5) → LLM/fallback SkillList → register_skill (idempotent)
         ├─► explain_skills()              per skill: retrieve_relevant(top3) → LLM/fallback explanation → setup_skill → [audio+image]
         ├─► explain_lesson()              retrieve_lesson(top5) → LLM/fallback LessonExplanation → explain_lesson tool → audio
         └─► generate_lesson_banks()       per skill: retrieve_skill(4)→ LLM/fallback n=10 Qs → critique → top_up → save_questions → WAITING_FOR_TEACHER

         ──────── Teacher boundary ────────   (explicit, never auto-bypassed)
               approve / reject(+feedback) / flag(reason)

         ──────── Student path ────────────
   assessment/start  (student_id, course, lesson, [skill_id])
        │  get_approved_questions + history + perf + failed
        │  select_questions: exactly 4 per approved bank
        │      (failed-retry → weak (<0.6) → unseen → difficulty balance)
        │  create Assessment row + bundle lesson_overview + per-skill explanations
        ▼
   Student studies → answers 4×N (public payload never contains correct_answer)
        │
        ▼
   assessment/{id}/submit  → evaluate_answer → record_attempt → update_student_memory
        │                                           (scoped by bank course/lesson to avoid slug collisions)
        ▼
   skill accuracy + skills_needing_review (<0.5) → ADAPTATION phase
```

### 4.3 Agent State Machine — `sahlha/app/agent/state.py:11` + `sahlha/app/agent/agent.py:35`

Single agent, **8 explicit phases** over `AgentState` (Pydantic, serializable, trace-logged — not a raw while-loop):

```text
SKILL_EXTRACTION ─► SKILL_EXPLANATION ─► LESSON_EXPLANATION
       │                   │                      │
       └───────────────────┴──────────────────────┘
                              │
                    QUESTION_GENERATION (per skill, critique+top_up)
                              │
                    WAITING_FOR_TEACHER  ← human-in-the-loop hard boundary
                              │
                         ASSESSMENT (select 4 per bank, bundle explanations)
                              │
                         EVALUATION (evaluate+record+scoped memory update)
                              │
                         ADAPTATION (mastery signals → next assessment adapts)
```

- `AgentState` fields — `sahlha/app/agent/state.py:22`: `student_id, teacher_id, course/lesson/skill_id, current_phase, retrieved_context, skills[], current_question_ids[], current_answers{}, student_memory{}, assessment_result{}, trace[]`.
- Every transition and tool call appends to `trace` (`AgentState.log()` / `transition()`), surfaced in the Debug tab and API responses.
- Idempotency: `extract_skills(..., force=False)` returns existing skills; `explain_skills` skips already-explained rows (still fills media gaps).

### 4.4 RAG Architecture — `sahlha/app/rag/*`

```
bytes → extract_document_text()         # native vs scanned detection
        → clean/sentence packer          # chunk_text(): sentence-aware, overlap trailing sentences
        → DocumentChunk rows (with course/lesson/skill/page/chunk_index metadata)
        → get_embeddings()               # Dense MiniLM-L6-v2 384-d L2-norm || TF-IDF 5k ngram(1,2)
        → vectorstore.rebuild_index()    # TF-IDF: full refit | Dense: incremental append if <50% churn (40s→0.03s)
        → search(query, filters)         # 3× top_k cosine candidates → MMR(λ=0.7) diversity → score floor (dense 0.05)
                                         # → backoff to top-1 when floor starves context → lexical overlap last resort
```

- Dense vectors are `normalize_embeddings=True`; cosine = dot product.
- Cache: `data/vectors.npz` holds `(ids, matrix, backend)`; backend mismatch or corpus drift triggers rebuild.
- Retrieval never injects full documents into prompts — only capped retrieved chunks (`llm_max_context_chars`).

### 4.5 LLM Layer — `sahlha/app/agent/llm.py:1`

| Concern | Groq path | Fallback path |
|---|---|---|
| Provider detect | `sahlha/app/config.py:14` `GROQ_API_KEY` present → `groq` else `openai` else `""` |  |
| Question gen | `_call_llm()` → `generate_questions_llm()` → structured JSON parsed via `_extract_json_array` → Pydantic validate | `fallback_questions()`: sentence → blank-keyword MCQ, deterministic rotation, difficulty toggled by feedback |
| Skill split | `complete_json()` → `SkillList` validate | `fallback_skills()`: ~2 sentences per skill, slug from top term |
| Explanations | `complete_json()` → `SkillExplanation` / `LessonExplanationModel` | `fallback_explanation/lesson_explanation()`: intro + key points + example + anti-mistake |
| Critique | LLM critique (`enable_llm_critique` opt-in) → `CritiqueResult` | `fallback_critique()`: term-overlap ≥2 + `correct_answer` bounds check |
| Safety | any LLM exception → `fallback(...)` soft-fail, loop never breaks |  |

Token optimization (`sahlha/app/config.py:40`): `llm_max_context_chars=6000`, `llm_skill_context_chars=4000`, `enable_llm_critique=False` (deterministic gate saves ~50% tokens).

### 4.6 Database Schema — `sahlha/app/database/models.py`

```
documents(id[12hex], filename, course_id, lesson_id, skill_id, status[uploaded|processed|failed], char_count, chunk_count, created_at)
document_chunks(id, document_id→documents, course_id, lesson_id, skill_id, page, chunk_index, text)
skills(id, course_id, lesson_id, skill_id[slug UQ(course,lesson,skill)], name, description, explanation, key_concepts[JSON], image_url/path/alt, created_at, updated_at)
lesson_explanations(id, course_id, lesson_id UQ, title, explanation, key_concepts[JSON], created_at, updated_at)
question_banks(id, course_id, lesson_id, skill_id, version, status[pending_review|approved|rejected], teacher_feedback, created_at, updated_at)  UQ(course,lesson,skill,version) — append-only versions
questions(id, question_bank_id→banks, skill_id, question_type[multiple_choice], question_text, options[JSON], correct_answer[JSON:int], explanation, difficulty[ easy|medium|hard ], created_at)
students(id, name, created_at)
assessments(id, student_id→students, question_bank_id→banks (representative), course_id, lesson_id, question_ids[JSON list of Q ids], status[started|submitted], score[float], created_at)
student_attempts(id, student_id, question_id→questions, assessment_id→assessments, answer[JSON], correct[bool], timestamp)
student_skill_performance(id, student_id, course_id, lesson_id, skill_id, total_attempts, correct_attempts, accuracy[float], last_updated)  UQ(student,course,lesson,skill)
question_feedback(id, question_id→questions, kind[flag], reason, created_at)  append-only flags, feed next generation
```

Scoping invariant: performance is **scoped by (student, course, lesson, skill)** so identical slugs in different lessons never share counters. Same for flags → fed per-skill (`get_flag_reasons_for_skill`).

Append-only history: `question_banks.version` increments; `student_attempts`/`question_feedback` never overwrite.

### 4.7 API Surface — thin routers

```
POST /documents/upload                         → ingest_upload(bytes, course, lesson, skill)
POST /documents/{id}/process                   → re-process stored upload
POST /agent/extract-skills  {course,lesson,max_skills,force} → extract_skills + explain_skills + explain_lesson (bundled for convenience in services)
GET  /agent/skills?course_id&lesson_id[&skill_id]           → list_skills
POST /agent/explain-lesson {course,lesson,force}            → explain_lesson
GET  /agent/lesson?course_id&lesson_id                       → { lesson, skills[] } study bundle
POST /agent/generate-question-bank {course,lesson,skill,feedback,n} → generate_question_bank
POST /agent/generate-lesson-banks {course,lesson,feedback,n} → one bank per skill (N×10)
GET  /teacher/question-banks/pending?limit
GET  /teacher/question-banks/{id}            → bank + questions (teacher sees answers)
POST /teacher/question-banks/{id}/approve    → status approved
POST /teacher/question-banks/{id}/reject  {feedback} → rejected, feedback steers next version
POST /teacher/questions/{qid}/flag {reason}  → flag → excluded from future selections
GET  /teacher/flags?course_id&lesson_id[&skill_id]
POST /assessment/start {student_id,course,lesson,[skill_id]} → {assessment_id, questions (no answers), lesson_explanation, skill_explanations, selection_meta}
POST /assessment/{id}/submit {answers: {qid: int}} → {score, correct, total, results[correct, correct_answer, skill_id], skills_needing_review, skill_performance}
GET  /students/{id}/performance
GET  /students/{id}/skill-progress?course&lesson → per-skill {completed, has_explanation, exercise_ready, attempted, accuracy, needs_review}
GET  /audio/skill?course&lesson&skill[&voice]   → WAV 503 if no GROQ_API_KEY/terms
GET  /audio/lesson?course&lesson[&voice]
GET  /images/skill?course&lesson&skill          → JPEG 503 if no PEXELS_API_KEY
GET  /health, GET /
```

Routes live in `sahlha/app/api/routes_*.py` and each handler is one `svc.*` call.

### 4.8 Media Subsystems

- **Audio** `sahlha/app/audio/tts.py` + `sahlha/app/agent/tools/audio_tools.py` → `skill_explanation_to_audio / lesson_explanation_to_audio`: long text → 900-char sentence-aware splits → sequential Orpheus calls → WAV concat → `data/audio/{hash}.wav` cache.
- **Images** `sahlha/app/images/pexels.py` + `sahlha/app/agent/tools/image_tools.py` → `fetch_skill_image`: query = `skill.name + key_concepts`, cache `data/images/{skill}.jpg`, persist `skill.image_*` cols (migrated on startup if missing).

Both are **non-fatal**: explanation succeeds even when TTS/image fails; image/audio `503` is honest.

### 4.9 Feedback Loops (the adaptivity)

1. **Generation self-critique** `sahlha/app/agent/agent.py:227` — every draft bank → `critique_questions` (LLM if enabled else deterministic gate). Ungrounded/mis-answered items dropped → grounded `fallback_questions` top-up. Logged in trace.

2. **Teacher flag steering** `sahlha/app/agent/agent.py:210` + `sahlha/app/database/repositories/repositories.py:get_flag_reasons_for_skill` — flagged question reasons are auto-appended to the next generation's `teacher_feedback` for that skill (no retyping). Flagged questions permanently excluded from `select_questions`.

3. **Mastery review** `sahlha/app/agent/agent.py:388` — submit returns `skills_needing_review` (<50% that assessment) and `skill-progress.needs_review` is persistent per-skill. Student re-studies; teacher sees which banks/explanations fail. Next `select_questions` prioritizes weak skills (`accuracy <0.6`) and failed questions.

---

## 5. Frontend — `frontend/index.html:1`

The static SPA is a **test client, not production UI** — served by the API itself at `/app/`
(no extra process; the header `API` input points to FastAPI, default `http://127.0.0.1:8000`).

- **👩‍🏫 Teacher tab** — upload+process, extract skills (slider = upper bound cap 6), reload skills, generate N banks, review pending banks (per-question flag + per-bank approve/reject+feedback), `trace` + chunk metadata surfaced.
- **🧑‍🎓 Student tab** — catalog-aware course/lesson pickers, `skill_progress` bar, study bundle fetch (`GET /agent/lesson` single bundle), per-skill: image → explanation → 🔊 Listen → gated checkbox ("I've read") → start 4Q exercise → radio answers (no default) → submit → mastery warning + score + re-fetched progress; `performance` loader.
- **🛠️ Debug tab** — raw `trace` events + `selection_meta`, `skill_performance`, `retrieved_chunks`, `backend`, etc.

---

## 6. Key Design Decisions & Rationale

| Decision | Why |
|---|---|
| Single `SahlhaAgent` state-machine vs multi-agent / LLM-loop | Determinism, auditability (`trace`), phase validation; LLM reasons, app enforces |
| One bank per skill (vs one bank per lesson) | `skill = explanation + exercise` is the mastery unit; each bank approved independently; assessment covers every skill |
| Exactly 4 questions per bank in assessment | Bounded cognitive load, cross-skill coverage (`N*4` total), adaptive selection within budgets |
| Skill-scoped memory (`student,course,lesson,skill`) | Prevents slug collisions across lessons; recurrence-safe |
| Human-in-the-loop gate `WAITING_FOR_TEACHER` is hard | Never auto-bypasses teacher approval; rejected bank needs feedback-steered regen |
| Grounded fallback generators | Offline-capable, deterministic, term-overlap provably retrieves correct chunks (paraphrase test) |
| Dense primary + TF-IDF fallback | Semantic quality by default, resilience when torch/model offline |
| MMR + score floor + backoff | Diversity + relevance; starvation-free (`or picked[:1]`) |
| Incremental dense rebuild | Upload latency: 1700 chunks from ~40s → 0.03s when adding 5 |
| Append-only versions/attempts/feedback | Auditable lineage, never overwrite teacher decisions or student history |
| Deterministic 4-slot rotation of correct answer index | Avoids positional bias without LLM |

---

## 7. Installation & Running

### Requirements
- Python 3.12+
- Tesseract 5.4 + Poppler (for scanned PDFs/images): `winget install UB-Mannheim.TesseractOCR oschwartz10612.Poppler` or set `TESSERACT_CMD` / `POPPLER_PATH` in `.env`.

```powershell
pip install -r requirements.txt
copy .env.example .env   # fill GROQ_API_KEY for real LLM, PEXELS_API_KEY for images
python -m uvicorn sahlha.app.main:app --reload --port 8000
# open http://127.0.0.1:8000/app
```

Without `GROQ_API_KEY`, the agent auto-falls back — the UI and tests still pass.

### Environment — `.env.example:1`
- `GROQ_API_KEY`, `GROQ_MODEL=llama-3.3-70b-versatile`
- `PEXELS_API_KEY` (free at https://www.pexels.com/api/)
- `TESSERACT_CMD`, `POPPLER_PATH` overrides
- `DATABASE_URL=sqlite:///./data/sahlha.db`

---

## 8. Testing

```powershell
python -m pytest tests/ -q
# 11+ tests: RAG, generation, approve, reject→v2, assessment(×4), memory-adapts, HTTP loop, skill extraction+explanations, one-bank-per-skill, skill banks approve+assess, skill HTTP endpoints, plus OCR/audio/image/feedback suites
```

Test map:
- `test_rag.py` / `test_rag_proper.py` — ingestion→chunk→index→retrieval (incl. paraphrase with no shared keywords)
- `test_ocr.py` — scanned PNG/PDF through real Tesseract
- `test_questions.py` — generation → validation → approve
- `test_skills.py` — extraction → explanation → per-skill banks
- `test_assessment.py` — adaptive selection, evaluation, memory, mastery
- `test_feedback.py` — flag exclusion + feedback-steered regeneration
- `test_audio.py` / `test_images.py` / `test_media_autogen.py` — TTS/image generation + caching + auto-media path
- `test_api_loop.py` — `TestClient` HTTP loop upload→skills→banks→approve→start→submit

---

## 9. Known Limitations & Roadmap

| Current (MVP) | Next |
|---|---|
| TF-IDF fallback is lexical | Sentence-transformers + FAISS/Chroma as primary (interfaces isolated) |
| Single-writer SQLite, no auth, no pagination | Real auth, row-level scopes, pagination, Postgres |
| Question types: `multiple_choice` only (short answer grading via LLM planned) | LLM-graded free text, code MCQs, step-by-step hints |
| Flat assessments | Spaced repetition scheduler on top of `StudentSkillPerformance` + analytics over `student_attempts` |
| Manual lesson granularity | Auto course map / prerequisites graph |

---

## 10. References

- FastAPI: `sahlha/app/main.py:27`
- Config: `sahlha/app/config.py:5`
- Agent: `sahlha/app/agent/agent.py:35`, State: `sahlha/app/agent/state.py:11`, LLM: `sahlha/app/agent/llm.py:1`
- RAG: `sahlha/app/rag/ingestion.py:24`, `ocr.py:101`, `embeddings.py:71`, `vectorstore.py:33`, `chunking.py`
- DB: `sahlha/app/database/models.py:1`, `database.py`, `repositories/repositories.py`
- Services: `sahlha/app/services/services.py`
- Routes: `sahlha/app/api/routes_*.py`
- Media: `sahlha/app/audio/tts.py`, `sahlha/app/images/pexels.py`
- App client: `frontend/index.html:1` (served at `/app/`)
- Tests: `tests/*`
