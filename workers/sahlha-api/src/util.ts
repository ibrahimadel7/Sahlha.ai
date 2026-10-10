import type { Context } from "hono";

export const DEV_JWT_SECRET = "sahlha-dev-secret-change-me-in-production-32";

/** Path param that is always a string ("" when absent). Hono types param() as string|undefined. */
export function P(c: Context, name: string): string {
  return c.req.param(name) || "";
}

export function uid(): string {
  const b = new Uint8Array(9);
  crypto.getRandomValues(b);
  return [...b].map((x) => x.toString(16).padStart(2, "0")).join("").slice(0, 12);
}

export function linkCode(len = 8): string {
  const abc = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
  const b = new Uint8Array(len);
  crypto.getRandomValues(b);
  return [...b].map((x) => abc[x % abc.length]).join("");
}

export function nowIso(): string {
  return new Date().toISOString();
}

export function jparse<T>(v: unknown, fallback: T): T {
  if (v === null || v === undefined || v === "") return fallback;
  if (typeof v !== "string") return v as T;
  try {
    return JSON.parse(v) as T;
  } catch {
    return fallback;
  }
}

export function jstr(v: unknown): string {
  return JSON.stringify(v ?? null);
}

export function err(c: Context, status: number, message: string) {
  return c.json({ detail: message }, status as 400);
}

export function slug(s: string, fallback = "lesson_1"): string {
  const words = (s || "")
    .replace(/[^A-Za-z0-9 ]+/g, " ")
    .trim()
    .split(/\s+/)
    .filter((w) => w.length > 1)
    .slice(0, 6)
    .map((w) => w.toLowerCase());
  const out = words.join("_").replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "");
  return out.length >= 3 ? out.slice(0, 80) : fallback;
}

export function corsOrigins(env: { CORS_EXTRA_ORIGINS?: string }): string[] {
  const base = ["http://localhost:3000", "https://sahlha.pages.dev"];
  const extra = (env.CORS_EXTRA_ORIGINS || "")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);
  return [...new Set([...base, ...extra])];
}
