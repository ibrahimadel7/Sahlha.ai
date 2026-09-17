"""Regression: publication apparatus must never consume the lesson's skill cap."""
import pytest

from sahlha.app.agent.agent import SahlhaAgent
from sahlha.app.agent import agent as agent_module
from sahlha.app.agent.pedagogy import instructional_views
from sahlha.app.agent.tools import content_tools
from sahlha.app.database.repositories import repositories as repo


def chunk(id, page, heading, body):
    return dict(chunk_id=id, page=page, section=heading, section_id=f's:{id}',
                document_id='doc', text=f'{heading}\n\n{body}')


def source():
    return [
        chunk('contents', 1, 'CONTENTS', 'Multiplication ........ 4\nArrays ........ 5\nCommutativity ........ 6'),
        chunk('notice', 2, 'Copyright notice', 'This work is licensed under Creative Commons Attribution. All rights reserved.'),
        chunk('disclaimer', 2, 'necessarily represent the views of the Australian Government', 'The views expressed here are those of the author.'),
        chunk('authors', 3, 'About the authors', 'Jane Smith is a professor and the writer of this book.'),
        chunk('bio', 3, 'Jane Smith', 'Jane Smith was born in 1970 and published several books.'),
        chunk('prior', 4, 'ASSUMED KNOWLEDGE', 'Students are expected to know addition, place value, and counting before this lesson.'),
        chunk('addition', 5, 'Introducing Multiplication', 'For whole numbers, multiplication is equivalent to repeated addition.'),
        chunk('arrays', 6, 'Modelling Multiplication by Arrays', 'An array represents multiplication using rows and columns. Multiplication is commutative because reversing the factors leaves the product unchanged.'),
        chunk('skip', 7, 'Skip Counting', 'Skip counting is repeated addition and helps us learn multiplication.'),
        chunk('area', 8, 'Area Models', 'The area model of multiplication uses equal unit squares to represent a product.'),
    ]


def test_publication_apparatus_does_not_become_topics():
    clean, roles = instructional_views(source())
    assert {c['chunk_id'] for c in clean} == {'addition', 'arrays', 'skip', 'area'}
    skills, _ = content_tools.validate_skills(content_tools.fallback_topics(clean), clean, 6)
    assert len(skills) >= 4
    assert all(set(s['evidence_chunk_ids']) <= {'addition', 'arrays', 'skip', 'area'} for s in skills)
    assert {'Multiplication as Repeated Addition', 'Array Models of Multiplication',
            'Commutative Property of Multiplication'} <= {s['name'] for s in skills}


@pytest.mark.parametrize('heading,body', [
    ('Ada Lovelace', 'Ada Lovelace was a writer and mathematician who described an algorithm for the Analytical Engine.'),
    ('Copyright', 'Copyright is a legal right that protects original creative works. Students compare ownership and permission.'),
    ('Work', 'Work is the energy transferred when a force moves an object through a displacement.'),
    ('Indexing Lists', 'An index is the position of an element in a list. Python uses zero-based indexing.'),
])
def test_legitimate_subjects_not_rejected_by_keyword(heading, body):
    chunks = [chunk('lesson', 1, heading, body)]
    clean, _ = instructional_views(chunks)
    assert len(clean) == 1
    candidate = dict(name=heading, skill_id='topic', evidence_chunk_ids=['lesson'])
    assert content_tools.validate_skills([candidate], chunks, 6)[0]


def test_copyright_footer_removed_from_mixed_evidence():
    chunks = [chunk('mixed', 1, 'Fractions', 'Fractions are equal parts of a whole.\n\nCopyright notice: all rights reserved.')]
    clean, _ = instructional_views(chunks)
    assert len(clean) == 1 and 'Fractions are' in clean[0]['text']
    assert 'rights reserved' not in clean[0]['text']


def test_index_only_material_has_no_skills():
    chunks = source()[:3]
    assert not content_tools.fallback_topics(chunks)
    invented = [dict(name='Multiplication', skill_id='m', evidence_chunk_ids=['contents'])]
    assert not content_tools.validate_skills(invented, chunks, 6)[0]


def test_old_cached_metadata_skills_refresh_and_remain_archived(db_session, monkeypatch):
    doc = repo.create_document(db_session, filename='math.txt', course_id='c', lesson_id='l', skill_id='general')
    records = []
    for index, c in enumerate(source()):
        records.append({k: v for k, v in dict(c, document_id=doc.id, course_id='c', lesson_id='l',
                        skill_id='general', chunk_index=index).items() if k != 'chunk_id'})
    repo.add_chunks(db_session, records)
    notice = repo.get_chunks(db_session, course_id='c', lesson_id='l')[1]
    old = repo.upsert_skill(db_session, course_id='c', lesson_id='l', skill_id='work', name='Work',
        educational_metadata={'evidence_chunk_ids': [notice.id], 'learning_objective': 'Explain Work.'})
    calls = []
    def generate(system, user):
        calls.append(user)
        raise RuntimeError('offline')
    monkeypatch.setattr(agent_module, 'complete_json', generate)
    result = SahlhaAgent(db_session).extract_skills(course_id='c', lesson_id='l')
    assert not old.extraction_active
    assert all(s['name'] != 'Work' for s in result['skills'])
    assert not any('rights reserved' in call or 'Jane Smith' in call or 'ASSUMED KNOWLEDGE' in call for call in calls)
    count = len(calls)
    assert SahlhaAgent(db_session).extract_skills(course_id='c', lesson_id='l')['backend'] == 'existing'
    assert len(calls) == count


def test_model_cannot_cite_noninstructional_chunks():
    candidate = dict(name='Government Views', skill_id='views', evidence_chunk_ids=['disclaimer'])
    assert not content_tools.validate_skills([candidate], source(), 6)[0]
