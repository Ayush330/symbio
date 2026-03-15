import 'dart:ui';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DioClient {
  final Dio dio;
  VoidCallback? onUnauthorized;
  String? _authToken;

  DioClient({required String baseUrl, this.onUnauthorized})
      : dio = Dio(
          BaseOptions(
            baseUrl: baseUrl,
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 10),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
          ),
        ) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // Use cached token if available, otherwise load from prefs
          if (_authToken == null) {
            final prefs = await SharedPreferences.getInstance();
            _authToken = prefs.getString('jwt_token');
          }
          
          if (_authToken != null) {
            options.headers['Authorization'] = 'Bearer $_authToken';
          }
          return handler.next(options);
        },
        onError: (DioException e, handler) {
          // Extract error message from structured JSON if available
          String? errorMessage;
          if (e.response?.data is Map) {
            errorMessage = e.response?.data['error'];
          }

          // Handle global errors like 401 Unauthorized
          if (e.response?.statusCode == 401) {
            if (onUnauthorized != null) {
              onUnauthorized!();
            }
          }

          // Create a more descriptive exception if we have an error message from backend
          if (errorMessage != null) {
            return handler.next(DioException(
              requestOptions: e.requestOptions,
              response: e.response,
              type: e.type,
              error: errorMessage,
              message: errorMessage,
            ));
          }

          return handler.next(e);
        },
      ),
    );
  }

  /// Update the cached token (e.g., after login/logout)
  void setToken(String? token) {
    _authToken = token;
  }

  Future<Response> get(String path, {Map<String, dynamic>? queryParameters}) {
    return dio.get(path, queryParameters: queryParameters);
  }

  Future<Response> post(String path, {dynamic data}) {
    return dio.post(path, data: data);
  }
}
