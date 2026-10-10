import type { Env } from "./env";

// ---------------------------------------------------------------------------
// Provider chain: Groq (OpenAI-compatible fetch) -> one OpenRouter failover
// on retryable errors -> deterministic grounded fallbacks. Mirrors
// sahlha/app/agent/llm.py behavior; temperature 0.4, 2000 tokens,
// json_object response format, 60s timeout.
// ---------------------------------------------------------------------------

export function resolveProvider(env: Env): { provider: string; key: string; model: string } {
  if (env.GROQ_API_KEY) return { provider: "groq", key: env.GROQ_API_KEY, model: env.GROQ_MODEL || "openai/gpt-oss-120b" };
  if (env.OPENROUTER_API_KEY)
    return { provider: "openrouter", key: env.OPENROUTER_API_KEY, model: env.OPENROUTER_MODEL || "openai/gpt-4o-mini" };
  if (env.OPENAI_API_KEY) return { provider: "openai", key: env.OPENAI_API_KEY, model: "gpt-4o-mini" };
  return { provider: "", key: "", model: "" };
}

export function llmAvailable(env: Env): boolean {
  return resolveProvider(env).provider !== "";
}

const NON_RETRY = ["invalid api key", "unauthorized", "forbidden", "invalid_request", "validation"];
const RETRY_PHRASES = [
  "rate limit", "rate_limit", "quota", "exhausted", "overloaded", "unavailable",
  "timeout", "timed out", "connection", "temporarily", "try again", "capacity",
  "over capacity", "5xx", "provider", "429", "abort",
  "model_not_found", "does not exist", "decommissioned", "failed to validate json", "json_validate_failed",
];

export function isRetryable(msg: string, status?: number): boolean {
  const m = (msg || "").toLowerCase();
  if (status === 429 || (status !== undefined && status >= 500 && status <= 599)) return true;
  if (status === 408) return true;
  if (status !== undefined && status >= 400 && status < 500) {
    if (status === 404 && m.includes("model")) return true;
    return false;
  }
  if (RETRY_PHRASES.some((p) => m.includes(p))) {
    if (NON_RETRY.some((n) => m.includes(n))) return false;
    return true;
  }
  return false;
}

async function chatOnce(baseUrl: string, key: string, model: string, system: string, user: string): Promise<string> {
  // Long timeout: reasoning models (gpt-oss) can think for a while on big
  // prompts. Waiting on fetch does not consume CPU-time budget.
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), 110_000);
  try {
    const r = await fetch(`${baseUrl.replace(/\/$/, "")}/chat/completions`, {
      method: "POST",
      headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        model,
        messages: [
          { role: "system", content: system },
          { role: "user", content: user },
        ],
        temperature: 0.4,
        max_tokens: 2000,
        response_format: { type: "json_object" },
      }),
      signal: ctrl.signal,
    });
    if (!r.ok) {
      const text = await r.text().catch(() => "");
      throw new Error(`provider error code: ${r.status} ${text.slice(0, 200)}`);
    }
    const data = (await r.json()) as { choices?: Array<{ message?: { content?: string } }> };
    return data.choices?.[0]?.message?.content || "{}";
  } finally {
    clearTimeout(t);
  }
}

export async function callLlm(env: Env, system: string, user: string): Promise<{ text: string; backend: string }> {
  const { provider, key, model } = resolveProvider(env);
  if (provider === "groq") {
    try {
      const text = await chatOnce(env.GROQ_BASE_URL || "https://api.groq.com/openai/v1", key, model, system, user);
      return { text, backend: "groq" };
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      const m = /error code:\s*(\d+)/i.exec(msg);
      const status = m ? parseInt(m[1], 10) : undefined;
      if (isRetryable(msg, status) && env.OPENROUTER_API_KEY) {
        const text = await chatOnce(
          env.OPENROUTER_BASE_URL || "https://openrouter.ai/api/v1",
          env.OPENROUTER_API_KEY,
          env.OPENROUTER_MODEL || "openai/gpt-4o-mini",
          system,
          user,
        );
        return { text, backend: "openrouter" };
      }
      throw e;
    }
  }
  if (provider === "openrouter") {
    const text = await chatOnce(env.OPENROUTER_BASE_URL || "https://openrouter.ai/api/v1", key, model, system, user);
    return { text, backend: "openrouter" };
  }
  if (provider === "openai") {
    const text = await chatOnce("https://api.openai.com/v1", key, model, system, user);
    return { text, backend: "openai" };
  }
  throw new Error("no-llm-configured");
}

