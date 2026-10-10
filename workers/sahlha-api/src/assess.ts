import type { Env } from "./env";
import { insertMany, q, q1, run } from "./db";
import { jparse, jstr, nowIso, uid } from "./util";
import { listSkills } from "./agent";

// ---------------------------------------------------------------------------
// Mapping (port of services/mapping.py)
// ---------------------------------------------------------------------------

export const courseForClassroom = (classroomId: string) => `class:${classroomId}`;
export const courseForChild = (studentId: string) => `child:${studentId}`;

export function scopeForMaterial(mat: Record<string, unknown>): [string, string] {
  if (mat.scope === "official" && mat.classroom_id) return [courseForClassroom(String(mat.classroom_id)), String(mat.id)];
  if (mat.child_student_id) return [courseForChild(String(mat.child_student_id)), String(mat.id)];
  return ["general", String(mat.id)];
}

export function classroomIdFromCourse(courseId: string): string | null {
  return courseId.startsWith("class:") ? courseId.slice(6) : null;
}

// ---------------------------------------------------------------------------
// Mastery (port of services/mastery.py)
// ---------------------------------------------------------------------------

export const NOT_STARTED = "not_started";
export const NEEDS_PRACTICE = "needs_practice";
export const DEVELOPING = "developing";
export const MASTERED = "mastered";

export function masteryState(attempted: number, accuracy: number | null): string {
  if (!attempted) return NOT_STARTED;
  const acc = accuracy || 0;
  if (acc >= 0.8 && attempted >= 4) return MASTERED;
  if (acc >= 0.6) return DEVELOPING;
  return NEEDS_PRACTICE;
}

export function summarizeMastery(states: string[]): Record<string, number> {
  const c: Record<string, number> = { [NOT_STARTED]: 0, [NEEDS_PRACTICE]: 0, [DEVELOPING]: 0, [MASTERED]: 0 };
  for (const s of states) c[s] = (c[s] || 0) + 1;
  return c;
}

// ---------------------------------------------------------------------------
// Profiles (port of services/profiles.py)
// ---------------------------------------------------------------------------

export const KNOWN_SIGNALS = new Set([
  "hint_used", "retry", "example_helped", "simpler_helped", "audio_used",
  "visual_helped", "step_helped", "struggled", "improved",
]);

const READING: Record<string, string> = { easy: "standard_text", sometimes: "larger_text_breaks", hard: "short_chunks_audio" };
const FOCUS: Record<string, string> = { long: "standard_sessions", medium: "short_steps_checkins", short: "one_task_short" };
const INSTRUCTIONS: Record<string, string> = { long_ok: "full_instructions", steps: "step_by_step", show_first: "example_first" };
const PRESENTATION: Record<string, string> = { read: "read_first", listen: "audio_offered", pictures: "visual_first" };
const PRACTICE: Record<string, string> = { try_first: "independent_first", example_first: "example_first", practice_more: "extra_repetition" };
const SESSION: Record<string, string> = { short: "short", medium: "medium", long: "long" };
const CONFIDENCE: Record<string, string> = { confident: "confident", sometimes: "building", nervous: "needs_encouragement" };

export async function applyOnboarding(env: Env, studentId: string, answers: Record<string, string>) {
  const pick = (k: string, t: Record<string, string>, d: string) => t[String(answers[k] || "").trim()] || d;
  const row = {
    student_id: studentId,
    onboarding_completed: 1,
    reading_support: pick("reading", READING, "standard_text"),
    focus_support: pick("focus", FOCUS, "standard_sessions"),
    instruction_support: pick("instructions", INSTRUCTIONS, "full_instructions"),
    presentation_support: pick("presentation", PRESENTATION, "read_first"),
    practice_support: pick("practice", PRACTICE, "independent_first"),
    session_preference: pick("session", SESSION, "medium"),
    learning_confidence: pick("confidence", CONFIDENCE, "building"),
    raw_answers: jstr(answers),
    updated_at: nowIso(),
  };
  const ex = await q1(env.DB, "SELECT student_id FROM student_learning_profiles WHERE student_id = ?", studentId);
  if (ex) {
    await run(
      env.DB,
      `UPDATE student_learning_profiles SET onboarding_completed=1, reading_support=?, focus_support=?, instruction_support=?,
       presentation_support=?, practice_support=?, session_preference=?, learning_confidence=?, raw_answers=?, updated_at=? WHERE student_id=?`,
      row.reading_support, row.focus_support, row.instruction_support, row.presentation_support,
      row.practice_support, row.session_preference, row.learning_confidence, row.raw_answers, row.updated_at, studentId,
    );
  } else {
    await run(
      env.DB,
      `INSERT INTO student_learning_profiles (student_id, onboarding_completed, reading_support, focus_support, instruction_support,
       presentation_support, practice_support, session_preference, learning_confidence, raw_answers, observed_settings, updated_at)
       VALUES (?,?,?,?,?,?,?,?,?,'{}',?)`,
      studentId, 1, row.reading_support, row.focus_support, row.instruction_support, row.presentation_support,
      row.practice_support, row.session_preference, row.learning_confidence, row.raw_answers, row.updated_at,
    );
  }
  return getProfile(env, studentId);
}

export async function getProfile(env: Env, studentId: string): Promise<Record<string, unknown> | null> {
  return q1<Record<string, unknown>>(env.DB, "SELECT * FROM student_learning_profiles WHERE student_id = ?", studentId);
}

export function profileToDict(prof: Record<string, unknown> | null): Record<string, unknown> {
  if (!prof) return { onboarding_completed: false, supports: {}, observed: {}, support_summary: [] };
  const supports = {
    reading: prof.reading_support, focus: prof.focus_support, instructions: prof.instruction_support,
    presentation: prof.presentation_support, practice: prof.practice_support,
    session: prof.session_preference, confidence: prof.learning_confidence,
  };
  return {
    onboarding_completed: !!prof.onboarding_completed, supports,
    observed: jparse(prof.observed_settings, {}),
    support_summary: supportSummary(prof),
    hint_count: Number(prof.support_hint_count || 0), retry_count: Number(prof.support_retry_count || 0),
  };
}

