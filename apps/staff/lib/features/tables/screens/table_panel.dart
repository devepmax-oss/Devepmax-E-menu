import 'package:collection/collection.dart';
import 'package:devepmax_ui/devepmax_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/auth/auth_controller.dart';
import '../../../core/ui/feedback.dart';
import '../../billing/screens/receipt_dialog.dart' show ChecksDialog;
import '../../customers/data/customers_api.dart';
import '../../customers/screens/customer_picker.dart';
import '../../orders/data/orders_api.dart';
import '../../orders/data/orders_models.dart';
import '../../orders/screens/orders_screen.dart' show showOrderDetail;
import '../data/tables_api.dart';
import '../data/tables_models.dart';
import 'tables_screen.dart' show elapsedLabel;

/// Panel lateral de una mesa: quiénes están, sus pedidos, la cuenta y qué hacer.
Future<void> showTablePanel(BuildContext context, String tableId) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Cerrar',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (context, _, __) => Align(alignment: Alignment.centerRight, child: _TablePanel(tableId: tableId)),
    transitionBuilder: (context, animation, _, child) => SlideTransition(
      position: Tween(begin: const Offset(1, 0), end: Offset.zero)
          .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: child,
    ),
  );
}

DmTone tableTone(String status) => switch (status) {
      'OCCUPIED' => DmTone.primary,
      'RESERVED' => DmTone.info,
      'CLEANING' => DmTone.warning,
      _ => DmTone.success,
    };

class _TablePanel extends ConsumerStatefulWidget {
  const _TablePanel({required this.tableId});
  final String tableId;

  @override
  ConsumerState<_TablePanel> createState() => _TablePanelState();
}

class _TablePanelState extends ConsumerState<_TablePanel> {
  bool _busy = false;

  TablesApi get _api => ref.read(tablesApiProvider);

