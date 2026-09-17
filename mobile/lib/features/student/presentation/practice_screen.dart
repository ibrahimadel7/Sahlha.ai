import 'widgets/joyful_cards.dart';
import 'widgets/lesson_content.dart';
import 'widgets/playful_background.dart';
import 'widgets/quick_check_intro.dart';
import 'widgets/skill_completion.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/sahlha_widgets.dart'
    show
        SahlhaAppBar,
        SahlhaPrimaryButton,
        ErrorState,
        EmptyState,
        LoadingState;
import 'practice_controller.dart';
import 'journey_presentation.dart' show cleanStudentText, learningLocation;
import 'widgets/learning_journey.dart' show StudentCanvas;

class PracticeScreen extends ConsumerStatefulWidget {
  const PracticeScreen({
    super.key,
    this.classroomId,
    this.materialId,
    this.skillId,
    this.supplementary = false,
    this.mode = 'practice',
  });
  final String? classroomId, materialId, skillId;
  final bool supplementary;
  final String mode;
  @override
  ConsumerState<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends ConsumerState<PracticeScreen> {
  final _answer = TextEditingController();
  final _elapsed = Stopwatch();
  bool _intro = true;
  final _scroll = ScrollController();
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted && widget.mode != 'checkpoint') _start();
    });
  }

  Future<void> _start() async {
    _answer.clear();
    _elapsed.stop();
    _elapsed.reset();
    await ref
        .read(practiceControllerProvider.notifier)
        .start(
          classroomId: widget.classroomId,
          materialId: widget.materialId,
          skillId: widget.skillId,
          childScope: widget.supplementary,
          checkpoint: widget.mode == 'checkpoint',
        );
    if (mounted && ref.read(practiceControllerProvider).questions.isNotEmpty) {
      _elapsed.start();
    }
  }

  @override
  void dispose() {
    _elapsed.stop();
    _answer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _path() {
    context.go(
      learningLocation(
        classroomId: widget.classroomId,
        supplementary: widget.supplementary,
      ),
    );
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      _path();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(practiceControllerProvider);
    ref.listen(practiceControllerProvider.select((s) => s.result), (_, result) {
      if (result != null) _elapsed.stop();
    });
    final controller = ref.read(practiceControllerProvider.notifier);
    final text = Theme.of(context).textTheme;
    final title = widget.mode == 'mastery'
        ? 'Unit mastery check'
        : widget.mode == 'checkpoint'
        ? 'Quick Check'
        : 'Practice';
    return Scaffold(
      appBar: SahlhaAppBar(
        title: state.result != null ? 'Your next step' : title,
        onBack: _back,
      ),
      body: PlayfulBackground(
        variant: PlayfulVariant.practice,
        child: StudentCanvas(
          child: SafeArea(
            child: Builder(
              builder: (context) {
                if (widget.mode == 'checkpoint' && _intro) {
                  return QuickCheckIntro(
                    classroomId: widget.classroomId,
                    materialId: widget.materialId,
                    supplementary: widget.supplementary,
                    onStart: () {
                      setState(() => _intro = false);
                      _start();
                    },
                  );
                }
                if (state.starting) {
                  return const LoadingState(
                    message: 'Preparing a little practice…',
                  );
                }
                if (state.error != null && state.questions.isEmpty) {
                  return ErrorState(message: state.error!, onRetry: _start);
                }
                if (state.result != null) return _feedback(context, state);
                if (state.current == null) {
                  return SingleChildScrollView(
                    child: EmptyState(
                      title: 'Practice is being prepared.',
                      message: 'Return to your learning path for another step.',
                      action: SahlhaPrimaryButton(
                        label: 'Back to my path',
                        onPressed: _path,
                      ),
                    ),
                  );
                }
                final q = state.current!;
                final check = state.checked[q.id];
                final selected = state.answers[q.id];
                final valid =
                    selected != null &&
                    (selected is! String || selected.trim().isNotEmpty);
                return ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  children: [
                    PracticeProgressHeader(
                      title: title,
                      index: state.index,
                      total: state.questions.length,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'What will this code print?',
                      style: text.bodySmall?.copyWith(
                        color: const Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xFFE7E1D4)),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF22313F)
                                .withValues(alpha: 0.05),
                            blurRadius: 14,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: LessonContent(source: q.question, question: true),
                    ),
                    const SizedBox(height: 16),
                    if (q.options.isNotEmpty)
                      for (var i = 0; i < q.options.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: AnswerOptionCard(
                            label: cleanStudentText(q.options[i]),
                            index: i,
                            selected: selected == i,
                            correct: check != null
                                ? (check.correctAnswer == i ||
                                      (check.correct && selected == i))
                                : null,
                            onTap: check != null || state.checking
                                ? null
                                : () async {
                                    controller.answerCurrent(i);
                                    await controller.checkCurrent();
                                  },
                          ),
                        )
                    else
                      TextField(
                        controller: _answer,
                        enabled: check == null && !state.checking,
                        minLines: 2,
                        maxLines: 5,
                        decoration: const InputDecoration(
                          labelText: 'Your answer',
                          hintText: 'Write what you think',
                        ),
                        onChanged: controller.answerCurrent,
                      ),
                    if (state.error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(state.error!, style: text.bodyMedium),
                        ),
                      ),
                    if (check != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Semantics(
                          liveRegion: true,
                          child: FeedbackCard(
                            correct: check.correct,
                            message: cleanStudentText(check.explanation).isEmpty
                                ? (check.correct
                                      ? 'The loop runs while the condition is true — nice reading!'
                                      : 'Keep this idea in mind for the next question. You\u2019re getting closer.')
                                : cleanStudentText(check.explanation),
                          ),
                        ),
                      ),
                    if (state.checking)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                          'Checking your answer...',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    if (state.supportLevel > 0 && check == null)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF3D1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: const Color(0xFFFFC94A)
                                .withValues(alpha: 0.4),
                          ),
                        ),
                        child: const Text(
                          'Read one part at a time. What is the question asking you to find?',
                        ),
                      ),
                    const SizedBox(height: 16),
                    if (check == null) ...[
                      if (q.options.isEmpty || state.error != null)
                        SahlhaPrimaryButton(
                          label: 'Check answer',
                          loading: state.checking,
                          onPressed: valid ? controller.checkCurrent : null,
                        ),
                      TextButton.icon(
                        onPressed: controller.requestSupportHint,
                        icon: const Icon(
                          Icons.lightbulb_outline_rounded,
                          size: 20,
                        ),
                        label: const Text('A little hint'),
                      ),
                    ] else
                      SahlhaPrimaryButton(
                        label: state.isLast
                            ? 'Finish practice'
                            : 'Next question →',
                        loading: state.submitting,
                        onPressed: state.isLast
                            ? controller.submit
                            : () {
                                _answer.clear();
                                controller.next();
                                try {
                                  _scroll.jumpTo(0);
                                } catch (_) {}
                              },
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _feedback(BuildContext context, PracticeState state) =>
      SkillCompletion(
        state: state,
        elapsed: _elapsed.elapsed,
        onPath: _path,
        onRetry: _start,
      );
}
