# Sahlah — Deployment Plan (staged, no execution yet)

> Recommendation first, then stages. Nothing below has been executed.
> Commands marked **[AUTH]** require `wrangler login` / Docker and modify live infra — do not run without explicit approval.

## Recommended hosting strategy

**Stage 1: Cloudflare Containers (demo/MVP) + Cloudflare DNS/HTTPS.**
Run the existing `Dockerfile` behind the existing `workers/backend-proxy` (Worker + Durable Object `SAHLHA_BACKEND`, `/edge-health` edge probe, `sleepAfter 10m`, `max_instances 2`).
Accept ephemeral disk for the demo; set secrets via `wrangler secret`; point Flutter `API_BASE_URL` at the Worker URL.

**Why this over the alternatives:**

| Option | Compatibility with Python agent | Effort | Cost (demo) | Reliability | Verdict |
|---|---|---|---|---|---|
| **A. Python-compatible hosting (Render/Railway/Fly/VM) + Cloudflare DNS/proxy/R2/AI Gateway** | Full (native binaries, threads, minutes-long jobs, SQLite file) | Lowest (Dockerfile already valid) | ~$5–12/mo + free Cloudflare front | Highest for persistent SQLite (real volume) | **Lowest-risk path to a working deployment.** Use if Containers cold-start/ephemeral behavior proves annoying, or for the pilot (attach a real volume/Postgres + R2). Cloudflare still fronts DNS/HTTPS/security/observability without rewriting the agent. |
| **B. Cloudflare Containers** | Full (runs the exact image: Python 3.12, torch optional, Tesseract+Poppler, `--workers 1`) | Low (proxy + scripts already exist) | Workers Paid $5/mo base + metered memory/CPU/disk (demo fits largely in included allotments) | Good for demo; **ephemeral disk** is the caveat (SQLite/`data/*` reset on eviction — already warned in code) | **Recommended for Stage 1 demo** because it keeps everything on Cloudflare with minimal change. Not production-persistent without Stage 2 storage. |
| **C. Move slices to Workers** | Poor for backend (V8 isolates: 128MB, 10ms–5min CPU, 1s startup, no Tesseract/Poppler/torch wheels) | High (split auth/upload-webhook helpers + RPC/binding overhead) | Cheap per-request, but two systems to operate | Adds failure modes | **Not worth it for MVP.** Keep the proxy thin (`/edge-health`, routing). Revisit only for genuinely stateless edge helpers (signed URLs, webhook receivers) post-pilot. |

Hybrid is the honest answer: **Containers (compute) + Cloudflare (edge/storage/observability) + external AI providers (Groq/OpenRouter/Pexels)**. Do not choose Cloudflare-only hosting if it forces an agent rewrite — it doesn't, as long as Containers hosts the Python runtime.

### Backend hosting comparison detail (Option A vs B vs C)

- **A keeps** SQLite + `data/` + `.env` semantics exactly (attach a volume for persistence). Cloudflare contributes DNS/HTTPS/proxy, R2 (uploads/assets), AI Gateway (LLM observability), Turnstile (later). Effort: new `render.yaml`/`fly.toml` or Dockerfile deploy + env wiring + CORS origin.
- **B keeps** the same image but disk is ephemeral and wake-from-sleep adds latency. Needs Stage-2 R2 + external Postgres (`DATABASE_URL`) for anything beyond a demo. Concurrency today is `max_instances: 2` — fine for demo, needs load validation for pilot.
- **C** is limited to: edge health probe (done), auth pre-checks, signed upload URLs, webhooks, tiny API endpoints. Each split endpoint duplicates types/auth and needs contract tests. Overhead exceeds benefit at MVP scale.

## Stage 1 — Minimum viable deployment (existing app, minimal changes)

### Prerequisites

- `wrangler login` (browser) **[AUTH]**, Docker Desktop running, Node 20+, `workers/backend-proxy/node_modules` installed.
- `.env` present locally (never committed); production values ready to enter via `wrangler secret` (typed interactively, never pasted into chat).
- Flutter SDK for mobile smoke tests; `cloudflared` only if using the tunnel alternative.

### Files that need modification (minimal)

- `workers/backend-proxy/wrangler.jsonc`: set production `vars` (`CORS_EXTRA_ORIGINS`, `EMBEDDING_WARMUP`, `LEGACY_DEV_API_ENABLED`) — non-secret only. Secrets go via `wrangler secret`, not into the file.
- Backend CORS: production origin added via `CORS_EXTRA_ORIGINS` env (no code edit needed — `main.py` already reads it).
- Mobile: no code edit — rebuild/(`flutter run`) with `--dart-define API_BASE_URL=<worker-url>`.
- Optional hardening (one-line env, no logic change): `SAHLHA_SEED_DEMO=0` or `ENVIRONMENT=production` to disable demo seeding; `TEACHER_API_KEY=<random>` or `LEGACY_DEV_API_ENABLED=false` once legacy clients retire (verify tests first — legacy routes serve Streamlit/tests today).

### Infrastructure to create

- Cloudflare: Worker `sahlha-backend` + `SahlhaBackend` container binding + Durable Object namespace (all declared in `wrangler.jsonc`; created by `wrangler deploy` **[AUTH]**).
- DNS/HTTPS: Worker `*.workers.dev` URL works immediately; custom domain via Cloudflare DNS (orange-cloud) when ready.

### Environment variables (names only — set values via secrets manager)

