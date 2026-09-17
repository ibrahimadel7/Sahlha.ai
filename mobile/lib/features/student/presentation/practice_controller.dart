import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/student_repository.dart';
import '../domain/assessment_models.dart';

part 'practice_controller.freezed.dart';
part 'practice_controller.g.dart';

@freezed
abstract class PracticeState with _$PracticeState {
  const factory PracticeState({
    @Default(false) bool starting,
    String? assessmentId,
    @Default([]) List<PracticeQuestion> questions,
    @Default(0) int index,
    @Default({}) Map<String, Object?> answers,
    @Default(false) bool submitting,
    @Default(false) bool checking,
    AssessmentResult? result,
    String? error,
    @Default({}) Map<String, CheckResult> checked,
    // Progressive support level for the current question (hint -> example).
    @Default(0) int supportLevel,
    // Scope of the started assessment, so refreshes after submit only
    // invalidate the affected learning-path/skill providers (no refetch
    // storms across every classroom).
    String? classroomId,
    String? materialId,
    String? skillId,
    @Default(false) bool childScope,
  }) = _PracticeState;
}

extension PracticeStateX on PracticeState {
  PracticeQuestion? get current =>
      questions.isEmpty || index >= questions.length ? null : questions[index];
  bool get isLast => questions.isNotEmpty && index >= questions.length - 1;
  int get answered => answers.length;
}

@riverpod
class PracticeController extends _$PracticeController {
  @override
  PracticeState build() => const PracticeState();

  Future<void> start({
    String? classroomId,
    String? materialId,
    String? skillId,
    bool childScope = false,
    bool checkpoint = false,
  }) async {
    if (state.starting) return;
    state = PracticeState(
      starting: true,
      classroomId: classroomId,
      materialId: materialId,
      skillId: skillId,
      childScope: childScope,
    );
    try {
      final started = checkpoint
          ? await ref
                .read(studentRepositoryProvider)
                .startQuickCheck(
                  classroomId: classroomId,
                  materialId: materialId,
                  childScope: childScope,
                )
          : await ref
                .read(studentRepositoryProvider)
                .startAssessment(
                  classroomId: classroomId,
                  materialId: materialId,
                  skillId: skillId,
                  childScope: childScope,
                );
      if (!ref.mounted) return;
      state = PracticeState(
        assessmentId: started.assessmentId,
        questions: started.questions,
        classroomId: classroomId,
        materialId: materialId,
        skillId: skillId,
        childScope: childScope,
      );
    } catch (_) {
      if (!ref.mounted) return;
      state = state.copyWith(
        starting: false,
        error: "We couldn't prepare your practice. Please try again.",
      );
    }
  }

  void answerCurrent(Object? answer) {
    final q = state.current;
    if (q == null ||
        state.result != null ||
        state.checking ||
        state.checked.containsKey(q.id)) {
      return;
    }
    state = state.copyWith(
      answers: {...state.answers, q.id: answer},
      supportLevel: 0,
    );
  }

  Future<void> checkCurrent() async {
    final q = state.current;
    final id = state.assessmentId;
    if (q == null ||
        id == null ||
        state.checking ||
        state.checked.containsKey(q.id)) {
      return;
    }
    final answer = state.answers[q.id];
    if (answer == null || (answer is String && answer.trim().isEmpty)) return;
    state = state.copyWith(error: null, checking: true);
    try {
      final res = await ref
          .read(studentRepositoryProvider)
          .checkAnswer(assessmentId: id, questionId: q.id, answer: answer);
      if (!ref.mounted || state.assessmentId != id) return;
      state = state.copyWith(
        checking: false,
        checked: {...state.checked, q.id: res},
      );
    } catch (_) {
      if (!ref.mounted || state.assessmentId != id) return;
      state = state.copyWith(
        checking: false,
        error: "We couldn't check your answer. Try again when you're ready.",
      );
    }
  }

  void next() {
    if (!state.isLast) {
      state = state.copyWith(index: state.index + 1, supportLevel: 0);
    }
  }

  void previous() {
    if (state.index > 0) {
      state = state.copyWith(index: state.index - 1, supportLevel: 0);
    }
  }

  /// Progressive support without giving away the answer. The level is
  /// bounded (the UI shows one hint card) and repeat taps collapse into one
  /// network signal via the repository throttle.
  void requestSupportHint() {
    if (state.supportLevel >= 2) return;
    state = state.copyWith(supportLevel: state.supportLevel + 1);
    ref.read(studentRepositoryProvider).supportSignal('hint_used');
  }

  Future<void> submit() async {
    final id = state.assessmentId;
    if (id == null || state.submitting) return;
    state = state.copyWith(submitting: true, error: null);
    try {
      final result = await ref
          .read(studentRepositoryProvider)
          .submitAssessment(assessmentId: id, answers: state.answers);
      if (!ref.mounted || state.assessmentId != id) return;
      state = state.copyWith(submitting: false, result: result);
      // Refresh progress-dependent providers, scoped to the practiced
      // material so other classrooms do not refetch in a storm.
      ref.invalidate(studentHomeProvider);
      ref.invalidate(studentProgressProvider);
      ref.invalidate(
        studentLearningPathProvider(
          classroomId: state.classroomId,
          supplementary: state.childScope,
        ),
      );
      if (state.materialId != null && state.materialId!.isNotEmpty) {
        ref.invalidate(
          studentSkillBundleProvider(
            skillId: state.skillId ?? '',
            materialId: state.materialId!,
            classroomId: state.classroomId,
            supplementary: state.childScope,
          ),
        );
      }
    } catch (_) {
      if (!ref.mounted || state.assessmentId != id) return;
      state = state.copyWith(
        submitting: false,
        error: "We couldn't save your results. Please try again.",
      );
    }
  }

  void reset() => state = const PracticeState();
}
