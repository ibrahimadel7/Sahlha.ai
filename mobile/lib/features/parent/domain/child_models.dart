import 'package:freezed_annotation/freezed_annotation.dart';

part 'child_models.freezed.dart';
part 'child_models.g.dart';

@freezed
abstract class LinkedChild with _$LinkedChild {
  const factory LinkedChild({
    required String id,
    @Default('') String name,
    @Default([]) List<ChildClassroom> classrooms,
  }) = _LinkedChild;

  factory LinkedChild.fromJson(Map<String, dynamic> json) =>
      _$LinkedChildFromJson(json);
}

@freezed
abstract class ChildClassroom with _$ChildClassroom {
  const factory ChildClassroom({
    required String id,
    @Default('') String name,
    @Default('') String subject,
  }) = _ChildClassroom;

  factory ChildClassroom.fromJson(Map<String, dynamic> json) =>
      _$ChildClassroomFromJson(json);
}
