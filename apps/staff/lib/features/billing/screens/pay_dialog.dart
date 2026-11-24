import 'package:devepmax_ui/devepmax_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/feedback.dart';
import '../data/billing_api.dart';
import '../data/billing_models.dart';

/// Cobrar: cuánto (todo, una parte o partes iguales), propina y forma de pago.
/// Devuelve la cuenta actualizada y el cambio a entregar.
Future<({BillView bill, double change})?> showPayDialog(BuildContext context, BillView bill) =>
    showDialog<({BillView bill, double change})>(
        context: context, barrierDismissible: false, builder: (_) => _PayDialog(bill: bill));

class _PayDialog extends ConsumerStatefulWidget {
  const _PayDialog({required this.bill});
  final BillView bill;

  @override
  ConsumerState<_PayDialog> createState() => _PayDialogState();
}

class _PayDialogState extends ConsumerState<_PayDialog> {
  final _requestId = newRequestId();
  final _amount = TextEditingController();
  final _tip = TextEditingController();
  final _tendered = TextEditingController();
  final _reference = TextEditingController();
  int _parts = 1; // 0 = otro monto
  int? _tipPercent; // null = sin propina, -1 = otra
  String _method = 'CASH';
  bool _busy = false;

  double get _due => widget.bill.due;

  double get _amountValue {
    if (_parts == 0) return double.tryParse(_amount.text.replaceAll(',', '.')) ?? 0;
    if (_parts == 1) return _due;
    // Partes iguales: se redondea hacia arriba al centavo (la última parte paga lo que falte).
    return ((_due / _parts) * 100).ceilToDouble() / 100;
  }

  double get _tipValue {
    final p = _tipPercent;
    if (p == null) return 0;
    if (p == -1) return double.tryParse(_tip.text.replaceAll(',', '.')) ?? 0;
    return ((_amountValue * p / 100) * 100).roundToDouble() / 100;
  }

  double get _charged => _amountValue + _tipValue;
  double get _tenderedValue => double.tryParse(_tendered.text.replaceAll(',', '.')) ?? _charged;
  double get _change => (_tenderedValue - _charged).clamp(0, double.infinity);

  String? get _problem {
    final a = _amountValue;
    if (a <= 0) return 'Escribe el monto';
    if (a > _due + 0.001) return 'Es más de lo que se debe (${formatMoney(_due)})';
    if (_method == 'CASH' && _tenderedValue + 0.001 < _charged) return 'El efectivo recibido no alcanza';
    return null;
  }

