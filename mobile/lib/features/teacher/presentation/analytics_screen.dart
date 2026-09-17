import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/sahlha_colors.dart';
import '../../../core/theme/sahlha_spacing.dart';
import '../../../core/widgets/sahlha_widgets.dart';
import '../../classrooms/data/classroom_repository.dart';
import '../data/teacher_repository.dart';
import 'widgets/teacher_widgets.dart';

/// Reviews — the Teacher review queue (route stays /teacher/analytics for
/// backwards compatibility; tab label is "Reviews").
///
/// Real pending banks only. No fake analytics. Tapping a bank opens the
/// full BankReviewScreen. Classroom insights live in ClassroomDetail.
class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  String? _classroomId; // null = all classrooms

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final rooms = ref.watch(classroomListProvider);
    final banks = ref.watch(
      teacherBanksProvider(
        status: 'pending_review',
        classroomId: _classroomId,
      ),
    );
    return Scaffold(
      appBar: AppBar(title: Text('Reviews', style: text.titleLarge)),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(teacherBanksProvider);
          ref.invalidate(pendingBanksProvider);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(SahlhaSpacing.page),
          children: [
            Text(
              'AI-drafted questions waiting for your approval.',
              style: text.bodyMedium?.copyWith(color: SahlhaColors.muted),
            ),
            const SizedBox(height: SahlhaSpacing.md),
            rooms.when(
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
              data: (list) {
                if (list.isEmpty) return const SizedBox.shrink();
                return DropdownButtonFormField<String?>(
                  initialValue: _classroomId,
                  decoration: const InputDecoration(
                    labelText: 'Classroom (optional)',
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('All classrooms'),
                    ),
                    for (final r in list)
                      DropdownMenuItem<String?>(
                        value: r.id,
                        child: Text(r.name),
                      ),
                  ],
                  onChanged: (v) => setState(() => _classroomId = v),
                );
              },
            ),
            const SizedBox(height: SahlhaSpacing.md),
            banks.when(
              loading: () =>
                  const LoadingState(message: 'Loading review queue…'),
              error: (e, _) => ErrorState(
                message: e.toString(),
                onRetry: () => ref.invalidate(teacherBanksProvider),
              ),
              data: (list) {
                if (list.isEmpty) {
                  return const SahlhaCard(
                    child: Row(
                      children: [
                        SahlhaProcessingAvatar(size: 52),
                        SizedBox(width: SahlhaSpacing.md),
                        Expanded(
                          child: Text(
                            'All caught up! No questions waiting for review.',
                          ),
                        ),
                      ],
                    ),
                  );
                }
                // Group by skill for a calm, scannable queue.
                final bySkill = <String, List<dynamic>>{};
                for (final b in list) {
                  bySkill.putIfAbsent(b.skillId, () => []).add(b);
                }
                return Column(
                  children: [
                    for (final entry in bySkill.entries)
                      Padding(
                        padding: const EdgeInsets.only(
                          bottom: SahlhaSpacing.sm,
                        ),
                        child: _ReviewGroup(
                          skillId: entry.key,
                          banks: entry.value,
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: SahlhaSpacing.xl),
          ],
        ),
      ),
    );
  }
}

class _ReviewGroup extends StatelessWidget {
  const _ReviewGroup({required this.skillId, required this.banks});

  final String skillId;
  final List<dynamic> banks;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final totalQuestions = banks.fold<int>(
      0,
      (sum, b) => sum + ((b as dynamic).numQuestions as int? ?? 0),
    );
    return SahlhaCard(
      onTap: banks.isNotEmpty && (banks.first as dynamic).id != null
          ? () => context.push('/teacher/banks/${(banks.first as dynamic).id}')
          : null,
      padding: const EdgeInsets.all(SahlhaSpacing.md),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: SahlhaColors.warmYellowSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.rate_review_outlined,
              color: SahlhaColors.warmYellowDeep,
            ),
          ),
          const SizedBox(width: SahlhaSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  skillId,
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '$totalQuestions question${totalQuestions == 1 ? '' : 's'} · ${banks.length} bank${banks.length == 1 ? '' : 's'}',
                  style: text.bodySmall?.copyWith(
                    color: SahlhaColors.muted,
                  ),
                ),
              ],
            ),
          ),
          const EvidenceBadge(label: 'Pending', tone: 'pending'),
          const Icon(Icons.chevron_right, color: SahlhaColors.muted),
        ],
      ),
    );
  }
}
