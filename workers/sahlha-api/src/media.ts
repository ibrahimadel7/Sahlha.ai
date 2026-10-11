import type { Env } from "./env";
import { q1 } from "./db";
import { splitSentences } from "./llm";
import { ensureScopeExplanations } from "./agent";

// ---------------------------------------------------------------------------
// TTS: Groq Orpheus -> OpenRouter fallback, KV-cached bytes.
// Speakable text matches the Python contract: "{name}. {explanation}".
// ---------------------------------------------------------------------------

function splitForTts(text: string, max = 900): string[] {
  const out: string[] = [];
  let cur = "";
  for (const s of splitSentences(text)) {
    if ((cur + " " + s).trim().length > max) {
      if (cur.trim()) out.push(cur.trim());
      cur = s;
    } else {
      cur = (cur + " " + s).trim();
    }
  }
  if (cur.trim()) out.push(cur.trim());
  return out.length > 0 ? out : [text.slice(0, max)];
}

async function groqTts(env: Env, text: string, voice: string): Promise<{ bytes: Uint8Array; format: string } | null> {
  if (!env.GROQ_API_KEY) {
    console.error("groqTts: no GROQ_API_KEY");
    return null;
  }
  const chunks = splitForTts(text);
  const parts: Uint8Array[] = [];
  for (const ch of chunks) {
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), 110_000);
    try {
      const r = await fetch(`${(env.GROQ_BASE_URL || "https://api.groq.com/openai/v1").replace(/\/$/, "")}/audio/speech`, {
        method: "POST",
        headers: { Authorization: `Bearer ${env.GROQ_API_KEY}`, "Content-Type": "application/json" },
        body: JSON.stringify({
          model: env.GROQ_TTS_MODEL || "canopylabs/orpheus-v1-english",
          input: ch,
          voice: voice || env.GROQ_TTS_VOICE || "troy",
          response_format: "wav",
        }),
        signal: ctrl.signal,
      });
      if (!r.ok) {
        const msg = await r.text().catch(() => "");
        console.error(`groqTts ${r.status}: ${msg.slice(0, 300)}`);
        const retry = /429|5\d\d|timeout|overloaded|capacity/i.test(` ${r.status} ${msg}`);
        if (retry) return null; // fall through to OpenRouter
        throw new Error(`TTS failed: ${r.status}`);
      }
      parts.push(new Uint8Array(await r.arrayBuffer()));
    } catch (e) {
      console.error(`groqTts fetch failed: ${e instanceof Error ? e.message : String(e)}`);
      throw e;
    } finally {
      clearTimeout(t);
    }
  }
  return { bytes: stitchWav(parts), format: "wav" };
}

function findDataChunk(wav: Uint8Array): { header: Uint8Array; data: Uint8Array; fmt: Uint8Array } | null {
  if (wav.length < 44 || wav[0] !== 0x52 || wav[1] !== 0x49 || wav[2] !== 0x46 || wav[3] !== 0x46) return null;
  let off = 12;
  let fmt: Uint8Array | null = null;
  while (off + 8 <= wav.length) {
    const id = String.fromCharCode(wav[off], wav[off + 1], wav[off + 2], wav[off + 3]);
    const size = wav[off + 4] | (wav[off + 5] << 8) | (wav[off + 6] << 16) | (wav[off + 7] << 24);
    if (id === "fmt ") fmt = wav.slice(off, off + 8 + size);
    if (id === "data") {
      if (!fmt) return null;
      return { header: wav.slice(0, 12), data: wav.slice(off + 8, off + 8 + size), fmt };
    }
    off += 8 + size + (size % 2);
  }
  return null;
}

