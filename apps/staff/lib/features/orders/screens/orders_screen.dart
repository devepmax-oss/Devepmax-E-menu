import 'dart:async';

import 'package:devepmax_ui/devepmax_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/realtime/realtime.dart';
import '../../../core/ui/feedback.dart';
import '../../menu/widgets/common.dart';
import '../data/orders_api.dart';
import '../data/orders_models.dart';

/// Columnas del tablero.
enum _Lane { approval, kitchen, ready, onTheWay }

_Lane? _laneOf(OrderView o) => switch (o.status) {
      'PENDING_APPROVAL' => _Lane.approval,
      'PLACED' || 'ACCEPTED' || 'PREPARING' => _Lane.kitchen,
      'READY' => _Lane.ready,
      'OUT_FOR_DELIVERY' => _Lane.onTheWay,
      _ => null,
    };

const _laneTitles = {
  _Lane.approval: 'Por aprobar',
  _Lane.kitchen: 'En cocina',
  _Lane.ready: 'Listas para entregar',
  _Lane.onTheWay: 'En camino',
};

/// Filtro por origen de la orden.
const _channelFilters = <String, String>{'all': 'Todas', 'POS': 'Caja', 'TABLET': 'Mesa', 'ONLINE': 'Web'};

class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  String _view = 'active';
  String _channel = 'all';
  Timer? _clock;
  Timer? _todayDebounce;

  @override
  void initState() {
    super.initState();
    // Los minutos transcurridos se actualizan solos.
    _clock = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _todayDebounce?.cancel();
    super.dispose();
  }

  bool _matches(OrderView o) => _channel == 'all' || o.channel == _channel;

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final status = ref.watch(realtimeProvider);
    final board = ref.watch(ordersBoardProvider);
    final activeCount = board.value?.orders.length ?? 0;

    // En la vista "Hoy", cualquier cambio en tiempo real refresca la lista (agrupado).
    ref.listen(ordersBoardProvider, (_, __) {
      if (_view != 'today') return;
      _todayDebounce?.cancel();
      _todayDebounce = Timer(const Duration(milliseconds: 600), () => ref.invalidate(todayOrdersProvider));
    });

    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          const Text('Órdenes'),
          const SizedBox(width: 16),
          _LiveIndicator(status: status),
        ]),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              ref.read(ordersBoardProvider.notifier).refresh();
              ref.invalidate(todayOrdersProvider);
            },
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Wrap(spacing: 16, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'active', label: Text('En curso · $activeCount')),
                const ButtonSegment(value: 'today', label: Text('Hoy')),
              ],
              selected: {_view},
              showSelectedIcon: false,
              onSelectionChanged: (v) => setState(() => _view = v.first),
            ),
            Wrap(spacing: 8, children: [
              for (final e in _channelFilters.entries)
                ChoiceChip(
                  label: Text(e.value),
                  selected: _channel == e.key,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _channel = e.key),
                ),
            ]),
          ]),
        ),
        Expanded(
          child: _view == 'active'
              ? board.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (error, _) => ErrorView(error: error, onRetry: () => ref.invalidate(ordersBoardProvider)),
                  data: (b) => _Board(
                    orders: b.orders.where(_matches).toList(),
                    arrivedAt: b.arrivedAt,
                  ),
                )
              : _TodayList(filter: _matches),
        ),
      ]),
      backgroundColor: t.bg,
    );
  }
}

class _LiveIndicator extends StatelessWidget {
  const _LiveIndicator({required this.status});
  final RealtimeStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, tone) = switch (status) {
      RealtimeStatus.live => ('En vivo', DmTone.success),
      RealtimeStatus.connecting => ('Conectando…', DmTone.warning),
      RealtimeStatus.reconnecting => ('Reconectando…', DmTone.warning),
      RealtimeStatus.offline => ('Sin conexión', DmTone.danger),
    };
    return DmPill(label, tone: tone, icon: status == RealtimeStatus.live ? Icons.circle : Icons.sync_rounded);
  }
}

// ───────────────────────── Tablero ─────────────────────────