const FRIENDLY: Record<string, string> = {
  short_chunks_audio: "Shorter explanations with audio currently help.",
  larger_text_breaks: "Larger text with breaks currently helps.",
  one_task_short: "One task at a time currently helps.",
  short_steps_checkins: "Short steps with check-ins currently help.",
  step_by_step: "Step-by-step instructions work well.",
  example_first: "Examples before independent practice help.",
  extra_repetition: "Additional repetition currently helps.",
  audio_offered: "Audio support currently appears helpful.",
  visual_first: "Visual explanations currently appear helpful.",
  short: "Short sessions are preferred.",
};

export function supportSummary(prof: Record<string, unknown>): string[] {
  const out: string[] = [];
  for (const key of [prof.reading_support, prof.focus_support, prof.instruction_support, prof.presentation_support, prof.practice_support, prof.session_preference]) {
    const k = String(key || "");
    if (FRIENDLY[k] && !out.includes(FRIENDLY[k])) out.push(FRIENDLY[k]);
  }
  const obs = jparse<Record<string, unknown>>(prof.observed_settings, {});
  for (const [key, value] of Object.entries(obs)) {
    if (value && FRIENDLY[key] && !out.includes(FRIENDLY[key])) out.push(FRIENDLY[key]);
  }
  return out;
}

export async function recordSupportSignal(env: Env, studentId: string, signal: string): Promise<Record<string, unknown> | null> {
  signal = (signal || "").trim();
  if (!KNOWN_SIGNALS.has(signal)) {
    const prof = await getProfile(env, studentId);
    if (!prof) throw new Error(`Unknown support signal: ${signal.slice(0, 64)}`);
    return prof;
  }
  let prof = await getProfile(env, studentId);
  const observed: Record<string, unknown> = prof ? { ...jparse<Record<string, unknown>>(prof.observed_settings, {}) } : {};
  const num = (k: string) => Number(observed[k] || 0);
  if (signal === "hint_used") observed.hints_helpful = num("hints_helpful") + 1;
  else if (signal === "retry") observed.retries = num("retries") + 1;
  else if (signal === "struggled") {
    observed.needs_simpler = num("needs_simpler") + 1;
    if (num("needs_simpler") >= 3) {
      observed.short_chunks_audio = true;
      observed.step_by_step = true;
    }
  } else if (signal === "example_helped") observed.example_first = true;
  else if (signal === "simpler_helped") observed.short_chunks_audio = true;
  else if (signal === "audio_used") observed.audio_offered = true;
  else if (signal === "visual_helped") observed.visual_first = true;
  else if (signal === "step_helped") observed.step_by_step = true;
  else if (signal === "improved") {
    observed.improving = num("improving") + 1;
    if (num("needs_simpler") > 0) observed.needs_simpler = num("needs_simpler") - 1;
  }
  const now = nowIso();
  if (!prof) {
    await run(
      env.DB,
      "INSERT INTO student_learning_profiles (student_id, onboarding_completed, observed_settings, updated_at) VALUES (?,?,?,?)",
      studentId, 0, jstr(observed), now,
    );
  } else {
    let hintCount = Number(prof.support_hint_count || 0);
    let retryCount = Number(prof.support_retry_count || 0);
    if (signal === "hint_used") hintCount++;
    if (signal === "retry") retryCount++;
    await run(
      env.DB,
      "UPDATE student_learning_profiles SET observed_settings=?, support_hint_count=?, support_retry_count=?, updated_at=? WHERE student_id=?",
      jstr(observed), hintCount, retryCount, now, studentId,
    );
  }
  return getProfile(env, studentId);
}

export function helpOrderFor(prof: Record<string, unknown> | null): string[] {
  const base = ["simpler", "example", "read_aloud", "steps", "visual", "word"];
  if (!prof) return base;
  const obs = jparse<Record<string, unknown>>(prof.observed_settings, {});
  const score: Record<string, number> = { simpler: 0, example: 0, read_aloud: 0, steps: 0, visual: 0, word: 0 };
  if (prof.presentation_support === "audio_offered" || obs.audio_offered) score.read_aloud += 2;
  if (prof.presentation_support === "visual_first" || obs.visual_first) score.visual += 2;
  if (prof.instruction_support === "example_first" || obs.example_first) score.example += 2;
  if (prof.instruction_support === "step_by_step" || obs.step_by_step) score.steps += 2;
  if (prof.reading_support === "short_chunks_audio" || obs.short_chunks_audio) score.simpler += 2;
  return [...base].sort((a, b) => score[b] - score[a]);
}

// ---------------------------------------------------------------------------
// Question pool + selection (port of assessment_tools.select_questions)
// ---------------------------------------------------------------------------

export interface PoolQ {
  id: string;
  bank_id: string;
  course_id: string;
  lesson_id: string;
  skill_id: string;
  type: string;
  question: string;
  options: string[];
  correct_answer: number | string;
  explanation: string;
  difficulty: string;
  version: number;
}

