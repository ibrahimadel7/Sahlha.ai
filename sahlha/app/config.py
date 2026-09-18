"""Central application settings."""
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    app_name: str = "Sahlha AI Learning Platform"
    database_url: str = "sqlite:///./data/sahlha.db"
    upload_dir: str = "./data/uploads"
    vectorizer_path: str = "./data/tfidf_vectorizer.pkl"
    vector_cache_path: str = "./data/vectors.npz"
    dense_embeddings_enabled: bool = True
    embedding_model: str = "sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2"
    embedding_warmup: bool = True
    vector_incremental_churn: float = 0.35
    mmr_lambda: float = 0.7
    dense_min_score: float = 0.05
    retrieval_backoff_ratio: float = 0.5
    tesseract_cmd: str = ""
    poppler_path: str = ""
    ocr_min_chars: int = 50
    ocr_languages: str = "eng+ara"
    ocr_dpi: int = 250
    reranker_enabled: bool = False
    reranker_model: str = "cross-encoder/mmarco-mMiniLMv2-L12-H384-v1"
    reranker_candidate_multiplier: int = 3
    reranker_max_candidates: int = 30
    enable_llm_critique: bool = False
    semantic_verification_enabled: bool = True
    # Mounted unconditionally in main.py during transition so both mobile platform
    # and legacy Streamlit/tests work. Set false only when legacy clients retired.
    legacy_dev_api_enabled: bool = True

    # ---- Auth (JWT) ----
    # Prototype default; override via SAHLHA_JWT_SECRET in real deployments.
    jwt_secret: str = "sahlha-dev-secret-change-me-in-production-32"
    jwt_algorithm: str = "HS256"
    jwt_expires_minutes: int = 60 * 24 * 7  # 7 days (mobile prototype convenience)

    # ---- Mastery thresholds (student-facing states) ----
    mastery_developing_min: float = 0.6  # accuracy >= this => developing
    mastery_mastered_min: float = 0.8  # accuracy >= this (+ min attempts) => mastered
    mastery_min_attempts: int = 4  # attempts required before "mastered" is awarded

    # ---- Uploads ----
    max_upload_mb: int = 25
    allowed_extensions: str = ".pdf,.docx,.pptx,.txt,.md,.png,.jpg,.jpeg,.tiff,.bmp"

    # ---- CORS (mobile development) ----
    # Comma-separated origins allowed in addition to the mobile defaults.
    cors_extra_origins: str = ""

    # LLM provider: Groq (OpenAI-compatible API). Empty key => grounded fallback generator.
    groq_api_key: str = ""
    groq_model: str = "openai/gpt-oss-120b"
    groq_base_url: str = "https://api.groq.com/openai/v1"
    # Backup LLM provider: OpenRouter (OpenAI-compatible). Used only when Groq fails.
    openrouter_api_key: str = ""
    openrouter_base_url: str = "https://openrouter.ai/api/v1"
    openrouter_model: str = "openai/gpt-4o-mini"
    provider_timeout_seconds: float = 45

    # Optional OpenAI override (used only if Groq key is absent).
    openai_api_key: str = ""
    openai_model: str = "gpt-4o-mini"
    openai_base_url: str = ""

    # Groq text-to-speech (Orpheus English). Requires GROQ_API_KEY + accepted model terms
    # in the Groq console. No offline fallback exists for audio.
    groq_tts_model: str = "canopylabs/orpheus-v1-english"
    groq_tts_voice: str = "troy"
    groq_tts_max_chars: int = 900  # per TTS request; longer text is chunked + stitched
    groq_tts_speed: float = 1.0  # provider-level rate (0.25-4.0); calm default, no text hacks
    openrouter_tts_speed: float = 1.0  # only applied by models that support `speed`
    tts_target_chars: int = 550  # preferred natural speech unit; max stays 900
    audio_dir: str = "./data/audio"
    # Backup TTS via OpenRouter (OpenAI-compatible audio/speech). Used when Groq TTS fails.
    # Per OpenRouter docs: POST /api/v1/audio/speech with mp3/pcm, e.g. fish-audio/s2.1-pro-free:free (free) or openai/gpt-4o-mini-tts-2025-12-15
    openrouter_tts_model: str = "fish-audio/s2.1-pro-free:free"
    openrouter_tts_voice: str = "alloy"
    # MP3 default: self-describing sample rate, always plays at normal speed.
    # Use pcm only with a matching OPENROUTER_TTS_SAMPLE_RATE (Fish 44100,
    # OpenAI 24000) — a mismatch plays deep + slow.
    openrouter_tts_format: str = "mp3"
    openrouter_tts_sample_rate: int = 44100

    # Pexels image search (one related image per skill). Empty => image tool unavailable.
    pexels_api_key: str = ""
    image_dir: str = "./data/images"
    teacher_api_key: str = ""

    # Optional teacher gate: when TEACHER_API_KEY is set, mutating teacher
    # endpoints (upload / extract / generate / approve / reject / flag) require
    # header X-API-Key. Empty (dev/test default) => all requests allowed.

    chunk_size: int = 800
    chunk_overlap: int = 120
    top_k_retrieval: int = 5
    assessment_num_questions: int = 4  # questions selected from EACH skill's latest approved bank

    # ---- Skill discovery capacity (dynamic soft cap + hard safety bound) ----
    skill_discovery_min_cap: int = 6
    skill_discovery_hard_cap: int = 22

    # ---- Task-specific LLM temperatures (bounded, grounding-first) ----
    skill_extraction_temperature: float = 0.15
    skill_consolidation_temperature: float = 0.15
    semantic_verifier_temperature: float = 0.1
    question_generation_temperature: float = 0.4
    explanation_temperature: float = 0.3

    # Token optimization
    llm_max_context_chars: int = 6000  # was 12000 — halves input tokens
    llm_skill_context_chars: int = 4000  # skill explanations/questions


settings = Settings()
