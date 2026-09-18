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
///
/// Single source of truth (no parallel booleans): idle → loading → ready →
/// playing ⇄ paused, with stopped (explicit stop/completed) and error
/// (last attempt failed calmly; the lesson always continues).
enum ReadAloudState { idle, loading, ready, playing, paused, stopped, error }

/// Calm message shown when audio cannot play. The lesson always continues.
const String kAudioUnavailableMessage = 'Audio is unavailable right now.';

/// Plays skill/lesson audio (TTS WAV/MP3 via FastAPI).
///
/// The bytes are downloaded through the shared Dio client, so authenticated
/// media uses the normal JWT flow (interceptors, 401 -> sign out, timeouts)
/// instead of bypassing it. Failures are reported as one calm message —
/// learning never breaks. Only one explanation plays at a time: starting
/// a new URL always stops the previous one first (request ids + CancelToken,
/// so Skill A can never cut in after the student moved to Skill B). One tap
/// causes exactly one request: repeat taps while preparing (or while the same
/// URL already plays) reuse the in-flight playback instead of firing again.
/// Small in-memory bytes cache (5 entries) makes repeat taps instant without
/// re-downloading; the backend disk cache makes cold loads fast.
class AudioService {
  AudioService(this._player, this._api) {
    _playerSubscription = _player.playerStateStream.listen((state) {
      if (_activeUrl == null || _disposed) return;
      if (_suppressPlayerCallback) return;
      if (state.processingState == ProcessingState.completed) {
        _emit(ReadAloudState.stopped);
        return;
      }
      // While preparing (setAudioSource) the player reports buffering/loading:
      // keep the explicit loading state instead of flickering.
      if (_loading) return;
      _emit(
        state.processingState == ProcessingState.buffering
            ? ReadAloudState.loading
            : state.playing
            ? ReadAloudState.playing
            : _state == ReadAloudState.error
            ? ReadAloudState.error
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
  bool _suppressPlayerCallback = false;
  String? _activeUrl;
  CancelToken? _downloadToken;

  /// Tiny LRU-ish bytes cache: repeat taps / back-navigation replay instantly.
  final Map<String, Uint8List> _bytesCache = {};
  static const int _maxCacheEntries = 5;

  /// Lip-sync envelopes keyed by audio URL: mouth-openness levels in [0, 1]
  /// over FRACTIONS of total duration (server contract, version 1). The
  /// avatar maps playback position/duration to an index with one rule, so
  /// the mouth follows the actual words for WAV (true energy) and MP3
  /// (word-timed) alike. Missing envelope degrades to cadence animation.
  final Map<String, List<double>> _envelopeCache = {};
  int _envelopeRequest = 0;

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
        if (!_disposed && request == _request) {
          _activeUrl = null;
          _emit(ReadAloudState.error);
        }
      }),
    );
  }

  Stream<bool> get playingStream =>
      _player.playerStateStream.map((s) => s.playing);

  /// The URL currently loaded (or loading), if any.
  String? get activeUrl => _activeUrl;

  /// Idle / loading / ready / playing / paused / stopped / error.
  Stream<ReadAloudState> get stateStream => _uiState.stream;

  void _emit(ReadAloudState state) {
    if (_disposed || _uiState.isClosed) return;
    _state = state;
    _uiState.add(state);
  }

  void _resetToError() {
    _activeUrl = null;
    _emit(ReadAloudState.error);
  }

  void _cacheBytes(String url, Uint8List bytes) {
    _bytesCache[url] = bytes;
    if (_bytesCache.length > _maxCacheEntries) {
      final evicted = _bytesCache.keys.first;
      _bytesCache.remove(evicted);
      _envelopeCache.remove(evicted);
    }
  }

  /// Cached lip-sync levels for [audioUrl], or null when unavailable (the
  /// avatar then uses its cadence animation — the lesson never breaks).
  List<double>? envelopeFor(String audioUrl) => _envelopeCache[audioUrl];

