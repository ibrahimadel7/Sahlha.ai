import pytest
from sqlalchemy import create_engine, text, inspect
from sqlalchemy.orm import Session

from sahlha.app.agent.agent import SahlhaAgent
from sahlha.app.agent.tools import assessment_tools, critique_tools
from sahlha.app.database import database, models as m
from sahlha.app.database.repositories import repositories as repo
from sahlha.app.services import platform as plat
from tests.conftest import SAMPLE_TEXT
from tests.test_platform import _setup_teacher_student, _material_flow, _auth, _register


def bank(db, lesson='one', skill='loops', count=6, status='approved'):
    repo.upsert_skill(db, course_id='course', lesson_id=lesson, skill_id=skill, name=skill.title())
    records = [dict(skill_id=skill, question_type='multiple_choice', question_text=f'Loops repeat instructions {i}?',
                    options=['a', 'b', 'c', 'd'], correct_answer=0, difficulty=['easy', 'medium', 'hard'][i % 3])
               for i in range(count)]
    row = repo.create_bank(db, course_id='course', lesson_id=lesson, skill_id=skill, questions=records)
    repo.set_bank_status(db, row, status)
    return row


def test_critique_rejects_bad_shape_ungrounded_and_tops_up():
    valid = dict(skill_id='wrong', type='multiple_choice', question='What do loops repeat in a program?',
                 options=['instructions', 'plants', 'oceans', 'clouds'], correct_answer=0, difficulty='easy')
    bad_index = dict(valid, correct_answer=9)
    unrelated = dict(valid, question='What color are ocean dolphins?')
    context = [{'text': 'Loops repeat instructions in a program until a condition changes.'}]
    assert critique_tools.critique_question(valid, context, 'loops')[0]
    assert not critique_tools.critique_question(bad_index, context, 'loops')[0]
    assert not critique_tools.critique_question(unrelated, context, 'loops')[0]
    questions, meta = critique_tools.critique_and_top_up([valid, bad_index, unrelated], context, 'loops', 4)
    assert len(questions) == 4 and meta['replacements'] == 3
    assert all(q['skill_id'] == 'loops' for q in questions)


def test_selection_flags_failed_unseen_balance_and_scope(db_session):
    db = db_session
    repo.get_or_create_student(db, 'student')
    first = bank(db)
    bank(db, lesson='other')
    bank(db, skill='pending', status='pending_review')
    questions = repo.get_questions(db, first.id)
    repo.flag_question(db, questions[0].id, 'Ambiguous wording')
    repo.record_attempt(db, student_id='student', question_id=questions[1].id,
                        assessment_id='old', answer=1, correct=False)
    repo.record_attempt(db, student_id='student', question_id=questions[2].id,
                        assessment_id='old', answer=0, correct=True)
    repo.upsert_skill_performance(db, student_id='student', course_id='course', lesson_id='other', skill_id='loops', correct=False)
    selected, meta = assessment_tools.select_questions(db, student_id='student', course_id='course', lesson_id='one', skill_id='loops')
    ids = [q['id'] for q in selected]
    assert len(ids) == len(set(ids)) == 4
    assert questions[0].id not in ids and ids[0] == questions[1].id
    assert questions[2].id not in ids  # unseen outranks previously correct
    assert {q['difficulty'] for q in selected} == {'easy', 'medium', 'hard'}
    assert meta['flagged_excluded'] == 1 and meta['weak_skills'] == []
    assert meta['failed_retried'] == [questions[1].id]
    assert set(meta['per_bank']) == {first.id}
    with pytest.raises(assessment_tools.SelectionError) as error:
        assessment_tools.select_questions(db, student_id='student', course_id='course', lesson_id='one')
    assert error.value.metadata['missing_skills'] == ['pending']
    for question in questions[3:]: repo.flag_question(db, question.id, 'Incorrect answer')
    with pytest.raises(ValueError, match='only 2 usable approved questions; 4 are required'):
        assessment_tools.select_questions(db, student_id='student', course_id='course', lesson_id='one', skill_id='loops')


