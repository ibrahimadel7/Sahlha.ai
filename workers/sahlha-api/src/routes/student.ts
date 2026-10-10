import { Hono } from "hono";
import type { Env } from "../env";
import { currentUser, getUser, requireRole } from "../auth";
import { q, q1 } from "../db";
import { P, err, jparse } from "../util";
import { toErr } from "../guards";
import { checkRate } from "../ratelimit";
import {
  KNOWN_SIGNALS,
  applyOnboarding,
  checkAnswer,
  childProgress,
  classroomIdFromCourse,
  helpForSkill,
  learningPath,
  profileToDict,
  getProfile,
  recordSupportSignal,
  skillBundle,
  skillStatesForLesson,
  startAssessment,
  studentGrades,
  submitAssessment,
  summarizeMastery,
  scopeForMaterial,
} from "../assess";
import { envelopeForAudio, skillAudio, skillImage } from "../media";

async function resolveScope(env: Env, studentId: string, materialId: string, classroomId?: string): Promise<[string, string]> {
  const mat = await q1<Record<string, unknown>>(env.DB, "SELECT * FROM learning_materials WHERE id = ?", materialId);
  if (!mat) throw Object.assign(new Error("Material not found"), { status: 404 });
  if (mat.scope === "official") {
    if (!mat.classroom_id) throw Object.assign(new Error("Material not found"), { status: 404 });
    const en = await q1(env.DB, "SELECT id FROM classroom_enrollments WHERE classroom_id = ? AND student_id = ?", String(mat.classroom_id), studentId);
    if (!en) throw Object.assign(new Error("Material not found"), { status: 404 });
    if (classroomId && classroomId !== String(mat.classroom_id)) throw Object.assign(new Error("Material not found"), { status: 404 });
  } else if (String(mat.child_student_id) !== studentId) {
    throw Object.assign(new Error("Material not found"), { status: 404 });
  }
  return scopeForMaterial(mat);
}

export const studentRoutes = new Hono<{ Bindings: Env }>();

studentRoutes.get("/profile", requireRole("student"), async (c) => {
  const me = getUser(c);
  const prof = await getProfile(c.env, me.id);
  const payload = profileToDict(prof);
  payload.link_code = me.link_code;
  return c.json(payload);
});

studentRoutes.post("/profile", requireRole("student"), async (c) => {
  const me = getUser(c);
  const body = await c.req.json().catch(() => ({}));
  const prof = await applyOnboarding(c.env, me.id, (body.answers || {}) as Record<string, string>);
  return c.json(profileToDict(prof));
});

studentRoutes.post("/support-signal", requireRole("student"), async (c) => {
  const me = getUser(c);
  const body = await c.req.json().catch(() => ({}));
  const signal = String(body.signal || "").trim();
  if (!KNOWN_SIGNALS.has(signal)) return err(c, 422, `Unknown support signal: ${signal.slice(0, 64)}`);
  try {
    const prof = await recordSupportSignal(c.env, me.id, signal);
    return c.json(profileToDict(prof));
  } catch (e) {
    return toErr(c, e, 422);
  }
});

studentRoutes.get("/home", requireRole("student"), async (c) => {
  const me = getUser(c);
  const rooms = await q<Record<string, unknown>>(
    c.env.DB, "SELECT r.* FROM classrooms r JOIN classroom_enrollments e ON e.classroom_id = r.id WHERE e.student_id = ? ORDER BY r.rowid", me.id);
  const cards = [];
  for (const room of rooms) {
    const path = await learningPath(c.env, me.id, String(room.id));
    const grades = await studentGrades(c.env, me.id, String(room.id));
    cards.push({
      classroom_id: room.id, name: room.name, subject: room.subject, grade_level: room.grade_level,
      current: path.current, summary: path.summary, total_skills: path.total_skills, mastered: path.mastered,
      recent_score: grades.length > 0 ? grades[0].score : null,
      recent_practiced_at: grades.length > 0 ? grades[0].created_at : null,
    });
  }
  const supp = await learningPath(c.env, me.id, undefined, true);
  const prof = await getProfile(c.env, me.id);
  return c.json({
    classrooms: cards,
    supplementary: { current: supp.current, summary: supp.summary, total_skills: supp.total_skills },
    onboarding_completed: !!(prof && prof.onboarding_completed),
  });
});

