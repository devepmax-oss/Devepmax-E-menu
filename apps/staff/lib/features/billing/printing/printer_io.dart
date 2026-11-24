import 'dart:async';
import 'dart:io';

/// Manda el ticket a una impresora de red (puerto 9100, el estándar de las térmicas).
Future<void> sendToPrinter(String host, int port, List<int> bytes) async {
  final socket = await Socket.connect(host, port, timeout: const Duration(seconds: 5));
  try {
    socket.add(bytes);
    await socket.flush().timeout(const Duration(seconds: 10));
  } finally {
    await socket.close();
    socket.destroy();
  }
}

const bool canPrintHere = true;
