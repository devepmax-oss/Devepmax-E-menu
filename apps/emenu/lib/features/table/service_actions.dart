import 'package:devepmax_ui/devepmax_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/widgets.dart';
import 'table_data.dart';

/// "Llamar al mesero" y "Pedir la cuenta", con su estado (pendiente / ya viene).
class ServiceActions extends ConsumerStatefulWidget {
  const ServiceActions({super.key, this.vertical = true, this.compact = false});
  final bool vertical;
  final bool compact;

  @override
  ConsumerState<ServiceActions> createState() => _ServiceActionsState();
}

class _ServiceActionsState extends ConsumerState<ServiceActions> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, {String? done}) async {
    setState(() => _busy = true);
    try {
      await action();
      if (done != null && mounted) showMessage(context, done);
    } catch (error) {
      if (mounted) showMessage(context, '$error', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final session = ref.watch(tableProvider).value?.session;
    final call = session?.request('CALL_WAITER');
    final bill = session?.request('REQUEST_BILL');
    final controller = ref.read(tableProvider.notifier);
    final hasOrders = session?.orders.any((o) => o.status != 'CANCELLED') ?? false;

    final Widget callButton;
    if (call == null) {
      callButton = _ActionTile(
        icon: Icons.notifications_active_rounded,
        label: 'Llamar al mesero',
        compact: widget.compact,
        onTap: _busy ? null : () => _run(controller.callWaiter, done: 'Listo, avisamos al mesero'),
      );
    } else {
      callButton = _ActionTile(
        icon: call.status == 'ACKNOWLEDGED' ? Icons.directions_walk_rounded : Icons.hourglass_top_rounded,
        label: call.status == 'ACKNOWLEDGED' ? 'El mesero ya viene' : 'Avisamos al mesero',
        caption: call.status == 'ACKNOWLEDGED' ? null : 'Toca para cancelar',
        highlight: t.accent,
        compact: widget.compact,
        onTap: _busy || call.status == 'ACKNOWLEDGED' ? null : () => _run(() => controller.cancelRequest(call.id)),
      );
    }

    final billButton = _ActionTile(
      icon: Icons.receipt_long_rounded,
      label: bill == null ? 'Pedir la cuenta' : 'Cuenta pedida',
      caption: bill == null ? (hasOrders ? formatMoney(session!.bill.total) : null) : 'El mesero la trae',
      highlight: bill == null ? null : t.accent,
      compact: widget.compact,
      onTap: hasOrders ? () => showBillSheet(context) : null,
    );

    final children = <Widget>[callButton, const SizedBox(width: 10, height: 10), billButton];
    return widget.vertical
        ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children)
        : Row(children: [for (final c in children) c is SizedBox ? c : Expanded(child: c)]);
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.icon, required this.label, this.caption, this.highlight, this.onTap, this.compact = false});
  final IconData icon;
  final String label;
  final String? caption;
  final Color? highlight;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final active = highlight != null;
    final fg = active ? t.onAccent : (onTap == null ? t.faint : t.text);
    return Material(
      color: active ? highlight : t.surface2,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: compact ? 10 : 14),
          child: Row(children: [
            Icon(icon, color: fg, size: compact ? 22 : 26),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: compact ? 14 : 15.5)),
                if (caption != null)
                  Text(caption!, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: fg.withValues(alpha: 0.8), fontSize: 12.5)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// La cuenta de la mesa: todo lo pedido, descuentos, impuestos y total. Desde aquí se pide.
Future<void> showBillSheet(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _BillDialog());

class _BillDialog extends ConsumerStatefulWidget {
  const _BillDialog();

  @override
  ConsumerState<_BillDialog> createState() => _BillDialogState();
}

class _BillDialogState extends ConsumerState<_BillDialog> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) showMessage(context, '$error', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final text = Theme.of(context).textTheme;
    final table = ref.watch(tableProvider).value;
    final session = table?.session;
    final controller = ref.read(tableProvider.notifier);
    final request = session?.request('REQUEST_BILL');
    final items = [
      for (final o in session?.orders ?? const <GuestOrder>[])
        if (o.status != 'CANCELLED') ...o.items,
    ];
    final bill = session?.bill;

    Widget row(String label, double value, {bool bold = false, Color? color}) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(children: [
            Expanded(child: Text(label, style: (bold ? text.titleLarge : text.bodyLarge)?.copyWith(color: color))),
            Text(formatMoney(value), style: (bold ? text.headlineSmall : text.bodyLarge)?.copyWith(color: color)),
          ]),
        );

    return Dialog(
      insetPadding: const EdgeInsets.all(32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 12, 4),
            child: Row(children: [
              Expanded(child: Text('Tu cuenta${table?.label != null ? ' · Mesa ${table!.label}' : ''}', style: text.headlineMedium)),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
            ]),
          ),
          Expanded(
            child: items.isEmpty
                ? Center(child: Text('Todavía no hay nada en la cuenta.', style: TextStyle(color: t.muted)))
                : ListView(padding: const EdgeInsets.fromLTRB(28, 8, 28, 8), children: [
                    for (final i in items)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          SizedBox(width: 34, child: Text('${i.quantity}×', style: text.titleMedium?.copyWith(color: t.accentText))),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(i.name, style: text.titleMedium),
                              if (i.modifiers.isNotEmpty) Text(i.modifiers.join(' · '), style: TextStyle(color: t.muted)),
                              if (i.notes != null) Text('“${i.notes}”', style: TextStyle(color: t.muted, fontStyle: FontStyle.italic)),
                            ]),
                          ),
                          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Text(formatMoney(i.lineTotal), style: text.titleMedium),
                            if (i.discount > 0) Text('−${formatMoney(i.discount)}', style: TextStyle(color: t.success)),
                          ]),
                        ]),
                      ),
                  ]),
          ),
          if (bill != null && items.isNotEmpty)
            Container(
              padding: const EdgeInsets.fromLTRB(28, 12, 28, 8),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: t.line))),
              child: Column(children: [
                row('Subtotal', bill.subtotal),
                if (bill.discountTotal > 0) row('Descuentos', -bill.discountTotal, color: t.success),
                row('Impuestos', bill.taxTotal),
                if (bill.tipTotal > 0) row('Propina', bill.tipTotal),
                const SizedBox(height: 4),
                row('Total', bill.total, bold: true),
                if (bill.paid > 0) ...[
                  row('Pagado', bill.paid, color: t.success),
                  row('Por pagar', bill.due, bold: true),
                ],
              ]),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 12, 28, 24),
            child: request == null
                ? FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(60), textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    onPressed: _busy || items.isEmpty ? null : () => _run(controller.requestBill),
                    icon: const Icon(Icons.receipt_long_rounded),
                    label: const Text('Pedir la cuenta'),
                  )
                : Row(children: [
                    Icon(Icons.check_circle_rounded, color: t.success, size: 30),
                    const SizedBox(width: 12),
                    Expanded(child: Text('Listo: el mesero te trae la cuenta.', style: text.titleMedium)),
                    TextButton(
                      onPressed: _busy ? null : () => _run(() => controller.cancelRequest(request.id)),
                      child: const Text('Cancelar'),
                    ),
                  ]),
          ),
        ]),
      ),
    );
  }
}