export async function approvedPool(env: Env, courseId?: string, lessonId?: string, skillId?: string): Promise<{ pool: PoolQ[]; flagged: number }> {
  const conds: string[] = ["b.status = 'approved'", "q.retired = 0"];
  const params: unknown[] = [];
  if (courseId) {
    conds.push("b.course_id = ?");
    params.push(courseId);
  }
  if (lessonId) {
    conds.push("b.lesson_id = ?");
    params.push(lessonId);
  }
  if (skillId) {
    conds.push("b.skill_id = ?");
    params.push(skillId);
  }
  const rows = await q<Record<string, unknown>>(
    env.DB,
    `SELECT q.id, q.question_bank_id AS bank_id, b.course_id, b.lesson_id, b.skill_id, q.question_type AS type,
            q.question_text AS question, q.options, q.correct_answer, q.explanation, q.difficulty, b.version
     FROM questions q JOIN question_banks b ON b.id = q.question_bank_id
     WHERE ${conds.join(" AND ")} ORDER BY b.version, q.rowid`,
    ...params,
  );
  const flaggedRows = await q<{ id: string }>(env.DB, "SELECT question_id AS id FROM question_feedback WHERE kind = 'flag'");
  const flagged = new Set(flaggedRows.map((r) => String(r.id)));
  // latest approved bank per skill
  const bySkill = new Map<string, { version: number; ids: Set<string> }>();
  for (const r of rows) {
    const k = `${r.course_id}|${r.lesson_id}|${r.skill_id}`;
    const e = bySkill.get(k) || { version: -1, ids: new Set<string>() };
    const v = Number(r.version || 0);
    if (v > e.version) {
      e.version = v;
      e.ids = new Set([String(r.bank_id)]);
    } else if (v === e.version) {
      e.ids.add(String(r.bank_id));
    }
    bySkill.set(k, e);
  }
  const pool: PoolQ[] = [];
  for (const r of rows) {
    const k = `${r.course_id}|${r.lesson_id}|${r.skill_id}`;
    if (!bySkill.get(k)!.ids.has(String(r.bank_id))) continue;
    if (flagged.has(String(r.id))) continue;
    pool.push({
      id: String(r.id), bank_id: String(r.bank_id), course_id: String(r.course_id), lesson_id: String(r.lesson_id),
      skill_id: String(r.skill_id), type: String(r.type || "multiple_choice"), question: String(r.question || ""),
      options: jparse<string[]>(r.options, []), correct_answer: jparse<number | string>(r.correct_answer, 0),
      explanation: String(r.explanation || ""), difficulty: String(r.difficulty || "medium"), version: Number(r.version || 0),
    });
  }
  return { pool, flagged: flagged.size };
}

export class SelectionError extends Error {}

export async function selectQuestions(
  env: Env,
  studentId: string,
  opts: { courseId?: string; lessonId?: string; skillId?: string; nPerBank?: number; learnedOnly?: boolean },
): Promise<{ selected: PoolQ[]; meta: Record<string, unknown> }> {
  const n = opts.nPerBank || 4;
  const { pool } = await approvedPool(env, opts.courseId, opts.lessonId, opts.skillId);
  if (pool.length === 0) throw new SelectionError("No approved questions are available yet. The teacher must approve a question bank first.");
  const attempts = await q<Record<string, unknown>>(env.DB, "SELECT question_id, correct FROM student_attempts WHERE student_id = ?", studentId);
  const attemptedIds = new Set(attempts.map((a) => String(a.question_id)));
  const failedIds = new Set(attempts.filter((a) => !a.correct).map((a) => String(a.question_id)));
  const perfRows = await q<Record<string, unknown>>(
    env.DB,
    "SELECT skill_id, accuracy FROM student_skill_performance WHERE student_id = ?" +
      (opts.courseId ? " AND course_id = ?" : "") + (opts.lessonId ? " AND lesson_id = ?" : ""),
    studentId, ...(opts.courseId ? [opts.courseId] : []), ...(opts.lessonId ? [opts.lessonId] : []),
  );
  const perf = new Map(perfRows.map((p) => [String(p.skill_id), Number(p.accuracy || 0)]));
  let scopePool = pool;
  if (opts.learnedOnly) {
    const attemptedSkills = new Set<string>();
    const qSkill = new Map(pool.map((qq) => [qq.id, qq.skill_id]));
    for (const id of attemptedIds) {
      const sk = qSkill.get(id);
      if (sk) attemptedSkills.add(sk);
    }
    // also include skills with recorded performance
    for (const sk of perf.keys()) attemptedSkills.add(sk);
    if (attemptedSkills.size < 2) throw new SelectionError("Quick Checks need at least two practiced skills. Practice more skills first.");
    scopePool = pool.filter((qq) => attemptedSkills.has(qq.skill_id));
    if (scopePool.length === 0) throw new SelectionError("No approved questions for practiced skills yet.");
  }
  const byBank = new Map<string, PoolQ[]>();
  for (const qq of scopePool) {
    if (!byBank.has(qq.bank_id)) byBank.set(qq.bank_id, []);
    byBank.get(qq.bank_id)!.push(qq);
  }
  const selected: PoolQ[] = [];
  const perBank: Record<string, number> = {};
  const weakSkills: string[] = [];
  let failedRetried = 0;
  const covered = new Set<string>();
  const bankIds = [...byBank.keys()].sort();
  for (const bid of bankIds) {
    const group = byBank.get(bid)!;
    if (group.length < n) {
      throw new SelectionError(
        `Bank ${bid} (skill '${group[0].skill_id}') has only ${group.length} approved questions; need ${n}. Regenerate or unflag questions.`,
      );
    }
    const weak = (perf.get(group[0].skill_id) ?? 1) < 0.6 && attemptedIds.size > 0;
    if (weak && !weakSkills.includes(group[0].skill_id)) weakSkills.push(group[0].skill_id);
    const picked: PoolQ[] = [];
    const take = (cands: PoolQ[]) => {
      for (const c of cands) {
        if (picked.length >= n) break;
        if (picked.includes(c) || selected.includes(c)) continue;
        picked.push(c);
      }
    };
    take(group.filter((c) => failedIds.has(c.id)));
    failedRetried += picked.length;
    const unseen = group.filter((c) => !attemptedIds.has(c.id) && !picked.includes(c));
    if (weak) take(unseen.length > 0 ? unseen : group.filter((c) => !picked.includes(c)));
    else take(unseen);
    // difficulty balance
    const counts: Record<string, number> = {};
    for (const p of picked) counts[p.difficulty] = (counts[p.difficulty] || 0) + 1;
    const rest = group.filter((c) => !picked.includes(c) && !selected.includes(c));
    rest.sort((a, b) => (counts[a.difficulty] || 0) - (counts[b.difficulty] || 0));
    take(rest);
    take(group.filter((c) => !picked.includes(c) && !selected.includes(c)));
    for (const p of picked) {
      selected.push(p);
      covered.add(p.skill_id);
    }
    perBank[bid] = picked.length;
  }
  // missing skills: lesson skills with zero approved questions
  let missing: string[] = [];
  if (opts.courseId && opts.lessonId) {
    const skills = await listSkills(env, opts.courseId, opts.lessonId);
    const coveredSkills = new Set(pool.map((qq) => qq.skill_id));
    missing = skills.map((s) => s.skill_id).filter((s) => !coveredSkills.has(s));
  }
  return {
    selected,
    meta: {
      rationale: `failed-retry -> weak-skills -> unseen -> difficulty-balance (${selected.length} questions)`,
      weak_skills: weakSkills,
      failed_retried: failedRetried,
      per_bank: perBank,
      pool_size: pool.length,
      covered_skills: [...covered],
      missing_skills: missing,
    },
  };
}