class _Board extends StatelessWidget {
  const _Board({required this.orders, required this.arrivedAt});
  final List<OrderView> orders;
  final Map<String, DateTime> arrivedAt;

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return const EmptyState(
        icon: Icons.receipt_long_rounded,
        message: 'No hay órdenes en curso.\nLas nuevas aparecen aquí solas, al instante.',
      );
    }
    final byLane = <_Lane, List<OrderView>>{};
    for (final o in orders) {
      final lane = _laneOf(o);
      if (lane != null) byLane.putIfAbsent(lane, () => []).add(o);
    }
    final lanes = [
      if (byLane.containsKey(_Lane.approval)) _Lane.approval,
      _Lane.kitchen,
      _Lane.ready,
      if (byLane.containsKey(_Lane.onTheWay)) _Lane.onTheWay,
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < lanes.length; i++) ...[
          if (i > 0) const SizedBox(width: 16),
          Expanded(child: _LaneColumn(lane: lanes[i], orders: byLane[lanes[i]] ?? const [], arrivedAt: arrivedAt)),
        ],
      ]),
    );
  }
}

class _LaneColumn extends StatelessWidget {
  const _LaneColumn({required this.lane, required this.orders, required this.arrivedAt});
  final _Lane lane;
  final List<OrderView> orders;
  final Map<String, DateTime> arrivedAt;

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(color: t.rail, borderRadius: BorderRadius.circular(24), border: Border.all(color: t.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
          child: Row(children: [
            Expanded(child: Text(_laneTitles[lane]!, style: text.titleLarge)),
            DmPill('${orders.length}', tone: lane == _Lane.ready ? DmTone.success : DmTone.neutral),
          ]),
        ),
        Expanded(
          child: orders.isEmpty
              ? Center(child: Text('Nada por aquí', style: text.bodySmall))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                  itemCount: orders.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) => _OrderCard(order: orders[i], arrivedAt: arrivedAt[orders[i].id]),
                ),
        ),
      ]),
    );
  }
}

/// Minutos desde que entró a cocina, con su tono (a tiempo / atención / atrasada).
(String, DmTone) _elapsed(OrderView o) {
  final minutes = DateTime.now().difference(o.startedAt).inMinutes;
  final label = minutes < 1 ? 'Recién' : '$minutes min';
  if (o.status == 'READY' || o.status == 'PENDING_APPROVAL') return (label, DmTone.neutral);
  if (minutes >= 25) return (label, DmTone.danger);
  if (minutes >= 15) return (label, DmTone.warning);
  return (label, DmTone.success);
}

class _OrderCard extends ConsumerWidget {
  const _OrderCard({required this.order, this.arrivedAt});
  final OrderView order;
  final DateTime? arrivedAt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = BrandTokens.of(context);
    final text = Theme.of(context).textTheme;
    final isNew = arrivedAt != null && DateTime.now().difference(arrivedAt!) < const Duration(seconds: 12);
    final (elapsed, elapsedTone) = _elapsed(order);
    final items = order.activeItems;
    final employee = ref.watch(authControllerProvider).value?.employee;

