import type { Context } from "hono";
import type { Env } from "./env";
import { getUser, type User } from "./auth";
import { q1 } from "./db";
import { err } from "./util";
import { scopeForMaterial } from "./assess";

export async function teacherClassroom(c: Context<{ Bindings: Env }>, classroomId: string) {
  const me = getUser(c);
  const room = await q1<Record<string, unknown>>(c.env.DB, "SELECT * FROM classrooms WHERE id = ?", classroomId);
  if (!room || String(room.teacher_id) !== me.id) {
    throw Object.assign(new Error("Classroom not found"), { status: 404 });
  }
  return room;
}

export async function enrolledClassroom(c: Context<{ Bindings: Env }>, classroomId: string, studentId: string) {
  const e = await q1(c.env.DB, "SELECT id FROM classroom_enrollments WHERE classroom_id = ? AND student_id = ?", classroomId, studentId);
  if (!e) throw Object.assign(new Error("Not enrolled"), { status: 404 });
}

export async function linkedStudent(c: Context<{ Bindings: Env }>, studentId: string, parentId: string) {
  const u = await q1<Record<string, unknown>>(c.env.DB, "SELECT * FROM users WHERE id = ?", studentId);
  if (!u) throw Object.assign(new Error("Child not found"), { status: 404 });
  const link = await q1(c.env.DB, "SELECT id FROM parent_student_links WHERE parent_id = ? AND student_id = ?", parentId, studentId);
  if (!link) throw Object.assign(new Error("Child not found"), { status: 404 });
  return u;
}

export function canViewMaterial(user: User, mat: Record<string, unknown>, db: { isEnrolled: boolean; isLinked: boolean; roomTeacher?: string }): boolean {
  if (user.role === "teacher") {
    return mat.scope === "official" && !!mat.classroom_id && db.roomTeacher === user.id;
  }
  if (user.role === "student") {
    return (
      (mat.scope === "official" && !!mat.classroom_id && db.isEnrolled) ||
      (mat.scope === "supplementary" && mat.child_student_id === user.id)
    );
  }
  if (user.role === "parent") {
    return mat.scope === "supplementary" && !!mat.child_student_id && db.isLinked;
  }
  return false;
}

export async function visibleMaterial(c: Context<{ Bindings: Env }>, materialId: string, user: User) {
  const mat = await q1<Record<string, unknown>>(c.env.DB, "SELECT * FROM learning_materials WHERE id = ?", materialId);
  if (!mat) throw Object.assign(new Error("Material not found"), { status: 404 });
  const db = c.env.DB;
  let roomTeacher: string | undefined;
  let isEnrolled = false;
  let isLinked = false;
  if (mat.classroom_id) {
    const room = await q1<Record<string, unknown>>(db, "SELECT teacher_id FROM classrooms WHERE id = ?", String(mat.classroom_id));
    roomTeacher = room ? String(room.teacher_id) : undefined;
    if (user.role === "student") {
      isEnrolled = !!(await q1(db, "SELECT id FROM classroom_enrollments WHERE classroom_id = ? AND student_id = ?", String(mat.classroom_id), user.id));
    }
  }
  if (user.role === "parent" && mat.child_student_id) {
    isLinked = !!(await q1(db, "SELECT id FROM parent_student_links WHERE parent_id = ? AND student_id = ?", user.id, String(mat.child_student_id)));
  }
  if (!canViewMaterial(user, mat, { isEnrolled, isLinked, roomTeacher })) {
    throw Object.assign(new Error("Material not found"), { status: 404 });
  }
  return mat;
}

export async function ownedMaterial(c: Context<{ Bindings: Env }>, materialId: string, user: User) {
  const mat = await q1<Record<string, unknown>>(c.env.DB, "SELECT * FROM learning_materials WHERE id = ?", materialId);
  if (!mat || String(mat.uploader_id) !== user.id) {
    throw Object.assign(new Error("Material not found"), { status: 404 });
  }
  return mat;
}

export async function ownedBank(c: Context<{ Bindings: Env }>, bankId: string, teacher: User) {
  const bank = await q1<Record<string, unknown>>(c.env.DB, "SELECT * FROM question_banks WHERE id = ?", bankId);
  if (!bank) throw Object.assign(new Error("Question bank not found"), { status: 404 });
  const course = String(bank.course_id || "");
  const classroomId = String(bank.classroom_id || "") || (course.startsWith("class:") ? course.slice(6) : "");
  if (classroomId) await teacherClassroom(c, classroomId);
  if (course.startsWith("child:") || (bank.teacher_id && String(bank.teacher_id) !== teacher.id)) {
    throw Object.assign(new Error("Question bank not found"), { status: 404 });
  }
  return bank;
}

export function studentScope(
  mat: Record<string, unknown>,
  opts: { classroomId?: string; supplementary?: boolean },
): [string, string] {
  void opts;
  return scopeForMaterial(mat);
}

export function toErr(c: Context, e: unknown, fallbackStatus = 400) {
  const status = (e as { status?: number }).status || fallbackStatus;
  const msg = e instanceof Error ? e.message : "Request failed";
  return err(c, status, msg);
}
