import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../domain/classroom.dart';

part 'classroom_repository.g.dart';

/// Teacher classrooms + student enrollment (join codes).
class ClassroomRepository {
  ClassroomRepository(this._dio);

  final Dio _dio;

  Future<List<Classroom>> list() async {
    try {
      final res = await _dio.get<dynamic>('/classrooms');
      final items = (res.data as List? ?? []).cast<Map<String, dynamic>>();
      return items.map(Classroom.fromJson).toList();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<Classroom> create({
    required String name,
    required String subject,
    required String gradeLevel,
  }) async {
    try {
      final res = await _dio.post<dynamic>(
        '/classrooms',
        data: {'name': name, 'subject': subject, 'grade_level': gradeLevel},
      );
      return Classroom.fromJson(_asMap(res.data));
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<Classroom> get(String id) async {
    try {
      final res = await _dio.get<dynamic>('/classrooms/$id');
      return Classroom.fromJson(_asMap(res.data));
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<List<ClassroomStudent>> students(String id) async {
    try {
      final res = await _dio.get<dynamic>('/classrooms/$id/students');
      final items = (res.data as List? ?? []).cast<Map<String, dynamic>>();
      return items.map(ClassroomStudent.fromJson).toList();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<JoinResult> join(String code) async {
    try {
      final res = await _dio.post<dynamic>(
        '/classrooms/join',
        data: {'join_code': code.trim().toUpperCase()},
      );
      return JoinResult.fromJson(_asMap(res.data));
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

/// Result of joining a classroom with a join code.
class JoinResult {
  const JoinResult({required this.classroom, required this.alreadyEnrolled});

  final Classroom classroom;
  final bool alreadyEnrolled;

  factory JoinResult.fromJson(Map<String, dynamic> json) => JoinResult(
    classroom: Classroom.fromJson(_asMap(json['classroom'])),
    alreadyEnrolled: json['already_enrolled'] as bool? ?? false,
  );
}

Map<String, dynamic> _asMap(dynamic data) =>
    Map<String, dynamic>.from(data as Map);

@riverpod
ClassroomRepository classroomRepository(Ref ref) =>
    ClassroomRepository(ref.watch(apiClientProvider).dio);

/// Classrooms visible to the signed-in user
/// (teacher: own rooms · student: enrolled rooms).
@riverpod
Future<List<Classroom>> classroomList(Ref ref) =>
    ref.watch(classroomRepositoryProvider).list();
