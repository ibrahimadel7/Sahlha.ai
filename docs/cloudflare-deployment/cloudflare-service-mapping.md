# Sahlah — Cloudflare Service Mapping

> Only services that solve an actual verified problem are recommended. For each: role, fit,
> required changes, limitations, plan requirements, docs/pricing links, MVP vs later.
> Research date: Oct 2026 (official `developers.cloudflare.com` + `cloudflare.com` pricing).

## Verdict at a glance

| Service | Verdict | Stage |
|---|---|---|
| DNS + SSL/TLS + Reverse proxy (Orange-cloud) | **Use** — free HTTPS, DDoS, custom domain for backend | Stage 1 |
| Containers (+ Worker proxy + Durable Object) | **Use for backend+agent** — only Cloudflare runtime that fits (Dockerfile, torch, Tesseract, threads, minutes-long jobs) | Stage 1 (demo/MVP) |
| Workers (TypeScript proxy) | **Use narrowly** — `/edge-health` edge probe + routing/auth-edge-checks only; **not** for the Python backend | Stage 1 (already in `workers/backend-proxy/src/index.ts`) |
| R2 | **Use** — uploads + generated audio/images (replaces ephemeral container disk) | Stage 2 (required for any production) |
| AI Gateway | **Use** — observability/caching/rate-limit visibility for Groq/OpenRouter calls | Stage 2 (low-risk, no behavior change) |
| Secrets (`wrangler secret`) + `vars` | **Use** — lion's share of env config | Stage 1 |
| Turnstile | **Optional later** — public register/upload bot protection only if abuse appears | Stage 3 |
| Queues | **Defer** — only if OCR/embedding outgrows container background tasks | Stage 3 if needed |
| Workflows / Durable Objects (custom) / KV / Hyperdrive / D1 / Vectorize / Workers AI / AI Search / AutoRAG / Pages | **Do not adopt for MVP** — wrong fit or unjustified migration (details below) | Re-evaluate post-pilot |

## 1. Compute and hosting

### Cloudflare Containers — RECOMMENDED for the FastAPI backend + agent

- **Role:** Run the existing `Dockerfile` (Python 3.12-slim, Tesseract+Poppler, `uvicorn --workers 1`) unchanged behind the existing `workers/backend-proxy` Worker.
- **Why it fits:** Only Cloudflare compute that supports: Dockerfile/native binaries (Tesseract/Poppler), torch/`sentence-transformers`, threads + `BackgroundTasks`, 40s+ index rebuilds, multi-minute bank generation, local SQLite + disk cache semantics. Workers V8 isolates cannot (128MB memory, 10ms–5min CPU, 1s startup, no POSIX binaries, Pyodide-only packages — see Workers Limits + Python Workers GA notes).
- **Changes required:** None to app code for demo. Set `wrangler secret put` keys, `max_instances: 2` (already), `sleepAfter: 10m` (already). Accept ephemeral disk for demo; add R2/external DB for production (Stage 2).
- **Limitations:** Ephemeral disk (SQLite/`data/*` reset on eviction — already warned in `src/index.ts` + deploy script); cold start (model load ~9s + container wake); `sleepAfter` tuning trades cost vs latency; image storage 50GB/account; concurrent memory/vCPU/disk caps per account.
- **Plan:** Requires **Workers Paid ($5/mo)** — Containers have no free tier. Included: 25 GiB-hours memory + 375 vCPU-minutes + 200 GB-hours disk per month; overage at per-GiB-second/vCPU-second/GB-second rates. Inbound Worker requests + Durable Object backing also metered.
- **Docs:** Containers GA changelog `https://developers.cloudflare.com/changelog/post/2026-04-13-containers-sandbox-ga/` · Limits `https://developers.cloudflare.com/containers/platform/limits/` · Pricing `https://developers.cloudflare.com/containers/pricing/` and `https://developers.cloudflare.com/containers/platform/pricing/` · Workers pricing (Containers section) `https://developers.cloudflare.com/workers/platform/pricing/`.

### Cloudflare Workers (TypeScript/JavaScript) — EDGE PROXY ONLY

