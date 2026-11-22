import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/config.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import 'delivery_models.dart';

final deliveriesApiProvider = Provider<DeliveriesApi>((ref) => DeliveriesApi(ref.watch(dioProvider)));

/// Marca pública del restaurante (no necesita sesión).
final brandProvider = FutureProvider<Json?>((ref) async {
  try {
    final dio = Dio(BaseOptions(baseUrl: AppConfig.apiBaseUrl, connectTimeout: const Duration(seconds: 8)));
    return (await dio.get<Map<String, dynamic>>('/settings/public')).data;
  } catch (_) {
    return null;
  }
});

class DeliveriesApi {
  DeliveriesApi(this._dio);
  final Dio _dio;

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } catch (error) {
      throw ApiException.from(error);
    }
  }

  Future<DriverMe> me() => _call(() async => DriverMe.fromJson((await _dio.get<Json>('/delivery/me')).data!));

  Future<DriverMe> updateMe(Json data) =>
      _call(() async => DriverMe.fromJson((await _dio.patch<Json>('/delivery/me', data: data)).data!));

  Future<List<Delivery>> deliveries() => _call(() async {
        final response = await _dio.get<List<dynamic>>('/delivery/me/deliveries');
        return response.data!.map((d) => Delivery.fromJson(d as Json)).toList();
      });

  Future<Delivery> _action(String id, String action) =>
      _call(() async => Delivery.fromJson((await _dio.post<Json>('/delivery/assignments/$id/$action')).data!));

  Future<Delivery> accept(String id) => _action(id, 'accept');
  Future<Delivery> pickedUp(String id) => _action(id, 'picked-up');
  Future<Delivery> delivered(String id) => _action(id, 'delivered');
  Future<void> decline(String id) => _call(() => _dio.post<Json>('/delivery/assignments/$id/decline'));

  Future<void> sendLocation(double lat, double lng) =>
      _call(() => _dio.post<Json>('/delivery/me/location', data: {'lat': lat, 'lng': lng}));
}
