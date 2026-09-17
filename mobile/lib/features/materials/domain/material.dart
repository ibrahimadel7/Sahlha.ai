import 'package:freezed_annotation/freezed_annotation.dart';

part 'material.freezed.dart';
part 'material.g.dart';

@freezed
abstract class Material with _$Material {
  const factory Material({
    required String id,
    @Default('') String title,
    @Default('') String filename,
    @Default('official') String scope,
    @JsonKey(name: 'source_type') @Default('teacher') String sourceType,
    @JsonKey(name: 'classroom_id') String? classroomId,
    @JsonKey(name: 'child_student_id') String? childStudentId,
    @Default('uploaded') String status,
    @JsonKey(name: 'status_detail') @Default('') String statusDetail,
    @JsonKey(name: 'document_id') String? documentId,
    @JsonKey(name: 'num_skills') @Default(0) int numSkills,
    @JsonKey(name: 'num_banks') @Default(0) int numBanks,
    @JsonKey(name: 'approved_banks') @Default(0) int approvedBanks,
  }) = _Material;

  factory Material.fromJson(Map<String, dynamic> json) =>
      _$MaterialFromJson(json);
}

extension MaterialX on Material {
  bool get isSupplementary => scope == 'supplementary';
  bool get isProcessed =>
      status == 'processed' ||
      status == 'skills_ready' ||
      status == 'banks_ready';
  bool get isFailed => status == 'failed';

  /// Student/parent-friendly processing label (no internal jargon).
  String get friendlyStatus => switch (status) {
    'processing' => 'Reading your material…',
    'processed' => 'Ready to find skills',
    'skills_ready' => 'Skills ready',
    'banks_ready' => 'Practice ready',
    'failed' => 'Needs attention',
    _ => 'Uploading…',
  };
}

@freezed
abstract class GeneratedSkill with _$GeneratedSkill {
  const factory GeneratedSkill({
    required String id,
    @JsonKey(name: 'skill_id') @Default('') String skillId,
    @Default('') String name,
    @Default('') String description,
    @Default('') String explanation,
    @JsonKey(name: 'key_concepts') @Default([]) List<String> keyConcepts,
    @JsonKey(name: 'has_image') @Default(false) bool hasImage,
    @JsonKey(name: 'bank_status') @Default('none') String bankStatus,
    @JsonKey(name: 'approved_questions') @Default(0) int approvedQuestions,
  }) = _GeneratedSkill;

  factory GeneratedSkill.fromJson(Map<String, dynamic> json) =>
      _$GeneratedSkillFromJson(json);
}