  Future<void> _act(Future<TableView> Function() action, {String? done}) async {
    setState(() => _busy = true);
    try {
      final updated = await action();
      ref.read(floorProvider.notifier).apply(updated);
      if (done != null && mounted) showSuccess(context, done);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resolve(String requestId, String status) async {
    setState(() => _busy = true);
    try {
      await _api.resolveRequest(requestId, status);
      // La mesa llega actualizada por tiempo real; por si acaso, se refresca.
      await ref.read(floorProvider.notifier).refresh();
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deliver(OrderView order) async {
    setState(() => _busy = true);
    try {
      await ref.read(ordersApiProvider).complete(order.id);
      await ref.read(ordersBoardProvider.notifier).refresh();
      if (mounted) showSuccess(context, 'Pedido #${order.number} entregado');
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _seat(TableView table) async {
    final guests = await showDialog<int>(
      context: context,
      builder: (_) => _GuestsDialog(initial: table.session?.guestCount ?? suggestedGuests(table.seats)),
    );
    if (guests == null) return;
    await _act(() => _api.open(table.id, guests),
        done: table.session == null ? 'Mesa ${table.label}: $guests ${guests == 1 ? 'cliente' : 'clientes'}' : null);
  }

  Future<void> _close(TableView table) async {
    setState(() => _busy = true);
    try {
      final updated = await _api.close(table.id);
      ref.read(floorProvider.notifier).apply(updated);
      if (mounted) showSuccess(context, 'Mesa ${table.label} cerrada · queda por limpiar');
    } on ApiException catch (error) {
      if (!mounted) return;
      final unpaid = error.statusCode == 409 && error.message.contains('pendientes');
      if (!unpaid) {
        showError(context, error);
        return;
      }
      final ok = await confirm(
        context,
        title: 'La cuenta no está saldada',
        message: '${error.message}.\n\n¿Cerrar la mesa de todas formas? Quedará registrado que se cerró con saldo.',
        confirmLabel: 'Cerrar igual',
      );
      if (ok) await _act(() => _api.close(table.id, force: true), done: 'Mesa ${table.label} cerrada con saldo');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final text = Theme.of(context).textTheme;
    final areas = ref.watch(floorProvider).value ?? const <AreaView>[];
    final area = areas.firstWhereOrNull((a) => a.tables.any((x) => x.id == widget.tableId));
    final table = area?.tables.firstWhereOrNull((x) => x.id == widget.tableId);

    if (table == null) {
      return Material(
        color: t.surface,
        child: SizedBox(
          width: MediaQuery.sizeOf(context).width.clamp(0, 440).toDouble(),
          height: double.infinity,
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Esta mesa ya no está en el plano.'),
              const SizedBox(height: 12),
              FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
            ]),
          ),
        ),
      );
    }

    final s = table.session;
    final status = table.displayStatus;
    final orders = (ref.watch(ordersBoardProvider).value?.orders ?? const <OrderView>[])
        .where((o) => o.tableLabel == table.label && o.fulfillmentType == 'DINE_IN')
        .toList();
    final time = DateFormat.jm();

    Widget stat(String label, String value, {IconData? icon, VoidCallback? onEdit}) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: t.surface2, borderRadius: BorderRadius.circular(16)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                if (icon != null) ...[Icon(icon, size: 16, color: t.muted), const SizedBox(width: 6)],
                Expanded(child: Text(label, style: text.bodySmall?.copyWith(color: t.muted))),
                if (onEdit != null)
                  InkWell(onTap: onEdit, child: Icon(Icons.edit_rounded, size: 16, color: t.accentText)),
              ]),
              const SizedBox(height: 4),
              Text(value, style: text.titleLarge),
            ]),
          ),
        );

    Widget money(String label, double value, {Color? color, bool bold = false}) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(children: [
            Expanded(child: Text(label, style: (bold ? text.titleMedium : text.bodyMedium)?.copyWith(color: color))),
            Text(formatMoney(value), style: (bold ? text.titleLarge : text.bodyMedium)?.copyWith(color: color)),
          ]),
        );

    final canCharge = ref.watch(authControllerProvider).value?.employee.can('payments.take') ?? false;
    final canOrder = ref.watch(authControllerProvider).value?.employee.can('orders.create') ?? false;
    final me = ref.watch(authControllerProvider).value?.employee;
    final actions = <Widget>[
      if (s != null && s.total > 0 && !canCharge)
        OutlinedButton.icon(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => ChecksDialog(title: 'Cuenta · Mesa ${table.label}', load: (ref) => ref.read(tablesApiProvider).checks(table.id)),
          ),
          icon: const Icon(Icons.receipt_long_rounded),
          label: const Text('Cuenta'),
        ),
      if (canOrder && status != 'CLEANING')
        FilledButton.icon(
          onPressed: () {
            final router = GoRouter.of(context);
            Navigator.pop(context);
            router.go('/pos?table=${table.id}');
          },
          icon: const Icon(Icons.add_shopping_cart_rounded),
          label: Text(s == null ? 'Tomar pedido' : 'Agregar pedido'),
        ),
      if (s != null) ...[
        if (canCharge && s.total > 0)
          FilledButton.tonalIcon(
            onPressed: () {
              final router = GoRouter.of(context);
              Navigator.pop(context);
              router.go('/billing?table=${table.id}');
            },
            icon: const Icon(Icons.point_of_sale_rounded),
            label: Text(s.due > 0 ? 'Cobrar ${formatMoney(s.due)}' : 'Ver la cuenta'),
          ),
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _seat(table),
          icon: const Icon(Icons.people_alt_rounded),
          label: const Text('Clientes'),
        ),
        if (s.total > 0 || s.customerName != null)
          OutlinedButton.icon(
            onPressed: _busy
                ? null
                : () => showCustomerPicker(
                      context,
                      currentName: s.customerName,
                      attach: (ref, id) => ref.read(customersApiProvider).attachToTable(table.id, id),
                    ),
            icon: Icon(s.customerName == null ? Icons.person_add_alt_rounded : Icons.person_rounded),
            label: Text(s.customerName ?? 'Cliente'),
          ),
        FilledButton.icon(
          onPressed: _busy ? null : () => _close(table),
          icon: const Icon(Icons.logout_rounded),
          label: const Text('Cerrar mesa'),
        ),
      ] else ...[
        if (status == 'AVAILABLE')
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _act(() => _api.setStatus(table.id, 'RESERVED'), done: 'Mesa ${table.label} reservada'),
            icon: const Icon(Icons.event_available_rounded),
            label: const Text('Reservar'),
          ),
        if (status == 'RESERVED')
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _act(() => _api.setStatus(table.id, 'AVAILABLE')),
            icon: const Icon(Icons.event_busy_rounded),
            label: const Text('Quitar reserva'),
          ),
        if (status == 'CLEANING' || status == 'OCCUPIED')
          FilledButton.icon(
            onPressed: _busy ? null : () => _act(() => _api.setStatus(table.id, 'AVAILABLE'), done: 'Mesa ${table.label} lista'),
            icon: const Icon(Icons.cleaning_services_rounded),
            label: const Text('Lista, ya está limpia'),
          ),
        if (status != 'CLEANING' && status != 'OCCUPIED')
          FilledButton.icon(
            onPressed: _busy ? null : () => _seat(table),
            icon: const Icon(Icons.event_seat_rounded),
            label: const Text('Sentar clientes'),
          ),
      ],
    ];

    return Material(
      color: t.surface,
      child: SizedBox(
        width: MediaQuery.sizeOf(context).width.clamp(0, 440).toDouble(),
        height: double.infinity,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 12, 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Mesa ${table.label}', style: text.headlineMedium),
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, runSpacing: 6, children: [
                    DmPill(tableStatusLabels[status] ?? status, tone: tableTone(status)),
                    DmPill('${table.seats} lugares', icon: Icons.chair_rounded),
                    if (area != null) DmPill(area.name),
                  ]),
                ]),
              ),
              IconButton(tooltip: 'Cerrar', icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
            ]),
          ),
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(24, 8, 24, 24), children: [
              if (s != null) ...[
                Row(children: [
                  stat('Clientes', '${s.guestCount ?? '—'}', icon: Icons.people_alt_rounded, onEdit: _busy ? null : () => _seat(table)),
                  const SizedBox(width: 10),
                  stat('Tiempo', elapsedLabel(s.openedAt), icon: Icons.schedule_rounded),
                  const SizedBox(width: 10),
                  stat('Pedidos', '${s.orderCount}', icon: Icons.receipt_long_rounded),
                ]),
                const SizedBox(height: 6),
                Text('Sentados a las ${time.format(s.openedAt)}'
                    '${s.activeOrders > 0 ? ' · ${s.activeOrders} en preparación' : ''}',
                    style: text.bodySmall),
                const SizedBox(height: 10),
                Row(children: [
                  Icon(Icons.person_rounded, size: 18, color: t.muted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      s.waiterId == null
                          ? 'Sin mesero asignado'
                          : s.waiterId == me?.id
                              ? 'La atiendes tú'
                              : 'La atiende ${s.waiterName ?? 'otro mesero'}',
                      style: text.bodyMedium,
                    ),
                  ),
                  if (s.waiterId != me?.id)
                    TextButton(
                      onPressed: _busy ? null : () => _act(() => _api.assignWaiter(table.id), done: 'Ahora atiendes la mesa ${table.label}'),
                      child: const Text('Tomar mesa'),
                    ),
                ]),
                if (s.requests.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  for (final r in s.requests)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                      decoration: BoxDecoration(color: t.accentSoft, borderRadius: BorderRadius.circular(14)),
                      child: Row(children: [
                        Icon(r.type == 'REQUEST_BILL' ? Icons.receipt_long_rounded : Icons.notifications_active_rounded,
                            color: t.accentText),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(serviceRequestLabels[r.type] ?? r.type, style: text.titleSmall?.copyWith(color: t.accentText)),
                            Text(
                              r.status == 'ACKNOWLEDGED'
                                  ? 'Alguien ya va en camino'
                                  : 'hace ${elapsedLabel(r.createdAt).replaceAll('Recién', 'un momento')}',
                              style: text.bodySmall?.copyWith(color: t.accentText),
                            ),
                          ]),
                        ),
                        if (r.status == 'OPEN')
                          TextButton(
                            onPressed: _busy ? null : () => _resolve(r.id, 'ACKNOWLEDGED'),
                            child: const Text('Voy'),
                          ),
                        FilledButton(
                          onPressed: _busy ? null : () => _resolve(r.id, 'DONE'),
                          child: const Text('Atendido'),
                        ),
                      ]),
                    ),
                ],
                const SizedBox(height: 20),
                Text('Cuenta', style: text.titleMedium),
                money('Total', s.total),
                if (s.paid > 0) money('Pagado', s.paid, color: t.success),
                Divider(height: 20, color: t.line),
                money('Pendiente', s.due, bold: true, color: s.due > 0 ? null : t.success),
              ] else
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    switch (status) {
                      'RESERVED' => 'Reservada. Cuando lleguen los clientes, siéntalos aquí.',
                      'CLEANING' => 'Los clientes se fueron. Márcala lista cuando esté limpia.',
                      _ => 'Libre. Sienta a los clientes para abrir la cuenta de la mesa.',
                    },
                    style: text.bodyLarge?.copyWith(color: t.muted),
                  ),
                ),
              if (orders.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text('Pedidos en curso', style: text.titleMedium),
                const SizedBox(height: 6),
                for (final o in orders)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    color: o.status == 'READY' ? t.successSoft : null,
                    child: ListTile(
                      onTap: () => showOrderDetail(context, o),
                      title: Text('#${o.number} · ${o.itemCount} ${o.itemCount == 1 ? 'artículo' : 'artículos'}'),
                      subtitle: Text(o.status == 'READY' ? '¡Listo! Llévalo a la mesa' : (orderStatusLabels[o.status] ?? o.status),
                          style: o.status == 'READY' ? TextStyle(color: t.success, fontWeight: FontWeight.w700) : null),
                      trailing: o.status == 'READY' && canOrder
                          ? FilledButton(onPressed: _busy ? null : () => _deliver(o), child: const Text('Entregado'))
                          : Text(formatMoney(o.total), style: text.titleMedium),
                    ),
                  ),
              ],
              const SizedBox(height: 20),
              Text('Tablet de la mesa', style: text.titleMedium),
              const SizedBox(height: 6),
              if (table.tablets.isEmpty)
                Text('Sin tablet. Asígnala en Dispositivos.', style: text.bodyMedium?.copyWith(color: t.muted))
              else
                for (final d in table.tablets)
                  Row(children: [
                    Icon(Icons.tablet_android_rounded, size: 18, color: t.muted),
                    const SizedBox(width: 8),
                    Expanded(child: Text(d.name)),
                    if (d.lastSeenAt != null)
                      Text('vista ${DateFormat.MMMd().add_jm().format(d.lastSeenAt!)}', style: text.bodySmall),
                  ]),
            ]),
          ),
          if (actions.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: t.line))),
              child: Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: actions),
            ),
        ]),
      ),
    );
  }
}

