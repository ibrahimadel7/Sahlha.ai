# Sahlah — Cost and Free-Tier Assessment

> Pricing sources (Oct 2026): Workers pricing `https://developers.cloudflare.com/workers/platform/pricing/`,
> Containers pricing `https://developers.cloudflare.com/containers/pricing/`,
> R2 `https://developers.cloudflare.com/r2/pricing/`, D1 `https://developers.cloudflare.com/d1/platform/pricing/`,
> Vectorize `https://developers.cloudflare.com/vectorize/platform/pricing/`,
> Workers AI `https://developers.cloudflare.com/workers-ai/platform/pricing/`,
> Queues `https://developers.cloudflare.com/queues/platform/pricing/`, D1 limits `https://developers.cloudflare.com/d1/platform/limits/`,
> Workers limits `https://developers.cloudflare.com/workers/platform/limits/`.
> External provider prices change often — treat Groq/OpenRouter/Pexels numbers as directions, verify at deploy time.

## Method (do not invent usage)

For each metered service: `billable = max(0, usage − included) × unit_price`, plus the $5/mo Workers Paid base when Containers/paid features are used.
Where usage is unknown, this doc gives the **formula + assumption table** so the team can plug real numbers after the demo. No claim below asserts the whole system is free.

## Assumed workloads (explicit assumptions)

| Assumption | Scenario 1: Dev/demo | Scenario 2: Early pilot |
|---|---|---|
| Users | 3–5 testers | 3 teachers + 30 students + 10 parents |
| Documents | 5–10 small PDFs/TXT (<2MB each) | 50–150 docs (mix native + some scanned), ~500–2,000 chunks total |
| Agent generations | Dozens of skill/bank runs | Hundreds/month (banks versioned, regenerations) |
| Assessments | Tens | Hundreds–low thousands/month |
| Audio/images | Light (cache hits high) | Moderate (one image/skill, audio per explanation, hash-cached) |
| Availability | On-demand demo (container sleeps) | School-hours usage (container warm most of day) |

## Cloudflare costs by service

| Service | Free / included | Demo (S1) estimate | Pilot (S2) estimate | Bottleneck risk |
|---|---|---|---|---|
| Workers requests + CPU (proxy) | Free 100k req/day; Paid 10M req/mo + 30M CPU-ms included, then $0.30/M req + $0.02/M CPU-ms | ~$0 (proxy is thin; well under free) | $5 base covers it unless traffic explodes | Low |
| Containers (backend+agent) | **No free tier.** Paid $5/mo base includes 25 GiB-hours mem + 375 vCPU-min + 200 GB-hours disk | **~$5–8/mo.** `basic` (¼ vCPU, 1GiB) sleeping between demos stays near included allotments | **~$8–25/mo.** Warmer daytime use + OCR/embedding spikes burn vCPU-min; larger instance (`standard-1/2`) raises mem/disk burn | **Most likely Cloudflare bottleneck.** Active-CPU billing helps bursty use; sustained daytime warmth + scanned-PDF OCR is what moves the needle |
| R2 (uploads/audio/images) | 10 GB-mo + 1M Class-A + 10M Class-B ops/mo free (Standard) | $0 (MBs of files, thousands of ops) | $0–2/mo (GBs + tens of thousands of ops; zero egress helps audio/image downloads) | Low; op count only matters with cache misses/re-upload churn |
| D1 | 5M rows-read/day + 100k rows-written/day + 5GB free; paid 25B reads + 50M writes included | $0 (not used — SQLite file) | $0 (still not recommended; external Postgres instead — see below) | N/A unless adopted (then watch full-scan reads) |
| Vectorize | 30M queried + 5M stored dims/mo free; paid 50M + 10M included | $0 (not used) | $0 (deferred; 2,000 chunks × 384d ≈ 0.77M stored dims — would fit free tier if ever migrated) | None for MVP |
| Queues / Workflows | Queues free 10k ops/day; paid 1M/mo + $0.40/M. Workflows steps/storage metered | $0 (not used) | $0 unless added (ingestion queue would be trivially cheap at pilot scale) | None |
| Workers AI | 10k neurons/day free, then $0.011/1k neurons | $0 (not used — external LLMs) | $0 (deferred complement only) | None |
| AI Gateway | Logging/caching on Workers plan | $0–included | $0–included | None |
| DNS/TLS | Free plan | $0 | $0 (+ registrar domain fee ~$10–15/yr if custom domain) | None |

