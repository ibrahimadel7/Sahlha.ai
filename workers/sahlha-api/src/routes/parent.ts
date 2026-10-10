import { Hono } from "hono";
import type { Env } from "../env";
import { getUser, requireRole } from "../auth";
import { q, q1, run } from "../db";
import { P, err, nowIso, uid } from "../util";
import { linkedStudent } from "../guards";
import { childProgress, classroomIdFromCourse, studentGrades } from "../assess";

export const parentRoutes = new Hono<{ Bindings: Env }>();

parentRoutes.post("/link-child", requireRole("parent"), async (c) => {
  const me = getUser(c);
  const body = await c.req.json().catch(() => ({}));
  const code = String(body.link_code || "").trim().toUpperCase();
  if (!code) return err(c, 422, "Link code is required");
  const child = await q1<Record<string, unknown>>(c.env.DB, "SELECT * FROM users WHERE link_code = ? AND role = 'student'", code);
  if (!child) return err(c, 404, "Invalid link code");
  const already = !!(await q1(c.env.DB, "SELECT id FROM parent_student_links WHERE parent_id = ? AND student_id = ?", me.id, String(child.id)));
  if (!already) {
    await run(c.env.DB, "INSERT INTO parent_student_links (id, parent_id, student_id, created_at) VALUES (?,?,?,?)", uid(), me.id, String(child.id), nowIso());
  }
  return c.json({ linked: true, already_linked: already, child: { id: child.id, name: child.name } }, 201);
});

parentRoutes.get("/children", requireRole("parent"), async (c) => {
  const me = getUser(c);
  const kids = await q<Record<string, unknown>>(
    c.env.DB,
    "SELECT u.* FROM users u JOIN parent_student_links l ON l.student_id = u.id WHERE l.parent_id = ? ORDER BY u.name",
    me.id,
  );
  const out = [];
  for (const k of kids) {
    const rooms = await q<Record<string, unknown>>(
      c.env.DB,
      "SELECT r.id, r.name, r.subject FROM classrooms r JOIN classroom_enrollments e ON e.classroom_id = r.id WHERE e.student_id = ?",
      String(k.id),
    );
    out.push({ id: k.id, name: k.name, classrooms: rooms });
  }
  return c.json(out);
});

parentRoutes.get("/children/:id/progress", requireRole("parent"), async (c) => {
  const me = getUser(c);
  const child = await linkedStudent(c, P(c, "id"), me.id).catch(() => null);
  if (!child) return err(c, 404, "Child not found");
  return c.json(await childProgress(c.env, String(child.id)));
});

parentRoutes.get("/children/:id/materials", requireRole("parent"), async (c) => {
  const me = getUser(c);
  const child = await linkedStudent(c, P(c, "id"), me.id).catch(() => null);
  if (!child) return err(c, 404, "Child not found");
  const mats = await q<Record<string, unknown>>(c.env.DB, "SELECT * FROM learning_materials WHERE child_student_id = ? AND scope = 'supplementary' ORDER BY rowid", String(child.id));
  const { materialDict } = await import("./materials");
  const out = [];
  for (const m of mats) out.push(await materialDict(c.env, m));
  return c.json(out);
});

parentRoutes.get("/children/:id/grades", requireRole("parent"), async (c) => {
  const me = getUser(c);
  const child = await linkedStudent(c, P(c, "id"), me.id).catch(() => null);
  if (!child) return err(c, 404, "Child not found");
  return c.json(await studentGrades(c.env, String(child.id)));
});

export { classroomIdFromCourse };
