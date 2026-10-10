import { Hono } from "hono";
import type { Env } from "../env";
import { currentUser, getUser, requireRole, type User } from "../auth";
import { q, q1, run } from "../db";
import { P, err, jparse, jstr, nowIso, uid } from "../util";
import { ownedMaterial, toErr, visibleMaterial } from "../guards";
import { checkRate } from "../ratelimit";
import { explainLesson, explainSkills, extractSkills, generateLessonBanks, listSkills } from "../agent";
import { approvedPool } from "../assess";
import { ingestUpload, validateUpload } from "../ingest";
import { scopeForMaterial } from "../assess";

export async function materialDict(env: Env, mat: Record<string, unknown>) {
  const [courseId, lessonId] = scopeForMaterial(mat);
  const skills = await q<{ n: number }>(env.DB, "SELECT COUNT(*) AS n FROM skills WHERE course_id = ? AND lesson_id = ?", courseId, lessonId);
  const banks = await q<Record<string, unknown>>(env.DB, "SELECT status FROM question_banks WHERE course_id = ? AND lesson_id = ?", courseId, lessonId);
  return {
    id: mat.id, title: mat.title, filename: mat.original_filename, scope: mat.scope, source_type: mat.source_type,
    classroom_id: mat.classroom_id || null, child_student_id: mat.child_student_id || null,
    status: mat.processing_status, status_detail: mat.status_detail || "",
    quality_signals: jparse(mat.quality_signals, {}), document_id: mat.document_id || null,
    num_skills: Number(skills[0]?.n || 0), num_banks: banks.length,
    approved_banks: banks.filter((b) => b.status === "approved").length,
    created_at: mat.created_at || null,
  };
}

export async function skillDict(env: Env, courseId: string, lessonId: string, row: Record<string, unknown>) {
  const banks = await q<Record<string, unknown>>(env.DB, "SELECT * FROM question_banks WHERE course_id = ? AND lesson_id = ? AND skill_id = ?", courseId, lessonId, String(row.skill_id));
  const approved = banks.filter((b) => b.status === "approved");
  const pending = banks.filter((b) => b.status === "pending_review");
  // latest approved count
  let latestCount = 0;
  let latestIds: string[] = [];
  if (approved.length > 0) {
    const maxV = Math.max(...approved.map((b) => Number(b.version || 0)));
    const latest = approved.filter((b) => Number(b.version) === maxV);
    latestIds = latest.map((b) => String(b.id));
    const { pool } = await approvedPool(env, courseId, lessonId, String(row.skill_id));
    latestCount = pool.filter((p) => latestIds.includes(p.bank_id)).length;
  }
  const hasImage = (await env.MEDIA.get(`img:${courseId}:${lessonId}:${row.skill_id}`)) !== null;
  const hasAudio = (await env.MEDIA.get(`aud:${courseId}:${lessonId}:${row.skill_id}:default`)) !== null;
  return {
    id: row.id, course_id: row.course_id, lesson_id: row.lesson_id, skill_id: row.skill_id,
    name: row.name, description: row.description, explanation: row.explanation || "",
    key_concepts: jparse(row.key_concepts, []), has_image: hasImage, image_alt: String(row.image_alt || ""),
    has_audio: hasAudio, approved_questions: latestCount, active_bank_ids: latestIds.sort(),
    bank_status: approved.length > 0 ? "approved" : pending.length > 0 ? "pending" : banks.length > 0 ? "rejected" : "none",
  };
}

export const materialRoutes = new Hono<{ Bindings: Env }>();

