import type { Env } from "./env";
import { insertMany, q, q1, run } from "./db";
import {
  attachQuestionEvidence,
  attachSkillEvidence,
  retrieveLesson,
  searchChunks,
  validateQuestionGrounding,
  validateSkillGrounding,
  type StoredChunk,
} from "./rag";
import {
  completeJson,
  fallbackCritique,
  fallbackExplanation,
  fallbackLessonExplanation,
  fallbackQuestions,
  fallbackSkills,
  generateQuestionsLlm,
  LESSON_EXPLANATION_SYSTEM,
  QUESTION_SYSTEM,
  SKILL_EXPLANATION_SYSTEM,
  SKILL_EXTRACTION_SYSTEM,
  type Chunk,
  type DraftQuestion,
} from "./llm";
import { jparse, jstr, nowIso, uid } from "./util";

const MAX_CONTEXT = 6000;
const SKILL_CONTEXT = 4000;
const N_PER_BANK = 4;

function ctxText(chunks: Chunk[], budget: number, withSkill = false): string {
  const parts = chunks.map(
    (c, i) => `[chunk ${c.chunk_id || i}${withSkill ? ` | skill=${c.skill_id || ""}` : ""}] ${c.text || ""}`,
  );
  return parts.join("\n\n").slice(0, budget) || "(no context retrieved)";
}

function isSlug(s: string): boolean {
  return typeof s === "string" && s.length > 0 && s.length <= 128 && /^[a-z0-9_]+$/.test(s);
}

// ---------------------------------------------------------------------------
// Skills
// ---------------------------------------------------------------------------

export interface SkillRow extends Record<string, unknown> {
  id: string;
  course_id: string;
  lesson_id: string;
  skill_id: string;
  name: string;
  description: string;
  explanation: string;
  key_concepts: string[];
}

export async function listSkills(env: Env, courseId: string, lessonId: string): Promise<SkillRow[]> {
  const rows = await q<Record<string, unknown>>(
    env.DB,
    "SELECT * FROM skills WHERE course_id = ? AND lesson_id = ? ORDER BY rowid",
    courseId,
    lessonId,
  );
  return rows.map((r) => ({ ...r, key_concepts: jparse<string[]>(r.key_concepts, []) }) as SkillRow);
}

