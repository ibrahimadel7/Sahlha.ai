import type { Env } from "./env";
import { insertMany, q } from "./db";
import { isIncidentalSentence, splitSentences, type Chunk } from "./llm";
import { jparse, jstr, uid } from "./util";

// ---------------------------------------------------------------------------
// Chunking: sentence-aware 800/120 packer (port of rag/chunking.py).
// ---------------------------------------------------------------------------

export function cleanText(t: string): string {
  return (t || "").replace(/\s+/g, " ").trim();
}

export function chunkText(text: string, chunkSize = 800, overlap = 120): string[] {
  const cleaned = cleanText(text);
  if (!cleaned) return [];
  const sentences = splitSentences(cleaned);
  const out: string[] = [];
  let cur: string[] = [];
  let curLen = 0;
  const push = () => {
    if (cur.length > 0) {
      out.push(cur.join(" "));
      // overlap: carry trailing sentences covering ~overlap chars
      let acc = 0;
      const carry: string[] = [];
      for (let i = cur.length - 1; i >= 0 && acc < overlap; i--) {
        carry.unshift(cur[i]);
        acc += cur[i].length + 1;
      }
      cur = carry;
      curLen = carry.join(" ").length;
    }
  };
  for (const s of sentences) {
    if (s.length > chunkSize) {
      push();
      // hard-split monster sentences
      for (let i = 0; i < s.length; i += chunkSize) out.push(s.slice(i, i + chunkSize));
      cur = [];
      curLen = 0;
      continue;
    }
    if (curLen + s.length + 1 > chunkSize && cur.length > 0) push();
    cur.push(s);
    curLen += s.length + 1;
  }
  push();
  return out.filter(Boolean);
}

// ---------------------------------------------------------------------------
// Embeddings via Workers AI (bge-m3, multilingual, 1024-d).
// ---------------------------------------------------------------------------

