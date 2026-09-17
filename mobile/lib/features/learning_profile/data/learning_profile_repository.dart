import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../domain/learning_profile.dart';

part 'learning_profile_repository.g.dart';

/// Student learning profile (support preferences + parent link code).
class LearningProfileRepository {
  LearningProfileRepository(this._dio);

  final Dio _dio;

  Future<LearningProfile> get() async {
    try {
      final res = await _dio.get<dynamic>('/student/profile');
      return LearningProfile.fromJson(_asMap(res.data));
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<LearningProfile> submit(Map<String, String> answers) async {
    try {
      final res = await _dio.post<dynamic>(
        '/student/profile',
        data: {'answers': answers},
      );
      return LearningProfile.fromJson(_asMap(res.data));
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

Map<String, dynamic> _asMap(dynamic data) =>
    Map<String, dynamic>.from(data as Map);

@riverpod
LearningProfileRepository learningProfileRepository(Ref ref) =>
    LearningProfileRepository(ref.watch(apiClientProvider).dio);

@riverpod
Future<LearningProfile> learningProfile(Ref ref) =>
    ref.watch(learningProfileRepositoryProvider).get();
