import io
from pathlib import Path

import pytest
from fastapi import BackgroundTasks
from sqlalchemy import event

from sahlha.app.agent.tools import explanation_tools, image_tools, audio_tools
from sahlha.app.config import settings
from sahlha.app.database.repositories import repositories as repo
from sahlha.app.database.repositories import platform as prepo
from sahlha.app.images import pexels
from sahlha.app.rag import ocr, ingestion, vectorstore
from sahlha.app.services import platform as plat
from tests.test_provider_failover import wav_bytes
from tests.test_upload_edges import text_pdf
from tests.test_platform import _setup_teacher_student, _auth


@pytest.mark.parametrize('name', ['Python', 'Python Loops', 'Programming Statements', 'While Loops', 'if/else'])
def test_programming_queries(name):
    query = pexels.build_image_query({'name': name})
    assert 'programming' in query and 'education' in query
    assert query.lower() != 'python' and 'snake' not in query


def test_image_search_fallback_and_invalid_download(monkeypatch):
    queries = []
    def search(query):
        queries.append(query)
        return [] if len(queries) < 2 else [{'image_url': 'https://example.test/a.jpg'}]
    monkeypatch.setattr(pexels, 'search_pexels', search)
    import requests
    class Response:
        content = b'not an image' * 200
        headers = {'content-type': 'text/html'}
        def raise_for_status(self): pass
    monkeypatch.setattr(requests, 'get', lambda *a, **k: Response())
    with pytest.raises(RuntimeError, match='valid image'):
        pexels.fetch_related_image('specific topic')
    assert queries == ['specific topic', 'education technology']


def test_ocr_native_sparse_unavailable_and_failure(monkeypatch):
    assert ocr.extract_document_text(text_pdf('Fractions are equal parts of a whole and help represent quantities.'), 'native.pdf').method == 'pypdf'
    calls = []
    monkeypatch.setattr(ocr, '_try_ocr_images', lambda *args: (calls.append(args[1]) or 'Recovered scanned lesson.', 'ocr:tesseract(pdf2image)'))
    result = ocr.extract_document_text(text_pdf('Page 1'), 'scan.pdf')
    assert calls == ['.pdf'] and result.is_scanned and result.text == 'Recovered scanned lesson.'
    monkeypatch.setattr(ocr, '_try_ocr_images', lambda *args: ('', 'ocr:unavailable'))
    result = ocr.extract_document_text(b'image', 'scan.png')
    assert result.method == 'ocr:unavailable' and result.is_scanned


def test_ocr_image_and_failure(monkeypatch):
    import pytesseract
    from PIL import Image
    data = io.BytesIO()
    Image.new('RGB', (40, 40), 'white').save(data, format='PNG')
    monkeypatch.setattr(pytesseract, 'image_to_string', lambda *args, **kwargs: 'Scanned image text')
    assert ocr.extract_document_text(data.getvalue(), 'scan.png').method == 'ocr:tesseract'
    def fail(*args, **kwargs): raise RuntimeError('internal binary failure')
    monkeypatch.setattr(pytesseract, 'image_to_string', fail)
    result = ocr.extract_document_text(data.getvalue(), 'scan.png')
    assert result.method.startswith('ocr:failed') and not result.text


def test_binary_discovery_order(monkeypatch, tmp_path):
    executable = tmp_path / 'tesseract.exe'
    executable.write_text('fixture')
    monkeypatch.setattr(settings, 'tesseract_cmd', str(executable))
    monkeypatch.setattr(ocr.shutil, 'which', lambda name: 'path/tesseract' if name == 'tesseract' else None)
    assert ocr.discover_tesseract() == 'path/tesseract'
    monkeypatch.setattr(ocr.shutil, 'which', lambda name: None)
    assert ocr.discover_tesseract() == str(executable)
    (tmp_path / 'pdftoppm.exe').write_text('fixture')
    monkeypatch.setattr(settings, 'poppler_path', str(tmp_path))
    assert ocr.discover_poppler() == str(tmp_path)


def test_poppler_discovery_in_winget_without_path(monkeypatch, tmp_path):
    monkeypatch.setattr(ocr.shutil, 'which', lambda name: None)
    monkeypatch.setattr(settings, 'poppler_path', '')
    monkeypatch.setenv('ProgramFiles', str(tmp_path / 'programs'))
    monkeypatch.setenv('LOCALAPPDATA', str(tmp_path))
    binary_dir = (tmp_path / 'Microsoft' / 'WinGet' / 'Packages' /
                  'oschwartz10612.Poppler_test' / 'poppler-25.07.0' / 'Library' / 'bin')
    binary_dir.mkdir(parents=True)
    (binary_dir / 'pdftoppm.exe').write_text('fixture')
    assert ocr.discover_poppler() == str(binary_dir)