## Non-Cloudflare costs (usually dominate)

| Cost | Demo | Pilot | Notes |
|---|---|---|---|
| External Postgres (only Stage 2, if needed) | $0 (SQLite file) | $0–15/mo (Neon/Supabase free tier often suffices; paid tiers when data grows) | Preferred over D1 for SQLAlchemy compat. `Hyperdrive` free 100k queries/day, paid unlimited. |
| Groq LLM/TTS | $0 (free tier + rate limits; fallback covers outages) | $0–20/mo (free tier usually suffices at pilot scale; pay only if 429/quota forces upgrade or heavy TTS) | Single biggest variance. Token budgets already halved (`6000/4000` chars, deterministic critique default saves ~50%). Verify current Groq pricing/limits before pilot. |
| OpenRouter backup | $0 (unused unless Groq fails) | Pay-as-you-go micro-spend (only on Groq failover; `gpt-4o-mini`-class is cents per 1M tokens) | Requires `OPENROUTER_API_KEY`; no code change. |
| Pexels images | $0 (free API tier) | $0 | Rate limits only. |
| Tesseract/Poppler | $0 (in image) | $0 (CPU time shows up in Containers bill instead) | Scanned-PDF volume is the hidden driver — see below. |
| Mobile builds/distribution | $0 (sideload/APK) | $0 (+ Play fees only if store-listed) | `API_BASE_URL` re-point is free. |

## Worked example (illustrative, check assumptions)

Pilot container guess: `basic` instance (1 GiB) warm ~10h/day × 30d = 300 GiB-hours. Included = 25 GiB-hours → billable ≈ 275 GiB-hours ≈ 990,000 GiB-seconds × $0.0000025 ≈ **~$2.48** memory overage + $5 base + CPU active-seconds on top (e.g. 20% of ¼ vCPU × 10h × 30d ≈ 45,000 vCPU-seconds vs 22,500 included → ~22,500 × $0.00002 ≈ **~$0.45**). Total ≈ **~$8** before R2/egress/LLM. Double warmth or a bigger instance roughly doubles it — hence the $8–25/mo pilot range. Plug real `sleepAfter`/warm-hours after the demo week.

R2 pilot guess: 3GB stored + 50k Class-A + 200k Class-B → all inside free tier → **$0**.

## What can realistically remain free

- Demo: everything Cloudflare except the **$5/mo Workers Paid base** (Containers require it); R2/D1/Vectorize/Queues/Workers AI/AI Gateway all inside free tiers at demo scale; Groq/OpenRouter/Pexels free tiers + deterministic fallbacks cover the AI path.
- Pilot: R2, DNS, Gateway, Vectorize-free-equivalent, Queues-free-equivalent stay free; the **paid items are the $5 base + container overage + (likely) external LLM usage + (optionally) managed Postgres**.

## Likely cost bottlenecks (in order)

1. **Containers warmth + CPU** (OCR of scanned PDFs, dense embedding rebuilds, daytime warmth) — the only Cloudflare meter that scales with real use.
2. **External LLM/TTS spend** (Groq free-tier 429s → OpenRouter pay-as-you-go → output tokens on regenerations). Mitigations already in code: context caps, deterministic critique default, hash-cached media, append-only versions (no silent re-generation).
3. **Managed Postgres** if adopted (free tier usually suffices for pilot; watch storage + connection limits).
4. Free-tier tripwires: Workers 100k req/day (free) — irrelevant behind Paid; D1 daily caps — irrelevant (unused); R2 10GB/1M-A/10M-B — comfortable; Vectorize/Queues/AI free tiers — comfortable because unused.

## Pricing verification checklist (re-check before spending)

- [ ] Workers + Containers + R2 + D1 + Vectorize + Workers AI + Queues pages above (all fetched Oct 2026; re-open before pilot).
- [ ] Groq pricing/limits + OpenRouter model pricing at deploy time (not fetched here — do not budget from memory).
- [ ] Postgres provider (Neon/Supabase/Render) free-tier caps if Stage 2 adopts it.
- [ ] Domain registrar fee if custom domain is wanted.
