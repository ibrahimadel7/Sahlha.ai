# Sahlha — Same curriculum. Different path to mastery.

Sahlha is an **adaptive learning application** for every learner — including
students who benefit from additional educational support (e.g. dyslexia, ADHD,
autism). Sahlha is **not** a medical or diagnostic product and never diagnoses
anything; it adapts *how* a learner reaches the objective, never *what* they
are expected to learn.

> Core product principle: **same curriculum, different path to mastery.**

## 1. Architecture

```text
Flutter mobile app (mobile/)              Python / FastAPI backend (sahlha/)
─────────────────────────────             ─────────────────────────────────
ALL user-facing UI:                       Auth + RBAC, users, classrooms,
onboarding, role auth,                    enrollment, parent links, materials,
student home / path / lesson /            document ownership, OCR/RAG,
practice / feedback / progress,           Sahlha AI agent, skills,
teacher dashboard / classroom /           explanations, question banks,
upload / review / analytics,              approval, assessments, grades,
parent home / child / materials           mastery, weak-skill memory,
                                          learning profiles, analytics
```

- **Flutter owns**: UI, navigation, forms, state, loading/empty/error states,
  role presentation, API communication, secure token storage.
- **FastAPI owns**: everything else — the database, RBAC, the AI/RAG agent,
  answer evaluation (server-side only), grades, mastery, adaptation.
- `streamlit_app.py` remains only as a **developer/AI debug tool**, not the
  product.

### Preserved AI / RAG engine (unchanged architecture)

Material upload → document processing / OCR → chunking → RAG → lesson
understanding → skill extraction → lesson + skill explanations → question-bank
generation → **teacher approval boundary** → assessment → student-aware question
selection (failed-retry → weak skills → unseen → difficulty balance) → answer
evaluation → attempt recording → skill performance → weak-skill memory →
adaptive future practice.

Key preserved pieces:

- `sahlha/app/agent/agent.py` — one `SahlhaAgent` state machine
  (`SKILL_EXTRACTION → … → WAITING_FOR_TEACHER → ASSESSMENT → … → ADAPTATION`)
- `sahlha/app/agent/tools/*` — the agent only touches infra through tools
- `sahlha/app/agent/llm.py` — Groq structured generation + **grounded
  deterministic fallback** (full loop works offline without an API key)
- `sahlha/app/rag/*` — ingestion, OCR interface, chunking, TF-IDF
  embeddings (swappable), cosine vector store, filtered retriever
- Question banks stay **append-only versions** (`pending_review → approved /
  rejected`); regenerating creates a new version, never overwrites history
- Correct answers **never leave the server** before submission; students get
  stripped payloads, teachers get full review payloads

### Platform extensions (new)

- **IDs**: official classroom material → `course_id = "class:{classroom_id}"`,
  `lesson_id = material.id`; supplementary child material →
  `course_id = "child:{student_id}"`; `student_id` = the student's `User.id`.
  All mapping lives in `sahlha/app/services/mapping.py`.
- **Mastery** (`sahlha/app/services/mastery.py`, thresholds in settings):
  `not_started → needs_practice (<0.6) → developing (≥0.6) → mastered
  (≥0.8 after ≥4 attempts)`.
- **Student Skill Performance** is now scoped by
  `(student_id, course_id, lesson_id, skill_id)` so identical skill slugs in
  different lessons never collide. Memory updates in the agent submit path
  resolve scope from each question's bank.
- **Per-question check**: `POST /student/assessments/{id}/check` evaluates one
  answer immediately, **locks the attempt**, and updates memory; `submit`
  reuses locked attempts (no double counting) and finalizes the grade.
- **Learning Profile**: short support-preference onboarding (one question at a
  time) + deterministic behavior adaptation (`hint_used`, `retry`,
  `struggled`, `improved`, …). Support language only.
- **Help Me**: one entry point → Make it simpler / Show an example / Read
  aloud (+ Break into steps / Show visually / Explain this word), ordered by
  the student's profile.

## 2. Roles

| Role | Capabilities |
|---|---|
| **Teacher** | Register/login, create classrooms + join codes, enroll students, upload official materials, run OCR/RAG, extract skills, review/edit skills, generate question banks, review **every** question (edit / remove / regenerate one / regenerate bank / approve / reject), monitor grades, mastery (Mastered / Developing / Needs Practice / Not Started), students needing support, class skill performance |
| **Student** | Register/login, join via code, onboarding profile, learning path, one skill at a time, adapted explanations, Help Me, Read Aloud (when TTS available), practice, assessments with immediate feedback, grades, progress |
| **Parent** | Register/login, link children via **parent link code** (no IDs), child progress/grades/activity, supplementary material upload (private, never touches official curriculum/grades) |
| **Sahlha AI Agent** | System intelligence layer embedded in the structured flow (never a generic chatbot screen) |

