# Sahlah — Architecture Diagrams (Mermaid)

> All diagrams render in standard Markdown/Mermaid viewers. They reflect verified code, not aspirational infra.

## 1. Current architecture (as-built)

```mermaid
flowchart TB
  subgraph Clients
    MOB[mobile/ Flutter<br/>Riverpod + go_router + Dio<br/>API_BASE_URL compile-time]
    WEB[frontend/index.html at /app<br/>testing UI]
    DEV[streamlit_app.py<br/>dev debug tool]
  end
  subgraph Backend [FastAPI sahlha/app/main.py — 14 routers]
    PLAT[Platform routers<br/>auth / classrooms / materials<br/>student / teacher_platform / parent]
    LEG[Legacy routers<br/>documents / agent / teacher<br/>assessment / audio / images / catalog / workflow]
    SVC_P[services/platform.py<br/>+ mapping / mastery / profiles]
    SVC_L[services/services.py<br/>legacy AI-loop logic]
  end
  subgraph AgentRAG [Agent + RAG — same process]
    AG[SahlhaAgent<br/>8-phase state machine<br/>no LLM tool loop]
    WF[workflow/ LangGraph<br/>MemorySaver in-process]
    TL[tools/ rag skill question<br/>assessment student explanation<br/>audio image critique]
    RG[rag/ ingestion ocr chunking<br/>embeddings MiniLM or TF-IDF<br/>vectorstore cosine+MMR<br/>retriever]
    LLM[llm.py<br/>Groq → OpenRouter once<br/>→ grounded fallback]
    MD[audio/tts speech envelope<br/>images/pexels + categories]
  end
  subgraph Persist [Local disk + SQLite]
    DB[(data/sahlha.db<br/>SQLite + SQLAlchemy<br/>users classrooms materials<br/>docs chunks skills banks<br/>assessments attempts memory)]
    DK[data/uploads audio images<br/>vectors.npz + tfidf pkl]
  end
  subgraph Ext [External providers]
    GQ[Groq LLM + Orpheus TTS]
    OR[OpenRouter LLM + TTS backup]
    PX[Pexels images]
    OCRB[Tesseract + Poppler binaries]
  end
  MOB --> PLAT
  MOB --> LEG
  WEB --> PLAT
  WEB --> LEG
  DEV --> LEG
  PLAT --> SVC_P
  LEG --> SVC_L
  SVC_P --> SVC_L
  SVC_P --> DB
  SVC_L --> AG
  WF --> AG
  AG --> TL
  TL --> RG
  TL --> MD
  TL --> DB
  RG --> DB
  RG --> DK
  MD --> DK
  AG --> LLM
  LLM --> GQ
  LLM --> OR
  MD --> GQ
  MD --> OR
  MD --> PX
  RG --> OCRB
```

## 2. Proposed deployment architecture (Stage 1 demo → Stage 2 production)

```mermaid
flowchart TB
  subgraph Edge [Cloudflare edge]
    DNS[DNS + TLS + proxy<br/>api.domain + worker.dev]
    W[Worker proxy workers/backend-proxy<br/>/edge-health at edge<br/>routing only]
    GW[AI Gateway<br/>Groq/OpenRouter observability]
  end
  subgraph Compute [Cloudflare Containers — Stage 1]
    CT[SahlhaBackend container<br/>existing Dockerfile<br/>uvicorn --workers 1<br/>ephemeral disk demo]
    DO[(Durable Object SAHLHA_BACKEND<br/>container backing)]
  end
  subgraph Persist2 [Stage 2 persistence]
    R2[(R2<br/>uploads audio images)]
    PG[(Postgres external<br/>Neon Supabase Render<br/>via DATABASE_URL)]
  end
  subgraph Ext2 [External AI]
    GQ2[Groq]:::ext
    OR2[OpenRouter]:::ext
    PX2[Pexels]:::ext
  end
  subgraph Clients2 [Clients]
    MOB2[Flutter app<br/>API_BASE_URL = worker/domain]:::cli
  end
  MOB2 --> DNS
  DNS --> W
  W --> CT
  CT -.-> DO
  CT --> GW
  GW --> GQ2
  GW --> OR2
  CT --> PX2
  CT -. Stage 1 ephemeral .-> DK1[data/ in container]
  CT -- Stage 2 --> R2
  CT -- Stage 2 --> PG
  classDef ext fill:#f6f6f6,stroke:#999
  classDef cli fill:#e8f4f0,stroke:#0E9388
```

