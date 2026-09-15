# Project Changelog

A chronological record of meaningful changes, upgrades, fixes, architectural changes, and implemented features for **Sahlha.ai**. The codebase is the source of truth; architecture docs and git history are secondary evidence. Dates use git history where reliable; otherwise `2026-09-15 — Current State Audit` for the present working-tree inspection.

---

## 2026-09-14 — Initial Project Scaffolding

### Type
- Infrastructure / Documentation

### What Changed
- Created repository with `LICENSE`, minimal `README.md`, and `.gitignore` (`__pycache__/`, `.env`, `data/`, `.pytest_cache/`).
- No source code, no dependencies, no runtime.

### Why
- Establish repo hygiene and licensing before code landed.

### Implementation
- Files: `LICENSE`, `README.md` (initial), `.gitignore:1` (seen in `git show 5b9165d --name-only`).

### Architecture Impact
- None — empty scaffold. Old flow: (none) → New flow: (none).

### Dependencies / Technologies
- None.

### Status
- Implemented

### Notes
- Git commit `5b9165d 2026-09-14 Initial commit`.

---

## 2026-09-14 — Learning-Loop MVP (RAG, Single Agent, Skill Banks, Assessment, Audio, Images)

### Type
- Feature / Architecture / Backend / AI / Frontend / Infrastructure

### What Changed
- Shipped the first functional prototype proving the full closed loop: `upload → OCR → RAG → agent splits lesson into skills → writes lesson overview + per-skill explanation → one 10-question bank per skill → teacher approve/reject → student studies (lesson + skills) → adaptive assessment (4 questions per approved bank) → evaluate → record attempts → update skill memory → next assessment adapts`.
- Introduced layered architecture: FastAPI thin routers → `services/services.py` → agent state-machine → tool facades → `rag/*` + `database/repositories` + `audio/tts`/`images/pexels` → SQLite + `vectors.npz` cache.

### Why
- Validate the learning model end-to-end (`skill = explanation + exercise`) before hardening, auth, or pagination.

### Implementation
- **API entrypoint** `sahlha/app/main.py:27` — `FastAPI(title="Sahlha AI Learning Agent (MVP)", lifespan=init_db+warm embeddings)`, CORS `allow_origins=["*"]`, inclusion of `routes_documents`, `routes_agent`, `routes_teacher`, `routes_assessment`, `routes_audio`, `routes_images` (routes_catalog added later, see audit entries).
- **Config** `sahlha/app/config.py:5` — `Settings(BaseSettings)` covering `database_url`, `upload_dir`, `vectorizer_path`, `groq_api_key/model/base_url`, `chunk_size=800/chunk_overlap=120`, `top_k_retrieval=5`, `assessment_num_questions=4`, `llm_max_context_chars=6000/skill=4000`, `enable_llm_critique=False`.
- **RAG** `sahlha/app/rag/ingestion.py:24` `bytes → extract_document_text() → chunk_text() → persist chunks → rebuild_index()`; `sahlha/app/rag/ocr.py:101` native vs scanned detection; `sahlha/app/rag/chunking.py` overlapping char chunker; `sahlha/app/rag/embeddings.py` TF-IDF `max_features=5000 ngram(1,2)`; `sahlha/app/rag/vectorstore.py:33` cosine + MMR λ=0.7 + score floor + backoff; `sahlha/app/rag/retriever.py` filtered retrieval.
- **Database** `sahlha/app/database/models.py:1` + `sahlha/app/database/database.py` — 8 tables: `documents`, `document_chunks`, `skills` (UQ course/lesson/skill), `lesson_explanations` (UQ course/lesson), `question_banks` (UQ course/lesson/skill/version, append-only), `questions`, `students`, `assessments`, `student_attempts`, `student_skill_performance` (UQ student/skill). `init_db()` creates tables.
- **Agent** `sahlha/app/agent/agent.py:35` — `SahlhaAgent` explicit state-machine over `AgentState` `sahlha/app/agent/state.py:11` (`SKILL_EXTRACTION → SKILL_EXPLANATION → LESSON_EXPLANATION → QUESTION_GENERATION → WAITING_FOR_TEACHER → ASSESSMENT → EVALUATION → ADAPTATION`), `trace[]` logging every phase/tool. `sahlha/app/agent/llm.py:1` Groq via native SDK + `groq>=0.11` / `openai>=1.30` compat at `https://api.groq.com/openai/v1`, `temperature 0.4`, `response_format json_object`, plus deterministic `fallback_questions/skills/explanation/lesson/critique`. `sahlha/app/agent/prompts.py:1` grounded prompts (question generation, skill extraction, explanations, critique). `sahlha/app/agent/schemas.py:1` `GeneratedQuestion/QuestionList/ExtractedSkill/SkillList/SkillExplanation/LessonExplanationModel/CritiqueResult`.
- **Tools** `sahlha/app/agent/tools/rag_tools.py` (`retrieve_lesson/skill_material/relevant_material`), `question_tools.py` (`save_questions/get_question_bank/get_approved_questions`), `student_tools.py` (`history/failed/skill_performance/update_memory`), `assessment_tools.py` (`select_questions/evaluate_answer/record_attempt`), `audio_tools.py` (`skill/lesson_explanation_to_audio`), `image_tools.py` (`fetch_skill_image`). Invariant: agent never touches DB/vector directly.
- **Services** `sahlha/app/services/services.py:1` — `upload_and_process`, `extract_skills` (bundles extraction + explain_skills + explain_lesson), `generate_bank/generate_lesson_banks`, `approve/reject/flag`, `start/submit_assessment`, `student_performance/skill_progress`.
- **Routes** Thin handlers: `routes_documents.py:POST /documents/upload`, `POST /documents/{id}/process`; `routes_agent.py:POST /agent/extract-skills|/generate-question-bank|/generate-lesson-banks, GET /agent/skills|/lesson, POST /agent/explain-lesson`; `routes_teacher.py:GET pending/GET bank/POST approve|reject/POST flag/GET flags`; `routes_assessment.py:POST /assessment/start|submit, GET /students/{id}/performance|/skill-progress`; `routes_audio.py:GET /audio/skill|/lesson`; `routes_images.py:GET /images/skill`; `GET /health, GET /`.
- **Frontend** `streamlit_app.py:1` — 3-tab test client (Teacher/Student/Debug) driven by `SAHLHA_API` (`http://127.0.0.1:8000`), upload→extract→generate→approve→study→assess→debug trace.
- **Media** `sahlha/app/audio/tts.py:1` Groq Orpheus `canopylabs/orpheus-v1-english` voice `troy`, 900-char sentence-aware split + WAV stitch, `data/audio/{hash}.wav` cache; `sahlha/app/images/pexels.py:1` Pexels landscape search + disk cache `data/images/`, `503` when no key.
- **Tests** `tests/conftest.py`, `test_rag.py`, `test_questions.py`, `test_assessment.py`, `test_skills.py`, `test_api_loop.py`, `test_audio.py`, `test_images.py`.

### Architecture Impact
- Previous: empty repo. Current:
```
File bytes → OCR (pypdf/docx/txt vs scanned detection)
        → clean → sentence-aware chunk (overlap) → Document + DocumentChunk rows → vectorstore rebuild
        → [Agent: extract_skills → explain_skills → explain_lesson → generate_lesson_banks (N×10, critique+top-up) ]
        → WAITING_FOR_TEACHER (approve/reject/flag — never auto-bypassed)
        → Student: GET /agent/lesson bundle → per-skill study (explanation+image+audio) → POST /assessment/start (4 per bank, memory-aware)
        → POST /assessment/{id}/submit → evaluate → record_attempt → update scoped skill memory → ADAPTATION + mastery (<50%)
```

### Dependencies / Technologies
- `fastapi>=0.110`, `uvicorn[standard]>=0.29`, `sqlalchemy>=2.0`, `pydantic>=2.6`, `pydantic-settings>=2.2`, `python-multipart>=0.0.9`, `numpy>=1.26`, `scikit-learn>=1.4` (TF-IDF), `pypdf>=4.0`, `python-docx>=1.1`, `Pillow>=10.0`, `requests>=2.31`, `streamlit>=1.33`, `pytest>=8.0`, `httpx>=0.27`, `groq>=0.11`, `openai>=1.30`, `pytesseract>=0.3.10`, `pdf2image>=1.17` (see `requirements.txt:1`). Tesseract 5.4 + Poppler binaries external.