    return TweenAnimationBuilder<double>(
      key: ValueKey('${order.id}-$isNew'),
      tween: Tween(begin: isNew ? 0 : 1, end: 1),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, (1 - v) * -12), child: child),
      ),
      child: Material(
        color: t.surface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => showOrderDetail(context, order),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: isNew ? t.accent : t.line, width: isNew ? 2 : 1),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('#${order.number}', style: text.headlineMedium),
                const SizedBox(width: 10),
                if (isNew) const Padding(padding: EdgeInsets.only(top: 6), child: DmPill('Nueva', tone: DmTone.accent)),
                const Spacer(),
                DmPill(elapsed, tone: elapsedTone, icon: Icons.schedule_rounded),
              ]),
              const SizedBox(height: 4),
              Row(children: [
                Expanded(child: Text(order.where, style: text.titleSmall, overflow: TextOverflow.ellipsis)),
                Text(channelLabels[order.channel] ?? order.channel, style: text.bodySmall),
              ]),
              const SizedBox(height: 12),
              for (final item in items.take(4))
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: '${item.quantity}× ', style: TextStyle(fontWeight: FontWeight.w800, color: t.accentText)),
                      TextSpan(text: item.name),
                    ]),
                    style: text.bodyMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (items.length > 4) Text('+${items.length - 4} más', style: text.bodySmall),
              if (order.fulfillmentType == 'DELIVERY') ...[
                const SizedBox(height: 8),
                order.delivery == null
                    ? const DmPill('Sin repartidor', tone: DmTone.warning, icon: Icons.delivery_dining_rounded)
                    : DmPill(
                        '${order.delivery!.driverName} · ${deliveryStatusLabels[order.delivery!.status] ?? order.delivery!.status}',
                        tone: order.delivery!.status == 'PENDING' ? DmTone.warning : DmTone.info,
                        icon: Icons.delivery_dining_rounded,
                      ),
              ],
              if (order.tickets.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final ticket in order.tickets)
                    DmPill(
                      '${ticket.stationName} · ${ticketStatusLabels[ticket.status] ?? ticket.status}',
                      color: ticket.status == 'READY' ? t.success : colorFromHex(ticket.stationColor, fallback: t.muted),
                    ),
                ]),
              ],
              const SizedBox(height: 14),
              Row(children: [
                Text(formatMoney(order.total), style: text.titleLarge),
                if (order.isPaid) ...[
                  const SizedBox(width: 8),
                  const DmPill('Pagado', tone: DmTone.success),
                ],
                const Spacer(),
                if (order.status == 'PENDING_APPROVAL' && (employee?.can('orders.approve') ?? false))
                  _ActionButton(label: 'Aprobar', run: (api) => api.approve(order.id)),
                if (order.status == 'READY' && (employee?.can('orders.create') ?? false))
                  _ActionButton(label: 'Entregar', run: (api) => api.complete(order.id)),
                if (employee?.can('kitchen.operate') ?? false) _KitchenButton(order: order),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Botón de acción que muestra el progreso y aplica la respuesta al tablero.
class _ActionButton extends ConsumerStatefulWidget {
  const _ActionButton({required this.label, required this.run});
  final String label;
  final Future<OrderView> Function(OrdersApi api) run;

  @override
  ConsumerState<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends ConsumerState<_ActionButton> {
  bool _busy = false;

  Future<void> _go() async {
    setState(() => _busy = true);
    try {
      final updated = await widget.run(ref.read(ordersApiProvider));
      ref.read(ordersBoardProvider.notifier).apply(updated);
      ref.invalidate(orderByIdProvider(updated.id));
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: _busy ? null : _go,
      child: _busy
          ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : Text(widget.label),
    );
  }
}

/// Siguiente paso de cocina para toda la orden: "Empezar" (los tickets nuevos pasan a
/// preparando) o "Listo" (los que se preparan pasan a listos). Sirve mientras no haya
/// pantalla de cocina, o para restaurantes pequeños que no la usan.
class _KitchenButton extends ConsumerStatefulWidget {
  const _KitchenButton({required this.order, this.expanded = false});
  final OrderView order;
  final bool expanded;

  @override
  ConsumerState<_KitchenButton> createState() => _KitchenButtonState();
}

class _KitchenButtonState extends ConsumerState<_KitchenButton> {
  bool _busy = false;

  ({String label, String to, List<OrderTicket> tickets})? _next() {
    if (!const {'PLACED', 'ACCEPTED', 'PREPARING'}.contains(widget.order.status)) return null;
    final waiting = widget.order.tickets.where((t) => t.status == 'NEW' || t.status == 'ACCEPTED').toList();
    if (waiting.isNotEmpty) return (label: 'Empezar', to: 'PREPARING', tickets: waiting);
    final cooking = widget.order.tickets.where((t) => t.status == 'PREPARING').toList();
    if (cooking.isNotEmpty) return (label: 'Listo', to: 'READY', tickets: cooking);
    return null;
  }

  Future<void> _go(({String label, String to, List<OrderTicket> tickets}) next) async {
    setState(() => _busy = true);
    try {
      final api = ref.read(ordersApiProvider);
      for (final ticket in next.tickets) {
        await api.moveTicket(ticket.id, next.to);
      }
      // El tiempo real trae la orden actualizada; esto es respaldo por si el socket está caído.
      await ref.read(ordersBoardProvider.notifier).refresh();
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final next = _next();
    if (next == null) return const SizedBox.shrink();
    final child = _busy
        ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
        : Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(next.to == 'READY' ? Icons.check_rounded : Icons.local_fire_department_rounded, size: 18),
            const SizedBox(width: 6),
            Text(widget.expanded ? (next.to == 'READY' ? 'Marcar lista' : 'Empezar a preparar') : next.label),
          ]);
    return next.to == 'READY'
        ? FilledButton(onPressed: _busy ? null : () => _go(next), child: child)
        : FilledButton.tonal(onPressed: _busy ? null : () => _go(next), child: child);
  }
}

// ───────────────────────── Hoy ─────────────────────────

class _TodayList extends ConsumerWidget {
  const _TodayList({required this.filter});
  final bool Function(OrderView) filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = BrandTokens.of(context);
    final text = Theme.of(context).textTheme;
    final today = ref.watch(todayOrdersProvider);
    final time = DateFormat.jm();

    return today.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => ErrorView(error: error, onRetry: () => ref.invalidate(todayOrdersProvider)),
      data: (all) {
        final orders = all.where(filter).toList();
        if (orders.isEmpty) {
          return const EmptyState(icon: Icons.today_rounded, message: 'Todavía no hay órdenes hoy.');
        }
        final sales = orders.where((o) => o.status != 'CANCELLED').fold<double>(0, (s, o) => s + o.total);
        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text('${orders.length} órdenes · ${formatMoney(sales)} sin contar canceladas', style: text.bodySmall),
            ),
            DmPanel(
              padding: EdgeInsets.zero,
              child: Column(children: [
                for (var i = 0; i < orders.length; i++) ...[
                  if (i > 0) Divider(color: t.line),
                  ListTile(
                    onTap: () => showOrderDetail(context, orders[i]),
                    leading: SizedBox(width: 56, child: Text('#${orders[i].number}', style: text.titleLarge)),
                    title: Text(orders[i].where, style: text.titleSmall),
                    subtitle: Text(
                      '${time.format(orders[i].createdAt)} · ${channelLabels[orders[i].channel] ?? orders[i].channel} · '
                      '${orders[i].orderedCount} productos',
                      style: text.bodySmall,
                    ),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      _StatusPill(status: orders[i].status),
                      const SizedBox(width: 16),
                      SizedBox(
                        width: 90,
                        child: Text(formatMoney(orders[i].total), textAlign: TextAlign.right, style: text.titleSmall),
                      ),
                    ]),
                  ),
                ],
              ]),
            ),
          ],
        );
      },
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final tone = switch (status) {
      'COMPLETED' => DmTone.success,
      'CANCELLED' => DmTone.danger,
      'READY' => DmTone.success,
      'PENDING_APPROVAL' || 'PENDING_PAYMENT' => DmTone.warning,
      _ => DmTone.primary,
    };
    return DmPill(orderStatusLabels[status] ?? status, tone: tone);
  }
}

