import 'dart:convert';
import 'dart:typed_data';

/// Comandos ESC/POS para impresoras térmicas de tickets (58 u 80 mm).
/// Texto en Windows-1252 para que salgan bien los acentos y la ñ.
class EscPos {
  EscPos(this.columns) {
    _b.add(const [0x1B, 0x40]); // reiniciar
    _b.add(const [0x1B, 0x74, 16]); // página de códigos WPC1252
  }

  /// Caracteres por línea: 32 en 58 mm, 48 en 80 mm.
  final int columns;
  final _b = BytesBuilder();

  Uint8List get bytes => _b.toBytes();

  void center() => _b.add(const [0x1B, 0x61, 1]);
  void left() => _b.add(const [0x1B, 0x61, 0]);
  void bold(bool on) => _b.add([0x1B, 0x45, on ? 1 : 0]);

  /// Doble alto y ancho (títulos y total).
  void big(bool on) => _b.add([0x1D, 0x21, on ? 0x11 : 0x00]);

  void line([String text = '']) {
    _b.add(encode(text));
    _b.addByte(0x0A);
  }

  /// Texto largo partido en líneas del ancho del papel.
  void wrap(String text, {int indent = 0}) {
    final width = columns - indent;
    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    var current = '';
    for (final w in words) {
      if (current.isEmpty) {
        current = w.length > width ? w.substring(0, width) : w;
      } else if (current.length + 1 + w.length <= width) {
        current = '$current $w';
      } else {
        line('${' ' * indent}$current');
        current = w.length > width ? w.substring(0, width) : w;
      }
    }
    if (current.isNotEmpty) line('${' ' * indent}$current');
  }

  /// Texto a la izquierda y monto a la derecha en la misma línea.
  void row(String leftText, String rightText) {
    final space = columns - rightText.length - 1;
    if (leftText.length > space) {
      wrap(leftText);
      line(rightText.padLeft(columns));
      return;
    }
    line('${leftText.padRight(space)} $rightText');
  }

  void divider([String char = '-']) => line(char * columns);
  void feed([int lines = 1]) => _b.add([0x1B, 0x64, lines]);

  /// Código QR (modelo 2), p. ej. el enlace al recibo digital.
  void qr(String data, {int size = 6}) {
    final payload = utf8.encode(data);
    final length = payload.length + 3;
    _b.add(const [0x1D, 0x28, 0x6B, 0x04, 0x00, 0x31, 0x41, 0x32, 0x00]);
    _b.add([0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x43, size]);
    _b.add(const [0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x45, 0x31]);
    _b.add([0x1D, 0x28, 0x6B, length & 0xFF, (length >> 8) & 0xFF, 0x31, 0x50, 0x30]);
    _b.add(payload);
    _b.add(const [0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x51, 0x30]);
    _b.addByte(0x0A);
  }

  /// Avanza el papel y corta.
  void cut() {
    feed(4);
    _b.add(const [0x1D, 0x56, 0x42, 0x00]);
  }

  static const _special = <int, int>{
    0x2022: 0x95, // •
    0x2013: 0x96, // –
    0x2014: 0x97, // —
    0x2018: 0x91,
    0x2019: 0x92,
    0x201C: 0x93,
    0x201D: 0x94,
    0x20AC: 0x80, // €
    0x2212: 0x2D, // − → -
    0x00A0: 0x20,
  };

  static List<int> encode(String text) => [
        for (final rune in text.runes)
          if (rune < 0x80 || (rune >= 0xA0 && rune <= 0xFF)) rune else _special[rune] ?? 0x3F,
      ];
}
