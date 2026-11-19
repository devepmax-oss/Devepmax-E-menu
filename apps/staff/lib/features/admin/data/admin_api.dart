import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../menu/data/menu_models.dart' show Station;
import 'admin_models.dart';

final adminApiProvider = Provider<AdminApi>((ref) => AdminApi(ref.watch(dioProvider)));

final employeesProvider = FutureProvider<List<EmployeeView>>((ref) => ref.watch(adminApiProvider).employees());
final rolesProvider = FutureProvider<List<Role>>((ref) => ref.watch(adminApiProvider).roles());
final devicesProvider = FutureProvider<List<DeviceView>>((ref) => ref.watch(adminApiProvider).devices());
final stationsProvider = FutureProvider<List<Station>>((ref) => ref.watch(adminApiProvider).stations());

/// Ajustes completos (settings.manage) + horarios.
final settingsProvider = FutureProvider<(Json, List<OpeningHour>)>((ref) async {
  final api = ref.watch(adminApiProvider);
  final results = await Future.wait([api.settings(), api.publicSettings()]);
  final hours = ((results[1]['openingHours'] as List?) ?? const [])
      .map((h) => OpeningHour.fromJson(h as Json))
      .toList();
  return (results[0], hours);
});

class AdminApi {
  AdminApi(this._dio);
  final Dio _dio;

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } catch (error) {
      throw ApiException.from(error);
    }
  }

  Future<List<Json>> _list(String path) => _call(() async {
        final response = await _dio.get<List<dynamic>>(path);
        return response.data!.cast<Json>();
      });

  // Empleados y roles
  Future<List<EmployeeView>> employees() async => (await _list('/employees')).map(EmployeeView.fromJson).toList();
  Future<List<Role>> roles() async => (await _list('/roles')).map(Role.fromJson).toList();
  /// Devuelven el empleado; `generatedPin` viene solo si se generó un PIN (se muestra una única vez).
  Future<Json> createEmployee(Json data) =>
      _call(() async => (await _dio.post<Json>('/employees', data: data)).data!);
  Future<Json> updateEmployee(String id, Json data) =>
      _call(() async => (await _dio.patch<Json>('/employees/$id', data: data)).data!);

  // Dispositivos
  Future<List<DeviceView>> devices() async => (await _list('/devices')).map(DeviceView.fromJson).toList();
  Future<List<Station>> stations() async => (await _list('/menu/stations')).map(Station.fromJson).toList();
  Future<DeviceView> createDevice(Json data) => _call(() async {
        final response = await _dio.post<Json>('/devices', data: data);
        return DeviceView.fromJson(response.data!);
      });
  Future<void> updateDevice(String id, Json data) => _call(() => _dio.patch('/devices/$id', data: data));
  Future<DeviceView> newPairingCode(String id) => _call(() async {
        final response = await _dio.post<Json>('/devices/$id/pairing-code');
        return DeviceView.fromJson(response.data!);
      });
  Future<void> revokeDevice(String id) => _call(() => _dio.post('/devices/$id/revoke'));

  // Ajustes
  Future<Json> settings() => _call(() async => (await _dio.get<Json>('/settings')).data!);
  Future<Json> publicSettings() => _call(() async => (await _dio.get<Json>('/settings/public')).data!);
  Future<void> updateSettings(Json data) => _call(() => _dio.patch('/settings', data: data));
  Future<void> replaceOpeningHours(List<OpeningHour> hours) =>
      _call(() => _dio.put('/settings/opening-hours', data: {'hours': hours.map((h) => h.toJson()).toList()}));
  Future<void> uploadLogo(Uint8List bytes, String filename) => _call(() {
        final ext = filename.split('.').last.toLowerCase();
        final mime = ext == 'png' ? 'image/png' : (ext == 'webp' ? 'image/webp' : 'image/jpeg');
        return _dio.post('/settings/logo',
            data: FormData.fromMap({
              'file': MultipartFile.fromBytes(bytes, filename: filename, contentType: DioMediaType.parse(mime)),
            }));
      });
  Future<void> removeLogo() => _call(() => _dio.delete('/settings/logo'));
}

/// Marca y datos públicos del restaurante (colores del tema, nombre, logo).
final publicSettingsProvider =
    FutureProvider<Json>((ref) => ref.watch(adminApiProvider).publicSettings());
