"""Sparse skill evidence must not discard other skills' reviewable practice."""
import pytest

from sahlha.app.agent.tools import content_tools, critique_tools
from sahlha.app.database import models as m
from sahlha.app.database.repositories import repositories as repo
from sahlha.app.services import mapping
from tests.test_platform import _setup_teacher_student, _upload, _auth


SHORT = [{'chunk_id': 'syntax', 'text': 'def functionName( list of parameters ):'}]
FULL = [{'chunk_id': 'function', 'text':
         'A function is a reusable block of code that performs a specific task. '
         'Parameters pass input values into functions and return statements provide output.'}]


def test_function_list_with_page_credit_is_not_question_evidence():
    from sahlha.app.agent.pedagogy import instructional_views
    footer = 'pg. 1 www.example.org by Author Teacher School'
    cleaned, _ = instructional_views([
        {'chunk_id': 'list', 'text': 'dir() id() oct() sorted()\n\n' + footer},
        {'chunk_id': 'definition', 'text': FULL[0]['text'] + '\n\n' + footer},
    ])
    assert [c['chunk_id'] for c in cleaned] == ['definition']
    assert footer not in cleaned[0]['text']


def test_partial_bank_keeps_only_verified_unique_questions():
    with pytest.raises(critique_tools.InsufficientEvidenceError):
        critique_tools.critique_and_top_up([], SHORT, 'syntax', 10)
    questions, meta = critique_tools.critique_and_top_up([], SHORT, 'syntax', 10, allow_partial=True)
    assert 0 < len(questions) < 10
    assert meta['shortfall'] == 10 - len(questions)
    assert len({q['question'] for q in questions}) == len(questions)
    assert all(critique_tools.critique_question(q, SHORT, 'syntax')[0] for q in questions)


@pytest.mark.parametrize('context', [[], [{'chunk_id': 'x', 'text': 'dir() id() oct() sorted()'}]])
def test_partial_mode_still_rejects_unusable_evidence(context):
    with pytest.raises(critique_tools.InsufficientEvidenceError):
        critique_tools.critique_and_top_up([], context, 'empty', 10, allow_partial=True)


@pytest.mark.parametrize('all_empty', [False, True])
def test_material_generation_reports_sparse_skills_and_stamps_ownership(client, db_session, monkeypatch, all_empty):
    teacher, _, room = _setup_teacher_student(client)
    upload = _upload(client, teacher['token'], classroom_id=room['id'])
    assert upload.status_code == 201
    material_id = upload.json()['material']['id']
    mat = db_session.get(m.LearningMaterial, material_id)
    course_id, lesson_id = mapping.scope_for_material(mat)
    for skill_id in ('empty', 'syntax', 'function'):
        repo.upsert_skill(db_session, course_id=course_id, lesson_id=lesson_id,
                          skill_id=skill_id, name=skill_id)
    contexts = {'empty': [], 'syntax': SHORT, 'function': FULL}
    monkeypatch.setattr(content_tools, 'skill_evidence',
                        lambda db, **kw: [] if all_empty else [dict(c) for c in contexts[kw['skill_id']]])
    response = client.post(f'/materials/{material_id}/generate-banks', json={}, headers=_auth(teacher['token']))
    if all_empty:
        assert response.status_code == 400
        assert 'Re-extract' in response.json()['detail']
        assert not repo.list_banks(db_session, lesson_id=lesson_id)
        return
    assert response.status_code == 200, response.text
    result = response.json()
    assert [s['skill_id'] for s in result['skipped_skills']] == ['empty']
    assert len(result['banks']) == 2
    assert any(0 < b['num_questions'] < 10 for b in result['banks'])
    for bank in repo.list_banks(db_session, lesson_id=lesson_id):
        assert bank.teacher_id == teacher['user']['id']
        assert bank.classroom_id == room['id']
        assert bank.material_id == material_id
        assert bank.status == 'pending_review'
        assert repo.get_questions(db_session, bank.id)
    detail = client.get(f'/materials/{material_id}', headers=_auth(teacher['token'])).json()
    assert detail['status'] == 'banks_ready'
    assert 'fewer questions' in detail['status_detail']
    assert 'No questions for: empty' in detail['status_detail']
