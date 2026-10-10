import { Hono } from "hono";
import type { Env } from "../env";
import { createToken, currentUser, hashPassword, requireRole, userOut, verifyPassword, type User } from "../auth";
import { q1, run } from "../db";
import { err } from "../util";
import { linkCode, nowIso, uid } from "../util";
import { ensureProfile } from "../auth";
import { checkRate, clientIp } from "../ratelimit";

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export const authRoutes = new Hono<{ Bindings: Env }>();

authRoutes.post("/register", async (c) => {
  const body = await c.req.json().catch(() => ({}));
  const name = String(body.name || "").trim();
  const email = String(body.email || "").trim().toLowerCase();
  const password = String(body.password || "");
  const role = String(body.role || "");
  if (!name || name.length > 256) return err(c, 422, "Name is required");
  if (!EMAIL_RE.test(email)) return err(c, 422, "Enter a valid email address");
  if (!password || password.length < 6 || password.length > 128) return err(c, 422, "Password must be at least 6 characters");
  if (!["teacher", "student", "parent"].includes(role)) return err(c, 422, "Role must be teacher, student, or parent");
  const rl = await checkRate(c.env, "register", clientIp(c), 10, 60);
  if (!rl.allowed) return err(c, 429, "Too many attempts. Try again shortly.");
  const ex = await q1(c.env.DB, "SELECT id FROM users WHERE email = ?", email);
  if (ex) return err(c, 409, "Email is already registered");
  let pwHash: string;
  try {
    pwHash = await hashPassword(password);
  } catch (e) {
    return err(c, 422, e instanceof Error ? e.message : "Invalid password");
  }
  const id = uid();
  const now = nowIso();
  const code = role === "student" ? linkCode(8) : "";
  await run(
    c.env.DB,
    "INSERT INTO users (id, name, email, password_hash, role, active, link_code, created_at, updated_at) VALUES (?,?,?,?,?,1,?,?,?)",
    id, name.slice(0, 256), email, pwHash, role, code, now, now,
  );
  const user = (await q1<User>(c.env.DB, "SELECT * FROM users WHERE id = ?", id))!;
  if (role === "student") await ensureProfile(c.env.DB, id);
  const token = await createToken(c.env, id, role);
  return c.json({ token, user: userOut(user) }, 201);
});

authRoutes.post("/login", async (c) => {
  const body = await c.req.json().catch(() => ({}));
  const rl = await checkRate(c.env, "login", clientIp(c), 20, 60);
  if (!rl.allowed) return err(c, 429, "Too many attempts. Try again shortly.");
  const email = String(body.email || "").trim().toLowerCase();
  const password = String(body.password || "");
  const user = await q1<User>(c.env.DB, "SELECT * FROM users WHERE email = ?", email);
  if (!user || !(await verifyPassword(password, user.password_hash))) return err(c, 401, "Invalid email or password");
  if (!user.active) return err(c, 403, "Account is disabled");
  const token = await createToken(c.env, user.id, user.role);
  return c.json({ token, user: userOut(user) });
});

authRoutes.get("/me", async (c) => {
  const user = await currentUser(c);
  if (!user) return err(c, 401, "Not authenticated");
  return c.json(userOut(user));
});

authRoutes.patch("/me", async (c) => {
  const user = await currentUser(c);
  if (!user) return err(c, 401, "Not authenticated");
  const body = await c.req.json().catch(() => ({}));
  if (body.name) {
    const name = String(body.name).trim().slice(0, 256);
    if (!name) return err(c, 422, "Name is required");
    await run(c.env.DB, "UPDATE users SET name = ?, updated_at = ? WHERE id = ?", name, nowIso(), user.id);
    const fresh = (await q1<User>(c.env.DB, "SELECT * FROM users WHERE id = ?", user.id))!;
    return c.json(userOut(fresh));
  }
  return c.json(userOut(user));
});