materialRoutes.post("/upload", async (c) => {
  const me = await currentUser(c);
  if (!me) return err(c, 401, "Not authenticated");
  if (me.role !== "teacher" && me.role !== "parent") return err(c, 403, "Only teachers and parents can upload materials");
  const rlUp = await checkRate(c.env, "upload", me.id, 20, 3600);
  if (!rlUp.allowed) return err(c, 429, "Upload limit reached. Try again later.");
  let form: FormData;
  try {
    form = await c.req.formData();
  } catch {
    return err(c, 422, "Upload a file first.");
  }
  const file = form.get("file");
  const title = String(form.get("title") || "");
  const classroomId = form.get("classroom_id") ? String(form.get("classroom_id")) : null;
  const childStudentId = form.get("child_student_id") ? String(form.get("child_student_id")) : null;
  if (!(file instanceof File)) return err(c, 422, "Upload a file first.");
  const bytes = new Uint8Array(await file.arrayBuffer());
  try {
    validateUpload(file.name || "upload", bytes.length);
  } catch (e) {
    return toErr(c, e, 422);
  }
  // create record (role checks mirror create_material_record)
  try {
    if (me.role === "teacher") {
      if (!classroomId) throw Object.assign(new Error("classroom_id is required for teacher uploads"), { status: 404 });
      const room = await q1<Record<string, unknown>>(c.env.DB, "SELECT * FROM classrooms WHERE id = ?", classroomId);
      if (!room || String(room.teacher_id) !== me.id) throw Object.assign(new Error("Classroom not found"), { status: 404 });
    } else {
      if (!childStudentId) throw Object.assign(new Error("child_student_id is required for parent uploads"), { status: 404 });
      const link = await q1(c.env.DB, "SELECT id FROM parent_student_links WHERE parent_id = ? AND student_id = ?", me.id, childStudentId);
      if (!link) throw Object.assign(new Error("Child not found"), { status: 404 });
    }
  } catch (e) {
    return toErr(c, e);
  }
  const id = uid();
  const now = nowIso();
  await run(
    c.env.DB,
    `INSERT INTO learning_materials (id, uploader_id, source_type, classroom_id, child_student_id, title, original_filename, scope, processing_status, status_detail, quality_signals, created_at, updated_at)
     VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)`,
    id, me.id, me.role, classroomId, childStudentId, title || file.name || "upload", file.name || "upload",
    me.role === "teacher" ? "official" : "supplementary", "processing", "", "{}", now, now,
  );
  const fail = async (msg: string) => {
    await run(c.env.DB, "UPDATE learning_materials SET processing_status = 'failed', status_detail = ?, updated_at = ? WHERE id = ?", msg, nowIso(), id);
    const mat = (await q1<Record<string, unknown>>(c.env.DB, "SELECT * FROM learning_materials WHERE id = ?", id))!;
    return c.json({ material: await materialDict(c.env, mat), error: msg });
  };
  try {
    const scopeCourse = me.role === "teacher" ? `class:${classroomId}` : `child:${childStudentId}`;
    const res = await ingestUpload(c.env, bytes, file.name || "upload", scopeCourse, id);
    // lesson_id for the AI loop is always the material id: re-scope chunks
    await run(c.env.DB, "UPDATE documents SET lesson_id = ? WHERE id = ?", id, res.document_id);
    await run(c.env.DB, "UPDATE document_chunks SET lesson_id = ? WHERE document_id = ?", id, res.document_id);
    await run(c.env.DB, "UPDATE learning_materials SET document_id = ?, title = ?, processing_status = 'processed', updated_at = ? WHERE id = ?",
      res.document_id,
      !title || title === file.name || ["lesson", "upload", "document", "untitled"].includes(title.toLowerCase()) ? res.title : title,
      nowIso(), id);
    const mat = (await q1<Record<string, unknown>>(c.env.DB, "SELECT * FROM learning_materials WHERE id = ?", id))!;
    return c.json({ material: await materialDict(c.env, mat), document_id: res.document_id, chunk_count: res.chunk_count }, 201);
  } catch (e) {
    const msg = e instanceof Error ? e.message : "Could not read this file";
    const full = msg.startsWith("Could not") || msg.startsWith("This scan") || msg.startsWith("No readable") || msg.startsWith("Empty") || msg.startsWith("Files of type") || msg.startsWith("Unsupported") || msg.startsWith("File is") || msg.startsWith("The file")
      ? msg
      : `Could not read this file: ${msg}`;
    return fail(full);
  }
});

