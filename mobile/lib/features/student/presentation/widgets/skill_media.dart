import 'audio_companion.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/audio/audio_service.dart';
import '../../../../core/theme/sahlha_colors.dart';
import '../../data/student_repository.dart';

/// Structured placeholder while a lesson opens: title bar, reading card
/// shape and action shapes, so the layout does not jump when content lands.
class LessonSkeleton extends StatelessWidget {
  const LessonSkeleton({super.key});
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Opening your lesson',
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
        children: [
          Container(
            height: 12,
            width: 140,
            decoration: BoxDecoration(
              color: SahlhaColors.tealSoft,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            height: 10,
            decoration: BoxDecoration(
              color: SahlhaColors.borderSubtle,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            height: 30,
            width: 220,
            decoration: BoxDecoration(
              color: SahlhaColors.tealSoft,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            height: 220,
            decoration: BoxDecoration(
              color: SahlhaColors.surfaceRaised,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: SahlhaColors.borderSubtle),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            height: 54,
            decoration: BoxDecoration(
              color: SahlhaColors.tealSoft,
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ],
      ),
    ),
  );
}

/// A calm supporting visual for one skill: rounded corners, soft border and
/// shadow, gentle fade-in, skeleton while loading. Renders nothing at all
/// when the backend has no image — the lesson simply continues.
class SkillVisualCard extends ConsumerWidget {
  const SkillVisualCard({
    super.key,
    required this.skillId,
    required this.materialId,
    this.classroomId,
    this.supplementary = false,
    this.semanticLabel = 'A picture that supports this skill',
  });

  final String skillId;
  final String materialId;
  final String? classroomId;
  final bool supplementary;
  final String semanticLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = skillImageProvider(
      skillId: skillId,
      materialId: materialId,
      classroomId: classroomId,
      supplementary: supplementary,
    );
    final image = ref.watch(provider);
    Widget unavailable() => Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SahlhaColors.tealSoft,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          const Icon(Icons.image_outlined, color: SahlhaColors.tealDark),
          const SizedBox(height: 8),
          const Text(
            "No picture is available right now.",
            textAlign: TextAlign.center,
          ),
          TextButton.icon(
            onPressed: () => ref.invalidate(provider),
            icon: const Icon(Icons.refresh),
            label: Text(
              "Try picture again",
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(color: SahlhaColors.tealDark),
            ),
          ),
        ],
      ),
    );
    return image.when(
      loading: () => const _ImageSkeleton(),
      error: (_, _) => unavailable(),
      data: (bytes) {
        if (bytes == null) return unavailable();
        return Semantics(
          image: true,
          label: semanticLabel,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: SahlhaColors.borderSubtle),
              boxShadow: SahlhaShadows.soft,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: AspectRatio(
                aspectRatio: 16 / 10,
                child: Image.memory(
                  bytes,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  frameBuilder:
                      (context, child, frame, wasSynchronouslyLoaded) {
                        if (wasSynchronouslyLoaded || frame != null) {
                          return AnimatedOpacity(
                            opacity: frame == null ? 0 : 1,
                            duration: MediaQuery.disableAnimationsOf(context)
                                ? Duration.zero
                                : const Duration(milliseconds: 350),
                            curve: Curves.easeOut,
                            child: child,
                          );
                        }
                        return const _ImageSkeleton(borderless: true);
                      },
                  errorBuilder: (_, _, _) => unavailable(),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ImageSkeleton extends StatelessWidget {
  const _ImageSkeleton({this.borderless = false});
  final bool borderless;
  @override
  Widget build(BuildContext context) {
    final radius = borderless ? BorderRadius.zero : BorderRadius.circular(20);
    return ClipRRect(
      borderRadius: radius,
      child: AspectRatio(
        aspectRatio: 16 / 10,
        child: Container(
          decoration: BoxDecoration(
            color: SahlhaColors.surfaceTealSoft,
            borderRadius: radius,
            border: borderless
                ? null
                : Border.all(color: SahlhaColors.borderSubtle),
          ),
          child: const Center(
            child: Icon(
              Icons.image_outlined,
              color: SahlhaColors.muted,
              size: 34,
            ),
          ),
        ),
      ),
    );
  }
}

/// Full lesson player using authenticated backend audio.
class ReadAloudButton extends ConsumerStatefulWidget {
  const ReadAloudButton({
    super.key,
    required this.skillId,
    required this.materialId,
    this.classroomId,
    this.supplementary = false,
  });

  final String skillId;
  final String materialId;
  final String? classroomId;
  final bool supplementary;

  @override
  ConsumerState<ReadAloudButton> createState() => _ReadAloudButtonState();
}

class _ReadAloudButtonState extends ConsumerState<ReadAloudButton>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  late final String _url = ref
      .read(studentRepositoryProvider)
      .skillAudioUrl(
        skillId: widget.skillId,
        materialId: widget.materialId,
        classroomId: widget.classroomId,
        supplementary: widget.supplementary,
      );
  late final String _envelopeUrl = ref
      .read(studentRepositoryProvider)
      .skillEnvelopeUrl(
        skillId: widget.skillId,
        materialId: widget.materialId,
        classroomId: widget.classroomId,
        supplementary: widget.supplementary,
      );

  /// Cached on every build: `ref` cannot be used in [dispose].
  AudioService? _audio;

  @override
  void dispose() {
    // Leaving the skill (or switching skills) stops this explanation so
    // two readings never overlap. The service is cached in a field because
    // `ref` is unsafe to use once the widget is unmounted.
    final audio = _audio;
    if (audio != null && audio.activeUrl == _url) {
      audio.stop();
    }
    super.dispose();
  }

  Future<void> _toggle(ReadAloudState state) async {
    final audio = ref.read(audioServiceProvider);
    HapticFeedback.selectionClick();
    if (state == ReadAloudState.playing) {
      await audio.pause();
      return;
    }
    if (state == ReadAloudState.paused && audio.activeUrl == _url) {
      await audio.resume();
      return;
    }
    final err = await audio.playUrl(_url, envelopeUrl: _envelopeUrl);
    if (err != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err), duration: const Duration(seconds: 2)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // Watching keeps the shared player alive while this skill is visible.
    final audio = ref.watch(audioServiceProvider);
    _audio = audio;
    return StreamBuilder<ReadAloudState>(
      stream: audio.stateStream,
      initialData: audio.activeUrl == _url ? audio.state : ReadAloudState.idle,
      builder: (context, snap) {
        var state = snap.data ?? ReadAloudState.idle;
        if (audio.activeUrl != _url) state = ReadAloudState.idle;
        final busy = state == ReadAloudState.loading;
        final ready = !busy && audio.activeUrl == _url;
        final text = Theme.of(context).textTheme;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFE6FAF7), Color(0xFFD2F1EC)],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: SahlhaColors.joyTeal.withValues(alpha: 0.25),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AudioCompanion(url: _url, size: 52),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.headphones_rounded,
                              size: 16,
                              color: SahlhaColors.joyTealDark,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Listen to this explanation',
                                style: text.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          switch (state) {
                            ReadAloudState.loading ||
                            ReadAloudState.ready =>
                              'Getting the voice ready…',
                            ReadAloudState.playing => 'Sahlha is reading…',
                            ReadAloudState.paused => 'Paused — resume anytime.',
                            ReadAloudState.stopped => 'Finished — replay anytime.',
                            ReadAloudState.error =>
                              'Voice unavailable — try again soon.',
                            ReadAloudState.idle =>
                              'Hear it in a friendly voice.',
                          },
                          style: text.bodySmall?.copyWith(
                            color: SahlhaColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              StreamBuilder<Duration?>(
                stream: audio.durationStream,
                initialData: audio.duration,
                builder: (context, durationSnapshot) => StreamBuilder<Duration>(
                  stream: audio.positionStream,
                  initialData: audio.position,
                  builder: (context, positionSnapshot) {
                    final total = ready
                        ? (durationSnapshot.data ?? Duration.zero)
                        : Duration.zero;
                    final position = ready
                        ? (positionSnapshot.data ?? Duration.zero)
                        : Duration.zero;
                    final max = total.inMilliseconds.toDouble();
                    final double value = position.inMilliseconds
                        .toDouble()
                        .clamp(0.0, max > 0 ? max : 1.0)
                        .toDouble();
                    return Column(
                      children: [
                        Row(
                          children: [
                            GestureDetector(
                              onTap: busy ? null : () => _toggle(state),
                              child: Container(
                                width: 52,
                                height: 52,
                                decoration: const BoxDecoration(
                                  color: SahlhaColors.joyTeal,
                                  shape: BoxShape.circle,
                                ),
                                child: busy
                                    ? const Padding(
                                        padding: EdgeInsets.all(14),
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Icon(
                                        state == ReadAloudState.playing
                                            ? Icons.pause_rounded
                                            : Icons.play_arrow_rounded,
                                        color: Colors.white,
                                        size: 28,
                                      ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                children: [
                                  // Tiny waveform-ish bars (decorative,
                                  // progress-driven, reduced-motion safe).
                                  SizedBox(
                                    height: 22,
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        for (var i = 0; i < 24; i++)
                                          Expanded(
                                            child: Container(
                                              margin:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 1.5,
                                                  ),
                                              height:
                                                  6 +
                                                  (max > 0
                                                      ? ((i / 24) <=
                                                                (value /
                                                                    (max > 0
                                                                        ? max
                                                                        : 1))
                                                            ? 14
                                                            : 8)
                                                      : 8),
                                              decoration: BoxDecoration(
                                                color:
                                                    (max > 0 &&
                                                        (i / 24) <=
                                                            (value / max))
                                                    ? SahlhaColors.joyTeal
                                                    : SahlhaColors.joyTeal
                                                          .withValues(
                                                            alpha: 0.3,
                                                          ),
                                                borderRadius:
                                                    BorderRadius.circular(3),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      trackHeight: 6,
                                      thumbShape: const RoundSliderThumbShape(
                                        enabledThumbRadius: 8,
                                      ),
                                      overlayShape:
                                          const RoundSliderOverlayShape(
                                            overlayRadius: 14,
                                          ),
                                      activeTrackColor: SahlhaColors.joyTeal,
                                      inactiveTrackColor: Colors.white
                                          .withValues(alpha: 0.8),
                                      thumbColor: SahlhaColors.joyTealDark,
                                    ),
                                    child: Slider(
                                      semanticFormatterCallback: (v) =>
                                          '${(v / 1000).round()} seconds',
                                      min: 0.0,
                                      max: max > 0 ? max : 1.0,
                                      value: value,
                                      onChanged: ready && max > 0
                                          ? (v) => audio.seek(
                                              Duration(milliseconds: v.round()),
                                            )
                                          : null,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_time(position), style: text.bodySmall),
                            Row(
                              children: [
                                GestureDetector(
                                  onTap: () async {
                                    final next = audio.speed >= 2.0
                                        ? 0.75
                                        : audio.speed >= 1.5
                                        ? 2.0
                                        : audio.speed >= 1.25
                                        ? 1.5
                                        : audio.speed >= 1.0
                                        ? 1.25
                                        : 1.0;
                                    await audio.setSpeed(next);
                                    if (mounted) setState(() {});
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(99),
                                    ),
                                    child: Text(
                                      '${audio.speed}x',
                                      style: text.labelSmall?.copyWith(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(_time(total), style: text.bodySmall),
                              ],
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
              if (!ready && !busy) ...[
                const SizedBox(height: 6),
                Text(
                  'Tap play — audio stays here, no extra downloads.',
                  style: text.bodySmall?.copyWith(color: SahlhaColors.muted),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  String _time(Duration value) =>
      '${value.inMinutes}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';
}
