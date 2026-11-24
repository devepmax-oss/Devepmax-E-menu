import 'package:devepmax_ui/devepmax_ui.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_exception.dart';
import '../../core/device_session.dart';
import '../../core/widgets.dart';
import '../menu/menu_data.dart';
import '../table/table_data.dart';
import 'kiosk.dart';

/// Menú oculto del personal (logo presionado 3 s): pide un PIN de alguien que atiende mesas.
Future<void> openStaffMenu(BuildContext context) async {
  final name = await showDialog<String>(context: context, builder: (_) => const _PinDialog());
  if (name == null || !context.mounted) return;
  await showDialog<void>(context: context, builder: (_) => _StaffOptions(employeeName: name));
}

class _PinDialog extends ConsumerStatefulWidget {
  const _PinDialog();

  @override
  ConsumerState<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends ConsumerState<_PinDialog> {
  String _pin = '';
  String? _error;
  bool _busy = false;

  Future<void> _submit() async {
    if (_pin.length < 4 || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final dio = ref.read(dioProvider);
      final response = await dio.post<Map<String, dynamic>>(
        '/auth/device/staff-check',
        data: {'pin': _pin},
        options: Options(extra: {'pin': true}),
      );
      if (mounted) Navigator.pop(context, response.data?['name'] as String? ?? 'Personal');
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = ApiException.from(error).message;
          _pin = '';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _tap(String key) {
    setState(() {
      _error = null;
      if (key == '⌫') {
        if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1);
      } else if (_pin.length < 6) {
        _pin += key;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    return AlertDialog(
      title: const Text('Solo personal'),
      content: SizedBox(
        width: 320,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Escribe tu PIN', style: TextStyle(color: t.muted)),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < 6; i++)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 6),
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < _pin.length ? t.primary : Colors.transparent,
                  border: Border.all(color: i < _pin.length ? t.primary : t.lineStrong, width: 2),
                ),
              ),
          ]),
          SizedBox(
            height: 28,
            child: Center(child: Text(_error ?? '', style: TextStyle(color: t.danger, fontWeight: FontWeight.w600))),
          ),
          NumericKeypad(onKey: _tap),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: _pin.length >= 4 && !_busy ? _submit : null,
          child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Entrar'),
        ),
      ],
    );
  }
}

/// Teclado numérico grande (PIN y código de vinculación).
class NumericKeypad extends StatelessWidget {
  const NumericKeypad({super.key, required this.onKey, this.keySize = 72});
  final ValueChanged<String> onKey;
  final double keySize;

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', '⌫'];
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      alignment: WrapAlignment.center,
      children: [
        for (final k in keys)
          SizedBox(
            width: keySize,
            height: keySize * 0.8,
            child: k.isEmpty
                ? const SizedBox()
                : Material(
                    color: t.surface2,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => onKey(k),
                      child: Center(
                        child: k == '⌫'
                            ? Icon(Icons.backspace_outlined, color: t.muted)
                            : Text(k, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: t.text)),
                      ),
                    ),
                  ),
          ),
      ],
    );
  }
}

class _StaffOptions extends ConsumerWidget {
  const _StaffOptions({required this.employeeName});
  final String employeeName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = BrandTokens.of(context);
    final session = ref.watch(deviceSessionProvider).value;
    final table = ref.watch(tableProvider).value;

    Widget option(IconData icon, String title, String subtitle, VoidCallback onTap, {bool danger = false}) => ListTile(
          leading: Icon(icon, color: danger ? t.danger : t.accentText),
          title: Text(title, style: TextStyle(color: danger ? t.danger : null, fontWeight: FontWeight.w700)),
          subtitle: Text(subtitle),
          onTap: onTap,
        );

    return AlertDialog(
      title: Text('Hola, $employeeName'),
      content: SizedBox(
        width: 460,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
            '${session?.deviceName ?? 'Tablet'}${table?.label != null ? ' · Mesa ${table!.label}' : ' · sin mesa'}',
            style: TextStyle(color: t.muted),
          ),
          const SizedBox(height: 12),
          option(Icons.refresh_rounded, 'Recargar', 'Vuelve a cargar el menú y la mesa', () {
            ref.read(menuProvider.notifier).reload();
            ref.read(tableProvider.notifier).refresh();
            ref.invalidate(brandProvider);
            Navigator.pop(context);
          }),
          option(Icons.home_rounded, 'Volver a la bienvenida', 'Vacía el pedido que estaban armando', () {
            ref.read(kioskStageProvider.notifier).reset();
            Navigator.pop(context);
          }),
          option(Icons.link_off_rounded, 'Desvincular esta tablet', 'Para usarla en otra mesa o cambiarla', () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('¿Desvincular la tablet?'),
                content: const Text('Para volver a usarla hay que generar un código nuevo en la app Staff → Dispositivos.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
                  FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Desvincular')),
                ],
              ),
            );
            if (ok != true || !context.mounted) return;
            final session = ref.read(deviceSessionProvider.notifier);
            Navigator.pop(context);
            await session.forget();
          }, danger: true),
          const SizedBox(height: 8),
          Text('Servidor: ${ref.watch(apiBaseProvider)}', style: TextStyle(color: t.faint, fontSize: 12)),
        ]),
      ),
      actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))],
    );
  }
}