// ───────────────────────── Detalle ─────────────────────────

/// Panel lateral con todo el detalle de la orden y sus acciones.
Future<void> showOrderDetail(BuildContext context, OrderView order) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Cerrar',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (context, _, __) => Align(
      alignment: Alignment.centerRight,
      child: _OrderDetail(orderId: order.id, initial: order),
    ),
    transitionBuilder: (context, animation, _, child) => SlideTransition(
      position: Tween(begin: const Offset(1, 0), end: Offset.zero)
          .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: child,
    ),
  );
}

class _OrderDetail extends ConsumerWidget {
  const _OrderDetail({required this.orderId, required this.initial});
  final String orderId;
  final OrderView initial;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = BrandTokens.of(context);
    final text = Theme.of(context).textTheme;
    // Si la orden cambia mientras el panel está abierto, se ve al instante.
    final live = ref.watch(ordersBoardProvider).value?.orders.where((o) => o.id == orderId).firstOrNull;
    // Si ya no está en el tablero (entregada o cancelada), se trae la versión final del servidor.
    final fetched = live == null ? ref.watch(orderByIdProvider(orderId)).value : null;
    final order = live ?? fetched ?? initial;
    final employee = ref.watch(authControllerProvider).value?.employee;
    final time = DateFormat.jm();

