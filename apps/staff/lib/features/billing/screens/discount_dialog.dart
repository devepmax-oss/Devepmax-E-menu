import 'package:devepmax_ui/devepmax_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/ui/feedback.dart';
import '../data/billing_api.dart';
import '../data/billing_models.dart';

/// Descuento a la cuenta o a un artículo. Si quien lo aplica no tiene permiso, pide el PIN
/// de un gerente (queda registrado quién autorizó).
Future<BillView?> showDiscountDialog(BuildContext context, BillView bill) =>
    showDialog<BillView>(context: context, builder: (_) => _DiscountDialog(bill: bill));

const _reasons = ['Cortesía de la casa', 'Cliente frecuente', 'Error en el pedido', 'Demora en la cocina'];

class _DiscountDialog extends ConsumerStatefulWidget {
  const _DiscountDialog({required this.bill});
  final BillView bill;

  @override
  ConsumerState<_DiscountDialog> createState() => _DiscountDialogState();
}

class _DiscountDialogState extends ConsumerState<_DiscountDialog> {
  final _value = TextEditingController();
  final _reason = TextEditingController();
  final _pin = TextEditingController();
  String _type = 'PERCENT';
  String? _itemId;
  bool _busy = false;

  @override
  void dispose() {
    _value.dispose();
    _reason.dispose();
    _pin.dispose();
    super.dispose();
  }

  double get _valueNum => double.tryParse(_value.text.replaceAll(',', '.')) ?? 0;

  String? _problem(bool needsPin) {
    if (_valueNum <= 0) return 'Escribe el descuento';
    if (_type == 'PERCENT' && _valueNum > 100) return 'El porcentaje va de 1 a 100';
    if (_reason.text.trim().length < 3) return 'Escribe o elige el motivo';
    if (needsPin && _pin.text.length < 4) return 'Hace falta el PIN de un gerente';
    return null;
  }

  Future<void> _save(bool needsPin) async {
    if (_problem(needsPin) != null) return;
    setState(() => _busy = true);
    try {
      final updated = await ref.read(billingApiProvider).discount(
            widget.bill.id,
            type: _type,
            value: _valueNum,
            reason: _reason.text.trim(),
            itemId: _itemId,
            managerPin: needsPin ? _pin.text : null,
          );
      if (mounted) Navigator.pop(context, updated);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final needsPin = !(ref.watch(authControllerProvider).value?.employee.can('bills.discount') ?? false);
    final problem = _problem(needsPin);
    return AlertDialog(
      title: const Text('Descuento'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [ButtonSegment(value: 'PERCENT', label: Text('%')), ButtonSegment(value: 'AMOUNT', label: Text('\$'))],
                selected: {_type},
                onSelectionChanged: (v) => setState(() => _type = v.first),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _value,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                  decoration: InputDecoration(
                    labelText: _type == 'PERCENT' ? 'Porcentaje' : 'Monto',
                    suffixText: _type == 'PERCENT' ? '%' : null,
                    prefixText: _type == 'AMOUNT' ? '\$ ' : null,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ]),
            const SizedBox(height: 14),
            DropdownButtonFormField<String?>(
              initialValue: _itemId,
              decoration: const InputDecoration(labelText: 'A qué', border: OutlineInputBorder()),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Toda la cuenta')),
                for (final i in widget.bill.items)
                  DropdownMenuItem<String?>(value: i.id, child: Text('${i.quantity}× ${i.name} · ${formatMoney(i.lineTotal)}')),
              ],
              onChanged: (v) => setState(() => _itemId = v),
            ),
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final r in _reasons)
                ChoiceChip(
                  label: Text(r),
                  selected: _reason.text == r,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _reason.text = r),
                ),
            ]),
            const SizedBox(height: 10),
            TextField(
              controller: _reason,
              maxLength: 200,
              decoration: const InputDecoration(labelText: 'Motivo', border: OutlineInputBorder()),
              onChanged: (_) => setState(() {}),
            ),
            if (needsPin) ...[
              const SizedBox(height: 6),
              TextField(
                controller: _pin,
                obscureText: true,
                maxLength: 6,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'PIN de un gerente',
                  helperText: 'Tu rol no aplica descuentos solo: un gerente lo autoriza con su PIN.',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
            if (problem != null && _valueNum > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(problem, style: TextStyle(color: t.danger, fontWeight: FontWeight.w600)),
              ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: problem == null && !_busy ? () => _save(needsPin) : null, child: const Text('Aplicar descuento')),
      ],
    );
  }
}

/// Pide el PIN de un gerente (para quitar un descuento sin permiso propio).
Future<String?> askManagerPin(BuildContext context) {
  final pin = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('PIN de un gerente'),
      content: TextField(
        controller: pin,
        autofocus: true,
        obscureText: true,
        maxLength: 6,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(border: OutlineInputBorder()),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(context, pin.text), child: const Text('Autorizar')),
      ],
    ),
  );
}