def test_weak_skills_presented_first_and_assessment_scope_persisted(db_session):
    repo.get_or_create_student(db_session, 'student')
    bank(db_session, skill='strong')
    bank(db_session, skill='weak')
    repo.upsert_skill_performance(db_session, student_id='student', course_id='course', lesson_id='one', skill_id='weak', correct=False)
    out = SahlhaAgent(db_session).start_assessment(student_id='student', course_id='course', lesson_id='one')
    assert out['questions'][0]['skill_id'] == 'weak'
    assessment = repo.get_assessment(db_session, out['assessment_id'])
    assert (assessment.course_id, assessment.lesson_id) == ('course', 'one')
    assert assessment.selection_meta['weak_skills'] == ['weak']


def test_teacher_flags_auth_persist_and_influence_generation(client, db_session, monkeypatch):
    teacher, student, room = _setup_teacher_student(client)
    material = _material_flow(client, teacher, room)
    banks = client.get('/teacher/banks', params={'material_id': material['id']}, headers=_auth(teacher['token'])).json()
    bid = banks[0]['id']
    detail = client.get(f'/teacher/banks/{bid}', headers=_auth(teacher['token'])).json()
    qid = detail['questions'][0]['id']
    route = f'/teacher/banks/{bid}/questions/{qid}/flag'
    assert client.post(route, json={'reason': 'Ambiguous wording'}).status_code == 401
    assert client.post(route, json={'reason': 'Ambiguous wording'}, headers=_auth(student['token'])).status_code == 403
    other = _register(client, 'Other', 'other@teacher.com', 'secret12', 'teacher')
    assert client.post(route, json={'reason': 'Ambiguous wording'}, headers=_auth(other['token'])).status_code == 404
    result = client.post(route, json={'reason': 'Ambiguous wording'}, headers=_auth(teacher['token']))
    assert result.status_code == 201 and result.json()['question_id'] == qid
    assert result.json()['reason'] == 'Ambiguous wording'
    assert qid in repo.get_flagged_question_ids(db_session)
    flags = client.get(f'/teacher/banks/{bid}/flags', headers=_auth(teacher['token'])).json()
    assert flags[0]['reason'] == 'Ambiguous wording'
    client.post(f'/teacher/banks/{bid}/approve', headers=_auth(teacher['token']))
    assessment = client.post('/student/assessments/start', json={'classroom_id': room['id'],
        'material_id': material['id'], 'skill_id': detail['skill_id']}, headers=_auth(student['token'])).json()
    assert qid not in [q['id'] for q in assessment['questions']]
    assert 'trace' not in assessment and 'selection_meta' not in assessment
    import sahlha.app.agent.agent as agent_module
    original = agent_module.generate_questions_llm
    seen = []
    def generate(system, user, chunks, skill_id, count, feedback):
        seen.append(user)
        return original(system, user, chunks, skill_id, count, feedback)
    monkeypatch.setattr(agent_module, 'generate_questions_llm', generate)
    regen = client.post(f'/teacher/banks/{bid}/regenerate', json={'n_questions': 5}, headers=_auth(teacher['token']))
    assert regen.status_code == 201 and 'Ambiguous wording' in seen[0]
    assert repo.get_bank(db_session, bid).status == 'approved'


