import 'package:freezed_annotation/freezed_annotation.dart';

part 'bank_models.freezed.dart';
part 'bank_models.g.dart';

/// Teacher-facing question (correct answer visible — teachers are authorized).
@freezed
abstract class BankQuestion with _$BankQuestion {
  const factory BankQuestion({
    required String id,
    @JsonKey(name: 'skill_id') @Default('') String skillId,
    @Default('multiple_choice') String type,
    @Default('') String question,
    @Default([]) List<dynamic> options,
    @JsonKey(name: 'correct_answer') dynamic correctAnswer,
    @Default('') String explanation,
    @Default('medium') String difficulty,
  }) = _BankQuestion;

  factory BankQuestion.fromJson(Map<String, dynamic> json) =>
      _$BankQuestionFromJson(json);
}

extension BankQuestionX on BankQuestion {
  List<String> get optionTexts =>
      options.map((o) => o.toString()).toList(growable: false);

  String get correctAnswerText {
    final c = correctAnswer;
    if (c is int && c >= 0 && c < optionTexts.length) return optionTexts[c];
    return c?.toString() ?? '';
  }
}

@freezed
abstract class BankSummary with _$BankSummary {
  const factory BankSummary({
    String? id,
    @JsonKey(name: 'skill_id') @Default('') String skillId,
    @Default(1) int version,
    @Default('pending_review') String status,
    @Default('') String feedback,
    @JsonKey(name: 'num_questions') @Default(0) int numQuestions,
    @JsonKey(name: 'classroom_id') String? classroomId,
    @JsonKey(name: 'material_id') String? materialId,
  }) = _BankSummary;

  factory BankSummary.fromJson(Map<String, dynamic> json) =>
      _$BankSummaryFromJson(json);
}

extension BankSummaryX on BankSummary {
  bool get isPending => status == 'pending_review';
  bool get isApproved => status == 'approved';

  String get statusLabel => switch (status) {
    'approved' => 'Approved',
    'rejected' => 'Rejected',
    _ => 'Pending review',
  };
}

@freezed
abstract class BankDetail with _$BankDetail {
  const factory BankDetail({
    required String id,
    @JsonKey(name: 'skill_id') @Default('') String skillId,
    @JsonKey(name: 'lesson_id') @Default('') String lessonId,
    @Default(1) int version,
    @Default('pending_review') String status,
    @Default('') String feedback,
    @JsonKey(name: 'classroom_id') String? classroomId,
    @JsonKey(name: 'material_id') String? materialId,
    @Default([]) List<BankQuestion> questions,
  }) = _BankDetail;

  factory BankDetail.fromJson(Map<String, dynamic> json) =>
      _$BankDetailFromJson(json);
}
