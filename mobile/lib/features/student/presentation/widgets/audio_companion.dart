import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/audio/audio_service.dart';
import 'sahlha_companion.dart';

CompanionMood companionMoodFor(ReadAloudState state) => switch (state) {
  ReadAloudState.playing => CompanionMood.speaking,
  ReadAloudState.loading => CompanionMood.listening,
  ReadAloudState.idle || ReadAloudState.paused => CompanionMood.idle,
};

/// Observes the single authenticated player; never starts or downloads audio.
class AudioCompanion extends ConsumerWidget {
  const AudioCompanion({super.key, required this.url, this.size = 64});
  final String url;
  final double size;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audio = ref.watch(audioServiceProvider);
    return StreamBuilder<ReadAloudState>(
      stream: audio.stateStream,
      initialData: audio.state,
      builder: (_, snapshot) => SahlhaCompanion(
        size: size,
        mood: companionMoodFor(
          audio.activeUrl == url
              ? snapshot.data ?? ReadAloudState.idle
              : ReadAloudState.idle,
        ),
      ),
    );
  }
}
