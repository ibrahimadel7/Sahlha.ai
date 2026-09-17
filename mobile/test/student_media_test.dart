import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sahlha/core/api/api_exception.dart';
import 'package:sahlha/features/student/data/student_repository.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);

  final ResponseBody Function(RequestOptions options) handler;
  int calls = 0;
  RequestOptions? lastOptions;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    lastOptions = options;
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object body, int status) => ResponseBody.fromString(
  body is String ? body : '{"ok":true}',
  status,
  headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
);

StudentRepository _repo(_FakeAdapter adapter) {
  final dio = Dio(
    BaseOptions(baseUrl: 'http://10.0.2.2:8000'),
  )..httpClientAdapter = adapter;
  return StudentRepository(dio);
}

void main() {
  test('media URLs use the backend snake_case query names', () {
    final repo = _repo(_FakeAdapter((o) => _json('{}', 200)));
    final audio = Uri.parse(
      repo.skillAudioUrl(
        skillId: 'sk',
        materialId: 'mat',
        classroomId: 'room',
      ),
    );
    expect(audio.path, '/student/skills/sk/audio');
    expect(audio.queryParameters['material_id'], 'mat');
    expect(audio.queryParameters['classroom_id'], 'room');
    expect(audio.queryParameters['supplementary'], 'false');

    final image = Uri.parse(
      repo.skillImageUrl(skillId: 'sk', materialId: 'mat'),
    );
    expect(image.path, '/student/skills/sk/image');
    expect(image.queryParameters['material_id'], 'mat');
  });

  test('identical support signals collapse into one request', () async {
    final adapter = _FakeAdapter((o) => _json('{}', 200));
    final repo = _repo(adapter);

    await repo.supportSignal('hint_used');
    await repo.supportSignal('hint_used');
    expect(adapter.calls, 1);
    expect(adapter.lastOptions?.path, '/student/support-signal');

    // A different signal is a different user action: it still goes out.
    await repo.supportSignal('retry');
    expect(adapter.calls, 2);
  });

  test('support signals never throw, even when the backend is down', () async {
    final repo = _repo(
      _FakeAdapter(
        (o) => throw DioException.connectionError(
          requestOptions: o,
          reason: 'offline',
        ),
      ),
    );
    await repo.supportSignal('hint_used', throttle: Duration.zero);
  });

  test('skillAudioBytes returns bytes on 200', () async {
    final wav = Uint8List.fromList([
      0x52, 0x49, 0x46, 0x46, 0x00, 0x00, 0x00, 0x00,
      0x57, 0x41, 0x56, 0x45, 0x01, 0x02,
    ]);
    final repo = _repo(
      _FakeAdapter(
        (o) => ResponseBody.fromBytes(
          wav,
          200,
          headers: {
            Headers.contentTypeHeader: ['audio/wav'],
          },
        ),
      ),
    );
    final out = await repo.skillAudioBytes(
      skillId: 'sk',
      materialId: 'mat',
      classroomId: 'room',
    );
    expect(out, wav);
  });

  test('skillAudioBytes surfaces 401 so the session can expire cleanly', () async {
    final repo = _repo(
      _FakeAdapter((o) => _json('{"detail":"Not authenticated"}', 401)),
    );
    try {
      await repo.skillAudioBytes(skillId: 'sk', materialId: 'mat');
      fail('expected ApiException');
    } on ApiException catch (e) {
      expect(e.statusCode, 401);
    }
  });

  test('skillImageBytes degrades to null on 503 (lesson continues)', () async {
    final repo = _repo(
      _FakeAdapter((o) => _json('{"detail":"unavailable"}', 503)),
    );
    final out = await repo.skillImageBytes(
      skillId: 'sk',
      materialId: 'mat',
    );
    expect(out, isNull);
  });
}
