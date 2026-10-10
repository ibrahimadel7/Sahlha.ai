import { Hono } from "hono";
import type { Env } from "../env";
import { getUser, requireRole } from "../auth";
import { q, q1, run } from "../db";
import { P, err, jparse, jstr, nowIso, uid } from "../util";
import { ownedBank, teacherClassroom, toErr } from "../guards";
import { checkRate } from "../ratelimit";
import { classroomMastery, studentGrades, teacherOverview } from "../assess";
import { generateQuestionBank, generateLessonBanks } from "../agent";
import { QUESTION_SYSTEM, fallbackCritique, fallbackQuestions, generateQuestionsLlm } from "../llm";
import { attachQuestionEvidence, retrieveLesson, searchChunks, validateQuestionGrounding } from "../rag";
import type { Chunk } from "../llm";

function teacherQ(qr: Record<string, unknown>) {
  return {
    id: qr.id, skill_id: qr.skill_id, type: qr.question_type || "multiple_choice",
    question: qr.question_text, options: jparse(qr.options, []),
    correct_answer: jparse(qr.correct_answer, 0), explanation: qr.explanation || "",
    difficulty: qr.difficulty || "medium",
  };
}

async function bankTeacherDict(env: Env, bank: Record<string, unknown>) {
  const qs = await q<Record<string, unknown>>(env.DB, "SELECT * FROM questions WHERE question_bank_id = ? ORDER BY rowid", String(bank.id));
  return {
    id: bank.id, course_id: bank.course_id, lesson_id: bank.lesson_id, skill_id: bank.skill_id,
    version: bank.version, status: bank.status, feedback: bank.teacher_feedback || "",
    classroom_id: bank.classroom_id || null, material_id: bank.material_id || null, teacher_id: bank.teacher_id || null,
    questions: qs.map(teacherQ),
  };
}

export const teacherRoutes = new Hono<{ Bindings: Env }>();

teacherRoutes.get("/overview", requireRole("teacher"), async (c) => {
  return c.json(await teacherOverview(c.env, getUser(c).id));
});

teacherRoutes.get("/banks", requireRole("teacher"), async (c) => {
  const me = getUser(c);
  const status = c.req.query("status") || undefined;
  const classroomId = c.req.query("classroom_id") || undefined;
  const materialId = c.req.query("material_id") || undefined;
  if (classroomId) {
    const ok = await teacherClassroom(c, classroomId).catch(() => null);
    if (!ok) return err(c, 404, "Classroom not found");
  }
  const conds: string[] = [];
  const params: unknown[] = [];
  if (!classroomId && !materialId) {
    conds.push("((teacher_id = ?) OR (teacher_id IS NULL AND course_id NOT LIKE 'class:%' AND course_id NOT LIKE 'child:%'))");
    params.push(me.id);
  } else {
    conds.push("(teacher_id = ? OR teacher_id IS NULL)");
    params.push(me.id);
  }
  if (status) {
    conds.push("status = ?");
    params.push(status);
  }
  if (classroomId) {
    conds.push("classroom_id = ?");
    params.push(classroomId);
  }
  if (materialId) {
    conds.push("material_id = ?");
    params.push(materialId);
  }
  const banks = await q<Record<string, unknown>>(c.env.DB, `SELECT * FROM question_banks WHERE ${conds.join(" AND ")} ORDER BY rowid`, ...params);
  const out = [];
  for (const b of banks) {
    const nq = await q1<{ n: number }>(c.env.DB, "SELECT COUNT(*) AS n FROM questions WHERE question_bank_id = ?", String(b.id));
    out.push({
      id: b.id, course_id: b.course_id, lesson_id: b.lesson_id, skill_id: b.skill_id, version: b.version,
      status: b.status, feedback: b.teacher_feedback || "", classroom_id: b.classroom_id || null,
      material_id: b.material_id || null, num_questions: Number(nq?.n || 0),
    });
  }
  return c.json(out);
});

teacherRoutes.get("/banks/:id", requireRole("teacher"), async (c) => {
  const bank = await ownedBank(c, P(c, "id"), getUser(c)).catch(() => null);
  if (!bank) return err(c, 404, "Question bank not found");
  return c.json(await bankTeacherDict(c.env, bank));
});

teacherRoutes.post("/banks/:id/approve", requireRole("teacher"), async (c) => {
  const bank = await ownedBank(c, P(c, "id"), getUser(c)).catch(() => null);
  if (!bank) return err(c, 404, "Question bank not found");
  await run(c.env.DB, "UPDATE question_banks SET status = 'approved', updated_at = ? WHERE id = ?", nowIso(), String(bank.id));
  const fresh = (await q1<Record<string, unknown>>(c.env.DB, "SELECT * FROM question_banks WHERE id = ?", String(bank.id)))!;
  return c.json(await bankTeacherDict(c.env, fresh));
});