studentRoutes.get("/learning-path", requireRole("student"), async (c) => {
  const me = getUser(c);
  const classroomId = c.req.query("classroom_id");
  const supplementary = c.req.query("supplementary") === "true";
  if (classroomId) {
    const en = await q1(c.env.DB, "SELECT id FROM classroom_enrollments WHERE classroom_id = ? AND student_id = ?", classroomId, me.id);
    if (!en) return err(c, 404, "Not enrolled");
    return c.json(await learningPath(c.env, me.id, classroomId));
  }
  if (supplementary) return c.json(await learningPath(c.env, me.id, undefined, true));
  const rooms = await q<Record<string, unknown>>(
    c.env.DB, "SELECT r.* FROM classrooms r JOIN classroom_enrollments e ON e.classroom_id = r.id WHERE e.student_id = ? ORDER BY r.rowid", me.id);
  const paths = [];
  for (const room of rooms) {
    paths.push({ classroom_id: room.id, name: room.name, subject: room.subject, ...(await learningPath(c.env, me.id, String(room.id))) });
  }
  paths.push({ classroom_id: null, name: "Extra practice", ...(await learningPath(c.env, me.id, undefined, true)) });
  return c.json({ paths });
});

studentRoutes.get("/skills/:skillId", requireRole("student"), async (c) => {
  const me = getUser(c);
  const materialId = c.req.query("material_id") || "";
  const classroomId = c.req.query("classroom_id") || undefined;
  const supplementary = c.req.query("supplementary") === "true";
  void supplementary;
  try {
    const [courseId, lessonId] = await resolveScope(c.env, me.id, materialId, classroomId);
    const bundle = await skillBundle(c.env, me.id, courseId, lessonId, P(c, "skillId"));
    if (classroomId) {
      const room = await q1<Record<string, unknown>>(c.env.DB, "SELECT subject FROM classrooms WHERE id = ?", classroomId);
      (bundle as Record<string, unknown>).subject = room ? String(room.subject) : "";
    }
    return c.json(bundle);
  } catch (e) {
    return toErr(c, e, 404);
  }
});

studentRoutes.get("/skills/:skillId/help", requireRole("student"), async (c) => {
  const me = getUser(c);
  const materialId = c.req.query("material_id") || "";
  const kind = c.req.query("kind") || "";
  const classroomId = c.req.query("classroom_id") || undefined;
  try {
    const [courseId, lessonId] = await resolveScope(c.env, me.id, materialId, classroomId);
    return c.json(await helpForSkill(c.env, me.id, courseId, lessonId, P(c, "skillId"), kind));
  } catch (e) {
    return toErr(c, e, 404);
  }
});

studentRoutes.post("/assessments/start", requireRole("student"), async (c) => {
  const me = getUser(c);
  const body = await c.req.json().catch(() => ({}));
  const materialId = body.material_id ? String(body.material_id) : null;
  const classroomId = body.classroom_id ? String(body.classroom_id) : null;
  const skillId = body.skill_id ? String(body.skill_id) : null;
  const childScope = !!body.child_scope;
  const checkpoint = !!body.checkpoint;
  try {
    if (checkpoint && (!materialId || skillId)) return err(c, 400, "Quick Checks require a material and mixed skills");
    let courseId: string | undefined;
    let lessonId: string | undefined;
    if (materialId) {
      const mat = await q1<Record<string, unknown>>(c.env.DB, "SELECT * FROM learning_materials WHERE id = ?", materialId);
      if (!mat) return err(c, 400, "Material not found");
      if (mat.scope === "official") {
        if (!classroomId || String(mat.classroom_id) !== classroomId) return err(c, 400, "Material does not belong to this classroom");
        const en = await q1(c.env.DB, "SELECT id FROM classroom_enrollments WHERE classroom_id = ? AND student_id = ?", classroomId, me.id);
        if (!en) return err(c, 404, "Not enrolled in this classroom");
      } else if (String(mat.child_student_id) !== me.id) {
        return err(c, 404, "Not allowed");
      }
      [courseId, lessonId] = scopeForMaterial(mat);
    } else if (classroomId) {
      const en = await q1(c.env.DB, "SELECT id FROM classroom_enrollments WHERE classroom_id = ? AND student_id = ?", classroomId, me.id);
      if (!en) return err(c, 404, "Not enrolled in this classroom");
      courseId = `class:${classroomId}`;
    } else if (childScope) {
      courseId = `child:${me.id}`;
    }
    if (!courseId) return err(c, 400, "Choose a classroom or material before starting practice");
    return c.json(await startAssessment(c.env, me.id, { courseId, lessonId, skillId: skillId || undefined, learnedOnly: checkpoint }));
  } catch (e) {
    const st = (e as { status?: number }).status;
    if (st === 403) return err(c, 404, e instanceof Error ? e.message : "Not allowed");
    return toErr(c, e);
  }
});