// ---------------------------------------------------------------------------
// Evaluation + memory
// ---------------------------------------------------------------------------

export function evaluateAnswer(q: { id: string; skill_id: string; type: string; correct_answer: unknown }, answer: unknown): { correct: boolean } {
  if (q.type === "multiple_choice") {
    const ca = q.correct_answer;
    if (typeof answer === "number" && typeof ca === "number") return { correct: answer === ca };
    try {
      if (parseInt(String(answer), 10) === parseInt(String(ca), 10) && String(answer).trim() !== "") return { correct: true };
    } catch { /* fall through */ }
    return { correct: String(answer) === String(ca) };
  }
  const norm = (s: string) => s.toLowerCase().replace(/\s+/g, " ").trim();
  const a = norm(String(answer ?? ""));
  const c = norm(String(ca_(q) ?? ""));
  if (!a || !c) return { correct: false };
  return { correct: a === c || a.includes(c) };
}
function ca_(q: { correct_answer: unknown }): string {
  return String(q.correct_answer ?? "");
}

export async function updateMemory(
  env: Env,
  studentId: string,
  skillId: string,
  correct: boolean,
  courseId: string,
  lessonId: string,
  skillRowId?: string,
): Promise<Record<string, unknown>> {
  const cc = courseId || "general";
  const ll = lessonId || "lesson_1";
  const ex = await q1<Record<string, unknown>>(
    env.DB,
    "SELECT * FROM student_skill_performance WHERE student_id = ? AND course_id = ? AND lesson_id = ? AND skill_id = ?",
    studentId, cc, ll, skillId,
  );
  const now = nowIso();
  if (ex) {
    const total = Number(ex.total_attempts || 0) + 1;
    const right = Number(ex.correct_attempts || 0) + (correct ? 1 : 0);
    await run(env.DB, "UPDATE student_skill_performance SET total_attempts=?, correct_attempts=?, accuracy=?, last_updated=? WHERE id=?",
      total, right, right / total, now, String(ex.id));
    return { skill: skillId, total, correct: right, accuracy: right / total };
  }
  await run(
    env.DB,
    "INSERT INTO student_skill_performance (id, student_id, skill_id, course_id, lesson_id, skill_row_id, total_attempts, correct_attempts, accuracy, last_updated) VALUES (?,?,?,?,?,?,?,?,?,?)",
    uid(), studentId, skillId, cc, ll, skillRowId || null, 1, correct ? 1 : 0, correct ? 1 : 0, now,
  );
  return { skill: skillId, total: 1, correct: correct ? 1 : 0, accuracy: correct ? 1 : 0 };
}

// ---------------------------------------------------------------------------
// Assessment flows
// ---------------------------------------------------------------------------

export function stripQuestion(qq: PoolQ): Record<string, unknown> {
  return { id: qq.id, bank_id: qq.bank_id, skill_id: qq.skill_id, type: qq.type, question: qq.question, options: qq.options, difficulty: qq.difficulty };
}

export async function startAssessment(
  env: Env,
  studentId: string,
  opts: { courseId?: string; lessonId?: string; skillId?: string; learnedOnly?: boolean },
): Promise<Record<string, unknown>> {
  const { selected, meta } = await selectQuestions(env, studentId, {
    courseId: opts.courseId, lessonId: opts.lessonId, skillId: opts.skillId, nPerBank: 4, learnedOnly: opts.learnedOnly,
  });
  const courses = selected.map((s) => s.course_id);
  const lessons = selected.map((s) => s.lesson_id);
  const domCourse = courses.sort()[Math.floor(courses.length / 2)] || opts.courseId || "general";
  const domLesson = lessons.sort()[Math.floor(lessons.length / 2)] || opts.lessonId || "lesson_1";
  // representative bank: most common
  const bankCount = new Map<string, number>();
  for (const s of selected) bankCount.set(s.bank_id, (bankCount.get(s.bank_id) || 0) + 1);
  const repBank = [...bankCount.entries()].sort((a, b) => b[1] - a[1])[0][0];
  const id = uid();
  const now = nowIso();
  await run(
    env.DB,
    `INSERT INTO assessments (id, student_id, question_bank_id, course_id, lesson_id, selection_meta, question_ids, status, score, created_at)
     VALUES (?,?,?,?,?,?,?,?,?,?)`,
    id, studentId, repBank, domCourse, domLesson, jstr(meta), jstr(selected.map((s) => s.id)), "started", 0, now,
  );
  const lesson = await q1<Record<string, unknown>>(env.DB, "SELECT * FROM lesson_explanations WHERE course_id = ? AND lesson_id = ?", domCourse, domLesson);
  const distinctSkills = [...new Set(selected.map((s) => s.skill_id))];
  const skillExpl: Record<string, unknown>[] = [];
  for (const sk of distinctSkills) {
    const row = await q1<Record<string, unknown>>(env.DB, "SELECT skill_id, name, explanation FROM skills WHERE course_id = ? AND lesson_id = ? AND skill_id = ?", domCourse, domLesson, sk);
    if (row) skillExpl.push({ skill_id: row.skill_id, name: row.name, explanation: row.explanation });
  }
  return {
    assessment_id: id,
    questions: selected.map(stripQuestion),
    lesson_explanation: lesson ? { title: lesson.title, explanation: lesson.explanation, key_concepts: jparse(lesson.key_concepts, []) } : null,
    skill_explanations: skillExpl,
    selection_meta: meta,
  };
}

