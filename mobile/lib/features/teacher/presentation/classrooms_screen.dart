import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/sahlha_spacing.dart';
import '../../../core/widgets/sahlha_widgets.dart';
import '../../classrooms/data/classroom_repository.dart';
import '../../materials/data/material_repository.dart';
import 'widgets/teacher_widgets.dart';

/// My Classrooms — matches the reference: title + New classroom action,
/// All / Active / Archived filter, premium classroom rows with subject icon,
/// grade + students + real material counts.
class ClassroomsScreen extends ConsumerStatefulWidget {
  const ClassroomsScreen({super.key});

  @override
  ConsumerState<ClassroomsScreen> createState() => _ClassroomsScreenState();
}

class _ClassroomsScreenState extends ConsumerState<ClassroomsScreen> {
  String _filter = 'All';

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final rooms = ref.watch(classroomListProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text('My Classrooms', style: text.titleLarge),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: FilledButton.icon(
              onPressed: () => context.push('/teacher/classrooms/new'),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New classroom'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
      body: rooms.when(
        loading: () => const LoadingState(message: 'Loading classrooms…'),
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
                onPressed: () => context.push('/teacher/classrooms/new'),
              ),
            );
          }
          final filtered = _applyFilter(list);
          return Consumer(
            builder: (context, ref, _) {
              // Single request for all materials; counts grouped locally
              // (avoids one request per classroom row).
              final allMaterials =
                  ref.watch(materialListProvider()).value ?? const [];
              final counts = <String, int>{};
              for (final m in allMaterials) {
                final cid = m.classroomId;
                if (cid != null) counts[cid] = (counts[cid] ?? 0) + 1;
              }
              return ListView(
                padding: const EdgeInsets.all(SahlhaSpacing.page),
                children: [
                  TeacherFilterChips(
                    options: const ['All', 'Active', 'Archived'],
                    selected: _filter,
                    onSelected: (v) => setState(() => _filter = v),
                  ),
                  const SizedBox(height: SahlhaSpacing.md),
                  if (filtered.isEmpty)
                    const SahlhaCard(
                      child: Text('Nothing here under this filter.'),
                    )
                  else
                    for (final room in filtered)
                      Padding(
                        padding: const EdgeInsets.only(
                          bottom: SahlhaSpacing.sm,
                        ),
                        child: Builder(
                          builder: (context) {
                            final s = teacherSubjectIcon(room.subject);
                            final grade = room.gradeLevel.isEmpty
                                ? ''
                                : 'Grade ${room.gradeLevel}';
                            final subject = room.subject.isEmpty
                                ? grade
                                : room.subject;
                            final matCount = counts[room.id];
                            return TeacherClassroomTile(
                              icon: s.icon,
                              iconBg: s.bg,
                              iconFg: s.fg,
                              title: room.name,
                              subtitle:
                                  '${grade.isEmpty ? subject : '$subject · $grade'} · ${room.numStudents ?? 0} students'
                                      .trim(),
                              meta: matCount == null
                                  ? 'Loading materials…'
                                  : '$matCount material${matCount == 1 ? '' : 's'}',
                              onTap: () => context.push(
                                '/teacher/classrooms/${room.id}',
                              ),
                            );
                          },
                        ),
                      ),
                  const SizedBox(height: 80),
                ],
              );
            },
          );
        },
      ),
    );
  }

  List<dynamic> _applyFilter(List<dynamic> list) {
    // Backend has no archived flag today — Active shows all real rooms,
    // Archived shows an honest empty state (no fake data).
    if (_filter == 'Archived') return const [];
    return list;
  }
}




