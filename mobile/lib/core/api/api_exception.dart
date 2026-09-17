import 'package:dio/dio.dart';

/// Friendly, user-facing API error. Never exposes raw stack traces.
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  static ApiException fromDio(Object error) {
    if (error is DioException) {
      final code = error.response?.statusCode;
      final data = error.response?.data;
      String? detail;
      if (data is Map<String, dynamic>) {
        final d = data['detail'] ?? data['message'] ?? data['error'];
        if (d is String && d.isNotEmpty) detail = d;
      }
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return const ApiException(
            'The connection timed out. Check your internet and try again.',
          );
        case DioExceptionType.connectionError:
          return const ApiException(
            'Could not reach Sahlha. Check your connection and try again.',
          );
        case DioExceptionType.badResponse:
          if (code == 401) {
            return ApiException(
              detail ?? 'Your session expired. Please sign in again.',
              statusCode: 401,
            );
          }
          if (code == 403) {
            return ApiException(
              detail ?? 'You are not allowed to do that.',
              statusCode: 403,
            );
          }
          if (code == 404) {
            return ApiException(
              detail ?? 'This was not found.',
              statusCode: 404,
            );
          }
          if (code == 422) {
            return ApiException(
              detail ?? 'Some details need attention. Check and try again.',
              statusCode: 422,
            );
          }
          if (code == 503) {
            return ApiException(
              detail ?? 'This is unavailable right now. Try again later.',
              statusCode: 503,
            );
          }
          return ApiException(
            detail ?? 'Something went wrong. Please try again.',
            statusCode: code,
          );
        default:
          return ApiException(
            detail ?? 'Something went wrong. Please try again.',
            statusCode: code,
          );
      }
    }
    return const ApiException('Something went wrong. Please try again.');
  }

  @override
  String toString() => message;
}
