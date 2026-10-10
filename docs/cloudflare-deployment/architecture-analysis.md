# Sahlah — Current Architecture Analysis

> Verified against the repository working tree (Oct 2026). File paths are relative to the repo root.
> Docs cross-checked: `README.md`, `PROJECT.md`, `architecture_overview.md`, `sahlha/app/*`, `mobile/*`,
> `workers/backend-proxy/*`, `Dockerfile`, `requirements.txt`, `.env.example`, `scripts/*`.
> No secrets are reproduced here — only variable **names** and purposes.

## 1. What Sahlah is

Sahlah is an AI-assisted learning platform (dyslexia/ADHD-friendly positioning, "same curriculum, different path to mastery").
The closed learning loop is:

```
Teacher/parent uploads material → OCR/ingestion → RAG index → agent splits lesson into skills
→ lesson overview + per-skill explanations (+ TTS audio + Pexels image)
→ one question bank per skill → teacher approval gate → student studies skill-by-skill
→ memory-aware assessment (4 questions per approved bank) → deterministic evaluation
→ attempts + scoped skill memory → mastery states → future practice adapts
```

## 2. Major components and roles

| Component | Location | Role |
|---|---|---|
| FastAPI backend | `sahlha/app/main.py`, `sahlha/app/api/*` (14 routers) | All business logic, auth/RBAC, agent orchestration, RAG, assessments, grades, media serving. Thin routers delegate to `services/*`; no SQL in routes. |
| Platform services | `sahlha/app/services/platform.py`, `mapping.py`, `mastery.py`, `profiles.py` | Classrooms, enrollment, materials, learning path, help-me, grades, mastery, parent links. `mapping.py` maps official material → `course_id="class:{classroom_id}"`, `lesson_id=material.id`; supplementary → `course_id="child:{student_id}"`. |
| Legacy AI-loop services | `sahlha/app/services/services.py` | Original upload/skills/banks/assessment flow reused by platform + Streamlit/tests. |
| Agent | `sahlha/app/agent/agent.py` (`SahlhaAgent`), `state.py`, `prompts.py`, `schemas.py`, `llm.py`, `providers.py`, `grounding.py`, `tools/*` | Deterministic Python state machine (8 phases). LLM only generates text/JSON; all IDs, scores, statuses, persistence are Python-controlled. See `agent-analysis.md`. |
| Optional LangGraph wrapper | `sahlha/app/workflow/graph.py`, `nodes.py`, `state.py` | Stateful teacher pipeline `retrieve → extract → lesson → generate → teacher_review (interrupt) → apply → regenerate/done/exhausted`. Checkpointer is in-process `MemorySaver` (restarts lose paused runs). Reuses `SahlhaAgent`/tools; no duplicated RAG/LLM logic. |
| RAG | `sahlha/app/rag/ingestion.py`, `ocr.py`, `chunking.py`, `text.py`, `textnorm.py`, `document.py`, `embeddings.py`, `vectorstore.py`, `retriever.py` | Upload → extract → chunk → persist → index → filtered search. See §5 and `agent-analysis.md` / `architecture-diagram.md`. |
| Database layer | `sahlha/app/database/models.py`, `database.py`, `repositories/repositories.py`, `repositories/platform.py` | SQLAlchemy 2.0 + SQLite (`data/sahlha.db` default). `repositories/*` are the only ORM-touching layers besides services (agent must go through tools — convention, not enforced). |
| TTS | `sahlha/app/audio/tts.py`, `speech.py`, `envelope.py`, `agent/tools/audio_tools.py` | Groq Orpheus primary → OpenRouter backup, 900-char chunking + WAV stitch, SHA-hash cache in `data/audio/`. Lip-sync envelope (`300` buckets) for mobile. No offline fallback — honest `503` without keys. |
| Images | `sahlha/app/images/pexels.py`, `agent/tools/image_tools.py`, `lesson_categories.py` | One related JPEG per skill via Pexels REST, cached in `data/images/`, `503` without key. Query is category-aware (code topics mapped to `programming education technology`). |
| Auth | `sahlha/app/auth/security.py` (PBKDF2 + PyJWT, 7-day expiry), `sahlha/app/auth/deps.py` (role guards), `sahlha/app/api/deps.py` (legacy `X-API-Key` gate) | Two coexisting schemes: platform JWT bearer (`teacher|student|parent` + classroom/parent-link ownership) and legacy `TEACHER_API_KEY` header gate (open when empty). Legacy auto-created `students` rows coexist with platform `users`. |
| Test clients | `frontend/index.html` (served at `/app/`), legacy `streamlit_app.py` (dev debug tool) | Not production UI. Teacher/student/debug tabs, catalog-aware, trace surfaced. |
| Product client | `mobile/` (Flutter: Riverpod, go_router, Dio, just_audio, flutter_markdown, secure storage) | All user-facing UI. `API_BASE_URL` is compile-time (`--dart-define API_BASE_URL=...`, default `http://10.0.2.2:8000` for Android emulator). See §8. |
| Container scaffold | `Dockerfile`, `workers/backend-proxy/*`, `scripts/cloudflare-*.ps1` | Pre-existing Cloudflare Containers path (proxy + deploy/tunnel scripts). Not yet production-hardened — see `deployment-plan.md`. |

