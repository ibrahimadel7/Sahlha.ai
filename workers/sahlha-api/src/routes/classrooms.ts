import { Hono } from "hono";
import type { Env } from "../env";
import { currentUser, getUser, requireRole } from "../auth";
import { q, q1, run } from "../db";
import { P, err, linkCode, nowIso, uid } from "../util";
import { enrolledClassroom, teacherClassroom } from "../guards";

function out(room: Record<string, unknown>, students?: number) {
  const p: Record<string, unknown> = {
    id: room.id, teacher_id: room.teacher_id, name: room.name,
    subject: room.subject, grade_level: room.grade_level, join_code: room.join_code,
  };
  if (students !== undefined) p.num_students = students;
  return p;
}

async function countEnrolled(db: D1Database, classroomId: string): Promise<number> {
  const r = await q1<{ n: number }>(db, "SELECT COUNT(*) AS n FROM classroom_enrollments WHERE classroom_id = ?", classroomId);
  return Number(r?.n || 0);
}

export const classroomRoutes = new Hono<{ Bindings: Env }>();

classroomRoutes.post("", requireRole("teacher"), async (c) => {
  const me = getUser(c);
  const body = await c.req.json().catch(() => ({}));
  const name = String(body.name || "").trim();
  if (!name || name.length > 256) return err(c, 422, "Name is required");
  const id = uid();
  const now = nowIso();
  await run(
    c.env.DB,
    "INSERT INTO classrooms (id, teacher_id, name, subject, grade_level, join_code, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?)",
    id, me.id, name, String(body.subject || "").slice(0, 128), String(body.grade_level || "").slice(0, 64), linkCode(8), now, now,
  );
  const room = (await q1<Record<string, unknown>>(c.env.DB, "SELECT * FROM classrooms WHERE id = ?", id))!;
  return c.json(out(room, 0), 201);
});

classroomRoutes.get("", async (c) => {
  const me = await currentUser(c);
  if (!me) return err(c, 401, "Not authenticated");
  if (me.role === "teacher") {
    const rooms = await q<Record<string, unknown>>(c.env.DB, "SELECT * FROM classrooms WHERE teacher_id = ? ORDER BY rowid", me.id);
    const list = [];
    for (const r of rooms) list.push(out(r, await countEnrolled(c.env.DB, String(r.id))));
    return c.json(list);
  }
  if (me.role === "student") {
    const rooms = await q<Record<string, unknown>>(
      c.env.DB,
      "SELECT r.* FROM classrooms r JOIN classroom_enrollments e ON e.classroom_id = r.id WHERE e.student_id = ? ORDER BY r.rowid",
      me.id,
    );
    const list = [];
    for (const r of rooms) list.push(out(r, await countEnrolled(c.env.DB, String(r.id))));
    return c.json(list);
  }
  return err(c, 403, "Not allowed");
});

classroomRoutes.get("/:id", async (c) => {
  const me = await currentUser(c);
  if (!me) return err(c, 401, "Not authenticated");
  const room = await q1<Record<string, unknown>>(c.env.DB, "SELECT * FROM classrooms WHERE id = ?", P(c, "id"));
  if (!room) return err(c, 404, "Classroom not found");
  if (me.role === "teacher" && String(room.teacher_id) !== me.id) return err(c, 404, "Classroom not found");
  if (me.role === "student") {
    try {
      await enrolledClassroom(c, String(room.id), me.id);
    } catch {
      return err(c, 404, "Classroom not found");
    }
  }
  if (me.role === "parent") return err(c, 403, "Not allowed");
  const students = await q<Record<string, unknown>>(
    c.env.DB,
    "SELECT u.id, u.name FROM users u JOIN classroom_enrollments e ON e.student_id = u.id WHERE e.classroom_id = ? ORDER BY u.name",
    String(room.id),
  );
  const payload = out(room, students.length);
  if (me.role === "teacher") payload.students = students;
  return c.json(payload);
});

classroomRoutes.patch("/:id", requireRole("teacher"), async (c) => {
  const room = await teacherClassroom(c, P(c, "id")).catch(() => null);
  if (!room) return err(c, 404, "Classroom not found");
  const body = await c.req.json().catch(() => ({}));
  const sets: string[] = [];
  const params: unknown[] = [];
  for (const k of ["name", "subject", "grade_level"]) {
    if (body[k] !== undefined && body[k] !== null) {
      sets.push(`${k} = ?`);
      params.push(String(body[k]).trim());
    }
  }
  if (sets.length > 0) {
    params.push(nowIso(), String(room.id));
    await run(c.env.DB, `UPDATE classrooms SET ${sets.join(", ")}, updated_at = ? WHERE id = ?`, ...params);
  }
  const fresh = (await q1<Record<string, unknown>>(c.env.DB, "SELECT * FROM classrooms WHERE id = ?", String(room.id)))!;
  return c.json(out(fresh));
});

classroomRoutes.post("/join", requireRole("student"), async (c) => {
  const me = getUser(c);
  const body = await c.req.json().catch(() => ({}));
  const code = String(body.join_code || "").trim().toUpperCase();
  if (!code) return err(c, 422, "Join code is required");
  const room = await q1<Record<string, unknown>>(c.env.DB, "SELECT * FROM classrooms WHERE join_code = ?", code);
  if (!room) return err(c, 404, "Invalid join code");
  const already = !!(await q1(c.env.DB, "SELECT id FROM classroom_enrollments WHERE classroom_id = ? AND student_id = ?", String(room.id), me.id));
  if (!already) {
    await run(c.env.DB, "INSERT INTO classroom_enrollments (id, classroom_id, student_id, joined_at) VALUES (?,?,?,?)", uid(), String(room.id), me.id, nowIso());
  }
  return c.json({ classroom: out(room), already_enrolled: already });
});

classroomRoutes.get("/:id/students", requireRole("teacher"), async (c) => {
  const room = await teacherClassroom(c, P(c, "id")).catch(() => null);
  if (!room) return err(c, 404, "Classroom not found");
  const students = await q<Record<string, unknown>>(
    c.env.DB,
    "SELECT u.id, u.name FROM users u JOIN classroom_enrollments e ON e.student_id = u.id WHERE e.classroom_id = ? ORDER BY u.name",
    String(room.id),
  );
  return c.json(students);
});
