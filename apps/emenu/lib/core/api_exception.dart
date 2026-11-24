import 'package:dio/dio.dart';

/// Error de la API con un mensaje listo para mostrar.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;

  static ApiException from(Object error) {
    if (error is ApiException) return error;
    if (error is DioException) {
      final data = error.response?.data;
      String? message;
      if (data is Map) {
        final raw = data['message'];
        message = raw is List ? raw.join('\n') : raw?.toString();
      }
      if (error.type == DioExceptionType.connectionError || error.type == DioExceptionType.connectionTimeout) {
        message ??= 'No hay conexión con el restaurante';
      }
      return ApiException(message ?? 'Algo salió mal (${error.response?.statusCode ?? 'sin respuesta'})',
          statusCode: error.response?.statusCode);
    }
    return ApiException(error.toString());
  }
}