export function extractJsonArray(text: string): unknown[] {
  const t = text.trim();
  try {
    const data = JSON.parse(t);
    if (Array.isArray(data)) return data;
    if (data && typeof data === "object") {
      for (const k of ["questions", "question_bank", "items", "data"]) {
        if (Array.isArray((data as Record<string, unknown>)[k])) return (data as Record<string, unknown>)[k] as unknown[];
      }
      return [data];
    }
  } catch { /* fall through */ }
  const m = /\[.*\]/s.exec(t);
  if (m) return JSON.parse(m[0]);
  throw new Error("LLM did not return parseable JSON");
}

export function extractJsonObject(text: string): Record<string, unknown> {
  const t = text.trim();
  try {
    const data = JSON.parse(t);
    if (data && typeof data === "object" && !Array.isArray(data)) return data as Record<string, unknown>;
    if (Array.isArray(data) && data.length > 0) return data[0] as Record<string, unknown>;
  } catch { /* fall through */ }
  const m = /\{.*\}/s.exec(t);
  if (m) return JSON.parse(m[0]);
  throw new Error("LLM did not return parseable JSON");
}

// ---------------------------------------------------------------------------
// Prompts (verbatim port of sahlha/app/agent/prompts.py)
// ---------------------------------------------------------------------------

export const QUESTION_SYSTEM = `You are Sahlha, a careful teacher writing a question bank GROUNDED ONLY in the retrieved lesson context.

CORE PRINCIPLE: The presence of information in the source does NOT make it a valid learning objective.
A fact being present is necessary for grounding but NOT sufficient for a good question.

STEP 1 — IDENTIFY THE CENTRAL EDUCATIONAL TOPIC:
Before writing any question, determine what the student is actually expected to learn
(concepts, definitions, processes, relationships, procedures, principles). Ignore incidental text.

CONTEXT HIERARCHY:
HIGH PRIORITY (ask about these): learning objectives, concepts, definitions, processes,
relationships, procedures, principles, and examples that teach the concept.
LOW PRIORITY / INCIDENTAL (NEVER ask about these unless the lesson explicitly teaches them):
document metadata, teacher/author names, school/university names, dates that are not taught
as chronology, page numbers, references/citations, formatting or document-structure text,
administrative notes, unrelated surrounding text.

A VALID QUESTION MUST:
- Assess the requested skill (not a neighboring skill, not trivia).
- Be a realistic question a teacher could actually ask a student about this topic.
- Test meaningful understanding (concept, mechanism, use, distinction, application).
- Be answerable using ONLY the provided educational material, with the correct answer
  directly supported by the instructional content (supported-by-source, not inference, never invented).
- Use only knowledge from the material; do not require outside facts unless the skill demands it.

FORBIDDEN — DO NOT:
- Test document metadata: teacher/author names, school names, dates that are incidental,
  page numbers, formatting, references.
- Test arbitrary wording ("which word appears in sentence 3?") or create artificial
  scenarios unrelated to the lesson.
- Invent facts, options, or explanations not supported by the context.
- Write "gotcha" or trick questions, or questions merely because a sentence exists
  ("The text mentions X, so ask about X").
- Pad to reach the requested count. Generate UP TO the requested number of GOOD
  questions; if the material only supports fewer, return fewer. Never invent fillers.

RELEVANCE TEST (apply silently to every candidate; reject on any NO):
1. What is the educational topic? 2. What is the learning objective of this skill?
3. How does this question assess that objective? 4. Is this something the student is
expected to learn? 5. Would a teacher reasonably ask this? 6. Is the tested
information instructional content rather than incidental document information?
7. Is the correct answer directly supported by the instructional content?

OVER-FILTERING GUARD: Do NOT blindly ignore names/dates/numbers/places.
A name IS valid if the lesson is about that person; a date IS valid if the lesson
teaches chronology; a place IS valid for geography; a formula/number/term IS valid
if it is part of the lesson. Rule: ignore information INCIDENTAL to the learning objective.

GROUNDING LEVELS: (a) supported by source — quoteable/entailable, USE THIS ONLY;
(b) reasonable inference — do NOT base correct answers on it; (c) unsupported/invented — FORBIDDEN.

BAD EXAMPLE — Source: "Photosynthesis is the process by which plants convert light energy
into chemical energy. Prepared by Ahmed Hassan."
Do NOT create: "Who prepared the lesson?" / "What is the teacher's name?"
GOOD: "What happens during photosynthesis?" / "What role does light energy play in photosynthesis?"
BAD EXAMPLE — Source: Python elif lesson ending with "Prepared by Mr. Karim, Al-Noor School, page 4."
Do NOT create: "Who prepared the elif lesson?" / "Which school is named on page 4?"
GOOD: "When does the elif branch execute?" / "What happens when no if/elif condition matches?"

- Mix easy/medium/hard; 4 options, correct_answer is 0-based index.
- Cover different key concepts of the SKILL; follow teacher feedback if any.
Return ONLY JSON array of {skill_id, type:"multiple_choice", question, options[4], correct_answer, explanation, difficulty}.`;

