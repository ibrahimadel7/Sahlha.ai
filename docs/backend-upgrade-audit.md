# Backend upgrade audit

| Feature | Current state | Needed change | Conflict risk |
|---|---|---|---|
| Platform/auth | JWT, roles, ownership, enrollment and parent links implemented | Preserve guards; prevent unscoped access and trace leakage | Legacy public development routes coexist with platform routes |
| RAG | TF-IDF, character chunks, no vector cache; empty scoped search falls back globally | Lazy dense model, safe fallback, persistent incremental vectors, MMR, sentence chunks | Never cross material/classroom boundaries |
| OCR/ingestion | Structured extraction and bounded page OCR exist; synchronous indexing | Binary discovery, meaningful-text threshold, safe names/titles, background status lifecycle | Preserve short native PDFs and material ownership |
| Providers | Groq text/speech, grounded fallbacks; no OpenRouter | Explicit retry classification, one failover, WAV-compatible speech | Preserve environment-selected models and authenticated media |
| Agent/media | Agent embeds skill/explanation persistence; separate media tools and caches exist | Extract tools, independently fill media gaps, validate caches | Media failures cannot roll back explanations |
| Questions | MCQ shape validation, pending review and bank versions exist | Grounding critique/top-up, append-only teacher flags and feedback | Preserve approval boundary and approved history |
| Memory/assessment | Scoped performance columns exist, but legacy error fallback merges scopes; assessment scope missing | Safe legacy adoption/migration, scoped selection and persisted assessment context | Existing SQLite rows must survive |
| Selection/study | Per-bank selection exists; difficulty stage starves; repeated queries | Flag exclusion, priority/balance, missing-bank errors, batched study bundle | Keep current student response fields and mastery states |
| Verification | Platform/media regression suites exist | Isolate providers/data, add subsystem and migration tests, run full suite | Never touch real .env, provider accounts, or live database in tests |

Flutter is out of scope and will remain unchanged for this upgrade.