  /// Mouth openness (0..1) at [position] in [duration] from cached levels.
  /// Null when the envelope or duration is missing — callers fall back.
  double? lipSyncLevel(String audioUrl, Duration position, Duration? duration) {
    final levels = _envelopeCache[audioUrl];
    if (levels == null || levels.isEmpty) return null;
    final totalMs = duration?.inMilliseconds ?? 0;
    if (totalMs <= 0) return null;
    var index = (position.inMilliseconds / totalMs * levels.length).floor();
    if (index < 0) index = 0;
    if (index >= levels.length) index = levels.length - 1;
    return levels[index].clamp(0.0, 1.0);
  }

  /// Best-effort fetch of the tiny envelope JSON (authenticated, same JWT
  /// flow as audio). Cached per audio URL; failures are silent and never
  /// throw — lip-sync is enhancement, never a lesson blocker.
  Future<void> warmEnvelope(String audioUrl, String envelopeUrl) async {
    if (_disposed || _envelopeCache.containsKey(audioUrl)) return;
    final request = ++_envelopeRequest;
    try {
      final res = await _api.dio.get<dynamic>(envelopeUrl);
      if (_disposed || request != _envelopeRequest) return;
      final data = res.data;
      if (data is Map<String, dynamic>) {
        final levels = _levelsFromJson(data);
        if (levels != null) {
          _envelopeCache[audioUrl] = levels;
          if (_envelopeCache.length > _maxCacheEntries) {
            _envelopeCache.remove(_envelopeCache.keys.first);
          }
        }
      }
    } catch (_) {}
  }

  /// Validates the server envelope contract (version 1, 20..1200 levels).
  static List<double>? _levelsFromJson(Map<String, dynamic> json) {
    try {
      if (json['version'] != 1) return null;
      final raw = json['levels'];
      if (raw is! List || raw.length < 20 || raw.length > 1200) return null;
      final levels = <double>[];
      for (final v in raw) {
        final d = (v as num).toDouble();
        if (d.isNaN) return null;
        levels.add(d.clamp(0.0, 1.0));
      }
      return levels;
    } catch (_) {
      return null;
    }
  }

  /// Start (or restart) reading [url] aloud. Stops anything playing first.
  /// Returns null on success, or a calm message when audio is unavailable.
  /// Never throws: media failure must never break the lesson.
  /// [envelopeUrl] warms the lip-sync envelope for true word-synced mouth
  /// movement; null keeps the local cadence animation.
  Future<String?> playUrl(String url, {String? envelopeUrl}) async {
    if (_disposed) return kAudioUnavailableMessage;
    // Single-flight: a second tap for the same explanation while it is
    // still preparing (or already playing) must not fire another request.
    if (_loading && _activeUrl == url) return null;
    if (!_loading && _activeUrl == url) {
      if (_state == ReadAloudState.playing) return null;
      if (_state == ReadAloudState.paused) {
        await resume();
        return null;
      }
      if (_state == ReadAloudState.ready) {
        _startPlayback();
        return null;
      }
      // stopped/error for the same URL: fall through and replay from cache.
    }
    final request = ++_request;
    // Cancel any stale download: newest student intent wins.
    try {
      _downloadToken?.cancel('superseded');
    } catch (_) {}
    _loading = true;
    _activeUrl = url;
    _emit(ReadAloudState.loading);
    try {
      _suppressPlayerCallback = true;
      try {
        await _player.stop();
      } catch (_) {}
      _suppressPlayerCallback = false;
      final bytes = await _downloadAudio(url, request);
      if (_disposed || request != _request) return null;
      final source = await _toAudioSource(url, bytes);
      if (_disposed || request != _request) return null;
      await _player.setAudioSource(source);
      if (_disposed || request != _request) return null;
      _loading = false;
      _emit(ReadAloudState.ready);
      _emit(ReadAloudState.playing);
      _startPlayback();
      // Lip-sync warms in the background: playback never waits for it, and
      // its failure simply keeps the cadence animation.
      final envUrl = envelopeUrl;
      if (envUrl != null && envUrl.isNotEmpty) {
        unawaited(warmEnvelope(url, envUrl));
      }
      return null;
    } on DioException catch (e) {
      // Cancelled because a newer skill took over: stay silent, keep the
      // newer request's state (do not reset to error).
      if (e.type == DioExceptionType.cancel) return null;
      // 401 already reached the shared interceptor (session handling);
      // 404/503/transport failures all degrade to the same calm line.
      if (request == _request) _resetToError();
      return kAudioUnavailableMessage;
    } catch (_) {
      if (request == _request) _resetToError();
      return kAudioUnavailableMessage;
    } finally {
      if (request == _request) _loading = false;
      if (request == _request) _suppressPlayerCallback = false;
    }
  }

