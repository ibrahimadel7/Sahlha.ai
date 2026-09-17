import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../domain/app_user.dart';

part 'auth_repository.g.dart';

/// Email/password authentication against the FastAPI backend.
class AuthRepository {
  AuthRepository(this._dio);

  final Dio _dio;

  Future<AuthResult> login({
    required String email,
    required String password,
  }) async {
    try {
      final res = await _dio.post<dynamic>(
        '/auth/login',
        data: {'email': email, 'password': password},
      );
      return AuthResult.fromJson(_asMap(res.data));
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<AuthResult> register({
    required String name,
    required String email,
    required String password,
    required String role,
  }) async {
    try {
      final res = await _dio.post<dynamic>(
        '/auth/register',
        data: {
          'name': name,
          'email': email,
          'password': password,
          'role': role,
        },
      );
      return AuthResult.fromJson(_asMap(res.data));
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<AppUser> me() async {
    try {
      final res = await _dio.get<dynamic>('/auth/me');
      return AppUser.fromJson(_asMap(res.data));
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<AppUser> updateName(String name) async {
    try {
      final res = await _dio.patch<dynamic>('/auth/me', data: {'name': name});
      return AppUser.fromJson(_asMap(res.data));
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

/// Token + user pair returned by login/register.
class AuthResult {
  const AuthResult({required this.token, required this.user});

  final String token;
  final AppUser user;

  factory AuthResult.fromJson(Map<String, dynamic> json) => AuthResult(
    token: json['token'] as String? ?? '',
    user: AppUser.fromJson(_asMap(json['user'])),
  );
}

Map<String, dynamic> _asMap(dynamic data) =>
    Map<String, dynamic>.from(data as Map);

@riverpod
AuthRepository authRepository(Ref ref) =>
    AuthRepository(ref.watch(apiClientProvider).dio);