## 3. How components communicate

```
Flutter (Dio + JWT bearer) ──HTTPS──▶ FastAPI (14 routers)
Static SPA (/app) ──same-origin──▶ FastAPI
Routes ──function call──▶ services/* ──function call──▶ SahlhaAgent ──function call──▶ tools/*
tools/* ──▶ repositories/* ──▶ SQLite; ──▶ rag/* ──▶ DB chunks + vectors.npz
tools/* ──HTTPS──▶ Groq / OpenRouter / Pexels (outbound only)
LangGraph nodes ──▶ same SahlhaAgent/tools via ContextVar DB session (never in graph state)
BackgroundTasks / threads ──▶ vectorstore.rebuild_index / audio prefetch (same process)
```

Key invariants (verified in code):

- Routes never touch ORM directly; services never embed/search vectors directly; agent never touches DB/vectors directly (only via `tools/`).
- Nothing is pushed to the agent — it **pulls** per phase via `rag_tools` (`retrieve_lesson top_k=5`, `retrieve_relevant_material top_k=3/4`).
- Assessment payloads **strip `correct_answer`** for students; teachers get full review payloads (`routes_teacher*`, `get_approved_questions` vs `get_latest_approved_questions`).
- Per-question `POST /student/assessments/{id}/check` **locks** the attempt at check time; `submit` reuses locked attempts (no double counting).

## 4. External services and dependencies

| Dependency | Type | Required? | Notes |
|---|---|---|---|
| Groq LLM + TTS (`GROQ_API_KEY`, `GROQ_MODEL=openai/gpt-oss-120b`, `GROQ_TTS_MODEL=canopylabs/orpheus-v1-english`, `GROQ_TTS_VOICE=troy`) | Outbound HTTPS | Optional (degrades to grounded fallback / `503` audio) | Native `groq` SDK preferred, `openai`-client compat fallback. 60s timeout, 1 retry, then single OpenRouter failover on retryable errors (429/5xx/408/timeout/quota/capacity/model-decommissioned; never 401/403/422). |
| OpenRouter LLM + TTS backup (`OPENROUTER_API_KEY`, `OPENROUTER_MODEL=openai/gpt-4o-mini`, `OPENROUTER_TTS_MODEL=fish-audio/s2.1-pro-free:free`, `OPENROUTER_TTS_VOICE=alloy`) | Outbound HTTPS | Optional | Auto-used only on Groq retryable failure. No code change needed. |
| Pexels (`PEXELS_API_KEY`) | Outbound HTTPS | Optional | `503` without key; explanation still succeeds. |
| Tesseract binary + language packs + Poppler (`TESSERACT_CMD`, `POPPLER_PATH`, `OCR_LANGUAGES=eng+ara` default per config, `OCR_MIN_CHARS=50`, `OCR_DPI=250`) | OS binaries | Needed for scanned PDFs/images only | Auto-detected (PATH → env → Windows defaults). `Dockerfile` installs `tesseract-ocr{,-eng,-ara}` + `poppler-utils`. Native-text PDF/DOCX/PPTX-fallback/TXT/MD need no binaries. |
| `sentence-transformers` + torch (dense embeddings) | Native Python packages | Optional | `DenseEmbeddingModel` tried first; any load failure → TF-IDF fallback. `requirements-ai.txt` marks it optional. `Dockerfile` does **not** pin torch — image size/startup risk, see §9. |
| `scikit-learn`, `numpy`, `pypdf`, `python-docx`, `python-pptx`, `Pillow`, `pytesseract`, `pdf2image`, `langgraph>=0.3`, `PyJWT`, `email-validator` | Pure/normal pip | Required | See `requirements.txt`. `python-pptx` is installed but `ocr.py` has **no `.pptx` branch** (falls to raw UTF-8 decode — likely garbled for binary PPTX; discrepancy, §9). |
| SQLite file | Local file | Required (current) | `DATABASE_URL=sqlite:///./data/sahlha.db`. Single-writer by design; `Dockerfile` runs `--workers 1`. |
| Local disk (`UPLOAD_DIR=./data/uploads`, `AUDIO_DIR=./data/audio`, `IMAGE_DIR=./data/images`, `VECTOR_CACHE_PATH=./data/vectors.npz`, `VECTORIZER_PATH=./data/tfidf_vectorizer.pkl`) | Local files | Required (current) | Traversal-safe names, hash caches. Ephemeral on Containers — production needs R2/external DB. |

