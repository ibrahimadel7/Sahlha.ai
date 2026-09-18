import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sahlha/core/audio/audio_service.dart';
import 'package:sahlha/features/student/presentation/widgets/audio_companion.dart';
import 'package:sahlha/features/student/presentation/widgets/sahlha_companion.dart';

class Playback extends Fake implements AudioService {
  final events = StreamController<ReadAloudState>.broadcast();
  @override
  String? activeUrl = 'lesson';
  @override
  ReadAloudState state = ReadAloudState.idle;
  @override
  Stream<ReadAloudState> get stateStream => events.stream;
}

/// Minimal service with a scripted envelope: loud - quiet - loud.
class SyncPlayback extends Fake implements AudioService {
  final events = StreamController<ReadAloudState>.broadcast();
  @override
  String? activeUrl = 'lesson';
  @override
  ReadAloudState state = ReadAloudState.playing;
  @override
  Stream<ReadAloudState> get stateStream => events.stream;

  Duration position = Duration.zero;
  Duration? duration = const Duration(seconds: 10);
  static const levels = [0.9, 0.9, 0.9, 0.0, 0.0, 0.0, 0.0, 0.9, 0.9, 0.9];

  @override
  double? lipSyncLevel(String audioUrl, Duration position, Duration? duration) {
    final totalMs = duration?.inMilliseconds ?? 0;
    if (totalMs <= 0 || audioUrl != 'lesson') return null;
    var index = (position.inMilliseconds / totalMs * levels.length).floor();
    index = index.clamp(0, levels.length - 1);
    return levels[index];
  }
}

void main() {
  testWidgets(
    'avatar follows playback, pause, completion, and scoped audio without requests',
    (tester) async {
      final player = Playback();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [audioServiceProvider.overrideWithValue(player)],
          child: const MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: true),
              child: AudioCompanion(url: 'lesson'),
            ),
          ),
        ),
      );
      for (final entry in {
        ReadAloudState.loading: CompanionMood.listening,
        ReadAloudState.playing: CompanionMood.speaking,
        ReadAloudState.paused: CompanionMood.idle,
        ReadAloudState.idle: CompanionMood.idle,
      }.entries) {
        player.events.add(entry.key);
        await tester.pumpAndSettle();
        expect(
          tester.widget<SahlhaCompanion>(find.byType(SahlhaCompanion)).mood,
          entry.value,
        );
        expect(tester.binding.transientCallbackCount, 0);
      }
      player.activeUrl = 'another lesson';
      player.events.add(ReadAloudState.playing);
      await tester.pumpAndSettle();
      expect(
        tester.widget<SahlhaCompanion>(find.byType(SahlhaCompanion)).mood,
        CompanionMood.idle,
      );
      await tester.pumpWidget(const SizedBox());
      await player.events.close();
    },
  );

  testWidgets('mouth follows the envelope position while playing', (tester) async {
    final player = SyncPlayback();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [audioServiceProvider.overrideWithValue(player)],
        child: const MaterialApp(home: AudioCompanion(url: 'lesson')),
      ),
    );
    player.events.add(ReadAloudState.playing);
    await tester.pump();

    double? mouth() =>
        tester.widget<SahlhaCompanion>(find.byType(SahlhaCompanion)).mouthOpen;

    // Loud span (1s of 10s): mouth opens.
    player.position = const Duration(seconds: 1);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      tester.widget<SahlhaCompanion>(find.byType(SahlhaCompanion)).mood,
      CompanionMood.speaking,
    );
    expect(mouth(), isNotNull);
    expect(mouth()!, greaterThan(0.6));

    // Silent span (5s of 10s): mouth relaxes closed.
    player.position = const Duration(seconds: 5);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(mouth()!, lessThan(0.3));

    // Pause: avatar leaves speaking mood.
    player.events.add(ReadAloudState.paused);
    await tester.pump();
    expect(
      tester.widget<SahlhaCompanion>(find.byType(SahlhaCompanion)).mood,
      CompanionMood.idle,
    );
    await tester.pumpWidget(const SizedBox());
    await player.events.close();
  });
}
