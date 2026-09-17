import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/sahlha_colors.dart';
import '../../../core/theme/sahlha_spacing.dart';
import '../../../core/widgets/sahlha_widgets.dart';
import '../../classrooms/data/classroom_repository.dart';
import '../data/teacher_repository.dart';
import 'widgets/teacher_widgets.dart';

/// Student Detail — matches the reference Maya Hassan screen.
///
/// Header avatar + name + grade + On track pill, Learning summary trio
/// (real counts), Current lesson (real first in-progress unit), Skills list
/// with real states. Supportive language only.
class StudentDetailScreen extends ConsumerWidget {
  const StudentDetailScreen({
    super.key,
    required this.classroomId,
    required this.studentId,
  });

  final String classroomId;
  final String studentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final detail = ref.watch(
      teacherStudentProgressProvider(classroomId, studentId),
    );
    final students = ref.watch(_classStudentsProvider(classroomId));
    final rooms = ref.watch(classroomListProvider).value ?? const [];
    String gradeLabel = '';
    for (final r in rooms) {
      if (r.id == classroomId) {
        gradeLabel = r.gradeLevel.isEmpty ? r.subject : 'Grade ${r.gradeLevel}';
        break;
      }
    }
    String studentName = '';
    for (final s in students.value ?? const []) {
      if (s.id == studentId) {
        studentName = s.name;
        break;
      }
    }

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/teacher/classrooms/$classroomId');
            }
          },
        ),
        title: Text(
          studentName.isEmpty ? 'Student' : studentName,
          style: text.titleLarge,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none_outlined),
            onPressed: () {},
          ),
        ],
      ),
      body: detail.when(
        loading: () => const LoadingState(message: 'Loading progress…'),
        error: (e, _) => ErrorState(
          message: e.toString(),
          onRetry: () => ref.invalidate(
            teacherStudentProgressProvider(classroomId, studentId),
          ),
        ),
        data: (data) {
          final units = (data['units'] as List? ?? []);
          final support = (data['support_summary'] as List? ?? [])
              .cast<String>();
          final states = [
            for (final u in units)
              for (final s in ((u as Map)['skills'] as List? ?? []))
                (s as Map)['state']?.toString() ?? 'not_started',
          ];
          int count(String k) => states.where((s) => s == k).length;
          final mastered = count('mastered');
          final developing = count('developing');
          final needs = count('needs_practice');
          final onTrack = needs == 0;

          // Current lesson: first unit with any non-mastered skill, else first.
          Map<String, dynamic>? currentUnit;
          double currentProgress = 0;
          for (final u in units) {
            final um = u as Map<String, dynamic>;
            final uskills = (um['skills'] as List? ?? []);
            if (uskills.isEmpty) continue;
            var mCount = 0;
            for (final s in uskills) {
              if ((s as Map)['state']?.toString() == 'mastered') mCount++;
            }
            final progress = mCount / uskills.length;
            if (currentUnit == null && progress < 1.0) {
              currentUnit = um;
              currentProgress = progress;
            }
          }
          currentUnit ??= units.isEmpty
              ? null
              : units.first as Map<String, dynamic>;
          if (currentUnit != null) {
            final uskills = (currentUnit['skills'] as List? ?? []);
            var mCount = 0;
            for (final s in uskills) {
              if ((s as Map)['state']?.toString() == 'mastered') mCount++;
            }
            currentProgress = uskills.isEmpty ? 0 : mCount / uskills.length;
          }

          // Flatten skills for the Skills section (real states).
          final flatSkills = <Map<String, dynamic>>[];
          for (final u in units) {
            final um = u as Map<String, dynamic>;
            for (final s in (um['skills'] as List? ?? [])) {
              final sm = Map<String, dynamic>.from(s as Map);
              sm['unit_title'] = um['title']?.toString() ?? '';
              flatSkills.add(sm);
            }
          }

          return ListView(
            padding: const EdgeInsets.all(SahlhaSpacing.page),
            children: [
              SahlhaCard(
                child: Row(
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: teacherAvatarColor(studentId),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          teacherInitials(
                            studentName.isEmpty ? '?' : studentName,
                          ),
                          style: text.titleLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: SahlhaSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            studentName.isEmpty ? 'Student' : studentName,
                            style: text.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            gradeLabel,
                            style: text.bodySmall?.copyWith(
                              color: SahlhaColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ReviewPill(
                      label: onTrack ? 'On track' : 'Needs support',
                      tone: onTrack ? 'ready' : 'attention',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: SahlhaSpacing.lg),
              Text('Learning summary', style: text.titleMedium),
              const SizedBox(height: SahlhaSpacing.sm),
              TeacherSummaryTrio(
                mastered: mastered,
                developing: developing,
                needsPractice: needs,
              ),
              const SizedBox(height: SahlhaSpacing.lg),
              Text('Current lesson', style: text.titleMedium),
              const SizedBox(height: SahlhaSpacing.sm),
              if (currentUnit == null)
                const SahlhaCard(child: Text('No lessons yet.'))
              else
                SahlhaCard(
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: SahlhaColors.tealSoft,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.code_outlined,
                          color: SahlhaColors.tealDark,
                        ),
                      ),
                      const SizedBox(width: SahlhaSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              currentUnit['title']?.toString() ?? '',
                              style: text.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              'In progress — ${(currentProgress * 100).round()}%',
                              style: text.bodySmall?.copyWith(
                                color: SahlhaColors.muted,
                              ),
                            ),
                            const SizedBox(height: 6),
                            SahlhaProgressBar(
                              value: currentProgress,
                              height: 6,
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right,
                        color: SahlhaColors.muted,
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: SahlhaSpacing.lg),
              Text('Skills', style: text.titleMedium),
              const SizedBox(height: SahlhaSpacing.sm),
              if (flatSkills.isEmpty)
                const SahlhaCard(child: Text('No skills yet.'))
              else
                for (final s in flatSkills.take(20))
                  Padding(
                    padding: const EdgeInsets.only(bottom: SahlhaSpacing.sm),
                    child: SahlhaCard(
                      padding: const EdgeInsets.all(SahlhaSpacing.md),
                      child: Row(
                        children: [
                          _SkillStateIcon(
                            state: s['state']?.toString() ?? 'not_started',
                          ),
                          const SizedBox(width: SahlhaSpacing.md),
                          Expanded(
                            child: Text(
                              (s['name'] as String?)?.isNotEmpty == true
                                  ? s['name'] as String
                                  : (s['skill_id']?.toString() ?? ''),
                              style: text.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          SkillStatusBadge(
                            state: s['state']?.toString() ?? 'not_started',
                          ),
                        ],
                      ),
                    ),
                  ),
              if (support.isNotEmpty) ...[
                const SizedBox(height: SahlhaSpacing.lg),
                Text('What seems to help', style: text.titleMedium),
                const SizedBox(height: SahlhaSpacing.sm),
                SahlhaCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final line in support)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.check,
                                size: 18,
                                color: SahlhaColors.teal,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(line, style: text.bodyMedium),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: SahlhaSpacing.xl),
            ],
          );
        },
      ),
    );
  }
}