teacherRoutes.post("/banks/:id/reject", requireRole("teacher"), async (c) => {
  const bank = await ownedBank(c, P(c, "id"), getUser(c)).catch(() => null);
  if (!bank) return err(c, 404, "Question bank not found");
  const feedback = c.req.query("feedback") || "";
  await run(c.env.DB, "UPDATE question_banks SET status = 'rejected', teacher_feedback = ?, updated_at = ? WHERE id = ?", feedback, nowIso(), String(bank.id));
  const fresh = (await q1<Record<string, unknown>>(c.env.DB, "SELECT * FROM question_banks WHERE id = ?", String(bank.id)))!;
  return c.json(await bankTeacherDict(c.env, fresh));
});

teacherRoutes.patch("/banks/:bankId/questions/:qid", requireRole("teacher"), async (c) => {
  const bank = await ownedBank(c, P(c, "bankId"), getUser(c)).catch(() => null);
  if (!bank) return err(c, 404, "Question bank not found");
  if (String(bank.status) === "approved") {
    return err(c, 404, "Approved bank history is preserved. Regenerate a new bank version before editing questions.");
  }
  const qr = await q1<Record<string, unknown>>(c.env.DB, "SELECT * FROM questions WHERE id = ?", P(c, "qid"));
  if (!qr || String(qr.question_bank_id) !== String(bank.id)) return err(c, 404, "Question not found");
  const body = await c.req.json().catch(() => ({}));
  const sets: string[] = [];
  const params: unknown[] = [];
  const map: Record<string, string> = {
    question_text: "question_text", options: "options", correct_answer: "correct_answer",
    explanation: "explanation", difficulty: "difficulty", question_type: "question_type",
  };
  for (const [bk, col] of Object.entries(map)) {
    if (body[bk] !== undefined && body[bk] !== null) {
      sets.push(`${col} = ?`);
      params.push(col === "options" || col === "correct_answer" ? jstr(body[bk]) : String(body[bk]));
    }
  }
  if (sets.length > 0) {
    params.push(String(qr.id));
    await run(c.env.DB, `UPDATE questions SET ${sets.join(", ")} WHERE id = ?`, ...params);
  }
  const fresh = (await q1<Record<string, unknown>>(c.env.DB, "SELECT * FROM questions WHERE id = ?", String(qr.id)))!;
  return c.json(teacherQ(fresh));
});

teacherRoutes.delete("/banks/:bankId/questions/:qid", requireRole("teacher"), async (c) => {
  const bank = await ownedBank(c, P(c, "bankId"), getUser(c)).catch(() => null);
  if (!bank) return err(c, 404, "Question bank not found");
  if (String(bank.status) === "approved") {
    return err(c, 404, "Approved bank history is preserved. Regenerate a new bank version before editing questions.");
  }
  const qr = await q1<Record<string, unknown>>(c.env.DB, "SELECT * FROM questions WHERE id = ?", P(c, "qid"));
  if (!qr || String(qr.question_bank_id) !== String(bank.id)) return err(c, 404, "Question not found");
  await run(c.env.DB, "DELETE FROM questions WHERE id = ?", String(qr.id));
  const nq = await q1<{ n: number }>(c.env.DB, "SELECT COUNT(*) AS n FROM questions WHERE question_bank_id = ?", String(bank.id));
  return c.json({ removed: String(qr.id), remaining: Number(nq?.n || 0) });
});