    Widget totalRow(String label, double value, {Color? color, bool bold = false}) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(children: [
            Expanded(child: Text(label, style: (bold ? text.titleMedium : text.bodyMedium)?.copyWith(color: color))),
            Text(formatMoney(value), style: (bold ? text.titleLarge : text.bodyMedium)?.copyWith(color: color)),
          ]),
        );

    return Material(
      color: t.surface,
      child: SizedBox(
        width: 460,
        height: double.infinity,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 12, 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Orden #${order.number}', style: text.headlineMedium),
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, runSpacing: 6, children: [
                    _StatusPill(status: order.status),
                    DmPill(channelLabels[order.channel] ?? order.channel),
                    DmPill('Código ${order.publicCode}'),
                    if (order.isPaid)
                      const DmPill('Pagado', tone: DmTone.success, icon: Icons.check_rounded)
                    else if (order.channel == 'ONLINE' && order.status != 'PENDING_PAYMENT')
                      const DmPill('Paga al recoger', tone: DmTone.warning),
                  ]),
                ]),
              ),
              IconButton(tooltip: 'Cerrar', icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
            ]),
          ),
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(24, 8, 24, 24), children: [
              Text(order.where, style: text.titleMedium),
              Text(
                'Creada ${time.format(order.createdAt)}'
                '${order.readyAt != null ? ' · lista ${time.format(order.readyAt!)}' : ''}',
                style: text.bodySmall,
              ),
              if (order.customerPhone != null) Text('Tel. ${order.customerPhone}', style: text.bodySmall),
              if (order.customerEmail != null && order.customerEmail!.isNotEmpty) Text(order.customerEmail!, style: text.bodySmall),
              if (order.addressText != null) ...[
                const SizedBox(height: 12),
                DmPanel(
                  padding: const EdgeInsets.all(12),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.location_on_rounded, size: 20, color: t.accentText),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Entregar en', style: text.labelMedium),
                        Text(order.addressText!, style: text.titleSmall),
                        if (order.deliveryInstructions != null && order.deliveryInstructions!.isNotEmpty)
                          Text(order.deliveryInstructions!, style: text.bodySmall?.copyWith(color: t.warning)),
                      ]),
                    ),
                  ]),
                ),
              ],
              if (order.fulfillmentType == 'DELIVERY') ...[
                const SizedBox(height: 12),
                _DriverSection(order: order),
              ],
              if (order.notes != null && order.notes!.isNotEmpty) ...[
                const SizedBox(height: 12),
                DmPanel(
                  color: t.warningSoft,
                  padding: const EdgeInsets.all(12),
                  child: Text('Nota: ${order.notes}', style: text.bodyMedium?.copyWith(color: t.warning)),
                ),
              ],
              if (order.cancelReason != null) ...[
                const SizedBox(height: 12),
                DmPanel(
                  color: t.dangerSoft,
                  padding: const EdgeInsets.all(12),
                  child: Text('Cancelada: ${order.cancelReason}', style: text.bodyMedium?.copyWith(color: t.danger)),
                ),
              ],
              const SizedBox(height: 20),
              Text('Productos', style: text.titleLarge),
              const SizedBox(height: 8),
              for (final item in order.items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(
                      width: 36,
                      child: Text('${item.quantity}×', style: text.titleMedium?.copyWith(color: t.accentText)),
                    ),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(
                          item.name,
                          style: text.titleSmall?.copyWith(
                            decoration: item.isActive ? null : TextDecoration.lineThrough,
                            color: item.isActive ? null : t.faint,
                          ),
                        ),
                        for (final m in item.modifiers) Text('${m.group}: ${m.option}', style: text.bodySmall),
                        if (item.notes != null && item.notes!.isNotEmpty)
                          Text('“${item.notes}”', style: text.bodySmall?.copyWith(color: t.warning)),
                        if (item.discount > 0)
                          Text('Promoción −${formatMoney(item.discount)}', style: text.bodySmall?.copyWith(color: t.accentText)),
                      ]),
                    ),
                    Text(formatMoney(item.lineTotal), style: text.titleSmall),
                  ]),
                ),
              Divider(color: t.line, height: 24),
              totalRow('Subtotal', order.subtotal),
              for (final p in order.promotions) totalRow(p.name, -p.amount, color: t.accentText),
              totalRow('Impuesto', order.taxTotal),
              if (order.deliveryFee > 0) totalRow('Envío', order.deliveryFee),
              if (order.tipTotal > 0) totalRow('Propina', order.tipTotal),
              totalRow('Total', order.total, bold: true),
              if (order.amountPaid > 0) totalRow(order.isPaid ? 'Pagado' : 'Abonado', order.amountPaid, color: t.success),
              if (order.tickets.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text('Cocina', style: text.titleLarge),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final ticket in order.tickets)
                    DmPill(
                      '${ticket.stationName} · ${ticketStatusLabels[ticket.status] ?? ticket.status}',
                      color: ticket.status == 'READY' ? t.success : colorFromHex(ticket.stationColor, fallback: t.muted),
                    ),
                ]),
              ],
            ]),
          ),
          if (!order.isFinished)
            Container(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: t.line))),
              child: Row(children: [
                if (employee?.can('orders.cancel') ?? false)
                  OutlinedButton(
                    onPressed: () => _cancel(context, ref, order),
                    style: OutlinedButton.styleFrom(foregroundColor: t.danger, side: BorderSide(color: t.danger)),
                    child: const Text('Cancelar orden'),
                  ),
                const Spacer(),
                if (order.status == 'PENDING_APPROVAL' && (employee?.can('orders.approve') ?? false))
                  _ActionButton(label: 'Aprobar y enviar a cocina', run: (api) => api.approve(order.id)),
                if (order.status == 'READY' && (employee?.can('orders.create') ?? false))
                  _ActionButton(label: 'Marcar entregada', run: (api) => api.complete(order.id)),
                if (employee?.can('kitchen.operate') ?? false) _KitchenButton(order: order, expanded: true),
              ]),
            ),
        ]),
      ),
    );
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref, OrderView order) async {
    final reason = await showDialog<String>(context: context, builder: (_) => const _CancelDialog());
    if (reason == null || !context.mounted) return;
    try {
      final updated = await ref.read(ordersApiProvider).cancel(order.id, reason);
      ref.read(ordersBoardProvider.notifier).apply(updated);
      ref.invalidate(todayOrdersProvider);
      ref.invalidate(orderByIdProvider(order.id));
      if (context.mounted) {
        Navigator.pop(context);
        showSuccess(context, 'Orden #${order.number} cancelada');
      }
    } catch (error) {
      if (context.mounted) showError(context, error);
    }
  }
}

