import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../domain/assessment_models.dart';
import '../domain/skill_models.dart';

part 'student_repository.g.dart';

/// Student learning APIs: home, learning path, skill bundles,
/// help, assessments, grades, progress, audio/image URLs.
class StudentRepository {
  StudentRepository(this._dio);

  final Dio _dio;

  /// Last-sent timestamp per support signal, to collapse accidental
  /// double-taps / rebuild storms into one request. Intentional reuse
  /// after the window still counts.
  final Map<String, DateTime> _lastSignalAt = {};

  String get _base => _dio.options.baseUrl;

  Future<Map<String, dynamic>> home() async {
    try {
      final res = await _dio.get<dynamic>('/student/home');
      return _asMap(res.data);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<Map<String, dynamic>> learningPath({
    String? classroomId,
    bool supplementary = false,
  }) async {
    try {
      final res = await _dio.get<dynamic>(
        '/student/learning-path',
        queryParameters: {
          if (classroomId != null && classroomId.isNotEmpty)
            'classroom_id': classroomId,
          'supplementary': supplementary,
        },
      );
      final data = _asMap(res.data);
      // Scoped requests return {units, current, ...} directly.
      if (data.containsKey('units')) return data;
      // Unscoped requests return {paths: [...]} — pick the requested room.
      final paths = (data['paths'] as List? ?? []).cast<Map<String, dynamic>>();
      if (paths.isEmpty) return {'units': [], 'current': null};
      if (classroomId != null && classroomId.isNotEmpty) {
        for (final p in paths) {
          if (p['classroom_id']?.toString() == classroomId) return p;
        }
      }
      return paths.first;
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<SkillBundle> skillBundle({
    required String skillId,
    required String materialId,
    String? classroomId,
    bool supplementary = false,
  }) async {
    try {
      final res = await _dio.get<dynamic>(
        '/student/skills/$skillId',
        queryParameters: {
          'material_id': materialId,
          if (classroomId != null && classroomId.isNotEmpty)
            'classroom_id': classroomId,
          'supplementary': supplementary,
        },
      );
      return SkillBundle.fromJson(_asMap(res.data));
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<SkillHelp> skillHelp({
    required String skillId,
    required String materialId,
    required String kind,
    String? classroomId,
    bool supplementary = false,
  }) async {
    try {
      final res = await _dio.get<dynamic>(
        '/student/skills/$skillId/help',
        queryParameters: {
          'material_id': materialId,
          'kind': kind,
          if (classroomId != null && classroomId.isNotEmpty)
            'classroom_id': classroomId,
          'supplementary': supplementary,
        },
      );
      return SkillHelp.fromJson(_asMap(res.data));
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<AssessmentStart> startAssessment({
    String? classroomId,
    String? materialId,
    String? skillId,
    bool childScope = false,
  }) async {
    try {
      final res = await _dio.post<dynamic>(
        '/student/assessments/start',
        data: {
          'classroom_id': classroomId,
          'material_id': materialId,
          'skill_id': skillId,
          'child_scope': childScope,
        },
      );
      return AssessmentStart.fromJson(_asMap(res.data));
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<AssessmentStart> startQuickCheck({
    String? classroomId,
    String? materialId,
    bool childScope = false,
  }) async {
    try {
      final response = await _dio.post<dynamic>(
        '/student/assessments/start',
        data: {
          'classroom_id': classroomId,
          'material_id': materialId,
          'child_scope': childScope,
          'checkpoint': true,
        },
      );
      return AssessmentStart.fromJson(_asMap(response.data));
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<CheckResult> checkAnswer({
    required String assessmentId,
    required String questionId,
    Object? answer,
  }) async {
    try {
      final res = await _dio.post<dynamic>(
        '/student/assessments/$assessmentId/check',
        data: {'question_id': questionId, 'answer': answer},
      );
      return CheckResult.fromJson(_asMap(res.data));
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<AssessmentResult> submitAssessment({
    required String assessmentId,
    required Map<String, Object?> answers,
  }) async {
    try {
      final res = await _dio.post<dynamic>(
        '/student/assessments/$assessmentId/submit',
        data: {'answers': answers},
      );
      return AssessmentResult.fromJson(_asMap(res.data));
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<Map<String, dynamic>> progress({String? classroomId}) async {
    try {
      final res = await _dio.get<dynamic>(
        '/student/progress',
        queryParameters: {
          if (classroomId != null && classroomId.isNotEmpty)
            'classroom_id': classroomId,
        },
      );
      return _asMap(res.data);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// Fire-and-forget support signal (hint used, retry, ...).
  /// Identical signals within [throttle] of each other are sent once, so a
  /// double-tap or a rebuild storm cannot inflate the learning profile.
  Future<void> supportSignal(
    String signal, {
    Duration throttle = const Duration(seconds: 3),
  }) async {
    final now = DateTime.now();
    final last = _lastSignalAt[signal];
    if (last != null && now.difference(last) < throttle) return;
    _lastSignalAt[signal] = now;
    try {
      await _dio.post<dynamic>(
        '/student/support-signal',
        data: {'signal': signal},
      );
    } on DioException catch (_) {
      // Support signals must never break learning.
    }
  }

  /// Authenticated audio URL (downloaded through Dio by the audio service,
  /// so the normal JWT flow applies — never streamed with ad-hoc headers).
  String skillAudioUrl({
    required String skillId,
    required String materialId,
    String? classroomId,
    bool supplementary = false,
  }) {
    final uri = Uri.parse('$_base/student/skills/$skillId/audio').replace(
      queryParameters: {
        'material_id': materialId,
        if (classroomId != null && classroomId.isNotEmpty)
          'classroom_id': classroomId,
        'supplementary': '$supplementary',
      },
    );
    return uri.toString();
  }

  /// Tiny lip-sync envelope for the same explanation (levels over normalized
  /// time; see AudioService.envelopeFor). Same params/auth as [skillAudioUrl];
  /// missing/unavailable degrades to the local cadence animation.
  String skillEnvelopeUrl({
    required String skillId,
    required String materialId,
    String? classroomId,
    bool supplementary = false,
  }) {
    final uri = Uri.parse('$_base/student/skills/$skillId/audio-envelope').replace(
      queryParameters: {
        'material_id': materialId,
        if (classroomId != null && classroomId.isNotEmpty)
          'classroom_id': classroomId,
        'supplementary': '$supplementary',
      },
    );
    return uri.toString();
  }

  /// Raw WAV bytes for one skill's explanation. Throws [ApiException]
  /// (including 401 session expiry and 503 unavailability) so the audio
  /// service can react; callers degrade to a calm message and the lesson
  /// always continues.
  Future<Uint8List> skillAudioBytes({
    required String skillId,
    required String materialId,
    String? classroomId,
    bool supplementary = false,
  }) async {
    try {
      final res = await _dio.get<List<int>>(
        '/student/skills/$skillId/audio',
        queryParameters: {
          'material_id': materialId,
          if (classroomId != null && classroomId.isNotEmpty)
            'classroom_id': classroomId,
          'supplementary': supplementary,
        },
        options: Options(responseType: ResponseType.bytes),
      );
      final data = res.data;
      if (data == null || data.isEmpty) {
        throw const ApiException('Audio is unavailable right now.');
      }
      return Uint8List.fromList(data);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// Authenticated image URL. Prefer [skillImageBytes] (Dio + JWT flow);
  /// raw URLs must always be fetched with the Authorization header.
  String skillImageUrl({
    required String skillId,
    required String materialId,
    String? classroomId,
    bool supplementary = false,
  }) {
    final uri = Uri.parse('$_base/student/skills/$skillId/image').replace(
      queryParameters: {
        'material_id': materialId,
        if (classroomId != null && classroomId.isNotEmpty)
          'classroom_id': classroomId,
        'supplementary': '$supplementary',
      },
    );
    return uri.toString();
  }

  /// Raw JPEG bytes for one skill's visual. Returns null when the backend
  /// has no image (404) or the service is unavailable (503, network, ...).
  /// Callers treat null as "no visual" and continue the lesson normally.
  Future<Uint8List?> skillImageBytes({
    required String skillId,
    required String materialId,
    String? classroomId,
    bool supplementary = false,
  }) async {
    try {
      final res = await _dio.get<List<int>>(
        '/student/skills/$skillId/image',
        queryParameters: {
          'material_id': materialId,
          if (classroomId != null && classroomId.isNotEmpty)
            'classroom_id': classroomId,
          'supplementary': supplementary,
        },
        options: Options(responseType: ResponseType.bytes),
      );
      final data = res.data;
      if (data == null || data.isEmpty) return null;
      return Uint8List.fromList(data);
    } on DioException catch (_) {
      return null;
    }
  }
}

Map<String, dynamic> _asMap(dynamic data) =>
    Map<String, dynamic>.from(data as Map);

@riverpod
StudentRepository studentRepository(Ref ref) =>
    StudentRepository(ref.watch(apiClientProvider).dio);

/// "What should I do next?" card data for the student home screen.
@riverpod
Future<Map<String, dynamic>> studentHome(Ref ref) =>
    ref.watch(studentRepositoryProvider).home();

/// Ordered units -> skills for one classroom (or supplementary).
@riverpod
Future<Map<String, dynamic>> studentLearningPath(
  Ref ref, {
  String? classroomId,
  bool supplementary = false,
}) => ref
    .watch(studentRepositoryProvider)
    .learningPath(classroomId: classroomId, supplementary: supplementary);

/// One skill lesson bundle (explanation, position, help order).
@riverpod
Future<SkillBundle> studentSkillBundle(
  Ref ref, {
  required String skillId,
  required String materialId,
  String? classroomId,
  bool supplementary = false,
}) => ref
    .watch(studentRepositoryProvider)
    .skillBundle(
      skillId: skillId,
      materialId: materialId,
      classroomId: classroomId,
      supplementary: supplementary,
    );

/// Mastery summary + recent practice per classroom.
@riverpod
Future<Map<String, dynamic>> studentProgress(Ref ref, {String? classroomId}) =>
    ref.watch(studentRepositoryProvider).progress(classroomId: classroomId);

/// Cached visual for one skill. Null means "no visual available" — the
/// lesson renders without an image area. Scoped by skill + material so
/// fast skill switches never show a stale picture.
@riverpod
Future<Uint8List?> skillImage(
  Ref ref, {
  required String skillId,
  required String materialId,
  String? classroomId,
  bool supplementary = false,
}) => ref
    .watch(studentRepositoryProvider)
    .skillImageBytes(
      skillId: skillId,
      materialId: materialId,
      classroomId: classroomId,
      supplementary: supplementary,
    );
