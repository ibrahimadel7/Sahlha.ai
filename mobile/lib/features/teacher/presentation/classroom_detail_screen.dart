import 'package:flutter/material.dart' hide Material;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/sahlha_colors.dart';
import '../../../core/theme/sahlha_spacing.dart';
import '../../../core/widgets/sahlha_widgets.dart';
import '../../classrooms/data/classroom_repository.dart';
import '../../classrooms/domain/classroom.dart';
import '../../materials/data/material_repository.dart';
import '../../materials/domain/material.dart';
import '../data/teacher_repository.dart';
import 'widgets/teacher_widgets.dart';

/// Classroom detail — matches the reference Programming 10 screen.
///
/// Tabs: Overview / Students / Materials / Insights.
/// Students tab has real search + mastered/developing counts from
/// classroomMastery (no fake analytics).
class ClassroomDetailScreen extends ConsumerStatefulWidget {
  const ClassroomDetailScreen({
    super.key,
    required this.classroomId,
    this.initialTab = 0,
  });

  final String classroomId;
  final int initialTab;

  @override
  ConsumerState<ClassroomDetailScreen> createState() =>
      _ClassroomDetailScreenState();
}

class _ClassroomDetailScreenState
    extends ConsumerState<ClassroomDetailScreen> {
  late int _tab;
  final _search = TextEditingController();
  String _query = '';

  static const _tabs = ['Overview', 'Students', 'Materials', 'Insights'];

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab.clamp(0, 3);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final roomAsync = ref.watch(_classroomProvider(widget.classroomId));
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/teacher/classrooms');
            }
          },
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              roomAsync.value?.name ?? 'Classroom',
              style: text.titleLarge,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (roomAsync.value != null)
              Text(
                [
                  if (roomAsync.value!.subject.isNotEmpty)
                    roomAsync.value!.subject,
                  if (roomAsync.value!.gradeLevel.isNotEmpty)
                    'Grade ${roomAsync.value!.gradeLevel}',
                ].join(' · '),
                style: text.bodySmall?.copyWith(color: SahlhaColors.muted),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none_outlined),
            onPressed: () {},
          ),
        ],
      ),
      body: roomAsync.when(
        loading: () => const LoadingState(message: 'Loading classroom…'),
        error: (e, _) => ErrorState(
          message: e.toString(),
          onRetry: () =>
              ref.invalidate(_classroomProvider(widget.classroomId)),
        ),
        data: (room) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                SahlhaSpacing.page,
                8,
                SahlhaSpacing.page,
                8,
              ),
              child: CurriculumTabBar(
                tabs: _tabs,
                selected: _tab,
                onSelected: (i) => setState(() => _tab = i),
              ),
            ),
            Expanded(
              child: switch (_tab) {
                0 => _OverviewTab(room: room),
                1 => _StudentsTab(
                    classroomId: room.id,
                    search: _search,
                    query: _query,
                    onQuery: (v) =>
                        setState(() => _query = v.trim().toLowerCase()),
                  ),
                2 => _MaterialsTab(
                    classroomId: room.id,
                    joinCode: room.joinCode,
                  ),
                _ => _InsightsTab(classroomId: room.id),
              },
            ),
          ],
        ),
      ),
    );
  }
}

final _classroomProvider = FutureProvider.autoDispose.family<Classroom, String>(
  (ref, id) {
    return ref.watch(classroomRepositoryProvider).get(id);
  },
);

// ------------------------------------------------------------- overview
class _OverviewTab extends ConsumerWidget {
  const _OverviewTab({required this.room});

  final Classroom room;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final mastery = ref.watch(classroomMasteryProvider(room.id));
    final materials = ref.watch(
      materialListProvider(classroomId: room.id),
    );
    final students = ref.watch(_studentsProvider(room.id));

    final studentCount = students.value?.length ?? room.numStudents ?? 0;
    final matCount = materials.value?.length ?? 0;
    final needing =
        (mastery.value?['needing_support'] as List? ?? []).length;