function stitchWav(parts: Uint8Array[]): Uint8Array {
  if (parts.length === 0) return new Uint8Array();
  if (parts.length === 1) return parts[0];
  const parsed = parts.map(findDataChunk).filter(Boolean) as Array<{ header: Uint8Array; data: Uint8Array; fmt: Uint8Array }>;
  if (parsed.length !== parts.length) return parts[0]; // mixed formats: keep first
  const total = parsed.reduce((a, p) => a + p.data.length, 0);
  const out = new Uint8Array(12 + parsed[0].fmt.length + 8 + total);
  out.set(parsed[0].header, 0);
  out.set(parsed[0].fmt, 12);
  const doff = 12 + parsed[0].fmt.length;
  out.set([0x64, 0x61, 0x74, 0x61], doff); // 'data'
  const dv = new DataView(out.buffer);
  dv.setUint32(doff + 4, total, true);
  let pos = doff + 8;
  for (const p of parsed) {
    out.set(p.data, pos);
    pos += p.data.length;
  }
  // fix RIFF size
  dv.setUint32(4, out.length - 8, true);
  return out;
}

async function openrouterTts(env: Env, text: string): Promise<{ bytes: Uint8Array; format: string } | null> {
  if (!env.OPENROUTER_API_KEY) {
    console.error("openrouterTts: no OPENROUTER_API_KEY");
    return null;
  }
  const chunks = splitForTts(text);
  const models = [env.OPENROUTER_TTS_MODEL || "fish-audio/s2.1-pro-free:free", "openai/gpt-4o-mini-tts"];
  const parts: Uint8Array[] = [];
  let fmt = "mp3";
  for (const ch of chunks) {
    let done = false;
    for (const model of models) {
      for (const format of ["mp3", "wav"]) {
        try {
          const ctrl = new AbortController();
          const t = setTimeout(() => ctrl.abort(), 110_000);
          try {
            const r = await fetch(`${(env.OPENROUTER_BASE_URL || "https://openrouter.ai/api/v1").replace(/\/$/, "")}/audio/speech`, {
              method: "POST",
              headers: { Authorization: `Bearer ${env.OPENROUTER_API_KEY}`, "Content-Type": "application/json" },
              body: JSON.stringify({ model, input: ch, voice: env.OPENROUTER_TTS_VOICE || "alloy", response_format: format }),
              signal: ctrl.signal,
            });
            if (r.status === 404) {
              console.error(`openrouterTts ${model}/${format}: 404`);
              continue; // try next candidate
            }
            if (!r.ok) {
              const msg = await r.text().catch(() => "");
              console.error(`openrouterTts ${model}/${format}: ${r.status} ${msg.slice(0, 300)}`);
              throw new Error(`TTS failed: ${r.status}`);
            }
            parts.push(new Uint8Array(await r.arrayBuffer()));
            fmt = format;
            done = true;
            break;
          } finally {
            clearTimeout(t);
          }
        } catch (e) {
          console.error(`openrouterTts ${model}/${format} fetch failed: ${e instanceof Error ? e.message : String(e)}`);
          continue;
        }
      }
      if (done) break;
    }
    if (!done) return null;
  }
  if (fmt === "wav") return { bytes: stitchWav(parts), format: "wav" };
  const total = parts.reduce((a, p) => a + p.length, 0);
  const out = new Uint8Array(total);
  let pos = 0;
  for (const p of parts) {
    out.set(p, pos);
    pos += p.length;
  }
  return { bytes: out, format: "mp3" };
}

function looksLikeAudio(b: Uint8Array): boolean {
  // Guard against provider stubs: a bare 44-byte WAV header (or any tiny
  // payload) is not playable audio. Minimum ~4KB of real samples.
  if (b.length < 4096) return false;
  const wav = b[0] === 0x52 && b[1] === 0x49 && b[2] === 0x46 && b[3] === 0x46;
  if (wav) {
    const p = findDataChunk(b);
    return !!p && p.data.length > 1024;
  }
  return (b[0] === 0x49 && b[1] === 0x44 && b[2] === 0x33) || (b[0] === 0xff && (b[1] & 0xe0) === 0xe0);
}

