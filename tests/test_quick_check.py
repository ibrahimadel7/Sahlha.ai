import pytest
from sahlha.app.agent.agent import SahlhaAgent
from sahlha.app.agent.tools import assessment_tools
from sahlha.app.database.repositories import repositories as repo
from tests.test_quality_selection import bank


def test_quick_check_mixes_only_practiced_skills_and_uses_normal_grading(db_session):
    db = db_session
    repo.get_or_create_student(db, 'student')
    for skill in ['first', 'second', 'unseen']:
        bank(db, skill=skill)
    for skill in ['first', 'second']:
        repo.upsert_skill_performance(db, student_id='student', course_id='course',
                                     lesson_id='one', skill_id=skill, correct=True)
    # A practiced skill in another lesson must never leak into this checkpoint.
    bank(db, lesson='other', skill='elsewhere')
    repo.upsert_skill_performance(db, student_id='student', course_id='course',
                                 lesson_id='other', skill_id='elsewhere', correct=True)
    agent = SahlhaAgent(db)
    assessment = agent.start_assessment(student_id='student', course_id='course',
                                       lesson_id='one', learned_only=True)
    assert {q['skill_id'] for q in assessment['questions']} == {'first', 'second'}
    assert all('correct_answer' not in q for q in assessment['questions'])
    answers = {q['id']: 0 for q in assessment['questions']}
    result = agent.submit_assessment(assessment_id=assessment['assessment_id'], answers=answers)
    assert result['correct'] == result['total'] == len(answers)
    assert repo.get_assessment(db, assessment['assessment_id']).status == 'submitted'


def test_quick_check_requires_multiple_practiced_skills(db_session):
    db = db_session
    repo.get_or_create_student(db, 'student')
    bank(db, skill='only')
    repo.upsert_skill_performance(db, student_id='student', course_id='course',
                                 lesson_id='one', skill_id='only', correct=True)
    with pytest.raises(assessment_tools.SelectionError, match='at least two skills'):
        assessment_tools.select_questions(db, student_id='student', course_id='course',
                                         lesson_id='one', learned_only=True)
