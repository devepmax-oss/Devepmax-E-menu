import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../app/config.dart';
import 'api_exception.dart';

/// El aparato vinculado: su token, el servidor del restaurante y qué es (tablet de mesa o
/// pantalla de cocina). La misma app sirve para las dos cosas según el código con que se vincula.
class DeviceSession {
  const DeviceSession({required this.token, required this.apiBaseUrl, required this.deviceId, required this.deviceName, this.type = 'EMENU'});

  final String token;
  final String apiBaseUrl;
  final String deviceId;
  final String deviceName;

  /// EMENU (tablet de mesa) o KDS (pantalla de cocina).
  final String type;

  bool get isKitchen => type == 'KDS';

  Map<String, dynamic> toJson() => {'token': token, 'api': apiBaseUrl, 'id': deviceId, 'name': deviceName, 'type': type};

  factory DeviceSession.fromJson(Map<String, dynamic> j) => DeviceSession(
        token: j['token'] as String,
        apiBaseUrl: j['api'] as String,
        deviceId: j['id'] as String,
        deviceName: j['name'] as String? ?? 'Tablet',
        type: j['type'] as String? ?? 'EMENU',
      );
}

class _Storage {
  static const _key = 'devepmax.emenu.device';
  final _storage = const FlutterSecureStorage();

  Future<DeviceSession?> read() async {
    try {
      final raw = await _storage.read(key: _key);
      return raw == null ? null : DeviceSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      await clear();
      return null;
    }
  }

  Future<void> write(DeviceSession s) => _storage.write(key: _key, value: jsonEncode(s.toJson()));
  Future<void> clear() => _storage.delete(key: _key);
}

/// Qué servidor usar. El QR trae la dirección del restaurante; solo se acepta si es https
/// (en desarrollo se usa la configurada al compilar, por ejemplo 10.0.2.2 en el emulador).
String resolveApiBase(String? fromQr) {
  final candidate = fromQr?.trim();
  if (candidate != null && candidate.startsWith('https://')) return candidate.replaceAll(RegExp(r'/$'), '');
  return AppConfig.apiBaseUrl;
}

/// Datos que vienen en el QR de la app Staff: devepmax://pair?code=123456&api=…
({String code, String? api})? parsePairingQr(String raw) {
  final text = raw.trim();
  if (RegExp(r'^\d{6}$').hasMatch(text)) return (code: text, api: null);
  final uri = Uri.tryParse(text);
  if (uri == null || uri.scheme != 'devepmax' || uri.host != 'pair') return null;
  final code = uri.queryParameters['code'] ?? '';
  if (!RegExp(r'^\d{6}$').hasMatch(code)) return null;
  return (code: code, api: uri.queryParameters['api']);
}

final deviceSessionProvider = AsyncNotifierProvider<DeviceSessionController, DeviceSession?>(DeviceSessionController.new);

class DeviceSessionController extends AsyncNotifier<DeviceSession?> {
  final _storage = _Storage();

  @override
  Future<DeviceSession?> build() => _storage.read();

  /// Canjea el código de 6 dígitos por el token de esta tablet.
  Future<void> pair(String code, {String? api}) async {
    final base = resolveApiBase(api);
    final dio = Dio(BaseOptions(
      baseUrl: base,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
    ));
    final Map<String, dynamic> data;
    try {
      data = (await dio.post<Map<String, dynamic>>('/auth/device/pair', data: {'code': code, 'appVersion': 'emenu-1.0.0'})).data!;
    } catch (error) {
      throw ApiException.from(error);
    }
    final device = data['device'] as Map<String, dynamic>;
    final type = device['type'] as String?;
    if (type != 'EMENU' && type != 'KDS') {
      throw ApiException('Ese código es de una caja o de un mesero. Aquí se vinculan tablets de mesa y pantallas de cocina.');
    }
    final session = DeviceSession(
      token: data['deviceToken'] as String,
      apiBaseUrl: base,
      deviceId: device['id'] as String,
      deviceName: device['name'] as String? ?? 'Tablet',
      type: type!,
    );
    await _storage.write(session);
    state = AsyncData(session);
  }

  /// La tablet deja de estar vinculada (la desvincularon en el panel o lo pidió el personal).
  Future<void> forget() async {
    await _storage.clear();
    state = const AsyncData(null);
  }
}

/// Cliente HTTP con el token de la tablet. Si el servidor dice que la tablet ya no está
/// autorizada, se olvida la vinculación y vuelve la pantalla de vincular.
final dioProvider = Provider<Dio>((ref) {
  final session = ref.watch(deviceSessionProvider).value;
  final dio = Dio(BaseOptions(
    baseUrl: session?.apiBaseUrl ?? AppConfig.apiBaseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 25),
  ));
  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) {
      if (session != null) options.headers['Authorization'] = 'Bearer ${session.token}';
      handler.next(options);
    },
    onError: (error, handler) {
      final revoked = error.response?.statusCode == 401 && session != null && error.requestOptions.extra['pin'] != true;
      if (revoked) {
        try {
          ref.read(deviceSessionProvider.notifier).forget();
        } catch (_) {
          // Este cliente ya fue reemplazado (otra vinculación); no hay nada que olvidar.
        }
      }
      handler.next(error);
    },
  ));
  return dio;
});

/// Hace una petición y convierte los errores en mensajes claros.
Future<T> apiCall<T>(Future<T> Function() request) async {
  try {
    return await request();
  } catch (error) {
    throw ApiException.from(error);
  }
}
