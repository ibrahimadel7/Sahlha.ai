import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'api_config.dart';

part 'api_client.g.dart';

/// Single Dio instance for the app. Widgets must never touch Dio directly —
/// they go through repositories + Riverpod providers.
class ApiClient {
  ApiClient() {
    _dio = Dio(
      BaseOptions(
        baseUrl: kApiBaseUrl,
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 60),
        sendTimeout: const Duration(seconds: 120),
        headers: {'Content-Type': 'application/json'},
      ),
    );
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final token = _token;
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) {
          if (error.response?.statusCode == 401 && _token != null) {
            onUnauthorized?.call();
          }
          handler.next(error);
        },
      ),
    );
  }

  late final Dio _dio;
  String? _token;

  /// Called on HTTP 401 while a token is set (expired/invalid session).
  void Function()? onUnauthorized;

  Dio get dio => _dio;
  String? get token => _token;
  String get baseUrl => kApiBaseUrl;

  void setToken(String token) => _token = token;
  void clearToken() => _token = null;
}

// Keep the session token and unauthorized callback across screen transitions.
@Riverpod(keepAlive: true)
ApiClient apiClient(Ref ref) => ApiClient();