export async function extractSkills(
  env: Env,
  courseId: string,
  lessonId: string,
  maxSkills = 6,
  force = false,
): Promise<{ skills: SkillRow[]; backend: string; dropped: unknown[]; retrieved_chunks: number; status?: string }> {
  if (!force) {
    const existing = await listSkills(env, courseId, lessonId);
    if (existing.length > 0) return { skills: existing, backend: "existing", dropped: [], retrieved_chunks: 0 };
  }
  const chunks = await retrieveLesson(env, courseId, lessonId, 5);
  if (chunks.length === 0) {
    return { skills: [], backend: "empty-retrieval", dropped: [], retrieved_chunks: 0, status: "failed" };
  }
  type Raw = { skill_id: string; name: string; description: string; key_concepts: string[] };
  let raw: Raw[];
  let backend: string;
  try {
    const user = `Course: ${courseId}\nLesson: ${lessonId}\nMaximum skills (upper bound only — you decide the actual number from the INSTRUCTIONAL topics, fewer is fine): ${maxSkills}\n\n--- LESSON CONTEXT ---\n${ctxText(chunks, MAX_CONTEXT)}\n--- END CONTEXT ---\n\nFirst identify the central educational topic, then extract skills ONLY from instructional content. Ignore incidental information (teacher/author/school names, dates, page numbers, references, formatting).`;
    const { data } = await completeJson(env, SKILL_EXTRACTION_SYSTEM, user);
    const list = ((data as Record<string, unknown>).skills as Raw[]) || [];
    raw = list.filter((s) => s && isSlug(s.skill_id) && s.name && s.description);
    const seen = new Set<string>();
    raw = raw.filter((s) => (seen.has(s.skill_id) ? false : (seen.add(s.skill_id), true)));
    backend = "llm";
  } catch (e) {
    raw = fallbackSkills(chunks, lessonId, maxSkills) as Raw[];
    backend = `fallback:${(e instanceof Error ? e.message : String(e)).slice(0, 120)}`;
  }
  let enriched = attachSkillEvidence(raw, chunks);
  // schema-valid strict subset
  enriched = enriched.filter((s) => isSlug(String(s.skill_id)) && String(s.name || "").trim() && String(s.description || "").trim());
  let accepted: Record<string, unknown>[] = [];
  let rejected: unknown[] = [];
  {
    const acc: Record<string, unknown>[] = [];
    const rej: unknown[] = [];
    for (const s of enriched) {
      const { ok, reasons } = validateSkillGrounding(s, chunks, courseId, lessonId);
      if (ok) acc.push(s);
      else rej.push({ skill_id: s.skill_id || "?", reasons });
    }
    accepted = acc;
    rejected = rej;
  }
  if (accepted.length === 0 && backend === "llm") {
    // one bounded fallback attempt on the same chunks
    const fb = attachSkillEvidence(fallbackSkills(chunks, lessonId, maxSkills) as unknown as Record<string, unknown>[], chunks).filter(
      (s) => isSlug(String(s.skill_id)) && String(s.name || "").trim(),
    );
    const acc: Record<string, unknown>[] = [];
    for (const s of fb) {
      if (validateSkillGrounding(s, chunks, courseId, lessonId).ok) acc.push(s);
    }
    accepted = acc;
    backend = "llm+fallback-retry";
  }
  accepted = accepted.slice(0, Math.max(1, maxSkills));
  const now = nowIso();
  for (const s of accepted) {
    const sid = String(s.skill_id);
    const ex = await q1(env.DB, "SELECT id FROM skills WHERE course_id = ? AND lesson_id = ? AND skill_id = ?", courseId, lessonId, sid);
    const kc = jstr((s.key_concepts as string[]) || []);
    const lo = String(s.learning_objective || "");
    const sc = jstr((s.source_chunk_ids as string[]) || []);
    const se2 = jstr((s.source_evidence as string[]) || []);
    if (ex) {
      await run(
        env.DB,
        "UPDATE skills SET name=?, description=?, key_concepts=?, learning_objective=?, source_chunk_ids=?, source_evidence=?, updated_at=? WHERE id=?",
        String(s.name || ""), String(s.description || ""), kc, lo, sc, se2, now, String(ex.id),
      );
    } else {
      await run(
        env.DB,
        "INSERT INTO skills (id, course_id, lesson_id, skill_id, name, description, key_concepts, learning_objective, source_chunk_ids, source_evidence, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
        uid(), courseId, lessonId, sid, String(s.name || ""), String(s.description || ""), kc, lo, sc, se2, now, now,
      );
    }
  }
  const skills = await listSkills(env, courseId, lessonId);
  const out: { skills: SkillRow[]; backend: string; dropped: unknown[]; retrieved_chunks: number; status?: string } = {
    skills, backend, dropped: rejected, retrieved_chunks: chunks.length,
  };
  if (skills.length === 0) out.status = "failed";
  return out;
}

export async function explainSkills(env: Env, courseId: string, lessonId: string, force = false): Promise<void> {
  const skills = await listSkills(env, courseId, lessonId);
  // Concurrent LLM calls (fetch-bound); D1 serializes the persists.
  await Promise.all(
    skills.map(async (sk) => {
      if (sk.explanation && !force) return;
      const chunks = await searchChunks(env, `${sk.name} ${sk.description} ${(sk.key_concepts || []).join(" ")}`, 3, courseId, lessonId);
      let text: string;
      try {
        const user = `Course: ${courseId}\nLesson: ${lessonId}\nSkill: ${sk.name} (${sk.skill_id})\nDescription: ${sk.description}\nKey concepts: ${(sk.key_concepts || []).join(", ")}\n\n--- SKILL MATERIAL ---\n${ctxText(chunks, SKILL_CONTEXT)}\n--- END MATERIAL ---\n\nExplain ONLY the skill above from instructional content; ignore incidental metadata.`;
        const { data } = await completeJson(env, SKILL_EXPLANATION_SYSTEM, user);
        text = String((data as Record<string, unknown>).explanation || "");
        if (text.length < 40) throw new Error("short explanation");
      } catch {
        text = fallbackExplanation({ name: sk.name, skill_id: sk.skill_id, description: sk.description }, chunks);
      }
      await run(env.DB, "UPDATE skills SET explanation=?, updated_at=? WHERE id=?", text, nowIso(), sk.id);
    }),
  );
}

