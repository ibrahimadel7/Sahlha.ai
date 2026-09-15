"""Central application settings."""
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    app_name: str = "Sahlha AI Learning Agent (MVP)"
    database_url: str = "sqlite:///./data/sahlha.db"
    upload_dir: str = "./data/uploads"
    vectorizer_path: str = "./data/tfidf_vectorizer.pkl"

    # LLM provider: Groq (OpenAI-compatible API). Empty key => grounded fallback generator.
    groq_api_key: str = ""
    groq_model: str = "openai/gpt-oss-120b"
    groq_base_url: str = "https://api.groq.com/openai/v1"

    # Optional OpenAI override (used only if Groq key is absent).
    openai_api_key: str = ""
    openai_model: str = "gpt-4o-mini"
    openai_base_url: str = ""

    # Backup LLM provider: OpenRouter (OpenAI-compatible). Used only when Groq fails.
    openrouter_api_key: str = ""
    openrouter_base_url: str = "https://openrouter.ai/api/v1"
    openrouter_model: str = "openai/gpt-4o-mini"

    # Groq text-to-speech (Orpheus English). Requires GROQ_API_KEY + accepted model terms
    # in the Groq console. No offline fallback exists for audio.
    groq_tts_model: str = "canopylabs/orpheus-v1-english"
    groq_tts_voice: str = "troy"
    groq_tts_max_chars: int = 900  # per TTS request; longer text is chunked + stitched
    audio_dir: str = "./data/audio"

    # Backup TTS via OpenRouter (OpenAI-compatible audio/speech). Used when Groq TTS fails.
    # Per OpenRouter docs: POST /api/v1/audio/speech with mp3/pcm, e.g. fish-audio/s2.1-pro-free:free (free) or openai/gpt-4o-mini-tts-2025-12-15
    openrouter_tts_model: str = "fish-audio/s2.1-pro-free:free"
    openrouter_tts_voice: str = "alloy"

    # Pexels image search (one related image per skill). Empty => image tool unavailable.
    pexels_api_key: str = ""
    image_dir: str = "./data/images"

    chunk_size: int = 800
    chunk_overlap: int = 120
    top_k_retrieval: int = 5
    assessment_num_questions: int = 4  # questions selected from EACH approved bank

    # Token optimization
    llm_max_context_chars: int = 6000  # was 12000 — halves input tokens
    llm_skill_context_chars: int = 4000  # skill explanations/questions
    enable_llm_critique: bool = False  # deterministic critique saves ~50% tokens; enable for high-stakes


settings = Settings()
