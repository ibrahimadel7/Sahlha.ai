import 'package:freezed_annotation/freezed_annotation.dart';

part 'skill_models.freezed.dart';
part 'skill_models.g.dart';

@freezed
abstract class PathSkill with _$PathSkill {
  const factory PathSkill({
    required String id,
    @JsonKey(name: 'skill_id') @Default('') String skillId,
    @Default('') String name,
    @Default('') String description,
    @Default(false) bool explanation,
    @Default(0) int attempted,
    double? accuracy,
    @Default('not_started') String state,
    @JsonKey(name: 'exercise_ready') @Default(false) bool exerciseReady,
    @JsonKey(name: 'bank_questions') @Default(0) int bankQuestions,
    @JsonKey(name: 'practice_questions') @Default(0) int practiceQuestions,
  }) = _PathSkill;

  factory PathSkill.fromJson(Map<String, dynamic> json) =>
      _$PathSkillFromJson(json);
}

@freezed
abstract class PathUnit with _$PathUnit {
  const factory PathUnit({
    @JsonKey(name: 'material_id') @Default('') String materialId,
    @Default('') String title,
    @Default('') String status,
    @Default([]) List<PathSkill> skills,
  }) = _PathUnit;

  factory PathUnit.fromJson(Map<String, dynamic> json) =>
      _$PathUnitFromJson(json);
}

@freezed
abstract class SkillBundle with _$SkillBundle {
  const factory SkillBundle({
    @JsonKey(name: 'example_metadata', includeToJson: false)
    @Default({})
    Map<String, dynamic> exampleMetadata,
    @JsonKey(name: 'skill_id') @Default('') String skillId,
    @Default('') String name,
    @Default('') String subject,
    @Default('') String description,
    @Default('') String explanation,
    @JsonKey(name: 'key_concepts') @Default([]) List<String> keyConcepts,
    @JsonKey(name: 'has_image') @Default(false) bool hasImage,
    @Default(1) int position,
    @Default(1) int total,
    @Default('not_started') String state,
    @JsonKey(name: 'exercise_ready') @Default(false) bool exerciseReady,
    @JsonKey(name: 'help_order')
    @Default(['simpler', 'example', 'read_aloud', 'steps', 'visual', 'word'])
    List<String> helpOrder,
  }) = _SkillBundle;

  factory SkillBundle.fromJson(Map<String, dynamic> json) =>
      _$SkillBundleFromJson({...json, 'example_metadata': json});
}

@freezed
abstract class SkillHelp with _$SkillHelp {
  const factory SkillHelp({
    @JsonKey(name: 'example_metadata', includeToJson: false)
    @Default({})
    Map<String, dynamic> exampleMetadata,
    @Default('') String kind,
    @Default('') String title,
    @Default('') String body,
    @Default([]) List<String> steps,
    @JsonKey(name: 'key_concepts') @Default([]) List<String> keyConcepts,
    @JsonKey(name: 'has_image') @Default(false) bool hasImage,
  }) = _SkillHelp;

  factory SkillHelp.fromJson(Map<String, dynamic> json) =>
      _$SkillHelpFromJson({...json, 'example_metadata': json});
}
