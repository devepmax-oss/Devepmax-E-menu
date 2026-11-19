import 'package:flutter/foundation.dart';
import 'package:gopicadera/core/config/app_config.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

class SocketService {
  SocketService._();

  static final SocketService instance = SocketService._();

  io.Socket? _socket;
  final String baseUrl = AppConfig.socketBaseUrl;

  bool get isConnected => _socket?.connected ?? false;
  bool get isInitialized => _socket != null;

  io.Socket get socket {
    final current = _socket;
    if (current == null) {
      throw Exception('Socket no inicializado');
    }
    return current;
  }

  void init() {
    if (_socket != null) {
      if (!_socket!.connected) {
        debugPrint('🔄 Socket existente detectado, reconectando...');
        _socket!.connect();
      }
      return;
    }

    debugPrint('🔌 Inicializando socket en $baseUrl');

    _socket = io.io(
      baseUrl,
      io.OptionBuilder()
          .setPath('/socket.io')
          .setTransports(['websocket', 'polling'])
          .enableReconnection()
          .setReconnectionAttempts(999999)
          .setReconnectionDelay(1500)
          .setReconnectionDelayMax(5000)
          .disableAutoConnect()
          .build(),
    );

    _socket!.onConnect((_) {
      debugPrint('✅ Socket conectado: ${_socket?.id}');
    });

    _socket!.onDisconnect((reason) {
      debugPrint('❌ Socket desconectado: $reason');
    });

    _socket!.onConnectError((err) {
      debugPrint('🚨 Socket connect error: $err');
    });

    _socket!.onError((err) {
      debugPrint('🚨 Socket error: $err');
    });

    _socket!.onReconnect((attempt) {
      debugPrint('♻️ Socket reconectado. Intento: $attempt');
    });

    _socket!.onReconnectAttempt((attempt) {
      debugPrint('🔁 Intentando reconectar socket: $attempt');
    });

    _socket!.connect();
  }

  void reconnect() {
    if (_socket == null) {
      init();
      return;
    }

    debugPrint('🔄 Forzando reconexión de socket...');
    _socket!.disconnect();
    _socket!.connect();
  }

  /// Registra un listener sin borrar otros listeners del mismo evento.
  /// Esto es importante porque AppShellScreen y OrdersDashboardScreen escuchan
  /// new_order/order_updated al mismo tiempo.
  void on(String event, Function(dynamic) handler) {
    init();
    _socket?.on(event, handler);
  }

  void off(String event) {
    _socket?.off(event);
  }

  void offAll() {
    _socket?.clearListeners();
  }

  void onConnect(Function(dynamic) handler) {
    init();
    _socket?.onConnect(handler);
  }

  void onDisconnect(Function(dynamic) handler) {
    init();
    _socket?.onDisconnect(handler);
  }

  void onConnectError(Function(dynamic) handler) {
    init();
    _socket?.onConnectError(handler);
  }

  void onError(Function(dynamic) handler) {
    init();
    _socket?.onError(handler);
  }

  void dispose() {
    debugPrint('🧹 Cerrando socket...');
    _socket?.clearListeners();
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
  }
}
