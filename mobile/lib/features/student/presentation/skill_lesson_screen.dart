import 'dart:async';

import '../../../core/audio/sound_effects.dart';
import '../../../core/theme/sahlha_spacing.dart';
import '../examples/presentation/adaptive_example_screen.dart';
import 'widgets/avatar_teacher.dart';
import 'widgets/lesson_content.dart';
import 'widgets/playful_background.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/audio/audio_service.dart';
import '../../../core/theme/sahlha_colors.dart';
import '../../../core/widgets/sahlha_widgets.dart';
import '../data/student_repository.dart';
import '../domain/skill_models.dart';
import 'journey_presentation.dart';
import 'widgets/learning_journey.dart' show StudentCanvas;
import 'widgets/help_me_sheet.dart';
import 'widgets/skill_media.dart' show LessonSkeleton, SkillVisualCard;

/// One skill at a time: short explanation, key idea, one primary action,
/// and a single "Help me" entry point.
class SkillLessonScreen extends ConsumerWidget {
  const SkillLessonScreen({
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
  Widget build(BuildContext context, WidgetRef ref) {
    // A deep link without its material scope can never resolve server-side:
    // fail locally with a way back instead of firing a doomed request.
    if (materialId.isEmpty) {
      return Scaffold(
        appBar: SahlhaAppBar(
          title: 'A little understanding',
          onBack: () => context.go(
            learningLocation(
              classroomId: classroomId,
              supplementary: supplementary,
            ),
          ),
        ),
        body: StudentCanvas(
          child: ErrorState(
            message: "We couldn't open this lesson.",
            onRetry: () => context.go(
              learningLocation(
                classroomId: classroomId,
                supplementary: supplementary,
              ),
            ),
          ),
        ),
      );
    }
    final bundleProvider = studentSkillBundleProvider(
      skillId: skillId,
      materialId: materialId,
      classroomId: classroomId,
      supplementary: supplementary,
    );
    final bundle = ref.watch(bundleProvider);
    void back() {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(
          learningLocation(
            classroomId: classroomId,
            supplementary: supplementary,
          ),
        );
      }
    }

    return Scaffold(
      appBar: SahlhaAppBar(
        title: studentTitle(bundle.asData?.value.name ?? 'Your lesson'),
        onBack: back,
      ),
      body: StudentCanvas(
        child: bundle.when(
          loading: () => const LessonSkeleton(),
          error: (_, _) => ErrorState(
            message: "We couldn't open this lesson.",
            onRetry: () => ref.invalidate(bundleProvider),
          ),
          data: (skill) => _LessonReading(
            key: ValueKey('$materialId:$skillId'),
            skill: skill,
            audioUrl: ref
                .read(studentRepositoryProvider)
                .skillAudioUrl(
                  skillId: skillId,
                  materialId: materialId,
                  classroomId: classroomId,
                  supplementary: supplementary,
                ),
            skillId: skillId,
            materialId: materialId,
            classroomId: classroomId,
            supplementary: supplementary,
            help: () => _openHelp(context, ref, skill),
            example: () => ref
                .read(studentRepositoryProvider)
                .skillHelp(
                  skillId: skillId,
                  materialId: materialId,
                  classroomId: classroomId,
                  supplementary: supplementary,
                  kind: 'example',
                ),
            showVisual: () => _showVisual(context, hasImage: skill.hasImage),
            continueLearning: () {
              // Subtle tap first (fire-and-forget: navigation never waits).
              try {
                unawaited(ref.read(soundEffectsProvider).tap());
              } catch (_) {}
              if (skill.exerciseReady) {
                context.push(
                  practiceLocation(
                    materialId: materialId,
                    skillId: skillId,
                    classroomId: classroomId,
                    supplementary: supplementary,
                  ),
                );
              } else {
                context.go(
                  learningLocation(
                    classroomId: classroomId,
                    supplementary: supplementary,
                  ),
                );
              }
            },
          ),
        ),
      ),
    );
  }

  Future<void> _openHelp(
    BuildContext context,
    WidgetRef ref,
    SkillBundle skill,
  ) async {
    final kind = await showSahlhaSheet<String>(
      context,
      HelpMeSheet(order: skill.helpOrder),
    );
    if (kind != null && context.mounted) {
      await _showHelp(context, ref, kind, hasImage: skill.hasImage);
    }
  }

  /// "Show visually" surfaces the same skill visual used in the lesson,
  /// or a calm note when the backend has no picture for this skill.
  void _showVisual(BuildContext context, {required bool hasImage}) {
    final text = Theme.of(context).textTheme;
    showSahlhaSheet<void>(
      context,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('A picture for this skill', style: text.titleLarge),
          const SizedBox(height: SahlhaSpacing.md),
          SkillVisualCard(
            skillId: skillId,
            materialId: materialId,
            classroomId: classroomId,
            supplementary: supplementary,
          ),
        ],
      ),
    );
  }

  Future<void> _showHelp(
    BuildContext context,
    WidgetRef ref,
    String kind, {
    required bool hasImage,
  }) async {
    if (kind == 'read_aloud') {
      final repo = ref.read(studentRepositoryProvider);
      final url = repo.skillAudioUrl(
        skillId: skillId,
        materialId: materialId,
        classroomId: classroomId,
        supplementary: supplementary,
      );
      final envelopeUrl = repo.skillEnvelopeUrl(
        skillId: skillId,
        materialId: materialId,
        classroomId: classroomId,
        supplementary: supplementary,
      );
      final err = await ref
          .read(audioServiceProvider)
          .playUrl(url, envelopeUrl: envelopeUrl);
      if (context.mounted) {
        if (err != null) {
          // Real failure (not a learning mistake): gentle error nudge.
          try {
            unawaited(ref.read(soundEffectsProvider).failure());
          } catch (_) {}
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(err ?? 'Playing your lesson…'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return;
    }
    if (kind == 'visual') {
      if (!context.mounted) return;
      _showVisual(context, hasImage: hasImage);
      return;
    }
    if (!context.mounted) return;
    showSahlhaSheet<void>(
      context,
      FutureBuilder<SkillHelp>(
        future: ref
            .read(studentRepositoryProvider)
            .skillHelp(
              skillId: skillId,
              materialId: materialId,
              kind: kind,
              classroomId: classroomId,
              supplementary: supplementary,
            ),
        builder: (ctx, snap) {
          final text = Theme.of(ctx).textTheme;
          if (snap.connectionState == ConnectionState.waiting) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: LoadingState(message: 'Preparing help…'),
            );
          }
          if (snap.hasError || snap.data == null) {
            return Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                'Help is unavailable right now. Try again soon.',
                style: text.bodyMedium,
              ),
            );
          }
          final help = snap.data!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(cleanStudentText(help.title), style: text.titleLarge),
              const SizedBox(height: SahlhaSpacing.sm),
              if (help.steps.isNotEmpty)
                ...help.steps.map(
                  (s) => Padding(
                    padding: const EdgeInsets.only(bottom: SahlhaSpacing.sm),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.arrow_right, color: SahlhaColors.teal),
                        Expanded(child: LessonContent(source: s)),
                      ],
                    ),
                  ),
                ),
              if (help.steps.isEmpty) LessonContent(source: help.body),
              if (help.keyConcepts.isNotEmpty) ...[
                const SizedBox(height: SahlhaSpacing.md),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: help.keyConcepts
                      .map(
                        (c) => Chip(
                          label: Text(cleanStudentText(c)),
                          backgroundColor: SahlhaColors.tealSoft,
                          side: BorderSide.none,
                        ),
                      )
                      .toList(),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _LessonReading extends ConsumerStatefulWidget {
  const _LessonReading({
    super.key,
    required this.skill,
    required this.audioUrl,
    required this.skillId,
    required this.materialId,
    this.classroomId,
    this.supplementary = false,
    required this.help,
    required this.example,
    required this.showVisual,
    required this.continueLearning,
  });
  final SkillBundle skill;
  final String audioUrl;
  final String skillId;
  final String materialId;
  final String? classroomId;
  final bool supplementary;
  final VoidCallback help, showVisual, continueLearning;
  final Future<SkillHelp> Function() example;
  @override
  ConsumerState<_LessonReading> createState() => _LessonReadingState();
}

class _LessonReadingState extends ConsumerState<_LessonReading> {
  bool _examples = false;
  Future<SkillHelp>? _example;
  final _scroll = ScrollController();
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _tap() {
    // Very subtle selection click; fire-and-forget so paging never waits.
    try {
      unawaited(ref.read(soundEffectsProvider).tap());
    } catch (_) {}
  }

  void _showExamples() {
    _tap();
    setState(() {
      _examples = true;
      _example ??= widget.example();
    });
  }

  /// Stop any lesson audio before navigating so it never leaks into the
  /// next screen. Disposal also stops, but `push` keeps this widget alive.
  void _stopAudio() {
    try {
      final audio = ref.read(audioServiceProvider);
      if (audio.activeUrl != null) {
        unawaited(audio.stop());
      }
    } catch (_) {}
  }

  void _continueLearning() {
    _tap();
    _stopAudio();
    widget.continueLearning();
  }

  @override
  Widget build(BuildContext context) {
    final skill = widget.skill;
    final text = Theme.of(context).textTheme;
    final explanation = skill.explanation.isEmpty
        ? skill.description
        : skill.explanation;
    return SafeArea(
      child: PlayfulBackground(
        variant: PlayfulVariant.lesson,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          cleanStudentText(skill.subject).isEmpty
                              ? 'Your lesson'
                              : cleanStudentText(skill.subject),
                          style: text.bodySmall?.copyWith(
                            color: SahlhaColors.muted,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: SahlhaColors.aquaSoft,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          'Step ${skill.position}/${skill.total}',
                          style: text.labelSmall?.copyWith(
                            color: SahlhaColors.joyTealDark,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Segmented Learn / Examples / Practice (visual tabs,
                  // architecture preserved: Practice still routes).
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: SahlhaColors.borderSubtle),
                    ),
                    child: Row(
                      children: [
                        _Segment(
                          label: 'Learn',
                          selected: !_examples,
                          onTap: () {
                            _tap();
                            setState(() => _examples = false);
                          },
                        ),
                        _Segment(
                          label: 'Examples',
                          selected: _examples,
                          onTap: _showExamples,
                        ),
                        _Segment(
                          label: 'Practice',
                          selected: false,
                          enabled: skill.exerciseReady,
                          onTap: skill.exerciseReady
                              ? _continueLearning
                              : null,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // EXAMPLES: truly interactive visual lesson driven by REAL
                  // backend SkillHelp/SkillBundle data (no hardcoded content).
                  // The Future is cached in [_showExamples] so switching tabs
                  // never refires the request and build() never fetches.
                  if (_examples)
                    FutureBuilder<SkillHelp>(
                      future: _example,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: SahlhaColors.borderSubtle,
                              ),
                            ),
                            child: Column(
                              children: [
                                const Text(
                                  'The example is unavailable right now.',
                                ),
                                TextButton(
                                  onPressed: () => setState(
                                    () => _example = widget.example(),
                                  ),
                                  child: const Text('Try again'),
                                ),
                              ],
                            ),
                          );
                        }
                        if (!snapshot.hasData) {
                          return const LoadingState(
                            message: 'Preparing your example...',
                          );
                        }
                        final example = snapshot.data!;
                        return AdaptiveExampleScreen(
                          key: ValueKey(
                            '${widget.materialId}:${widget.skillId}:${example.body.hashCode}',
                          ),
                          skill: skill,
                          example: example,
                        );
                      },
                    )
                  else ...[
                    // LEARN: avatar is the teacher. Single tap plays/pauses,
                    // double tap changes speed, subtitles follow the audio,
                    // full explanation stays available but collapsed.
                    AvatarTeacher(
                      key: ValueKey(
                        'avatar-teacher:${widget.materialId}:${widget.skillId}',
                      ),
                      skillId: widget.skillId,
                      materialId: widget.materialId,
                      classroomId: widget.classroomId,
                      supplementary: widget.supplementary,
                      explanation: explanation,
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: TextButton.icon(
                        onPressed: widget.help,
                        icon: const Icon(Icons.lightbulb_outline_rounded),
                        label: const Text('Help me'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
              child: SahlhaPrimaryButton(
                label: _examples
                    ? (skill.exerciseReady
                          ? 'Continue to practice →'
                          : 'Back to my path')
                    : 'Continue',
                onPressed: _examples ? _continueLearning : _showExamples,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    this.onTap,
    this.enabled = true,
  });
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final bool enabled;
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Expanded(
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 220),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? SahlhaColors.aquaSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                textAlign: TextAlign.center,
                style: text.titleSmall?.copyWith(
                  color: !enabled
                      ? SahlhaColors.muted.withValues(alpha: 0.5)
                      : selected
                      ? SahlhaColors.joyTealDark
                      : SahlhaColors.muted,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                height: 3,
                width: 28,
                decoration: BoxDecoration(
                  color: selected ? SahlhaColors.joyTeal : Colors.transparent,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
