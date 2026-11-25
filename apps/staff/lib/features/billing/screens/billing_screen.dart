import 'dart:async';

import 'package:collection/collection.dart';
import 'package:devepmax_ui/devepmax_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/realtime/realtime.dart';
import '../../../core/ui/feedback.dart';
import '../../customers/data/customers_api.dart';
import '../../customers/screens/customer_picker.dart';
import '../../menu/widgets/common.dart';
import '../../orders/screens/orders_screen.dart' show LiveIndicator;
import '../data/billing_api.dart';
import '../data/billing_models.dart';
import 'discount_dialog.dart';
import 'pay_dialog.dart';
import 'receipt_dialog.dart';
import 'refund_dialog.dart';
import 'shift_dialogs.dart';

/// Caja: cuentas por cobrar a la izquierda, la cuenta elegida a la derecha.
class BillingScreen extends ConsumerStatefulWidget {
  const BillingScreen({super.key, this.tableId, this.billId});

  /// Abrir directo la cuenta de una mesa (desde Mesas) o una cuenta (desde Órdenes).
  final String? tableId;
  final String? billId;

  @override
  ConsumerState<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends ConsumerState<BillingScreen> {
  String? _selected;
  String _filter = 'all';
  bool _pickedFromRoute = false;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _selected = widget.billId;
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  bool _matches(BillView b) => switch (_filter) {
        'TABLE' => b.kind == 'TABLE',
        'TOGO' => b.kind != 'TABLE',
        'REQUESTED' => b.billRequested,
        _ => true,
      };

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final paidMode = _filter == 'PAID';
    final openBills = ref.watch(openBillsProvider);
    final bills = paidMode ? ref.watch(paidBillsProvider) : openBills;
    final status = ref.watch(realtimeProvider);
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    final list = openBills.value ?? const <BillView>[];

    // Si se llegó desde Mesas, se elige la cuenta de esa mesa una sola vez.
    if (!_pickedFromRoute && widget.tableId != null && bills.hasValue) {
      _pickedFromRoute = true;
      final match = list.firstWhereOrNull((b) => b.tableId == widget.tableId);
      if (match != null) _selected = match.id;
    }
    final visible = paidMode ? (bills.value ?? const <BillView>[]) : list.where(_matches).toList();
    final requested = list.where((b) => b.billRequested).length;

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        title: Row(children: [const Text('Caja'), const SizedBox(width: 16), Flexible(child: LiveIndicator(status: status))]),
        actions: [
          if (ref.watch(authControllerProvider).value?.employee.can('orders.create') ?? false) ...[
            AppBarAction(icon: Icons.add_shopping_cart_rounded, label: 'Nueva orden', filled: false, onPressed: () => context.go('/pos')),
            const SizedBox(width: 8),
          ],
          const _ShiftButton(),
          const SizedBox(width: 16),
        ],
      ),
      body: bills.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorView(error: error, onRetry: () => ref.invalidate(paidMode ? paidBillsProvider : openBillsProvider)),
        data: (_) {
          final listPane = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                for (final (key, label) in [
                  ('all', 'Todas · ${list.length}'),
                  ('TABLE', 'Mesas'),
                  ('TOGO', 'Para llevar'),
                  if (requested > 0) ('REQUESTED', 'Pidieron la cuenta · $requested'),
                  ('PAID', 'Pagadas hoy'),
                ])
                  ChoiceChip(
                    label: Text(label),
                    selected: _filter == key,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _filter = key),
                  ),
              ]),
            ),
            Expanded(
              child: visible.isEmpty
                  ? EmptyState(icon: Icons.point_of_sale_rounded, message: paidMode ? 'Todavía no hay cuentas cobradas hoy.' : 'No hay cuentas por cobrar.')
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: visible.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) => _BillTile(
                        bill: visible[i],
                        selected: visible[i].id == _selected,
                        onTap: () {
                          setState(() => _selected = visible[i].id);
                          if (!wide) _openNarrow(visible[i].id);
                        },
                      ),
                    ),
            ),
          ]);

          if (!wide) return listPane;
          // Pantalla mediana: la lista se angosta para que quepa la cuenta.
          return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(width: MediaQuery.sizeOf(context).width >= 1600 ? 460 : 400, child: listPane),
            VerticalDivider(width: 1, color: t.line),
            Expanded(
              child: _selected == null
                  ? const EmptyState(icon: Icons.receipt_long_rounded, message: 'Elige una cuenta para cobrarla.')
                  : BillPanel(
                      key: ValueKey(_selected),
                      billId: _selected!,
                      onSwitch: (id) => setState(() => _selected = id),
                    ),
            ),
          ]);
        },
      ),
    );
  }

  void _openNarrow(String id) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (context) => Scaffold(
        appBar: AppBar(title: const Text('Cuenta')),
        body: BillPanel(billId: id, onSwitch: (_) {}),
      ),
    ));
  }
}

