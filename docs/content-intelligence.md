Backend content intelligence
============================

Uploads now persist ordered `DocumentBlock` data and extraction diagnostics on the
document. Native PDF extraction is evaluated per page; only sparse/poor pages take
the OCR path. DOCX body elements retain paragraph/table order, styles and logical
page metadata. PPTX uses slide order and visual shape order. Text/Markdown and PDF
layout use conservative block inference. Tesseract uses EXIF orientation, optional
OSD, grayscale/autocontrast, configurable languages, whitespace preservation and
250 DPI rendering (bounded to 150–400). Missing OCR binaries remain nonfatal at
the extraction layer, with explicit warnings and existing material failure paths.

Structure-aware ingestion retains headings with following content, code indentation,
lists, tables and formulas. Chunks include document/course/lesson, page, section ID,
index, type and continuation metadata. The configured chunk size is a soft packing
limit. Atomic blocks can reach four times that size, capped at 12,000 characters;
larger units split with explicit continuation flags. This is a conservative character
budget rather than a model-specific tokenizer. Legacy `chunk_text` remains available.

Topic discovery reads **every ordered lesson chunk**, maps each in a bounded model
request (or an extractive fallback), and merges/validates the combined candidates.
It never uses ranked top-k retrieval. `LessonContentMap` stores sections, source
summaries, concepts, definitions, examples, code, formulas, tables, facts and domain.
Missing/foreign evidence and vague names are rejected. Skills store objectives,
prerequisites, misconceptions, difficulty and evidence links. Existing skills without
evidence are refreshed on extraction; superseded rows remain stored for history,
but are hidden from active skill lists. No documents, questions or attempts are deleted.
The skill cap remains an upper bound; omitted-topic coverage is reported as a warning.

Retrieval combines dense (when installed) or TF-IDF ranking with BM25 through reciprocal
rank fusion. Embedding dimensions come from the selected model. Cache identity includes
the model backend and checks dimensions. An optional CrossEncoder reranks bounded
candidates; import, inference or malformed-score failures preserve hybrid results.
All filtering is applied before ranking. Extracted skills use their evidence IDs
within the requested course and lesson. Search results include location, type,
score and contributing retrieval sources.

Skill explanations keep the existing `explanation` field and add `learning_content`:
core idea, steps, example, mistake, understanding check, audio script and declarative
visual/playground data. The closed schema supports programming, math, science,
history, geography and language visual types. No arbitrary object keys or executable
widget logic are accepted; source snippets are display-only. Offline content uses
`visual_type: none` rather than inventing an interactive model. The existing media
generation/authentication flow still runs independently.

Questions carry internal evidence IDs, objective, tested concept and verification.
Deterministic validation checks citations, answer support, source quotes, option
uniqueness and source reconstruction. General semantic questions require the optional
LLM verifier to affirm answerability, correct answer, incorrect distractors, uniqueness,
clarity, difficulty and objective alignment. Provider failures cannot approve those
questions. The offline fallback makes unique exact-source completion MCQs with actual
lesson terms, labels them **easy**, and fails cleanly when there are too few valid items.
It does not claim to produce higher-order or hard questions. Teacher approval remains
mandatory before assessment use.

Material responses add `quality_signals`: extraction, skill/evidence coverage,
duplicate objective rate, question grounding and warnings. Not-yet-generated metrics
are null rather than a misleading failure score. Raw content maps remain internal.
SQLite startup migrations add columns/tables with defaults and retain existing data.
Reprocessing a source creates new structured chunks; old uploads are not silently
re-OCRed or rewritten during server startup.

Configuration and optional dependencies
--------------------------------------

Base installation: `pip install -r requirements.txt`.
Optional dense embeddings and reranking: `pip install -r requirements-ai.txt`.
`EMBEDDING_MODEL` selects the encoder; `DENSE_EMBEDDINGS_ENABLED=false` forces offline
TF-IDF/BM25. Enable `RERANKER_ENABLED` and set `RERANKER_MODEL` to use reranking.
`ENABLE_LLM_CRITIQUE=true` enables the semantic question verifier through the existing
Groq/OpenRouter/OpenAI provider path. Existing cross-provider failover is unchanged.

OCR requires a Tesseract binary and installed language packs; PDF OCR additionally
needs Poppler. `TESSERACT_CMD`, `POPPLER_PATH`, `OCR_LANGUAGES` and `OCR_DPI` configure
them. Native text ingestion needs neither binary. No additional layout/OCR model is
required. Models and external providers were not downloaded or called by the golden
tests; adapters are tested with deterministic fixtures.

Known limits
------------

PDF columns, rasterized tables, handwritten math and complex slide/group layouts can
still need teacher review. DOCX pages are logical because pagination depends on a
layout engine. Text quality scores are heuristics, not calibrated OCR confidence.
The offline topic mapper recognizes common programming concepts and definition subjects;
open-ended or multilingual pedagogy benefits from the configured LLM. Skill evidence
is chunk-level; broad chunks can support multiple objectives. Semantic correctness of
general questions relies on the configured verifier plus teacher approval. Existing
approved banks and mastery histories are preserved, not automatically regraded.

Regression corpus
-----------------

Topic discovery now classifies document roles before proposing skills. It excludes
contents/index entries, publication notices, author credits/biographies, prerequisites,
running headers and labels without explanatory support. Mixed instructional passages
retain teaching text while notices are removed from generation views; raw documents
remain unchanged. This applies to LLM and offline generation and is checked again
during evidence validation. Legitimate lessons about authors, copyright, physics work
or programming indexes remain eligible when they are teaching content.

Content maps record inclusion decisions and a discovery-policy version. Previously
cached skills are refreshed on the next extraction even when they already have evidence
IDs; obsolete rows are archived rather than deleted. Quality coverage uses instructional
chunks, so omitting credits or indexes does not count as missing lesson coverage.

`tests/test_content_intelligence.py` covers programming, math, science, history,
geography, DOCX, PPTX, mixed native/scanned PDF, malformed OCR, code/tables/formulas,
full coverage beyond eight chunks, meaningful/merged topics, evidence isolation,
dynamic embedding dimensions, hybrid retrieval, optional reranking and safe specs.
Run the complete backend suite with `python -m pytest tests -q`.