export async function checkAnswer(env: Env, studentId: string, assessmentId: string, questionId: string, answer: unknown) {
  const a = await q1<Record<string, unknown>>(env.DB, "SELECT * FROM assessments WHERE id = ?", assessmentId);
  if (!a) throw Object.assign(new Error("Assessment not found"), { status: 404 });
  if (String(a.student_id) !== studentId) throw Object.assign(new Error("Not allowed"), { status: 403 });
  if (String(a.status) !== "started") throw Object.assign(new Error("This assessment is already finished"), { status: 404 });
  const qids = jparse<string[]>(a.question_ids, []);
  if (!qids.includes(questionId)) throw Object.assign(new Error("Question is not part of this assessment"), { status: 404 });
  const qr = await q1<Record<string, unknown>>(env.DB, "SELECT * FROM questions WHERE id = ?", questionId);
  if (!qr) throw Object.assign(new Error("Question not found"), { status: 404 });
  const existing = await q1<Record<string, unknown>>(env.DB, "SELECT * FROM student_attempts WHERE assessment_id = ? AND question_id = ?", assessmentId, questionId);
  if (existing) {
    return {
      question_id: questionId, correct: !!existing.correct, explanation: String(qr.explanation || ""), locked: true,
      correct_answer: String(qr.question_type) === "multiple_choice" ? jparse(qr.correct_answer, 0) : null,
    };
  }
  const res = evaluateAnswer(
    { id: String(qr.id), skill_id: String(qr.skill_id), type: String(qr.question_type || "multiple_choice"), correct_answer: jparse(qr.correct_answer, 0) },
    answer,
  );
  const now = nowIso();
  await run(env.DB, "INSERT INTO student_attempts (id, student_id, question_id, assessment_id, answer, correct, timestamp) VALUES (?,?,?,?,?,?,?)",
    uid(), studentId, questionId, assessmentId, jstr(answer), res.correct ? 1 : 0, now);
  const bank = await q1<Record<string, unknown>>(env.DB, "SELECT * FROM question_banks WHERE id = ?", String(qr.question_bank_id));
  const skRow = bank
    ? await q1<Record<string, unknown>>(env.DB, "SELECT id FROM skills WHERE course_id = ? AND lesson_id = ? AND skill_id = ?",
        String(bank.course_id), String(bank.lesson_id), String(qr.skill_id))
    : null;
  await updateMemory(env, studentId, String(qr.skill_id), res.correct,
    bank ? String(bank.course_id) : "", bank ? String(bank.lesson_id) : "", skRow ? String(skRow.id) : undefined);
  if (!res.correct) {
    try {
      await recordSupportSignal(env, studentId, "retry");
    } catch { /* never break grading */ }
  }
  return {
    question_id: questionId, correct: res.correct, explanation: String(qr.explanation || ""), locked: true,
    correct_answer: String(qr.question_type) === "multiple_choice" ? jparse(qr.correct_answer, 0) : null,
  };
}

export async function submitAssessment(env: Env, studentId: string, assessmentId: string, answers: Record<string, unknown>) {
  const a = await q1<Record<string, unknown>>(env.DB, "SELECT * FROM assessments WHERE id = ?", assessmentId);
  if (!a) throw Object.assign(new Error("Assessment not found"), { status: 404 });
  if (String(a.student_id) !== studentId) throw Object.assign(new Error("Not allowed"), { status: 403 });
  if (String(a.status) !== "started") throw Object.assign(new Error("This assessment is already submitted"), { status: 400 });
  const qids = jparse<string[]>(a.question_ids, []).slice(0, 200);
  const results: Record<string, unknown>[] = [];
  const memos: Array<{ qid: string; correct: boolean }> = [];
  for (const qid of qids) {
    const qr = await q1<Record<string, unknown>>(env.DB, "SELECT * FROM questions WHERE id = ?", qid);
    if (!qr) continue;
    const locked = await q1<Record<string, unknown>>(env.DB, "SELECT * FROM student_attempts WHERE assessment_id = ? AND question_id = ?", assessmentId, qid);
    if (locked) {
      results.push({ question_id: qid, correct: !!locked.correct, correct_answer: jparse(qr.correct_answer, 0), skill_id: String(qr.skill_id) });
      continue;
    }
    const ans = Object.prototype.hasOwnProperty.call(answers || {}, qid) ? (answers as Record<string, unknown>)[qid] : null;
    const res = evaluateAnswer(
      { id: String(qr.id), skill_id: String(qr.skill_id), type: String(qr.question_type || "multiple_choice"), correct_answer: jparse(qr.correct_answer, 0) },
      ans,
    );
    memos.push({ qid, correct: res.correct });
    results.push({ question_id: qid, correct: res.correct, correct_answer: jparse(qr.correct_answer, 0), skill_id: String(qr.skill_id) });
  }
  const now = nowIso();
  if (memos.length > 0) {
    // fetch bank scopes for memory updates
    const scopes = new Map<string, { c: string; l: string }>();
    for (const m of memos) {
      const qr = await q1<Record<string, unknown>>(env.DB, "SELECT question_bank_id FROM questions WHERE id = ?", m.qid);
      const bank = qr ? await q1<Record<string, unknown>>(env.DB, "SELECT course_id, lesson_id FROM question_banks WHERE id = ?", String(qr.question_bank_id)) : null;
      scopes.set(m.qid, { c: bank ? String(bank.course_id) : "", l: bank ? String(bank.lesson_id) : "" });
    }
    await insertMany(env.DB, "student_attempts",
      ["id", "student_id", "question_id", "assessment_id", "answer", "correct", "timestamp"],
      memos.map((m) => [uid(), studentId, m.qid, assessmentId, jstr((answers as Record<string, unknown>)[m.qid] ?? null), m.correct ? 1 : 0, now]),
      10);
    for (const m of memos) {
      const qr = await q1<Record<string, unknown>>(env.DB, "SELECT skill_id FROM questions WHERE id = ?", m.qid);
      const sc = scopes.get(m.qid)!;
      await updateMemory(env, studentId, qr ? String(qr.skill_id) : "general", m.correct, sc.c, sc.l);
    }
  }
  const correct = results.filter((r) => r.correct).length;
  const total = results.length;
  const score = total > 0 ? correct / total : 0;
  await run(env.DB, "UPDATE assessments SET status='submitted', score=? WHERE id=?", score, assessmentId);
  // per-skill accuracy within this assessment
  const bySkill = new Map<string, { c: number; t: number }>();
  for (const r of results) {
    const e = bySkill.get(String(r.skill_id)) || { c: 0, t: 0 };
    e.t++;
    if (r.correct) e.c++;
    bySkill.set(String(r.skill_id), e);
  }
  const needReview = [...bySkill.entries()].filter(([, v]) => v.t > 0 && v.c / v.t < 0.5).map(([k]) => k);
  const perf = await q<Record<string, unknown>>(env.DB, "SELECT skill_id, total_attempts, correct_attempts, accuracy FROM student_skill_performance WHERE student_id = ? AND course_id = ? AND lesson_id = ?",
    studentId, String(a.course_id || "general"), String(a.lesson_id || "lesson_1"));
  const perfOut: Record<string, unknown> = {};
  for (const p of perf) perfOut[String(p.skill_id)] = { total: p.total_attempts, correct: p.correct_attempts, accuracy: p.accuracy };
  const states: Record<string, string> = {};
  for (const p of perf) {
    states[String(p.skill_id)] = masteryState(Number(p.total_attempts || 0), Number(p.accuracy || 0));
  }
  return {
    assessment_id: assessmentId, score, correct, total, results,
    skill_performance: perfOut, mastery_states: states,
    skills_needing_review: Object.keys(states).filter((k) => states[k] === NEEDS_PRACTICE),
    _needReviewRaw: needReview,
    _wrong: total - correct,
  };
}

