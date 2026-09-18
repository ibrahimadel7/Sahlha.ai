import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:just_audio/just_audio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'sound_effects.g.dart';

/// Short learning-feedback sounds, centralized in one place.
///
/// Asset layout (all tiny local WAVs, total < 150KB):
/// - assets/sounds/correct.wav         pleasant two-note chime (correct answer)
/// - assets/sounds/wrong.wav           gentle descending pair (wrong answer, never harsh)
/// - assets/sounds/tap.wav             very subtle blip (choice selection)
/// - assets/sounds/skill_complete.wav  rewarding three-note ascent (skill done)
/// - assets/sounds/lesson_complete.wav short four-note celebration (lesson/quiz done)
/// - assets/sounds/error.wav           soft single-tone nudge (real app errors)
enum SoundEffect {
  correct,
  wrong,
  tap,
  skillComplete,
  lessonComplete,
  error,
}

/// Per-event tuning: asset, playback volume (kept low on purpose so
/// feedback never shouts over the lesson), and minimum gap between
/// repeats of the SAME sound (prevents stacking when a child taps fast).
extension SoundEffectConfig on SoundEffect {
  String get assetPath => switch (this) {
    SoundEffect.correct => 'assets/sounds/correct.wav',
    SoundEffect.wrong => 'assets/sounds/wrong.wav',
    SoundEffect.tap => 'assets/sounds/tap.wav',
    SoundEffect.skillComplete => 'assets/sounds/skill_complete.wav',
    SoundEffect.lessonComplete => 'assets/sounds/lesson_complete.wav',
    SoundEffect.error => 'assets/sounds/error.wav',
  };

  double get volume => switch (this) {
    SoundEffect.correct => 0.50,
    SoundEffect.wrong => 0.40,
    // Tap stays barely-there by design.
    SoundEffect.tap => 0.22,
    SoundEffect.skillComplete => 0.55,
    SoundEffect.lessonComplete => 0.60,
    SoundEffect.error => 0.35,
  };

  Duration get throttle => switch (this) {
    SoundEffect.tap => const Duration(milliseconds: 120),
    SoundEffect.correct || SoundEffect.wrong => const Duration(
      milliseconds: 350,
    ),
    SoundEffect.error => const Duration(milliseconds: 600),
    SoundEffect.skillComplete || SoundEffect.lessonComplete =>
      const Duration(milliseconds: 900),
  };

  /// Tap is lowest: it may never cut off a success/celebration sound.
  /// Success and celebration outrank everything else.
  int get priority => switch (this) {
    SoundEffect.tap => 0,
    SoundEffect.correct || SoundEffect.wrong || SoundEffect.error => 1,
    SoundEffect.skillComplete || SoundEffect.lessonComplete => 2,
  };
}

/// Minimal player surface the service needs. The production
/// implementation wraps a dedicated `just_audio` [AudioPlayer] that is
/// intentionally SEPARATE from the TTS/[AudioService] player, so short
/// feedback can never stop, seek, or reconfigure the lesson voice.
/// Tests inject a fake instead (no platform channels needed).
abstract class SfxPlayer {
  bool get playing;
  Future<void> setAsset(String assetPath);
  Future<void> setVolume(double volume);
  Future<void> play();
  Future<void> stop();
  Future<void> dispose();
}

class JustAudioSfxPlayer implements SfxPlayer {
  JustAudioSfxPlayer(this._player);
  final AudioPlayer _player;

