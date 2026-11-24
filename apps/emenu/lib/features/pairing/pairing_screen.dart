import 'package:devepmax_ui/devepmax_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/api_exception.dart';
import '../../core/device_session.dart';
import '../kiosk/staff_menu.dart' show NumericKeypad;

/// Primera vez: la tablet se vincula escaneando el QR de la app Staff o escribiendo el código.
class PairingScreen extends ConsumerStatefulWidget {
  const PairingScreen({super.key});

  @override
  ConsumerState<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends ConsumerState<PairingScreen> {
  final _scanner = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _typing = false;
  bool _busy = false;
  String _code = '';
  String? _error;

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  Future<void> _pair(String code, {String? api}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(deviceSessionProvider.notifier).pair(code, api: api);
      // Listo: la app cambia sola a la pantalla de la mesa.
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = ApiException.from(error).message;
          _code = '';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (_busy) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;
      final data = parsePairingQr(raw);
      if (data == null) {
        setState(() => _error = 'Ese QR no es de vinculación. Usa el que muestra la app Staff en Dispositivos.');
        return;
      }
      _pair(data.code, api: data.api);
      return;
    }
  }

  void _onKey(String key) {
    if (_busy) return;
    setState(() {
      _error = null;
      if (key == '⌫') {
        if (_code.isNotEmpty) _code = _code.substring(0, _code.length - 1);
      } else if (_code.length < 6) {
        _code += key;
      }
    });
    if (_code.length == 6) _pair(_code);
  }

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final text = Theme.of(context).textTheme;
    final wide = MediaQuery.sizeOf(context).width >= 900;

    final intro = Column(
      crossAxisAlignment: wide ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.tablet_android_rounded, size: 56, color: t.accentText),
        const SizedBox(height: 16),
        Text('Vincula este aparato', style: text.displaySmall, textAlign: wide ? TextAlign.start : TextAlign.center),
        const SizedBox(height: 16),
        for (final (i, step) in const [
          'En la app Staff abre Dispositivos.',
          'Crea una "Tablet de mesa" (con su mesa) o una "Pantalla de cocina" (con su estación).',
          'Toca "Generar código" y muestra el QR a esta tablet.',
        ].indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: t.primarySoft,
                child: Text('${i + 1}', style: TextStyle(color: t.primaryText, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 12),
              Flexible(child: Text(step, style: text.titleMedium)),
            ]),
          ),
      ],
    );

    final scanner = Column(mainAxisSize: MainAxisSize.min, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Container(
          width: 340,
          height: 340,
          color: Colors.black,
          child: Stack(fit: StackFit.expand, children: [
            MobileScanner(controller: _scanner, onDetect: _onDetect),
            IgnorePointer(
              child: Center(
                child: Container(
                  width: 230,
                  height: 230,
                  decoration: BoxDecoration(
                    border: Border.all(color: t.accent, width: 4),
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
              ),
            ),
            if (_busy) const ColoredBox(color: Colors.black54, child: Center(child: CircularProgressIndicator())),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      Text('Apunta la cámara al código QR', style: TextStyle(color: t.muted)),
      TextButton.icon(
        onPressed: () => _scanner.switchCamera(),
        icon: const Icon(Icons.cameraswitch_rounded),
        label: const Text('Cambiar de cámara'),
      ),
    ]);

    final keypad = Column(mainAxisSize: MainAxisSize.min, children: [
      Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < 6; i++) ...[
          if (i == 3) const SizedBox(width: 14),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: 46,
            height: 58,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: t.surface2,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: i == _code.length ? t.accent : t.line, width: 2),
            ),
            child: Text(i < _code.length ? _code[i] : '',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: t.text)),
          ),
        ],
      ]),
      const SizedBox(height: 20),
      SizedBox(width: 260, child: NumericKeypad(onKey: _onKey)),
      if (_busy) const Padding(padding: EdgeInsets.only(top: 16), child: CircularProgressIndicator()),
    ]);

    final action = Column(mainAxisSize: MainAxisSize.min, children: [
      AnimatedSwitcher(duration: const Duration(milliseconds: 220), child: _typing ? keypad : scanner),
      const SizedBox(height: 8),
      SizedBox(
        height: 48,
        child: _error == null
            ? null
            : Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: t.danger, fontWeight: FontWeight.w700)),
      ),
      OutlinedButton.icon(
        onPressed: _busy ? null : () => setState(() => _typing = !_typing),
        icon: Icon(_typing ? Icons.qr_code_scanner_rounded : Icons.dialpad_rounded),
        label: Text(_typing ? 'Escanear el QR' : 'Escribir el código de 6 dígitos'),
      ),
    ]);

    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: wide
                ? Row(mainAxisSize: MainAxisSize.min, children: [
                    ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440), child: intro),
                    const SizedBox(width: 64),
                    action,
                  ])
                : Column(mainAxisSize: MainAxisSize.min, children: [intro, const SizedBox(height: 32), action]),
          ),
        ),
      ),
    );
  }
}