## 3. Official classroom flow (acceptance loop)

Teacher registers → creates classroom → student joins with code → teacher
uploads material → OCR/RAG ingestion → AI extracts skills → grounded
explanations → question banks → teacher reviews/edits/regenerates → approves →
student learning path → skill lesson → Help Me if needed → practice →
server-side evaluation → feedback → grade → mastery update → weak-skill memory
→ future practice adapts → teacher + parent dashboards update.

## 4. API overview

Auth: `POST /auth/register`, `POST /auth/login`, `GET /auth/me`,
`PATCH /auth/me` (JWT bearer, PBKDF2-hashed passwords).

- Classrooms: `POST /classrooms`, `GET /classrooms`, `GET /classrooms/{id}`,
  `PATCH /classrooms/{id}`, `POST /classrooms/join`,
  `GET /classrooms/{id}/students`
- Materials: `POST /materials/upload`, `GET /materials`,
  `GET /materials/{id}`, `POST /materials/{id}/extract-skills`,
  `GET|POST /materials/{id}/skills`, `PATCH|DELETE
  /materials/{id}/skills/{skill}`, `POST /materials/{id}/generate-banks`,
  `GET /materials/{id}/banks`
- Teacher: `GET /teacher/overview`, `GET /teacher/banks`,
  `GET|POST /teacher/banks/{id}[/approve|/reject|/regenerate]`,
  `PATCH|DELETE|POST-regenerate /teacher/banks/{id}/questions/{qid}`,
  `GET /teacher/classrooms/{id}/mastery`,
  `GET /teacher/classrooms/{id}/students/{sid}`
- Student: `GET|POST /student/profile`, `POST /student/support-signal`,
  `GET /student/home`, `GET /student/learning-path`,
  `GET /student/skills/{id}`, `GET /student/skills/{id}/help`,
  `POST /student/assessments/start`, `POST /student/assessments/{id}/check`,
  `POST /student/assessments/{id}/submit`, `GET /student/grades`,
  `GET /student/progress`, `GET /student/skills/{id}/audio|/image`
- Parent: `POST /parent/link-child`, `GET /parent/children`,
  `GET /parent/children/{id}/progress|/grades|/materials`
- Legacy AI-loop endpoints (`/documents/*`, `/agent/*`, `/teacher/*`,
  `/assessment/*`, `/audio/*`, `/images/*`) are preserved for the Streamlit
  dev tool and existing tests.

## 5. Database & migration

SQLite prototype (`data/sahlha.db`), PostgreSQL-friendly relational design.
New tables: `users`, `classrooms`, `classroom_enrollments`,
`parent_student_links`, `learning_materials`, `student_learning_profiles`;
additive columns on `question_banks` (teacher/classroom/material ownership)
and `student_skill_performance` (course/lesson/row scoping).

Migration approach: **explicit, additive, idempotent** —
`Base.metadata.create_all()` for new tables plus `_ensure_columns()` ALTERs
for columns on pre-existing databases (`sahlha/app/database/database.py`).
Nothing is dropped, renamed, or reset; pre-platform AI data keeps working
(legacy rows are adopted/healed, e.g. unscoped performance rows gain scope).

Note: fresh databases enforce scoped performance uniqueness
`(student, course, lesson, skill)`; very old databases may still carry the
legacy unscoped constraint — the repository merges defensively in that case.

## 6. Environment

See `.env.example`. Important variables:

| Variable | Purpose |
|---|---|
| `DATABASE_URL` | SQLite path (default `./data/sahlha.db`) |
| `JWT_SECRET` | JWT signing secret (change outside local dev) |
| `GROQ_API_KEY` / `GROQ_MODEL` | Real LLM (else grounded fallback generator) |
| `GROQ_TTS_VOICE` | TTS voice (needs key + accepted model terms) |
| `PEXELS_API_KEY` | Skill images (else 503, UI continues without images) |
| `MASTERY_*` | Mastery thresholds |
| `MAX_UPLOAD_MB` | Upload cap (default 25) |
| `CORS_EXTRA_ORIGINS` | Extra dev origins |