// ---------------------------------------------------------------------------
// Path / progress / teacher views
// ---------------------------------------------------------------------------

export async function skillStatesForLesson(env: Env, studentId: string, courseId: string, lessonId: string) {
  const approved = await q<Record<string, unknown>>(
    env.DB,
    `SELECT q.id, q.skill_id FROM questions q JOIN question_banks b ON b.id = q.question_bank_id
     WHERE b.status = 'approved' AND b.course_id = ? AND b.lesson_id = ? AND q.retired = 0`,
    courseId, lessonId,
  );
  const qToSkill = new Map(approved.map((r) => [String(r.id), String(r.skill_id)]));
  const attempts = await q<Record<string, unknown>>(env.DB, "SELECT question_id, correct FROM student_attempts WHERE student_id = ? LIMIT 10000", studentId);
  const perSkill = new Map<string, { t: number; c: number }>();
  for (const at of attempts) {
    const sk = qToSkill.get(String(at.question_id));
    if (!sk) continue;
    const e = perSkill.get(sk) || { t: 0, c: 0 };
    e.t++;
    if (at.correct) e.c++;
    perSkill.set(sk, e);
  }
  const perfRows = await q<Record<string, unknown>>(env.DB, "SELECT * FROM student_skill_performance WHERE student_id = ? AND course_id = ? AND lesson_id = ?", studentId, courseId, lessonId);
  const perf = new Map(perfRows.map((p) => [String(p.skill_id), p]));
  const { pool } = await approvedPool(env, courseId, lessonId);
  const skills = await listSkills(env, courseId, lessonId);
  return skills.map((row) => {
    const at = perSkill.get(row.skill_id) || { t: 0, c: 0 };
    const pf = perf.get(row.skill_id);
    let accuracy: number | null = at.t > 0 ? at.c / at.t : null;
    let attempted = at.t;
    let correct = at.c;
    if (pf && Number(pf.total_attempts || 0) > 0) {
      accuracy = Number(pf.accuracy || 0);
      attempted = Number(pf.total_attempts || 0);
      correct = Number(pf.correct_attempts || 0);
    }
    const usable = pool.filter((qq) => qq.skill_id === row.skill_id);
    const ready = usable.length >= 4;
    return {
      id: row.id, skill_id: row.skill_id, name: row.name, description: row.description,
      explanation: !!row.explanation, attempted, correct, accuracy,
      state: masteryState(attempted, accuracy), exercise_ready: ready,
      bank_questions: usable.length, practice_questions: ready ? 4 : 0,
    };
  });
}

export async function learningPath(env: Env, studentId: string, classroomId?: string, childScope = false) {
  let materials: Record<string, unknown>[] = [];
  let courseId = "general";
  if (classroomId) {
    materials = await q<Record<string, unknown>>(env.DB, "SELECT * FROM learning_materials WHERE classroom_id = ? AND scope = 'official' ORDER BY rowid", classroomId);
    courseId = courseForClassroom(classroomId);
  } else if (childScope) {
    materials = await q<Record<string, unknown>>(env.DB, "SELECT * FROM learning_materials WHERE child_student_id = ? AND scope = 'supplementary' ORDER BY rowid", studentId);
    courseId = courseForChild(studentId);
  }
  const units = [];
  for (const mat of materials) {
    const skills = await skillStatesForLesson(env, studentId, courseId, String(mat.id));
    units.push({
      material_id: mat.id, title: mat.title, status: mat.processing_status, skills,
      summary: summarizeMastery(skills.map((s) => s.state)),
    });
  }
  let current: Record<string, unknown> | null = null;
  for (const u of units) {
    for (const s of u.skills as Array<Record<string, unknown>>) {
      if (s.state !== MASTERED && s.exercise_ready) {
        current = { material_id: u.material_id, skill_id: s.skill_id, name: s.name };
        break;
      }
    }
    if (current) break;
  }
  if (!current) {
    for (const u of units) {
      for (const s of u.skills as Array<Record<string, unknown>>) {
        if (s.state !== MASTERED && s.explanation) {
          current = { material_id: u.material_id, skill_id: s.skill_id, name: s.name };
          break;
        }
      }
      if (current) break;
    }
  }
  const all = units.flatMap((u) => (u.skills as Array<Record<string, unknown>>).map((s) => String(s.state)));
  return {
    units, current, summary: summarizeMastery(all), total_skills: all.length,
    mastered: all.filter((s) => s === MASTERED).length,
  };
}

