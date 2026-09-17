from sahlha.app.database.repositories import repositories as repo
from sahlha.app.services.platform import skill_states_for_lesson


def test_repeated_skill_name_does_not_leak_progress_between_lessons(db_session):
    student = repo.get_or_create_student(db_session, "student")
    repo.upsert_skill(db_session, course_id="math", lesson_id="new", skill_id="fractions")
    repo.upsert_skill_performance(db_session, student_id=student.id, skill_id="fractions",
                                 correct=True, course_id="math", lesson_id="old")
    states = skill_states_for_lesson(db_session, student_id=student.id,
                                    course_id="math", lesson_id="new")
    assert states[0]["attempted"] == 0
    assert states[0]["accuracy"] is None
    assert states[0]["state"] == "not_started"
