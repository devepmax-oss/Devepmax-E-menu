import 'package:devepmax_ui/devepmax_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/ui/feedback.dart';
import '../data/billing_api.dart';
import '../data/billing_models.dart';

double _parse(String v) => double.tryParse(v.replaceAll(',', '.')) ?? -1;

final _moneyInput = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];

/// Abrir la caja con el fondo inicial.
Future<void> showOpenShiftDialog(BuildContext context, WidgetRef ref) async {
  final amount = await _askMoney(context, title: 'Abrir caja', label: 'Efectivo inicial (fondo)', confirm: 'Abrir caja');
  if (amount == null || !context.mounted) return;
  try {
    await ref.read(billingApiProvider).openShift(amount);
    ref.invalidate(cashShiftProvider);
    if (context.mounted) showSuccess(context, 'Caja abierta con ${formatMoney(amount)}');
  } catch (error) {
    if (context.mounted) showError(context, error);
  }
}

Future<double?> _askMoney(BuildContext context, {required String title, required String label, required String confirm, String? help}) {
  final controller = TextEditingController();
  return showDialog<double>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final value = _parse(controller.text);
        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 380,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (help != null) ...[Text(help), const SizedBox(height: 12)],
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: _moneyInput,
                decoration: InputDecoration(prefixText: '\$ ', labelText: label, border: const OutlineInputBorder()),
                onChanged: (_) => setState(() {}),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            FilledButton(onPressed: value >= 0 ? () => Navigator.pop(context, value) : null, child: Text(confirm)),
          ],
        );
      },
    ),
  );
}

/// Resumen del turno: ventas por forma de pago, propinas, movimientos y efectivo esperado.
/// Desde aquí se registran entradas/salidas y se cierra la caja.
Future<void> showShiftSheet(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _ShiftDialog());

class _ShiftDialog extends ConsumerStatefulWidget {
  const _ShiftDialog();

  @override
  ConsumerState<_ShiftDialog> createState() => _ShiftDialogState();
}

class _ShiftDialogState extends ConsumerState<_ShiftDialog> {
  bool _busy = false;

  Future<void> _movement() async {
    final result = await showDialog<(String, double, String)>(context: context, builder: (_) => const _MovementDialog());
    if (result == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(billingApiProvider).movement(result.$1, result.$2, result.$3);
      ref.invalidate(cashShiftProvider);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _close(CashShiftView shift) async {
    final counted = await _askMoney(
      context,
      title: 'Cerrar caja',
      label: 'Efectivo contado',
      confirm: 'Cerrar caja',
      help: 'Cuenta el efectivo del cajón y escríbelo. Debería haber ${formatMoney(shift.expectedCash)}.',
    );
    if (counted == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final closed = await ref.read(billingApiProvider).closeShift(counted, null);
      ref.invalidate(cashShiftProvider);
      if (!mounted) return;
      Navigator.pop(context);
      final diff = closed.difference ?? 0;
      showSuccess(
        context,
        diff.abs() < 0.005
            ? 'Caja cerrada: cuadra exacto'
            : 'Caja cerrada: ${diff > 0 ? 'sobran' : 'faltan'} ${formatMoney(diff.abs())}',
      );
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final text = Theme.of(context).textTheme;
    final shift = ref.watch(cashShiftProvider).value;
    final canClose = ref.watch(authControllerProvider).value?.employee.can('cash.shift') ?? false;
    final time = DateFormat.jm();

    if (shift == null) {
      return AlertDialog(
        title: const Text('Caja cerrada'),
        content: const Text('No hay un turno de caja abierto.'),
        actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))],
      );
    }

    Widget line(String label, double value, {bool bold = false, Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(child: Text(label, style: (bold ? text.titleMedium : text.bodyMedium)?.copyWith(color: color))),
            Text(formatMoney(value), style: (bold ? text.titleLarge : text.bodyMedium)?.copyWith(color: color)),
          ]),
        );

    const movementLabels = {'PAY_IN': 'Entrada', 'PAY_OUT': 'Salida', 'DROP': 'Retiro a caja fuerte'};
    final cashSales = shift.sales.where((s) => s.method == 'CASH').fold<double>(0, (a, s) => a + s.amount);

    return AlertDialog(
      title: Text('Caja abierta desde ${time.format(shift.openedAt)}'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (shift.openedBy != null) Text('Abrió: ${shift.openedBy}', style: TextStyle(color: t.muted)),
            const SizedBox(height: 12),
            Text('Ventas', style: text.titleMedium),
            if (shift.sales.isEmpty) Text('Todavía no hay cobros.', style: TextStyle(color: t.muted)),
            for (final s in shift.sales) line('${paymentMethodLabels[s.method] ?? s.method} · ${s.count}', s.amount),
            if (shift.sales.isNotEmpty) ...[
              line('Total cobrado', shift.totalSales, bold: true),
              line('Propinas incluidas', shift.totalTips, color: t.muted),
            ],
            Divider(height: 24, color: t.line),
            Text('Efectivo en el cajón', style: text.titleMedium),
            line('Fondo inicial', shift.openingCash),
            line('Cobros en efectivo', cashSales),
            for (final m in shift.movements)
              line('${movementLabels[m.type]}: ${m.reason}', m.type == 'PAY_IN' ? m.amount : -m.amount, color: t.muted),
            line('Debería haber', shift.expectedCash, bold: true),
          ]),
        ),
      ),
      actions: [
        if (canClose) ...[
          TextButton.icon(
            onPressed: _busy ? null : _movement,
            icon: const Icon(Icons.swap_vert_rounded),
            label: const Text('Entrada / salida'),
          ),
          OutlinedButton(onPressed: _busy ? null : () => _close(shift), child: const Text('Cerrar caja')),
        ],
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Listo')),
      ],
    );
  }
}

class _MovementDialog extends StatefulWidget {
  const _MovementDialog();

  @override
  State<_MovementDialog> createState() => _MovementDialogState();
}

class _MovementDialogState extends State<_MovementDialog> {
  final _amount = TextEditingController();
  final _reason = TextEditingController();
  String _type = 'PAY_OUT';

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final amount = _parse(_amount.text);
    final ok = amount > 0 && _reason.text.trim().length >= 3;
    return AlertDialog(
      title: const Text('Movimiento de efectivo'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'PAY_OUT', label: Text('Salida')),
              ButtonSegment(value: 'PAY_IN', label: Text('Entrada')),
              ButtonSegment(value: 'DROP', label: Text('Retiro')),
            ],
            selected: {_type},
            onSelectionChanged: (v) => setState(() => _type = v.first),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: _moneyInput,
            decoration: const InputDecoration(prefixText: '\$ ', labelText: 'Monto', border: OutlineInputBorder()),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reason,
            maxLength: 200,
            decoration: InputDecoration(
              labelText: 'Motivo',
              hintText: _type == 'PAY_OUT' ? 'Compra de hielo, pago a proveedor…' : (_type == 'DROP' ? 'Retiro a caja fuerte' : 'Cambio extra…'),
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: ok ? () => Navigator.pop(context, (_type, amount, _reason.text.trim())) : null,
          child: const Text('Registrar'),
        ),
      ],
    );
  }
}
