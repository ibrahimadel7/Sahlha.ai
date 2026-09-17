import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:just_audio/just_audio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../api/api_client.dart';
import 'audio_tempfile_stub.dart'
    if (dart.library.io) 'audio_tempfile_io.dart'
    as tempfile;

part 'audio_service.g.dart';

/// UI-facing playback state for read-aloud explanations.
enum ReadAloudState { idle, loading, playing, paused }

/// Calm message shown when audio cannot play. The lesson always continues.
const String kAudioUnavailableMessage = 'Audio is unavailable right now.';

/// Plays skill/lesson audio (Groq TTS WAVs via FastAPI).
///
/// The bytes are downloaded through the shared Dio client, so authenticated
/// media uses the normal JWT flow (interceptors, 401 -> sign out, timeouts)
/// instead of bypassing it. Failures are reported as one calm message —
/// learning never breaks. Only one explanation plays at a time: starting
/// a new URL always stops the previous one first. One tap causes exactly one
/// request: repeat taps while preparing (or while the same URL already
/// plays) reuse the in-flight playback instead of firing again.
class AudioService {
  AudioService(this._player, this._api) {
    _playerSubscription = _player.playerStateStream.listen((state) {
      if (_loading || _activeUrl == null || _disposed) return;
      if (state.processingState == ProcessingState.completed) {
        _emit(ReadAloudState.idle);
        return;
      }
      _emit(
        state.processingState == ProcessingState.buffering
            ? ReadAloudState.loading
            : state.playing
            ? ReadAloudState.playing
            : ReadAloudState.paused,
      );
    });
  }

  final AudioPlayer _player;
  final ApiClient _api;
  final _uiState = StreamController<ReadAloudState>.broadcast();
  StreamSubscription<PlayerState>? _playerSubscription;

  int _request = 0;
  ReadAloudState _state = ReadAloudState.idle;
  bool _loading = false;
  bool _disposed = false;
  String? _activeUrl;

  bool get playing => _player.playing;
  ReadAloudState get state => _state;
  Duration get position => _player.position;
  Duration? get duration => _player.duration;
  double get speed => _player.speed;
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Future<void> seek(Duration value) async {
    if (_disposed || _activeUrl == null) return;
    try {
      await _player.seek(value);
    } catch (_) {}
  }

  Future<void> setSpeed(double value) async {
    if (_disposed) return;
    try {
      await _player.setSpeed(value);
    } catch (_) {}
  }

  void _startPlayback() {
    final request = _request;
    unawaited(
      _player.play().catchError((Object error) {
        if (!_disposed && request == _request) _reset();
      }),
    );
  }

  Stream<bool> get playingStream =>
      _player.playerStateStream.map((s) => s.playing);

  /// The URL currently loaded (or loading), if any.
  String? get activeUrl => _activeUrl;

  /// Idle / loading / playing / paused for read-aloud UI.
  Stream<ReadAloudState> get stateStream => _uiState.stream;

  void _emit(ReadAloudState state) {
    if (_disposed || _uiState.isClosed) return;
    _state = state;
    _uiState.add(state);
  }

  void _reset() {
    _activeUrl = null;
    _emit(ReadAloudState.idle);
  }

  /// Start (or restart) reading [url] aloud. Stops anything playing first.
  /// Returns null on success, or a calm message when audio is unavailable.
  /// Never throws: media failure must never break the lesson.
  Future<String?> playUrl(String url) async {
    if (_disposed) return kAudioUnavailableMessage;
    // Single-flight: a second tap for the same explanation while it is
    // still preparing (or already playing) must not fire another request.
    if (_loading && _activeUrl == url) return null;
    if (!_loading && _activeUrl == url) {
      if (_state == ReadAloudState.playing) return null;
      await resume();
      return null;
    }
    final request = ++_request;
    _loading = true;
    _activeUrl = url;
    _emit(ReadAloudState.loading);
    try {
      await _player.stop();
      final bytes = await _downloadAudio(url);
      if (_disposed || request != _request) return null;
      final source = await _toAudioSource(url, bytes);
      if (_disposed || request != _request) return null;
      await _player.setAudioSource(source);
      if (_disposed || request != _request) return null;
      _loading = false;
      _emit(ReadAloudState.playing);
      _startPlayback();
      return null;
    } on DioException {
      // 401 already reached the shared interceptor (session handling);
      // 404/503/transport failures all degrade to the same calm line.
      if (request == _request) _reset();
      return kAudioUnavailableMessage;
    } catch (_) {
      if (request == _request) _reset();
      return kAudioUnavailableMessage;
    } finally {
      if (request == _request) _loading = false;
    }
  }

  /// Download through Dio so the Authorization header, 401 handling and
  /// timeouts match every other API call. Throws on any failure.
  Future<Uint8List> _downloadAudio(String url) async {
    final res = await _api.dio.get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes),
    );
    final data = res.data;
    if (data == null || data.isEmpty) throw StateError('empty audio');
    final bytes = Uint8List.fromList(data);
    if (!_looksLikeWav(bytes)) throw StateError('not audio');
    return bytes;
  }

  /// Minimal WAV sanity check (RIFF....WAVE) so an HTML/JSON error page is
  /// never handed to the player as audio.
  bool _looksLikeWav(Uint8List bytes) {
    if (bytes.length < 12) return false;
    return bytes[0] == 0x52 && // R
        bytes[1] == 0x49 && // I
        bytes[2] == 0x46 && // F
        bytes[3] == 0x46 && // F
        bytes[8] == 0x57 && // W
        bytes[9] == 0x41 && // A
        bytes[10] == 0x56 && // V
        bytes[11] == 0x45; // E
  }

  /// Player source for downloaded bytes. Native plays a temp file (a single
  /// slot is reused: only one explanation plays at a time); web plays a
  /// data URI because there is no shared temp filesystem.
  Future<AudioSource> _toAudioSource(String url, Uint8List bytes) async {
    if (kIsWeb) {
      return AudioSource.uri(Uri.dataFromBytes(bytes, mimeType: 'audio/wav'));
    }
    return AudioSource.file(await tempfile.writeTempAudio(bytes));
  }

  /// Pause the current explanation, keeping the position for resume.
  Future<void> pause() async {
    if (_activeUrl == null || _disposed) return;
    try {
      await _player.pause();
    } catch (_) {
      // Pausing must never break the lesson.
    }
  }

  /// Resume a paused explanation.
  Future<void> resume() async {
    if (_activeUrl == null || _disposed) return;
    try {
      if (_player.processingState == ProcessingState.completed) {
        await _player.seek(Duration.zero);
      }
      _startPlayback();
    } catch (_) {
      _reset();
    }
  }

  /// Stop playback and release the current explanation.
  Future<void> stop() async {
    ++_request;
    _loading = false;
    _activeUrl = null;
    _emit(ReadAloudState.idle);
    if (_disposed) return;
    try {
      await _player.stop();
    } catch (_) {
      // Stopping must never break the lesson.
    }
  }

  void _dispose() {
    _disposed = true;
    _playerSubscription?.cancel();
    if (!_uiState.isClosed) _uiState.close();
  }
}

@riverpod
AudioService audioService(Ref ref) {
  final player = AudioPlayer();
  final service = AudioService(player, ref.watch(apiClientProvider));
  ref.onDispose(() {
    service._dispose();
    player.dispose();
  });
  return service;
}