export async function skillAudio(
  env: Env,
  courseId: string,
  lessonId: string,
  skillId: string,
  voice?: string,
): Promise<{ bytes: Uint8Array; format: string; cached: boolean }> {
  const key = `aud:${courseId}:${lessonId}:${skillId}:${voice || "default"}`;
  const cached = await env.MEDIA.get(key, "arrayBuffer");
  if (cached) {
    const b = new Uint8Array(cached);
    // Never serve a poisoned stub: validate, else drop and re-synthesize.
    if (looksLikeAudio(b)) {
      return { bytes: b, format: b[0] === 0x49 || b[0] === 0xff ? "mp3" : "wav", cached: true };
    }
    await env.MEDIA.delete(key).catch(() => null);
  }
  const sk = await q1<Record<string, unknown>>(env.DB, "SELECT name, explanation FROM skills WHERE course_id = ? AND lesson_id = ? AND skill_id = ?", courseId, lessonId, skillId);
  let explanation = sk ? String(sk.explanation || "") : "";
  if (!explanation) {
    // Backfill path: banks were approved but skill explanations were never
    // generated (only extract-skills generated them). Heal best-effort, then
    // re-read; still missing => honest 404 below.
    try {
      await ensureScopeExplanations(env, courseId, lessonId);
    } catch { /* fall through to the 404 below */ }
    const again = await q1<Record<string, unknown>>(env.DB, "SELECT name, explanation FROM skills WHERE course_id = ? AND lesson_id = ? AND skill_id = ?", courseId, lessonId, skillId);
    if (again) explanation = String(again.explanation || "");
  }
  if (!sk || !explanation) throw Object.assign(new Error("No finalized explanation for this skill yet"), { status: 404 });
  const text = `${sk.name || skillId}. ${explanation}`;
  let got = await groqTts(env, text, voice || "");
  if (!got) {
    console.error("skillAudio: groqTts returned null, trying OpenRouter");
    got = await openrouterTts(env, text);
  }
  if (!got) {
    console.error("skillAudio: all TTS providers returned null");
    throw Object.assign(new Error("TTS unavailable"), { status: 503 });
  }
  if (!looksLikeAudio(got.bytes)) {
    console.error(`skillAudio: provider returned ${got.bytes.length} non-audio bytes`);
    throw Object.assign(new Error("TTS unavailable"), { status: 503 });
  }
  await env.MEDIA.put(key, got.bytes.slice().buffer as ArrayBuffer, { expirationTtl: 60 * 60 * 24 * 30 });
  return { bytes: got.bytes, format: got.format, cached: false };
}

// ---------------------------------------------------------------------------
// Lip-sync envelope: 300 RMS levels for WAV (energy), deterministic timed
// contour for MP3. Payload matches the Python contract {version:1, levels, kind}.
// ---------------------------------------------------------------------------

export function envelopeForAudio(bytes: Uint8Array, format: string): { version: number; levels: number[]; kind: string } {
  const N = 300;
  if (format === "wav") {
    const p = findDataChunk(bytes);
    if (p) {
      const dv = new DataView(p.data.buffer, p.data.byteOffset, p.data.byteLength);
      const n = Math.floor(p.data.length / 2);
      if (n > 0) {
      const levels: number[] = [];
      const per = Math.max(1, Math.floor(n / N));
      let peak = 0;
      const rms: number[] = [];
      for (let i = 0; i < N; i++) {
        let sum = 0;
        const count = Math.min(per, 4000);
        for (let j = 0; j < count; j++) {
          const idx = (i * per + j) % n;
          const v = dv.getInt16(idx * 2, true) / 32768;
          sum += v * v;
        }
        const r = Math.sqrt(sum / count);
        rms.push(r);
        if (r > peak) peak = r;
      }
      for (const r of rms) levels.push(peak > 0 ? Math.min(1, r / peak) : 0);
      if (levels.length === N) return { version: 1, levels, kind: "energy" };
      }
    }
  }
  // timed contour: smooth deterministic variation over normalized duration
  const levels: number[] = [];
  let seed = bytes.length;
  const rnd = () => {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    return seed / 0x7fffffff;
  };
  for (let i = 0; i < N; i++) {
    const t = i / N;
    levels.push(Math.min(1, Math.max(0, 0.35 + 0.35 * Math.sin(t * Math.PI * 14) * rnd() + 0.2 * rnd())));
  }
  return { version: 1, levels, kind: "timed" };
}

