import 'package:devepmax_ui/devepmax_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/ui/feedback.dart';
import '../data/billing_api.dart';
import '../data/billing_models.dart';
import 'discount_dialog.dart' show askManagerPin;

/// Devolver todo o parte de un pago. Tarjeta: vuelve a la tarjeta del cliente.
/// Efectivo: sale del cajón. Otro: solo queda registrado.
Future<BillView?> showRefundDialog(BuildContext context, BillPayment payment) =>
    showDialog<BillView>(context: context, builder: (_) => _RefundDialog(payment: payment));

const _reasons = ['Error en el pedido', 'No le gustó', 'Tardó demasiado', 'Cobro duplicado', 'Cortesía'];

class _RefundDialog extends ConsumerStatefulWidget {
  const _RefundDialog({required this.payment});
  final BillPayment payment;

  @override
  ConsumerState<_RefundDialog> createState() => _RefundDialogState();
}

class _RefundDialogState extends ConsumerState<_RefundDialog> {
  late final _amount = TextEditingController(text: widget.payment.refundable.toStringAsFixed(2));
  final _reason = TextEditingController();
  final _requestId = newRequestId();
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  double get _value => double.tryParse(_amount.text.trim()) ?? 0;
  bool get _valid => _value > 0 && _value <= widget.payment.refundable + 0.001 && _reason.text.trim().length >= 3;

  Future<void> _submit() async {
    final canRefund = ref.read(authControllerProvider).value?.employee.can('payments.refund') ?? false;
    String? pin;
    if (!canRefund) {
      pin = await askManagerPin(context);
      if (pin == null || pin.isEmpty) return;
    }
    setState(() => _busy = true);
    try {
      final all = (_value - widget.payment.refundable).abs() < 0.005;
      final bill = await ref.read(billingApiProvider).refund(
            widget.payment.id,
            requestId: _requestId,
            amount: all ? null : _value,
            reason: _reason.text.trim(),
            managerPin: pin,
          );
      if (mounted) Navigator.pop(context, bill);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final p = widget.payment;
    final where = p.method == 'CASH'
        ? 'Saca ${formatMoney(_value)} del cajón y entrégalo al cliente. Queda como salida de caja.'
        : p.stripe
            ? 'Se devuelve a la tarjeta del cliente. Su banco puede tardar de 5 a 10 días en mostrarlo.'
            : 'Devuélvelo por el mismo medio (por ejemplo, en el lector de tarjetas). Aquí solo queda registrado.';
    return AlertDialog(
      title: const Text('Reembolsar'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
              '${paymentMethodLabels[p.method] ?? p.method}${p.reference != null ? ' · ${p.reference}' : ''} · ${formatMoney(p.amount)}'
              '${p.refunded > 0 ? ' (ya devuelto ${formatMoney(p.refunded)})' : ''}',
              style: TextStyle(color: t.muted),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              decoration: InputDecoration(
                labelText: 'Monto a devolver',
                prefixText: r'$ ',
                helperText: 'Hasta ${formatMoney(p.refundable)}',
                errorText: _value > p.refundable + 0.001 ? 'Es más de lo que se puede devolver' : null,
                suffixIcon: TextButton(
                  onPressed: () => setState(() => _amount.text = p.refundable.toStringAsFixed(2)),
                  child: const Text('Todo'),
                ),
              ),
              onChanged: (_) => setState(() {}),
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
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Motivo'),
              onChanged: (_) => setState(() {}),
            ),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: t.infoSoft, borderRadius: BorderRadius.circular(14)),
              child: Text(where, style: TextStyle(color: t.info, fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: t.danger, foregroundColor: Theme.of(context).colorScheme.onError),
          onPressed: !_valid || _busy ? null : _submit,
          icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.undo_rounded),
          label: Text('Reembolsar ${formatMoney(_value)}'),
        ),
      ],
    );
  }
}