export const SKILL_EXTRACTION_SYSTEM = `You are Sahlha. Split a lesson into skills — one per genuine TEACHING UNIT, not one per sentence or chunk.

CORE PRINCIPLE: The presence of information in the source does NOT make it a valid learning objective.
A skill must represent meaningful knowledge, a concept, procedure, relationship, or ability
the student is actually expected to learn — not anything that merely appears in the document.

STEP 1 — IDENTIFY THE CENTRAL EDUCATIONAL TOPIC FIRST:
Read all context, decide what the lesson is actually teaching, then extract skills ONLY from that topic.

WHAT COUNTS AS A SKILL (all must hold):
- Represents an actual educational concept or ability tied to the lesson/topic.
- Is an appropriate learning unit: independently learnable and testable, specific enough
  to teach and to write questions about (not too broad, not single-word trivia).
- Is directly supported by the instructional content (definitions, processes, examples that teach).

WHAT IS NEVER A SKILL (reject even if prominent in the text):
- Document metadata: teacher/author names, school/university names, dates that are not
  taught content, page numbers, references/citations, formatting or document-structure text.
- Administrative notes, unrelated surrounding text, or unrelated examples unless the example
  itself teaches the concept.
- Arbitrary facts that happen to appear (e.g. "lesson prepared by X" is NOT a skill).

CONTEXT HIERARCHY:
HIGH PRIORITY: learning objectives, concepts, definitions, processes, relationships,
procedures, principles, examples that teach the concept.
LOW PRIORITY / INCIDENTAL: metadata, author/teacher info, formatting, admin info, references.

RELEVANCE TEST (apply to every candidate; reject on any NO):
1. What is the educational topic? 2. What learning objective does this skill represent?
3. How does it relate to the topic? 4. Is the student actually expected to learn this?
5. Would a teacher reasonably teach/assess this? 6. Is it instructional content rather
than incidental document information? 7. Is it supported by the instructional content?

OVER-FILTERING GUARD: Do NOT blindly drop names/dates/numbers/places. A person's name IS a
valid skill focus if the lesson is about that person; a date IS valid if the lesson teaches
chronology; a place IS valid for geography; a formula/number/term IS valid if taught.
Rule: ignore information INCIDENTAL to the intended learning objective.

COUNT: You decide the number (up to the max). Prefer fewer, sharper skills over padding.
If only part of the context is instructional, extract skills ONLY from that part — return
fewer skills rather than inventing skills from metadata. Never pad to reach the maximum.

BAD EXAMPLE — Source: "Photosynthesis is the process by which plants convert light energy into chemical energy. Prepared by Ahmed Hassan."
Do NOT create: {"skill_id": "identify_ahmed_hassan", ...} or {"skill_id": "lesson_preparation", ...}.
GOOD: {"skill_id": "photosynthesis_basics", "name": "Explain the basic process of photosynthesis", ...},
{"skill_id": "light_energy_role", "name": "Identify the role of light energy in photosynthesis", ...}.
BAD EXAMPLE — Source: Python elif lesson + "Prepared by Mr. Karim, Al-Noor School, page 4, refs."
Do NOT create skills about Mr. Karim, Al-Noor School, page 4, or the reference list.
GOOD: skills about elif branch ordering, first-true-branch-wins, else fallback.

- skill_id: snake_case slug grounded in the CONCEPT (not in metadata); key_concepts: 3-6 phrases from the INSTRUCTIONAL material (never metadata).
Return ONLY JSON: {"skills": [{"skill_id": ..., "name": ..., "description": ..., "key_concepts": [...]}]}.`;

