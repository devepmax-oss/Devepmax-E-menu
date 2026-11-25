import 'package:devepmax_ui/devepmax_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
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
        label: context.tr('Llamar al mesero', 'Call the server'),
        compact: widget.compact,
        onTap: _busy ? null : () => _run(controller.callWaiter, done: context.tr('Listo, avisamos al mesero', 'Done, we let your server know')),
      );
    } else {
      callButton = _ActionTile(
        icon: call.status == 'ACKNOWLEDGED' ? Icons.directions_walk_rounded : Icons.hourglass_top_rounded,
        label: call.status == 'ACKNOWLEDGED' ? context.tr('El mesero ya viene', 'Your server is on the way') : context.tr('Avisamos al mesero', 'Server notified'),
        caption: call.status == 'ACKNOWLEDGED' ? null : context.tr('Toca para cancelar', 'Tap to cancel'),
        highlight: t.accent,
        compact: widget.compact,
        onTap: _busy || call.status == 'ACKNOWLEDGED' ? null : () => _run(() => controller.cancelRequest(call.id)),
      );
    }

    final billButton = _ActionTile(
      icon: Icons.receipt_long_rounded,
      label: bill != null ? context.tr('Cuenta pedida', 'Check requested') : (session?.payUrl != null && hasOrders ? context.tr('Cuenta y pago', 'Check & pay') : context.tr('Pedir la cuenta', 'Ask for the check')),
      caption: bill == null ? (hasOrders ? formatMoney(session!.bill.total) : null) : context.tr('El mesero la trae', 'Your server will bring it'),
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
    final canPayHere = session?.payUrl != null && bill != null && bill.due > 0 && items.isNotEmpty;

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
              Expanded(child: Text('${context.tr('Tu cuenta', 'Your check')}${table?.label != null ? ' · ${context.tr('Mesa', 'Table')} ${table!.label}' : ''}', style: text.headlineMedium)),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
            ]),
          ),
          Expanded(
            child: items.isEmpty
                ? Center(child: Text(context.tr('Todavía no hay nada en la cuenta.', 'Nothing on the check yet.'), style: TextStyle(color: t.muted)))
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
                if (bill.discountTotal > 0) row(context.tr('Descuentos', 'Discounts'), -bill.discountTotal, color: t.success),
                row(context.tr('Impuestos', 'Tax'), bill.taxTotal),
                if (bill.tipTotal > 0) row(context.tr('Propina', 'Tip'), bill.tipTotal),
                const SizedBox(height: 4),
                row('Total', bill.total, bold: true),
                if (bill.paid > 0) ...[
                  row(context.tr('Pagado', 'Paid'), bill.paid, color: t.success),
                  row(context.tr('Por pagar', 'Balance due'), bill.due, bold: true),
                ],
              ]),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 12, 28, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              if (canPayHere) ...[
                FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(60), textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  onPressed: () => showPayQr(context),
                  icon: const Icon(Icons.qr_code_2_rounded),
                  label: Text(context.tr('Pagar con mi celular', 'Pay with my phone')),
                ),
                const SizedBox(height: 6),
                Text(context.tr('Tarjeta, Apple Pay o Google Pay · todo o tu parte', 'Card, Apple Pay or Google Pay · all or your share'),
                    textAlign: TextAlign.center, style: TextStyle(color: t.muted, fontSize: 13)),
                const SizedBox(height: 12),
              ],
              if (bill != null && items.isNotEmpty && bill.due <= 0)
                Row(children: [
                  Icon(Icons.check_circle_rounded, color: t.success, size: 30),
                  const SizedBox(width: 12),
                  Expanded(child: Text(context.tr('Cuenta pagada. ¡Gracias!', 'Check paid. Thank you!'), style: text.titleMedium)),
                ])
              else
                _requestBillRow(context, request, controller, items.isEmpty, secondary: canPayHere),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _requestBillRow(BuildContext context, GuestRequest? request, TableController controller, bool empty, {required bool secondary}) {
    final t = BrandTokens.of(context);
    final text = Theme.of(context).textTheme;
    if (request == null) {
      final onPressed = _busy || empty ? null : () => _run(controller.requestBill);
      const icon = Icon(Icons.receipt_long_rounded);
      if (secondary) {
        return OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          onPressed: onPressed,
          icon: icon,
          label: Text(context.tr('Prefiero que el mesero me cobre', 'I’d rather pay my server')),
        );
      }
      return FilledButton.icon(
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(60), textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        onPressed: onPressed,
        icon: icon,
        label: Text(context.tr('Pedir la cuenta', 'Ask for the check')),
      );
    }
    return Row(children: [
      Icon(Icons.check_circle_rounded, color: t.success, size: 30),
      const SizedBox(width: 12),
      Expanded(child: Text(context.tr('Listo: el mesero te trae la cuenta.', 'Done: your server is bringing the check.'), style: text.titleMedium)),
      TextButton(
        onPressed: _busy ? null : () => _run(() => controller.cancelRequest(request.id)),
        child: Text(context.tr('Cancelar', 'Cancel')),
      ),
    ]);
  }
}