teacherRoutes.post("/banks/:bankId/questions/:qid/regenerate", requireRole("teacher"), async (c) => {
  const bank = await ownedBank(c, P(c, "bankId"), getUser(c)).catch(() => null);
  if (!bank) return err(c, 404, "Question bank not found");
  if (String(bank.status) === "approved") {
    return err(c, 404, "Approved bank history is preserved. Regenerate a new bank version before editing questions.");
  }
  const qr = await q1<Record<string, unknown>>(c.env.DB, "SELECT * FROM questions WHERE id = ?", P(c, "qid"));
  if (!qr || String(qr.question_bank_id) !== String(bank.id)) return err(c, 404, "Question not found");
  const rlRg = await checkRate(c.env, "ai", `${getUser(c).id}:regen`, 30, 3600);
  if (!rlRg.allowed) return err(c, 429, "AI generation limit reached. Try again later.");
  try {
    const courseId = String(bank.course_id);
    const lessonId = String(bank.lesson_id);
    const skid = String(bank.skill_id);
    const body = await c.req.json().catch(() => ({}));
    let feedback = String(body.feedback || "");
    const sk = await q1<Record<string, unknown>>(c.env.DB, "SELECT * FROM skills WHERE course_id = ? AND lesson_id = ? AND skill_id = ?", courseId, lessonId, skid);
    const objective = (sk && String(sk.learning_objective || "")) || `Explain ${skid.replace(/_/g, " ")}.`;
    let chunks = await searchChunks(c.env, `${skid} ${objective} ${sk ? String(sk.name || "") : ""}`, 8, courseId, lessonId, skid);
    if (chunks.length === 0) chunks = await searchChunks(c.env, `${skid} ${objective}`, 8, courseId, lessonId);
    if (chunks.length === 0) {
      return err(c, 404, "No source evidence is available within this skill scope. Re-extract skills or upload more detailed lesson content.");
    }
    for (const ch of chunks) {
      if (ch.course_id !== courseId || ch.lesson_id !== lessonId) {
        return err(c, 404, "Evidence scope violation during regeneration.");
      }
    }
    const flagRows = await q<Record<string, unknown>>(
      c.env.DB,
      `SELECT f.reason FROM question_feedback f JOIN questions q ON q.id = f.question_id WHERE q.question_bank_id = ? AND f.kind = 'flag'`,
      String(bank.id),
    );
    const reasons = flagRows.map((r) => String(r.reason || "")).filter(Boolean);
    if (reasons.length > 0) feedback += "\nPrevious teacher feedback to avoid:\n" + reasons.join("\n");
    const concepts = sk ? jparse<string[]>(sk.key_concepts, []) : [];
    const ctx = chunks.map((ch, i) => `[chunk ${ch.chunk_id || i}] ${ch.text || ""}`).join("\n\n").slice(0, 4000) || "(no context retrieved)";
    const user = `Course: ${courseId}\nLesson: ${lessonId}\nSkill: ${skid}\nTeacher feedback (may be empty): ${(feedback || "Generate a different question on the same skill.").slice(0, 800)}\n\n--- RETRIEVED LESSON CONTEXT ---\n${ctx}\n--- END CONTEXT ---\n\nFirst state the central educational topic in one line (as a JSON comment is NOT allowed, just use it internally), then generate UP TO 3 GOOD questions as a JSON array. Focus ONLY on the requested skill and instructional content; ignore incidental metadata (teacher/author/school names, dates, page numbers, references, formatting). If the material supports fewer than 3 meaningful questions, return fewer — never pad with trivia.`;
    const { questions: drafts, backend } = await generateQuestionsLlm(c.env, QUESTION_SYSTEM, user, chunks as Chunk[], skid, 3, feedback || "different question");
    for (const d of drafts) d.skill_id = skid;
    const verdicts = fallbackCritique(drafts, chunks as Chunk[]);
    const bad = new Set(verdicts.filter((v) => !(v.grounded && v.answer_correct && v.relevant)).map((v) => v.index));
    let kept = drafts.filter((_, i) => !bad.has(i));
    if (kept.length < 3) {
      const top = fallbackQuestions(chunks as Chunk[], skid, 3 - kept.length, feedback);
      kept = [...kept, ...top];
    }
    const enriched = attachQuestionEvidence(kept as unknown as Record<string, unknown>[], chunks as Chunk[]);
    const valid = enriched.filter((qd) => {
      const opts = qd.options as string[];
      if (!String(qd.question || "").trim() || !Array.isArray(opts) || opts.length !== 4) return false;
      if (!Number.isInteger(qd.correct_answer) || (qd.correct_answer as number) < 0 || (qd.correct_answer as number) > 3) return false;
      return validateQuestionGrounding(qd, chunks as Chunk[], new Set([skid]), courseId, lessonId).ok;
    });
    if (valid.length === 0) return err(c, 404, "Regeneration produced no grounded question. Try different feedback.");
    const rec = valid[0];
    await run(
      c.env.DB,
      "UPDATE questions SET question_text=?, options=?, correct_answer=?, explanation=?, difficulty=?, source_chunk_ids=?, source_evidence=? WHERE id=?",
      String(rec.question), jstr(rec.options), jstr(rec.correct_answer), String(rec.explanation || ""),
      String(rec.difficulty || "medium"), jstr(rec.source_chunk_ids || []), jstr(rec.source_evidence || []), String(qr.id),
    );
    if (String(bank.status) !== "pending_review") {
      await run(c.env.DB, "UPDATE question_banks SET status='pending_review', updated_at=? WHERE id=?", new Date().toISOString(), String(bank.id));
    }
    void retrieveLesson;
    const fresh = (await q1<Record<string, unknown>>(c.env.DB, "SELECT * FROM questions WHERE id = ?", String(qr.id)))!;
    return c.json({ question: teacherQ(fresh), backend });
  } catch (e) {
    return toErr(c, e, 404);
  }
});