export const SKILL_EXPLANATION_SYSTEM = `You are Sahlha. Write 150-300 word student explanation of ONE skill, grounded ONLY in the instructional context.

CORE PRINCIPLE: Presence in the source does NOT make content teachable. Explain the SKILL's
concept using HIGH-PRIORITY material (definitions, processes, examples that teach). Ignore
LOW-PRIORITY incidental text (teacher/author/school names, page numbers, dates, references,
formatting, admin notes) — never present metadata as lesson content.
Structure: intro, how it works, example from material, common mistake.
If the retrieved material is mostly metadata with little instructional content about the skill,
say what the material does establish and do NOT invent details or pad with metadata.
Return ONLY JSON: {"explanation": "..."}.`;

export const LESSON_EXPLANATION_SYSTEM = `You are Sahlha. Write lesson overview grounded ONLY in instructional context.

CORE PRINCIPLE: Presence in the source does NOT make content teachable. Base the overview on
HIGH-PRIORITY material (concepts, definitions, processes, relationships in order, how skills
connect, outcome). Ignore LOW-PRIORITY incidental text (teacher/author/school names, dates
unless taught as chronology, page numbers, references, formatting, admin notes).
Structure: what lesson is about (2-3s), main ideas in order, how skills connect, outcome. Plus 4-8 key_concepts from instructional content only.
Return ONLY JSON: {"title": "...", "explanation": "...", "key_concepts": [...]}.`;

export const CRITIQUE_SYSTEM = `You are Sahlha critic. For each question judge THREE things:
1. grounded — is the correct answer directly supported by the INSTRUCTIONAL material
   (not merely by incidental text, not invented, not outside knowledge)?
2. answer_correct — is the marked answer actually correct per the material?
3. relevant — is this a meaningful educational question a teacher would reasonably ask
   about the topic (tests a concept/process/relationship), rather than trivia about
   incidental information (teacher/author/school names, dates that are not taught content,
   page numbers, references, formatting, arbitrary wording, artificial scenarios, gotchas)?

CORE PRINCIPLE: A fact being present in the source is NECESSARY but NOT SUFFICIENT.
A question like "Who prepared the lesson? (Ahmed Hassan)" is GROUNDED but NOT RELEVANT — mark relevant=false.
Similarly "Which school is named on page 4?" or "What page mentions elif?" are grounded-but-irrelevant.

OVER-FILTERING GUARD: A name/date/place/number IS relevant when the lesson actually teaches it
(e.g. lesson about a historical figure, chronology, geography, a taught formula). Mark
relevant=true only when the tested fact is part of the intended learning objective.

Return ONLY JSON: {"verdicts": [{"index":0,"grounded":true,"answer_correct":true,"relevant":true,"issue":""}]} one per question in order. Put a 1-sentence reason in issue whenever any flag is false.`;

// ---------------------------------------------------------------------------
// Deterministic grounded fallbacks (port of llm.py fallback_*)
// ---------------------------------------------------------------------------

export interface Chunk {
  chunk_id: string;
  text: string;
  score: number;
  document_id?: string;
  course_id?: string;
  lesson_id?: string;
  skill_id?: string;
  page?: number;
  chunk_index?: number;
}

