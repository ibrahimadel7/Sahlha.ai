import 'package:freezed_annotation/freezed_annotation.dart';

part 'classroom.freezed.dart';
part 'classroom.g.dart';

@freezed
abstract class Classroom with _$Classroom {
  const factory Classroom({
    required String id,
    @JsonKey(name: 'teacher_id') @Default('') String teacherId,
    @Default('') String name,
    @Default('') String subject,
    @JsonKey(name: 'grade_level') @Default('') String gradeLevel,
    @JsonKey(name: 'join_code') @Default('') String joinCode,
    @JsonKey(name: 'num_students') int? numStudents,
  }) = _Classroom;

  factory Classroom.fromJson(Map<String, dynamic> json) =>
      _$ClassroomFromJson(json);
}

@freezed
abstract class ClassroomStudent with _$ClassroomStudent {
  const factory ClassroomStudent({
    required String id,
    @Default('') String name,
  }) = _ClassroomStudent;

  factory ClassroomStudent.fromJson(Map<String, dynamic> json) =>
      _$ClassroomStudentFromJson(json);
}
