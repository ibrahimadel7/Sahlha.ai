-- Sahlha Workers-native schema (D1). Faithful port of sahlha/app/database/models.py.
-- Adaptations: users own assessments/attempts/perf directly (no legacy students
-- table); document_chunks carry an embedding JSON column (Workers AI bge-m3);
-- datetimes stored as ISO8601 TEXT; JSON columns stored as TEXT.

CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL DEFAULT '',
  email TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL DEFAULT '',
  role TEXT NOT NULL DEFAULT 'student',
  active INTEGER NOT NULL DEFAULT 1,
  link_code TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL DEFAULT '',
  updated_at TEXT NOT NULL DEFAULT ''
);
CREATE UNIQUE INDEX IF NOT EXISTS ix_users_link_code ON users(link_code) WHERE link_code <> '';

CREATE TABLE IF NOT EXISTS classrooms (
  id TEXT PRIMARY KEY,
  teacher_id TEXT NOT NULL REFERENCES users(id),
  name TEXT NOT NULL DEFAULT '',
  subject TEXT NOT NULL DEFAULT '',
  grade_level TEXT NOT NULL DEFAULT '',
  join_code TEXT NOT NULL UNIQUE,
  created_at TEXT NOT NULL DEFAULT '',
  updated_at TEXT NOT NULL DEFAULT ''
);

CREATE TABLE IF NOT EXISTS classroom_enrollments (
  id TEXT PRIMARY KEY,
  classroom_id TEXT NOT NULL REFERENCES classrooms(id),
  student_id TEXT NOT NULL REFERENCES users(id),
  joined_at TEXT NOT NULL DEFAULT '',
  UNIQUE (classroom_id, student_id)
);

CREATE TABLE IF NOT EXISTS parent_student_links (
  id TEXT PRIMARY KEY,
  parent_id TEXT NOT NULL REFERENCES users(id),
  student_id TEXT NOT NULL REFERENCES users(id),
  created_at TEXT NOT NULL DEFAULT '',
  UNIQUE (parent_id, student_id)
);

CREATE TABLE IF NOT EXISTS learning_materials (
  id TEXT PRIMARY KEY,
  uploader_id TEXT NOT NULL REFERENCES users(id),
  source_type TEXT NOT NULL DEFAULT 'teacher',
  classroom_id TEXT REFERENCES classrooms(id),
  child_student_id TEXT REFERENCES users(id),
  title TEXT NOT NULL DEFAULT '',
  original_filename TEXT NOT NULL DEFAULT '',
  document_id TEXT,
  scope TEXT NOT NULL DEFAULT 'official',
  processing_status TEXT NOT NULL DEFAULT 'uploaded',
  status_detail TEXT NOT NULL DEFAULT '',
  quality_signals TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL DEFAULT '',
  updated_at TEXT NOT NULL DEFAULT ''
);
CREATE INDEX IF NOT EXISTS ix_materials_classroom ON learning_materials(classroom_id);
CREATE INDEX IF NOT EXISTS ix_materials_child ON learning_materials(child_student_id);

CREATE TABLE IF NOT EXISTS student_learning_profiles (
  student_id TEXT PRIMARY KEY REFERENCES users(id),
  onboarding_completed INTEGER NOT NULL DEFAULT 0,
  reading_support TEXT NOT NULL DEFAULT '',
  focus_support TEXT NOT NULL DEFAULT '',
  instruction_support TEXT NOT NULL DEFAULT '',
  presentation_support TEXT NOT NULL DEFAULT '',
  practice_support TEXT NOT NULL DEFAULT '',
  session_preference TEXT NOT NULL DEFAULT '',
  learning_confidence TEXT NOT NULL DEFAULT '',
  raw_answers TEXT NOT NULL DEFAULT '{}',
  observed_settings TEXT NOT NULL DEFAULT '{}',
  support_retry_count INTEGER NOT NULL DEFAULT 0,
  support_hint_count INTEGER NOT NULL DEFAULT 0,
  updated_at TEXT NOT NULL DEFAULT ''
);

