import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/theme/sahlha_colors.dart';
import '../../../core/theme/sahlha_spacing.dart';
import '../../../core/widgets/sahlha_widgets.dart';
import '../../classrooms/data/classroom_repository.dart';
import '../../materials/data/material_repository.dart';
import '../data/teacher_repository.dart';
import 'widgets/teacher_widgets.dart';

/// Teacher Home — premium overview matching the reference.
///
/// Real backend data only. No fake analytics. No plants. Avatar not used
/// here (sparing use policy); this screen stays professional and calm.
class TeacherDashboardScreen extends ConsumerWidget {
  const TeacherDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final overview = ref.watch(teacherOverviewProvider);
    final rooms = ref.watch(classroomListProvider);
    final allMaterials = ref.watch(materialListProvider());

    final firstName = (user?.name.trim().isNotEmpty == true)
        ? user!.name.trim().split(RegExp(r'\s+')).first
        : 'Teacher';

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(teacherOverviewProvider);
            ref.invalidate(classroomListProvider);
            ref.invalidate(materialListProvider());
            await ref.read(teacherOverviewProvider.future);
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(SahlhaSpacing.page),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TeacherHomeHeader(
                  greetingName: '$firstName!',
                  notificationCount:
                      ((overview.value?['pending_banks'] as num?)?.toInt() ??
                          0) >
                      0
                      ? 1
                      : 0,
                  onNotifications: () => context.push('/teacher/analytics'),
                ),
                const SizedBox(height: 2),
                Text(
                  teacherGreeting(),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: SahlhaColors.ink,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: SahlhaSpacing.lg),
                overview.when(
                  loading: () => const LoadingState(message: 'Loading overview…'),
                  error: (e, _) => ErrorState(
                    message: e.toString(),
                    onRetry: () => ref.invalidate(teacherOverviewProvider),
                  ),
                  data: (data) => TeacherStatGrid(
                    classrooms:
                        (data['num_classrooms'] as num?)?.toInt() ?? 0,
                    students: (data['num_students'] as num?)?.toInt() ?? 0,
                    materials: (data['num_materials'] as num?)?.toInt() ?? 0,
                    pendingReview:
                        (data['pending_banks'] as num?)?.toInt() ?? 0,
                  ),
                ),
                const SizedBox(height: SahlhaSpacing.xl),
                const TeacherSectionHeader(title: 'Needs your attention'),
                const SizedBox(height: SahlhaSpacing.sm),
                overview.when(
                  loading: () => const LoadingState(
                    message: 'Checking classrooms…',
                  ),
                  error: (e, _) => ErrorState(
                    message: e.toString(),
                    onRetry: () => ref.invalidate(teacherOverviewProvider),
                  ),
                  data: (data) => _AttentionList(
                    data: data,
                    materials: allMaterials.value ?? const [],
                  ),
                ),
                const SizedBox(height: SahlhaSpacing.xl),
                TeacherSectionHeader(
                  title: 'Recent classrooms',
                  actionLabel: 'View all',
                  onAction: () => context.go('/teacher/classrooms'),
                ),
                const SizedBox(height: SahlhaSpacing.sm),
                rooms.when(
                  loading: () => const LoadingState(message: 'Loading classes…'),
                  error: (e, _) => ErrorState(
                    message: e.toString(),
                    onRetry: () => ref.invalidate(classroomListProvider),
                  ),
                  data: (list) {
                    if (list.isEmpty) {
                      return EmptyState(
                        title: 'No classrooms yet',
                        message:
                            'Create your first classroom, then share the join code with students.',
                        action: SahlhaPrimaryButton(
                          label: 'Create classroom',
                          onPressed: () =>
                              context.push('/teacher/classrooms/new'),
                        ),
                      );
                    }
                    return Column(
                      children: [
                        for (final room in list.take(3))
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: SahlhaSpacing.sm,
                            ),
                            child: Builder(
                              builder: (context) {
                                final s = teacherSubjectIcon(room.subject);
                                final gradeLabel = room.gradeLevel.isEmpty
                                    ? ''
                                    : 'Grade ${room.gradeLevel}';
                                final subjectLabel = room.subject.isEmpty
                                    ? gradeLabel
                                    : gradeLabel.isEmpty
                                        ? room.subject
                                        : '${room.subject} · $gradeLabel';
                                return TeacherClassroomTile(
                                  icon: s.icon,
                                  iconBg: s.bg,
                                  iconFg: s.fg,
                                  title: room.name,
                                  subtitle: subjectLabel,
                                  meta:
                                      '${room.numStudents ?? 0} students · Code ${room.joinCode}',
                                  onTap: () => context.push(
                                    '/teacher/classrooms/${room.id}',
                                  ),
                                );
                              },
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
        ),
      ),
    );
  }
}