class _CancelDialog extends StatefulWidget {
  const _CancelDialog();

  @override
  State<_CancelDialog> createState() => _CancelDialogState();
}

class _CancelDialogState extends State<_CancelDialog> {
  final _reason = TextEditingController();
  static const _quick = ['El cliente cambió de opinión', 'Pedido duplicado', 'Se agotó un producto'];

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valid = _reason.text.trim().length >= 3;
    return AlertDialog(
      title: const Text('Cancelar orden'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Queda registrado quién la canceló y por qué. Si la cocina ya empezó, solo un gerente puede cancelarla.'),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final q in _quick)
              ActionChip(label: Text(q), onPressed: () => setState(() => _reason.text = q)),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _reason,
            autofocus: true,
            maxLength: 300,
            decoration: const InputDecoration(labelText: 'Motivo'),
            onChanged: (_) => setState(() {}),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Volver')),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: valid ? () => Navigator.pop(context, _reason.text.trim()) : null,
          child: const Text('Cancelar orden'),
        ),
      ],
    );
  }
}

// ───────────────────────── Repartidor ─────────────────────────

/// Quién lleva el pedido y botones para asignar, cambiar o quitar el repartidor.
class _DriverSection extends ConsumerStatefulWidget {
  const _DriverSection({required this.order});
  final OrderView order;

