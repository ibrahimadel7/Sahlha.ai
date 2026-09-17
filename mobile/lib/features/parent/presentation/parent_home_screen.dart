import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/theme/sahlha_colors.dart';
import '../../../core/theme/sahlha_spacing.dart';
import '../../../core/widgets/sahlha_widgets.dart';
import '../data/parent_repository.dart';

/// Parent home: selected child, current learning, mastery summary,
/// skills needing practice. Simpler than the teacher view.
class ParentHomeScreen extends ConsumerWidget {
  const ParentHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final user = ref.watch(currentUserProvider);
    final children = ref.watch(linkedChildrenProvider);

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(linkedChildrenProvider);
            await ref.read(linkedChildrenProvider.future);
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(SahlhaSpacing.page),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Good day,',
                  style: text.bodyMedium?.copyWith(color: SahlhaColors.muted),
                ),
                Text(
                  user?.name.split(' ').first ?? 'Parent',
                  style: text.headlineSmall,
                ),
                const SizedBox(height: SahlhaSpacing.lg),
                children.when(
                  loading: () => const LoadingState(),
                  error: (e, _) => ErrorState(
                    message: e.toString(),
                    onRetry: () => ref.invalidate(linkedChildrenProvider),
                  ),
                  data: (list) {
                    if (list.isEmpty) {
                      return EmptyState(
                        title: 'No linked child yet',
                        message: 'Ask your child for their parent link code (they find it in Profile), then link them here.',
                        action: SahlhaPrimaryButton(
                          label: 'Link a child',
                          onPressed: () => context.push('/parent/link'),
                        ),
                      );
                    }
                    return _HomeBody(key: ValueKey(list.length));
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeBody extends ConsumerWidget {
  const _HomeBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final children = ref.watch(linkedChildrenProvider).value ?? [];
    final selectedId = ref.watch(selectedChildProvider) ?? children.first.id;
    final selected =
        children.where((c) => c.id == selectedId).firstOrNull ?? children.first;
    final progress = ref.watch(selectedChildProgressProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: selected.id,
          decoration: const InputDecoration(labelText: 'Child'),
          items: children
              .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
              .toList(),
          onChanged: (v) => ref.read(selectedChildProvider.notifier).select(v),
        ),
        const SizedBox(height: SahlhaSpacing.sm),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => context.push('/parent/link'),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Link another child'),
          ),
        ),
        progress.when(
          loading: () => const LoadingState(message: 'Loading progress…'),
          error: (e, _) => ErrorState(
            message: e.toString(),
            onRetry: () => ref.invalidate(selectedChildProgressProvider),
          ),
          data: (data) {
            final rooms = (data['classrooms'] as List? ?? []);
            if (rooms.isEmpty) {
              return const SahlhaCard(
                child: Text('Your child has not joined a classroom yet.'),
              );
            }
            return Column(
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
                    onTap: () =>
                        context.push('/parent/children/${selected.id}'),
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
                            MasteryRing(
                              mastered: count('mastered'),
                              total: total,
                              size: 84,
                            ),
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
                                  const SizedBox(height: 4),
                                  Text(
                                    '${count('needs_practice')} skills need practice',
                                    style: text.bodyMedium?.copyWith(
                                      color: count('needs_practice') > 0
                                          ? const Color(0xFFB45309)
                                          : SahlhaColors.muted,
                                    ),
                                  ),
                                  Text(
                                    '${count('mastered')} mastered',
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
          },
        ),
      ],
    );
  }
}