Legend: solid = Stage 1 path; dashed-labeled = Stage 2 additions. Synchronous request paths are solid arrows; async work (`BackgroundTasks` index rebuild, audio prefetch) stays **inside** the container (no separate queue in Stage 1).

## 3. Agent execution flow

```mermaid
flowchart TB
  REQ[API request<br/>extract / generate / start / submit] --> SVC[services: SahlhaAgent db, AgentState]
  SVC --> RET[rag_tools retrieve<br/>lesson top5 / skill top3-4<br/>scoped, never cross-lesson]
  RET --> PRM[prompts build_*<br/>budgets 6000 / 4000 chars]
  PRM --> LLM{LLM?}
  LLM -- Groq ok --> G[complete_json / generate_questions_llm]
  LLM -- retryable + OR key --> O[OpenRouter failover once]
  LLM -- none / both fail --> F[grounded fallback over chunk sentences]
  G --> CR[critique: LLM opt-in else deterministic<br/>fail ungrounded/wrong/irrelevant]
  O --> CR
  F --> CR
  CR --> VAL[Pydantic raw → attach evidence<br/>→ strict → partition grounding]
  VAL --> TOP[one bounded fallback top-up if short]
  TOP --> PER[register_skill / save_questions<br/>append-only version pending_review]
  PER --> GATE{WAITING_FOR_TEACHER}
  GATE -- approve --> AS[start_assessment<br/>latest-approved pool minus flagged/retired<br/>4 per bank: failed→weak→unseen→balance]
  AS --> EV[submit: evaluate deterministic<br/>record batched + scoped memory<br/>mastery + needs_review]
  PER -.-> MED[audio + image tools<br/>non-fatal hash cache]
```

## 4. Document ingestion and RAG workflow (implemented vs planned)

Implemented (solid) vs planned/deferred (dashed):

```mermaid
flowchart LR
  UP[Teacher/parent upload<br/>PDF DOCX TXT MD image<br/>25MB cap + ext allowlist] --> VG[validate + sanitize name]
  VG --> EX[extract_document_text<br/>pypdf/docx/txt native<br/>Tesseract+Poppler if scanned]
  EX --> LS[derive lesson_id<br/>explicit > title line > filename]
  LS --> CH[chunk_text 800/120<br/>sentence-aware + overlap]
  CH --> PS[persist Document + Chunks<br/>course/lesson/skill/page/index]
  PS --> IX{index}
  IX -- HTTP path --> BG[BackgroundTasks rebuild_index<br/>incremental dense or TF-IDF refit]
  IX -- tests/sync path --> SY[synchronous rebuild]
  BG --> VS[vectors.npz cache<br/>ids matrix backend]
  SY --> VS
  VS --> RT[search: cosine → MMR 0.7<br/>→ floor 0.05 → backoff → lexical]
  RT --> AG2[agent pulls per phase<br/>same chunks for gen + evidence]
  AG2 --> SK[skills → explanations → banks]
  SK --> TG[teacher approve/reject/flag<br/>append-only versions]
  TG --> ST[student study + assess<br/>answers stripped]
  ST -.-> VZ[Vectorize migration<br/>deferred]
  ST -.-> Q[Queues for OCR/index<br/>deferred]
```

Verified implemented: steps UP→ST (including PPTX caveat: no dedicated parser — falls to raw decode).
Deferred (not in code): Vectorize, Queues/Workflows for ingestion, reranker wiring, `LearningContent` visuals.