CREATE TABLE IF NOT EXISTS documents (
  id TEXT PRIMARY KEY,
  filename TEXT NOT NULL,
  course_id TEXT NOT NULL DEFAULT 'general',
  lesson_id TEXT NOT NULL DEFAULT 'lesson_1',
  skill_id TEXT NOT NULL DEFAULT 'general',
  status TEXT NOT NULL DEFAULT 'uploaded',
  char_count INTEGER NOT NULL DEFAULT 0,
  chunk_count INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT ''
);

CREATE TABLE IF NOT EXISTS document_chunks (
  id TEXT PRIMARY KEY,
  document_id TEXT NOT NULL REFERENCES documents(id),
  course_id TEXT NOT NULL DEFAULT 'general',
  lesson_id TEXT NOT NULL DEFAULT 'lesson_1',
  skill_id TEXT NOT NULL DEFAULT 'general',
  page INTEGER NOT NULL DEFAULT 0,
  chunk_index INTEGER NOT NULL DEFAULT 0,
  text TEXT NOT NULL,
  embedding TEXT NOT NULL DEFAULT '[]',
  section TEXT NOT NULL DEFAULT '',
  section_id TEXT NOT NULL DEFAULT '',
  type TEXT NOT NULL DEFAULT 'paragraph',
  block_metadata TEXT NOT NULL DEFAULT '{}'
);
CREATE INDEX IF NOT EXISTS ix_chunks_scope ON document_chunks(course_id, lesson_id);

CREATE TABLE IF NOT EXISTS lesson_explanations (
  id TEXT PRIMARY KEY,
  course_id TEXT NOT NULL DEFAULT 'general',
  lesson_id TEXT NOT NULL DEFAULT 'lesson_1',
  title TEXT NOT NULL DEFAULT '',
  explanation TEXT NOT NULL DEFAULT '',
  key_concepts TEXT NOT NULL DEFAULT '[]',
  category TEXT NOT NULL DEFAULT '',
  image_url TEXT NOT NULL DEFAULT '',
  image_path TEXT NOT NULL DEFAULT '',
  image_alt TEXT NOT NULL DEFAULT '',
  audio_path TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL DEFAULT '',
  updated_at TEXT NOT NULL DEFAULT '',
  UNIQUE (course_id, lesson_id)
);

CREATE TABLE IF NOT EXISTS skills (
  id TEXT PRIMARY KEY,
  course_id TEXT NOT NULL DEFAULT 'general',
  lesson_id TEXT NOT NULL DEFAULT 'lesson_1',
  skill_id TEXT NOT NULL,
  name TEXT NOT NULL DEFAULT '',
  description TEXT NOT NULL DEFAULT '',
  explanation TEXT NOT NULL DEFAULT '',
  key_concepts TEXT NOT NULL DEFAULT '[]',
  learning_objective TEXT NOT NULL DEFAULT '',
  source_chunk_ids TEXT NOT NULL DEFAULT '[]',
  source_evidence TEXT NOT NULL DEFAULT '[]',
  image_url TEXT NOT NULL DEFAULT '',
  image_path TEXT NOT NULL DEFAULT '',
  image_alt TEXT NOT NULL DEFAULT '',
  audio_path TEXT NOT NULL DEFAULT '',
  extraction_active INTEGER NOT NULL DEFAULT 1,
  prerequisites TEXT NOT NULL DEFAULT '[]',
  misconceptions TEXT NOT NULL DEFAULT '[]',
  difficulty TEXT NOT NULL DEFAULT '',
  source_section_ids TEXT NOT NULL DEFAULT '[]',
  evidence_chunk_ids TEXT NOT NULL DEFAULT '[]',
  learning_content TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL DEFAULT '',
  updated_at TEXT NOT NULL DEFAULT '',
  UNIQUE (course_id, lesson_id, skill_id)
);

CREATE TABLE IF NOT EXISTS question_banks (
  id TEXT PRIMARY KEY,
  course_id TEXT NOT NULL DEFAULT 'general',
  lesson_id TEXT NOT NULL DEFAULT 'lesson_1',
  skill_id TEXT NOT NULL DEFAULT 'general',
  version INTEGER NOT NULL DEFAULT 1,
  status TEXT NOT NULL DEFAULT 'pending_review',
  teacher_feedback TEXT NOT NULL DEFAULT '',
  teacher_id TEXT REFERENCES users(id),
  classroom_id TEXT REFERENCES classrooms(id),
  material_id TEXT REFERENCES learning_materials(id),
  created_at TEXT NOT NULL DEFAULT '',
  updated_at TEXT NOT NULL DEFAULT '',
  UNIQUE (course_id, lesson_id, skill_id, version)
);

