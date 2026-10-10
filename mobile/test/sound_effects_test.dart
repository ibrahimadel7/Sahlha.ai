import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sahlha/core/audio/sound_effects.dart';

/// In-memory fake: records what the service asked the player to do.
/// No platform channels, so these tests run anywhere.
class FakeSfxPlayer implements SfxPlayer {
  FakeSfxPlayer({this.failOnAsset = false});
  final bool failOnAsset;
  @override
  bool playing = false;
  final List<String> assets = [];
  final List<double> volumes = [];
  int plays = 0;
  int stops = 0;

  @override
  Future<void> setAsset(String assetPath) async {
    if (failOnAsset) throw StateError('missing: $assetPath');
    assets.add(assetPath);
  }

  @override
  Future<void> setVolume(double volume) async => volumes.add(volume);

  @override
  Future<void> play() async {
    plays++;
    playing = true;
  }

  @override
  Future<void> stop() async {
    stops++;
    playing = false;
  }

  @override
  Future<void> dispose() async {
    playing = false;
  }
}

void main() {
  group('SoundEffect config', () {
    test('every event has a distinct bundled asset', () {
      final paths = SoundEffect.values.map((e) => e.assetPath).toList();
      expect(paths.toSet().length, SoundEffect.values.length);
      for (final path in paths) {
        expect(path, startsWith('assets/sounds/'));
        expect(path, endsWith('.wav'));
      }
      expect(SoundEffect.correct.assetPath, 'assets/sounds/correct.wav');
      expect(SoundEffect.wrong.assetPath, 'assets/sounds/wrong.wav');
      expect(SoundEffect.tap.assetPath, 'assets/sounds/tap.wav');
      expect(
        SoundEffect.skillComplete.assetPath,
        'assets/sounds/skill_complete.wav',
      );
      expect(
        SoundEffect.lessonComplete.assetPath,
        'assets/sounds/lesson_complete.wav',
      );
      expect(SoundEffect.error.assetPath, 'assets/sounds/error.wav');
    });

    test('volumes stay consistent and non-intrusive', () {
      for (final effect in SoundEffect.values) {
        expect(effect.volume, greaterThan(0));
        expect(effect.volume, lessThanOrEqualTo(0.60));
      }
      // Tap is the quietest; celebrations are the loudest but still calm.
      expect(SoundEffect.tap.volume, lessThan(SoundEffect.correct.volume));
      expect(
        SoundEffect.lessonComplete.volume,
        greaterThanOrEqualTo(SoundEffect.skillComplete.volume),
      );
    });
  });

  group('complete interaction flow', () {
    test('select correct answer -> immediate correct sound', () async {
      final player = FakeSfxPlayer();
      final sfx = SoundEffectsService(player);
      await sfx.correct();
      expect(player.assets, ['assets/sounds/correct.wav']);
      expect(player.volumes, [SoundEffect.correct.volume]);
      expect(player.plays, 1);
    });

    test('select wrong answer -> immediate wrong sound', () async {
      final player = FakeSfxPlayer();
      final sfx = SoundEffectsService(player);
      await sfx.wrong();
      expect(player.assets, ['assets/sounds/wrong.wav']);
      expect(player.plays, 1);
    });

    test('complete skill -> rewarding completion sound', () async {
      final player = FakeSfxPlayer();
      final sfx = SoundEffectsService(player);
      expect(
        SoundEffectsService.completionEffectFor(mastered: true),
        SoundEffect.skillComplete,
      );
      await sfx.skillComplete();
      expect(player.assets, ['assets/sounds/skill_complete.wav']);
      expect(player.plays, 1);
    });

    test('complete lesson/quiz -> celebration sound', () async {
      final player = FakeSfxPlayer();
      final sfx = SoundEffectsService(player);
      expect(
        SoundEffectsService.completionEffectFor(mastered: false),
        SoundEffect.lessonComplete,
      );
      await sfx.lessonComplete();
      expect(player.assets, ['assets/sounds/lesson_complete.wav']);
      expect(player.plays, 1);
    });

    test('choice tap + error nudge play their own sounds', () async {
      final player = FakeSfxPlayer();
      final sfx = SoundEffectsService(player);
      await sfx.tap();
      expect(player.assets.last, 'assets/sounds/tap.wav');
      await sfx.failure();
      expect(player.assets.last, 'assets/sounds/error.wav');
    });
  });

  group('overlap / stacking guards', () {
    test('rapid repeats of the same sound are throttled', () async {
      var now = DateTime(2026, 1, 1);
      final player = FakeSfxPlayer();
      final sfx = SoundEffectsService(player, clock: () => now);
      await sfx.tap();
      now = now.add(const Duration(milliseconds: 10));
      await sfx.tap();
      expect(player.plays, 1);
      now = now.add(const Duration(milliseconds: 200));
      await sfx.tap();
      expect(player.plays, 2);
    });

    test('tap never interrupts success; success interrupts tap', () async {
      var now = DateTime(2026, 1, 1);
      final player = FakeSfxPlayer();
      final sfx = SoundEffectsService(player, clock: () => now);
      await sfx.tap(); // now "playing" a tap
      expect(player.playing, isTrue);
      now = now.add(const Duration(milliseconds: 10));
      await sfx.tap();
      // throttled anyway; now a correct answer arrives right after the tap
      now = now.add(const Duration(milliseconds: 200));
      await sfx.correct();
      expect(player.assets.last, 'assets/sounds/correct.wav');
      expect(player.stops, greaterThanOrEqualTo(1));

      // Fresh service: a tap arriving while correct plays stays silent.
      final player2 = FakeSfxPlayer();
      final sfx2 = SoundEffectsService(player2, clock: () => now);
      await sfx2.correct();
      expect(player2.playing, isTrue);
      now = now.add(const Duration(milliseconds: 10));
      await sfx2.tap();
      expect(player2.assets, ['assets/sounds/correct.wav']);
      expect(player2.plays, 1);
    });
  });

  group('robustness', () {
    test('disabled service stays completely silent', () async {
      final player = FakeSfxPlayer();
      final sfx = SoundEffectsService(player, enabled: false);
      await sfx.correct();
      await sfx.wrong();
      await sfx.tap();
      await sfx.skillComplete();
      await sfx.lessonComplete();
      await sfx.failure();
      expect(player.plays, 0);
      expect(player.assets, isEmpty);
    });

    test('missing/failed files never throw', () async {
      final player = FakeSfxPlayer(failOnAsset: true);
      final sfx = SoundEffectsService(player);
      await sfx.correct();
      await sfx.wrong();
      await sfx.tap();
      await sfx.skillComplete();
      await sfx.lessonComplete();
      await sfx.failure();
      expect(player.plays, 0);
    });

    test('disabling mid-flight keeps later plays silent', () async {
      final player = FakeSfxPlayer();
      final sfx = SoundEffectsService(player);
      await sfx.correct();
      expect(player.plays, 1);
      sfx.setEnabled(false);
      await sfx.wrong();
      expect(player.plays, 1);
    });
  });

  group('bundled assets (regression: silence when files do not ship)', () {
    test('every sound asset loads from the bundle as valid WAV', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      for (final effect in SoundEffect.values) {
        final data = await rootBundle.load(effect.assetPath);
        final bytes = data.buffer.asUint8List();
        // Audible content: more than a bare header.
        expect(bytes.length, greaterThan(1000), reason: effect.assetPath);
        // RIFF....WAVE header (matches the TTS sniffing in AudioService).
        expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
        expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
      }
    });
  });

  group('provider lifecycle (regression: autoDispose = total silence)', () {
    test('toggle reaches the shared service without recreating it', () async {
      // The real audioplayers AudioPlayer needs a Flutter binding +
      // platform channels, so the player provider is overridden with a
      // fake: this test targets Riverpod wiring, not native playback.
      final container = ProviderContainer(
        overrides: [sfxPlayerProvider.overrideWithValue(FakeSfxPlayer())],
      );
      addTearDown(container.dispose);
      final first = container.read(soundEffectsProvider);
      expect(first.enabled, isTrue);
      await container.read(soundEnabledProvider.notifier).setEnabled(false);
      await Future<void>.delayed(Duration.zero);
      expect(first.enabled, isFalse);
      // Same instance: the player is NOT rebuilt on toggle, and the
      // provider survives with zero listeners (keepAlive). With the old
      // autoDispose + watch setup this was a new, immediately-disposed
      // instance and the app stayed silent.
      expect(identical(container.read(soundEffectsProvider), first), isTrue);
    });
  });
}