class _ShiftButton extends ConsumerWidget {
  const _ShiftButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shift = ref.watch(cashShiftProvider);
    final canOpen = ref.watch(authControllerProvider).value?.employee.can('cash.shift') ?? false;
    final s = shift.value;
    if (shift.isLoading && !shift.hasValue) return const SizedBox.shrink();
    if (s == null) {
      return canOpen
          ? FilledButton.icon(
              onPressed: () => showOpenShiftDialog(context, ref),
              icon: const Icon(Icons.lock_open_rounded),
              label: const Text('Abrir caja'),
            )
          : const DmPill('Caja cerrada', tone: DmTone.warning);
    }
    final narrow = MediaQuery.sizeOf(context).width < 700;
    return OutlinedButton.icon(
      onPressed: () => showShiftSheet(context),
      icon: const Icon(Icons.point_of_sale_rounded),
      label: Text(narrow ? formatMoney(s.expectedCash) : 'Caja abierta · efectivo ${formatMoney(s.expectedCash)}'),
    );
  }
}

class _BillTile extends StatelessWidget {
  const _BillTile({required this.bill, required this.selected, required this.onTap});
  final BillView bill;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final text = Theme.of(context).textTheme;
    final icon = switch (bill.kind) {
      'TABLE' => Icons.table_restaurant_rounded,
      'PICKUP' => Icons.shopping_bag_rounded,
      'DELIVERY' => Icons.delivery_dining_rounded,
      _ => Icons.storefront_rounded,
    };
    final minutes = DateTime.now().difference(bill.openedAt).inMinutes;
    return Material(
      color: selected ? t.primarySoft : t.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: selected ? t.primary : (bill.billRequested ? t.accent : t.line), width: selected ? 2 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Icon(icon, color: t.accentText),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(bill.label, style: text.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  DmPill('${bill.itemCount} art. · ${minutes < 60 ? '$minutes min' : '${minutes ~/ 60} h'}'),
                  if (bill.billRequested) const DmPill('Pidió la cuenta', tone: DmTone.accent, icon: Icons.receipt_long_rounded),
                  if (bill.status == 'PARTIALLY_PAID') const DmPill('Pago parcial', tone: DmTone.info),
                ]),
              ]),
            ),
            const SizedBox(width: 8),
            Text(formatMoney(bill.due), style: text.titleLarge),
          ]),
        ),
      ),
    );
  }
}

// ───────────────────────── Cuenta ─────────────────────────

/// La cuenta: artículos, descuentos, pagos y totales, con las acciones de cobro.
class BillPanel extends ConsumerStatefulWidget {
  const BillPanel({super.key, required this.billId, required this.onSwitch});
  final String billId;
  final ValueChanged<String> onSwitch;

  @override
  ConsumerState<BillPanel> createState() => _BillPanelState();
}

class _BillPanelState extends ConsumerState<BillPanel> {
  bool _splitting = false;
  final Set<String> _chosen = {};
  bool _busy = false;

  BillingApi get _api => ref.read(billingApiProvider);

  Future<void> _run(Future<BillView> Function() action, {String? done, bool select = false}) async {
    setState(() => _busy = true);
    try {
      final result = await action();
      ref.invalidate(billProvider(widget.billId));
      ref.invalidate(openBillsProvider);
      if (select) widget.onSwitch(result.id);
      if (done != null && mounted) showSuccess(context, done);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pay(BillView bill) async {
    final result = await showPayDialog(context, bill);
    if (result == null || !mounted) return;
    ref.invalidate(billProvider(widget.billId));
    if (result.change > 0.004) await showChangeDialog(context, result.change);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(result.bill.status == 'PAID' ? '${bill.label}: pagada' : 'Cobro registrado · quedan ${formatMoney(result.bill.due)}'),
      action: SnackBarAction(label: 'Recibo', onPressed: () => showReceiptDialog(context, result.bill)),
      duration: const Duration(seconds: 6),
    ));
  }

