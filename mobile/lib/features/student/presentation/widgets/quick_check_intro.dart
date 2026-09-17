import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/sahlha_colors.dart';
import '../../data/student_repository.dart';
import '../journey_presentation.dart';
import '../../../../core/widgets/sahlha_widgets.dart';
import 'playful_background.dart';
import 'sahlha_avatar.dart';

class QuickCheckIntro extends ConsumerWidget {
  const QuickCheckIntro({
    super.key,
    this.classroomId,
    this.materialId,
    this.supplementary = false,
    required this.onStart,
  });
  final String? classroomId, materialId;
  final bool supplementary;
  final VoidCallback onStart;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = studentLearningPathProvider(
      classroomId: classroomId,
      supplementary: supplementary,
    );
    return ref
        .watch(provider)
        .when(
          loading: () =>
              const LoadingState(message: 'Opening your Quick Check...'),
          error: (_, _) => ErrorState(
            message: 'Your Quick Check could not open.',
            onRetry: () => ref.invalidate(provider),
          ),
          data: (data) {
            final journey = LearningJourney.fromJson(data);
            final learned = journey.units
                .where((u) => u.source.materialId == materialId)
                .expand((u) => u.steps)
                .where((s) => s.learned)
                .toList();
            final ready =
                learned.length >= 2 &&
                learned.every((s) => s.skill.exerciseReady);
            final questions = learned.fold(
              0,
              (sum, s) => sum + s.skill.practiceQuestions,
            );
            final text = Theme.of(context).textTheme;
            return PlayfulBackground(
              variant: PlayfulVariant.home,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
                children: [
                  const SizedBox(height: 20),
                  Center(
                    child: Container(
                      width: 130,
                      height: 130,
                      decoration: BoxDecoration(
                        color: SahlhaColors.lavenderSoft,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: SahlhaColors.lavender.withValues(alpha: 0.35),
                          width: 2,
                        ),
                      ),
                      child: const Stack(
                        alignment: Alignment.center,
                        children: [
                          SahlhaAvatar(
                            size: 92,
                            state: SahlhaAvatarState.encouraging,
                          ),
                          Positioned(
                            right: 18,
                            top: 18,
                            child: Icon(
                              Icons.flag_rounded,
                              color: SahlhaColors.lavenderDark,
                              size: 26,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Quick Check',
                    textAlign: TextAlign.center,
                    style: text.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  // Keep exact reference copy for tests + spec.
                  const SizedBox(height: 10),
                  Text(
                    "Test what you've learned\nso far in this unit.",
                    textAlign: TextAlign.center,
                    style: text.bodyLarge?.copyWith(
                      color: SahlhaColors.muted,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: SahlhaColors.lavenderSoft,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: SahlhaColors.lavender.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      children: [
                        if (questions > 0)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.quiz_outlined,
                                color: SahlhaColors.lavenderDark,
                              ),
                            ),
                            title: Text(
                              '~$questions questions',
                              style: text.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            subtitle: const Text('Mixed skills'),
                          ),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.layers_outlined,
                              color: SahlhaColors.lavenderDark,
                            ),
                          ),
                          title: Text(
                            '${learned.length} practiced skills',
                            style: text.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            Icons.route_outlined,
                            color: SahlhaColors.lavenderDark,
                          ),
                          title: Text(
                            'Build understanding for your next steps',
                          ),
                          subtitle: Text('Helps unlock the next skills'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: SahlhaColors.lavender,
                      minimumSize: const Size(48, 56),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    onPressed: ready ? onStart : null,
                    icon: const Icon(Icons.arrow_forward_rounded),
                    label: const Text('Start Quick Check'),
                  ),
                  if (!ready)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text(
                        'Practice at least two skills with ready questions first.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        'Take it one question at a time. Mistakes show what to revisit.',
                        textAlign: TextAlign.center,
                        style: text.bodySmall?.copyWith(
                          color: SahlhaColors.muted,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
  }
}
