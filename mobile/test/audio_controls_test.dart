import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:sahlha/core/api/api_client.dart';
import 'package:sahlha/core/audio/audio_service.dart';

class Player extends Fake implements AudioPlayer {
  final states = StreamController<PlayerState>.broadcast();
  final playback = Completer<void>();
  int starts = 0;
  int sources = 0;
  @override
  bool get playing => false;
  @override
  Stream<PlayerState> get playerStateStream => states.stream;
  @override
  Future<void> stop() async {}
  @override
  Future<Duration?> setAudioSource(
    AudioSource source, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
  }) async {
    sources++;
    return const Duration(seconds: 30);
  }

  @override
  Future<void> play() {
    starts++;
    return playback.future;
  }

  @override
  Future<void> pause() async {
    states.add(PlayerState(false, ProcessingState.ready));
  }
}

class AudioAdapter implements HttpClientAdapter {
  final gate = Completer<void>();
  List<int>? overrideBytes;
  Map<String, List<String>>? overrideHeaders;
  static const _wav = [
    82,
    73,
    70,
    70,
    0,
    0,
    0,
    0,
    87,
    65,
    86,
    69,
    0,
    0,
  ];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    // Each fetch waits on the gate then returns a FRESH body: sharing one
    // ResponseBody across concurrent downloads would let the first reader
    // consume the stream and make the latest (wanted) request fail.
    await gate.future;
    final bytes = overrideBytes ?? List<int>.from(_wav);
    return ResponseBody.fromBytes(bytes, 200, headers: overrideHeaders);
  }

  @override
  void close({bool force = false}) {}
  void finish() {
    if (!gate.isCompleted) gate.complete();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('audio-controls-test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => temporary.path,
        );
  });
  tearDown(() async {
    await temporary.delete(recursive: true);
  });

  test('playback becomes controllable before the recording finishes', () async {
    final player = Player();
    final adapter = AudioAdapter();
    final api = ApiClient()..dio.httpClientAdapter = adapter;
    final audio = AudioService(player, api);
    final start = audio.playUrl('http://localhost/lesson.wav');
    adapter.finish();
    expect(await start.timeout(const Duration(seconds: 3)), isNull);
    expect(player.playback.isCompleted, isFalse);
    expect(audio.state, ReadAloudState.playing);
    await audio.pause();
    await Future<void>.delayed(Duration.zero);
    expect(audio.state, ReadAloudState.paused);
    await audio.stop();
    expect(audio.state, ReadAloudState.stopped);
    player.playback.complete();
    await player.states.close();
  });

  test('cancel during download prevents late playback', () async {
    final player = Player();
    final adapter = AudioAdapter();
    final api = ApiClient()..dio.httpClientAdapter = adapter;
    final audio = AudioService(player, api);
    final start = audio.playUrl('http://localhost/lesson.wav');
    await audio.stop();
    adapter.finish();
    await start;
    expect(player.starts, 0);
    expect(player.sources, 0);
    expect(audio.state, ReadAloudState.stopped);
    await player.states.close();
  });

  test('rapid navigation plays only the latest skill', () async {
    final player = Player();
    final adapter = AudioAdapter();
    final api = ApiClient()..dio.httpClientAdapter = adapter;
    final audio = AudioService(player, api);
    // Skill A starts, student immediately opens B then C (all downloads share
    // the one test response; request ids still guarantee only C proceeds).
    final a = audio.playUrl('http://localhost/skill-a.wav');
    final b = audio.playUrl('http://localhost/skill-b.wav');
    final c = audio.playUrl('http://localhost/skill-c.wav');
    adapter.finish();
    await Future.wait([a, b, c]);
    expect(audio.activeUrl, 'http://localhost/skill-c.wav');
    expect(player.sources, 1);
    expect(player.starts, 1);
    expect(audio.state, ReadAloudState.playing);
    player.playback.complete();
    await player.states.close();
  });

  test('mp3 fallback bytes play with the right container', () async {
    final player = Player();
    final adapter = AudioAdapter();
    final api = ApiClient()..dio.httpClientAdapter = adapter;
    final audio = AudioService(player, api);
    // MP3 (ID3) must be accepted, not rejected as "not audio".
    final start = audio.playUrl('http://localhost/lesson.mp3');
    adapter
      ..overrideBytes = [
        73, 68, 51, // ID3
        0, 0, 0, 0, 0, 0, 0, 0, 0,
      ]
      ..overrideHeaders = {
        Headers.contentTypeHeader: ['audio/mpeg'],
      }
      ..finish();
    expect(await start.timeout(const Duration(seconds: 3)), isNull);
    expect(player.sources, 1);
    expect(audio.state, ReadAloudState.playing);
    player.playback.complete();
    await player.states.close();
  });
}
