import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/sahlha_widgets.dart'
    show SahlhaAppBar, EmptyState, ErrorState, SahlhaPrimaryButton;
import '../../classrooms/data/classroom_repository.dart';
import '../data/student_repository.dart';
import 'journey_presentation.dart';
import 'widgets/learning_journey.dart';
import 'widgets/playful_background.dart';

class LearnScreen extends ConsumerWidget {
  const LearnScreen({super.key, this.classroomId, this.supplementary = false});
  final String? classroomId;
  final bool supplementary;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rooms = ref.watch(classroomListProvider);
    return Scaffold(
      appBar: SahlhaAppBar(
        title: supplementary ? 'Extra learning' : 'Your learning path',
      ),
      body: PlayfulBackground(
        variant: PlayfulVariant.path,
        child: StudentCanvas(
          child: supplementary
              ? const JourneyContent(supplementary: true)
              : rooms.when(
                  loading: () => const JourneyLoading(),
                  error: (_, _) => ErrorState(
                    message: "We couldn't load your learning path.",
                    onRetry: () => ref.invalidate(classroomListProvider),
                  ),
                  data: (list) {
                    if (list.isEmpty) {
                      return EmptyState(
                        title: 'Your journey starts here',
                        message: 'Join your classroom to discover your first learning step.',
                        action: SahlhaPrimaryButton(
                          label: 'Join a classroom',
                          onPressed: () => context.push('/student/join'),
                        ),
                      );
                    }
                    final selected =
                        list.where((r) => r.id == classroomId).firstOrNull ??
                        list.first;
                    return Column(
                      children: [
                        if (list.length > 1)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
                            child: DropdownButtonFormField<String>(
                              key: ValueKey(selected.id),
                              initialValue: selected.id,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Your classroom',
                              ),
                              items: list
                                  .map(
                                    (r) => DropdownMenuItem(
                                      value: r.id,
                                      child: Text(
                                        studentTitle(r.name),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (id) {
                                if (id != null) {
                                  context.go(learningLocation(classroomId: id));
                                }
                              },
                            ),
                          ),
                        Expanded(
                          child: JourneyContent(
                            key: ValueKey(selected.id),
                            classroomId: selected.id,
                            subject: selected.subject,
                          ),
                        ),
                      ],
                    );
                  },
                ),
        ),
      ),
    );
  }
}

class JourneyContent extends ConsumerStatefulWidget {
  const JourneyContent({
    super.key,
    this.classroomId,
    this.subject = '',
    this.supplementary = false,
  });
  final String? classroomId;
  final String subject;
  final bool supplementary;
  @override
  ConsumerState<JourneyContent> createState() => _JourneyContentState();
}

class _JourneyContentState extends ConsumerState<JourneyContent> {
  String? _selectedUnit;
  @override
  Widget build(BuildContext context) {
    final provider = studentLearningPathProvider(
      classroomId: widget.classroomId,
      supplementary: widget.supplementary,
    );
    return ref
        .watch(provider)
        .when(
          loading: () => const JourneyLoading(),
          error: (_, _) => ErrorState(
            message: "We couldn't load your learning path.",
            onRetry: () => ref.invalidate(provider),
          ),
          data: (data) {
            final journey = LearningJourney.fromJson(
              data,
              subject: widget.subject,
            );
            if (journey.total == 0) {
              return const EmptyState(
                title: 'Your learning path is being prepared.',
                message: 'Your next learning steps will appear here when they are ready.',
              );
            }
            final unit =
                journey.units
                    .where((u) => u.source.materialId == _selectedUnit)
                    .firstOrNull ??
                journey.activeUnit!;
            return RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(provider);
                await ref.read(provider.future);
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(22, 12, 22, 28),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  if (widget.subject.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Text(studentTitle(widget.subject)),
                    ),
                  LearningUnitHeader(unit: unit, subject: widget.subject),
                  if (journey.units.length > 1)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        icon: const Icon(Icons.unfold_more_rounded, size: 18),
                        label: const Text('Explore units'),
                        onPressed: () => _chooseUnit(journey),
                      ),
                    ),
                  if (unit.steps.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'This unit is being prepared. Explore another unit while you wait.',
                      ),
                    ),
                  if (unit.steps.isNotEmpty)
                    LearningPath(
                      key: ValueKey(unit.source.materialId),
                      unit: unit,
                      openSkill: (step) => context.push(
                        lessonLocation(
                          step,
                          classroomId: widget.classroomId,
                          supplementary: widget.supplementary,
                        ),
                      ),
                      openCheckpoint: (step) => context.push(
                        practiceLocation(
                          materialId: step.materialId,
                          classroomId: widget.classroomId,
                          supplementary: widget.supplementary,
                          mode: 'checkpoint',
                        ),
                      ),
                      openMastery: () => context.push(
                        practiceLocation(
                          materialId: unit.source.materialId,
                          classroomId: widget.classroomId,
                          supplementary: widget.supplementary,
                          mode: 'mastery',
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  Text(
                    'Small steps. Lasting understanding.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            );
          },
        );
  }

  Future<void> _chooseUnit(LearningJourney journey) async {
    final id = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Your learning units',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            for (final unit in journey.units)
              ListTile(
                title: Text(unit.title),
                subtitle: Text(
                  'Unit ${unit.number} · ${unit.mastered} of ${unit.steps.length} mastered',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.pop(context, unit.source.materialId),
              ),
          ],
        ),
      ),
    );
    if (mounted && id != null) setState(() => _selectedUnit = id);
  }
}