export async function embedTexts(env: Env, texts: string[]): Promise<number[][]> {
  const model = env.EMBEDDING_MODEL || "@cf/baai/bge-m3";
  const out: number[][] = [];
  for (let i = 0; i < texts.length; i += 16) {
    const part = texts.slice(i, i + 16);
    const r = (await env.AI.run(model as never, { text: part } as never)) as unknown as {
      data?: number[][];
    };
    const vecs = r.data || [];
    for (const v of vecs) {
      const n = Math.sqrt(v.reduce((a, x) => a + x * x, 0)) || 1;
      out.push(v.map((x) => x / n));
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// Chunk persistence + scoped cosine/MMR search over D1.
// Retrieval is always lesson-scoped in the hot paths; scoped queries with
// zero rows return [] (never leak across lessons).
// ---------------------------------------------------------------------------

export interface StoredChunk extends Chunk {
  id: string;
}

export async function persistChunks(
  env: Env,
  docId: string,
  courseId: string,
  lessonId: string,
  chunks: string[],
): Promise<{ ids: string[]; count: number }> {
  const vecs = await embedTexts(env, chunks.length > 0 ? chunks : [""]);
  const now = new Date().toISOString();
  void now;
  const rows: unknown[][] = [];
  const ids: string[] = [];
  chunks.forEach((text, i) => {
    const id = uid() + i.toString(36);
    ids.push(id);
    rows.push([id, docId, courseId, lessonId, "general", 0, i, text, jstr(vecs[i] || [])]);
  });
  await insertMany(
    env.DB,
    "document_chunks",
    ["id", "document_id", "course_id", "lesson_id", "skill_id", "page", "chunk_index", "text", "embedding"],
    rows,
    6,
  );
  return { ids, count: chunks.length };
}

function cosine(a: number[], b: number[]): number {
  let s = 0;
  const n = Math.min(a.length, b.length);
  for (let i = 0; i < n; i++) s += a[i] * b[i];
  return s;
}

function mmr(query: number[], cands: Array<{ v: number[] }>, topK: number, lambda = 0.7): number[] {
  const picked: number[] = [];
  const sims = cands.map((c) => cosine(query, c.v));
  while (picked.length < Math.min(topK, cands.length)) {
    let best = -1;
    let bestScore = -Infinity;
    for (let i = 0; i < cands.length; i++) {
      if (picked.includes(i)) continue;
      let maxSim = 0;
      for (const p of picked) maxSim = Math.max(maxSim, cosine(cands[i].v, cands[p].v));
      const score = lambda * sims[i] - (1 - lambda) * maxSim;
      if (score > bestScore) {
        bestScore = score;
        best = i;
      }
    }
    if (best < 0) break;
    picked.push(best);
  }
  return picked;
}

export async function searchChunks(
  env: Env,
  queryText: string,
  topK: number,
  courseId?: string,
  lessonId?: string,
  skillId?: string,
): Promise<StoredChunk[]> {
  let sql = "SELECT id, document_id, course_id, lesson_id, skill_id, page, chunk_index, text, embedding FROM document_chunks";
  const conds: string[] = [];
  const params: unknown[] = [];
  if (courseId) {
    conds.push("course_id = ?");
    params.push(courseId);
  }
  if (lessonId) {
    conds.push("lesson_id = ?");
    params.push(lessonId);
  }
  if (skillId) {
    conds.push("skill_id = ?");
    params.push(skillId);
  }
  if (conds.length > 0) sql += " WHERE " + conds.join(" AND ");
  sql += " ORDER BY rowid LIMIT 2000";
  const rows = await q<Record<string, unknown>>(env.DB, sql, ...params);
  if (rows.length === 0) {
    // Scoped miss: never leak across lessons. Unscoped callers get lexical fallback below.
    if (courseId || lessonId) return [];
  }
  let pool = rows;
  if (pool.length === 0) {
    pool = await q<Record<string, unknown>>(
      env.DB,
      "SELECT id, document_id, course_id, lesson_id, skill_id, page, chunk_index, text, embedding FROM document_chunks ORDER BY rowid LIMIT 2000",
    );
  }
  if (pool.length === 0) return [];
  let qv: number[];
  try {
    const vecs = await embedTexts(env, [queryText || "lesson"]);
    qv = vecs[0] || [];
  } catch {
    qv = [];
  }
  const cands = pool.map((r) => ({ r, v: jparse<number[]>(r.embedding, []) as number[] }));
  type Scored = { r: Record<string, unknown>; v: number[]; score: number };
  let ranked: Scored[];
  if (qv.length > 0 && cands.some((c) => c.v.length > 0)) {
    const idx = mmr(qv, cands.map((c) => ({ v: c.v })), Math.max(topK * 3, topK));
    ranked = idx.map((i) => ({ ...cands[i], score: cosine(qv, cands[i].v) }));
    ranked.sort((a, b) => b.score - a.score);
    // dense floor 0.05 with starvation backoff
    const kept = ranked.filter((cc) => cc.score >= 0.05);
    ranked = (kept.length > 0 ? kept : ranked.slice(0, 1)).slice(0, topK);
  } else {
    // lexical overlap last resort
    const terms = new Set((queryText || "").toLowerCase().split(/[^a-z0-9+]+/).filter((w) => w.length > 2));
    ranked = cands
      .map((c) => {
        const words = new Set(String(c.r.text || "").toLowerCase().split(/[^a-z0-9+]+/));
        let ov = 0;
        for (const t of terms) if (words.has(t)) ov++;
        return { ...c, score: ov };
      })
      .sort((a, b) => b.score - a.score)
      .slice(0, topK);
  }
  return ranked.map((c) => ({
    chunk_id: String(c.r.id),
    id: String(c.r.id),
    document_id: String(c.r.document_id),
    course_id: String(c.r.course_id),
    lesson_id: String(c.r.lesson_id),
    skill_id: String(c.r.skill_id),
    page: Number(c.r.page || 0),
    chunk_index: Number(c.r.chunk_index || 0),
    text: String(c.r.text || ""),
    score: c.score || 0,
  }));
}

export async function retrieveLesson(env: Env, courseId: string, lessonId: string, topK = 5): Promise<StoredChunk[]> {
  const hits = await searchChunks(env, `${lessonId} ${courseId}`, topK, courseId, lessonId);
  if (hits.length > 0) return hits;
  // backoff: direct scoped read (score 0), never global
  const rows = await q<Record<string, unknown>>(
    env.DB,
    "SELECT id, document_id, course_id, lesson_id, skill_id, page, chunk_index, text FROM document_chunks WHERE course_id = ? AND lesson_id = ? ORDER BY chunk_index LIMIT ?",
    courseId,
    lessonId,
    topK,
  );
  return rows.map((r) => ({
    chunk_id: String(r.id),
    id: String(r.id),
    document_id: String(r.document_id),
    course_id: String(r.course_id),
    lesson_id: String(r.lesson_id),
    skill_id: String(r.skill_id),
    page: Number(r.page || 0),
    chunk_index: Number(r.chunk_index || 0),
    text: String(r.text || ""),
    score: 0,
  }));
}

// ---------------------------------------------------------------------------
// Grounding (port of agent/grounding.py)
// ---------------------------------------------------------------------------

function sigTerms(text: string): Set<string> {
  return new Set(
    (text || "")
      .replace(/[^a-zA-Z ]/g, " ")
      .toLowerCase()
      .split(/\s+/)
      .filter((w) => w.length > 4),
  );
}

function instrTextOf(c: Chunk): string {
  const parts: string[] = [];
  for (const s of splitSentences(c.text || "")) {
    if (s.split(/\s+/).length >= 6 && !isIncidentalSentence(s)) parts.push(s);
  }
  return parts.join(" ");
}

function instrVocab(chunks: Chunk[]): Set<string> {
  const v = new Set<string>();
  for (const c of chunks) for (const w of sigTerms(instrTextOf(c))) v.add(w);
  return v;
}

function fullVocab(chunks: Chunk[]): Set<string> {
  const v = new Set<string>();
  for (const c of chunks) for (const w of sigTerms(c.text || "")) v.add(w);
  return v;
}

const META_Q_RE =
  /(who\s+(prepared|wrote|authored|teaches?)|teacher'?s?\s+name|author'?s?\s+name|which\s+school|school'?s?\s+name|university\s+name|what\s+page|which\s+page|page\s+number|reference\s+(list|number)|\bprepared\s+by\b)/i;

function bestChunksForTerms(terms: Set<string>, chunks: Chunk[], k = 2): Chunk[] {
  if (chunks.length === 0 || terms.size === 0) return [];
  const scored = chunks.map((c, idx) => {
    const iv = sigTerms(instrTextOf(c));
    let ov = 0;
    for (const t of terms) if (iv.has(t)) ov++;
    return { ov, idx };
  });
  scored.sort((a, b) => b.ov - a.ov || a.idx - b.idx);
  const top = scored.slice(0, k);
  if (scored.length > 0 && scored[0].ov >= 2) {
    const kept = top.filter((s) => s.ov >= 1).map((s) => chunks[s.idx]);
    return kept.length > 0 ? kept : [chunks[top[0].idx]];
  }
  return top.length > 0 ? [chunks[top[0].idx]] : [];
}

function evidenceForTerms(terms: Set<string>, chunk: Chunk, k = 2): string[] {
  const cands: Array<{ ov: number; s: string }> = [];
  for (const s of splitSentences(chunk.text || "")) {
    if (s.split(/\s+/).length < 6 || isIncidentalSentence(s)) continue;
    const st = sigTerms(s);
    let ov = 0;
    for (const t of terms) if (st.has(t)) ov++;
    cands.push({ ov, s });
  }
  cands.sort((a, b) => b.ov - a.ov || (a.s < b.s ? -1 : 1));
  const hit = cands.slice(0, k).filter((c) => c.ov >= 1).map((c) => c.s.slice(0, 320));
  if (hit.length > 0) return hit;
  return cands.length > 0 ? [cands[0].s.slice(0, 320)] : [];
}

export function attachSkillEvidence(raw: Record<string, unknown>[], chunks: Chunk[]): Record<string, unknown>[] {
  return (raw || []).map((rs) => {
    const s: Record<string, unknown> = { ...(rs || {}) };
    if (!s.learning_objective) {
      const desc = String(s.description || "").trim();
      const name = String(s.name || s.skill_id || "").trim();
      s.learning_objective = desc.length >= 10 ? desc : (`Understand ${name}`.trim() || "Understand the lesson concept.");
    }
    if (!s.source_chunk_ids || !s.source_evidence) {
      const text = [s.name, s.description, s.learning_objective, ((s.key_concepts as string[]) || []).join(" ")]
        .map((x) => String(x || ""))
        .join(" ");
      const terms = sigTerms(text);
      const best = bestChunksForTerms(terms, chunks, 2);
      if (!s.source_chunk_ids) s.source_chunk_ids = best.map((c) => c.chunk_id).filter(Boolean);
      if (!s.source_evidence) {
        const ev: string[] = [];
        for (const c of best) ev.push(...evidenceForTerms(terms, c, 1));
        s.source_evidence = ev.slice(0, 2);
      }
    }
    return s;
  });
}

export function attachQuestionEvidence(raw: Record<string, unknown>[], chunks: Chunk[]): Record<string, unknown>[] {
  return (raw || []).map((rq) => {
    const qd: Record<string, unknown> = { ...(rq || {}) };
    if (!qd.source_chunk_ids || !qd.source_evidence) {
      const qterms = sigTerms(`${qd.question || ""} ${((qd.options as string[]) || []).join(" ")} ${qd.explanation || ""}`);
      const best = bestChunksForTerms(qterms, chunks, 1);
      if (!qd.source_chunk_ids) qd.source_chunk_ids = best.map((c) => c.chunk_id).filter(Boolean);
      if (!qd.source_evidence) {
        const ev: string[] = [];
        for (const c of best) ev.push(...evidenceForTerms(qterms, c, 1));
        qd.source_evidence = ev.slice(0, 1);
      }
    }
    return qd;
  });
}

export function validateSkillGrounding(
  skill: Record<string, unknown>,
  chunks: Chunk[],
  courseId: string,
  lessonId: string,
): { ok: boolean; reasons: string[] } {
  const reasons: string[] = [];
  const s = skill || {};
  if (chunks.length === 0) return { ok: false, reasons: ["empty retrieval: no RAG evidence available; refusing to fabricate skills"] };
  const byId = new Map(chunks.filter((c) => c.chunk_id).map((c) => [c.chunk_id, c]));
  const refs = (s.source_chunk_ids as string[]) || [];
  const ev = (s.source_evidence as string[]) || [];
  if (refs.length === 0) reasons.push("missing source_chunk_ids: skill has no RAG references");
  if (ev.length === 0 || !ev.some((e) => String(e || "").trim())) reasons.push("missing source_evidence: skill has no quoted evidence");
  for (const cid of refs) {
    const hit = byId.get(cid);
    if (!hit) {
      reasons.push(`unknown source_chunk_id: ${JSON.stringify(cid)} not in current retrieval`);
      continue;
    }
    if (hit.course_id !== courseId || hit.lesson_id !== lessonId) {
      reasons.push(`source mismatch: chunk ${JSON.stringify(cid)} belongs to ${hit.course_id}/${hit.lesson_id}, not ${courseId}/${lessonId}`);
    }
  }
  for (const snippet of ev.map((e) => String(e || "")).filter((e) => e.trim())) {
    const norm = snippet.trim().toLowerCase().replace(/\s+/g, " ");
    let found = false;
    for (const cid of refs) {
      const hit = byId.get(cid);
      if (!hit) continue;
      const hay = (hit.text || "").toLowerCase().replace(/\s+/g, " ");
      const st = sigTerms(snippet);
      const ht = sigTerms(hit.text || "");
      let ov = 0;
      for (const t of st) if (ht.has(t)) ov++;
      if (norm && (hay.includes(norm) || ov >= 2)) {
        found = true;
        break;
      }
    }
    if (!found) {
      reasons.push(`evidence not supported by cited chunks: ${JSON.stringify(snippet.slice(0, 80))}`);
      break;
    }
  }
  const skillText = [s.name, s.description, s.learning_objective, ((s.key_concepts as string[]) || []).join(" ")]
    .map((x) => String(x || ""))
    .join(" ");
  const sterms = sigTerms(skillText);
  const instr = instrVocab(chunks);
  let overlap = 0;
  for (const t of sterms) if (instr.has(t)) overlap++;
  if (overlap < 2) {
    if (META_Q_RE.test(skillText) || isIncidentalSentence(skillText)) {
      reasons.push("irrelevant: skill tests incidental document metadata, not the learning objective");
    } else {
      reasons.push("ungrounded: skill shares <2 significant terms with instructional content");
    }
  }
  const loterms = sigTerms(String(s.learning_objective || ""));
  let loOverlap = 0;
  for (const t of loterms) if (instr.has(t)) loOverlap++;
  if (loOverlap < 2) reasons.push("unsupported learning_objective: not entailed by retrieved instructional content");
  return { ok: reasons.length === 0, reasons };
}

export function validateQuestionGrounding(
  qd: Record<string, unknown>,
  chunks: Chunk[],
  validSkillIds: Set<string>,
  courseId: string,
  lessonId: string,
): { ok: boolean; reasons: string[] } {
  const reasons: string[] = [];
  const q = qd || {};
  const skid = String(q.skill_id || "");
  if (!skid) reasons.push("missing skill_id");
  else if (validSkillIds.size > 0 && !validSkillIds.has(skid)) reasons.push(`references nonexistent skill: ${JSON.stringify(skid)}`);
  if (chunks.length === 0) return { ok: false, reasons: [...reasons, "empty retrieval: no RAG evidence available"] };
  const byId = new Map(chunks.filter((c) => c.chunk_id).map((c) => [c.chunk_id, c]));
  const refs = (q.source_chunk_ids as string[]) || [];
  const ev = (q.source_evidence as string[]) || [];
  if (refs.length === 0) reasons.push("missing source_chunk_ids");
  if (ev.length === 0 || !ev.some((e) => String(e || "").trim())) reasons.push("missing source_evidence");
  for (const cid of refs) {
    const hit = byId.get(cid);
    if (!hit) reasons.push(`unknown source_chunk_id: ${JSON.stringify(cid)} not in current retrieval`);
    else if (hit.course_id !== courseId || hit.lesson_id !== lessonId) {
      reasons.push(`source mismatch: chunk ${JSON.stringify(cid)} not in ${courseId}/${lessonId}`);
    }
  }
  for (const snippet of ev.map((e) => String(e || "")).filter((e) => e.trim())) {
    const norm = snippet.trim().toLowerCase().replace(/\s+/g, " ");
    let found = false;
    for (const cid of refs) {
      const hit = byId.get(cid);
      if (!hit) continue;
      const hay = (hit.text || "").toLowerCase().replace(/\s+/g, " ");
      const st = sigTerms(snippet);
      const ht = sigTerms(hit.text || "");
      let ov = 0;
      for (const t of st) if (ht.has(t)) ov++;
      if (norm && (hay.includes(norm) || ov >= 2)) {
        found = true;
        break;
      }
    }
    if (!found) {
      reasons.push(`evidence not supported by cited chunks: ${JSON.stringify(snippet.slice(0, 80))}`);
      break;
    }
  }
  const qtext = String(q.question || "");
  const qterms = sigTerms(`${qtext} ${((q.options as string[]) || []).join(" ")} ${q.explanation || ""}`);
  const full = fullVocab(chunks);
  let fo = 0;
  for (const t of qterms) if (full.has(t)) fo++;
  if (fo < 2) reasons.push("ungrounded: question shares <2 significant terms with retrieved material");
  const instr = instrVocab(chunks);
  let io = 0;
  for (const t of qterms) if (instr.has(t)) io++;
  if (META_Q_RE.test(qtext)) reasons.push("irrelevant: question tests incidental document metadata");
  else if (io < 2) reasons.push("irrelevant: question not supported by instructional content");
  return { ok: reasons.length === 0, reasons };
}