@pytest.mark.parametrize('name', ['../../bad.txt', '..\\..\\bad.txt', 'CON.txt', 'a:*?<>|.pdf', 'x' * 1000 + '.txt'])
def test_safe_filenames(name):
    safe = ingestion.sanitize_filename(name)
    assert len(safe) <= 140 and safe not in {'CON.txt', '.', '..'}
    assert not any(char in safe for char in '/\\:*?<>|')
    assert Path(safe).name == safe


def test_title_derivation():
    assert ingestion.derive_title('Page 1\nTable of Contents\nIntroduction to Fractions\nBody text.', 'file.txt') == 'Introduction to Fractions'
    assert ingestion.derive_title('', 'python_loops.txt') == 'Python loops'


def test_background_index_status_and_failure(client, db_session, monkeypatch):
    teacher, _, room = _setup_teacher_student(client)
    user = prepo.get_user_by_email(db_session, 'sara@t.com')
    mat = plat.create_material_record(db_session, uploader=user, title='', filename='../../lesson.txt', classroom_id=room['id'])
    tasks = BackgroundTasks()
    plat.process_material(db_session, mat, b'Introduction to Fractions\nFractions divide a whole into equal parts.', background_tasks=tasks)
    assert mat.processing_status == 'processing'
    assert mat.original_filename == '../../lesson.txt' and mat.title == 'Introduction to Fractions'
    with pytest.raises(ValueError, match='processing must finish'):
        plat.extract_material_skills(db_session, mat)
    assert len(tasks.tasks) == 1
    task = tasks.tasks[0]
    task.func(*task.args, **task.kwargs)
    db_session.refresh(mat)
    assert mat.processing_status == 'processed'
    prepo.set_material_status(db_session, mat, 'processing')
    monkeypatch.setattr(vectorstore, 'rebuild_index', lambda db: (_ for _ in ()).throw(RuntimeError('disk failed')))
    plat.index_material(db_session.get_bind(), mat.id)
    db_session.refresh(mat)
    assert mat.processing_status == 'failed' and 'Indexing failed' in mat.status_detail


@pytest.mark.parametrize('image_fails,audio_fails', [(False, False), (True, False), (False, True), (True, True)])
def test_explanation_survives_media_and_gap_fill(db_session, monkeypatch, tmp_path, image_fails, audio_fails):
    ingestion.ingest_upload(db_session, file_bytes=b'Loops repeat instructions until the condition changes.', filename='lesson.txt', course_id='c', lesson_id='l')
    row = repo.upsert_skill(db_session, course_id='c', lesson_id='l', skill_id='loops', name='Loops')
    calls = []
    image = tmp_path / 'picture.jpg'
    image.write_bytes(b'\xff\xd8\xff' + b'\0' * 2048)
    audio = tmp_path / 'audio.wav'
    audio.write_bytes(wav_bytes())
    def fetch(db, **scope):
        calls.append('image')
        if image_fails: raise RuntimeError('provider down')
        repo.set_media(db, row, image_path=str(image))
        return {'cached': False}
    def synth(db, **scope):
        calls.append('audio')
        if audio_fails: raise RuntimeError('provider down')
        repo.set_media(db, row, audio_path=str(audio))
        return {'cached': False}
    monkeypatch.setattr(image_tools, 'fetch_skill_image', fetch)
    monkeypatch.setattr(audio_tools, 'skill_explanation_to_audio', synth)
    result = explanation_tools.explain_skill(db_session, course_id='c', lesson_id='l', skill_id='loops')
    assert result['skill']['explanation'] and row.explanation
    assert calls == ['image', 'audio']
    calls.clear()
    explanation_tools.ensure_skill_media(db_session, course_id='c', lesson_id='l', skill_id='loops')
    assert calls == (['image'] if image_fails else []) + (['audio'] if audio_fails else [])


def test_study_bundle_constant_queries_and_authorization(client, db_session):
    teacher, student, room = _setup_teacher_student(client)
    response = client.post('/materials/upload', data={'classroom_id': room['id']},
        files={'file': ('lesson.txt', b'Loops repeat instructions until the condition changes.')}, headers=_auth(teacher['token']))
    material_id = response.json()['material']['id']
    for i in range(8): repo.upsert_skill(db_session, course_id=f'class:{room["id"]}', lesson_id=material_id, skill_id=f'skill{i}')
    queries = []
    def record(*args): queries.append(args[2])
    event.listen(db_session.get_bind(), 'before_cursor_execute', record)
    try:
        bundle = plat.study_bundle(db_session, course_id=f'class:{room["id"]}', lesson_id=material_id)
    finally:
        event.remove(db_session.get_bind(), 'before_cursor_execute', record)
    assert len(bundle['skills']) == 8 and len(queries) == 4
    route = f'/student/materials/{material_id}/study'
    assert client.get(route).status_code == 401
    assert client.get(route, params={'classroom_id': room['id']}, headers=_auth(student['token'])).status_code == 200
    assert client.get(route, params={'classroom_id': 'other'}, headers=_auth(student['token'])).status_code == 404