materialRoutes.get("", async (c) => {
  const me = await currentUser(c);
  if (!me) return err(c, 401, "Not authenticated");
  const classroomId = c.req.query("classroom_id");
  const childStudentId = c.req.query("child_student_id");
  let mats: Record<string, unknown>[] = [];
  if (me.role === "teacher") {
    if (classroomId) {
      const room = await q1<Record<string, unknown>>(c.env.DB, "SELECT * FROM classrooms WHERE id = ?", classroomId);
      if (room && String(room.teacher_id) === me.id) {
        mats = await q<Record<string, unknown>>(c.env.DB, "SELECT * FROM learning_materials WHERE classroom_id = ? AND scope = 'official' ORDER BY rowid", classroomId);
      }
    } else {
      const rooms = await q<Record<string, unknown>>(c.env.DB, "SELECT id FROM classrooms WHERE teacher_id = ?", me.id);
      for (const r of rooms) {
        mats.push(...(await q<Record<string, unknown>>(c.env.DB, "SELECT * FROM learning_materials WHERE classroom_id = ? AND scope = 'official' ORDER BY rowid", String(r.id))));
      }
    }
  } else if (me.role === "student") {
    if (classroomId) {
      const en = await q1(c.env.DB, "SELECT id FROM classroom_enrollments WHERE classroom_id = ? AND student_id = ?", classroomId, me.id);
      if (en) mats = await q<Record<string, unknown>>(c.env.DB, "SELECT * FROM learning_materials WHERE classroom_id = ? AND scope = 'official' ORDER BY rowid", classroomId);
    } else {
      const rooms = await q<Record<string, unknown>>(
        c.env.DB, "SELECT r.id FROM classrooms r JOIN classroom_enrollments e ON e.classroom_id = r.id WHERE e.student_id = ?", me.id);
      for (const r of rooms) {
        mats.push(...(await q<Record<string, unknown>>(c.env.DB, "SELECT * FROM learning_materials WHERE classroom_id = ? AND scope = 'official' ORDER BY rowid", String(r.id))));
      }
    }
    mats.push(...(await q<Record<string, unknown>>(c.env.DB, "SELECT * FROM learning_materials WHERE child_student_id = ? AND scope = 'supplementary' ORDER BY rowid", me.id)));
  } else if (me.role === "parent") {
    const kids = childStudentId
      ? [{ id: childStudentId }]
      : await q<Record<string, unknown>>(c.env.DB, "SELECT student_id AS id FROM parent_student_links WHERE parent_id = ?", me.id);
    for (const k of kids) {
      const link = await q1(c.env.DB, "SELECT id FROM parent_student_links WHERE parent_id = ? AND student_id = ?", me.id, String(k.id));
      if (!link) continue;
      mats.push(...(await q<Record<string, unknown>>(c.env.DB, "SELECT * FROM learning_materials WHERE child_student_id = ? AND scope = 'supplementary' ORDER BY rowid", String(k.id))));
    }
  }
  const out = [];
  for (const m of mats) out.push(await materialDict(c.env, m));
  return c.json(out);
});

materialRoutes.get("/:id", async (c) => {
  const me = await currentUser(c);
  if (!me) return err(c, 401, "Not authenticated");
  try {
    const mat = await visibleMaterial(c, P(c, "id"), me);
    return c.json(await materialDict(c.env, mat));
  } catch (e) {
    return toErr(c, e, 404);
  }
});

materialRoutes.post("/:id/extract-skills", async (c) => {
  const me = await currentUser(c);
  if (!me) return err(c, 401, "Not authenticated");
  try {
    const mat = await ownedMaterial(c, P(c, "id"), me);
    if (!["processed", "skills_ready", "banks_ready"].includes(String(mat.processing_status))) {
      return err(c, 400, "Material processing must finish before extracting skills");
    }
    const force = c.req.query("force") === "true";
    const rlEx = await checkRate(c.env, "ai", `${me.id}:extract`, 30, 3600);
    if (!rlEx.allowed) return err(c, 429, "AI generation limit reached. Try again later.");
    const [courseId, lessonId] = scopeForMaterial(mat);
    const out = await extractSkills(c.env, courseId, lessonId, 6, force);
    // Bundled like the Python service: skills ship with explanations + lesson overview.
    await explainSkills(c.env, courseId, lessonId, force);
    await explainLesson(c.env, courseId, lessonId, force);
    await run(c.env.DB, "UPDATE learning_materials SET processing_status = 'skills_ready', status_detail = ?, updated_at = ? WHERE id = ?",
      `${out.skills.length} skills`, nowIso(), String(mat.id));
    return c.json(out);
  } catch (e) {
    return toErr(c, e);
  }
});