function shorten(text: string, maxChars = 600): string {
  if (text.length <= maxChars) return text;
  const cut = text.slice(0, maxChars);
  for (const sep of [". ", ".\n", "\n"]) {
    const i = cut.lastIndexOf(sep);
    if (i > maxChars / 2) return cut.slice(0, i + 1).trim();
  }
  return cut.trim() + "…";
}

export async function skillBundle(env: Env, studentId: string, courseId: string, lessonId: string, skillId: string) {
  const row = await q1<Record<string, unknown>>(env.DB, "SELECT * FROM skills WHERE course_id = ? AND lesson_id = ? AND skill_id = ?", courseId, lessonId, skillId);
  if (!row) throw Object.assign(new Error("Skill not found"), { status: 404 });
  const skills = await listSkills(env, courseId, lessonId);
  const idx = skills.findIndex((s) => s.skill_id === skillId);
  const states = await skillStatesForLesson(env, studentId, courseId, lessonId);
  const stMap = new Map(states.map((s) => [s.skill_id, s]));
  const prof = await getProfile(env, studentId);
  let explanation = String(row.explanation || "");
  if (prof && String(prof.reading_support) === "short_chunks_audio") explanation = shorten(explanation);
  const lc = jparse<Record<string, unknown>>(row.learning_content, {});
  const hasImage = (await env.MEDIA.get(`img:${courseId}:${lessonId}:${skillId}`)) !== null;
  const hasAudio = (await env.MEDIA.get(`aud:${courseId}:${lessonId}:${skillId}`)) !== null;
  const st = stMap.get(skillId);
  return {
    skill_id: row.skill_id, name: row.name, description: row.description, explanation,
    key_concepts: jparse(row.key_concepts, []), learning_objective: row.learning_objective || "",
    prerequisites: jparse(row.prerequisites, []), misconceptions: jparse(row.misconceptions, []),
    difficulty: row.difficulty || "", source_section_ids: jparse(row.source_section_ids, []),
    evidence_chunk_ids: jparse(row.evidence_chunk_ids, []), learning_content: lc,
    visual_type: String(lc.visual_type || "none"), visual_spec: lc.visual_spec || {}, playground: lc.playground || {},
    has_image: hasImage, image_alt: String(row.image_alt || ""), has_audio: hasAudio,
    position: (idx >= 0 ? idx : 0) + 1, total: skills.length,
    state: st ? st.state : NOT_STARTED, exercise_ready: st ? st.exercise_ready : false,
    help_order: helpOrderFor(prof),
  };
}

export async function helpForSkill(env: Env, studentId: string, courseId: string, lessonId: string, skillId: string, kind: string) {
  const row = await q1<Record<string, unknown>>(env.DB, "SELECT * FROM skills WHERE course_id = ? AND lesson_id = ? AND skill_id = ?", courseId, lessonId, skillId);
  if (!row) throw Object.assign(new Error("Skill not found"), { status: 404 });
  const base = String(row.explanation || row.description || "");
  const hasImage = (await env.MEDIA.get(`img:${courseId}:${lessonId}:${skillId}`)) !== null;
  const hasAudio = (await env.MEDIA.get(`aud:${courseId}:${lessonId}:${skillId}`)) !== null;
  if (kind === "simpler") {
    try {
      await recordSupportSignal(env, studentId, "simpler_helped");
    } catch { /* ignore */ }
    return { kind, title: "A simpler way to see it", body: shorten(base, 420) };
  }
  if (kind === "steps") {
    const parts = base.split(/(?<=[.!?])\s+/).map((p) => p.trim()).filter(Boolean).slice(0, 5);
    const steps = parts.map((p, i) => `Step ${i + 1}: ${p}`);
    try {
      await recordSupportSignal(env, studentId, "step_helped");
    } catch { /* ignore */ }
    return { kind, title: "Broken into steps", steps: steps.length > 0 ? steps : [base] };
  }
  if (kind === "example") {
    try {
      await recordSupportSignal(env, studentId, "example_helped");
    } catch { /* ignore */ }
    return { kind, title: "An example first", body: `${row.description || ""}${base ? "\n\n" + base.slice(0, 400) : ""}`.trim() };
  }
  if (kind === "visual") {
    try {
      await recordSupportSignal(env, studentId, "visual_helped");
    } catch { /* ignore */ }
    return {
      kind, title: "Picture help", has_image: hasImage, image_alt: String(row.image_alt || ""),
      has_audio: hasAudio, key_concepts: jparse(row.key_concepts, []),
      body: "Look at the picture and the key ideas below, one at a time.",
    };
  }
  if (kind === "word") {
    return { kind, title: "Explain a word", body: "Pick a word from the lesson and ask your teacher — or try Read Aloud first.", key_concepts: jparse(row.key_concepts, []) };
  }
  if (kind === "read_aloud") {
    try {
      await recordSupportSignal(env, studentId, "audio_used");
    } catch { /* ignore */ }
    return { kind, title: "Read aloud", body: "Use the Read Aloud button to listen to this skill." };
  }
  throw Object.assign(new Error("Unknown help type"), { status: 404 });
}

export async function studentGrades(env: Env, studentId: string, classroomId?: string) {
  const rows = await q<Record<string, unknown>>(
    env.DB,
    "SELECT * FROM assessments WHERE student_id = ? AND status = 'submitted' ORDER BY created_at DESC LIMIT 200",
    studentId,
  );
  const out = [];
  for (const a of rows) {
    const bank = await q1<Record<string, unknown>>(env.DB, "SELECT * FROM question_banks WHERE id = ?", String(a.question_bank_id));
    const course = String(a.course_id || (bank ? bank.course_id : ""));
    const entry = {
      id: a.id, score: Number(a.score || 0), num_questions: jparse<string[]>(a.question_ids, []).length,
      created_at: String(a.created_at || null), course_id: course,
      lesson_id: String(a.lesson_id || (bank ? bank.lesson_id : "")), skill_id: bank ? String(bank.skill_id) : "",
      classroom_id: classroomIdFromCourse(course),
    };
    if (classroomId && entry.classroom_id !== classroomId) continue;
    out.push(entry);
  }
  return out;
}

