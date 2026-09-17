import 'package:freezed_annotation/freezed_annotation.dart';

part 'assessment_models.freezed.dart';
part 'assessment_models.g.dart';

/// Student-facing question. NEVER carries the correct answer.
@freezed
abstract class PracticeQuestion with _$PracticeQuestion {
  const factory PracticeQuestion({
    required String id,
    @JsonKey(name: 'bank_id') @Default('') String bankId,
    @JsonKey(name: 'skill_id') @Default('') String skillId,
    @Default('multiple_choice') String type,
    @Default('') String question,
    @Default([]) List<String> options,
    @Default('medium') String difficulty,
  }) = _PracticeQuestion;

  factory PracticeQuestion.fromJson(Map<String, dynamic> json) =>
      _$PracticeQuestionFromJson(json);
}

@freezed
abstract class AssessmentStart with _$AssessmentStart {
  const factory AssessmentStart({
    @JsonKey(name: 'assessment_id') @Default('') String assessmentId,
    @Default([]) List<PracticeQuestion> questions,
  }) = _AssessmentStart;

  factory AssessmentStart.fromJson(Map<String, dynamic> json) =>
      _$AssessmentStartFromJson(json);
}

@freezed
abstract class QuestionResult with _$QuestionResult {
  const factory QuestionResult({
    @JsonKey(name: 'question_id') @Default('') String questionId,
    @Default(false) bool correct,
    @JsonKey(name: 'skill_id') @Default('') String skillId,
  }) = _QuestionResult;

  factory QuestionResult.fromJson(Map<String, dynamic> json) =>
      _$QuestionResultFromJson(json);
}

@freezed
abstract class AssessmentResult with _$AssessmentResult {
  const factory AssessmentResult({
    @JsonKey(name: 'assessment_id') @Default('') String assessmentId,
    @Default(0) double score,
    @Default(0) int correct,
    @Default(0) int total,
    @Default([]) List<QuestionResult> results,
    @JsonKey(name: 'mastery_states')
    @Default({})
    Map<String, String> masteryStates,
  }) = _AssessmentResult;

  factory AssessmentResult.fromJson(Map<String, dynamic> json) =>
      _$AssessmentResultFromJson(json);
}

@freezed
abstract class Grade with _$Grade {
  const factory Grade({
    required String id,
    @Default(0) double score,
    @JsonKey(name: 'num_questions') @Default(0) int numQuestions,
    @JsonKey(name: 'created_at') String? createdAt,
    @JsonKey(name: 'classroom_id') String? classroomId,
    @JsonKey(name: 'skill_id') @Default('') String skillId,
  }) = _Grade;

  factory Grade.fromJson(Map<String, dynamic> json) => _$GradeFromJson(json);
}

@freezed
abstract class CheckResult with _$CheckResult {
  const factory CheckResult({
    @JsonKey(name: 'question_id') @Default('') String questionId,
    @Default(false) bool correct,
    @Default('') String explanation,
    @JsonKey(name: 'correct_answer') dynamic correctAnswer,
  }) = _CheckResult;

  factory CheckResult.fromJson(Map<String, dynamic> json) =>
      _$CheckResultFromJson(json);
}