/// Sugerencia de clientes al sentar: la mitad de los lugares (mínimo 1).
int suggestedGuests(int seats) => seats <= 2 ? seats : (seats / 2).ceil();

class _GuestsDialog extends StatefulWidget {
  const _GuestsDialog({required this.initial});
  final int initial;

  @override
  State<_GuestsDialog> createState() => _GuestsDialogState();
}

class _GuestsDialogState extends State<_GuestsDialog> {
  late int _n = widget.initial.clamp(1, 50);

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    return AlertDialog(
      scrollable: true,
      title: const Text('¿Cuántos clientes?'),
      content: SizedBox(
        width: 360,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton.filledTonal(
              iconSize: 28,
              onPressed: _n > 1 ? () => setState(() => _n--) : null,
              icon: const Icon(Icons.remove_rounded),
            ),
            SizedBox(
              width: 96,
              child: Text('$_n',
                  textAlign: TextAlign.center,
                  style: brandFont(t.headingFamily, weight: t.headingWeight, size: 48, color: t.text)),
            ),
            IconButton.filledTonal(
              iconSize: 28,
              onPressed: _n < 50 ? () => setState(() => _n++) : null,
              icon: const Icon(Icons.add_rounded),
            ),
          ]),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
            for (var i = 1; i <= 8; i++)
              ChoiceChip(
                label: Text('$i'),
                selected: _n == i,
                showCheckmark: false,
                onSelected: (_) => setState(() => _n = i),
              ),
          ]),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(context, _n), child: const Text('Listo')),
      ],
    );
  }
}