| Name | Where | Purpose |
|---|---|---|
| `GROQ_API_KEY`, `GROQ_MODEL`, `OPENROUTER_API_KEY`, `OPENROUTER_MODEL` | `wrangler secret put` **[AUTH]** | LLM primary + backup (fallback works without them) |
| `JWT_SECRET` | `wrangler secret put` **[AUTH]** | JWT signing (generate long random; dev default must not ship) |
| `PEXELS_API_KEY` | `wrangler secret put` **[AUTH]** | Skill images (else `503`, UI continues) |
| `CORS_EXTRA_ORIGINS` | `wrangler.jsonc vars` | Production web/app origin(s) |
| `SAHLHA_SEED_DEMO=0` or `ENVIRONMENT=production` | `vars` | Disable demo seed |
| `DATABASE_URL` | Leave as SQLite file for Stage 1 demo | External Postgres only in Stage 2 |

### Commands (official docs: `wrangler deploy`, `wrangler secret put`)

Local (safe, no auth):

```powershell
# From repo root — verify proxy types + container image builds locally
cd workers/backend-proxy
npm install
npx tsc --noEmit
docker build -f ../../Dockerfile -t sahlha-backend:local ../../
python -m pytest ../../tests/ -q
```

Production (require auth / modify live infra — **[AUTH]**, do not run until approved):

```powershell
# 1. Login + preflight (modifies account session)
wrangler whoami
# 2. Secrets (each prompts interactively; stored encrypted)
cd workers/backend-proxy
wrangler secret put GROQ_API_KEY
wrangler secret put JWT_SECRET
wrangler secret put PEXELS_API_KEY
wrangler secret put OPENROUTER_API_KEY
# 3. Deploy (builds Dockerfile, pushes image, creates Worker/DO binding)
wrangler deploy
# 4. Or use the checked-in wrapper (same operations):
powershell -ExecutionPolicy Bypass -File scripts/cloudflare-deploy.ps1
```

Tunnel alternative (no Cloudflare login; local backend + public URL for mobile testing):

```powershell
# Terminal 1:
python -m uvicorn sahlha.app.main:app --host 127.0.0.1 --port 8000
# Terminal 2:
powershell -ExecutionPolicy Bypass -File scripts/cloudflare-tunnel-quick.ps1
# Then: flutter run --dart-define API_BASE_URL=<printed https://*.trycloudflare.com URL>
```

### Validation / smoke tests (Stage 1 exit criteria)

```powershell
curl https://<your-worker>.workers.dev/edge-health   # edge probe, no container wake
curl https://<your-worker>.workers.dev/health          # container health + boolean flags
python -m pytest tests/ -q                             # backend suite still green
```

Then the product loop (see `deployment-checklist.md`): register teacher → classroom → upload → extract skills → explanations → banks → approve → student join → study → assessment → submit → mastery; verify audio/image degrade honestly without keys.

### Expected outcome / rollback

- Outcome: public HTTPS backend running the unmodified agent; mobile app pointed at it; demo loop completable; disk-ephemeral caveat documented.
- Rollback: `wrangler rollback` (or redeploy previous version) **[AUTH]**; or fall back to tunnel/local backend by flipping `API_BASE_URL`. No data migration to undo in Stage 1 (ephemeral by design — do not demo with irreplaceable data).

## Stage 2 — Recommended Cloudflare integrations (concrete benefit only)

1. **R2 for `data/uploads|audio|images`.** Add a storage backend abstraction (write-through to R2, DB keeps keys); presigned upload route; background backfill of existing files. Schema: no change (keys only). Validates: upload → R2 object → study/audio/image fetch after container restart.
2. **DNS + custom domain + TLS.** Orange-cloud `api.<domain>` → Worker; update `CORS_EXTRA_ORIGINS` + mobile `API_BASE_URL`; verify HTTPS + HSTS.
3. **AI Gateway for Groq/OpenRouter.** Point `GROQ_BASE_URL`/`OPENROUTER_BASE_URL` at the gateway; verify `json_object` passthrough, caching rules, log redaction. No prompt/logic change.
4. **Persistent relational store (only when demo data must survive).** Preferred: external Postgres via `DATABASE_URL` + Alembic migration (replaces hand-rolled `_ensure_columns`); `Hyperdrive` optional pooler. D1 is **not** recommended (dialect/throughput/metering mismatch — see service mapping). Validates: restart/redeploy preserves users/grades/banks.
5. **CI/CD.** GitHub Actions: `pytest` → `tsc` → `docker build` → `wrangler deploy` on approved branches **[AUTH]**.

Each item needs: migration script (R2 backfill / Postgres `alembic upgrade head`), env updates, and a re-run of the full checklist. Do not bundle them into one deploy.

## Stage 3 — Reliability and optimization (only as bottlenecks prove out)

- **Latency:** keep `EMBEDDING_WARMUP=true`; raise container `sleepAfter`/min-instances if cold starts hurt demos; cache audio/images aggressively (hash keys already); add CDN cache for public image/audio GETs.
- **Agent reliability:** idempotency keys on upload/generate; structured `trace` shipped to Workers Logs (redacted); 429/5xx dashboards via AI Gateway; bounded retries already in code — add DLQ only with Queues.
- **RAG performance:** pin the embedding model (resolve `paraphrase-multilingual` vs `all-MiniLM` divergence first); pre-warm after deploy; consider Vectorize only when corpus/instance scale demands it (re-embed + re-tune floor/MMR + re-validate paraphrase tests).
- **Storage efficiency:** R2 lifecycle rules for superseded bank artifacts; cap `vectors.npz` rebuilds via incremental path (already); paginate list endpoints (new code, approved separately).
- **Cost/scale:** load-test `max_instances: 2` → raise only with data; set Workers CPU-limit guardrails; monitor Containers memory/vCPU/disk + R2 ops + D1-free (unused) + neuron usage.
