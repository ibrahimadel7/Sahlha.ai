# Sahlha Workers-native backend — Security pass (free tier)

Deployed and verified. This note records what was hardened, what was
deliberately left at Python-parity, and the known residual risks.

## Implemented

- **Rate limiting (KV fixed-window, fail-open).** Register 10/min/IP, login
  20/min/IP, upload 20/h/user, extract 30/h, bank generation 20/h, single
  regenerations 30/h, check 600/h, submit 120/h, media 200/h. Verified: login
  429s on attempt 21. Fail-open on KV errors/quota so learning never breaks.
  Note: KV free allows 1k writes/day — under heavy abuse the limiter itself
  degrades to off; the 429s still fire first.
- **Security headers (Worker):** `nosniff`, `SAMEORIGIN` framing,
  `no-referrer`, restrictive `Permissions-Policy`, HSTS. Verified live.
- **Security headers (Pages):** `mobile/web/_headers` ships with the site
  (also copied into `build/web`); verified on `sahlha.pages.dev`.
- **Upload caps:** 10MB files (128MB isolate), 600-chunk guard with a clear
  400 (each chunk costs embedding subrequests + D1 writes; free caps are
  50/invocation). Diverges from Python's 25MB — client told exactly why.
- **No preview URLs** (`preview_urls = false`): only the production worker
  URL serves traffic.
- **Cached-media validation:** poisoned/empty audio stubs are rejected and
  re-synthesized instead of served (a real 44-byte stub was caught in smoke
  tests); envelope no longer crashes on empty WAV (`timed` fallback).
- **Preserved:** parameterized D1 queries everywhere (no string-built SQL),
  per-role guards + ownership checks on every route, answers stripped from
  student payloads (verified: no `correct_answer` leak), media behind JWT,
  secrets only via `wrangler secret`, 500s return "Internal error".

## Left at Python parity (known, accepted)

- Email enumeration via register-409 and login-401/403 distinction.
- 7-day JWT, no refresh rotation; PBKDF2 at 50k iterations (free-CPU bound;
  format carries the count so it can rise later).
- No bot protection on public register/upload.

## Recommended next (not done)

- Cloudflare Turnstile on register/upload (needs site/secret keys + a small
  Flutter widget + rebuild).
- AI Gateway in front of Groq/OpenRouter for observability/rate visibility.
- Raise PBKDF2 iterations if ever leaving the free CPU budget.
- Paginate list endpoints; add idempotency keys on upload/generate.