teacherRoutes.post("/banks/:id/regenerate", requireRole("teacher"), async (c) => {
  const bank = await ownedBank(c, P(c, "id"), getUser(c)).catch(() => null);
  if (!bank) return err(c, 404, "Question bank not found");
  const body = await c.req.json().catch(() => ({}));
  const rlRb = await checkRate(c.env, "ai", `${getUser(c).id}:regen`, 30, 3600);
  if (!rlRb.allowed) return err(c, 429, "AI generation limit reached. Try again later.");
  const n = Math.min(15, Math.max(4, Number(body.n_questions || 10)));
  const out = await generateQuestionBank(
    c.env, String(bank.course_id), String(bank.lesson_id), String(bank.skill_id),
    String(body.teacher_feedback || bank.teacher_feedback || ""), n,
    {
      teacher_id: bank.teacher_id ? String(bank.teacher_id) : getUser(c).id,
      classroom_id: bank.classroom_id ? String(bank.classroom_id) : "",
      material_id: bank.material_id ? String(bank.material_id) : "",
    },
  );
  void generateLessonBanks;
  return c.json(out, 201);
});

teacherRoutes.get("/classrooms/:id/mastery", requireRole("teacher"), async (c) => {
  const room = await teacherClassroom(c, P(c, "id")).catch(() => null);
  if (!room) return err(c, 404, "Classroom not found");
  return c.json(await classroomMastery(c.env, String(room.id)));
});

teacherRoutes.get("/classrooms/:cid/students/:sid", requireRole("teacher"), async (c) => {
  const me = getUser(c);
  const room = await teacherClassroom(c, P(c, "cid")).catch(() => null);
  if (!room) return err(c, 404, "Classroom not found");
  const en = await q1(c.env.DB, "SELECT id FROM classroom_enrollments WHERE classroom_id = ? AND student_id = ?", String(room.id), P(c, "sid"));
  if (!en) return err(c, 404, "Student not found");
  void me;
  const { studentGrades: _g } = await import("../assess");
  void _g;
  const grades = await studentGrades(c.env, P(c, "sid"), String(room.id));
  const { skillStatesForLesson } = await import("../assess");
  const { supportSummary } = await import("../assess");
  const { getProfile } = await import("../assess");
  const mats = await q<Record<string, unknown>>(c.env.DB, "SELECT * FROM learning_materials WHERE classroom_id = ? AND scope = 'official' ORDER BY rowid", String(room.id));
  const units = [];
  for (const mat of mats) {
    units.push({
      material_id: mat.id, title: mat.title,
      skills: await skillStatesForLesson(c.env, P(c, "sid"), `class:${room.id}`, String(mat.id)),
    });
  }
  const prof = await getProfile(c.env, P(c, "sid"));
  const attempts = await q<Record<string, unknown>>(c.env.DB, "SELECT question_id, correct, timestamp FROM student_attempts WHERE student_id = ? ORDER BY timestamp DESC LIMIT 20", P(c, "sid"));
  return c.json({
    student_id: P(c, "sid"), units, grades: grades.slice(0, 10),
    support_summary: prof ? supportSummary(prof) : [],
    recent_activity: attempts.map((a) => ({ question_id: a.question_id, correct: !!a.correct, timestamp: a.timestamp || null })),
  });
});

teacherRoutes.post("/banks/:bankId/questions/:qid/flag", requireRole("teacher"), async (c) => {
  const bank = await ownedBank(c, P(c, "bankId"), getUser(c)).catch(() => null);
  if (!bank) return err(c, 404, "Question bank not found");
  const qr = await q1<Record<string, unknown>>(c.env.DB, "SELECT * FROM questions WHERE id = ?", P(c, "qid"));
  if (!qr || String(qr.question_bank_id) !== String(bank.id)) return err(c, 404, "Question not found");
  const body = await c.req.json().catch(() => ({}));
  const reason = String(body.reason || "").trim();
  if (!reason) return err(c, 422, "A flag reason is required");
  const id = uid();
  await run(c.env.DB, "INSERT INTO question_feedback (id, question_id, teacher_id, kind, reason, created_at) VALUES (?,?,?,?,?,?)",
    id, String(qr.id), getUser(c).id, "flag", reason.slice(0, 2000), new Date().toISOString());
  return c.json({ id, question_id: String(qr.id), kind: "flag", reason }, 201);
});

teacherRoutes.get("/banks/:bankId/flags", requireRole("teacher"), async (c) => {
  const bank = await ownedBank(c, P(c, "bankId"), getUser(c)).catch(() => null);
  if (!bank) return err(c, 404, "Question bank not found");
  const rows = await q<Record<string, unknown>>(
    c.env.DB, "SELECT f.* FROM question_feedback f JOIN questions q ON q.id = f.question_id WHERE q.question_bank_id = ? ORDER BY f.rowid",
    String(bank.id),
  );
  return c.json(rows.map((f) => ({ id: f.id, question_id: f.question_id, kind: f.kind, reason: f.reason, created_at: f.created_at })));
});