export async function classroomMastery(env: Env, classroomId: string) {
  const students = await q<Record<string, unknown>>(
    env.DB,
    "SELECT u.id, u.name FROM users u JOIN classroom_enrollments e ON e.student_id = u.id WHERE e.classroom_id = ? ORDER BY u.name",
    classroomId,
  );
  const courseId = courseForClassroom(classroomId);
  const materials = await q<Record<string, unknown>>(env.DB, "SELECT * FROM learning_materials WHERE classroom_id = ? AND scope = 'official' ORDER BY rowid", classroomId);
  const perStudent = [];
  const totals = new Map<string, { name: string; attempted: number; students: number; mastered: number }>();
  for (const s of students) {
    const statesAll: string[] = [];
    const perSkill = [];
    for (const mat of materials) {
      const sks = await skillStatesForLesson(env, String(s.id), courseId, String(mat.id));
      for (const sk of sks) {
        statesAll.push(sk.state);
        perSkill.push({ material_id: mat.id, skill_id: sk.skill_id, name: sk.name, state: sk.state, accuracy: sk.accuracy, attempted: sk.attempted });
        const agg = totals.get(sk.skill_id) || { name: sk.name, attempted: 0, students: 0, mastered: 0 };
        agg.students++;
        agg.attempted += sk.attempted;
        if (sk.state === MASTERED) agg.mastered++;
        totals.set(sk.skill_id, agg);
      }
    }
    const grades = await studentGrades(env, String(s.id), classroomId);
    perStudent.push({
      student_id: s.id, name: s.name, summary: summarizeMastery(statesAll),
      needs_support: statesAll.includes(NEEDS_PRACTICE),
      recent_score: grades.length > 0 ? grades[0].score : null, skills: perSkill,
    });
  }
  const skillList = [...totals.entries()]
    .map(([skill_id, v]) => ({ skill_id, ...v, mastery_rate: v.students > 0 ? v.mastered / v.students : null }))
    .sort((a, b) => (a.mastery_rate === null ? 1 : b.mastery_rate === null ? -1 : a.mastery_rate - b.mastery_rate));
  return {
    classroom_id: classroomId, students: perStudent,
    needing_support: perStudent.filter((p) => p.needs_support).map((p) => ({ student_id: p.student_id, name: p.name })),
    skill_performance: skillList,
  };
}

export async function childProgress(env: Env, childId: string) {
  const rooms = await q<Record<string, unknown>>(
    env.DB, "SELECT r.* FROM classrooms r JOIN classroom_enrollments e ON e.classroom_id = r.id WHERE e.student_id = ? ORDER BY r.rowid", childId);
  const classrooms = [];
  for (const room of rooms) {
    const courseId = courseForClassroom(String(room.id));
    const skillsAll = [];
    const mats = await q<Record<string, unknown>>(env.DB, "SELECT * FROM learning_materials WHERE classroom_id = ? AND scope = 'official' ORDER BY rowid", String(room.id));
    for (const mat of mats) {
      skillsAll.push(...(await skillStatesForLesson(env, childId, courseId, String(mat.id))));
    }
    const grades = await studentGrades(env, childId, String(room.id));
    classrooms.push({
      classroom_id: room.id, name: room.name, subject: room.subject,
      summary: summarizeMastery(skillsAll.map((s) => s.state)), skills: skillsAll,
      recent_score: grades.length > 0 ? grades[0].score : null,
    });
  }
  const supp = await q<Record<string, unknown>>(env.DB, "SELECT * FROM learning_materials WHERE child_student_id = ? AND scope = 'supplementary' ORDER BY rowid", childId);
  const suppStates: string[] = [];
  for (const mat of supp) {
    const sks = await skillStatesForLesson(env, childId, courseForChild(childId), String(mat.id));
    for (const s of sks) suppStates.push(s.state);
  }
  const attempts = await q<Record<string, unknown>>(env.DB, "SELECT question_id, correct, timestamp FROM student_attempts WHERE student_id = ? ORDER BY timestamp DESC LIMIT 20", childId);
  return {
    student_id: childId, classrooms,
    supplementary_summary: summarizeMastery(suppStates),
    recent_activity: attempts.map((a) => ({ question_id: a.question_id, correct: !!a.correct, timestamp: a.timestamp || null })),
  };
}

export async function teacherOverview(env: Env, teacherId: string) {
  const rooms = await q<Record<string, unknown>>(env.DB, "SELECT * FROM classrooms WHERE teacher_id = ? ORDER BY rowid", teacherId);
  let totalStudents = 0;
  let materialsCount = 0;
  let pending = 0;
  const needing: Record<string, unknown>[] = [];
  for (const room of rooms) {
    const st = await q<Record<string, unknown>>(env.DB, "SELECT id FROM classroom_enrollments WHERE classroom_id = ?", String(room.id));
    totalStudents += st.length;
    const mats = await q<Record<string, unknown>>(env.DB, "SELECT id FROM learning_materials WHERE classroom_id = ? AND scope = 'official'", String(room.id));
    materialsCount += mats.length;
    const pb = await q<Record<string, unknown>>(env.DB, "SELECT id FROM question_banks WHERE status = 'pending_review' AND classroom_id = ?", String(room.id));
    pending += pb.length;
    const md = await classroomMastery(env, String(room.id));
    for (const p of md.needing_support as Array<Record<string, unknown>>) {
      needing.push({ classroom_id: room.id, classroom_name: room.name, ...p });
    }
  }
  return {
    classrooms: rooms.map((r) => ({ id: r.id, name: r.name, subject: r.subject, grade_level: r.grade_level, join_code: r.join_code })),
    num_classrooms: rooms.length, num_students: totalStudents, num_materials: materialsCount,
    pending_banks: pending, needing_support: needing.slice(0, 20),
  };
}
