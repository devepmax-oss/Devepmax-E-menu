import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/config.dart';
import '../auth/auth_controller.dart';

/// Cliente HTTP autenticado. Renueva el token una vez ante un 401 y reintenta.
final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(
    baseUrl: AppConfig.apiBaseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30),
  ));

  dio.interceptors.add(QueuedInterceptorsWrapper(
    onRequest: (options, handler) {
      final token = ref.read(authControllerProvider).value?.accessToken;
      if (token != null) options.headers['Authorization'] = 'Bearer $token';
      handler.next(options);
    },
    onError: (error, handler) async {
      final options = error.requestOptions;
      if (error.response?.statusCode != 401 || options.extra['retried'] == true) {
        return handler.next(error);
      }

      // Si otra petición ya renovó el token mientras esta esperaba, se usa ese.
      final current = ref.read(authControllerProvider).value?.accessToken;
      final used = (options.headers['Authorization'] as String?)?.replaceFirst('Bearer ', '');
      final token = (current != null && current != used)
          ? current
          : await ref.read(authControllerProvider.notifier).refresh();
      if (token == null) return handler.next(error);

      options.headers['Authorization'] = 'Bearer $token';
      options.extra['retried'] = true;
      try {
        handler.resolve(await dio.fetch(options));
      } on DioException catch (retryError) {
        handler.next(retryError);
      }
    },
  ));
  return dio;
});
