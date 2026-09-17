import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/sahlha_colors.dart';
import '../../../core/widgets/sahlha_widgets.dart'
    show SahlhaAppBar, ErrorState, EmptyState, SahlhaPrimaryButton;
import '../data/student_repository.dart';
import 'journey_presentation.dart';
import 'widgets/engagement.dart' show relativeDayLabel;
import 'widgets/joyful_cards.dart';
import 'widgets/learning_journey.dart';
import 'widgets/playful_background.dart';
import 'widgets/sahlha_avatar.dart';

class StudentProgressScreen extends ConsumerWidget {
  const StudentProgressScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = studentProgressProvider();
    final response = ref.watch(provider);
    return Scaffold(
      appBar: const SahlhaAppBar(title: 'Your progress'),
      body: PlayfulBackground(
        variant: PlayfulVariant.progress,
        child: StudentCanvas(
          child: response.when(
            loading: () => const JourneyLoading(),
            error: (_, _) => ErrorState(
              message: "We couldn't load your progress.",
              onRetry: () => ref.invalidate(provider),
            ),
            data: (data) {
              final rooms = (data['classrooms'] as List? ?? [])
                  .whereType<Map>()
                  .toList();
              if (rooms.isEmpty) {
                return EmptyState(
                  title: 'Your learning journey starts here',
                  message: 'Join your classroom. Your progress will grow here as you practice.',
                  action: SahlhaPrimaryButton(
                    label: 'Join a classroom',
                    onPressed: () => context.push('/student/join'),
                  ),
                );
              }
              return RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(provider);
                  await ref.read(provider.future);
                },
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    Row(
                      children: [
                        const SahlhaAvatar(
                          size: 56,
                          state: SahlhaAvatarState.encouraging,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'A clear view of growth.',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: SahlhaColors.muted,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    for (final room in rooms) _ProgressRoom(room: room),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ProgressRoom extends StatelessWidget {
  const _ProgressRoom({required this.room});
  final Map room;
  @override
  Widget build(BuildContext context) {
    final journey = LearningJourney.fromJson({
      'units': room['units'] ?? [],
    }, subject: room['subject']?.toString() ?? '');
    final steps = journey.units.expand((u) => u.steps).toList();
    final text = Theme.of(context).textTheme;
    final mastered = steps.where((s) => s.skill.state == 'mastered').length;
    final developing = steps.where((s) => s.skill.state == 'developing').length;
    final needs = steps.where((s) => s.skill.state == 'needs_practice').length;
    final practiced = steps
        .where((s) => s.skill.attempted > 0)
        .take(5)
        .toList();
    final hasHistory = practiced.any((s) => s.skill.state == 'mastered');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          studentTitle(
            room['subject']?.toString() ?? '',
            fallback: 'Your learning',
          ),
          style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ProgressStatusCard(
              count: mastered,
              label: 'Mastered',
              background: const Color(0xFFDEFBE5),
              foreground: const Color(0xFF138A43),
            ),
            ProgressStatusCard(
              count: developing,
              label: 'Developing',
              background: const Color(0xFFFFF3D5),
              foreground: const Color(0xFF9C6900),
            ),
            ProgressStatusCard(
              count: needs,
              label: 'Needs Practice',
              background: const Color(0xFFFFE8E4),
              foreground: const Color(0xFFB63752),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          hasHistory ? 'Recently improved' : 'Recently practiced',
          style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          'Small steps. Lasting understanding.',
          style: text.bodySmall?.copyWith(color: SahlhaColors.muted),
        ),
        const SizedBox(height: 10),
        if (practiced.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: SahlhaColors.borderSubtle),
            ),
            child: Text(
              'Your progress will appear after your first practice.',
              style: text.bodyMedium?.copyWith(color: SahlhaColors.muted),
            ),
          )
        else
          for (final step in practiced)
            RecentlyImprovedTile(
              title: step.title,
              status: switch (step.skill.state) {
                'mastered' => 'Now mastered!',
                'developing' => 'Great progress!',
                'needs_practice' => 'Keep going!',
                _ => 'Keep building your understanding',
              },
              state: step.skill.state,
              onTap: () => context.push(
                lessonLocation(
                  step,
                  classroomId: room['classroom_id']?.toString(),
                ),
              ),
            ),
        if ((room['grades'] as List? ?? []).isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Practice sessions',
            style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          for (final grade in (room['grades'] as List).whereType<Map>().take(3))
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: SahlhaColors.aquaSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.history_rounded,
                  color: SahlhaColors.joyTealDark,
                  size: 20,
                ),
              ),
              title: const Text('Practice session'),
              subtitle: Text(relativeDayLabel(grade['created_at']?.toString())),
              trailing: Text(
                '${((grade['score'] as num? ?? 0) * 100).round()}%',
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
        ],
        TextButton.icon(
          onPressed: () => context.go(
            learningLocation(classroomId: room['classroom_id']?.toString()),
          ),
          icon: const Icon(Icons.route_outlined),
          label: const Text('Visit this learning path'),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: SahlhaColors.aquaSoft.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              const SahlhaAvatar(size: 44),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'You\u2019re building real skills. Keep it up!',
                  style: text.bodyMedium?.copyWith(
                    color: SahlhaColors.joyTealDark,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}