- **Role:** Keep the existing `workers/backend-proxy` as a thin edge: `/edge-health` without waking the container, request routing, future signed-URL issuance / auth pre-checks / webhooks.
- **Why not the backend:** Python Workers are GA (Pyodide, FastAPI/Django support claimed) but Sahlah needs `torch`+`sentence-transformers` (no PyEmscripten wheel guarantee), Tesseract/Poppler POSIX binaries, 90MB model + 128MB isolate cap, 1s startup snapshot, and multi-minute CPU — all incompatible or high-rewrite. Do not port the agent to JS/TS.
- **Changes:** None (proxy already written). Optional later: small endpoints only if they stay stateless and dependency-free.
- **Plan:** Free 100k req/day, 10ms CPU; Paid 10M req/mo included + $0.30/M, 30M CPU-ms included + $0.02/M CPU-ms.
- **Docs:** Limits `https://developers.cloudflare.com/workers/platform/limits/` · Pricing `https://developers.cloudflare.com/workers/platform/pricing/` · Python Workers GA `https://blog.cloudflare.com/python-workers-ga/`.

### Cloudflare Pages — NOT RECOMMENDED

- Flutter `mobile/` builds APK/IPA (and optionally Flutter web), not a Pages-style static site/Functions app. The debug `frontend/index.html` is served same-origin at `/app/` by FastAPI itself — moving it to Pages would add CORS + split deployment for zero benefit. If a marketing site appears later, Pages is fine for that alone.

### Workers Builds / deployment tooling — USE `wrangler` ONLY

- `workers/backend-proxy/package.json` already pins `wrangler 4.131.2` + `@cloudflare/containers`. Deploy via `wrangler deploy` from `workers/backend-proxy` (see `deployment-plan.md`). No other build system needed.

## 2. Storage and databases

### R2 — RECOMMENDED (Stage 2, production)

- **Role:** Raw uploads + generated audio/images + (optionally) `vectors.npz` snapshots. Replaces `data/uploads|audio|images` on ephemeral container disk.
- **Why:** S3-compatible, zero egress fees (mobile audio/image downloads are egress-heavy), free tier 10 GB-month + 1M Class-A + 10M Class-B ops/mo. Presigned-URL uploads keep the 25MB path off the container.
- **Changes:** Small, isolated: storage backend abstraction over `upload_dir/audio_dir/image_dir` (write-through to R2, DB keeps keys); presigned upload route (Worker or FastAPI); background migration of existing `data/*`. No agent/RAG logic change.
- **Limitations:** Eventually consistent listing; Class-A/B op metering; Infrequent Access has retrieval fees + 30-day minimum (use Standard).
- **Plan:** Free tier above; then $0.015/GB-mo + $4.50/M Class-A + $0.36/M Class-B.
- **Docs:** `https://developers.cloudflare.com/r2/pricing/` · calculator `https://r2-calculator.cloudflare.com/`.

### D1 — NOT RECOMMENDED for MVP (defer; external Postgres preferred if relational scale is needed)

- **Why not now:** D1 is SQLite-*compatible*, not a drop-in for this SQLite usage: SQLAlchemy `sqlite://` dialect + `JSON` columns + hand-rolled `_ensure_columns()` ALTERs + `PRAGMA table_info` + file-path assumptions + `vectors.npz`-adjacent logic all assume a file DB. D1 adds: 10GB/DB + 5GB free total caps, single-threaded per-DB throughput (~1ms reads, multi-ms writes, queue-and-`overloaded` under concurrency), 2MB row / 100KB statement / 100 bind-param caps, 30s query cap, 50 (free)/1000 (paid) queries per Worker invocation, rows-read/written metering (full scans billed). Migration = new dialect/driver + Alembic + chunked backfill + re-testing all repositories — unjustified for a graduation MVP still on single-writer SQLite.
- **If relational scale is ever needed:** prefer external Postgres (Neon/Supabase/Render) via `DATABASE_URL` (SQLAlchemy already abstracts; needs Alembic + psycopg) over D1. `Hyperdrive` (free 100k queries/day; paid unlimited, billed with Workers) only helps if Postgres is chosen — it is a connection pooler, not a database.
- **Docs:** Pricing `https://developers.cloudflare.com/d1/platform/pricing/` · Limits `https://developers.cloudflare.com/d1/platform/limits/`.

### Hyperdrive — ONLY IF external Postgres is adopted

- Role: pool + cache Postgres connections from the container. No benefit with SQLite. Re-evaluate with Stage-2 Postgres decision.

### KV — NOT NEEDED

- No config/cache-like workload justifies KV (eventual consistency, 1GB free). App config is env-based; caches are content-hash files better suited to R2.

### Durable Objects — ONLY AS CONTAINER BACKING (already in use)

- The proxy binds `SAHLHA_BACKEND` (SQLite-backed DO) because Containers require it — that is the extent of the need. Do not build custom DOs for coordination; no such requirement exists in the code.

## 3. AI and background processing

### AI Gateway — RECOMMENDED (Stage 2, low-risk)

