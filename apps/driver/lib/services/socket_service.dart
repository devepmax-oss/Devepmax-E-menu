import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../core/config/app_config.dart';

class SocketService {
  SocketService._();

  static final SocketService instance = SocketService._();

  io.Socket? _socket;

  bool get isConnected => _socket?.connected ?? false;

  void init() {
    if (_socket != null) {
      if (!_socket!.connected) {
        _socket!.connect();
      }
      return;
    }

    debugPrint('Driver socket init => ${AppConfig.socketBaseUrl}');

    _socket = io.io(
      AppConfig.socketBaseUrl,
      io.OptionBuilder()
          .setPath('/socket.io')
          .setTransports(['websocket', 'polling'])
          .enableReconnection()
          .setReconnectionAttempts(999999)
          .setReconnectionDelay(2000)
          .disableAutoConnect()
          .build(),
    );

    _socket!.onConnect((_) {
      debugPrint('Driver socket connected: ${_socket?.id}');
    });

    _socket!.onDisconnect((reason) {
      debugPrint('Driver socket disconnected: $reason');
    });

    _socket!.onConnectError((error) {
      debugPrint('Driver socket connect error: $error');
    });

    _socket!.onError((error) {
      debugPrint('Driver socket error: $error');
    });

    _socket!.connect();
  }

  void on(String event, void Function(dynamic) handler) {
    _socket?.off(event);
    _socket?.on(event, handler);
  }

  void off(String event) {
    _socket?.off(event);
  }

  void emit(String event, dynamic data) {
    _socket?.emit(event, data);
  }

  void dispose() {
    _socket?.clearListeners();
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
  }
}
