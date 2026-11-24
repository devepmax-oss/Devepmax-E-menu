import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import 'device_session.dart';

enum RealtimeStatus { connecting, live, reconnecting, offline }

class RealtimeEvent {
  const RealtimeEvent(this.name, this.data);
  final String name;
  final Object? data;

  Map<String, dynamic>? get json => data is Map ? Map<String, dynamic>.from(data as Map) : null;
}

final realtimeProvider = NotifierProvider<RealtimeController, RealtimeStatus>(RealtimeController.new);

/// Socket de la tablet: recibe su mesa (pedidos, cuenta, llamados) y la disponibilidad del menú.
/// Cada (re)conexión emite `ready` para volver a cargar todo.
class RealtimeController extends Notifier<RealtimeStatus> {
  final _events = StreamController<RealtimeEvent>.broadcast();
  io.Socket? _socket;
  String? _key;

  Stream<RealtimeEvent> get events => _events.stream;

  @override
  RealtimeStatus build() {
    ref.listen(deviceSessionProvider, (_, next) => _sync(next.value));
    ref.onDispose(() {
      _close();
      _events.close();
    });
    final session = ref.read(deviceSessionProvider).value;
    Future.microtask(() => _sync(session));
    return session == null ? RealtimeStatus.offline : RealtimeStatus.connecting;
  }

  void _sync(DeviceSession? session) {
    if (session == null) {
      _close();
      _key = null;
      state = RealtimeStatus.offline;
      return;
    }
    final key = '${session.apiBaseUrl}|${session.token}';
    if (key == _key && _socket != null) return;
    _key = key;
    _close();
    _open(session);
  }

  void _open(DeviceSession session) {
    final api = Uri.parse(session.apiBaseUrl);
    final origin = api.replace(path: '', query: null, fragment: null).toString().replaceAll(RegExp(r'/$'), '');
    final socket = io.io(
      origin,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setPath('/socket.io')
          .setAuth({'token': session.token})
          .enableReconnection()
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(10000)
          .disableAutoConnect()
          .enableForceNew()
          .build(),
    );
    _socket = socket;
    socket.onConnect((_) => state = RealtimeStatus.live);
    socket.onDisconnect((reason) {
      state = RealtimeStatus.reconnecting;
      // El servidor cierra el socket cuando cambian la mesa de la tablet: vuelve a entrar.
      if (reason == 'io server disconnect') Future.delayed(const Duration(seconds: 1), () => _socket?.connect());
    });
    socket.onConnectError((_) => state = RealtimeStatus.reconnecting);
    socket.onAny((event, data) {
      if (!_events.isClosed) _events.add(RealtimeEvent(event, data));
    });
    socket.connect();
  }

  void _close() {
    _socket?.dispose();
    _socket = null;
  }
}
