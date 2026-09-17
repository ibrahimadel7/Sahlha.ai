import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/theme/sahlha_colors.dart';
import '../../../core/widgets/sahlha_widgets.dart'
    show EmptyState, ErrorState, SahlhaPrimaryButton;
import '../data/student_repository.dart';
import 'journey_presentation.dart';
import 'widgets/engagement.dart';
import 'widgets/joyful_cards.dart';
import 'widgets/learning_journey.dart';
import 'widgets/playful_background.dart';
import 'widgets/sahlha_avatar.dart';

class StudentHomeScreen extends ConsumerWidget {
  const StudentHomeScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final home = ref.watch(studentHomeProvider);
    final name = cleanStudentText(user?.name ?? '').split(' ').first;
    final returning = (home.asData?.value['classrooms'] as List? ?? [])
        .whereType<Map>()
        .any((r) => r['recent_practiced_at'] != null);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: PlayfulBackground(
          variant: PlayfulVariant.home,
          child: StudentCanvas(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(studentHomeProvider);
                ref.invalidate(studentLearningPathProvider);
                await ref.read(studentHomeProvider.future);
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Sahlha',
                              style: text.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              'Learning made for you',
                              style: text.bodyMedium?.copyWith(
                                color: SahlhaColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: SahlhaColors.borderSubtle),
                        ),
                        child: const Icon(
                          Icons.notifications_outlined,
                          size: 22,
                          color: SahlhaColors.joyTealDark,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  // Warm welcome: bubble + animated avatar.
                  // Keep exact strings for comeback tests.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: SahlhaSpeechBubble(
                          message: returning
                              ? (name.isEmpty
                                    ? 'Welcome back! Ready for your next step?'
                                    : 'Welcome back, $name!')
                              : "Let\u2019s do one learning step today!",
                        ),
                      ),
                      const SizedBox(width: 10),
                      SahlhaAvatar(
                        size: 84,
                        state: returning
                            ? SahlhaAvatarState.happy
                            : SahlhaAvatarState.encouraging,
                        label: 'Sahlha, your learning friend',
                      ),
                    ],
                  ),
                  if (returning) ...[
                    const SizedBox(height: 6),
                    Text(
                      'You got this! ✨',
                      style: text.bodySmall?.copyWith(
                        color: SahlhaColors.warmYellowDeep,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  home.when(
                    loading: () =>
                        const SizedBox(height: 320, child: JourneyLoading()),
                    error: (_, _) => ErrorState(
                      message: "We couldn't load your next step.",
                      onRetry: () => ref.invalidate(studentHomeProvider),
                    ),
                    data: (data) => _HomeLearning(data: data),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeLearning extends ConsumerWidget {
  const _HomeLearning({required this.data});
  final Map<String, dynamic> data;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rooms = (data['classrooms'] as List? ?? []).whereType<Map>().toList();
    final supp = data['supplementary'] as Map?;
    final hasExtra = (supp?['total_skills'] as num? ?? 0) > 0;
    final room =
        rooms.where((r) => r['current'] != null).firstOrNull ??
        rooms.firstOrNull;
    final useExtra =
        hasExtra &&
        (room == null || room['current'] == null) &&
        supp?['current'] != null;
    if (room == null && !hasExtra) {
      return EmptyState(
        title: 'Your first step is waiting',
        message: 'You haven\u2019t joined a classroom yet. Ask your teacher for a code to begin.',
        action: SahlhaPrimaryButton(
          label: 'Join a classroom',
          onPressed: () => context.push('/student/join'),
        ),
      );
    }
    final roomId = useExtra ? null : room?['classroom_id']?.toString();
    final extra = useExtra || room == null;
    final recent = mostRecentStamp(
      rooms.map((r) => r['recent_practiced_at']?.toString()),
    );
    final comeback = relativeDayLabel(recent);
    final isComeback = comeback.isNotEmpty;
    final provider = studentLearningPathProvider(
      classroomId: roomId,
      supplementary: extra,
    );
    final path = ref.watch(provider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isComeback) ...[
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: SahlhaColors.warmYellowSoft,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.history_rounded,
                      size: 16,
                      color: SahlhaColors.warmYellowDeep,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Welcome back — you practiced ${comeback.toLowerCase()}.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: SahlhaColors.warmYellowDeep,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        path.when(
          loading: () => const SizedBox(height: 260, child: JourneyLoading()),
          error: (_, _) => ErrorState(
            message: "We couldn't load your next lesson.",
            onRetry: () => ref.invalidate(provider),
          ),
          data: (value) {
            final journey = LearningJourney.fromJson(
              value,
              subject: room?['subject']?.toString() ?? '',
            );
            final unit = journey.activeUnit;
            final current = unit?.current;
            if (unit == null || journey.total == 0) {
              return const EmptyState(
                title: 'Your learning path is being prepared.',
                message: 'Your teacher hasn\u2019t added a lesson yet. Come back soon!',
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (current != null) ...[
                  if (isComeback)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Welcome back!',
                        style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                  CurrentSkillCard(
                    title: current.title,
                    contextLabel: isComeback
                        ? 'Continue where you left off'
                        : 'Continue learning',
                    questions: current.skill.practiceQuestions,
                    minutes:
                        ((current.skill.description
                                        .split(RegExp(r'\s+'))
                                        .length /
                                    150) +
                                current.skill.practiceQuestions * .6)
                            .ceil()
                            .clamp(1, 60),
                    subtitle: journey.units.isEmpty ? '' : unit.title,
                    started: current.skill.attempted > 0,
                    progress: unit.steps.isEmpty
                        ? null
                        : (current.index + 1) / unit.steps.length,
                    effort: effortLabelForMastery(current.skill.state),
                    onTap: () => context.push(
                      lessonLocation(
                        current,
                        classroomId: roomId,
                        supplementary: extra,
                      ),
                    ),
                    onContinue: () => context.push(
                      lessonLocation(
                        current,
                        classroomId: roomId,
                        supplementary: extra,
                      ),
                    ),
                  ),
                ] else
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFDFFBF6), Color(0xFFFFF3D1)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: SahlhaColors.borderSubtle),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SahlhaAvatar(
                          size: 64,
                          state: SahlhaAvatarState.celebrating,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          journey.mastered == journey.total
                              ? 'Look how far you\u2019ve come.'
                              : 'Learn at your own pace.',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'You\u2019re making great progress! Let\u2019s keep the momentum going.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: SahlhaColors.muted),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: () => context.go(
                            learningLocation(
                              classroomId: roomId,
                              supplementary: extra,
                            ),
                          ),
                          child: const Text('Explore your path'),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 20),
                Builder(
                  builder: (_) {
                    final goal = dailyGoalFor(
                      hasStep: journey.total > 0,
                      recentPracticedAt: recent,
                      stepTitle: current?.title,
                    );
                    return DailyGoalCard(goal: goal);
                  },
                ),
                const SizedBox(height: 20),
                Text(
                  'Recent activity',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                Builder(
                  builder: (_) {
                    final practiced = journey.units
                        .expand((u) => u.steps)
                        .where((s) => s.skill.attempted > 0)
                        .take(3)
                        .toList();
                    if (practiced.isEmpty) {
                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: SahlhaColors.borderSubtle),
                        ),
                        child: Text(
                          'Your learning steps will appear here after practice.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: SahlhaColors.muted),
                        ),
                      );
                    }
                    return Column(
                      children: [
                        for (final step in practiced)
                          RecentActivityTile(
                            title: step.title,
                            subtitle: effortLabelForMastery(step.skill.state),
                            state: step.skill.state,
                            onTap: () => context.push(
                              lessonLocation(
                                step,
                                classroomId: roomId,
                                supplementary: extra,
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                TextButton(
                  onPressed: () => context.go(
                    learningLocation(classroomId: roomId, supplementary: extra),
                  ),
                  child: const Text('See your learning path'),
                ),
              ],
            );
          },
        ),
        if (rooms.length > 1) ...[
          const SizedBox(height: 12),
          const JourneyEyebrow('MORE TO EXPLORE'),
          const SizedBox(height: 6),
          for (final other in rooms.where((r) => r['classroom_id'] != roomId))
            Card(
              elevation: 0,
              color: Colors.white,
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: SahlhaColors.borderSubtle),
              ),
              child: ListTile(
                title: Text(
                  studentTitle(
                    other['subject']?.toString() ?? '',
                    fallback: 'Your classroom',
                  ),
                ),
                trailing: const Icon(Icons.arrow_forward_rounded),
                onTap: () => context.go(
                  learningLocation(
                    classroomId: other['classroom_id']?.toString(),
                  ),
                ),
              ),
            ),
        ],
        if (hasExtra && !extra)
          Card(
            elevation: 0,
            color: SahlhaColors.lavenderFaint,
            margin: const EdgeInsets.only(top: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: SahlhaColors.lavender.withValues(alpha: 0.3),
              ),
            ),
            child: ListTile(
              leading: const Icon(
                Icons.auto_stories_outlined,
                color: SahlhaColors.lavenderDark,
              ),
              title: const Text('Extra learning'),
              subtitle: const Text('A little support from your family'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.go(learningLocation(supplementary: true)),
            ),
          ),
        if (data['onboarding_completed'] != true)
          TextButton.icon(
            onPressed: () => context.push('/student/setup'),
            icon: const Icon(Icons.tune_rounded),
            label: const Text('Make learning feel right for you'),
          ),
      ],
    );
  }
}