export async function explainLesson(env: Env, courseId: string, lessonId: string, force = false): Promise<Record<string, unknown>> {
  if (!force) {
    const ex = await q1<Record<string, unknown>>(env.DB, "SELECT * FROM lesson_explanations WHERE course_id = ? AND lesson_id = ?", courseId, lessonId);
    if (ex && String(ex.explanation || "")) {
      return { ...ex, key_concepts: jparse(ex.key_concepts, []) };
    }
  }
  const chunks = await retrieveLesson(env, courseId, lessonId, 5);
  const skills = await listSkills(env, courseId, lessonId);
  const names = skills.map((s) => s.name);
  let title = "";
  let text = "";
  let concepts: string[] = [];
  try {
    const user = `Course: ${courseId}\nLesson: ${lessonId}\nSkills in this lesson: ${names.join(", ") || "(skills not extracted yet)"}\n\n--- LESSON MATERIAL ---\n${ctxText(chunks, MAX_CONTEXT)}\n--- END MATERIAL ---\n\nSummarize the instructional topic; ignore incidental metadata.`;
    const { data } = await completeJson(env, LESSON_EXPLANATION_SYSTEM, user);
    const d = data as Record<string, unknown>;
    title = String(d.title || "");
    text = String(d.explanation || "");
    concepts = (d.key_concepts as string[]) || [];
    if (text.length < 60) throw new Error("short lesson explanation");
  } catch {
    const fb = fallbackLessonExplanation(chunks, lessonId, names);
    title = fb.title;
    text = fb.explanation;
    concepts = fb.key_concepts;
  }
  const now = nowIso();
  const ex = await q1<Record<string, unknown>>(env.DB, "SELECT id FROM lesson_explanations WHERE course_id = ? AND lesson_id = ?", courseId, lessonId);
  if (ex) {
    await run(env.DB, "UPDATE lesson_explanations SET title=?, explanation=?, key_concepts=?, updated_at=? WHERE id=?", title, text, jstr(concepts), now, String(ex.id));
  } else {
    await run(
      env.DB,
      "INSERT INTO lesson_explanations (id, course_id, lesson_id, title, explanation, key_concepts, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?)",
      uid(), courseId, lessonId, title, text, jstr(concepts), now, now,
    );
  }
  return { lesson_id: lessonId, title, explanation: text, key_concepts: concepts };
}

// ---------------------------------------------------------------------------
// Lazy backfill: some scopes have skill rows / approved banks but no
// explanations (the bank pipeline never generated them — only the
// extract-skills route did). Student read paths call this best-effort so the
// first request heals the data instead of 404ing. Both explain calls skip
// anything already present, so this is a no-op for healthy scopes.
// ---------------------------------------------------------------------------

export async function ensureScopeExplanations(env: Env, courseId: string, lessonId: string): Promise<void> {
  const missingSkill = await q1(env.DB, "SELECT id FROM skills WHERE course_id = ? AND lesson_id = ? AND (explanation IS NULL OR explanation = '') LIMIT 1", courseId, lessonId);
  if (missingSkill) await explainSkills(env, courseId, lessonId, false);
  const missingLesson = await q1<Record<string, unknown>>(env.DB, "SELECT id, explanation FROM lesson_explanations WHERE course_id = ? AND lesson_id = ?", courseId, lessonId);
  if (!missingLesson || !String(missingLesson.explanation || "")) await explainLesson(env, courseId, lessonId, false);
}

// ---------------------------------------------------------------------------
// Question banks
// ---------------------------------------------------------------------------

function validQuestion(qd: Record<string, unknown>): boolean {
  if ((qd.type || "multiple_choice") !== "multiple_choice") return false;
  if (!String(qd.question || "").trim()) return false;
  const opts = qd.options as string[];
  if (!Array.isArray(opts) || opts.length !== 4) return false;
  if (opts.some((o) => !String(o || "").trim())) return false;
  if (new Set(opts.map((o) => String(o).trim())).size !== 4) return false;
  const ca = qd.correct_answer;
  if (!Number.isInteger(ca) || (ca as number) < 0 || (ca as number) > 3) return false;
  return true;
}