/// QR "Paga con tu celular": el cliente lo escanea y paga en su teléfono. Se cierra solo al pagar.
Future<void> showPayQr(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _PayQrDialog());

class _PayQrDialog extends ConsumerStatefulWidget {
  const _PayQrDialog();

  @override
  ConsumerState<_PayQrDialog> createState() => _PayQrDialogState();
}

class _PayQrDialogState extends ConsumerState<_PayQrDialog> {
  String? _url;
  double? _startDue;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    final session = ref.read(tableProvider).value?.session;
    _url = session?.payUrl;
    _startDue = session?.bill.due;
  }

  void _closeSoon() {
    if (_closing) return;
    _closing = true;
    Future<void>.delayed(const Duration(seconds: 5), () {
      // Cierra el QR y la cuenta: la mesa ya quedó pagada.
      if (mounted) Navigator.of(context).popUntil((route) => route is! PopupRoute);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final text = Theme.of(context).textTheme;
    final table = ref.watch(tableProvider).value;
    final session = table?.session;
    final url = _url;
    // La mesa se cerró (todo pagado) o ya no queda nada por pagar.
    final allPaid = table != null && (session == null || session.bill.due <= 0);
    final due = session?.bill.due ?? 0;
    final someonePaid = !allPaid && _startDue != null && due < _startDue! - 0.009;
    if (allPaid) _closeSoon();

    final size = MediaQuery.sizeOf(context);
    final qrSize = (size.shortestSide * 0.5).clamp(200.0, 320.0);
    final testLink = url != null && !url.startsWith('https://');

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 20, 28, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
            ),
            if (allPaid) ...[
              Icon(Icons.check_circle_rounded, color: t.success, size: 96),
              const SizedBox(height: 16),
              Text(context.tr('¡Pago recibido!', 'Payment received!'), style: text.headlineMedium, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(context.tr('La cuenta está pagada. ¡Gracias por tu visita!', 'The check is paid. Thanks for your visit!'), style: text.titleMedium?.copyWith(color: t.muted), textAlign: TextAlign.center),
              const SizedBox(height: 12),
            ] else if (url == null) ...[
              Text(context.tr('El pago con el celular no está disponible ahora.', 'Paying with your phone is not available right now.'), style: text.titleMedium, textAlign: TextAlign.center),
            ] else ...[
              Text(context.tr('Paga con tu celular', 'Pay with your phone'), style: text.headlineMedium, textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Text(context.tr('Abre la cámara y apunta al código', 'Open your camera and point it at the code'), style: text.titleMedium?.copyWith(color: t.muted), textAlign: TextAlign.center),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
                child: QrImageView(
                  data: url,
                  size: qrSize,
                  backgroundColor: Colors.white,
                  errorCorrectionLevel: QrErrorCorrectLevel.M,
                  semanticsLabel: context.tr('Código QR para pagar la cuenta', 'QR code to pay the check'),
                ),
              ),
              const SizedBox(height: 18),
              Text('${context.tr('Por pagar', 'Balance due')}: ${formatMoney(due)}', style: text.headlineSmall),
              if (someonePaid) ...[
                const SizedBox(height: 10),
                DmPill(context.tr('Pago recibido · quedan ${formatMoney(due)}', 'Payment received · ${formatMoney(due)} left'), icon: Icons.check_rounded, color: t.success),
              ],
              const SizedBox(height: 14),
              Wrap(alignment: WrapAlignment.center, spacing: 18, runSpacing: 8, children: [
                for (final (icon, label) in [
                  (Icons.credit_card_rounded, context.tr('Tarjeta', 'Card')),
                  (Icons.phone_iphone_rounded, 'Apple Pay'),
                  (Icons.android_rounded, 'Google Pay'),
                  (Icons.call_split_rounded, context.tr('Todo o tu parte', 'All or your share')),
                ])
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(icon, size: 18, color: t.accentText),
                    const SizedBox(width: 6),
                    Text(label, style: TextStyle(color: t.muted)),
                  ]),
              ]),
              const SizedBox(height: 12),
              Text(context.tr('Tu tarjeta nunca se escribe en esta tablet.', 'Your card is never entered on this tablet.'), style: TextStyle(color: t.faint, fontSize: 12.5), textAlign: TextAlign.center),
              if (testLink) ...[
                const SizedBox(height: 14),
                Text(context.tr('Modo prueba · abre este enlace en el navegador:', 'Test mode · open this link in a browser:'), style: TextStyle(color: t.muted, fontSize: 12)),
                SelectableText(url, textAlign: TextAlign.center, style: TextStyle(color: t.accentText, fontSize: 12)),
              ],
            ],
          ]),
        ),
      ),
    );
  }
}