  Future<void> _refund(BillPayment p) async {
    final updated = await showRefundDialog(context, p);
    if (updated == null || !mounted) return;
    ref.invalidate(billProvider(widget.billId));
    ref.invalidate(openBillsProvider);
    showSuccess(context, updated.status == 'REFUNDED' ? 'Cuenta reembolsada' : 'Reembolso registrado');
  }

  Future<void> _removeDiscount(BillDiscount d) async {
    final canDiscount = ref.read(authControllerProvider).value?.employee.can('bills.discount') ?? false;
    String? pin;
    if (!canDiscount) {
      pin = await askManagerPin(context);
      if (pin == null || pin.isEmpty) return;
    }
    await _run(() => _api.removeDiscount(d.id, managerPin: pin), done: 'Descuento quitado');
  }

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final text = Theme.of(context).textTheme;
    final async = ref.watch(billProvider(widget.billId));
    final bill = async.value;
    if (bill == null) {
      return async.hasError
          ? ErrorView(error: async.error!, onRetry: () => ref.invalidate(billProvider(widget.billId)))
          : const Center(child: CircularProgressIndicator());
    }
    final siblings = bill.tableId == null ? const <BillView>[] : (ref.watch(tableBillsProvider(bill.tableId!)).value ?? const <BillView>[]);
    final time = DateFormat.jm();