function dedup(questions: Record<string, unknown>[]): Record<string, unknown>[] {
  const seen = new Set<string>();
  const out: Record<string, unknown>[] = [];
  for (const q of questions) {
    const k = String(q.question || "").trim().toLowerCase();
    if (!k || seen.has(k)) continue;
    seen.add(k);
    out.push(q);
  }
  return out;
}

async function flagReasons(env: Env, courseId: string, lessonId: string, skillId: string): Promise<string[]> {
  const rows = await q<Record<string, unknown>>(
    env.DB,
    `SELECT f.reason FROM question_feedback f JOIN questions q ON q.id = f.question_id
     JOIN question_banks b ON b.id = q.question_bank_id
     WHERE b.course_id = ? AND b.lesson_id = ? AND b.skill_id = ? AND f.kind = 'flag' ORDER BY f.rowid`,
    courseId, lessonId, skillId,
  );
  return rows.map((r) => String(r.reason || "")).filter(Boolean);
}

async function nextBankVersion(env: Env, courseId: string, lessonId: string, skillId: string): Promise<number> {
  await run(
    env.DB,
    "INSERT INTO bank_version_counters (course_id, lesson_id, skill_id, version) VALUES (?,?,?,0) ON CONFLICT (course_id, lesson_id, skill_id) DO NOTHING",
    courseId, lessonId, skillId,
  );
  await run(env.DB, "UPDATE bank_version_counters SET version = version + 1 WHERE course_id = ? AND lesson_id = ? AND skill_id = ?", courseId, lessonId, skillId);
  const row = await q1<{ version: number }>(env.DB, "SELECT version FROM bank_version_counters WHERE course_id = ? AND lesson_id = ? AND skill_id = ?", courseId, lessonId, skillId);
  return Number(row?.version || 1);
}

