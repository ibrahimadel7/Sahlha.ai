import type { Context, Next } from "hono";
import type { Env } from "./env";
import { q1, run } from "./db";
import { err, nowIso, uid } from "./util";

export interface User {
  id: string;
  name: string;
  email: string;
  password_hash: string;
  role: string;
  active: number;
  link_code: string;
}

// PBKDF2 iterations for the Workers port. The stored format carries the
// iteration count (pbkdf2$<iters>$<salt>$<hash>), so this can be raised later
// and old hashes still verify. Kept modest: key derivation is pure CPU and
// the free tier allows 10ms per invocation.
const ITERATIONS = 50_000;

function b64e(b: ArrayBuffer | Uint8Array): string {
  const u = b instanceof Uint8Array ? b : new Uint8Array(b);
  let s = "";
  for (const x of u) s += String.fromCharCode(x);
  return btoa(s);
}

function b64d(s: string): Uint8Array {
  const bin = atob(s);
  const u = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) u[i] = bin.charCodeAt(i);
  return u;
}

function ab(u: Uint8Array): Uint8Array<ArrayBuffer> {
  return new Uint8Array(u);
}

export async function hashPassword(password: string): Promise<string> {
  if (!password || password.length < 6) throw new Error("Password must be at least 6 characters");
  const salt = new Uint8Array(new ArrayBuffer(16));
  crypto.getRandomValues(salt);
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(password), "PBKDF2", false, [
    "deriveBits",
  ]);
  const bits = await crypto.subtle.deriveBits(
    { name: "PBKDF2", salt, iterations: ITERATIONS, hash: "SHA-256" },
    key,
    256,
  );
  return `pbkdf2$${ITERATIONS}$${b64e(salt)}$${b64e(bits)}`;
}

export async function verifyPassword(password: string, stored: string): Promise<boolean> {
  try {
    const [scheme, iters, saltB64, hashB64] = stored.split("$");
    if (scheme !== "pbkdf2") return false;
    const salt = b64d(saltB64);
    const expected = b64d(hashB64);
    const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(password), "PBKDF2", false, [
      "deriveBits",
    ]);
    const bits = new Uint8Array(
      await crypto.subtle.deriveBits(
        { name: "PBKDF2", salt: ab(salt), iterations: parseInt(iters, 10), hash: "SHA-256" },
        key,
        256,
      ),
    );
    if (bits.length !== expected.length) return false;
    let diff = 0;
    for (let i = 0; i < bits.length; i++) diff |= bits[i] ^ expected[i];
    return diff === 0;
  } catch {
    return false;
  }
}

async function hmacKey(secret: string): Promise<CryptoKey> {
  return crypto.subtle.importKey("raw", ab(new TextEncoder().encode(secret)), { name: "HMAC", hash: "SHA-256" }, false, [
    "sign",
    "verify",
  ]);
}

function b64url(u: Uint8Array): string {
  let s = "";
  for (const x of u) s += String.fromCharCode(x);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function unb64url(s: string): Uint8Array {
  const p = s.replace(/-/g, "+").replace(/_/g, "/");
  return b64d(p + "=".repeat((4 - (p.length % 4)) % 4));
}

export async function createToken(env: Env, userId: string, role: string): Promise<string> {
  const header = b64url(new TextEncoder().encode(JSON.stringify({ alg: "HS256", typ: "JWT" })));
  const now = Math.floor(Date.now() / 1000);
  const expMin = parseInt(env.JWT_EXPIRES_MINUTES || "10080", 10);
  const payload = b64url(
    new TextEncoder().encode(JSON.stringify({ sub: userId, role, iat: now, exp: now + expMin * 60 })),
  );
  const sig = new Uint8Array(await crypto.subtle.sign("HMAC", await hmacKey(env.JWT_SECRET), ab(new TextEncoder().encode(`${header}.${payload}`))));
  return `${header}.${payload}.${b64url(sig)}`;
}

export async function decodeToken(env: Env, token: string): Promise<{ sub: string; role: string } | null> {
  try {
    const [h, p, s] = token.split(".");
    if (!h || !p || !s) return null;
    const ok = await crypto.subtle.verify(
      "HMAC",
      await hmacKey(env.JWT_SECRET),
      ab(unb64url(s)),
      ab(new TextEncoder().encode(`${h}.${p}`)),
    );
    if (!ok) return null;
    const payload = JSON.parse(new TextDecoder().decode(unb64url(p)));
    if (typeof payload.exp === "number" && payload.exp < Math.floor(Date.now() / 1000)) return "expired" as unknown as null;
    if (!payload.sub) return null;
    return { sub: payload.sub, role: payload.role };
  } catch {
    return null;
  }
}

export function userOut(u: User) {
  return { id: u.id, name: u.name, email: u.email, role: u.role, link_code: u.role === "student" ? u.link_code : "" };
}

export async function currentUser(c: Context<{ Bindings: Env }>): Promise<User | null> {
  const h = c.req.header("authorization") || "";
  const m = /^bearer\s+(.+)$/i.exec(h);
  if (!m) return null;
  const dec = await decodeToken(c.env, m[1]);
  if (!dec || (dec as unknown as string) === "expired") return null;
  const u = await q1<User>(c.env.DB, "SELECT * FROM users WHERE id = ?", dec.sub);
  if (!u || !u.active) return null;
  return u;
}

export function requireRole(role: string) {
  return async (c: Context<{ Bindings: Env }>, next: Next) => {
    const u = await currentUser(c);
    if (!u) return err(c, 401, "Not authenticated");
    if (u.role !== role) return err(c, 403, "Not allowed");
    (c as unknown as { set: (k: string, v: unknown) => void }).set("user", u);
    await next();
  };
}

export function getUser(c: Context): User {
  return (c as unknown as { get: (k: string) => unknown }).get("user") as User;
}

export async function ensureProfile(db: D1Database, studentId: string) {
  const ex = await q1(db, "SELECT student_id FROM student_learning_profiles WHERE student_id = ?", studentId);
  if (!ex) {
    await run(
      db,
      "INSERT INTO student_learning_profiles (student_id, onboarding_completed, updated_at) VALUES (?,?,?)",
      studentId,
      0,
      nowIso(),
    );
  }
}

export { uid, nowIso };