### Status
- Implemented (commit `94f8c37 2026-09-14 Sahlha AI learning-loop MVP: RAG, skill agent, banks, assessment, audio, images` — 36 files).

### Notes
- SQLite `data/sahlha.db`, uploads `data/uploads/`, vectors `data/tfidf_vectorizer.pkl` + `vectors.npz`. No auth/pagination — intentional MVP.
- Grounded generation invariant: only retrieved chunks enter prompts; fallback builds stems from chunk sentences.

---

## 2026-09-14 — Skill Count Cap and Frontend Serialization Fix

### Type
- Fix / Refactor

### What Changed
- Hard-capped lesson decomposition to `max_skills ∈ [1,6]` (slider `max_skills (upper bound, hard cap 6)`). Agent still decides actual count; cap is a safety bound. `ExtractSkillsRequest.max_skills` `ge=1 le=6` and `SahlhaAgent.extract_skills(... max_skills=6, force=False)` + `n_skills` deprecated alias.
- Fixed radio-button option serialization in assessment UI (deterministic `index=None` until answered, `format_func` renders option text, avoids default-selection bias and JSON shape mismatch).

### Why
- Prevent runaway skill counts on long lessons (token/cost + teacher triage) and fix client bug where unanswered radios submitted as `0` or wrong types.

### Implementation
- `sahlha/app/agent/agent.py:41` `extract_skills` now `raw[:max(1,max_skills)]`; `sahlha/app/agent/schemas.py` `QuestionList` validator enforces `len(options)==4` and `0<=correct_answer<=3`.
- `sahlha/app/schemas/api.py:12` `ExtractSkillsRequest(max_skills=6)`, `streamlit_app.py:310` `st.radio(..., index=None, format_func=...)`.

### Architecture Impact
- No flow change; tightens parameter validation and UI contract.

### Dependencies / Technologies
- None new.

### Status
- Implemented (commit `d64d4fc 2026-09-14 Cap skills at 6 per lesson; fix radio options serialization` — 6 files).

### Notes
- Remaining working-tree drift beyond this commit is documented below as the 2026-09-15 audit.

---

## 2026-09-15 — Current State Audit: RAG Subsystem Upgrade (Dense Embeddings, Incremental Index, Retrieval Quality)

### Type
- Upgrade / Architecture / Performance

### What Changed
- **Dense primary with TF-IDF fallback.** `get_embeddings()` (`sahlha/app/rag/embeddings.py:71`) now tries `DenseEmbeddingModel` (`sentence-transformers/all-MiniLM-L6-v2`, 384-d, `normalize_embeddings=True` → cosine = dot) and falls back to `TfidfEmbeddingModel` (`max_features=5000`, `ngram(1,2)`, `stop_words="english"`) only when `torch`/model unavailable. Cache records backend tag; mismatch triggers rebuild. `requirements.txt:9` adds `sentence-transformers>=3.0` with comment documenting fallback.
- **Incremental dense rebuild.** `sahlha/app/rag/vectorstore.py:33` `rebuild_index()` now distinguishes backends: TF-IDF still refits on full corpus, but dense reuses `data/vectors.npz` (`ids, matrix, backend`). When cached IDs are a subset and churn <50%, only missing texts are encoded and reassembled in original order — upload of 5 chunks into 1700 drops from ~40s to ~0.03s. `data/vectors.npz` replaces ad-hoc pickles; `vectorizer_path` still `./data/tfidf_vectorizer.pkl` but `vectors.npz` holds the real matrix now.
- **MMR + calibrated floor + starvation backoff.** `vectorstore.py:21` `MMR_LAMBDA=0.7`, `MIN_SCORE=0.05` (dense calibrated: paraphrase ~0.09, junk ~0.02), `3× top_k` candidate pull → MMR diversity → floor drop with `or picked[:1]` guarantee so the agent is never starved of context. Lexical overlap is last resort when cache miss cannot rebuild. Proven by `tests/test_rag_proper.py:42` — a paraphrase with (almost) no shared keywords still retrieves the `elif` material (`score>0.05`).
- **Sentence-aware chunking hardening.** `sahlha/app/rag/chunking.py:1` now packs whole sentences (regex `(?<=[.!?])\s+`), hard-splits only monster sentences >`chunk_size`, trailing-sentence overlap carried to next chunk (`~120` chars), `clean_text()` collapses whitespace, `_make()` keeps `course/lesson/skill/page/chunk_index` metadata.
- **Retriever filtering preserved.** `sahlha/app/rag/retriever.py` thin wrapper stays; `vectorstore.search()` itself is the filtered semantic search with `course_id/lesson_id/skill_id` predicates plus global fallback.
- **Lifecycle warming.** `sahlha/app/main.py:12` `lifespan` now does `init_db()` and `threading.Thread(target=get_embeddings, daemon=True).start()` to pay dense cold-start off the request path. `sahlha/app/database/database.py:26` `init_db()` calls `Base.metadata.create_all` then `_ensure_columns()`.

### Why
- TF-IDF alone failed paraphrase tests; dense is required for semantic quality. Full re-encode on every upload killed latency. MMR + floor balances diversity vs relevance without starvation.

### Implementation
- Files: `sahlha/app/rag/embeddings.py:18` (`DenseEmbeddingModel`/`TfidfEmbeddingModel`/`get_embeddings`/`dense_available`), `sahlha/app/rag/vectorstore.py:33` (`_cache_path`, `rebuild_index`, `_load_cache`, `_mmr`, `search`, `_hit`), `sahlha/app/rag/chunking.py:18` (`clean_text`, `_sentences`, `chunk_text`, `_make`), `sahlha/app/rag/retriever.py`, `sahlha/app/main.py:12` (lifespan), `sahlha/app/database/database.py:29` (migrations), `requirements.txt:9`.
- Tests: `tests/test_rag_proper.py:17` (`test_chunks_never_split_mid_sentence`, `test_rebuild_caches_vectors`, `test_semantic_paraphrase_retrieval` skipped when `dense_available()==False`).

### Architecture Impact
- Previous (MVP):
```
chunk → TF-IDF fit on full corpus → cosine top-k → return
```
- Current:
```
chunk (sentence-aware, overlap) → Dense MiniLM (384-d, L2) || TF-IDF fallback → cache (ids+matrix+backend)
      → 3×cosine candidates → MMR(λ=0.7) → score floor (dense 0.05) + backoff → lexical last resort
      → incremental append when churn <50% (0.03s) else full encode
```
- Swappable interface preserved — `vectorstore.search()` signature unchanged; `embeddings.py` can be replaced by FAISS/Chroma behind same contract.

### Dependencies / Technologies
- Added `sentence-transformers>=3.0` (primary), `scikit-learn` remains fallback, `numpy>=1.26` for cosine/MMR. No new external service.

### Status
- Implemented (verified in working tree: `embeddings.py:18` class exists, `vectorstore.py:33` incremental logic exists, `test_rag_proper.py` passes conceptually; git diff shows +79/+154 lines vs HEAD).

### Notes
- `sahlha/app/rag/ingestion.py:79` still delegates to `vectorstore.rebuild_index()` — `eager=True` in tests, `eager=False` + background task in HTTP path (see Ingestion entry).
- Cache lives in `os.path.dirname(settings.vectorizer_path)/vectors.npz`; backend string is `dense:sentence-transformers/all-MiniLM-L6-v2` or `tfidf`.

---

## 2026-09-15 — Current State Audit: OCR Provider Hardening and Document Ingestion Robustness

### Type
- Upgrade / Fix