export async function generateQuestionBank(
  env: Env,
  courseId: string,
  lessonId: string,
  skillId: string,
  feedback = "",
  n = 8,
  ownership: { teacher_id?: string; classroom_id?: string; material_id?: string } = {},
): Promise<{ question_bank_id: string; version: number; status: string; num_questions: number; backend: string }> {
  let chunks = await searchChunks(env, `${skillId} ${lessonId}`, 4, courseId, lessonId, skillId);
  if (chunks.length === 0) chunks = await retrieveLesson(env, courseId, lessonId, 4);
  if (chunks.length === 0) {
    const version = await nextBankVersion(env, courseId, lessonId, skillId);
    const id = uid();
    const now = nowIso();
    await run(
      env.DB,
      "INSERT INTO question_banks (id, course_id, lesson_id, skill_id, version, status, teacher_feedback, teacher_id, classroom_id, material_id, created_at, updated_at) VALUES (?,?,?,?,?,'pending_review',?,?,?,?,?,?)",
      id, courseId, lessonId, skillId, version, feedback, ownership.teacher_id || null, ownership.classroom_id || null, ownership.material_id || null, now, now,
    );
    return { question_bank_id: id, version, status: "failed", num_questions: 0, backend: "empty-retrieval" };
  }
  const reasons = await flagReasons(env, courseId, lessonId, skillId);
  const effFeedback = reasons.length > 0 ? `${feedback}\nPrior teacher flags to avoid repeating:\n${reasons.join("\n")}` : feedback;
  const skill = await q1<Record<string, unknown>>(env.DB, "SELECT * FROM skills WHERE course_id = ? AND lesson_id = ? AND skill_id = ?", courseId, lessonId, skillId);
  const concepts = jparse<string[]>(skill?.key_concepts, []);
  const user = `Course: ${courseId}\nLesson: ${lessonId}\nSkill: ${skillId}\nTeacher feedback (may be empty): ${(effFeedback || "(none)").slice(0, 800)}\n\n--- RETRIEVED LESSON CONTEXT ---\n${ctxText(chunks, SKILL_CONTEXT, true)}\n--- END CONTEXT ---\n\nFirst state the central educational topic in one line (as a JSON comment is NOT allowed, just use it internally), then generate UP TO ${n} GOOD questions as a JSON array. Focus ONLY on the requested skill and instructional content; ignore incidental metadata (teacher/author/school names, dates, page numbers, references, formatting). If the material supports fewer than ${n} meaningful questions, return fewer — never pad with trivia.`;
  const { questions: drafts, backend } = await generateQuestionsLlm(env, QUESTION_SYSTEM, user, chunks, skillId, n, effFeedback);
  for (const d of drafts) d.skill_id = skillId;
  // deterministic critique (LLM critique opt-in only; default off)
  const verdicts = fallbackCritique(drafts, chunks);
  const bad = new Set(verdicts.filter((v) => !(v.grounded && v.answer_correct && v.relevant)).map((v) => v.index));
  let kept = drafts.filter((_, i) => !bad.has(i));
  kept = kept.filter((d) => {
    const r = d as unknown as Record<string, unknown>;
    if (!r.question || !Array.isArray(r.options) || r.options.length !== 4) return false;
    if (!Number.isInteger(r.correct_answer) || (r.correct_answer as number) < 0 || (r.correct_answer as number) > 3) return false;
    return true;
  });
  let enriched = attachQuestionEvidence(kept as unknown as Record<string, unknown>[], chunks);
  const validSkillIds = new Set([skillId]);
  let accepted = enriched.filter((qd) => validQuestion(qd) && validateQuestionGrounding(qd, chunks, validSkillIds, courseId, lessonId).ok);
  accepted = dedup(accepted);
  if (accepted.length < n) {
    // one bounded deterministic top-up, same chunks
    const need = n - accepted.length;
    const top = attachQuestionEvidence(fallbackQuestions(chunks, skillId, need, effFeedback) as unknown as Record<string, unknown>[], chunks);
    const more = top.filter((qd) => validQuestion(qd) && validateQuestionGrounding(qd, chunks, validSkillIds, courseId, lessonId).ok);
    const seen = new Set(accepted.map((q) => String(q.question).trim().toLowerCase()));
    for (const q of more) {
      const k = String(q.question).trim().toLowerCase();
      if (!seen.has(k)) {
        seen.add(k);
        accepted.push(q);
      }
    }
  }
  const version = await nextBankVersion(env, courseId, lessonId, skillId);
  const id = uid();
  const now = nowIso();
  // version-collision retry x3
  let v = version;
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      await run(
        env.DB,
        "INSERT INTO question_banks (id, course_id, lesson_id, skill_id, version, status, teacher_feedback, teacher_id, classroom_id, material_id, created_at, updated_at) VALUES (?,?,?,?,?,'pending_review',?,?,?,?,?,?)",
        id, courseId, lessonId, skillId, v, effFeedback, ownership.teacher_id || null, ownership.classroom_id || null, ownership.material_id || null, now, now,
      );
      break;
    } catch {
      v = await nextBankVersion(env, courseId, lessonId, skillId);
      if (attempt === 2) throw new Error("bank version allocation failed");
    }
  }
  if (accepted.length > 0) {
    await insertMany(
      env.DB,
      "questions",
      ["id", "question_bank_id", "skill_id", "question_type", "question_text", "options", "correct_answer", "explanation", "difficulty", "source_chunk_ids", "source_evidence", "created_at"],
      accepted.map((qd) => [
        uid(), id, skillId, "multiple_choice", String(qd.question), jstr(qd.options),
        jstr(qd.correct_answer), String(qd.explanation || ""), String(qd.difficulty || "medium"),
        jstr(qd.source_chunk_ids || []), jstr(qd.source_evidence || []), now,
      ]),
      6,
    );
  }
  return { question_bank_id: id, version: v, status: "pending_review", num_questions: accepted.length, backend };
}

export async function generateLessonBanks(
  env: Env,
  courseId: string,
  lessonId: string,
  feedback = "",
  n = 6,
  ownership: { teacher_id?: string; classroom_id?: string; material_id?: string } = {},
): Promise<{ banks: unknown[]; skipped_skills: unknown[] }> {
  let skills = await listSkills(env, courseId, lessonId);
  if (skills.length === 0) {
    await extractSkills(env, courseId, lessonId, 6, false);
    skills = await listSkills(env, courseId, lessonId);
  }
  // Concurrent (Promise.all over fetches — Workers have no threads, but
  // parallel subrequests keep total latency near one LLM call, which matters
  // because mobile clients time out long polls). D1 serializes the writes.
  const banks: unknown[] = await Promise.all(
    skills.map((sk) => generateQuestionBank(env, courseId, lessonId, sk.skill_id, feedback, n, ownership).then((b) => ({ skill_id: sk.skill_id, ...b }))),
  );
  return { banks, skipped_skills: [] };
}