  @override
  bool get playing {
    try {
      return _player.playing;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> setAsset(String assetPath) => _player.setAsset(assetPath);

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}

/// Central sound-effects service. All screens go through here — never
/// create an [AudioPlayer] for UI feedback anywhere else.
///
/// Guarantees:
/// - Never throws: missing/failed assets degrade to silence.
/// - No overlap stacking: one dedicated player + per-sound throttles +
///   priority (celebration interrupts tap; tap never interrupts success).
/// - Never touches TTS: separate player, low volumes, and an
///   ambient/mix session so feedback blends under the lesson voice
///   instead of stealing audio focus.
/// - Respects silence: the shared audio session is configured to
///   `ambient` + `mixWithOthers`, which follows the iOS silent switch
///   and mixes with other audio on Android (see [_configureSession]).
/// - Zero UI jank: callers fire-and-forget with `unawaited(...)`; local
///   assets load in ~10ms and [preload] warms them after first frame.
class SoundEffectsService {
  SoundEffectsService(
    this._player, {
    this._enabled = true,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final SfxPlayer _player;
  final DateTime Function() _clock;
  bool _enabled;
  bool _disposed = false;
  bool _sessionReady = false;

  final Map<SoundEffect, DateTime> _lastPlay = {};
  SoundEffect? _current;

  bool get enabled => _enabled;
  void setEnabled(bool value) => _enabled = value;

  /// Configure the shared audio session for quiet UI cues and warm the
  /// asset bundle. Best-effort, never throws. Safe to call repeatedly;
  /// only the first call configures the session.
  ///
  /// NOTE: no timeouts are used on purpose. This runs fire-and-forget
  /// (see [soundEffects]), and a `Future.timeout` would leave pending
  /// timers behind in widget tests. A slow platform call merely delays
  /// best-effort warming — playback itself always tries directly.
  Future<void> preload() async {
    if (_disposed) return;
    await _configureSession();
    // Warm each asset so the first real tap has no bundle-load delay.
    // Failures are ignored: a missing file simply stays silent later.
    for (final effect in SoundEffect.values) {
      if (_disposed) return;
      try {
        await _player.setAsset(effect.assetPath);
        try {
          await _player.stop();
        } catch (_) {}
      } catch (_) {
        // Keep warming the rest; playback degrades gracefully.
      }
    }
  }

  /// iOS has ONE shared audio session for the whole app (this also
  /// affects the TTS player, which is fine): `ambient` follows the
  /// silent switch, and `mixWithOthers` means a tap/correct chime can
  /// never pause or duck the lesson voice away. Android uses the
  /// sonification/notification attributes so cues behave like system
  /// UI sounds rather than media playback.
  Future<void> _configureSession() async {
    if (_sessionReady) return;
    try {
      final session = await AudioSession.instance;
      await session.configure(
        const AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.ambient,
          avAudioSessionCategoryOptions:
              AVAudioSessionCategoryOptions.mixWithOthers,
          androidAudioAttributes: AndroidAudioAttributes(
            contentType: AndroidAudioContentType.sonification,
            usage: AndroidAudioUsage.notification,
          ),
          androidAudioFocusGainType:
              AndroidAudioFocusGainType.gainTransientMayDuck,
        ),
      );
      _sessionReady = true;
    } catch (_) {
      // Session configuration is enhancement-only: playback still works
      // with platform defaults, and silence compliance degrades to the
      // OS default behavior.
    }
  }

  /// Play [effect] unless disabled, throttled, or preempted. Never throws.
  Future<void> play(SoundEffect effect) async {
    if (_disposed || !_enabled) return;
    final now = _clock();
    final last = _lastPlay[effect];
    if (last != null && now.difference(last) < effect.throttle) return;

    // Overlap guard on the single shared SFX player: a lower-priority
    // sound (tap) never cuts off a higher one (correct/celebration);
    // a higher-priority sound interrupts the lower one so success
    // feedback always wins over the tap that preceded it by milliseconds.
    try {
      if (_player.playing && _current != null) {
        final current = _current!;
        // A lower-priority sound (tap) never cuts off a higher one
        // (correct/celebration). Anything else restarts cleanly on the
        // single shared player — including the same sound after its
        // throttle window (e.g. a deliberate second tap).
        if (effect.priority < current.priority) return;
        try {
          await _player.stop();
        } catch (_) {}
      }
    } catch (_) {
      // If the player state is unreadable, try to play anyway.
    }

    _lastPlay[effect] = now;
    _current = effect;
    try {
      await _configureSession();
      if (_disposed || !_enabled) return;
      await _player.setVolume(effect.volume);
      await _player.setAsset(effect.assetPath);
      if (_disposed || !_enabled) return;
      // The enabled flag is re-checked after each await so turning
      // sounds off mid-load still stays silent.
      await _player.play();
    } catch (_) {
      // Missing asset, codec failure, interrupted load: stay silent.
      // Learning never breaks because of a sound effect.
    }
  }

  Future<void> correct() => play(SoundEffect.correct);
  Future<void> wrong() => play(SoundEffect.wrong);
  Future<void> tap() => play(SoundEffect.tap);
  Future<void> skillComplete() => play(SoundEffect.skillComplete);
  Future<void> lessonComplete() => play(SoundEffect.lessonComplete);
  Future<void> failure() => play(SoundEffect.error);

  /// Which single completion sound to play for a finished lesson/quiz.
  /// A newly-mastered skill gets the rewarding skill sound; any other
  /// finish gets the slightly bigger lesson celebration. Pure helper so
  /// the interaction flow is unit-testable and every caller stays
  /// consistent (exactly one sound per completion, never stacked).
  static SoundEffect completionEffectFor({required bool mastered}) =>
      mastered ? SoundEffect.skillComplete : SoundEffect.lessonComplete;

  void dispose() {
    _disposed = true;
    try {
      unawaited(_player.dispose());
    } catch (_) {}
  }
}

/// Global sound-effects on/off switch, persisted across launches.
///
/// Stored in secure storage (no new dependencies) as '1'/'0'; defaults
/// to ON. Loads lazily so [build] stays synchronous: the UI renders
/// enabled immediately, then corrects itself if storage says otherwise.
///
/// keepAlive: the toggle backs the (also keepAlive) SFX service, so it
/// must survive navigation between screens.
@Riverpod(keepAlive: true)
class SoundEnabled extends _$SoundEnabled {
  static const storageKey = 'sahlha_sound_enabled';
  static const _storage = FlutterSecureStorage();

  @override
  bool build() {
    _restore();
    return true;
  }

  Future<void> _restore() async {
    try {
      final raw = await _storage.read(key: storageKey);
      if (!ref.mounted) return;
      if (raw == '0') state = false;
      if (raw == '1') state = true;
    } catch (_) {}
  }

  Future<void> setEnabled(bool value) async {
    state = value;
    try {
      await _storage.write(key: storageKey, value: value ? '1' : '0');
    } catch (_) {}
  }

  Future<void> toggle() => setEnabled(!state);
}

/// The single shared sound-effects service. Uses its own [AudioPlayer]
/// (never the TTS player's) and disposes the player with the provider.
///
/// keepAlive is REQUIRED, not optional: every screen only `ref.read`s
/// this service inside tap handlers (fire-and-forget), so nothing ever
/// `watch`es it. With plain `@riverpod` (autoDispose) Riverpod would
/// dispose the provider — and its AudioPlayer — right after creation,
/// and every `play()` would return silently. The SFX player must live
/// for the whole app session.
@Riverpod(keepAlive: true)
SoundEffectsService soundEffects(Ref ref) {
  final player = AudioPlayer();
  final service = SoundEffectsService(
    JustAudioSfxPlayer(player),
    enabled: ref.read(soundEnabledProvider),
  );
  // Sync the global toggle without recreating the player: `listen`
  // (unlike `watch`) does not rebuild this provider on toggle.
  ref.listen<bool>(soundEnabledProvider, (_, enabled) {
    service.setEnabled(enabled);
  });
  ref.onDispose(() {
    service.dispose();
  });
  // Warm assets + audio session off the critical path: first real
  // feedback still falls back to lazy load if this hasn't finished.
  unawaited(service.preload());
  return service;
}
