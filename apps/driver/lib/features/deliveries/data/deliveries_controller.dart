import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/realtime/realtime.dart';
import 'deliveries_api.dart';
import 'delivery_models.dart';

/// Perfil del repartidor (disponible / desconectado, vehículo).
final driverMeProvider = AsyncNotifierProvider<DriverMeController, DriverMe>(DriverMeController.new);

class DriverMeController extends AsyncNotifier<DriverMe> {
  @override
  Future<DriverMe> build() => ref.read(deliveriesApiProvider).me();

  Future<void> save(Map<String, dynamic> data) async {
    state = AsyncData(await ref.read(deliveriesApiProvider).updateMe(data));
  }
}

/// Entregas en curso, al día en tiempo real. Suena cuando llega una nueva.
final deliveriesProvider = AsyncNotifierProvider<DeliveriesController, List<Delivery>>(DeliveriesController.new);

class DeliveriesController extends AsyncNotifier<List<Delivery>> {
  final Map<String, Delivery> _byId = {};
  final AudioPlayer _player = AudioPlayer();

  @override
  Future<List<Delivery>> build() async {
    final sub = ref.read(realtimeProvider.notifier).events.listen(_onEvent);
    ref.onDispose(() {
      sub.cancel();
      _player.dispose();
    });
    await _reload();
    return _snapshot();
  }

  Future<void> _reload() async {
    final list = await ref.read(deliveriesApiProvider).deliveries();
    _byId
      ..clear()
      ..addEntries(list.map((d) => MapEntry(d.assignmentId, d)));
  }

  List<Delivery> _snapshot() => _byId.values.toList()
    ..sort((a, b) => a.sortRank != b.sortRank ? a.sortRank.compareTo(b.sortRank) : a.number.compareTo(b.number));

  void _onEvent(RealtimeEvent event) {
    switch (event.name) {
      case 'ready':
        unawaited(refresh());
      case 'delivery.updated':
        final json = event.json?['delivery'];
        if (json is Map) apply(Delivery.fromJson(Map<String, dynamic>.from(json)), fromServer: true);
      case 'delivery.removed':
        final id = event.json?['assignmentId'];
        if (id is String && _byId.remove(id) != null) state = AsyncData(_snapshot());
    }
  }

  /// Aplica una versión de la entrega (del socket o de una acción propia).
  void apply(Delivery d, {bool fromServer = false}) {
    final current = _byId[d.assignmentId];
    if (current != null && d.updatedAt.isBefore(current.updatedAt)) return;
    if (!d.active) {
      _byId.remove(d.assignmentId);
    } else {
      if (current == null && fromServer && d.status == 'PENDING') unawaited(_alert());
      _byId[d.assignmentId] = d;
    }
    state = AsyncData(_snapshot());
  }

  Future<void> refresh() async {
    try {
      await _reload();
      state = AsyncData(_snapshot());
    } catch (error, stack) {
      if (!state.hasValue) state = AsyncError(error, stack);
    }
  }

  Future<void> _alert() async {
    HapticFeedback.heavyImpact();
    try {
      await _player.play(AssetSource('sounds/alert.mp3'));
    } catch (_) {
      // El navegador puede bloquear el sonido hasta que se toque la pantalla.
    }
  }
}

/// Compartir ubicación: solo mientras hay un pedido en camino.
enum LocationState { off, sharing, denied, disabled }

final locationSharingProvider = NotifierProvider<LocationSharing, LocationState>(LocationSharing.new);

class LocationSharing extends Notifier<LocationState> {
  StreamSubscription<Position>? _sub;
  Timer? _timer;
  Position? _last;
  bool _starting = false;

  @override
  LocationState build() {
    ref.listen(deliveriesProvider, (_, next) => _sync(next.value ?? const []));
    ref.onDispose(_stop);
    Future.microtask(() => _sync(ref.read(deliveriesProvider).value ?? const []));
    return LocationState.off;
  }

  void _sync(List<Delivery> list) {
    if (list.any((d) => d.status == 'PICKED_UP')) {
      unawaited(_start());
    } else {
      _stop();
      state = LocationState.off;
    }
  }

  /// Volver a intentar (después de que el repartidor active el GPS o dé el permiso).
  Future<void> retry() async {
    _stop();
    _sync(ref.read(deliveriesProvider).value ?? const []);
  }

  Future<void> _start() async {
    if (_sub != null || _starting) return;
    _starting = true;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        state = LocationState.disabled;
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        state = LocationState.denied;
        return;
      }
      _sub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 15),
      ).listen((p) {
        _last = p;
        _send();
      }, onError: (_) => state = LocationState.denied);
      // Aunque no se mueva (semáforo), se reporta cada 15 s para que el cliente vea que sigue en línea.
      _timer = Timer.periodic(const Duration(seconds: 15), (_) => _send());
      state = LocationState.sharing;
    } finally {
      _starting = false;
    }
  }

  void _send() {
    final p = _last;
    if (p == null) return;
    unawaited(ref.read(deliveriesApiProvider).sendLocation(p.latitude, p.longitude).catchError((_) {}));
  }

  void _stop() {
    _sub?.cancel();
    _sub = null;
    _timer?.cancel();
    _timer = null;
    _last = null;
  }
}
