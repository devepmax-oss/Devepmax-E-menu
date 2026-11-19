import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/config/app_config.dart';
import '../models/driver_models.dart';

class DriverApiService {
  DriverApiService._();

  static final DriverApiService instance = DriverApiService._();

  Uri _uri(String path) => Uri.parse('${AppConfig.apiBaseUrl}$path');

  Map<String, String> get _headers => const {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'User-Agent': 'Mozilla/5.0 Flutter Driver App',
      };

  Future<void> registerNotificationToken({
    required String token,
    required String driverId,
    required String deviceId,
  }) async {
    final response = await http.post(
      _uri('/notifications/register-token'),
      headers: _headers,
      body: jsonEncode({
        'token': token,
        'platform': Platform.isAndroid ? 'android' : 'ios',
        'deviceId': deviceId,
        'tokenType': 'driver',
        'driverId': driverId,
      }),
    );

    _ensureOk(response, 'No se pudo registrar el dispositivo para notificaciones');
  }

  Future<List<DriverProfile>> listDrivers() async {
    final response = await http.get(_uri('/drivers'), headers: _headers);
    _ensureOk(response, 'No se pudieron cargar los drivers');

    final data = jsonDecode(response.body);
    final raw = data is Map ? data['drivers'] : data;

    if (raw is! List) return [];

    return raw
        .whereType<Map>()
        .map((e) => DriverProfile.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<DriverProfile> createDriver({
    required String name,
    required String phone,
    String? email,
  }) async {
    final response = await http.post(
      _uri('/drivers'),
      headers: _headers,
      body: jsonEncode({
        'name': name,
        'phone': phone,
        if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
      }),
    );

    _ensureOk(response, 'No se pudo crear el driver');
    final data = jsonDecode(response.body);
    return DriverProfile.fromJson(_extractObject(data, 'driver'));
  }

  Future<DriverProfile> updateProfile({
    required String driverId,
    required String name,
    required String phone,
    String? email,
    String? vehicleType,
    String? vehiclePlate,
    String? vehicleColor,
  }) async {
    final response = await http.patch(
      _uri('/drivers/$driverId'),
      headers: _headers,
      body: jsonEncode({
        'name': name.trim(),
        'phone': phone.trim(),
        'email': email?.trim(),
        'vehicleType': vehicleType?.trim(),
        'vehiclePlate': vehiclePlate?.trim(),
        'vehicleColor': vehicleColor?.trim(),
      }),
    );

    _ensureOk(response, 'No se pudo actualizar el perfil');
    final data = jsonDecode(response.body);
    return DriverProfile.fromJson(_extractObject(data, 'driver'));
  }

  Future<DriverProfile> uploadProfilePhoto({
    required String driverId,
    required File imageFile,
  }) async {
    final request = http.MultipartRequest(
      'PATCH',
      _uri('/drivers/$driverId/photo'),
    );

    request.headers.addAll({
      'Accept': 'application/json',
      'User-Agent': 'Mozilla/5.0 Flutter Driver App',
    });

    request.files.add(
      await http.MultipartFile.fromPath('photo', imageFile.path),
    );

    debugPrint('DRIVER API PATCH ${request.url}');

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);

    _ensureOk(response, 'No se pudo actualizar la foto');

    final data = jsonDecode(response.body);
    return DriverProfile.fromJson(_extractObject(data, 'driver'));
  }

  Future<DriverProfile> updateStatus({
    required String driverId,
    required String status,
  }) async {
    final response = await http.patch(
      _uri('/drivers/$driverId/status'),
      headers: _headers,
      body: jsonEncode({'status': status}),
    );

    _ensureOk(response, 'No se pudo actualizar el estado');
    final data = jsonDecode(response.body);
    return DriverProfile.fromJson(_extractObject(data, 'driver'));
  }

  Future<void> updateLocation({
    required String driverId,
    required double lat,
    required double lng,
  }) async {
    final response = await http.patch(
      _uri('/drivers/$driverId/location'),
      headers: _headers,
      body: jsonEncode({'lat': lat, 'lng': lng}),
    );

    _ensureOk(response, 'No se pudo actualizar ubicación');
  }

  Future<List<DriverOrder>> listAvailableOrders() async {
    final response = await http.get(
      _uri('/drivers/orders/available'),
      headers: _headers,
    );

    _ensureOk(response, 'No se pudieron cargar órdenes disponibles');
    final data = jsonDecode(response.body);
    final raw =
        data is Map ? (data['orders'] ?? data['availableOrders']) : data;

    if (raw is! List) return [];

    return raw
        .whereType<Map>()
        .map((e) => DriverOrder.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<DriverAssignment>> listDriverAssignments(String driverId) async {
    final active = await getActiveAssignment(driverId);
    return active == null ? [] : [active];
  }

  Future<DriverAssignment?> getActiveAssignment(String driverId) async {
    final response = await http.get(
      _uri('/drivers/$driverId/assignments/active'),
      headers: _headers,
    );

    _ensureOk(response, 'No se pudo cargar la asignación activa');

    final data = jsonDecode(response.body);
    if (data is Map && data['assignment'] == null) {
      return null;
    }

    return DriverAssignment.fromJson(_extractObject(data, 'assignment'));
  }

  Future<DriverAssignment> assignOrder({
    required String orderId,
    required String driverId,
  }) async {
    final response = await http.post(
      _uri('/drivers/assign'),
      headers: _headers,
      body: jsonEncode({'orderId': orderId, 'driverId': driverId}),
    );

    _ensureOk(response, 'No se pudo asignar la orden');
    final data = jsonDecode(response.body);
    return DriverAssignment.fromJson(_extractObject(data, 'assignment'));
  }

  Future<DriverAssignment> acceptAssignment(String assignmentId) async {
    final response = await http.post(
      _uri('/drivers/assignments/$assignmentId/accept'),
      headers: _headers,
    );

    _ensureOk(response, 'No se pudo aceptar la orden');
    final data = jsonDecode(response.body);
    return DriverAssignment.fromJson(_extractObject(data, 'assignment'));
  }

  Future<DriverAssignment> pickupAssignment(String assignmentId) async {
    final response = await http.post(
      _uri('/drivers/assignments/$assignmentId/pickup'),
      headers: _headers,
    );

    _ensureOk(response, 'No se pudo marcar como recogida');
    final data = jsonDecode(response.body);
    return DriverAssignment.fromJson(_extractObject(data, 'assignment'));
  }

  Future<DriverAssignment> deliverAssignment(String assignmentId) async {
    final response = await http.post(
      _uri('/drivers/assignments/$assignmentId/delivered'),
      headers: _headers,
    );

    _ensureOk(response, 'No se pudo marcar como entregada');
    final data = jsonDecode(response.body);
    return DriverAssignment.fromJson(_extractObject(data, 'assignment'));
  }

  void _ensureOk(http.Response response, String fallback) {
    debugPrint(
        'DRIVER API ${response.request?.method} ${response.request?.url}');
    debugPrint('DRIVER API RESPONSE ${response.statusCode}: ${response.body}');

    if (response.statusCode >= 200 && response.statusCode < 300) return;

    try {
      final data = jsonDecode(response.body);
      if (data is Map && data['error'] != null) {
        throw Exception('${data['error']}');
      }
    } catch (_) {}

    throw Exception('$fallback (${response.statusCode})');
  }

  Map<String, dynamic> _extractObject(dynamic data, String key) {
    if (data is Map && data[key] is Map) {
      return Map<String, dynamic>.from(data[key] as Map);
    }
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
  }
}