  @override
  void dispose() {
    _amount.dispose();
    _tip.dispose();
    _tendered.dispose();
    _reference.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_problem != null || _busy) return;
    setState(() => _busy = true);
    try {
      final amount = double.parse(_amountValue.clamp(0, _due).toStringAsFixed(2));
      final updated = await ref.read(billingApiProvider).pay(
            widget.bill.id,
            requestId: _requestId,
            method: _method,
            amount: amount,
            tip: _tipValue,
            cashTendered: _method == 'CASH' ? _tenderedValue : null,
            reference: _method == 'CASH' ? null : _reference.text,
          );
      ref.invalidate(openBillsProvider);
      ref.invalidate(cashShiftProvider);
      if (!mounted) return;
      Navigator.pop(context, (bill: updated, change: _method == 'CASH' ? _change : 0.0));
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
    final problem = _problem;

    Widget section(String title, Widget child) => Padding(
          padding: const EdgeInsets.only(top: 18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: text.titleSmall?.copyWith(color: t.muted)),
            const SizedBox(height: 8),
            child,
          ]),
        );

    final quickCash = <double>{
      _charged,
      (_charged / 5).ceil() * 5.0,
      (_charged / 10).ceil() * 10.0,
      (_charged / 20).ceil() * 20.0,
      50,
      100,
    }.where((v) => v + 0.001 >= _charged).toList()
      ..sort();

    return AlertDialog(
      title: Row(children: [
        Expanded(child: Text('Cobrar · ${widget.bill.label}')),
        Text('Debe ${formatMoney(_due)}', style: text.titleMedium?.copyWith(color: t.accentText)),
      ]),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            section(
              '¿Cuánto paga?',
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final (parts, label) in const [(1, 'Todo'), (2, '½'), (3, '⅓'), (4, '¼'), (0, 'Otro monto')])
                    ChoiceChip(
                      label: Text(label),
                      selected: _parts == parts,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _parts = parts),
                    ),
                ]),
                if (_parts == 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: TextField(
                      controller: _amount,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                      decoration: const InputDecoration(prefixText: '\$ ', labelText: 'Monto', border: OutlineInputBorder()),
                      onChanged: (_) => setState(() {}),
                    ),
                  )
                else if (_parts > 1)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('Cada parte: ${formatMoney(_amountValue)}', style: TextStyle(color: t.muted)),
                  ),
              ]),
            ),
            section(
              'Propina',
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final (p, label) in const [(null, 'Sin propina'), (15, '15%'), (18, '18%'), (20, '20%'), (-1, 'Otra')])
                    ChoiceChip(
                      label: Text(p != null && p > 0 ? '$label · ${formatMoney(((_amountValue * p / 100) * 100).roundToDouble() / 100)}' : label),
                      selected: _tipPercent == p,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _tipPercent = p),
                    ),
                ]),
                if (_tipPercent == -1)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: TextField(
                      controller: _tip,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                      decoration: const InputDecoration(prefixText: '\$ ', labelText: 'Propina', border: OutlineInputBorder()),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
              ]),
            ),
            section(
              'Forma de pago',
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'CASH', label: Text('Efectivo'), icon: Icon(Icons.payments_rounded)),
                  ButtonSegment(value: 'CARD_TERMINAL', label: Text('Tarjeta'), icon: Icon(Icons.credit_card_rounded)),
                  ButtonSegment(value: 'OTHER', label: Text('Otro'), icon: Icon(Icons.more_horiz_rounded)),
                ],
                selected: {_method},
                onSelectionChanged: (v) => setState(() => _method = v.first),
              ),
            ),
            if (_method == 'CASH')
              section(
                '¿Con cuánto paga?',
                Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final v in quickCash)
                      ActionChip(
                        label: Text(v == _charged ? 'Exacto' : formatMoney(v)),
                        onPressed: () => setState(() => _tendered.text = v.toStringAsFixed(2)),
                      ),
                  ]),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _tendered,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                    decoration: InputDecoration(
                      prefixText: '\$ ',
                      labelText: 'Efectivo recibido',
                      hintText: _charged.toStringAsFixed(2),
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: t.successSoft, borderRadius: BorderRadius.circular(14)),
                    child: Row(children: [
                      Text('Cambio', style: text.titleMedium?.copyWith(color: t.success)),
                      const Spacer(),
                      Text(formatMoney(_change), style: text.headlineSmall?.copyWith(color: t.success, fontWeight: FontWeight.w800)),
                    ]),
                  ),
                ]),
              )
            else
              section(
                _method == 'CARD_TERMINAL' ? 'Cobra en el lector y anota (opcional)' : 'Cómo pagó (opcional)',
                TextField(
                  controller: _reference,
                  maxLength: 60,
                  decoration: InputDecoration(
                    hintText: _method == 'CARD_TERMINAL' ? 'Últimos 4 dígitos o autorización' : 'Zelle, transferencia, cortesía…',
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: t.surface2, borderRadius: BorderRadius.circular(14)),
              child: Column(children: [
                _Line('A la cuenta', _amountValue),
                if (_tipValue > 0) _Line('Propina', _tipValue),
                _Line('Total a cobrar', _charged, bold: true),
                if (_amountValue > 0 && _amountValue < _due - 0.001)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('Quedan ${formatMoney(_due - _amountValue)} por cobrar', style: TextStyle(color: t.muted)),
                  ),
              ]),
            ),
            if (problem != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(problem, style: TextStyle(color: t.danger, fontWeight: FontWeight.w700)),
              ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size(200, 52)),
          onPressed: problem == null && !_busy ? _confirm : null,
          icon: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.check_rounded),
          label: Text('Cobrar ${formatMoney(_charged)}'),
        ),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value, {this.bold = false});
  final String label;
  final double value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final style = bold ? text.titleLarge : text.bodyLarge;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(children: [Expanded(child: Text(label, style: style)), Text(formatMoney(value), style: style)]),
    );
  }
}

/// "Entrega de cambio: $X" en grande.
Future<void> showChangeDialog(BuildContext context, double change) {
  final t = BrandTokens.of(context);
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.payments_rounded, size: 56, color: t.success),
        const SizedBox(height: 12),
        const Text('Entrega de cambio'),
        const SizedBox(height: 6),
        Text(formatMoney(change), style: Theme.of(context).textTheme.displayMedium?.copyWith(fontWeight: FontWeight.w800)),
      ]),
      actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Listo'))],
    ),
  );
}