OCR: native text for PDF/DOCX/**PPTX**/TXT; scanned PDFs/images use Tesseract
when installed — otherwise ingestion records `ocr:unavailable` and the API
returns a clear error instead of crashing.

On Windows, install both external OCR dependencies (the Python packages alone
are not enough):

```powershell
winget install --id tesseract-ocr.tesseract --exact --source winget
winget install --id oschwartz10612.Poppler --exact --source winget
```

The backend detects standard Tesseract and WinGet Poppler installations.
For custom locations, set `TESSERACT_CMD` to `tesseract.exe` and `POPPLER_PATH`
to the folder containing `pdfinfo.exe` and `pdftoppm.exe` in `.env`, then restart
the backend. Install the matching Tesseract language packs when using
`OCR_LANGUAGES=ara+eng`.

## 7. Run the backend

```powershell
pip install -r requirements.txt
copy .env.example .env   # add GROQ_API_KEY to enable the real LLM; optional
python -m uvicorn sahlha.app.main:app --reload --port 8000
```

API base URL: `http://127.0.0.1:8000`.

## 8. Run the Flutter app

```powershell
cd mobile
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
flutter run --dart-define API_BASE_URL=http://10.0.2.2:8000
flutter build apk --debug
```

API base URL configuration (`--dart-define API_BASE_URL=...`):

- **Android emulator** (default): `http://10.0.2.2:8000`
- **Physical device over USB**: run `adb reverse tcp:8000 tcp:8000`, then use
  `http://127.0.0.1:8000`
- **Physical device over Wi-Fi**: use your machine's LAN IP,
  e.g. `http://192.168.1.10:8000`, with the backend bound to `0.0.0.0`

For a physical Android phone connected by USB, keep the backend running in
one terminal, then run this from the repository root in another terminal:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/run-android-usb.ps1
```

The launcher checks the backend, configures USB port forwarding, and launches
Flutter with `API_BASE_URL=http://127.0.0.1:8000`. With multiple devices, pass
`-DeviceId SERIAL`. Run it again after reconnecting the phone. Changing
`API_BASE_URL` requires restarting the Flutter run, not just hot reload.
The default `10.0.2.2` address is for the Android emulator only.

If the checked-in `mobile/android/` scaffold ever disagrees with your local
Flutter/Gradle versions, regenerate the platform folder (your `lib/` code is
untouched):

```powershell
cd mobile
flutter create --platforms=android .
```

## 9. Backend tests

```powershell
python -m pytest tests/ -q
```

40 tests: the original 25 (RAG, generation, approve/reject→v2, assessments,
memory adaptation, HTTP loop, skills, audio, images) plus 15 platform tests
(auth, hashing, JWT, role guards, classroom ownership, enrollment + duplicate
prevention, cross-classroom isolation, parent linking + duplicates +
unauthorized access, teacher vs supplementary separation, full bank lifecycle,
edit/regenerate/remove/approve, correct-answer security, check-locks-attempt,
grades, mastery, weak-skill adaptation, scoped-per-lesson mastery, teacher +
parent progress).

## 10. Local Flutter QA (your checklist)

```powershell
cd mobile
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
flutter run --dart-define API_BASE_URL=http://10.0.2.2:8000
```

Then walk the demo flow (§11). The Flutter source was written without a local
SDK in this environment — `build_runner` output (`*.g.dart`, `*.freezed.dart`)
is git-ignored by design and generated on your machine.

## 11. Demo flow

**Teacher**: register/login → create classroom → note join code → upload
curriculum → Find learning skills → review/edit skills → Generate practice
questions → open a pending bank → review each question → edit/regenerate/
remove as needed → Approve.
**Student**: register/login → join classroom → complete the 1-minute learning
profile → Home → Continue → Learning Path → open skill → Help Me if needed →
Practice → immediate feedback → results → mastery update.
**Teacher again**: open the student → updated grade, mastery, weak skills.
**Parent**: register/login → link child with the 8-letter code → child
progress, grades, activity → upload supplementary material.

## 12. Known limitations (non-blocking)

- Embeddings are TF-IDF (offline-friendly); swap `rag/embeddings.py` +
  `rag/vectorstore.py` for sentence-transformers + FAISS/Chroma later.
- Scanned-PDF OCR needs the Tesseract binary + `pdf2image`, else a clear
  error is returned.
- No pagination on list endpoints; SQLite only; JWT is a 7-day prototype
  session without refresh-token rotation.
- TTS/skill images need `GROQ_API_KEY` (+ accepted model terms) /
  `PEXELS_API_KEY`; the app degrades gracefully without them.
