import io
import wave
from types import SimpleNamespace

import pytest

from sahlha.app.agent import llm
from sahlha.app.agent.providers import retryable_provider_error
from sahlha.app.agent.tools import audio_tools
from sahlha.app.audio import tts
from sahlha.app.config import settings


class ProviderError(Exception):
    def __init__(self, status, message='provider error'):
        super().__init__(message)
        self.status_code = status


def wav_bytes():
    data = io.BytesIO()
    with wave.open(data, 'wb') as writer:
        writer.setnchannels(1)
        writer.setsampwidth(2)
        writer.setframerate(24000)
        writer.writeframes(b'\0\0' * 100)
    return data.getvalue()


@pytest.mark.parametrize('status,message,expected', [
    (429, 'rate limited', True), (503, 'overloaded', True), (408, 'timeout', True),
    (401, 'invalid API key', False), (403, 'forbidden', False), (400, 'bad payload', False),
    (404, 'model_not_found', True), (400, 'model_decommissioned', True),
    (429, 'model requires terms acceptance', False), (400, 'model requires terms acceptance', False),
])
def test_retryability(status, message, expected):
    assert retryable_provider_error(ProviderError(status, message)) is expected


@pytest.mark.parametrize('primary,error,backup,expected,calls_expected', [
    (True, None, True, 'groq', ['groq']),
    (True, 429, True, 'openrouter', ['groq', 'openrouter']),
    (True, 503, True, 'openrouter', ['groq', 'openrouter']),
    (True, 401, True, 'fallback', ['groq']),
    (True, 429, False, 'fallback', ['groq']),
    (False, None, True, 'openrouter', ['openrouter']),
])
def test_text_provider_chain(monkeypatch, primary, error, backup, expected, calls_expected):
    monkeypatch.setattr(settings, 'groq_api_key', 'primary' if primary else '')
    monkeypatch.setattr(settings, 'openrouter_api_key', 'backup' if backup else '')
    monkeypatch.setattr(settings, 'openrouter_model', 'configured-backup')
    monkeypatch.setattr(settings, 'groq_model', 'configured-primary')
    calls = []
    def complete(provider, key, model, system, user, temperature=0.4, **kwargs):
        calls.append(provider)
        assert model == ('configured-primary' if provider == 'groq' else 'configured-backup')
        if provider == 'groq' and error:
            raise ProviderError(error)
        return '{"questions": []}'
    monkeypatch.setattr(llm, '_provider_completion', complete)
    questions, backend = llm.generate_questions_llm('system', 'user', [{'text': 'A loop repeats instructions until a condition changes.'}], 'loops', 4)
    assert backend.startswith(expected)
    assert calls == calls_expected
    if expected == 'fallback':
        assert len(questions) == 4 and 'loop' in questions[0]['question'].lower()


def test_both_text_providers_fail_once(monkeypatch):
    monkeypatch.setattr(settings, 'groq_api_key', 'primary')
    monkeypatch.setattr(settings, 'openrouter_api_key', 'backup')
    monkeypatch.setattr(settings, 'openrouter_model', 'backup-model')
    calls = []
    def fail(provider, *args):
        calls.append(provider)
        raise ProviderError(503)
    monkeypatch.setattr(llm, '_provider_completion', fail)
    _, backend = llm.generate_questions_llm('', '', [{'text': 'Loops repeat instructions while a condition remains true.'}], 'loops', 4)
    assert backend.startswith('fallback') and calls == ['groq', 'openrouter']


@pytest.mark.parametrize('primary,error,backup_fails,expected', [
    (True, None, False, ['groq']), (True, 429, False, ['groq', 'openrouter']),
    (False, None, False, ['openrouter']), (True, 503, True, ['groq', 'openrouter']),
    (True, 401, False, ['groq']),
])
def test_tts_chain(monkeypatch, primary, error, backup_fails, expected):
    monkeypatch.setattr(settings, 'groq_api_key', 'primary' if primary else '')
    monkeypatch.setattr(settings, 'openrouter_api_key', 'backup')
    monkeypatch.setattr(settings, 'openrouter_tts_model', 'speech-model')
    calls = []
    def groq(*args, **kwargs):
        calls.append('groq')
        if error: raise ProviderError(error)
        return wav_bytes()
    def backup(*args, **kwargs):
        calls.append('openrouter')
        if backup_fails: raise ProviderError(503)
        return wav_bytes()
    monkeypatch.setattr(tts, '_synthesize_chunk', groq)
    monkeypatch.setattr(tts, '_openrouter_chunk', backup)
    if backup_fails or error == 401:
        with pytest.raises(RuntimeError): tts.synthesize('Lesson text.')
    else:
        assert tts.valid_wav(tts.synthesize('Lesson text.')[0])
    assert calls == expected


def test_terms_acceptance_never_calls_backup(monkeypatch):
    monkeypatch.setattr(settings, 'groq_api_key', 'primary')
    monkeypatch.setattr(settings, 'openrouter_api_key', 'backup')
    monkeypatch.setattr(settings, 'openrouter_tts_model', 'speech')
    def fail(*args, **kwargs): raise ProviderError(400, 'model requires terms acceptance')
    monkeypatch.setattr(tts, '_synthesize_chunk', fail)
    monkeypatch.setattr(tts, '_openrouter_chunk', lambda *a: pytest.fail('Backup must not run'))
    with pytest.raises(RuntimeError): tts.synthesize('Some speech.')


def test_audio_cache_reuse_and_corruption(monkeypatch):
    calls = []
    monkeypatch.setattr(tts, 'synthesize', lambda text, voice: (calls.append(text) or wav_bytes(), voice))
    path, _, cached = audio_tools._cached_or_synth('Lesson recording.', None)
    assert not cached
    assert audio_tools._cached_or_synth('Lesson recording.', None)[2]
    assert len(calls) == 1
    with open(path, 'wb') as stream: stream.write(b'not audio')
    assert not audio_tools._cached_or_synth('Lesson recording.', None)[2]
    assert len(calls) == 2
    monkeypatch.setattr(settings, 'groq_tts_model', 'new-model')
    assert audio_tools._cached_or_synth('Lesson recording.', None)[0] != path


def test_openrouter_pcm_wrapped_as_valid_wav(monkeypatch):
    import openai
    requests = []
    class Client:
        def __init__(self, **kwargs):
            assert kwargs['max_retries'] == 0
            self.audio = SimpleNamespace(speech=SimpleNamespace(create=self.create))
        def __enter__(self): return self
        def __exit__(self, *args): pass
        def create(self, **kwargs):
            requests.append(kwargs)
            return SimpleNamespace(read=lambda: b'\0\0' * 100)
    monkeypatch.setattr(openai, 'OpenAI', Client)
    audio = tts._openrouter_chunk('Hello.', 'alloy')
    assert tts.valid_wav(audio)
    assert requests[0]['response_format'] == 'pcm'
    with wave.open(io.BytesIO(audio)) as reader:
        assert reader.getframerate() == settings.openrouter_tts_sample_rate
