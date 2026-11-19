import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'driver_api_service.dart';

class DriverLocationService {
  DriverLocationService._();

  static final DriverLocationService instance = DriverLocationService._();

  Timer? _timer;
  bool _running = false;

  bool get isRunning => _running;

  Future<void> start({
    required String driverId,
    Duration interval = const Duration(seconds: 8),
    void Function(double lat, double lng)? onLocationUploaded,
  }) async {
    if (_running) return;

    final allowed = await _ensurePermission();

    if (!allowed) {
      debugPrint('Driver GPS permission denied');
      return;
    }

    _running = true;

    await _sendLocation(
      driverId: driverId,
      onLocationUploaded: onLocationUploaded,
    );

    _timer = Timer.periodic(interval, (_) async {
      await _sendLocation(
        driverId: driverId,
        onLocationUploaded: onLocationUploaded,
      );
    });
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _running = false;
  }

  Future<void> sendNow({
    required String driverId,
    void Function(double lat, double lng)? onLocationUploaded,
  }) async {
    final allowed = await _ensurePermission();

    if (!allowed) {
      debugPrint('Driver GPS permission denied');
      throw Exception(
        'Permiso de ubicación no disponible o GPS apagado',
      );
    }

    await _sendLocation(
      driverId: driverId,
      onLocationUploaded: onLocationUploaded,
    );
  }

  Future<void> _sendLocation({
    required String driverId,
    void Function(double lat, double lng)? onLocationUploaded,
  }) async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      await DriverApiService.instance.updateLocation(
        driverId: driverId,
        lat: position.latitude,
        lng: position.longitude,
      );

      onLocationUploaded?.call(
        position.latitude,
        position.longitude,
      );

      debugPrint(
        'Driver location uploaded => '
        '${position.latitude}, ${position.longitude}',
      );
    } catch (error, stackTrace) {
      debugPrint('==============================');
      debugPrint('GPS ERROR');
      debugPrint(error.toString());
      debugPrint(stackTrace.toString());
      debugPrint('==============================');
      rethrow;
    }
  }

  Future<bool> _ensurePermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      debugPrint('GPS deshabilitado');
      return false;
    }

    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      debugPrint('Permiso GPS denegado para siempre');
      return false;
    }

    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }
}