- **Role:** Observability (logs, latency, error/429 visibility), caching of identical explanation/question prompts, and unified billing hooks for Groq/OpenRouter calls. No behavior change: point `GROQ_BASE_URL`/`OPENROUTER_BASE_URL` at the gateway.
- **Changes:** Base-URL + key config only; verify `response_format=json_object` passthrough. Keep deterministic fallbacks as-is.
- **Plan:** Generous free logging tier; Workers AI neuron billing only if gateway pays for Workers AI (not our path — external providers stay external).
- **Docs:** `https://developers.cloudflare.com/ai-gateway/` (see Gateway docs index; pricing rides on Workers plan).

### Workers AI — NOT A REPLACEMENT (optional complement only)

- Embedding models (`bge-small/base/large`, `bge-m3`, ~$0.012–0.20/M tokens, 10k neurons/day free then $0.011/1k neurons) and LLMs (incl. `gpt-oss-120b` analogue) exist, but swapping means: re-embedding the corpus (dimension change 384→other), re-tuning MMR floor/critique/grounding thresholds, Arabic quality re-validation (`paraphrase-multilingual` intent vs English `bge`), and rewriting provider failover. Benefit is unproven for MVP. Only valid future role: server-side embeddings behind a Vectorize migration — explicitly deferred.
- **Docs:** Pricing `https://developers.cloudflare.com/workers-ai/platform/pricing/`.

### Vectorize — DEFER (re-evaluate post-pilot)

- Dimensions math is cheap (free 30M queried + 5M stored dims/mo; paid 50M + 10M included), but migration cost is high: upsert pipeline replacing `rebuild_index`, metadata-filter parity (course/lesson/skill scoping is correctness-critical), incremental-append semantics, cache semantics, and re-validation of paraphrase tests. Keep the DB + `vectors.npz` retriever until corpus size or multi-instance scale forces the move.

### AI Search / AutoRAG — DO NOT ADOPT

- Managed retrieval would discard the grounded-evidence/partition pipeline, teacher-flag steering, and deterministic fallbacks that are the product's correctness story. Migration cost with no proven benefit.

### Queues — DEFER (Stage 3, conditional)

- Pricing is cheap (free 10k ops/day; paid 1M/mo included + $0.40/M; ~3 ops per message). Justified only if OCR/embedding outgrows in-container `BackgroundTasks` (e.g. many concurrent scanned-PDF uploads, multi-minute backlogs needing retries/DLQ). MVP has no such load. If added: upload → Queue message → consumer rebuilds index/regenerates media; needs idempotency keys + DLQ + `MAX_UPLOAD_MB` chunking.

### Workflows — DEFER

- Step/storage metering exists, but LangGraph pauses are in-memory and teacher runs are re-runnable. No cross-restart resume requirement exists. Do not add until a durable multi-minute teacher pipeline across evictions is proven necessary.

## 4. Networking, security, operations

| Need | Recommendation | Notes |
|---|---|---|
| DNS + custom domain + SSL/TLS + HTTPS | **Use Cloudflare** (Free plan suffices) | Orange-cloud the container hostname; validation in `deployment-plan.md`. |
| CORS + secure API access | Keep explicit-origin `CORSMiddleware` + JWT bearer; add production origin via `CORS_EXTRA_ORIGINS`; gate legacy routes (`TEACHER_API_KEY` or `LEGACY_DEV_API_ENABLED=false`) | Code change is config-only. |
| Turnstile | Optional Stage 3 | Only if public register/upload abused. |
| Logging/monitoring | Workers Logs + container stdout + `/health` booleans (never log secrets) | Paid plan: 20M events/mo included + $0.60/M; retention 7d. |
| Secrets/config | `wrangler secret put GROQ_API_KEY/JWT_SECRET/PEXELS_API_KEY/OPENROUTER_API_KEY` + `vars` for non-secrets | Never commit `.env`; image excludes it via `.dockerignore`. |
| CI/CD | GitHub Actions (build → `wrangler deploy`) — new, Stage 2 | No workflow exists today; keep manual `scripts/cloudflare-deploy.ps1` for Stage 1. |

## 5. What was deliberately excluded (and why)

- **Full Workers port:** incompatible native deps + state + duration (see §1).
- **D1-as-drop-in:** dialect/migration/metering/throughput mismatch (see §2).
- **Vectorize/AI Search/AutoRAG/Workers-AI replacement:** discards grounding/critique/fallback correctness story; high migration cost, unproven benefit.
- **KV/custom DOs/Hyperdrive-without-Postgres/Pages/Queues-now/Workflows-now:** no verified requirement in code; each adds cost/complexity without solving a real problem.