    return ListView(
      padding: const EdgeInsets.all(SahlhaSpacing.page),
      children: [
        TeacherStatGrid(
          classrooms: 1,
          students: studentCount,
          materials: matCount,
          pendingReview: 0,
        ),
        const SizedBox(height: SahlhaSpacing.lg),
        SahlhaCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Classroom join code',
                      style: text.bodySmall?.copyWith(
                        color: SahlhaColors.muted,
                      ),
                    ),
                    Text(
                      room.joinCode,
                      style: text.headlineSmall?.copyWith(
                        letterSpacing: 3,
                        color: SahlhaColors.tealDark,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy_outlined),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: room.joinCode));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Join code copied')),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: SahlhaSpacing.md),
        if (needing > 0)
          TeacherAttentionTile(
            icon: Icons.person_outline,
            iconBg: SahlhaColors.softCoralSoft,
            iconFg: SahlhaColors.softCoralDark,
            title: '$needing student${needing == 1 ? '' : 's'} may need support',
            subtitle: 'See Students tab for details',
            onTap: null,
          ),
        const SizedBox(height: SahlhaSpacing.md),
        TeacherSectionHeader(
          title: 'Recent materials',
          actionLabel: 'View all',
          onAction: () => context.push(
            '/teacher/materials/new?classroomId=${room.id}',
          ),
        ),
        const SizedBox(height: SahlhaSpacing.sm),
        materials.when(
          loading: () => const LoadingState(message: 'Loading materials…'),
          error: (e, _) => ErrorState(
            message: e.toString(),
            onRetry: () => ref.invalidate(
              materialListProvider(classroomId: room.id),
            ),
          ),
          data: (list) {
            if (list.isEmpty) {
              return SahlhaPrimaryButton(
                label: 'Upload first lesson',
                onPressed: () => context.push(
                  '/teacher/materials/new?classroomId=${room.id}',
                ),
              );
            }
            return Column(
              children: [
                for (final m in list.take(3))
                  Padding(
                    padding: const EdgeInsets.only(
                      bottom: SahlhaSpacing.sm,
                    ),
                    child: _MaterialRow(material: m),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ------------------------------------------------------------- students
final _studentsProvider = FutureProvider.autoDispose
    .family<List<ClassroomStudent>, String>((ref, id) {
      return ref.watch(classroomRepositoryProvider).students(id);
    });

class _StudentsTab extends ConsumerWidget {
  const _StudentsTab({
    required this.classroomId,
    required this.search,
    required this.query,
    required this.onQuery,
  });

  final String classroomId;
  final TextEditingController search;
  final String query;
  final ValueChanged<String> onQuery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final students = ref.watch(_studentsProvider(classroomId));
    final mastery = ref.watch(classroomMasteryProvider(classroomId));
    return students.when(
      loading: () => const LoadingState(message: 'Loading students…'),
      error: (e, _) => ErrorState(
        message: e.toString(),
        onRetry: () => ref.invalidate(_studentsProvider(classroomId)),
      ),
      data: (list) {
        if (list.isEmpty) {
          return const EmptyState(
            title: 'No students yet',
            message:
                'Share the classroom join code (Materials tab shows it too) so students can join.',
          );
        }
        // Real per-student summary from classroomMastery.
        final byId = <String, Map<String, dynamic>>{};
        for (final s in (mastery.value?['students'] as List? ?? [])) {
          final m = s as Map<String, dynamic>;
          byId[m['student_id'].toString()] = m;
        }
        final filtered = list
            .where((s) => s.name.toLowerCase().contains(query))
            .toList();
        return ListView(
          padding: const EdgeInsets.all(SahlhaSpacing.page),
          children: [
            Text(
              '${list.length} students',
              style: text.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: SahlhaSpacing.sm),
            TeacherSearchField(
              controller: search,
              onChanged: onQuery,
            ),
            const SizedBox(height: SahlhaSpacing.md),
            if (filtered.isEmpty)
              const SahlhaCard(child: Text('No students match your search.'))
            else
              for (final s in filtered)
                Padding(
                  padding: const EdgeInsets.only(bottom: SahlhaSpacing.sm),
                  child: Builder(
                    builder: (context) {
                      final summary =
                          (byId[s.id]?['summary'] as Map?)?.cast<String, dynamic>() ??
                          const {};
                      final mastered =
                          (summary['mastered'] as num?)?.toInt() ?? 0;
                      final developing =
                          (summary['developing'] as num?)?.toInt() ?? 0;
                      final needs =
                          (summary['needs_practice'] as num?)?.toInt() ?? 0;
                      final subtitle = (mastered + developing + needs) == 0
                          ? 'Not started yet'
                          : '$mastered mastered · $developing developing${needs > 0 ? ' · $needs needs practice' : ''}';
                      return TeacherStudentRow(
                        initials: teacherInitials(s.name),
                        name: s.name,
                        subtitle: subtitle,
                        avatarColor: teacherAvatarColor(s.id),
                        onTap: () => context.push(
                          '/teacher/students/$classroomId/${s.id}',
                        ),
                      );
                    },
                  ),
                ),
          ],
        );
      },
    );
  }
}

// ------------------------------------------------------------- materials
class _MaterialsTab extends ConsumerWidget {
  const _MaterialsTab({required this.classroomId, required this.joinCode});

  final String classroomId;
  final String joinCode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final materials = ref.watch(
      materialListProvider(classroomId: classroomId),
    );
    return materials.when(
      loading: () => const LoadingState(message: 'Loading materials…'),
      error: (e, _) => ErrorState(
        message: e.toString(),
        onRetry: () => ref.invalidate(
          materialListProvider(classroomId: classroomId),
        ),
      ),
      data: (list) => ListView(
        padding: const EdgeInsets.all(SahlhaSpacing.page),
        children: [
          SahlhaCard(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Classroom join code',
                        style: text.bodySmall?.copyWith(
                          color: SahlhaColors.muted,
                        ),
                      ),
                      Text(
                        joinCode,
                        style: text.headlineSmall?.copyWith(
                          letterSpacing: 3,
                          color: SahlhaColors.tealDark,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy_outlined),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: joinCode));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Join code copied')),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: SahlhaSpacing.md),
          SahlhaPrimaryButton(
            label: 'Upload lesson',
            onPressed: () => context.push(
              '/teacher/materials/new?classroomId=$classroomId',
            ),
          ),
          const SizedBox(height: SahlhaSpacing.lg),
          if (list.isEmpty)
            const EmptyState(
              title: 'No materials yet',
              message:
                  'Upload your curriculum (PDF, DOCX, PPTX, TXT, images). Sahlha will find the skills and draft practice.',
            )
          else
            for (final m in list)
              Padding(
                padding: const EdgeInsets.only(bottom: SahlhaSpacing.sm),
                child: _MaterialRow(material: m),
              ),
        ],
      ),
    );
  }
}

class _MaterialRow extends StatelessWidget {
  const _MaterialRow({required this.material});

  final Material material;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SahlhaCard(
      onTap: () => context.push(
        '/teacher/materials/${material.id}?classroomId=${material.classroomId ?? ''}',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  material.title.isEmpty
                      ? material.filename
                      : material.title,
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _StatusChip(status: material.status),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            material.filename,
            style: text.bodySmall?.copyWith(color: SahlhaColors.muted),
          ),
          const SizedBox(height: SahlhaSpacing.sm),
          Text(
            '${material.numSkills} skills · ${material.approvedBanks}/${material.numBanks} banks approved',
            style: text.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    final String label;
    switch (status) {
      case 'banks_ready':
        bg = SahlhaColors.successSoft;
        fg = SahlhaColors.success;
        label = 'Practice ready';
        break;
      case 'skills_ready':
        bg = SahlhaColors.tealSoft;
        fg = SahlhaColors.tealDark;
        label = 'Skills ready';
        break;
      case 'failed':
        bg = SahlhaColors.dangerSoft;
        fg = SahlhaColors.danger;
        label = 'Needs attention';
        break;
      case 'processing':
      case 'uploaded':
        bg = SahlhaColors.sunSoft;
        fg = const Color(0xFFB45309);
        label = 'Processing…';
        break;
      default:
        bg = SahlhaColors.tealFaint;
        fg = SahlhaColors.tealDark;
        label = 'Uploaded';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: fg, fontWeight: FontWeight.w800),
      ),
    );
  }
}

// ------------------------------------------------------------- insights
class _InsightsTab extends ConsumerWidget {
  const _InsightsTab({required this.classroomId});

  final String classroomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final mastery = ref.watch(classroomMasteryProvider(classroomId));
    return mastery.when(
      loading: () => const LoadingState(message: 'Loading insights…'),
      error: (e, _) => ErrorState(
        message: e.toString(),
        onRetry: () =>
            ref.invalidate(classroomMasteryProvider(classroomId)),
      ),
      data: (data) {
        final skills = (data['skill_performance'] as List? ?? []);
        if (skills.isEmpty) {
          return const EmptyState(
            title: 'No insights yet',
            message: 'Insights appear once students start practicing.',
          );
        }
        return ListView(
          padding: const EdgeInsets.all(SahlhaSpacing.page),
          children: [
            Text('Which skill is difficult?', style: text.titleLarge),
            const SizedBox(height: SahlhaSpacing.sm),
            for (final s in skills)
              Padding(
                padding: const EdgeInsets.only(bottom: SahlhaSpacing.sm),
                child: Builder(
                  builder: (context) {
                    final skill = s as Map<String, dynamic>;
                    final rate =
                        (skill['mastery_rate'] as num?)?.toDouble();
                    return SahlhaCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (skill['name'] as String?)?.isNotEmpty == true
                                ? skill['name'] as String
                                : (skill['skill_id']?.toString() ?? ''),
                            style: text.titleMedium,
                          ),
                          const SizedBox(height: SahlhaSpacing.sm),
                          SahlhaProgressBar(value: rate ?? 0, height: 8),
                          const SizedBox(height: 4),
                          Text(
                            rate == null
                                ? 'Not attempted yet'
                                : '${(rate * 100).round()}% of students mastered · ${skill['attempted']} attempts',
                            style: text.bodySmall?.copyWith(
                              color: SahlhaColors.muted,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}