export function splitSentences(text: string): string[] {
  return (text || "").split(/(?<=[.!?])\s+/).map((s) => s.trim()).filter(Boolean);
}

export function longSentences(chunks: Array<{ text?: string } | string>, minWords = 6): string[] {
  const out: string[] = [];
  for (const t of chunks) {
    const body = typeof t === "string" ? t : t.text || "";
    for (const s of splitSentences(body)) {
      if (s.split(/\s+/).length >= minWords) out.push(s);
    }
  }
  return out;
}

const INCIDENTAL_RE =
  /(prepared\s+by|written\s+by|authored\s+by|teacher\s*:|instructor\s*:|author\s*:|\bschool\b|\buniversity\b|\bcollege\b|\binstitute\b|\bacademy\b|page\s*\d+|\bp\.?\s*\d+\b|table\s+of\s+contents|\breferences?\b|\bbibliography\b|all\s+rights\s+reserved|copyright\s*©|submitted\s+(by|to)|roll\s*(no|number)|\bdate\s*:)/i;

const METADATA_Q_RE =
  /(who\s+(prepared|wrote|authored|teaches?)|teacher'?s?\s+name|author'?s?\s+name|which\s+school|school'?s?\s+name|university\s+name|what\s+page|which\s+page|page\s+number|reference\s+(list|number)|\bprepared\s+by\b)/i;

const INSTR_VERB_RE =
  /\b(is|are|means?|defines?|explains?|describes?|causes?|converts?|controls?|executes?|runs?|checks?|tests?|uses?|requires?|produces?|process|example|because|when|if\b)/i;

export function isIncidentalSentence(sent: string): boolean {
  const s = (sent || "").trim();
  if (!s) return true;
  if (!INCIDENTAL_RE.test(s)) return false;
  const words = s.split(/\s+/);
  if (words.length <= 20) return true;
  return !INSTR_VERB_RE.test(s);
}

export function instructionalSentences(chunks: Chunk[]): Array<{ s: string; skill?: string }> {
  const out: Array<{ s: string; skill?: string }> = [];
  for (const c of chunks) {
    for (const s of splitSentences(c.text || "")) {
      if (s.split(/\s+/).length >= 6 && !isIncidentalSentence(s)) out.push({ s, skill: c.skill_id });
    }
  }
  return out;
}

const STOP = new Set(
  "this that with from have will when what does uses using into such than then them they their about after also program example lesson prepared teacher author school university college institute academy reference references bibliography edited written authored submitted".split(
    " ",
  ),
);

function topTerms(sentences: string[], k = 6): string[] {
  const counts = new Map<string, number>();
  for (const s of sentences) {
    for (const w of s.replace(/[^a-zA-Z ]/g, "").toLowerCase().split(/\s+/)) {
      if (w.length > 4 && !STOP.has(w)) counts.set(w, (counts.get(w) || 0) + 1);
    }
  }
  return [...counts.entries()].sort((a, b) => b[1] - a[1]).slice(0, k).map(([w]) => w);
}

function cap1(s: string): string {
  return s ? s[0].toUpperCase() + s.slice(1) : s;
}

export interface DraftQuestion {
  skill_id: string;
  type: string;
  question: string;
  options: string[];
  correct_answer: number;
  explanation: string;
  difficulty: string;
}

export function fallbackQuestions(chunks: Chunk[], skillId: string, n = 8, feedback = ""): DraftQuestion[] {
  if (!chunks || chunks.length === 0) return [];
  const usable: Array<{ s: string; sk: string }> = [];
  for (const c of chunks) {
    for (const s of splitSentences(c.text || "")) {
      if (s.split(/\s+/).length >= 6) usable.push({ s, sk: c.skill_id || skillId });
    }
  }
  let sentences = usable.filter(({ s }) => !isIncidentalSentence(s));
  if (sentences.length === 0) {
    if (usable.length > 0) return [];
    sentences = [{ s: "The lesson introduces key concepts and examples.", sk: skillId }];
  }
  const fb = (feedback || "").toLowerCase();
  const wantsHard = fb.includes("hard") || fb.includes("difficult") || fb.includes("practical");
  const difficulties = wantsHard ? ["medium", "hard", "medium", "hard"] : ["easy", "medium", "easy", "medium", "hard", "medium"];
  const out: DraftQuestion[] = [];
  for (let i = 0; i < n; i++) {
    const { s: sent, sk } = sentences[i % sentences.length];
    const words = sent.split(/\s+/);
    const cands = words.map((w) => w.replace(/[,.;:()"']/g, "")).filter((w) => w.length > 4);
    let keyword = "concept";
    for (const w of cands) if (w.length > keyword.length) keyword = w;
    const stem = sent.includes(keyword) ? sent.replace(keyword, "_____") : sent;
    const correct = `${keyword} — as stated in the lesson`;
    const distractors = [
      "It is unrelated to the lesson topic",
      "The lesson explicitly contradicts this",
      "This is never mentioned in the material",
    ];
    let options = [correct, ...distractors];
    const rot = i % 4;
    options = [...options.slice(rot), ...options.slice(0, rot)];
    out.push({
      skill_id: sk,
      type: "multiple_choice",
      question: `Based on the lesson, complete the statement: ${stem}`,
      options,
      correct_answer: options.indexOf(correct),
      explanation: `Grounded in lesson text: "${sent.slice(0, 160)}"`,
      difficulty: difficulties[i % difficulties.length],
    });
  }
  return out;
}

export interface DraftSkill {
  skill_id: string;
  name: string;
  description: string;
  key_concepts: string[];
}

export function fallbackSkills(chunks: Chunk[], lessonId: string, maxSkills = 6): DraftSkill[] {
  if (!chunks || chunks.length === 0) return [];
  const sentences = longSentences(chunks.map((c) => c.text || "")).filter((s) => !isIncidentalSentence(s));
  if (sentences.length === 0) return [];
  const k = Math.max(1, Math.min(maxSkills, Math.floor((sentences.length + 1) / 2)));
  const size = Math.max(1, Math.ceil(sentences.length / k));
  const out: DraftSkill[] = [];
  for (let i = 0; i < k; i++) {
    const part = sentences.slice(i * size, (i + 1) * size);
    if (part.length === 0) break;
    const terms = topTerms(part);
    const slug = ((terms[0] || `part${i + 1}`).toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "") || `part${i + 1}`);
    out.push({
      skill_id: `${lessonId}__${slug}`.slice(0, 120),
      name: `${terms[0] ? cap1(terms[0]) : `Part ${i + 1}`} (${lessonId})`,
      description: part[0].slice(0, 220),
      key_concepts: terms.slice(0, 5),
    });
  }
  return out;
}

export function fallbackExplanation(skill: { name?: string; skill_id?: string; description?: string }, chunks: Chunk[]): string {
  const sentences = longSentences(chunks.map((c) => c.text || "")).filter((s) => !isIncidentalSentence(s));
  const pool = sentences.length > 0 ? sentences : longSentences([skill.description || ""]);
  if (pool.length === 0) {
    return `${skill.name || skill.skill_id}: key lesson concept. Review the uploaded material for details and examples.`;
  }
  const intro = pool[0];
  const example = pool.slice(1).find((s) => /example|e\.g\.|for instance|:|if |when /i.test(s));
  const extra = pool.slice(1, 4).filter((s) => s !== example);
  const parts = [`${skill.name || skill.skill_id}: ${intro}`];
  if (extra.length > 0) parts.push("Key points: " + extra.join(" "));
  if (example) parts.push(`Example from the material: ${example}`);
  parts.push("Common mistake to avoid: confusing this with neighboring concepts — re-check the exact wording in the lesson.");
  return parts.join("\n\n");
}

export function fallbackLessonExplanation(
  chunks: Chunk[],
  lessonId: string,
  skillNames: string[] = [],
): { title: string; explanation: string; key_concepts: string[] } {
  const sentences = longSentences(chunks.map((c) => c.text || "")).filter((s) => !isIncidentalSentence(s));
  if (sentences.length === 0) {
    return {
      title: lessonId.replace(/_/g, " ").replace(/\b\w/g, (c) => c.toUpperCase()),
      explanation: `This lesson (${lessonId}) introduces its key concepts step by step. Study each skill below, then attempt the exercise.`,
      key_concepts: skillNames,
    };
  }
  const terms = topTerms(sentences, 8);
  const title = terms.length > 0 ? `${cap1(terms[0])} ${terms[1] || "basics"}` : lessonId;
  const about = sentences.slice(0, 2).join(" ");
  const ideas = sentences.slice(2, 5).join(" ");
  const parts = [`In this lesson: ${about}`];
  if (ideas) parts.push(`Main ideas: ${ideas}`);
  if (skillNames.length > 0) parts.push("You will work through these skills in order: " + skillNames.join(", ") + ".");
  parts.push("After studying each skill explanation below, you will be ready for the exercise.");
  return { title, explanation: parts.join("\n\n"), key_concepts: terms.slice(0, 8) };
}

export interface CritVerdict {
  index: number;
  grounded: boolean;
  answer_correct: boolean;
  relevant: boolean;
  issue: string;
}

export function fallbackCritique(questions: DraftQuestion[], chunks: Chunk[]): CritVerdict[] {
  const vocab = new Set<string>();
  for (const c of chunks) {
    for (const w of (c.text || "").replace(/[^a-zA-Z ]/g, "").toLowerCase().split(/\s+/)) {
      if (w.length > 4) vocab.add(w);
    }
  }
  const instrVocab = new Set<string>();
  for (const { s } of instructionalSentences(chunks)) {
    for (const w of s.replace(/[^a-zA-Z ]/g, "").toLowerCase().split(/\s+/)) {
      if (w.length > 4) instrVocab.add(w);
    }
  }
  return questions.map((q, i) => {
    const qterms = new Set(
      (q.question || "").replace(/[^a-zA-Z ]/g, "").toLowerCase().split(/\s+/).filter((w) => w.length > 4),
    );
    const overlap = [...qterms].filter((w) => vocab.has(w)).length;
    const grounded = overlap >= 2;
    let answerOk = true;
    if (q.type === "multiple_choice") {
      answerOk = Number.isInteger(q.correct_answer) && q.correct_answer >= 0 && q.correct_answer < q.options.length;
    }
    const isMeta = METADATA_Q_RE.test(q.question || "");
    const instrOverlap = [...qterms].filter((w) => instrVocab.has(w)).length;
    const relevant = !isMeta && instrOverlap >= 2;
    let issue = "";
    if (!grounded) issue = `shares only ${overlap} significant terms with the lesson material`;
    else if (!relevant) {
      issue = isMeta
        ? "tests incidental document metadata, not the learning objective"
        : `shares only ${instrOverlap} terms with instructional content; pedagogically irrelevant trivia`;
    } else if (!answerOk) issue = "correct_answer index is out of range";
    return { index: i, grounded, answer_correct: answerOk, relevant, issue };
  });
}

export async function generateQuestionsLlm(
  env: Env,
  system: string,
  user: string,
  chunks: Chunk[],
  skillId: string,
  n: number,
  feedback = "",
): Promise<{ questions: DraftQuestion[]; backend: string }> {
  if (llmAvailable(env)) {
    try {
      const { text, backend } = await callLlm(env, system, user);
      return { questions: extractJsonArray(text) as DraftQuestion[], backend };
    } catch (e) {
      return { questions: fallbackQuestions(chunks, skillId, n, feedback), backend: `fallback(llm-error: ${e instanceof Error ? e.message.slice(0, 120) : e})` };
    }
  }
  return { questions: fallbackQuestions(chunks, skillId, n, feedback), backend: "fallback(no-api-key)" };
}

export async function completeJson(
  env: Env,
  system: string,
  user: string,
): Promise<{ data: unknown; backend: string }> {
  if (!llmAvailable(env)) throw new Error("no-llm-configured");
  const { text, backend } = await callLlm(env, system, user);
  return { data: extractJsonObject(text), backend };
}