materialRoutes.get("/:id/skills", async (c) => {
  const me = await currentUser(c);
  if (!me) return err(c, 401, "Not authenticated");
  try {
    const mat = await visibleMaterial(c, P(c, "id"), me);
    const [courseId, lessonId] = scopeForMaterial(mat);
    const skills = await listSkills(c.env, courseId, lessonId);
    const out = [];
    for (const s of skills) out.push(await skillDict(c.env, courseId, lessonId, s as unknown as Record<string, unknown>));
    return c.json(out);
  } catch (e) {
    return toErr(c, e, 404);
  }
});

materialRoutes.post("/:id/skills", async (c) => {
  const me = await currentUser(c);
  if (!me) return err(c, 401, "Not authenticated");
  try {
    const mat = await ownedMaterial(c, P(c, "id"), me);
    const [courseId, lessonId] = scopeForMaterial(mat);
    const body = await c.req.json().catch(() => ({}));
    const skid = String(body.skill_id || "");
    if (!skid || skid.length > 128) return err(c, 422, "skill_id is required");
    const now = nowIso();
    await run(
      c.env.DB,
      `INSERT INTO skills (id, course_id, lesson_id, skill_id, name, description, key_concepts, created_at, updated_at)
       VALUES (?,?,?,?,?,?,?, ?,?) ON CONFLICT (course_id, lesson_id, skill_id) DO UPDATE SET name=excluded.name, description=excluded.description, key_concepts=excluded.key_concepts, updated_at=excluded.updated_at`,
      uid(), courseId, lessonId, skid, String(body.name || skid), String(body.description || ""),
      jstr(body.key_concepts || []), now, now,
    );
    const row = (await q1<Record<string, unknown>>(c.env.DB, "SELECT * FROM skills WHERE course_id = ? AND lesson_id = ? AND skill_id = ?", courseId, lessonId, skid))!;
    return c.json(await skillDict(c.env, courseId, lessonId, row));
  } catch (e) {
    return toErr(c, e, 404);
  }
});

materialRoutes.patch("/:id/skills/:skillId", async (c) => {
  const me = await currentUser(c);
  if (!me) return err(c, 401, "Not authenticated");
  try {
    const mat = await ownedMaterial(c, P(c, "id"), me);
    const [courseId, lessonId] = scopeForMaterial(mat);
    const row = await q1<Record<string, unknown>>(c.env.DB, "SELECT * FROM skills WHERE course_id = ? AND lesson_id = ? AND skill_id = ?", courseId, lessonId, P(c, "skillId"));
    if (!row) return err(c, 404, "Skill not found");
    const body = await c.req.json().catch(() => ({}));
    const sets: string[] = [];
    const params: unknown[] = [];
    const before = { name: String(row.name || ""), explanation: String(row.explanation || "") };
    for (const k of ["name", "description", "explanation"]) {
      if (body[k] !== undefined && body[k] !== null) {
        sets.push(`${k} = ?`);
        params.push(k === "key_concepts" ? jstr(body[k]) : String(body[k]));
      }
    }
    if (body.key_concepts !== undefined && body.key_concepts !== null) {
      sets.push("key_concepts = ?");
      params.push(jstr(body.key_concepts));
    }
    const after = {
      name: body.name !== undefined && body.name !== null ? String(body.name) : before.name,
      explanation: body.explanation !== undefined && body.explanation !== null ? String(body.explanation) : before.explanation,
    };
    if ((after.name !== before.name || after.explanation !== before.explanation)) {
      // stale audio for changed narration
      await c.env.MEDIA.delete(`aud:${courseId}:${lessonId}:${row.skill_id}:default`).catch(() => null);
    }
    if (sets.length > 0) {
      params.push(nowIso(), String(row.id));
      await run(c.env.DB, `UPDATE skills SET ${sets.join(", ")}, updated_at = ? WHERE id = ?`, ...params);
    }
    const fresh = (await q1<Record<string, unknown>>(c.env.DB, "SELECT * FROM skills WHERE id = ?", String(row.id)))!;
    return c.json({
      id: fresh.id, skill_id: fresh.skill_id, name: fresh.name, description: fresh.description,
      key_concepts: jparse(fresh.key_concepts, []), explanation: fresh.explanation,
    });
  } catch (e) {
    return toErr(c, e, 404);
  }
});