final _classStudentsProvider = FutureProvider.autoDispose
    .family<List<SimpleStudent>, String>((ref, id) async {
      final list = await ref.watch(classroomRepositoryProvider).students(id);
      return list.map((s) => SimpleStudent(id: s.id, name: s.name)).toList();
    });

class SimpleStudent {
  SimpleStudent({required this.id, required this.name});

  final String id;
  final String name;
}

class _SkillStateIcon extends StatelessWidget {
  const _SkillStateIcon({required this.state});

  final String state;

  @override
  Widget build(BuildContext context) {
    switch (state) {
      case 'mastered':
        return Container(
          width: 36,
          height: 36,
          decoration: const BoxDecoration(
            color: SahlhaColors.successSoft,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check,
            color: SahlhaColors.success,
            size: 18,
          ),
        );
      case 'developing':
        return Container(
          width: 36,
          height: 36,
          decoration: const BoxDecoration(
            color: SahlhaColors.warmYellowSoft,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.trending_up_outlined,
            color: SahlhaColors.warmYellowDeep,
            size: 18,
          ),
        );
      case 'needs_practice':
        return Container(
          width: 36,
          height: 36,
          decoration: const BoxDecoration(
            color: SahlhaColors.softCoralSoft,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.priority_high_outlined,
            color: SahlhaColors.softCoralDark,
            size: 18,
          ),
        );
      case 'in_progress':
        return Container(
          width: 36,
          height: 36,
          decoration: const BoxDecoration(
            color: SahlhaColors.tealSoft,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.play_arrow_outlined,
            color: SahlhaColors.tealDark,
            size: 18,
          ),
        );
      default:
        return Container(
          width: 36,
          height: 36,
          decoration: const BoxDecoration(
            color: Color(0xFFF1F5F9),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.circle_outlined,
            color: SahlhaColors.muted,
            size: 18,
          ),
        );
    }
  }
}