  @override
  ConsumerState<_DriverSection> createState() => _DriverSectionState();
}

class _DriverSectionState extends ConsumerState<_DriverSection> {
  bool _busy = false;

  Future<void> _assign() async {
    final driver = await showDialog<DriverOption>(context: context, builder: (_) => _AssignDriverDialog(current: widget.order.delivery?.driverId));
    if (driver == null || !mounted) return;
    await _run(() => ref.read(ordersApiProvider).assignDriver(widget.order.id, driver.id), 'Asignado a ${driver.name}');
  }

  Future<void> _unassign() => _run(() => ref.read(ordersApiProvider).unassignDriver(widget.order.id), 'Repartidor quitado');

  Future<void> _run(Future<OrderView> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      final updated = await action();
      ref.read(ordersBoardProvider.notifier).apply(updated);
      if (mounted) showSuccess(context, done);
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
    final order = widget.order;
    final d = order.delivery;
    final canDispatch = ref.watch(authControllerProvider).value?.employee.can('delivery.dispatch') ?? false;
    final editable = canDispatch && !order.isFinished && d?.status != 'PICKED_UP';

    return DmPanel(
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        Icon(Icons.delivery_dining_rounded, size: 22, color: d == null ? t.warning : t.accentText),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Repartidor', style: text.labelMedium),
            Text(d?.driverName ?? 'Sin asignar', style: text.titleSmall),
            if (d != null) Text(deliveryStatusLabels[d.status] ?? d.status, style: text.bodySmall),
          ]),
        ),
        if (_busy)
          const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
        else if (editable) ...[
          if (d != null)
            IconButton(tooltip: 'Quitar repartidor', icon: const Icon(Icons.person_remove_rounded), onPressed: _unassign),
          FilledButton.tonal(onPressed: _assign, child: Text(d == null ? 'Asignar' : 'Cambiar')),
        ],
      ]),
    );
  }
}

class _AssignDriverDialog extends ConsumerWidget {
  const _AssignDriverDialog({this.current});
  final String? current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = BrandTokens.of(context);
    final text = Theme.of(context).textTheme;
    return AlertDialog(
      title: const Text('Asignar repartidor'),
      content: SizedBox(
        width: 420,
        child: FutureBuilder<List<DriverOption>>(
          future: ref.read(ordersApiProvider).drivers(),
          builder: (context, snap) {
            if (snap.hasError) return Text('No se pudo cargar la lista: ${snap.error}');
            if (!snap.hasData) return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));
            final drivers = [...snap.data!]..sort((a, b) {
                if (a.available != b.available) return a.available ? -1 : 1;
                return a.activeDeliveries.compareTo(b.activeDeliveries);
              });
            if (drivers.isEmpty) {
              return Text(
                'Todavía no hay repartidores. Crea un empleado con el rol Repartidor (con email y contraseña) en Empleados.',
                style: text.bodyMedium,
              );
            }
            return Column(mainAxisSize: MainAxisSize.min, children: [
              for (final d in drivers)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  enabled: d.status != 'SUSPENDED' && d.id != current,
                  leading: CircleAvatar(
                    backgroundColor: t.surface3,
                    child: Text(d.name.characters.first.toUpperCase(), style: text.titleMedium?.copyWith(color: t.accentText)),
                  ),
                  title: Text(d.name),
                  subtitle: Text([
                    switch (d.status) { 'AVAILABLE' => 'Disponible', 'SUSPENDED' => 'Suspendido', _ => 'Desconectado' },
                    if (d.activeDeliveries > 0) '${d.activeDeliveries} en curso',
                    if (d.id == current) 'ya asignado',
                  ].join(' · ')),
                  trailing: Icon(Icons.circle, size: 12, color: d.available ? t.success : t.faint),
                  onTap: () => Navigator.pop(context, d),
                ),
            ]);
          },
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))],
    );
  }
}
