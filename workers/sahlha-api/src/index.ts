import { Hono } from "hono";
import { cors } from "hono/cors";
import type { Env } from "./env";
import { DEV_JWT_SECRET, corsOrigins } from "./util";
import { llmAvailable } from "./llm";
import { authRoutes } from "./routes/auth";
import { classroomRoutes } from "./routes/classrooms";
import { materialRoutes } from "./routes/materials";
import { studentRoutes } from "./routes/student";
import { teacherRoutes } from "./routes/teacher";
import { parentRoutes } from "./routes/parent";

const app = new Hono<{ Bindings: Env }>();

app.use("*", async (c, next) => {
  const origins = corsOrigins(c.env);
  const mw = cors({
    origin: origins,
    allowHeaders: ["Authorization", "Content-Type"],
    allowMethods: ["GET", "POST", "PATCH", "DELETE", "OPTIONS"],
    maxAge: 86400,
  });
  await mw(c, next);
  // Baseline hardening headers (API serves JSON/bytes only; no framing needed).
  c.header("X-Content-Type-Options", "nosniff");
  c.header("X-Frame-Options", "SAMEORIGIN");
  c.header("Referrer-Policy", "no-referrer");
  c.header("Permissions-Policy", "camera=(), microphone=(), geolocation=()");
  c.header("Strict-Transport-Security", "max-age=31536000");
});

app.get("/", (c) => c.json({ service: "sahlha", status: "ok", tier: "workers-native" }));

app.get("/health", (c) => {
  const jwt = c.env.JWT_SECRET || "";
  return c.json({
    ok: true,
    tier: "workers-native",
    tts_configured: !!(c.env.GROQ_API_KEY || c.env.OPENROUTER_API_KEY),
    images_configured: !!c.env.PEXELS_API_KEY,
    llm_configured: llmAvailable(c.env),
    jwt_configured: !!jwt && jwt !== DEV_JWT_SECRET,
    embeddings_model: c.env.EMBEDDING_MODEL || "@cf/baai/bge-m3",
    ocr_available: false,
    ocr_note: "Scanned documents need native OCR; upload searchable PDF/TXT/MD.",
  });
});

app.route("/auth", authRoutes);
app.route("/classrooms", classroomRoutes);
app.route("/materials", materialRoutes);
app.route("/student", studentRoutes);
app.route("/teacher", teacherRoutes);
app.route("/parent", parentRoutes);

app.notFound((c) => c.json({ detail: "Not found" }, 404));

app.onError((e, c) => {
  const status = (e as { status?: number }).status || 500;
  const msg = status === 500 ? "Internal error" : e instanceof Error ? e.message : "Request failed";
  return c.json({ detail: msg }, status as 400);
});

export default app;
