/// En el navegador no se puede abrir una conexión directa a la impresora.
Future<void> sendToPrinter(String host, int port, List<int> bytes) async {
  throw UnsupportedError('Para imprimir tickets usa la app instalada en el aparato (Android o Windows)');
}

const bool canPrintHere = false;
