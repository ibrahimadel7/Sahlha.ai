# Sahlah — Deployment Checklist (practical, in order)

> No test below is marked passing unless it was actually executed. Checkboxes are for the operator to tick during the real deploy.
> Covers the 16 verification areas from the task plus prep/security/readiness.

## A. Preparation

- [ ] Repo clean (`git status`), on the approved commit; `docs/cloudflare-deployment/*` reviewed.
- [ ] `python -m pytest tests/ -q` green locally (40 tests: 25 loop + 15 platform; hermetic except OCR tests needing binaries).
- [ ] `cd mobile && flutter analyze && flutter test` green (separate machine with SDK if needed).
- [ ] `cd workers/backend-proxy && npm install && npx tsc --noEmit` green; `docker build -f ../../Dockerfile -t sahlha-backend:local ../../` succeeds.
- [ ] `.env.example` reviewed; production secret values generated (long random `JWT_SECRET`); **no secrets pasted into chat/logs**.
- [ ] Embedding-model decision recorded (`paraphrase-multilingual-MiniLM-L12-v2` vs `all-MiniLM-L6-v2` divergence — see architecture analysis).
- [ ] `.pptx` decision recorded (add parser or remove from `allowed_extensions`).
- [ ] Legacy-route posture decided (`TEACHER_API_KEY` set and/or `LEGACY_DEV_API_ENABLED=false` only after Streamlit/tests migration verified).
- [ ] `SAHLHA_SEED_DEMO=0` or `ENVIRONMENT=production` planned for production deploy.
- [ ] `CORS_EXTRA_ORIGINS` production origin(s) known; mobile `API_BASE_URL` target URL known.

## B. Deploy (Stage 1)

- [ ] `wrangler whoami` / `wrangler login` **[AUTH]**.
- [ ] `wrangler secret put GROQ_API_KEY / JWT_SECRET / PEXELS_API_KEY / OPENROUTER_API_KEY` **[AUTH]** (interactive prompts).
- [ ] `wrangler deploy` from `workers/backend-proxy` **[AUTH]** (or `scripts/cloudflare-deploy.ps1`).
- [ ] Custom domain (optional): DNS orange-cloud → Worker; TLS verified; `CORS_EXTRA_ORIGINS` + `API_BASE_URL` updated.

## C. Smoke tests (backend + connectivity)

- [ ] 1. Backend health: `GET /edge-health` → `{ok, edge}` without container wake; `GET /health` → `{ok, jwt_configured, tts_configured, images_configured, llm_configured, dense_*, reranker_*, ocr_available}` booleans sane (`jwt_configured` must be `true` in production — proves `JWT_SECRET` reached the container).
- [ ] 2. Mobile connectivity: app built with `--dart-define API_BASE_URL=<worker-url>`; login/register reaches backend (no CORS error); token persists across restart.
- [ ] Existing suite re-run against prod URL where safe (read-only endpoints first).

## D. Content loop validation (areas 3–10, 12)

- [ ] 3. Upload + persistent storage (demo: in-container; prod: R2): PDF, DOCX, TXT, Markdown, and image each ingest; oversize (>25MB) rejected; traversal filename sanitized.
- [ ] 4. Format processing per supported type; scanned PDF/image OCR path returns text or honest `ocr:unavailable` (never crash).
- [ ] 5. OCR/extract verified via `method/is_scanned` in upload response + `/health ocr_available`.
- [ ] 6. RAG indexing + retrieval: `vectors.npz` warms (background task); paraphrase query retrieves the right chunks; scoped search never leaks across lessons (spot-check two lessons).
- [ ] 7. Agent end-to-end: extract skills → explanations → lesson overview → banks → approve → study → assessment → submit → mastery, one full pass.
- [ ] 8. Tool invocation + data flow: `trace` shows `retrieve → llm/fallback → critique → grounding → persist → media`; bank versions append (`pending_review`, never overwrite).
- [ ] 9. Skill extraction + content generation quality: skills reference real chunks (`source_chunk_ids/evidence` present); explanations ≥ length floors; questions are 4-option MCQ with valid index.
- [ ] 10. External LLM integration: with keys, `backend` reports `groq/openrouter` (not `fallback`); without keys, grounded fallback still completes the loop.
- [ ] 12. TTS + images: with keys, audio WAV + JPEG served; without keys, honest `503` and UI continues (explanation unaffected).

## E. Failure, persistence, security (areas 11, 13–16)

- [ ] 11. Provider failure + fallback: temporarily break primary (wrong key in staging) → OpenRouter failover on retryable errors; no keys → deterministic fallback; 400-class errors do **not** fail over (by design).
- [ ] 13. Persistence across restarts: demo — document that container eviction resets SQLite/`data/*` (do not demo irreplaceable data); prod — verify R2 objects + Postgres rows survive `wrangler deploy`/eviction.
- [ ] 14. Timeouts/retries/errors: long bank generation completes or surfaces a clear error (no silent hang); double-submit → 400; thin bank (`<4` approved) → actionable `need 4, have K` error; flagged questions excluded.
- [ ] 15. Auth/isolation: teacher A cannot see/edit teacher B's classrooms/banks; student cannot fetch `correct_answer` pre-submit (inspect payload); parent sees only linked children; enrollment + link-code duplicates rejected; unauthenticated → 401, wrong role → 403.
- [ ] 16. Production logging: `/health` exposes booleans only; no secrets/student PII in Worker/container logs; AI Gateway redaction verified if enabled.

## F. Production readiness + rollback

- [ ] Monitoring: Workers Logs + container logs + AI Gateway dashboards watched for 429/5xx/latency during the demo week.
- [ ] Cost guardrails: Workers CPU-limit set; container `sleepAfter`/`max_instances` reviewed after warm-hours observed; R2 op counts checked.
- [ ] Rollback rehearsed: `wrangler rollback` / redeploy previous version **[AUTH]**; mobile `API_BASE_URL` flip back to prior URL or tunnel.
- [ ] Known-test inventory: `tests/test_*.py` covers loop/rag/assessment/feedback/audio/images/workflow/platform; missing prod-only coverage (R2 persistence, Postgres migration, gateway passthrough, multi-instance concurrency) listed as follow-ups, not claimed.

## Test inventory (exists vs must-add)

- Exists: `test_api_loop` (HTTP loop), `test_rag*` (ingest→retrieve incl. paraphrase), `test_questions/skills/assessment/feedback` (banks, memory, flags), `test_audio*/test_images/test_media_autogen` (TTS/image/cache), `test_provider_fallback/failover` (Groq→OR→deterministic + TTS), `test_workflow` (LangGraph gate), `test_platform/progress_edges/upload_edges/quick_check/*` (RBAC, mastery, scoping).
- Must add (Stage 2+): R2 write-through/persistence tests, Postgres/Alembic migration tests, AI Gateway passthrough tests, container-restart survival tests, concurrent `max_instances` tests, mobile E2E against staging URL.