    Widget total(String label, double value, {bool bold = false, Color? color}) => Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(children: [
            Expanded(child: Text(label, style: (bold ? text.titleLarge : text.bodyLarge)?.copyWith(color: color))),
            Text(formatMoney(value), style: (bold ? text.headlineSmall : text.bodyLarge)?.copyWith(color: color)),
          ]),
        );

    final open = bill.isOpen;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(bill.label, style: text.headlineMedium)),
            if (!open)
              bill.status == 'REFUNDED'
                  ? const DmPill('Reembolsada', tone: DmTone.danger, icon: Icons.undo_rounded)
                  : DmPill(bill.status == 'PAID' ? 'Pagada' : bill.status, tone: DmTone.success, icon: Icons.check_rounded),
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 6, children: [
            DmPill(billKindLabels[bill.kind] ?? bill.kind),
            for (final o in bill.orders.where((o) => o.status != 'CANCELLED')) DmPill('Orden #${o.number}'),
            if (bill.guestCount != null) DmPill('${bill.guestCount} clientes', icon: Icons.people_alt_rounded),
            if (bill.billRequested) const DmPill('Pidió la cuenta', tone: DmTone.accent),
            ActionChip(
              avatar: Icon(bill.customerName == null ? Icons.person_add_alt_rounded : Icons.person_rounded, size: 18),
              label: Text(bill.customerName ?? 'Cliente'),
              tooltip: bill.customerName == null ? 'Identificar al cliente' : 'Cambiar o quitar el cliente',
              onPressed: () async {
                final changed = await showCustomerPicker(
                  context,
                  currentName: bill.customerName,
                  attach: (ref, id) => ref.read(customersApiProvider).attachToBill(bill.id, id),
                );
                if (!changed || !mounted) return;
                ref.invalidate(billProvider(widget.billId));
                ref.invalidate(openBillsProvider);
              },
            ),
          ]),
          if (siblings.length > 1) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (i, s) in siblings.indexed)
                ChoiceChip(
                  label: Text('Cuenta ${i + 1} · ${s.isOpen ? formatMoney(s.due) : 'pagada'}'),
                  selected: s.id == bill.id,
                  showCheckmark: false,
                  onSelected: (_) => widget.onSwitch(s.id),
                ),
            ]),
          ],
        ]),
      ),
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(24, 4, 24, 16), children: [
          if (_splitting)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: t.infoSoft, borderRadius: BorderRadius.circular(14)),
              child: Text('Marca lo que pasa a una cuenta aparte (por ejemplo, lo de un cliente).',
                  style: TextStyle(color: t.info, fontWeight: FontWeight.w600)),
            ),
          for (final i in bill.items)
            InkWell(
              onTap: _splitting ? () => setState(() => _chosen.contains(i.id) ? _chosen.remove(i.id) : _chosen.add(i.id)) : null,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (_splitting)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Icon(_chosen.contains(i.id) ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                          color: t.primary),
                    ),
                  SizedBox(width: 36, child: Text('${i.quantity}×', style: text.titleMedium?.copyWith(color: t.accentText))),
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
            ),
          if (bill.discounts.isNotEmpty) ...[
            Divider(height: 24, color: t.line),
            Text('Descuentos', style: text.titleMedium),
            for (final d in bill.discounts)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.local_offer_rounded, color: t.success),
                title: Text('${d.label} · ${d.itemName ?? 'toda la cuenta'}'),
                subtitle: Text('${d.reason}${d.authorizedBy != null ? ' · autorizó ${d.authorizedBy}' : ''}'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('−${formatMoney(d.amount)}', style: TextStyle(color: t.success, fontWeight: FontWeight.w700)),
                  if (open)
                    IconButton(
                      tooltip: 'Quitar',
                      onPressed: _busy ? null : () => _removeDiscount(d),
                      icon: const Icon(Icons.close_rounded),
                    ),
                ]),
              ),
          ],
          if (bill.couponCode != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.confirmation_number_rounded, color: t.success),
              title: Text('Cupón ${bill.couponCode}'),
              subtitle: bill.couponName == null || bill.couponName == 'Cupón ${bill.couponCode}' ? null : Text(bill.couponName!),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(bill.couponAmount > 0 ? '−${formatMoney(bill.couponAmount)}' : '', style: TextStyle(color: t.success, fontWeight: FontWeight.w700)),
                if (open)
                  IconButton(
                    tooltip: 'Quitar cupón',
                    onPressed: _busy ? null : () => _run(() => _api.removeCoupon(bill.id), done: 'Cupón quitado'),
                    icon: const Icon(Icons.close_rounded),
                  ),
              ]),
            ),
          if (bill.payments.isNotEmpty) ...[
            Divider(height: 24, color: t.line),
            Text('Pagos', style: text.titleMedium),
            for (final p in bill.payments.where((p) => p.status == 'SUCCEEDED'))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(p.method == 'CASH' ? Icons.payments_rounded : Icons.credit_card_rounded, color: t.accentText),
                title: Text('${paymentMethodLabels[p.method] ?? p.method}${p.reference != null ? ' · ${p.reference}' : ''}'),
                subtitle: Text([
                  time.format(p.createdAt),
                  if (p.employee != null) p.employee!,
                  if (p.tipAmount > 0) 'propina ${formatMoney(p.tipAmount)}',
                  if ((p.changeGiven ?? 0) > 0) 'cambio ${formatMoney(p.changeGiven!)}',
                ].join(' · ')),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(formatMoney(p.amount), style: text.titleMedium),
                  if (p.refundable > 0.004)
                    IconButton(tooltip: 'Reembolsar', onPressed: _busy ? null : () => _refund(p), icon: const Icon(Icons.undo_rounded)),
                ]),
              ),
            for (final p in bill.payments.where((p) => p.status == 'SUCCEEDED'))
              for (final r in p.refunds)
                ListTile(
                  contentPadding: const EdgeInsets.only(left: 40),
                  dense: true,
                  leading: Icon(Icons.undo_rounded, color: t.danger, size: 20),
                  title: Text('Reembolso · ${paymentMethodLabels[p.method] ?? p.method}'),
                  subtitle: Text([time.format(r.createdAt), r.reason, if (r.employee != null) r.employee!].join(' · ')),
                  trailing: Text('−${formatMoney(r.amount)}', style: text.titleSmall?.copyWith(color: t.danger)),
                ),
          ],
          Divider(height: 28, color: t.line),
          total('Subtotal', bill.subtotal),
          if (bill.discountTotal > 0) total('Descuentos', -bill.discountTotal, color: t.success),
          total('Impuestos', bill.taxTotal),
          if (bill.deliveryFee > 0) total('Envío', bill.deliveryFee),
          if (bill.tipTotal > 0) total('Propina', bill.tipTotal),
          total('Total', bill.total, bold: true),
          if (bill.amountPaid > 0) ...[
            total('Pagado', bill.amountPaid, color: t.success),
            total('Por cobrar', bill.due, bold: true, color: bill.due > 0 ? t.accentText : t.success),
          ],
          if (bill.refundedTotal > 0) total('Reembolsado', -bill.refundedTotal, color: t.danger),
        ]),
      ),
      if (!open)
        Container(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
          decoration: BoxDecoration(color: t.surface, border: Border(top: BorderSide(color: t.line))),
          child: Wrap(alignment: WrapAlignment.end, spacing: 10, runSpacing: 10, children: [
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(200, 52)),
              onPressed: () => showReceiptDialog(context, bill),
              icon: const Icon(Icons.receipt_rounded),
              label: const Text('Recibo'),
            ),
          ]),
        ),
      if (open)
        Container(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
          decoration: BoxDecoration(color: t.surface, border: Border(top: BorderSide(color: t.line))),
          child: _splitting
              ? Row(children: [
                  TextButton(
                    onPressed: () => setState(() {
                      _splitting = false;
                      _chosen.clear();
                    }),
                    child: const Text('Cancelar'),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _chosen.isEmpty || _chosen.length == bill.items.length || _busy
                        ? null
                        : () async {
                            final ids = _chosen.toList();
                            setState(() {
                              _splitting = false;
                              _chosen.clear();
                            });
                            await _run(() => _api.split(bill.id, ids), done: 'Cuenta dividida', select: true);
                          },
                    icon: const Icon(Icons.call_split_rounded),
                    label: Text('Pasar ${_chosen.length} a otra cuenta'),
                  ),
                ])
              : Wrap(alignment: WrapAlignment.end, spacing: 10, runSpacing: 10, children: [
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => showCheckDialog(context, bill),
                    icon: const Icon(Icons.receipt_long_rounded),
                    label: const Text('Cuenta'),
                  ),
                  // Ya pagaron una parte: el recibo de ese pago.
                  if (bill.hasPayments)
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => showReceiptDialog(context, bill),
                      icon: const Icon(Icons.receipt_rounded),
                      label: const Text('Recibo'),
                    ),
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () async {
                            final updated = await showDiscountDialog(context, bill);
                            if (updated != null) {
                              ref.invalidate(billProvider(widget.billId));
                              ref.invalidate(openBillsProvider);
                            }
                          },
                    icon: const Icon(Icons.local_offer_rounded),
                    label: const Text('Descuento'),
                  ),
                  if (bill.couponCode == null)
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () async {
                              final code = await _askCoupon(context);
                              if (code != null) await _run(() => _api.applyCoupon(bill.id, code), done: 'Cupón aplicado');
                            },
                      icon: const Icon(Icons.confirmation_number_rounded),
                      label: const Text('Cupón'),
                    ),
                  if (bill.tableId != null && !bill.hasPayments && bill.items.length > 1)
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => setState(() => _splitting = true),
                      icon: const Icon(Icons.call_split_rounded),
                      label: const Text('Dividir'),
                    ),
                  if (siblings.length > 1 && !bill.hasPayments)
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () {
                              final target = siblings.firstWhereOrNull((s) => s.id != bill.id && s.isOpen);
                              if (target != null) {
                                _run(() => _api.merge(bill.id, target.id), done: 'Cuentas juntas', select: true);
                              }
                            },
                      icon: const Icon(Icons.merge_rounded),
                      label: const Text('Juntar'),
                    ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size(220, 56), textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    onPressed: _busy || bill.due <= 0 ? null : () => _pay(bill),
                    icon: const Icon(Icons.point_of_sale_rounded),
                    label: Text('Cobrar ${formatMoney(bill.due)}'),
                  ),
                ]),
        ),
    ]);
  }
}

/// Pide el código del cupón que da el cliente.
Future<String?> _askCoupon(BuildContext context) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      scrollable: true,
      title: const Text('Cupón'),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.characters,
        decoration: const InputDecoration(labelText: 'Código del cupón', hintText: 'VERANO10'),
        onSubmitted: (v) => Navigator.pop(context, v.trim().isEmpty ? null : v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim().isEmpty ? null : controller.text.trim()), child: const Text('Aplicar')),
      ],
    ),
  );
}