materialRoutes.delete("/:id/skills/:skillId", async (c) => {
  const me = await currentUser(c);
  if (!me) return err(c, 401, "Not authenticated");
  try {
    const mat = await ownedMaterial(c, P(c, "id"), me);
    const [courseId, lessonId] = scopeForMaterial(mat);
    const row = await q1<Record<string, unknown>>(c.env.DB, "SELECT * FROM skills WHERE course_id = ? AND lesson_id = ? AND skill_id = ?", courseId, lessonId, P(c, "skillId"));
    if (!row) return err(c, 404, "Skill not found");
    await run(c.env.DB, "DELETE FROM skills WHERE id = ?", String(row.id));
    return new Response(null, { status: 204 });
  } catch (e) {
    return toErr(c, e, 404);
  }
});

materialRoutes.post("/:id/generate-banks", requireRole("teacher"), async (c) => {
  const me = getUser(c);
  try {
    const mat = await ownedMaterial(c, P(c, "id"), me);
    if (String(mat.scope) !== "official") return err(c, 403, "Only official classroom materials have reviewable banks");
    if (!["processed", "skills_ready", "banks_ready"].includes(String(mat.processing_status))) {
      return err(c, 400, "Material processing must finish before generating questions");
    }
    const body = await c.req.json().catch(() => ({}));
    const rlGen = await checkRate(c.env, "ai", `${me.id}:banks`, 20, 3600);
    if (!rlGen.allowed) return err(c, 429, "AI generation limit reached. Try again later.");
    const [courseId, lessonId] = scopeForMaterial(mat);
    const out = await generateLessonBanks(c.env, courseId, lessonId, String(body.teacher_feedback || ""), Number(body.n_questions || 10), {
      teacher_id: me.id, classroom_id: String(mat.classroom_id || ""), material_id: String(mat.id),
    });
    const banks = out.banks as Array<Record<string, unknown>>;
    const generated = banks.reduce((a, b) => a + Number(b.num_questions || 0), 0);
    let detail = `Created ${generated} questions for review.`;
    await run(c.env.DB, "UPDATE learning_materials SET processing_status = 'banks_ready', status_detail = ?, updated_at = ? WHERE id = ?", detail, nowIso(), String(mat.id));
    return c.json(out);
  } catch (e) {
    return toErr(c, e);
  }
});

materialRoutes.get("/:id/banks", async (c) => {
  const me = await currentUser(c);
  if (!me) return err(c, 401, "Not authenticated");
  try {
    const mat = await visibleMaterial(c, P(c, "id"), me);
    const [, lessonId] = scopeForMaterial(mat);
    const banks = await q<Record<string, unknown>>(c.env.DB, "SELECT * FROM question_banks WHERE lesson_id = ? ORDER BY rowid", lessonId);
    if (me.role === "student" || me.role === "parent") {
      const out = [];
      for (const b of banks) {
        const nq = await q1<{ n: number }>(c.env.DB, "SELECT COUNT(*) AS n FROM questions WHERE question_bank_id = ?", String(b.id));
        out.push({ skill_id: b.skill_id, version: b.version, status: b.status, num_questions: Number(nq?.n || 0) });
      }
      return c.json(out);
    }
    const out = [];
    for (const b of banks) {
      const nq = await q1<{ n: number }>(c.env.DB, "SELECT COUNT(*) AS n FROM questions WHERE question_bank_id = ?", String(b.id));
      out.push({
        id: b.id, skill_id: b.skill_id, version: b.version, status: b.status,
        feedback: b.teacher_feedback, num_questions: Number(nq?.n || 0),
      });
    }
    return c.json(out);
  } catch (e) {
    return toErr(c, e, 404);
  }
});

export { scopeForMaterial };
export type { User };