class _AttentionList extends ConsumerWidget {
  const _AttentionList({required this.data, required this.materials});

  final Map<String, dynamic> data;
  final List<dynamic> materials;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = (data['pending_banks'] as num?)?.toInt() ?? 0;
    final needing = (data['needing_support'] as List? ?? []);
    // Most recent processing / failed material (real data only).
    dynamic processing;
    dynamic failed;
    dynamic ready;
    for (final m in materials) {
      final status = (m as dynamic).status as String? ?? '';
      if (status == 'processing' && processing == null) processing = m;
      if (status == 'failed' && failed == null) failed = m;
      if ((status == 'banks_ready' ||
              status == 'skills_ready' ||
              status == 'processed') &&
          ready == null) {
        ready = m;
      }
    }

    final tiles = <Widget>[];
    if (pending > 0) {
      tiles.add(
        TeacherAttentionTile(
          icon: Icons.rate_review_outlined,
          iconBg: SahlhaColors.warmYellowSoft,
          iconFg: SahlhaColors.warmYellowDeep,
          title: '$pending question${pending == 1 ? '' : 's'} waiting for review',
          subtitle: 'AI-drafted banks need your approval',
          onTap: () => context.push('/teacher/analytics'),
        ),
      );
    }
    if (failed != null) {
      tiles.add(
        Padding(
          padding: const EdgeInsets.only(top: SahlhaSpacing.sm),
          child: TeacherAttentionTile(
            icon: Icons.error_outline,
            iconBg: SahlhaColors.softCoralSoft,
            iconFg: SahlhaColors.softCoralDark,
            title: 'A lesson needs attention',
            subtitle: failed.title.toString(),
            onTap: () => context.push('/teacher/materials/${failed.id}'),
          ),
        ),
      );
    } else if (processing != null) {
      tiles.add(
        Padding(
          padding: const EdgeInsets.only(top: SahlhaSpacing.sm),
          child: TeacherAttentionTile(
            icon: Icons.hourglass_bottom_outlined,
            iconBg: SahlhaColors.tealSoft,
            iconFg: SahlhaColors.tealDark,
            title: 'Lesson processing',
            subtitle: '${processing.title} — still reading',
            onTap: () => context.push('/teacher/materials/${processing.id}'),
          ),
        ),
      );
    } else if (ready != null) {
      tiles.add(
        Padding(
          padding: const EdgeInsets.only(top: SahlhaSpacing.sm),
          child: TeacherAttentionTile(
            icon: Icons.check_circle_outline,
            iconBg: SahlhaColors.successSoft,
            iconFg: SahlhaColors.success,
            title: 'Lesson processing completed',
            subtitle: ready.title.toString(),
            onTap: () => context.push('/teacher/materials/${ready.id}'),
          ),
        ),
      );
    }
    if (needing.isNotEmpty) {
      final first = needing.first as Map<String, dynamic>;
      tiles.add(
        Padding(
          padding: const EdgeInsets.only(top: SahlhaSpacing.sm),
          child: TeacherAttentionTile(
            icon: Icons.person_outline,
            iconBg: SahlhaColors.softCoralSoft,
            iconFg: SahlhaColors.softCoralDark,
            title:
                '${needing.length} student${needing.length == 1 ? '' : 's'} may need support',
            subtitle:
                "${first['name'] ?? ''}${(first['classroom_name'] as String?)?.isNotEmpty == true ? ' · ${first['classroom_name']}' : ''}",
            onTap: () {
              final cid = first['classroom_id']?.toString();
              final sid = first['student_id']?.toString();
              if (cid != null && sid != null) {
                context.push('/teacher/students/$cid/$sid');
              } else if (cid != null) {
                context.push('/teacher/classrooms/$cid');
              }
            },
          ),
        ),
      );
    }

    if (tiles.isEmpty) {
      return const SahlhaCard(
        child: Text('Everything is on track. Nice work.'),
      );
    }
    return Column(children: tiles);
  }
}
