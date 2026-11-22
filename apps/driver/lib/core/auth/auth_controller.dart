import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/config.dart';
import '../api/api_exception.dart';
import 'session.dart';
import 'session_storage.dart';

final sessionStorageProvider = Provider<SessionStorage>((ref) => SessionStorage());

final authControllerProvider =
    AsyncNotifierProvider<AuthController, Session?>(AuthController.new);

/// Sesión del empleado: login, renovación automática del token y logout.
class AuthController extends AsyncNotifier<Session?> {
  // Cliente sin interceptores para no entrar en bucles al renovar.
  final Dio _plain = Dio(BaseOptions(
    baseUrl: AppConfig.apiBaseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 20),
  ));

  SessionStorage get _storage => ref.read(sessionStorageProvider);

  @override
  Future<Session?> build() => _storage.read();

  Future<void> login(String email, String password) async {
    try {
      final response = await _plain.post<Map<String, dynamic>>(
        '/auth/login',
        data: {'email': email.trim(), 'password': password},
      );
      final session = Session.fromJson(response.data!);
      await _storage.write(session);
      state = AsyncData(session);
    } catch (error) {
      throw ApiException.from(error);
    }
  }

  /// Devuelve un access token nuevo, o null si la sesión ya no es válida.
  Future<String?> refresh() async {
    final current = state.value;
    if (current == null) return null;
    try {
      final response = await _plain.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refreshToken': current.refreshToken},
      );
      final session = Session.fromJson(response.data!);
      await _storage.write(session);
      state = AsyncData(session);
      return session.accessToken;
    } catch (_) {
      await _clear();
      return null;
    }
  }

  Future<void> logout() async {
    final current = state.value;
    if (current != null) {
      try {
        await _plain.post<void>('/auth/logout', data: {'refreshToken': current.refreshToken});
      } catch (_) {
        // Aunque falle la red, se cierra la sesión localmente.
      }
    }
    await _clear();
  }

  Future<void> _clear() async {
    await _storage.clear();
    state = const AsyncData(null);
  }
}
