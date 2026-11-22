import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../../app/config.dart';
import '../auth/auth_controller.dart';

/// Estado de la conexión en tiempo real, para mostrarlo en pantalla.
enum RealtimeStatus { connecting, live, reconnecting, offline }

/// Un aviso del servidor: `order.created`, `order.updated`, `ticket.updated`,
/// `bill.updated`, `product.availability`… y `ready` (señal para resincronizar).
class RealtimeEvent {
  const RealtimeEvent(this.name, this.data);
  final String name;
  final Object? data;

  Map<String, dynamic>? get json => data is Map ? Map<String, dynamic>.from(data as Map) : null;
}

final realtimeProvider = NotifierProvider<RealtimeController, RealtimeStatus>(RealtimeController.new);

/// Mantiene un socket abierto mientras haya sesión. Se reconecta solo; si el
/// token vence, lo renueva y vuelve a entrar. Cada (re)conexión emite `ready`.
class RealtimeController extends Notifier<RealtimeStatus> {
  final _events = StreamController<RealtimeEvent>.broadcast();
  io.Socket? _socket;
  String? _token;
  bool _renewing = false;
  DateTime? _lastRenew;

  /// Avisos del servidor. Las pantallas se suscriben y actualizan su lista.
  Stream<RealtimeEvent> get events => _events.stream;

  /// `http://localhost:3000/api/v1` → `http://localhost:3000`
  static String get _origin {
    final uri = Uri.parse(AppConfig.apiBaseUrl);
    return uri.replace(path: '', query: null, fragment: null).toString().replaceAll(RegExp(r'/$'), '');
  }

  @override
  RealtimeStatus build() {
    ref.listen(authControllerProvider, (_, next) => _sync(next.value?.accessToken));
    ref.onDispose(() {
      _close();
      _events.close();
    });
    final token = ref.read(authControllerProvider).value?.accessToken;
    Future.microtask(() => _sync(token));
    return token == null ? RealtimeStatus.offline : RealtimeStatus.connecting;
  }

  void _sync(String? token) {
    if (token == null) {
      _close();
      _token = null;
      state = RealtimeStatus.offline;
      return;
    }
    if (token == _token && _socket != null) return;
    _token = token;
    // Token nuevo (login o renovación): se abre un socket limpio con él.
    _close();
    _open(token);
  }

  void _open(String token) {
    final socket = io.io(
      _origin,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setPath('/socket.io')
          .setAuth({'token': token})
          .enableReconnection()
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(8000)
          .disableAutoConnect()
          .enableForceNew()
          .build(),
    );
    _socket = socket;

    socket.onConnect((_) => state = RealtimeStatus.live);
    socket.onDisconnect((reason) {
      state = RealtimeStatus.reconnecting;
      // Si el servidor cerró la sesión (token vencido, permisos cambiados), se renueva y se vuelve a entrar.
      if (reason == 'io server disconnect') _renewAndReconnect();
    });
    socket.onConnectError((error) {
      state = RealtimeStatus.reconnecting;
      if ('$error'.contains('Token') || '$error'.contains('Autenticación')) _renewAndReconnect();
    });
    socket.on('session.expired', (_) => _renewAndReconnect());
    socket.onAny((event, data) {
      if (!_events.isClosed) _events.add(RealtimeEvent(event, data));
    });
    socket.connect();
  }

  Future<void> _renewAndReconnect() async {
    // Una renovación a la vez, y no más de una cada 30 s (evita bucles si el servidor falla).
    final last = _lastRenew;
    if (_renewing) return;
    if (last != null && DateTime.now().difference(last) < const Duration(seconds: 30)) {
      final socket = _socket;
      if (socket != null && socket.disconnected) socket.connect();
      return;
    }
    _renewing = true;
    _lastRenew = DateTime.now();
    try {
      // Al renovar, el listener de la sesión abre un socket nuevo con el token nuevo.
      // Si la sesión terminó, el router vuelve al login.
      await ref.read(authControllerProvider.notifier).refresh();
    } finally {
      _renewing = false;
    }
  }

  void _close() {
    _socket?.dispose();
    _socket = null;
  }
}
