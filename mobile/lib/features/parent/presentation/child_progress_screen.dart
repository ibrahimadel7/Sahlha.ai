import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/sahlha_colors.dart';
import '../../../core/theme/sahlha_spacing.dart';
import '../../../core/widgets/sahlha_widgets.dart';
import '../data/parent_repository.dart';

/// Child progress with tabs: Overview / Skills / Activity.
class ChildProgressScreen extends ConsumerWidget {
  const ChildProgressScreen({super.key, this.childId});

  final String? childId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final children = ref.watch(linkedChildrenProvider);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            children.value
                    ?.where(
                      (c) =>
                          c.id == (childId ?? ref.watch(selectedChildProvider)),
                    )
                    .firstOrNull
                    ?.name ??
                'Child progress',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          bottom: const TabBar(
            labelColor: SahlhaColors.tealDark,
            unselectedLabelColor: SahlhaColors.muted,
            indicatorColor: SahlhaColors.teal,
            tabs: [
              Tab(text: 'Overview'),
              Tab(text: 'Skills'),
              Tab(text: 'Activity'),
            ],
          ),
        ),
        body: children.when(
          loading: () => const LoadingState(),
          error: (e, _) => ErrorState(
            message: e.toString(),
            onRetry: () => ref.invalidate(linkedChildrenProvider),
          ),
          data: (list) {
            if (list.isEmpty) {
              return EmptyState(
                title: 'No linked child yet',
                message: 'Link your child to follow their progress.',
                action: SahlhaPrimaryButton(
                  label: 'Link a child',
                  onPressed: () => context.push('/parent/link'),
                ),
              );
            }
            final id =
                childId ?? ref.watch(selectedChildProvider) ?? list.first.id;
            return _ProgressTabs(childId: id);
          },
        ),
      ),
    );
  }
}

class _ProgressTabs extends ConsumerWidget {
  const _ProgressTabs({required this.childId});

  final String childId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(_childProgressProvider(childId));
    return progress.when(
      loading: () => const LoadingState(),
      error: (e, _) => ErrorState(
        message: e.toString(),
        onRetry: () => ref.invalidate(_childProgressProvider(childId)),
      ),
      data: (data) => TabBarView(
        children: [
          _OverviewTab(data: data, childId: childId),
          _SkillsTab(data: data),
          _ActivityTab(data: data),
        ],
      ),
    );
  }
}

final _childProgressProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, id) {
      return ref.watch(parentRepositoryProvider).childProgress(id);
    });

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.data, required this.childId});

  final Map<String, dynamic> data;
  final String childId;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final rooms = (data['classrooms'] as List? ?? []);
    if (rooms.isEmpty) {
      return const EmptyState(
        title: 'No classroom yet',
        message: 'Progress appears once your child joins a classroom.',
      );
    }
    return ListView(
      padding: const EdgeInsets.all(SahlhaSpacing.page),
      children: rooms.map((r) {
        final room = r as Map<String, dynamic>;
        final summary =
            (room['summary'] as Map?)?.cast<String, dynamic>() ?? {};
        int count(String k) => (summary[k] as num?)?.toInt() ?? 0;
        final total =
            count('mastered') +
            count('developing') +
            count('needs_practice') +
            count('not_started');
        final recent = (room['recent_score'] as num?)?.toDouble();
        return Padding(
          padding: const EdgeInsets.only(bottom: SahlhaSpacing.md),
          child: SahlhaCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${room['subject'] ?? ''} · ${room['name'] ?? ''}',
                  style: text.titleLarge,
                ),
                const SizedBox(height: SahlhaSpacing.md),
                Row(
                  children: [
                    MasteryRing(mastered: count('mastered'), total: total),
                    const SizedBox(width: SahlhaSpacing.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (recent != null)
                            Text(
                              'Recent practice: ${(recent * 100).round()}%',
                              style: text.titleMedium,
                            ),
                          Text(
                            '${count('needs_practice')} need practice',
                            style: text.bodyMedium,
                          ),
                          Text(
                            '${count('developing')} developing · ${count('not_started')} not started',
                            style: text.bodySmall?.copyWith(
                              color: SahlhaColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _SkillsTab extends StatelessWidget {
  const _SkillsTab({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final rooms = (data['classrooms'] as List? ?? []);
    final skills = [
      for (final r in rooms)
        for (final s in (((r as Map)['skills'] as List?) ?? []))
          s as Map<String, dynamic>,
    ];
    if (skills.isEmpty) {
      return const EmptyState(
        title: 'No skills yet',
        message: 'Skills appear once the teacher adds materials.',
      );
    }
    return ListView(
      padding: const EdgeInsets.all(SahlhaSpacing.page),
      children: skills.map((s) {
        final state = s['state']?.toString() ?? 'not_started';
        return Padding(
          padding: const EdgeInsets.only(bottom: SahlhaSpacing.sm),
          child: SahlhaCard(
            padding: const EdgeInsets.all(SahlhaSpacing.md),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    (s['name'] as String?)?.isNotEmpty == true
                        ? s['name'] as String
                        : (s['skill_id']?.toString() ?? ''),
                    style: text.titleMedium,
                  ),
                ),
                SkillStatusBadge(state: state),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _ActivityTab extends StatelessWidget {
  const _ActivityTab({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final activity = (data['recent_activity'] as List? ?? []);
    if (activity.isEmpty) {
      return const EmptyState(
        title: 'No activity yet',
        message: 'Recent practice will show up here.',
      );
    }
    return ListView(
      padding: const EdgeInsets.all(SahlhaSpacing.page),
      children: activity.map((a) {
        final item = a as Map<String, dynamic>;
        final correct = item['correct'] == true;
        return Padding(
          padding: const EdgeInsets.only(bottom: SahlhaSpacing.xs),
          child: SahlhaCard(
            padding: const EdgeInsets.all(SahlhaSpacing.md),
            child: Row(
              children: [
                Icon(
                  correct ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: correct ? SahlhaColors.success : SahlhaColors.muted,
                ),
                const SizedBox(width: SahlhaSpacing.md),
                Expanded(
                  child: Text(
                    correct
                        ? 'Answered practice correctly'
                        : 'Practiced (keep encouraging!)',
                    style: text.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