## 5. Persistence — what must survive restarts

| Data | Where today | Must persist? |
|---|---|---|
| Relational rows (users, classrooms, enrollments, links, materials, profiles, documents, chunks, skills, lesson_explanations, banks v1..N, questions, students, assessments, attempts, skill_performance, feedback, counters, content_maps) | SQLite file `data/sahlha.db` (+ `_ensure_columns()` additive ALTERs + legacy backfills on every `init_db()`) | **Yes** — student history, approvals, grades are append-only and auditable. Loss = lost classrooms/grades. |
| Raw uploads | `data/uploads/<doc_id>_<sanitized>` | **Yes** (re-process + audit). Cap `MAX_UPLOAD_MB=25`. |
| Generated audio / images | `data/audio/{sha1}.wav`, `data/images/{skill}_{sha1}.jpg` (+ `.env.json` lip-sync envelopes) | **Yes** (cache; regenerable at LLM/TTS cost, but re-generation is slow/paid). |
| Vector index | `data/vectors.npz` (`ids, matrix, backend`) + TF-IDF pickle | **No (rebuildable)** — but rebuild of large corpora is expensive (dense full encode ~40s/1700 chunks; incremental append ~0.03s for small churn). Treat as warm cache, not source of truth (DB chunks are). |
| LangGraph checkpoints | In-process `MemorySaver` | **No today** (paused teacher runs die on restart). If durable teacher runs are required, this needs Redis/Postgres checkpointer — currently **not** implemented. |
| Embedding model weights (~90MB) | In-memory after first `get_embeddings()` (+ lifespan background warmup thread) | **No** (reloadable; ~9s cold start, locked singleton). |

## 6. Stateful vs stateless

- **Stateless:** all HTTP handlers (per-request `SessionLocal`), `SahlhaAgent` instances (constructed per call with caller-owned `Session`), LLM/TTS/Pexels clients, chunking/grounding/mastery functions.
- **Stateful (must be accounted for in deployment):**
  - SQLite file + local disk caches (single-writer; `--workers 1` assumed).
  - In-memory singletons: embedding model (`_embeddings` + lock), vector `.npz` disk cache, LangGraph `_checkpointer` + `_graph` module globals.
  - `ThreadPoolExecutor(max_workers=min(6, N))` fan-out in `generate_lesson_banks` / `explain_skills` (threads share the job dict; DB writes stay on the main thread by design — `_generate_bank_draft` is pure/no-DB).
  - `BackgroundTasks`: deferred `rebuild_index` after upload + audio prefetch (same-process threads; lost on crash/eviction; retrieval falls back to keyword ranking if index is cold).

## 7. Long-running / heavy operations