studentRoutes.post("/assessments/:id/check", requireRole("student"), async (c) => {
  const me = getUser(c);
  const rlCk = await checkRate(c.env, "check", me.id, 600, 3600);
  if (!rlCk.allowed) return err(c, 429, "Too many attempts. Try again shortly.");
  const body = await c.req.json().catch(() => ({}));
  try {
    return c.json(await checkAnswer(c.env, me.id, P(c, "id"), String(body.question_id || ""), body.answer ?? null));
  } catch (e) {
    const st = (e as { status?: number }).status || 404;
    return err(c, st, e instanceof Error ? e.message : "Check failed");
  }
});

studentRoutes.post("/assessments/:id/submit", requireRole("student"), async (c) => {
  const me = getUser(c);
  const rlSb = await checkRate(c.env, "submit", me.id, 120, 3600);
  if (!rlSb.allowed) return err(c, 429, "Too many attempts. Try again shortly.");
  const body = await c.req.json().catch(() => ({}));
  try {
    const out = await submitAssessment(c.env, me.id, P(c, "id"), (body.answers || {}) as Record<string, unknown>);
    const wrong = Number(out._wrong || 0);
    if (wrong >= 3) {
      try {
        await recordSupportSignal(c.env, me.id, "struggled");
      } catch { /* ignore */ }
    } else if (Number(out.score || 0) >= 0.8) {
      try {
        await recordSupportSignal(c.env, me.id, "improved");
      } catch { /* ignore */ }
    }
    for (const sig of ((body.support_signals as string[]) || [])) {
      if (KNOWN_SIGNALS.has(String(sig))) {
        try {
          await recordSupportSignal(c.env, me.id, String(sig));
        } catch { /* ignore */ }
      }
    }
    const states = out.mastery_states as Record<string, string>;
    const { _needReviewRaw, _wrong, ...rest } = out;
    void _needReviewRaw;
    void _wrong;
    return c.json({ ...rest, skills_needing_review: Object.keys(states).filter((k) => states[k] === "needs_practice") });
  } catch (e) {
    const st = (e as { status?: number }).status || 404;
    return err(c, st, e instanceof Error ? e.message : "Submit failed");
  }
});

studentRoutes.get("/grades", requireRole("student"), async (c) => {
  const me = getUser(c);
  const classroomId = c.req.query("classroom_id") || undefined;
  if (classroomId) {
    const en = await q1(c.env.DB, "SELECT id FROM classroom_enrollments WHERE classroom_id = ? AND student_id = ?", classroomId, me.id);
    if (!en) return err(c, 404, "Not enrolled");
  }
  return c.json(await studentGrades(c.env, me.id, classroomId));
});

studentRoutes.get("/progress", requireRole("student"), async (c) => {
  const me = getUser(c);
  const classroomId = c.req.query("classroom_id") || undefined;
  let rooms = await q<Record<string, unknown>>(
    c.env.DB, "SELECT r.* FROM classrooms r JOIN classroom_enrollments e ON e.classroom_id = r.id WHERE e.student_id = ? ORDER BY r.rowid", me.id);
  if (classroomId) {
    const en = await q1(c.env.DB, "SELECT id FROM classroom_enrollments WHERE classroom_id = ? AND student_id = ?", classroomId, me.id);
    if (!en) return err(c, 404, "Not enrolled");
    rooms = rooms.filter((r) => String(r.id) === classroomId);
  }
  const out = [];
  for (const room of rooms) {
    const units = [];
    const mats = await q<Record<string, unknown>>(c.env.DB, "SELECT * FROM learning_materials WHERE classroom_id = ? AND scope = 'official' ORDER BY rowid", String(room.id));
    for (const mat of mats) {
      const skills = await skillStatesForLesson(c.env, me.id, `class:${room.id}`, String(mat.id));
      units.push({ material_id: mat.id, title: mat.title, skills });
    }
    const grades = await studentGrades(c.env, me.id, String(room.id));
    const allStates = units.flatMap((u) => u.skills.map((s: { state: string }) => s.state));
    out.push({
      classroom_id: room.id, name: room.name, subject: room.subject,
      summary: summarizeMastery(allStates), units, grades: grades.slice(0, 10),
    });
  }
  return c.json({ classrooms: out });
});

