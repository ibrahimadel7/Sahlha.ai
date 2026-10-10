import type { Env } from "./env";
import { run } from "./db";
import { chunkText, embedTexts } from "./rag";
import { nowIso, slug, uid } from "./util";

// ---------------------------------------------------------------------------
// Ingestion: bytes -> extract -> chunk -> embed -> persist (synchronous;
// the Workers free tier has no background workers, so small-doc ingestion
// completes inside the upload request).
// Supported: pdf (native text via unpdf), txt, md.
// docx/pptx/images need native binaries (python-docx/Tesseract) that cannot
// run on isolates -> honest 400, never a silent empty ingest.
// ---------------------------------------------------------------------------

const PDF_EXTS = new Set([".pdf"]);
const TEXT_EXTS = new Set([".txt", ".md", ""]);

function suffixOf(filename: string): string {
  const i = filename.lastIndexOf(".");
  return i >= 0 ? filename.slice(i).toLowerCase() : "";
}

export function validateUpload(filename: string, size: number, maxMb = 10): string {
  // 10MB (not the Python tier's 25MB): a whole file is buffered in the
  // 128MB isolate, so the cap protects against OOM. The client is told
  // the exact limit in the 400 message.
  const suffix = suffixOf(filename || "upload.bin");
  if (!PDF_EXTS.has(suffix) && !TEXT_EXTS.has(suffix)) {
    if ([".docx", ".pptx", ".png", ".jpg", ".jpeg", ".tiff", ".bmp"].includes(suffix)) {
      throw Object.assign(
        new Error(
          `Files of type '${suffix}' need desktop document processing (Office/OCR binaries) that the serverless tier cannot run. Please upload a searchable PDF, TXT, or Markdown file.`,
        ),
        { status: 400 },
      );
    }
    throw Object.assign(new Error(`Unsupported file type '${suffix || "?"}'. Supported: .pdf, .txt, .md`), { status: 400 });
  }
  if (size <= 0) throw Object.assign(new Error("The file is empty."), { status: 400 });
  if (size > maxMb * 1024 * 1024) throw Object.assign(new Error(`File is larger than ${maxMb} MB.`), { status: 400 });
  return suffix;
}

async function extractPdfText(bytes: Uint8Array): Promise<{ text: string; pages: number }> {
  const { extractText } = await import("unpdf");
  const pdf = await import("unpdf").catch(() => null);
  void pdf;
  const { text, totalPages } = await extractText(new Uint8Array(bytes));
  const joined = Array.isArray(text) ? (text as string[]).join("\n") : String(text || "");
  return { text: joined, pages: Number(totalPages || 0) };
}

export async function extractDocument(bytes: Uint8Array, filename: string): Promise<{ text: string; pages: number; method: string }> {
  const suffix = suffixOf(filename);
  if (TEXT_EXTS.has(suffix)) {
    const text = new TextDecoder("utf-8", { fatal: false }).decode(bytes);
    return { text, pages: 1, method: "txt" };
  }
  if (PDF_EXTS.has(suffix)) {
    const { text, pages } = await extractPdfText(bytes);
    if (text.trim().length >= 50) return { text, pages, method: "pypdf" };
    throw Object.assign(
      new Error("This scan needs text recognition (OCR), which the serverless tier cannot run. Try a searchable PDF or a smaller scan."),
      { status: 400 },
    );
  }
  throw Object.assign(new Error("Unsupported file type."), { status: 400 });
}

function firstMeaningfulLine(text: string): string {
  for (const line of (text || "").split("\n")) {
    const t = line.trim();
    if (t.length >= 3 && t.split(/\s+/).length >= 2 && !/^(page\s*\d+|table of contents)$/i.test(t)) {
      return t;
    }
  }
  return "";
}

function deriveLessonId(filename: string, text: string, provided: string): string {
  const p = (provided || "").trim();
  if (p && !["lesson_1", "general", "lesson1"].includes(p)) return slug(p);
  const stem = filename.replace(/\.[^.]+$/, "");
  let first = "";
  for (const line of (text || "").split("\n")) {
    const t = line.trim();
    if (t.length >= 3 && t.split(/\s+/).length >= 2 && !/^(page\s*\d+|table of contents)$/i.test(t)) {
      first = t;
      break;
    }
  }
  return slug(`${first} ${stem}`.trim() ? first || stem : "lesson_1");
}

function prettifyTitle(s: string): string {
  return s.replace(/_/g, " ").replace(/\b\w/g, (c) => c.toUpperCase()).slice(0, 120) || "Untitled lesson";
}

export async function ingestUpload(
  env: Env,
  fileBytes: Uint8Array,
  filename: string,
  courseId: string,
  lessonHint: string,
): Promise<{ document_id: string; lesson_id: string; course_id: string; title: string; chunk_count: number; char_count: number; method: string }> {
  const cleanCourse = courseId.startsWith("class:") || courseId.startsWith("child:")
    ? courseId
    : slug(courseId || "general", "general");
  const extracted = await extractDocument(fileBytes, filename);
  if (!extracted.text.trim()) {
    throw Object.assign(new Error("Empty file: no extractable text found (upload a non-empty pdf/txt/md file)"), { status: 400 });
  }
  const lessonId = deriveLessonId(filename, extracted.text, lessonHint);
  // Human title comes from content (first meaningful line) or filename —
  // never from the internal lesson id. lesson_id itself stays the material id
  // so AI-loop scoping (mapping.scope_for_material) keeps working.
  const stem = filename.replace(/\.[^.]+$/, "").trim() || "Untitled lesson";
  const contentTitle = firstMeaningfulLine(extracted.text);
  const title = prettifyTitle((contentTitle ? contentTitle.split(/\s+/).slice(0, 6).join(" ") : stem).slice(0, 80));
  const docId = uid();
  const now = nowIso();
  const chunks = chunkText(extracted.text, 800, 120);
  if (chunks.length === 0) {
    throw Object.assign(new Error("No readable text was found. The file may be empty or unsupported."), { status: 400 });
  }
  // Free-tier guard: every chunk costs an embedding subrequest + D1 writes,
  // and invocations are capped (50 subrequests / 50 D1 queries). ~600 chunks
  // ≈ 200KB of text, far above demo needs. Larger documents must be split.
  if (chunks.length > 600) {
    throw Object.assign(
      new Error(`This document is too large for the serverless tier (${chunks.length} sections; limit 600). Split it into smaller files.`),
      { status: 400 },
    );
  }
  await run(
    env.DB,
    "INSERT INTO documents (id, filename, course_id, lesson_id, skill_id, status, char_count, chunk_count, created_at) VALUES (?,?,?,?,?,'processed',?,?,?)",
    docId, filename.slice(0, 255), cleanCourse, lessonId, "general", extracted.text.length, chunks.length, now,
  );
  const vecs = await embedTexts(env, chunks);
  const { insertMany } = await import("./db");
  const rows: unknown[][] = [];
  chunks.forEach((text, i) => {
    rows.push([uid() + i.toString(36), docId, cleanCourse, lessonId, "general", 0, i, text, JSON.stringify(vecs[i] || [])]);
  });
  await insertMany(
    env.DB, "document_chunks",
    ["id", "document_id", "course_id", "lesson_id", "skill_id", "page", "chunk_index", "text", "embedding"],
    rows, 6,
  );
  return {
    document_id: docId, lesson_id: lessonId, course_id: cleanCourse,
    title, chunk_count: chunks.length,
    char_count: extracted.text.length, method: extracted.method,
  };
}
