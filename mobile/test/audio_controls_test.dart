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
  final response = Completer<ResponseBody>();
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => response.future;
  @override
  void close({bool force = false}) {}
  void finish() => response.complete(
    ResponseBody.fromBytes([
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
    ], 200),
  );
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
    expect(audio.state, ReadAloudState.idle);
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
    expect(audio.state, ReadAloudState.idle);
    await player.states.close();
  });
}