def test_legacy_schema_migration_preserves_rows_and_separates_lessons(tmp_path, monkeypatch):
    engine = create_engine(f'sqlite:///{tmp_path / "legacy.db"}')
    with engine.begin() as conn:
        conn.execute(text('CREATE TABLE student_skill_performance (id VARCHAR(32) PRIMARY KEY, student_id VARCHAR(32), skill_id VARCHAR(128), total_attempts INTEGER, correct_attempts INTEGER, accuracy FLOAT, last_updated DATETIME, CONSTRAINT uq_student_skill UNIQUE(student_id, skill_id))'))
        conn.execute(text("INSERT INTO student_skill_performance VALUES ('old', 'student', 'loops', 3, 2, 0.6667, '2026-01-01 00:00:00')"))
    monkeypatch.setattr(database, 'engine', engine)
    database.init_db()
    database.init_db()  # repeat startup must be safe
    with Session(engine) as db:
        repo.get_or_create_student(db, 'student')
        repo.upsert_skill(db, course_id='c', lesson_id='a', skill_id='loops')
        adopted = repo.upsert_skill_performance(db, student_id='student', course_id='c', lesson_id='a', skill_id='loops', correct=True)
        assert adopted.id == 'old' and adopted.total_attempts == 4 and adopted.correct_attempts == 3
        repo.upsert_skill(db, course_id='c', lesson_id='b', skill_id='loops')
        second = repo.upsert_skill_performance(db, student_id='student', course_id='c', lesson_id='b', skill_id='loops', correct=False)
        assert second.id != 'old' and second.total_attempts == 1 and second.accuracy == 0
        assert adopted.total_attempts == 4
    assert 'question_feedback' in inspect(engine).get_table_names()
    with engine.connect() as conn:
        assert conn.execute(text('SELECT total_attempts FROM student_skill_performance_legacy_backup')).scalar() == 3
    engine.dispose()


def test_retired_flagged_question_retains_feedback(db_session):
    row = bank(db_session, status='pending_review')
    question = repo.get_questions(db_session, row.id)[0]
    repo.flag_question(db_session, question.id, 'Ambiguous wording')
    repo.delete_question(db_session, question)
    assert len(repo.get_questions(db_session, row.id)) == 5
    assert repo.get_question(db_session, question.id).retired
    assert repo.get_flag_reasons_for_skill(db_session, course_id='course', lesson_id='one', skill_id='loops') == ['Ambiguous wording']


def test_approved_questions_cannot_be_overwritten(db_session):
    row = bank(db_session)
    question = repo.get_questions(db_session, row.id)[0]
    with pytest.raises(ValueError, match='history is preserved'):
        plat.edit_question(db_session, row, question.id, {'question_text': 'Replacement'})
    with pytest.raises(ValueError, match='history is preserved'):
        plat.remove_question(db_session, row, question.id)
    assert repo.get_question(db_session, question.id).question_text != 'Replacement'


def test_version_allocation_retries_integrity_error(db_session, monkeypatch):
    from sqlalchemy.exc import IntegrityError
    original = db_session.flush
    calls = []
    def flush(*args, **kwargs):
        if not calls:
            calls.append('collision')
            raise IntegrityError('insert', {}, Exception('simulated allocation race'))
        return original(*args, **kwargs)
    # Seed the skill first so the injected collision belongs to bank allocation.
    repo.upsert_skill(db_session, course_id='course', lesson_id='one', skill_id='loops')
    monkeypatch.setattr(db_session, 'flush', flush)
    first = repo.create_bank(db_session, course_id='course', lesson_id='one', skill_id='loops', questions=[])
    second = repo.create_bank(db_session, course_id='course', lesson_id='one', skill_id='loops', questions=[])
    assert calls == ['collision'] and (first.version, second.version) == (1, 2)


def test_ambiguous_legacy_performance_is_not_adopted_into_another_lesson(db_session):
    repo.get_or_create_student(db_session, 'student')
    legacy = repo.upsert_skill_performance(db_session, student_id='student', skill_id='loops', correct=True)
    repo.upsert_skill(db_session, course_id='course', lesson_id='one', skill_id='loops')
    repo.upsert_skill(db_session, course_id='course', lesson_id='two', skill_id='loops')
    current = repo.upsert_skill_performance(db_session, student_id='student', course_id='course', lesson_id='one', skill_id='loops', correct=False)
    assert current.id != legacy.id and current.total_attempts == 1
    assert legacy.total_attempts == 1 and legacy.course_id == ''
    assert repo.get_skill_performance(db_session, 'student', course_id='course', lesson_id='two') == []