studentRoutes.get("/skills/:skillId/audio", requireRole("student"), async (c) => {
  const me = getUser(c);
  const rlAu = await checkRate(c.env, "media", me.id, 200, 3600);
  if (!rlAu.allowed) return err(c, 429, "Too many attempts. Try again shortly.");
  try {
    const [courseId, lessonId] = await resolveScope(c.env, me.id, c.req.query("material_id") || "", c.req.query("classroom_id") || undefined);
    const res = await skillAudio(c.env, courseId, lessonId, P(c, "skillId"), c.req.query("voice") || undefined);
    return new Response(res.bytes.slice().buffer as ArrayBuffer, {
      headers: {
        "Content-Type": res.format === "mp3" ? "audio/mpeg" : "audio/wav",
        "X-Cache": res.cached ? "HIT" : "MISS",
        "X-Audio-Format": res.format,
        "Accept-Ranges": "bytes",
        "Cache-Control": "public, max-age=86400",
      },
    });
  } catch (e) {
    const st = (e as { status?: number }).status || 503;
    return err(c, st, st === 404 ? (e instanceof Error ? e.message : "Not found") : "Audio is unavailable right now.");
  }
});

studentRoutes.get("/skills/:skillId/audio-envelope", requireRole("student"), async (c) => {
  const me = getUser(c);
  try {
    const [courseId, lessonId] = await resolveScope(c.env, me.id, c.req.query("material_id") || "", c.req.query("classroom_id") || undefined);
    const res = await skillAudio(c.env, courseId, lessonId, P(c, "skillId"), c.req.query("voice") || undefined);
    return c.json(envelopeForAudio(res.bytes, res.format), 200, { "Cache-Control": "public, max-age=86400" });
  } catch (e) {
    const st = (e as { status?: number }).status || 503;
    return err(c, st, st === 404 ? (e instanceof Error ? e.message : "Not found") : "Audio is unavailable right now.");
  }
});

studentRoutes.get("/skills/:skillId/image", requireRole("student"), async (c) => {
  const me = getUser(c);
  const rlIm = await checkRate(c.env, "media", me.id, 200, 3600);
  if (!rlIm.allowed) return err(c, 429, "Too many attempts. Try again shortly.");
  try {
    const [courseId, lessonId] = await resolveScope(c.env, me.id, c.req.query("material_id") || "", c.req.query("classroom_id") || undefined);
    const res = await skillImage(c.env, courseId, lessonId, P(c, "skillId"));
    return new Response(res.bytes.slice().buffer as ArrayBuffer, { headers: { "Content-Type": "image/jpeg", "Cache-Control": "public, max-age=86400" } });
  } catch (e) {
    const st = (e as { status?: number }).status || 503;
    return err(c, st, st === 404 ? (e instanceof Error ? e.message : "Not found") : "No picture is available right now.");
  }
});

studentRoutes.get("/materials/:id/study", requireRole("student"), async (c) => {
  const me = getUser(c);
  try {
    const [courseId, lessonId] = await resolveScope(c.env, me.id, P(c, "id"), c.req.query("classroom_id") || undefined);
    const lesson = await q1<Record<string, unknown>>(c.env.DB, "SELECT * FROM lesson_explanations WHERE course_id = ? AND lesson_id = ?", courseId, lessonId);
    const { approvedPool } = await import("../assess");
    const { pool } = await approvedPool(c.env, courseId, lessonId);
    const bySkill = new Map<string, number>();
    for (const p of pool) bySkill.set(p.skill_id, (bySkill.get(p.skill_id) || 0) + 1);
    const skills = await skillStatesForLesson(c.env, me.id, courseId, lessonId);
    return c.json({
      lesson: lesson ? { title: lesson.title, explanation: lesson.explanation, key_concepts: jparse(lesson.key_concepts, []) } : null,
      skills: skills.map((s) => ({ ...s, exercise_ready: (bySkill.get(s.skill_id) || 0) >= 4, approved_questions: bySkill.get(s.skill_id) || 0 })),
    });
  } catch (e) {
    return toErr(c, e, 404);
  }
});

export { classroomIdFromCourse };
export { currentUser };