### What Changed
- **OCR provider interface hardened.** `sahlha/app/rag/ocr.py:1` `ExtractedDocument(text, num_pages, is_scanned, method)` now explicitly distinguishes native vs scanned. Native pdf path `_extract_pdf_native()` via `pypdf.PdfReader`; threshold `len(text.strip())>=50` otherwise falls through to `_try_ocr_images()`. Tesseract resolution via `_tesseract_cmd()` (checks `PATH` → `TESSERACT_CMD` → `C:\Program Files\Tesseract-OCR\tesseract.exe`). Poppler resolution via `_poppler_path()` (checks `pdftoppm` on PATH → `POPPLER_PATH` → WinGet `Packages/*oppler*/**/pdftoppm.exe`). Image inputs (png/jpg/jpeg/tiff/bmp) go straight to `_try_ocr_images()`. Every result reports `method` (`pypdf|docx|txt|ocr:tesseract|ocr:tesseract(pdf2image)|ocr:unavailable|ocr:failed`).
- **Chunk metadata enrichment.** `ingestion.py:24` `_extract_lesson_id()` auto-derives a slug from PDF content when user leaves `lesson_id` as `lesson_1`/`general`: prefers first meaningful line of extracted text (skips `Page N`, `Table of contents`), then filename stem, up to 6 words, snake_case, max 80 chars. `_safe_filename()` sanitizes `filename` to prevent path traversal (`[^A-Za-z0-9._-]` → `_`, cap 120 chars + `doc_id` prefix). `chunk_text()` now receives explicit `course/lesson/skill/document_id/page`.
- **Background vs eager indexing split.** `sahlha/app/api/routes_documents.py:13` `_background_warm_index()` rebuilds vectors off the request thread via `SessionLocal`; `POST /documents/upload` now calls `ingest_upload(..., eager=False)` and schedules `background_tasks.add_task(_background_warm_index)` when `chunk_count>0`. Direct `ingestion.ingest_upload(eager=True)` path remains for tests.

### Why
- MVP scanned-PDF path was best-effort and leaked failures. Teacher UX needed filename/path safety and zero-config lesson naming for bulk PDF drops.

### Implementation
- Files: `sahlha/app/rag/ocr.py:39` (`_tesseract_cmd`, `_poppler_path`, `_try_ocr_images`, `extract_document_text`), `sahlha/app/rag/ingestion.py:15` (`_safe_filename`, `_extract_lesson_id`, `ingest_upload`), `sahlha/app/api/routes_documents.py:13` (background task), `sahlha/app/config.py:5` (settings unchanged but `TESSERACT_CMD`/`POPPLER_PATH` read via `os.getenv`).
- Tests: `tests/test_ocr.py` (new, untracked) proves scanned PNG/PDFs are actually read via real Tesseract; `tests/conftest.py:17` `_no_external_keys` still hermetic except OCR tests set env overrides.

### Architecture Impact
- Previous: `upload bytes → pypdf or raw decode → chunk → persist → rebuild` (scanned PDFs often empty, filename unsanitized, lesson_id required).
- Current:
```
upload bytes → extract_document_text() [pypdf → threshold 50 chars → real tesseract+pdf2image if needed]
            → _extract_lesson_id() auto-slug from content/filename
            → _safe_filename() sanitized write to data/uploads/
            → chunk_text(sentence-aware) → add_chunks → mark_document_processed(is_scanned, method)
            → if chunk_count>0: background_tasks → vectorstore.rebuild_index() (fast return 200)
```

### Dependencies / Technologies
- `pypdf>=4.0`, `python-docx>=1.1`, `Pillow>=10.0`, `pytesseract>=0.3.10`, `pdf2image>=1.17`, external binaries Tesseract 5.4 + Poppler (winget `UB-Mannheim.TesseractOCR` + `oschwartz10612.Poppler` or env overrides). No new provider.

### Status
- Implemented (diff `ocr.py +44`, `ingestion.py +70`, `routes_documents.py +35`; file system checks confirm methods and background task exist).

### Notes
- `ingestion.ingest_upload()` caps 25 MB, returns `{document_id, filename, course_id, lesson_id, skill_id, method, is_scanned, num_pages, char_count, chunk_count, text_preview}` — `lesson_id` is the auto-extracted value, overwritten before `create_document`.
- OCR failures are non-fatal: `ocr:failed (exc)` still returns a result; ingestion never crashes.

---

## 2026-09-15 — Current State Audit: LLM Provider Abstraction (Groq Primary → OpenRouter Backup → Deterministic Fallback)

### Type
- Upgrade / Architecture / Infrastructure

