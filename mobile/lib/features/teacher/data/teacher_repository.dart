import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../domain/bank_models.dart';

part 'teacher_repository.g.dart';

/// Teacher platform APIs: overview, classroom mastery, student
/// progress, and the full question-bank review workflow.
class TeacherRepository {
  TeacherRepository(this._dio);

  final Dio _dio;

  Future<Map<String, dynamic>> overview() async {
    try {
      final res = await _dio.get<dynamic>('/teacher/overview');
      return _asMap(res.data);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<Map<String, dynamic>> classroomMastery(String classroomId) async {
    try {
      final res = await _dio.get<dynamic>(
        '/teacher/classrooms/$classroomId/mastery',
      );
      return _asMap(res.data);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<Map<String, dynamic>> studentProgress(
    String classroomId,
    String studentId,
  ) async {
    try {
      final res = await _dio.get<dynamic>(
        '/teacher/classrooms/$classroomId/students/$studentId',
      );
      return _asMap(res.data);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<BankDetail> bankDetail(String bankId) async {
    try {
      final res = await _dio.get<dynamic>('/teacher/banks/$bankId');
      return BankDetail.fromJson(_asMap(res.data));
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<List<BankSummary>> listBanks({
    String? status,
    String? classroomId,
    String? materialId,
  }) async {
    try {
      final query = <String, dynamic>{};
      if (status != null) query['status'] = status;
      if (classroomId != null) query['classroom_id'] = classroomId;
      if (materialId != null) query['material_id'] = materialId;
      final res = await _dio.get<dynamic>(
        '/teacher/banks',
        queryParameters: query,
      );
      final items = (res.data as List? ?? []).cast<Map<String, dynamic>>();
      return items.map(BankSummary.fromJson).toList();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<void> approveBank(String bankId) async {
    try {
      await _dio.post<dynamic>('/teacher/banks/$bankId/approve');
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<void> rejectBank(String bankId, String feedback) async {
    try {
      await _dio.post<dynamic>(
        '/teacher/banks/$bankId/reject',
        queryParameters: {'feedback': feedback},
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<void> editQuestion(
    String bankId,
    String questionId, {
    String? questionText,
    List<String>? options,
    int? correctAnswer,
    String? explanation,
  }) async {
    try {
      final data = <String, dynamic>{};
      if (questionText != null) data['question_text'] = questionText;
      if (options != null) data['options'] = options;
      if (correctAnswer != null) data['correct_answer'] = correctAnswer;
      if (explanation != null) data['explanation'] = explanation;
      await _dio.patch<dynamic>(
        '/teacher/banks/$bankId/questions/$questionId',
        data: data,
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<void> deleteQuestion(String bankId, String questionId) async {
    try {
      await _dio.delete<dynamic>(
        '/teacher/banks/$bankId/questions/$questionId',
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<void> regenerateQuestion(
    String bankId,
    String questionId,
    String feedback,
  ) async {
    try {
      await _dio.post<dynamic>(
        '/teacher/banks/$bankId/questions/$questionId/regenerate',
        data: {'feedback': feedback},
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

Map<String, dynamic> _asMap(dynamic data) =>
    Map<String, dynamic>.from(data as Map);

@riverpod
TeacherRepository teacherRepository(Ref ref) =>
    TeacherRepository(ref.watch(apiClientProvider).dio);

/// Dashboard cards: class/student counts, pending banks, support list.
@riverpod
Future<Map<String, dynamic>> teacherOverview(Ref ref) =>
    ref.watch(teacherRepositoryProvider).overview();

/// Skill-level analytics for one classroom.
@riverpod
Future<Map<String, dynamic>> classroomMastery(Ref ref, String classroomId) =>
    ref.watch(teacherRepositoryProvider).classroomMastery(classroomId);

/// One question bank with teacher-visible questions for review.
@riverpod
Future<BankDetail> bankDetail(Ref ref, String bankId) =>
    ref.watch(teacherRepositoryProvider).bankDetail(bankId);

/// All / filtered banks for the signed-in teacher (Reviews surface).
/// Keepalive=false on purpose: Reviews must always reflect the backend.
@riverpod
Future<List<BankSummary>> teacherBanks(
  Ref ref, {
  String? status,
  String? classroomId,
  String? materialId,
}) => ref
    .watch(teacherRepositoryProvider)
    .listBanks(
      status: status,
      classroomId: classroomId,
      materialId: materialId,
    );

/// Pending-review banks only (home badge + Reviews tab).
@riverpod
Future<List<BankSummary>> pendingBanks(Ref ref) =>
    ref.watch(teacherRepositoryProvider).listBanks(status: 'pending_review');

/// One student's full progress (teacher view). Public so Curriculum Studio
/// Students tab and Student Detail share one source of truth.
@riverpod
Future<Map<String, dynamic>> teacherStudentProgress(
  Ref ref,
  String classroomId,
  String studentId,
) => ref
    .watch(teacherRepositoryProvider)
    .studentProgress(classroomId, studentId);