  /// Warm the cache for the likely-next skill without playing anything.
  /// Best-effort: bounded to one URL, failures are silent, never throws.
  Future<void> prefetch(String url) async {
    if (_disposed || url.isEmpty) return;
    if (_bytesCache.containsKey(url)) return;
    if (_loading && _activeUrl == url) return;
    final token = CancelToken();
    try {
      final res = await _api.dio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
        cancelToken: token,
      );
      final data = res.data;
      if (data == null || data.isEmpty) return;
      final bytes = Uint8List.fromList(data);
      if (!_looksLikeAudio(bytes)) return;
      _cacheBytes(url, bytes);
    } catch (_) {}
  }

  /// Download through Dio so the Authorization header, 401 handling and
  /// timeouts match every other API call. Throws on any failure.
  /// Served from the tiny memory cache when available (no re-download).
  Future<Uint8List> _downloadAudio(String url, int request) async {
    final cached = _bytesCache[url];
    if (cached != null && cached.isNotEmpty) return cached;
    final token = CancelToken();
    _downloadToken = token;
    try {
      final res = await _api.dio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
        cancelToken: token,
      );
      final data = res.data;
      if (data == null || data.isEmpty) throw StateError('empty audio');
      final bytes = Uint8List.fromList(data);
      if (!_looksLikeAudio(bytes)) throw StateError('not audio');
      _cacheBytes(url, bytes);
      return bytes;
    } finally {
      if (identical(_downloadToken, token)) _downloadToken = null;
    }
  }

  /// WAV (RIFF....WAVE) or MP3 (ID3 / frame-sync) so the OpenRouter MP3
  /// fallback plays too — an HTML/JSON error page is never handed to the
  /// player as audio.
  bool _looksLikeAudio(Uint8List bytes) {
    if (bytes.length < 12) return false;
    final isWav =
        bytes[0] == 0x52 && // R
        bytes[1] == 0x49 && // I
        bytes[2] == 0x46 && // F
        bytes[3] == 0x46 && // F
        bytes[8] == 0x57 && // W
        bytes[9] == 0x41 && // A
        bytes[10] == 0x56 && // V
        bytes[11] == 0x45; // E
    if (isWav) return true;
    // ID3v2 header.
    if (bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33) return true;
    // MP3 frame sync (0xFFEx).
    if (bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0) return true;
    // Raw PCM wrapped as WAV always starts with RIFF; anything else here is
    // an error page. Unknown containers are rejected rather than guessed.
    return false;
  }

  String _mimeFor(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0x49 &&
        bytes[1] == 0x44 &&
        bytes[2] == 0x33) {
      return 'audio/mpeg';
    }
    if (bytes.length >= 2 && bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0) {
      return 'audio/mpeg';
    }
    return 'audio/wav';
  }

  /// Player source for downloaded bytes. Native plays a temp file (a single
  /// slot is reused: only one explanation plays at a time); web plays a
  /// data URI because there is no shared temp filesystem. MIME matches the
  /// sniffed container (WAV vs MP3), never hardcoded.
  Future<AudioSource> _toAudioSource(String url, Uint8List bytes) async {
    void _unused(String _) {}
    _unused(url);
    if (kIsWeb) {
      return AudioSource.uri(
        Uri.dataFromBytes(bytes, mimeType: _mimeFor(bytes)),
      );
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
      _resetToError();
    }
  }

  /// Stop playback and release the current explanation.
  Future<void> stop() async {
    ++_request;
    try {
      _downloadToken?.cancel('stopped');
    } catch (_) {}
    _loading = false;
    _suppressPlayerCallback = false;
    _activeUrl = null;
    _emit(ReadAloudState.stopped);
    if (_disposed) return;
    try {
      _suppressPlayerCallback = true;
      await _player.stop();
    } catch (_) {
      // Stopping must never break the lesson.
    } finally {
      _suppressPlayerCallback = false;
    }
  }

  void _dispose() {
    _disposed = true;
    try {
      _downloadToken?.cancel('disposed');
    } catch (_) {}
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