### What Changed
- **Single-failover LLM abstraction.** `sahlha/app/agent/llm.py:15` `_resolve_provider() → (provider, api_key, model)` now resolves `groq` (if `GROQ_API_KEY`) else `openrouter` (if `OPENROUTER_API_KEY`) else `openai` else `""`. Groq call (`_call_groq`) uses `groq.Groq` native SDK first, then `openai.OpenAI(base_url=GROQ_BASE_URL)` compat. OpenRouter call (`_call_openrouter`) uses `openai.OpenAI(base_url=OPENROUTER_BASE_URL)` with `temperature 0.4`, `max_tokens 2000`, `response_format json_object`. `_call_llm()` does **Groq → on retryable failure → one OpenRouter retry**, no loop. Provider reporting returns `"groq"` or `"openrouter"` as `backend`.
- **Retryability gate.** `_is_retryable_llm_error()` (`llm.py:54`) only failovers on transient/provider errors: `429`, `500-599`, `408`, or phrases `rate limit/quota/exhausted/overloaded/unavailable/timeout/capacity/5xx/provider` plus `model does not exist / decommissioned / json_validate_failed`. Explicitly excludes `invalid api key/unauthorized/forbidden/invalid_request/validation` for `400-499`. `404 model_not_found` is retryable (deprecated model → try backup).
- **Deterministic grounded fallback stays primary offline path.** `generate_questions_llm()` (`llm.py:257`) → if `llm_available()` tries `_call_llm()` otherwise immediately `fallback_questions()`; any `Exception` → `fallback_questions(..., backend=f"fallback(llm-error: {exc})")`. `complete_json()` raises `RuntimeError("no-llm-configured")` so callers can use `fallback_skills/explanation/lesson_explanation/critique`. All fallbacks remain grounded (build stems from chunk sentences, keyword blank-out MCQ with deterministic `i%4` rotation).
- **Configuration.** `sahlha/app/config.py:23` new fields `openrouter_api_key/base_url/model` (`OPENROUTER_API_KEY`, `OPENROUTER_BASE_URL=https://openrouter.ai/api/v1`, `OPENROUTER_MODEL=openai/gpt-4o-mini`), plus legacy `openai_*` still supported when Groq absent. `.env.example:4` documents `GROQ_API_KEY/GROQ_MODEL/openai/gpt-oss-120b`, `OPENROUTER_API_KEY/MODEL/BASE_URL`, backup purpose, and that OpenRouter is auto-used only on Groq failure (no code change needed).
- **Coverage.** New hermetic suite `tests/test_provider_fallback.py:1` covers 6 LLM scenarios (groq succeeds without calling OR, 429→OR, both fail→deterministic, no OR key→deterministic, non-retryable 400 doesn't fallback, OR direct when no Groq).

### Why
- Groq free-tier rate limits / quota / decommissioned models broke generation (e.g. `llama-3.3-70b-versatile` 404s). A resilient backup without user code changes plus guaranteed offline fallback keeps the learning loop never-broken.

### Implementation
- Files: `sahlha/app/agent/llm.py:15` (`_resolve_provider`, `_get_openrouter_key`, `_is_retryable_llm_error`, `_call_groq`, `_call_openrouter`, `_call_llm`, `_extract_json_array`, `fallback_*`, `generate_questions_llm`, `complete_json`, `critique_questions`), `sahlha/app/config.py:23` (OpenRouter settings), `.env.example:4` (docs), `tests/test_provider_fallback.py:24` (LLM section).
- Prior HEAD `llm.py` had only groq/openai or empty; diff shows +207 lines adding openrouter path.

### Architecture Impact
- Previous: `llm_available ? groq/openai : deterministic fallback` (binary; groq outage = fallback immediately).
- Current:
```
provider = groq if GROQ_API_KEY else openrouter if OPENROUTER_API_KEY else openai else ""
if provider=="groq": try _call_groq() except retryable & OR key → _call_openrouter() (once) else raise
if provider=="openrouter": _call_openrouter() directly
if provider=="": raise → caller uses grounded fallback
any LLM exception → fallback_questions/skills/explanation (loop never breaks)
```
- Critique path also benefits: `agent.py:233` checks `settings.enable_llm_critique` (default False deterministic, opt-in LLM) — when LLM critique fails it falls soft to `fallback_critique`.

### Dependencies / Technologies
- Providers: **Groq** primary (`GROQ_API_KEY`, `GROQ_MODEL` default `openai/gpt-oss-120b` per current config, was `llama-3.3-70b-versatile` in MVP commit; both legacy docs and new config accepted via `os.getenv("GROQ_MODEL", settings.groq_model)`), model `canopylabs/orpheus-v1-english` for TTS separate. **OpenRouter** backup (`OPENROUTER_API_KEY`, `OPENROUTER_MODEL` default `openai/gpt-4o-mini`, `OPENROUTER_BASE_URL=https://openrouter.ai/api/v1`) — OpenAI-compatible via `openai>=1.30` client. **Deterministic** grounded fallback — always available, never hallucinates.

### Status
- Implemented (working tree verified; env vars read in `config.py:23` and `llm.py:20`, 6 tests pass hermetically via monkeypatch).

### Notes
- `GROQ_MODEL=openai/gpt-oss-120b` in current `.env.example:3` reflects the newest default; MVP README still mentions `llama-3.3-70b-versatile` — both work via `GROQ_MODEL` override. Do not invent additional providers.
- `OPENROUTER_API_KEY` must be set to enable the backup; without it behavior is exactly `Groq → deterministic fallback` as before.

---

## 2026-09-15 — Current State Audit: TTS Provider Chain (Groq Orpheus → OpenRouter Backup, Chunked Stitching, Hash Cache)

### Type
- Upgrade / Fix / Infrastructure

### What Changed
- **Two-provider TTS with shared chunking/stitching.** `sahlha/app/audio/tts.py:175` `synthesize(text, voice?) → (bytes, voice_used)` now: if `GROQ_API_KEY` present try Groq Orpheus (`groq.Groq.audio.speech.create(model=GROQ_TTS_MODEL, voice=voice_groq)`) chunked at `settings.groq_tts_max_chars=900` via `split_for_tts()` → `stitch_wavs()`; on `_is_retryable_tts_error()` (429/5xx/timeout phrases, excluding invalid key) and `OPENROUTER_API_KEY` present, falls through to OpenRouter TTS; otherwise raises. If no Groq key but OR key present, goes direct to OR. OR path (`_synthesize_chunk_openrouter`) tries `response_format` `mp3` then `pcm` per docs (`wav` is invalid → ZodError) and candidate models `[configured, openai/gpt-4o-mini-tts-2025-12-15, mistralai/voxtral-mini-tts-2603]` with 404-model→next-candidate logic, then stitches (`wav` via `wave` concat, `mp3` via `b"".join`, `pcm` normalized via `_pcm_to_wav` at 24kHz mono 16-bit).
- **Config.** `sahlha/app/config.py:35` `openrouter_tts_model=fish-audio/s2.1-pro-free:free`, `openrouter_tts_voice=alloy` (`.env.example:14` docs reference `openai/gpt-4o-mini-tts` `alloy` as default but current value is `fish-audio/s2.1-pro-free:free` — free-tier friendly; both valid). `groq_tts_model=canopylabs/orpheus-v1-english`, `groq_tts_voice=troy`, `groq_tts_max_chars=900`, `audio_dir=./data/audio`.
- **Audio tools hash cache.** `sahlha/app/agent/tools/audio_tools.py:23` `expected_path(text, voice)` hashes `f"{groq_tts_model}|{voice}|{text}"` SHA1[:16] → `data/audio/{hash}.wav`; `_cached_or_synth` reuses file if exists, else calls `tts.synthesize` and writes. `skill_explanation_to_audio` (`audio_tools.py:50`) composes `f"{name}. {explanation}"`, `lesson_explanation_to_audio:65` composes `f"{title}. {explanation}"` — both raise if explanation missing.
- **Non-fatal media contract preserved.** `sahlha/app/agent/tools/explanation_tools.py:13` wraps audio/image calls in `try/except` → `{"status":"skipped","reason": str(exc)[:500]}` — explanation persists even when TTS fails; HTTP `GET /audio/*` returns `503` when no provider key.

### Why
- Groq Orpheus free tier frequently 429s; students need speech without manual retry. OpenRouter offers pay-as-you-go/free models with same OpenAI-compatible audio endpoint.

### Implementation
- Files: `sahlha/app/audio/tts.py:1` (`tts_available`, `_is_retryable_tts_error`, `split_for_tts`, `stitch_wavs`, `_synthesize_chunk`, `_synthesize_chunk_openrouter`, `synthesize`), `sahlha/app/agent/tools/audio_tools.py:1` (hash cache, skill/lesson wrappers), `sahlha/app/agent/tools/explanation_tools.py:47` (fan-out), `sahlha/app/config.py:28` (TTS settings), `.env.example:9` (TTS docs), `sahlha/app/api/routes_audio.py` (unchanged but now benefits from OR fallback).
- Tests: `tests/test_audio.py` (existing), `tests/test_provider_fallback.py:149` (4 TTS scenarios: groq succeeds without OR, 429→OR, both fail raises, OR direct when no groq with voice `alloy`), `tests/test_media_autogen.py` (new, auto-media path).

### Architecture Impact
- Previous (MVP): `explanation → split 900 → Groq Orpheus → stitch → cache; no backup; 503 if no key or Groq down`.
- Current:
```
explanation text → skill_audio_text(name+explanation) → expected_path(hash) ? cached : synthesize()
synthesize: Groq(voice troy) chunks → wav stitch  ──retryable? & OR key?──→ OpenRouter(voice alloy, mp3/pcm→wav) chunks → stitch
          → none available → RuntimeError → explanation_tools records skipped, HTTP 503
```

### Dependencies / Technologies
- APIs: **Groq Orpheus** `canopylabs/orpheus-v1-english` voice `troy` (requires `GROQ_API_KEY` + accepted model terms in Groq console) — primary. **OpenRouter** `POST /api/v1/audio/speech` model `fish-audio/s2.1-pro-free:free` (or `openai/gpt-4o-mini-tts-2025-12-15`) voice `alloy` — backup when Groq 429/5xx/timeout and `OPENROUTER_API_KEY` set. Env: `GROQ_API_KEY`, `GROQ_TTS_MODEL/VOICE`, `OPENROUTER_API_KEY`, `OPENROUTER_TTS_MODEL/VOICE`, `OPENROUTER_BASE_URL`.

### Status
- Implemented (verified: `tts.py:132` OR chunk handles mp3/pcm, `tts.py:175` Groq→OR failover, `audio_tools.py:23` hash cache).

### Notes
- Without any key endpoints honestly return `503` — no offline TTS fallback exists.
- Voice mapping: when caller passes `voice=None` and OR is used, `troy` → `alloy` remap keeps OR valid.

---

## 2026-09-15 — Current State Audit: Agent Tool Chain Refactor and Feedback Loops Hardening

### Type
- Refactor / Architecture / Feature

### What Changed
- **New tool layering.** Split monolithic skill handling into `sahlha/app/agent/tools/skill_tools.py:1` (`register_skill` persists without explanation; `setup_skill` delegates to explanation tool; `skill_media` re-fans; `_to_dict` adds `has_image/has_audio` derived from `audio_tools.expected_path` existence) and `sahlha/app/agent/tools/explanation_tools.py:1` (`explain_skill` persists explanation then `ensure_skill_media` calls `image_tools.fetch_skill_image` + `audio_tools.skill_explanation_to_audio` with non-fatal `skipped` capture; `explain_lesson` persists `lesson_explanations` then audio fan-out; `ensure_*_media` idempotent gap-fillers). Chain is now explicitly `skill tool → explanation tool → audio + image tools` (documented in `skill_tools.py:1` and `explanation_tools.py:1`).
- **Agent wiring updated.** `sahlha/app/agent/agent.py:35` `SahlhaAgent` (8 phases, `Phase` enum `sahlha/app/agent/state.py:10` added `LESSON_EXPLANATION`) now:
  - `extract_skills(42, force, n_skills alias)` — idempotent unless `force`, retrieves `top_k=5` lesson chunks, `complete_json` → `SkillList` or `fallback_skills` (`~2 sentences per skill`), caps `raw[:max(1,max_skills)]`, persists via `skill_tools.register_skill`, logs `llm:extract_skills` with backend.
  - `explain_skills(83)` — per skill, `retrieve_relevant_material` `top_k=3` filtered, `SkillExplanation` or `fallback_explanation`, then `skill_tools.setup_skill` (which chains media), logs `media:skill` even when already explained (gap fill).
  - `explain_lesson(120)` — `retrieve_lesson top_k=5`, validates `LessonExplanationModel` or `fallback_lesson_explanation`, delegates to `explanation_tools.explain_lesson` (persists + audio).
  - `generate_question_bank(192, skill-focused retrieval, flag steering, critique+top-up, skill enforcement)` — retrieves `top_k=4` for skill then lesson fallback, merges prior teacher flags (`repo.get_flag_reasons_for_skill` auto-appended to `teacher_feedback` — Feedback Loop 2), calls `generate_questions_llm`, enforces `q["skill_id"]=skill_id` app-side, runs critique (see below), filters bad indices, tops up with `fallback_questions`, persists via `question_tools.save_questions` (append-only version), transitions `WAITING_FOR_TEACHER`.
  - `start_assessment(263)` + `submit_assessment(350)` — multi-bank dominant `(course,lesson)` resolution via `Counter` over `repo.get_bank`, bundles `lesson_explanation` + per-skill explanations, `select_questions` with memory-aware heuristics, `evaluate_answer/record_attempt` + **scoped** `update_student_memory(course_id/lesson_id from QuestionBank)` to avoid slug collisions, mastery `<50%` per-skill → `skills_needing_review`.
- **Three closed feedback loops hardened:**
  1. Generation self-critique (`agent.py:227`): every draft bank → `critique_questions` (LLM if `enable_llm_critique` else `fallback_critique` term-overlap ≥2 + `correct_answer` bounds) — ungrounded/mis-answered dropped and topped up with grounded replacements. Logged in trace, token-optimized (deterministic default saves ~50%).
  2. Teacher flag steering (`agent.py:210` + `assessment_tools.py:33`): `POST /teacher/questions/{qid}/flag {reason}` creates `QuestionFeedback(kind=flag)` append-only; `get_flagged_question_ids()` permanently excludes from `select_questions`; `get_flag_reasons_for_skill()` feeds next generation's feedback (`Prior teacher flags to avoid repeating: …`).
  3. Mastery review (`agent.py:388`): submit returns `skills_needing_review` (<50% in that assessment); `skill-progress.needs_review` persistent flag; next `select_questions` prioritizes weak skills (`accuracy <0.6`).

### Why
- MVP mixed skill persistence and media in routes/services. The chain makes ownership explicit (LLM reasons, app enforces, tools own persistence), enables idempotent retries, and closes the three adaptivity loops without retyping.

### Implementation
- Files: `sahlha/app/agent/tools/skill_tools.py:1`, `sahlha/app/agent/tools/explanation_tools.py:1`, `sahlha/app/agent/agent.py:35` (whole file rewritten), `sahlha/app/agent/state.py:10` (`Phase` enum + `AgentState` with `skills/current_question_ids/current_answers/student_memory/assessment_result/trace` + `log/transition`), `sahlha/app/agent/prompts.py:1` (added `LESSON_EXPLANATION_SYSTEM/USER_TEMPLATE`, `CRITIQUE_SYSTEM/USER_TEMPLATE`, token caps `llm_max_context_chars=6000`, `llm_skill_context_chars=4000`), `sahlha/app/agent/schemas.py:1` (`LessonExplanationModel`, `CritiqueVerdict/Result`, MCQ validators), `sahlha/app/agent/tools/assessment_tools.py:13` (flag exclusion, per-bank selection), `sahlha/app/database/repositories/repositories.py:212` (flag helpers), `sahlha/app/services/services.py:28` (`extract_skills` now bundles `explain_skills`+`explain_lesson`).
- New services convenience: `sahlha/app/services/services.py:44` `explain_lesson`, `50` `get_lesson` (study bundle), `60` `list_skills` with `has_image/has_audio`, `162` `skill_audio/lesson_audio/skill_image` delegations.

### Architecture Impact
- Previous: `agent → rag_tools + question_tools + student_tools + assessment_tools + audio/image ad-hoc` (media coupled to routes).
- Current:
```
skill_tools.register_skill ──┐
                             ▼
                   explanation_tools.explain_skill/lesson
                             │            │
                             ▼            ▼
                      audio_tools   image_tools (non-fatal, skipped→503, hash/disk cache)
```
- `AgentState.trace` now surfaces `phase`, `tool:retrieve_*`, `llm:*`, `media:*`, `feedback:*` for Streamlit Debug tab and API payloads.

### Dependencies / Technologies
- No new deps; leverages existing Groq/OpenRouter + `groq>=0.11`/`openai>=1.30` + Pexels. `pydantic>=2.6` validators guard MCQ shape.

### Status
- Implemented (all new tool files exist and are imported by `agent.py` and `services.py`; `git status` shows untracked `skill_tools.py`, `explanation_tools.py` with actual content above).

### Notes
- `enable_llm_critique=False` by default (`config.py:52`) — deterministic gate is pure logic (`llm.py:381` `fallback_critique`), unit-tested.
- `skill_id` enforcement is app-side: `agent.py:224` `q["skill_id"]=skill_id` regardless of LLM output.

---

## 2026-09-15 — Current State Audit: Data Layer Evolution (Scoped Performance, Media Columns, Feedback, Catalog)

### Type
- Architecture / Backend / Fix

### What Changed
- **New tables / column evolution:**
  - `LessonExplanation` (`models.py:46`) `__table_args__ UniqueConstraint(course_id, lesson_id)` + `title, explanation, key_concepts[JSON]`.
  - `Skill` (`models.py:64`) adds `image_url/path/alt` (`VARCHAR 1024/1024/512`), UQ `(course,lesson,skill)`.
  - `Assessment` (`models.py:130`) adds `course_id, lesson_id` (dominant pair) + `question_bank_id` remains representative; `question_ids[JSON]`.
  - `StudentSkillPerformance` (`models.py:157`) UQ now `UQ(student,course,lesson,skill)` (was `student,skill` in MVP) — scope prevents slug collision across lessons; `accuracy` float.
  - `QuestionFeedback` (`models.py:173`) new append-only table `question_feedback(id, question_id→questions, kind=flag, reason, created_at)` — feeds regeneration and exclusion.
- **Repositories** `sahlha/app/database/repositories/repositories.py:1` (397 lines) adds: `upsert_lesson_explanation/get_lesson_explanation`, `upsert_skill/list_skills/get_skill/get_skill_by_slug/set_skill_explanation`, `next_bank_version/create_bank` (retry 3 on `IntegrityError` for concurrent version allocation), `get_bank/list_banks/set_bank_status/get_questions/get_approved_questions`, flag suite `flag_question/get_flagged_question_ids/get_flag_reasons_for_skill/list_flags`, `get_or_create_student/get_student/list_students`, `create_assessment/get_assessment/record_attempt/get_attempts/get_failed_question_ids`, **scoped** `upsert_skill_performance(course/lesson)` with legacy-row back-compat adoption, `get_skill_performance` filtered, plus catalog helpers `list_courses()` (distinct `course_id` across 5 models) and `list_lessons(course_id?)` (distinct `(course,lesson)` enriched with `title`/`skill_count`).
- **Additive SQLite migration.** `sahlha/app/database/database.py:29` `_ensure_columns()` introspects `PRAGMA table_info`, `ALTER TABLE ADD COLUMN` for missing `skills.image_*`, `assessments.course/lesson`, `student_skill_performance.course/lesson`, then backfills `NULL → general/lesson_1`. Runs inside `init_db()` on every startup; `Base.metadata.create_all` handles fresh DBs.

### Why
- MVP stored performance by `(student, skill)` only — same slug in two lessons shared counters (wrong). Banks need per-skill versioning without overwrite. Teacher flags must be append-only and queryable. `assessments` previously inferred course/lesson from one bank — wrong for multi-skill assessments.

### Implementation
- Files: `sahlha/app/database/models.py:46` (`LessonExplanation`), `64` (`Skill`+images), `87` (`QuestionBank` UQ), `130` (`Assessment` scoped), `157` (`StudentSkillPerformance` scoped), `173` (`QuestionFeedback`), `sahlha/app/database/database.py:29` (`_ensure_columns`), `sahlha/app/database/repositories/repositories.py:60` (all repos), `sahlha/app/services/services.py:204` (`skill_progress` now `q_to_skill` map + scoped perf + `needs_review`).
- Diff vs HEAD: `models.py +29`, `database.py +9`, `repositories.py +174`.

### Architecture Impact
- Previous: `Performance UQ(student,skill)` + `Assessment(course/lesson inferred from one bank)` + `no flags`.
- Current:
```
SkillPerformance UQ(student,course,lesson,skill) — never collides across lessons
Assessment(course_id,lesson_id) persisted as dominant Counter over banks
QuestionFeedback append-only → get_flagged → excluded in select_questions + steers next gen
Skill.image_url/path/alt cached on row, migrated additively on startup
```

### Dependencies / Technologies
- `sqlalchemy>=2.0`, SQLite only. No new external deps.

### Status
- Implemented (tables exist, migration verified in `database.py:29`, `skill_progress` + `select_questions` scoping verified).

### Notes
- `create_bank` retry handles race where two workers compute same `next_bank_version`.
- `upsert_skill_performance` back-compat path adopts legacy unscoped row (`course_id` NULL → `general`) instead of creating duplicate that splits history.

---

## 2026-09-15 — Current State Audit: Assessment Selection and Memory Scoping Hardening

### Type
- Fix / Upgrade / AI

### What Changed
- **Per-bank deterministic selection** `sahlha/app/agent/tools/assessment_tools.py:13` `select_questions(db, student,course,lesson,skill, n_per_bank=4)` now:
  1. Loads `pool = get_approved_questions(...)` filtered by course/lesson/skill, 2. Excludes `flagged=set(get_flagged_question_ids())`, 3. Groups by `bank_id`, validates each bank has `≥n_per_bank` unflagged (else helpful error `Bank {id} (skill '{skid}') has only {k} … need {n} … Regenerate or unflag`), 4. Per bank applies priority: failed-retry (`failed_ids`) → weak skills (`accuracy<0.6` via `get_student_skill_performance` scoped to lesson) → unseen (`question_id not in {history}`) → difficulty balancing (`easy/medium/hard` missing) → fill remainder, never repeats `q["id"]` within assessment. Returns `selected` + `meta{rationale, weak_skills, failed_retried, per_bank, flagged_excluded, covered_skills, missing_skills}`.
  - **Scoping.** `weak_skills` scoped to `(course,lesson)` when given, else global (preserves single-lesson MVP while preventing cross-lesson leakage). `missing_skills` surfaces lesson skills with zero approved-unflagged questions so UI warns instead of silently covering a subset.
- **Scoped memory update** `sahlha/app/agent/agent.py:350` `submit_assessment`: per question resolves `_qbank = get_bank(q.question_bank_id)` → `_cc/_ll = bank.course/lesson` else `assessment.course/lesson` else `general/lesson_1`, then `student_tools.update_student_memory(course_id=_cc, lesson_id=_ll)`. Same scoping used for explanations bundle (`agent.py:302` bank→skill lookup).
- **Evaluation** `assessment_tools.py:108` `evaluate_answer` supports `multiple_choice` int compare + string fallback, else normalized substring check for future `short_answer`. `student_tools.py:1` `get_failed_questions` / `get_student_history` / `get_student_skill_performance` now pass `course/lesson` filters.

### Why
- MVP selection was lesson-global; flagged questions resurfaced; memory collided across lessons. Per-bank exactly-4 guarantees every skill is tested; flagged exclusion and scoped memory are correctness fixes.

### Implementation
- Files: `sahlha/app/agent/tools/assessment_tools.py:13` (full rewrite +33 lines), `sahlha/app/agent/tools/student_tools.py:21` diff (scoped filters), `sahlha/app/agent/agent.py:263` (`start_assessment` dominant pair + study bundle), `350` (`submit_assessment` scoped update), `sahlha/app/services/services.py:204` (`skill_progress` maps attempts via `q→skill`).
- Services add `skill_progress` HTTP exposure `GET /students/{id}/skill-progress?course&lesson → {skills[{has_explanation, bank_questions, exercise_ready, attempted, accuracy, completed, needs_review}], completed/total}`.

### Architecture Impact
- Previous: `select_questions = weak-unseen-difficulty over global approved pool (may skip skills, flagged shown)`.
- Current:
```
pool(filtered by lesson) —flagged→ grouped by bank —per-bank 4→
  failed-retry → weak(<0.6) → unseen → difficulty balance → fill
  + meta.missing_skills warning + per_bank counts
memory key = (student,course,lesson,skill) — never shared across lessons
```

### Dependencies / Technologies
- None new; uses `settings.assessment_num_questions=4`.

### Status
- Implemented (verified `assessment_tools.py:33` flagged filter, `64` per-bank length check, `48` scoped perf, `102` meta).

### Notes
- `settings.assessment_num_questions` is per bank, so total assessment size is `N×4` where N=number of approved banks for the lesson (or 4 when `skill_id` filtered).

---

## 2026-09-15 — Current State Audit: API Surface, Catalog, and Background Ingestion

### Type
- Feature / Architecture / Infrastructure

### What Changed
- **New catalog API** `sahlha/app/api/routes_catalog.py:1` `GET /catalog/courses → string[]` (distinct `course_id`), `GET /catalog/lessons?course_id → [{course_id, lesson_id, title, skill_count}]`, `GET /catalog/tree → [{course_id, lessons: [...]}]` for dropdown hydration; mounted in `sahlha/app/main.py:44`.
- **Teacher flags** `sahlha/app/api/routes_teacher.py:42` `POST /teacher/questions/{qid}/flag {reason}` + `GET /teacher/flags`; services `flag_question/list_flags` thin wrappers.
- **Lesson & skills** `sahlha/app/api/routes_agent.py:1` now also exposes `POST /agent/explain-lesson` (body `course,lesson,force`) and `GET /agent/lesson` (study bundle), plus existing `POST /agent/extract-skills|/generate-*-banks`, `GET /agent/skills`.
- **Assessment extensions** `sahlha/app/api/routes_assessment.py:1` adds `GET /students` (list), `POST /students {student_id?, name}` → create-or-return-existing, existing `POST /assessment/start` (`student_id, student_name, course, lesson, skill_id`) now returns `{assessment_id, questions(without correct_answer), lesson_explanation, skill_explanations, selection_meta, trace}`, `POST /assessment/{id}/submit → {score, correct, total, results[{correct,correct_answer,skill_id}], skills_needing_review, skill_performance, trace}`. `GET /students/{id}/performance` and `GET /students/{id}/skill-progress?course&lesson` enriched.
- **Upload backgrounding** `sahlha/app/api/routes_documents.py:13` `POST /documents/upload` now `eager=False` + `background_tasks.add_task(_background_warm_index)` — 200 returns fast with `chunk_count/method/is_scanned` while `data/vectors.npz` warms off-thread; `POST /documents/{id}/process` still returns chunk count. `GET /health` and `GET /` remain, plus `app.mount("/app", StaticFiles(frontend/), html=True)` when `frontend/` exists.
- **Static frontend serving** `sahlha/app/main.py:46` serves detached `frontend/` SPA at `/app` (HTML/JS only, no Streamlit) alongside API.

### Why
- MVP required students to manually type course/lesson; catalog enables discovery. Flags needed API. Background reindex keeps upload snappy (dense model 5s cold load). Static SPA gives non-Streamlit testing path.

### Implementation
- Files: `sahlha/app/api/routes_catalog.py:1` (new, untracked), `sahlha/app/api/routes_teacher.py:42` (+20), `sahlha/app/api/routes_agent.py:34` (`explain-lesson`, `lesson`), `sahlha/app/api/routes_assessment.py:1` (+19, new student routes), `sahlha/app/api/routes_documents.py:13` (background), `sahlha/app/main.py:38` (catalog router + static mount), `sahlha/app/schemas/api.py:1` (`LessonBanksRequest n=10, GenerateBankRequest n=8, CreateStudentRequest, FlagRequest`).
- All handlers delegate to `sahlha/app/services/services.py` — zero business logic in routes.

### Architecture Impact
- Routes remain thin; services own transactions. Catalog tree avoids N+1 for dropdowns. Upload no longer blocks on vector build.

### Dependencies / Technologies
- FastAPI `BackgroundTasks`, `StaticFiles`. No new external.

### Status
- Implemented (routes exist, `main.py` includes them, `catalog/tree` tested via `frontend/index.html:185`).

### Notes
- `POST /documents/upload` form fields `course_id/lesson_id/skill_id` still required but `lesson_id` may be auto-overridden by `_extract_lesson_id()` result returned to client.

---

## 2026-09-15 — Current State Audit: Frontend Evolution (Streamlit Test Client + Detached HTML SPA)

### Type
- Feature / Upgrade

### What Changed
- **Streamlit** `streamlit_app.py:1` (378 lines, +304 vs HEAD) reworked: teacher tab uses `max_skills` slider `1-6` + Extract/Reload split, `translate` not needed, pending banks show per-question flag UI + approve/reject with feedback, student tab adds `skill_progress` bar (`completed/total`), study bundle fetch `GET /agent/lesson` once (avoids N+1), per-skill image (`GET /images/skill` 120s timeout) + 🔊 Listen (180s) with `503` guidance (`GROQ_API_KEY` + terms or `OPENROUTER_API_KEY`), explicit `I've read the explanation — show my 4 questions` checkbox gating, `st.radio(index=None, format_func=…)` no-default, `missing_skills` warnings, progress re-fetch after submit, debug tab renders `trace` + `selection_meta/skill_performance/retrieved_chunks/backend`. Timeouts: upload 300s, extract 180s, gen 300s, audio 180s, image 120s. Error helper `_api_error()`.
- **New detached SPA** `frontend/index.html:1` (420 lines, new untracked) — HTML/CSS/JS only (no Python), served at `GET /app/` via `StaticFiles`, sticky header with `API` input + `Check health`, tabs `Teacher/Student/Debug`, teacher cards mirror Streamlit (upload with lesson auto-extract note, max_skills slider, reload, `n per skill`, pending with flag inputs), student section catalog-aware (`loadCatalog()` → `GET /catalog/tree` → `course/lesson <select>` + `<datalist>`), `Load my skills → GET /students/{id}/skill-progress + GET /agent/lesson`, progress bar, per-skill details (explanation, `fetch /images/skill → blob`, Listen → `fetch /audio/skill` with 503 mapping to `GROQ_API_KEY` or `OPENROUTER_API_KEY`, exercise gating checkbox, 4 radios, submit → mastery warning), `Load performance`, debug `Clear`. Catalog `coursesList/lessonsList` datalists enable free-typing plus selection.

### Why
- Streamlit was slow to iterate; detached SPA is zero-install for QA, demonstrates catalog integration, and validates static serving.

### Implementation
- Files: `streamlit_app.py:57` (state keys `last_bank/assessment/debug/progress/study_bundle/lesson_overview/skill_asm/studied`), `frontend/index.html:136` (JS `apiGet/apiPost/apiUpload`, `loadCatalog/loadLessonsFor/wireCatalog`, `renderStudent`), `sahlha/app/main.py:46` mount.
- Session hardening: `streamlit_app.py:61` normalizes legacy `None → dict` for bundle keys; `frontend/index.html:189` preserves teacher typing, auto-selects first course if student empty.

### Architecture Impact
- No backend change; presentation layer now has two test clients (Streamlit for Python UX, SPA for static HTML/JS). Both are **not production UI** — intentional.

### Dependencies / Technologies
- `streamlit>=1.33` (existing) + browser `fetch` + FastAPI `StaticFiles`. No bundler.

### Status
- Implemented (SPA file exists and is served; Streamlit diff +304 lines).

### Notes
- Health check hits `GET /health`; `SAHLHA_API` env (Streamlit) or header input (SPA) points to FastAPI (default `http://127.0.0.1:8000`).

---

## 2026-09-15 — Current State Audit: Image Provider and Configuration Tightening

### Type
- Upgrade / Fix

### What Changed
- **Pexels provider** `sahlha/app/images/pexels.py:1` improvements: `build_image_query()` detects code topics (`python/elif/if else/function/loop/code/programming/algorithm`) and returns `programming education technology` to avoid snake ambiguity; strips `(lesson)` suffixes, caps 120 chars, falls back to `skill_id` or `education`. `search_pexels()` uses `orientation=landscape, size=large, per_page=3`, raises on 401. `fetch_related_image()` cascades fallback queries `education technology → learning → school classroom` when specific query empty, validates `content-type image/` and `len>=1024`, returns `{bytes, page_url, image_url, alt, photographer}`.
- **Image tool** `sahlha/app/agent/tools/image_tools.py:18` `fetch_skill_image()` returns cached if `image_path` exists (unless `force`), otherwise builds query via `pexels.build_image_query`, downloads, writes `data/images/{skill_id[:60]}_{sha1[:16]}.jpg`, records `skill.image_url/path/alt`, commits.
- **Config tightening** `sahlha/app/config.py:5` now documents OpenRouter + TTS + Pexels clearly, `extra="ignore"` for `.env` tolerance, `llm_max_context_chars=6000`, `llm_skill_context_chars=4000`, `enable_llm_critique=False`, `assessment_num_questions=4`. `.env.example:1` documents every key including `TESSERACT_CMD`/`POPPLER_PATH` overrides and `DATABASE_URL`.

### Why
- `python` queries returned snake pictures; fallback queries improve hit rate when Pexels narrow query empty.

### Implementation
- Files: `sahlha/app/images/pexels.py:23` (`build_image_query`, `_api_key`, `search_pexels`, `fetch_related_image`), `sahlha/app/agent/tools/image_tools.py:1`, `sahlha/app/config.py:5`, `.env.example:1`.

### Architecture Impact
- Previous: raw `name + key_concepts` query, no fallback. Current: code-aware mapping + 3 fallback queries + validation.

### Dependencies / Technologies
- Pexels API (`https://api.pexels.com/v1/search`, header `Authorization: PEXELS_API_KEY`) — free tier. No new pip deps.

### Status
- Implemented (diff `pexels.py +22`, new `image_tools.py` verified).

### Notes
- Without `PEXELS_API_KEY` `GET /images/skill → 503` honestly; explanation still succeeds (non-fatal).
- Image tests: `tests/test_images.py` (+13) + `tests/test_media_autogen.py` new, both hermetic (503 path mocked).

---

## 2026-09-15 — Current State Audit: Testing & CI Hardening

### Type
- Infrastructure / Testing

### What Changed
- **Hermetic fixtures** `tests/conftest.py:17` `_no_external_keys` autouse fixture monkeypatches `settings.groq_api_key/openrouter_api_key/openai_api_key/pexels_api_key` to `""` and deletes `GROQ_API_KEY/OPENROUTER_API_KEY/OPENAI_API_KEY/PEXELS_API_KEY` env vars — developer's real `.env` no longer bleeds into tests (prevents real API calls + order-dependence). Adds `db_session` tmp `NamedTemporaryFile .db` + `Base.metadata.create_all`, cleanup handles Windows lingering handles. `client` fixture overrides `get_db`.
- **New suites** (all hermetic, mocked):
  - `tests/test_rag_proper.py:1` — sentence boundary (`test_chunks_never_split_mid_sentence`), cache reuse (`test_rebuild_caches_vectors` with `tmp_path/vectorizer`), paraphrase semantic (`@skipif not dense_available()`).
  - `tests/test_ocr.py` (new) — scanned PNG/PDF through real tesseract when available, else mocked.
  - `tests/test_feedback.py` (new) — flag exclusion (`get_flagged_question_ids` excludes from `select_questions`) + flag reason steers `generate_question_bank` via `get_flag_reasons_for_skill`.
  - `tests/test_provider_fallback.py:1` — 10 tests: 6 LLM (groq→or, both fail→fallback, no OR key, non-retryable, OR direct), 4 TTS (groq succeeds, 429→OR, both fail raises, OR direct with `alloy`).
  - `tests/test_media_autogen.py` (new) — auto-media chain (explanation → audio/image non-fatal).
  - Augmented `tests/test_images.py` (+13) and `tests/conftest.py` (+19).
- **Run guidance** `README.md:212` now enumerates `pytest tests/ -q` → 11+ tests (`RAG, generation, approve, reject→v2, assessment×4, memory-adapts, HTTP loop, skill extraction+explanations, one-bank-per-skill, skill banks approve+assess, skill HTTP endpoints, plus OCR/audio/image/feedback suites`).

### Why
- Without `_no_external_keys`, tests spent real Groq/OR/Pexels calls via auto media generation and became flaky. Provider fallback needs explicit contracts.

### Implementation
- Files: `tests/conftest.py:17`, `tests/test_rag_proper.py:1`, `tests/test_ocr.py`, `tests/test_feedback.py`, `tests/test_provider_fallback.py:1`, `tests/test_media_autogen.py`, `tests/test_images.py`.

### Architecture Impact
- No runtime change; test isolation enables `python -m pytest tests/ -q` offline (dense skip, tesseract skip).

### Dependencies / Technologies
- `pytest>=8.0`, `httpx>=0.27` (httpx via TestClient), `pytest` autodiscovery.

### Status
- Implemented (files exist and are imported; `test_provider_fallback.py` verified 10 functions).

### Notes
- Real OCR tests still need Tesseract/Poppler installed to pass unmocked, but CI can skip via `dense_available()` analog.
- `tests/test_api_loop.py` etc. remain thin; they use `eager=True` ingestion to avoid background race.

---

## 2026-09-15 — Current State Audit: Configuration & Documentation Consolidation

### Type
- Documentation / Infrastructure

### What Changed
- **`.env.example`** `D:\projects\Sahlha.ai\.env.example:1` rewritten to document primary `GROQ_API_KEY/GROQ_MODEL` (`openai/gpt-oss-120b`), backup `OPENROUTER_API_KEY/MODEL/BASE_URL`, TTS `GROQ_TTS_*` + `OPENROUTER_TTS_MODEL/VOICE` (free `fish-audio/s2.1-pro-free:free` → `alloy`), `PEXELS_API_KEY`, `TESSERACT_CMD`/`POPPLER_PATH` overrides, `DATABASE_URL=sqlite:///./data/sahlha.db` with comments explaining failover vs fallback.
- **`PROJECT.md`** (470 lines, untracked) added as detailed architecture doc covering vision (`skill=explanation+exercise`, 3 feedback loops), tech stack table with file:line refs (`sahlha/app/config.py:5`, `sahlha/app/agent/agent.py:35`, `sahlha/app/rag/embeddings.py:18`, etc.), full tree (`data/sahlha.db` + `vectors.npz`), layered diagram, data flow, 8-phase state machine, RAG/LLM/DB/API/media/Loops sections, key decisions table, install/run, test map, roadmap.
- **`README.md`** (257 lines, +61 vs HEAD) updated to reflect Groq primary → OpenRouter backup → deterministic fallback, TTS chain (`Groq Orpheus → OpenRouter TTS → non-fatal skip`), structure table, feedback loops section, endpoint list (now includes `GET /catalog/*`, `POST /teacher/questions/{id}/flag`, `GET /teacher/flags`, skill/lesson audio/image), run instructions (`copy .env.example .env`), test count 11, audio/images sections (§10b/10c).
- **`requirements.txt`** pins floors unchanged except `sentence-transformers>=3.0` added.

### Why
- MVP commit had docs drift (README said `llama-3.3-70b-versatile`, new default is `openai/gpt-oss-120b`; no catalog/flag docs). Consolidation makes the repo self-documenting for a new dev months later.

### Implementation
- Files: `.env.example:1`, `PROJECT.md:1`, `README.md:1`, `requirements.txt:9`.

### Architecture Impact
- Docs only; no flow change. `PROJECT.md` is the source of line-anchored references (`file_path:line_number`) for navigation.

### Dependencies / Technologies
- None new.

### Status
- Implemented

### Notes
- Planned but **not implemented** (and thus not claimed above): FAISS/Chroma swap (interfaces isolated but still custom numpy), real auth/row-level scopes, pagination, Postgres, spaced-repetition scheduler, LLM-graded free-text, `short_answer` runtime — all remain roadmap in `PROJECT.md:449`.

---

## Current Architecture Evolution Summary

```
Initial (2026-09-14 empty):
  (none)

MVP (2026-09-14 94f8c37):
  File → OCR(pypdf) → chunks(TF-IDF) → RAG
            ↓
          Agent (skill split + banks) → Teacher approve → Student assess (global pool) → memory(student,skill)

Post-MVP Working Tree (2026-09-15 audit):
  File
    ↓
  OCR(pypdf | tesseract+pdf2image, is_scanned+method) + _extract_lesson_id + _safe_filename
    ↓
  clean → sentence-aware chunks(overlap 120/800, never mid-sentence) → DocumentChunk rows
    ↓
  Dense MiniLM-L6-v2(384-d, L2, cache vectors.npz, incremental <50% churn)
  || TF-IDF fallback → 3×cosine candidates → MMR(λ=0.7) → floor(0.05)+backoff → lexical last resort
    ↓
  Agent(8 phases, trace-logged)
    ├─ extract_skills(retrieve lesson×5 → complete_json/fallback → register_skill, idempotent)
    ├─ explain_skills(per skill retrieve×3 → explanation → skill_tools.setup_skill → explanation_tools→audio+image)
    ├─ explain_lesson(retrieve lesson×5 → LessonExplanationModel/fallback → audio)
    └─ generate_lesson_banks(per skill retrieve×4→ generate_questions_llm(Groq→OpenRouter→fallback)
          → critique(deterministic|LLM)+top-up → enforce skill_id → save_questions(versioned, append-only)
          → WAITING_FOR_TEACHER
    ↓ (human-in-the-loop, never auto-bypassed)
  Teacher: GET pending/GET bank/POST approve|reject(+feedback)|POST flag(+reason)→ QuestionFeedback
            → flagged excluded from selects + reasons auto-append to next gen (Loop 2)
    ↓
  Student: GET /catalog/tree→ pick course/lesson → GET /agent/lesson bundle(lesson_overview+skill explanations)
           → GET /images/skill (Pexels code-aware fallback) + GET /audio/skill|lesson(Groq→OpenRouter, hash cache)
           → POST /assessment/start(4 per approved bank, memory-aware: failed→weak<0.6→unseen→difficulty, flagged excluded, missing_skills warn)
           → gated study(checkbox) → radio answers(index=None) → POST /assessment/{id}/submit
           → evaluate/record_attempt→ scoped memory(student,course,lesson,skill) → mastery review(<50%→needs_review, Loop 3)
    ↓
  Persistence: documents/chunks/skills(+image cols)/lesson_explanations/question_banks(ver)/questions/students/assessments(+course/lesson)/attempts/skill_performance(UQ student,course,lesson,skill)/question_feedback(+flags)
              + migration(_ensure_columns, backfill) + vectors.npz cache
    ↓
  Presentation: Streamlit(Teacher/Student/Debug) + detached HTML SPA at /app + FastAPI thin routers(BackgroundTasks for index warm)
```

---

## Verification

- [x] `PROJECT_CHANGELOG.md` exists at repo root.
- [x] Every Implemented entry cross-checked against working-tree files (paths and line numbers above) and `git log --name-only` for dated commits.
- [x] No planned feature presented as implemented: `FAISS/Chroma`, `auth`, `pagination`, `Postgres`, `spaced-repetition`, `short_answer grading` remain in § Known Limitations / Roadmap only.
- [x] Provider behavior not invented: Groq primary, OpenRouter single-failover on 429/5xx/408/decommissioned, deterministic offline fallback, TTS `mp3/pcm` formats, Pexels `503` contract all quote source (`llm.py:54`, `tts.py:33`, `pexels.py:39`).
- [x] Append-only/versioned claims verified (`question_banks.version` increment with IntegrityError retry, `student_attempts`/`question_feedback` never overwrite).

## Maintenance Rule (from this point forward)

1. Implement change. 2. Verify against code. 3. Append a new dated entry (never rewrite history unless factually wrong). 4. Keep entries chronological with `files/components` and `Architecture Impact old→new`. 5. Mark `Implemented / Partially Implemented / Planned / Deprecated` honestly.