// ---------------------------------------------------------------------------
// Images: Pexels landscape photo per skill, KV-cached.
// ---------------------------------------------------------------------------

function buildImageQuery(name: string, concepts: string[]): string {
  const raw = `${name || ""} ${(concepts || []).join(" ")}`.toLowerCase();
  if (/(python|elif|if\s*else|function|loop|code|programming|algorithm)/.test(raw)) return "programming education technology";
  let q = `${name || ""} ${(concepts || []).slice(0, 2).join(" ")}`.replace(/\(lesson\)/gi, "").trim().slice(0, 120);
  return q || "education";
}

export async function skillImage(env: Env, courseId: string, lessonId: string, skillId: string): Promise<{ bytes: Uint8Array; alt: string; cached: boolean }> {
  const key = `img:${courseId}:${lessonId}:${skillId}`;
  const cached = await env.MEDIA.get(key, "arrayBuffer");
  if (cached) {
    const meta = await env.MEDIA.get(`${key}:meta`, "json").catch(() => null);
    return { bytes: new Uint8Array(cached), alt: String((meta as Record<string, unknown> | null)?.alt || ""), cached: true };
  }
  if (!env.PEXELS_API_KEY) throw Object.assign(new Error("Image service unavailable"), { status: 503 });
  const sk = await q1<Record<string, unknown>>(env.DB, "SELECT name, key_concepts, explanation FROM skills WHERE course_id = ? AND lesson_id = ? AND skill_id = ?", courseId, lessonId, skillId);
  if (!sk) throw Object.assign(new Error("Skill not found"), { status: 404 });
  let concepts: string[] = [];
  try {
    concepts = JSON.parse(String(sk.key_concepts || "[]"));
  } catch { /* ignore */ }
  const queries = [buildImageQuery(String(sk.name || skillId), concepts), "education technology", "learning", "school classroom"];
  for (const qq of queries) {
    try {
      const r = await fetch(`https://api.pexels.com/v1/search?query=${encodeURIComponent(qq)}&orientation=landscape&size=large&per_page=3`, {
        headers: { Authorization: env.PEXELS_API_KEY },
      });
      if (r.status === 401) throw Object.assign(new Error("Image service unavailable"), { status: 503 });
      if (!r.ok) continue;
      const data = (await r.json()) as { photos?: Array<{ src?: { large?: string }; url?: string; alt?: string; photographer?: string }> };
      const photo = (data.photos || [])[0];
      const url = photo?.src?.large;
      if (!url) continue;
      const img = await fetch(url);
      const ct = img.headers.get("content-type") || "";
      const buf = new Uint8Array(await img.arrayBuffer());
      if (!ct.startsWith("image/") || buf.length < 1024) continue;
      await env.MEDIA.put(key, buf.slice().buffer as ArrayBuffer, { expirationTtl: 60 * 60 * 24 * 30 });
      await env.MEDIA.put(`${key}:meta`, JSON.stringify({ alt: photo.alt || "", page_url: photo.url || "" }), { expirationTtl: 60 * 60 * 24 * 30 });
      await env.DB.prepare("UPDATE skills SET image_url=?, image_alt=?, updated_at=? WHERE course_id=? AND lesson_id=? AND skill_id=?")
        .bind(photo.url || "", photo.alt || "", new Date().toISOString(), courseId, lessonId, skillId).run().catch(() => null);
      return { bytes: buf, alt: photo.alt || "", cached: false };
    } catch (e) {
      if (e instanceof Error && (e as { status?: number }).status === 503) throw e;
      continue;
    }
  }
  throw Object.assign(new Error("No picture is available right now."), { status: 503 });
}
