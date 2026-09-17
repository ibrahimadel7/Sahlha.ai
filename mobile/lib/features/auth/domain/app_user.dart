import 'package:freezed_annotation/freezed_annotation.dart';

part 'app_user.freezed.dart';
part 'app_user.g.dart';

@freezed
abstract class AppUser with _$AppUser {
  const factory AppUser({
    required String id,
    @Default('') String name,
    @Default('') String email,
    @Default('student') String role,
    @JsonKey(name: 'link_code') @Default('') String linkCode,
  }) = _AppUser;

  factory AppUser.fromJson(Map<String, dynamic> json) =>
      _$AppUserFromJson(json);
}

extension AppUserX on AppUser {
  bool get isTeacher => role == 'teacher';
  bool get isStudent => role == 'student';
  bool get isParent => role == 'parent';

  String get homeRoute => switch (role) {
    'teacher' => '/teacher/home',
    'parent' => '/parent/home',
    _ => '/student/home',
  };
}