| Operation | Behavior | Cost class |
|---|---|---|
| Dense embedding load (first request) | ~9s, background-warmed at lifespan | CPU + memory spike, once per process |
| `rebuild_index` full dense encode | ~40s per ~1700 chunks; incremental ~0.03s when churn <50% | CPU-bound; off request thread via `BackgroundTasks` for uploads (`eager=False` on HTTP, `eager=True` in tests) |
| `extract_skills` → `explain_skills` → `explain_lesson` bundle | 1 + N + 1 LLM calls (N = skills, cap 6 default; hard cap 22 in config) + retrieval | Network-bound (LLM), sequential + threaded fan-out |
| `generate_lesson_banks` (N skills × `n` questions, default 6–10) | Threaded LLM drafts + deterministic critique/top-up per skill, then ordered persist | Network-bound + CPU validation; longest teacher action (Streamlit timeout hints: 300s) |
| TTS synthesis | 900-char chunks (target 550), sequential provider calls + WAV stitch | Network-bound; cached by content hash |
| OCR of scanned PDFs | `pdf2image` dpi 250 + Tesseract per page | CPU-bound, potentially tens of seconds for long scans; no queue today |
| Assessment start/submit | Pure DB + deterministic selection/evaluation; single commit for whole batch | Fast; must stay synchronous (student waits) |

No streaming responses, no WebSockets, no background queue (only `BackgroundTasks` + threads). No pagination on list endpoints (known limitation).

## 8. Frontend / mobile specifics

- Flutter `mobile/` is the product UI (auth, classrooms, materials, student/teacher/parent flows, audio playback via `just_audio`, markdown rendering). Verified: `api_config.dart` compiles `API_BASE_URL` from `--dart-define` (default `http://10.0.2.2:8000`); changing it requires **restart**, not hot reload. Token in `flutter_secure_storage` (bearer, not cookies — CORS stays explicit).
- `mobile/web/` exists (Flutter web scaffold) but the deployment target is mobile builds (`flutter build apk`, `flutter run`); no web hosting is currently wired.
- `frontend/index.html` is served same-origin at `/app/` (no CORS needed); Streamlit app is a dev-only debug tool.

## 9. Uncertainties / discrepancies found

1. **Embedding model name mismatch (needs a decision).** `config.py:14` default is `sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2`, but `rag/embeddings.py:15` hardcodes `sentence-transformers/all-MiniLM-L6-v2` (`DENSE_MODEL_NAME`). The multilingual default matches `OCR_LANGUAGES=eng+ara` intent; the hardcoded English MiniLM does not. Behavior depends on which path actually loads in the deployed image. Recommend pinning one model and removing the divergence before production (affects Vectorize dimension choice: 384 vs larger).
2. **`.pptx` listed as allowed but not parsed.** `allowed_extensions` includes `.pptx` and `python-pptx` is installed, yet `ocr.py` has no `.pptx` branch — files fall to raw UTF-8 decode. Native PPTX uploads likely ingest garbage. Either add a `python-pptx` extractor or remove `.pptx` from allowed types.
3. **`architecture_overview.md` is newer than `PROJECT.md`/`README.md`.** Model defaults (`openai/gpt-oss-120b` vs `llama-3.3-70b-versatile`), skill-cap semantics (slider cap 6 vs dynamic 6/22 caps), and media pipeline details differ across docs. `architecture_overview.md` matches the current code most closely; treat it as primary until docs are reconciled.
4. **Legacy vs platform duality.** `LEGACY_DEV_API_ENABLED` is mounted unconditionally; legacy auto-created `students` and platform `users` coexist. Safe for demo, but production must decide whether to gate legacy routes (`TEACHER_API_KEY` / disable flag) to avoid unauthenticated content/assessment paths.
5. **Demo seed in production risk.** `seed_demo_student()` runs on every `init_db()` unless `SAHLHA_SEED_DEMO=0` or `ENVIRONMENT=production`. Production must set one of these.
6. **No CI/CD, no migrations framework, no pagination.** `_ensure_columns()` is hand-rolled SQLite-only (`engine.dialect.name != "sqlite"` → no-op). Any move to Postgres/D1 requires a real migration story (Alembic or equivalent) — budgeted in `deployment-plan.md` Stage 2.
7. **Reranker present but not wired.** `RERANKER_ENABLED=false` + health probe only; `content-intelligence.md`/`learning_content.py` schemas exist without production callers. Do not provision reranker infra for MVP.
