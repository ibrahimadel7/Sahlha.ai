export interface Env {
  DB: D1Database;
  MEDIA: KVNamespace;
  AI: Ai;
  JWT_SECRET: string;
  JWT_EXPIRES_MINUTES?: string;
  CORS_EXTRA_ORIGINS?: string;
  GROQ_API_KEY?: string;
  GROQ_MODEL?: string;
  GROQ_BASE_URL?: string;
  OPENROUTER_API_KEY?: string;
  OPENROUTER_MODEL?: string;
  OPENROUTER_BASE_URL?: string;
  OPENAI_API_KEY?: string;
  // Provider priority: "openrouter" (default) or "groq". The other
  // configured provider is used automatically on retryable failures.
  LLM_PRIMARY?: string;
  TTS_PRIMARY?: string;
  PEXELS_API_KEY?: string;
  GROQ_TTS_MODEL?: string;
  GROQ_TTS_VOICE?: string;
  OPENROUTER_TTS_MODEL?: string;
  OPENROUTER_TTS_VOICE?: string;
  EMBEDDING_MODEL?: string;
}
