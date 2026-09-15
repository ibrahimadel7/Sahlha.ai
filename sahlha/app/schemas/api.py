from pydantic import BaseModel, Field


class GenerateBankRequest(BaseModel):
    course_id: str = "general"
    lesson_id: str = "lesson_1"
    skill_id: str = "general"
    teacher_feedback: str = ""
    n_questions: int = Field(default=8, ge=4, le=20)


class ExtractSkillsRequest(BaseModel):
    course_id: str = "general"
    lesson_id: str = "lesson_1"
    max_skills: int = Field(default=6, ge=1, le=6)  # hard cap: max 6 skills per lesson
    force: bool = False  # re-extract even if skills already exist


class LessonBanksRequest(BaseModel):
    course_id: str = "general"
    lesson_id: str = "lesson_1"
    teacher_feedback: str = ""
    n_questions: int = Field(default=10, ge=4, le=15)  # per-skill bank size


class StartAssessmentRequest(BaseModel):
    student_id: str = "student_1"
    student_name: str = "Student"
    course_id: str | None = None
    lesson_id: str | None = None
    skill_id: str | None = None


class SubmitAssessmentRequest(BaseModel):
    answers: dict[str, object] = Field(default_factory=dict)


class ReviewRequest(BaseModel):
    feedback: str = ""


class FlagRequest(BaseModel):
    reason: str = ""


class CreateStudentRequest(BaseModel):
    student_id: str | None = Field(default=None, description="Optional custom ID; auto-generated if empty")
    name: str = Field(default="Student", min_length=1, max_length=256)