CREATE TABLE IF NOT EXISTS questions (
  id TEXT PRIMARY KEY,
  question_bank_id TEXT NOT NULL REFERENCES question_banks(id),
  skill_id TEXT NOT NULL DEFAULT 'general',
  question_type TEXT NOT NULL DEFAULT 'multiple_choice',
  question_text TEXT NOT NULL,
  options TEXT NOT NULL DEFAULT '[]',
  correct_answer TEXT NOT NULL DEFAULT '0',
  explanation TEXT NOT NULL DEFAULT '',
  difficulty TEXT NOT NULL DEFAULT 'medium',
  source_chunk_ids TEXT NOT NULL DEFAULT '[]',
  source_evidence TEXT NOT NULL DEFAULT '[]',
  evidence_chunk_ids TEXT NOT NULL DEFAULT '[]',
  learning_objective TEXT NOT NULL DEFAULT '',
  tested_concept TEXT NOT NULL DEFAULT '',
  verification TEXT NOT NULL DEFAULT '{}',
  retired INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT ''
);
CREATE INDEX IF NOT EXISTS ix_questions_bank ON questions(question_bank_id);

CREATE TABLE IF NOT EXISTS assessments (
  id TEXT PRIMARY KEY,
  student_id TEXT NOT NULL REFERENCES users(id),
  question_bank_id TEXT NOT NULL REFERENCES question_banks(id),
  course_id TEXT NOT NULL DEFAULT 'general',
  lesson_id TEXT NOT NULL DEFAULT 'lesson_1',
  selection_meta TEXT NOT NULL DEFAULT '{}',
  question_ids TEXT NOT NULL DEFAULT '[]',
  status TEXT NOT NULL DEFAULT 'started',
  score REAL NOT NULL DEFAULT 0.0,
  created_at TEXT NOT NULL DEFAULT ''
);

CREATE TABLE IF NOT EXISTS student_attempts (
  id TEXT PRIMARY KEY,
  student_id TEXT NOT NULL REFERENCES users(id),
  question_id TEXT NOT NULL REFERENCES questions(id),
  assessment_id TEXT NOT NULL REFERENCES assessments(id),
  answer TEXT,
  correct INTEGER NOT NULL DEFAULT 0,
  timestamp TEXT NOT NULL DEFAULT ''
);
CREATE INDEX IF NOT EXISTS ix_attempts_student ON student_attempts(student_id);
CREATE INDEX IF NOT EXISTS ix_attempts_assessment ON student_attempts(assessment_id);

CREATE TABLE IF NOT EXISTS student_skill_performance (
  id TEXT PRIMARY KEY,
  student_id TEXT NOT NULL REFERENCES users(id),
  skill_id TEXT NOT NULL,
  course_id TEXT NOT NULL DEFAULT 'general',
  lesson_id TEXT NOT NULL DEFAULT 'lesson_1',
  skill_row_id TEXT REFERENCES skills(id),
  total_attempts INTEGER NOT NULL DEFAULT 0,
  correct_attempts INTEGER NOT NULL DEFAULT 0,
  accuracy REAL NOT NULL DEFAULT 0.0,
  last_updated TEXT NOT NULL DEFAULT '',
  UNIQUE (student_id, course_id, lesson_id, skill_id)
);

CREATE TABLE IF NOT EXISTS question_feedback (
  id TEXT PRIMARY KEY,
  question_id TEXT NOT NULL REFERENCES questions(id),
  teacher_id TEXT REFERENCES users(id),
  kind TEXT NOT NULL DEFAULT 'flag',
  reason TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL DEFAULT ''
);
CREATE INDEX IF NOT EXISTS ix_feedback_question ON question_feedback(question_id);

CREATE TABLE IF NOT EXISTS bank_version_counters (
  course_id TEXT NOT NULL,
  lesson_id TEXT NOT NULL,
  skill_id TEXT NOT NULL,
  version INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (course_id, lesson_id, skill_id)
);
