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
}
