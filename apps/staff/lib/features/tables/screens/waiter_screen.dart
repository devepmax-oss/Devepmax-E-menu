import 'dart:async';

import 'package:devepmax_ui/devepmax_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/realtime/realtime.dart';
import '../../../core/ui/feedback.dart';
import '../../menu/widgets/common.dart';
import '../../orders/screens/orders_screen.dart' show LiveIndicator;
import '../data/tables_api.dart';
import '../data/tables_models.dart';
import 'table_panel.dart';
import 'tables_screen.dart' show elapsedLabel;

enum _Filter { mine, all, free }

/// Modo mesero: las mesas como lista para el teléfono, primero lo urgente (llamados, pedidos
/// listos para llevar, cuenta pedida). Un toque abre la mesa con todo lo que se puede hacer.
class WaiterScreen extends ConsumerStatefulWidget {
  const WaiterScreen({super.key});

  @override
  ConsumerState<WaiterScreen> createState() => _WaiterScreenState();
}

class _WaiterScreenState extends ConsumerState<WaiterScreen> {
  _Filter _filter = _Filter.mine;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  /// Más urgente primero: llaman, hay pedidos listos, pidieron la cuenta; luego las que llevan más tiempo.
  int _priority(TableSessionView s) {
    if (s.calling) return 0;
    if (s.readyOrders > 0) return 1;
    if (s.billRequested) return 2;
    return 3;
  }

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final floor = ref.watch(floorProvider);
    final status = ref.watch(realtimeProvider);
    final me = ref.watch(authControllerProvider).value?.employee;
    final canOrder = me?.can('orders.create') ?? false;
    final entries = [
      for (final a in floor.value ?? const <AreaView>[])
        for (final table in a.tables) (area: a.name, table: table),
    ];
    final busy = entries.where((e) => e.table.session != null).toList()
      ..sort((a, b) {
        final pa = _priority(a.table.session!), pb = _priority(b.table.session!);
        return pa != pb ? pa.compareTo(pb) : a.table.session!.openedAt.compareTo(b.table.session!.openedAt);
      });
    final mine = busy.where((e) => e.table.session!.waiterId == me?.id).toList();
    final free = entries.where((e) => e.table.session == null && e.table.status != 'CLEANING').toList();
    final visible = switch (_filter) {
      _Filter.mine => mine,
      _Filter.all => busy,
      _Filter.free => free,
    };

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        title: Row(children: [
          const Flexible(child: Text('Mis mesas', maxLines: 1, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 12),
          Flexible(child: LiveIndicator(status: status)),
        ]),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.read(floorProvider.notifier).refresh(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: canOrder
          ? FloatingActionButton.extended(
              onPressed: () => context.go('/pos'),
              icon: const Icon(Icons.add_shopping_cart_rounded),
              label: const Text('Tomar pedido'),
            )
          : null,
      body: floor.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(floorProvider)),
        data: (_) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: EdgeInsets.fromLTRB(pagePadding(context), 4, pagePadding(context), 12),
            child: FitSegmented<_Filter>(SegmentedButton<_Filter>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: _Filter.mine, label: Text('Mías · ${mine.length}')),
                ButtonSegment(value: _Filter.all, label: Text('Con clientes · ${busy.length}')),
                ButtonSegment(value: _Filter.free, label: Text('Libres · ${free.length}')),
              ],
              selected: {_filter},
              onSelectionChanged: (s) => setState(() => _filter = s.first),
            )),
          ),
          Expanded(
            child: visible.isEmpty
                ? EmptyState(
                    icon: Icons.table_restaurant_rounded,
                    message: switch (_filter) {
                      _Filter.mine => 'No tienes mesas. Sienta clientes o toma una mesa desde "Con clientes".',
                      _Filter.all => 'No hay mesas con clientes.',
                      _Filter.free => 'No hay mesas libres.',
                    },
                  )
                : LayoutBuilder(builder: (context, box) {
                    final cols = (box.maxWidth / 380).floor().clamp(1, 4);
                    return GridView.builder(
                      padding: EdgeInsets.fromLTRB(pagePadding(context), 0, pagePadding(context), 96),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: cols,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        mainAxisExtent: 128,
                      ),
                      itemCount: visible.length,
                      itemBuilder: (_, i) => _TableTile(
                        table: visible[i].table,
                        area: visible[i].area,
                        showWaiter: _filter != _Filter.mine,
                        mine: visible[i].table.session?.waiterId == me?.id,
                        onTap: () => showTablePanel(context, visible[i].table.id),
                      ),
                    );
                  }),
          ),
        ]),
      ),
    );
  }
}

class _TableTile extends StatelessWidget {
  const _TableTile({required this.table, required this.area, required this.showWaiter, required this.mine, required this.onTap});
  final TableView table;
  final String area;
  final bool showWaiter;
  final bool mine;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final text = Theme.of(context).textTheme;
    final s = table.session;
    final urgent = s != null && (s.calling || s.readyOrders > 0);
    final accent = s == null
        ? t.success
        : s.calling
            ? t.accent
            : s.readyOrders > 0
                ? t.success
                : s.billRequested
                    ? t.info
                    : t.primary;

    final badges = <Widget>[
      if (s != null && s.calling) const DmPill('Llamando', tone: DmTone.accent, icon: Icons.notifications_active_rounded),
      if (s != null && s.readyOrders > 0)
        DmPill('${s.readyOrders} ${s.readyOrders == 1 ? 'listo' : 'listos'} para llevar', tone: DmTone.success, icon: Icons.room_service_rounded),
      if (s != null && s.billRequested) const DmPill('Pidió la cuenta', tone: DmTone.info, icon: Icons.receipt_long_rounded),
      if (s != null && s.activeOrders - s.readyOrders > 0) DmPill('${s.activeOrders - s.readyOrders} en cocina', icon: Icons.soup_kitchen_rounded),
      if (s == null) DmPill(table.status == 'RESERVED' ? 'Reservada' : 'Libre', tone: table.status == 'RESERVED' ? DmTone.info : DmTone.success),
    ];

    return Material(
      color: t.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: urgent ? accent : t.line, width: urgent ? 2 : 1),
      ),
      child: InkWell(
        onTap: onTap,
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(width: 6, color: accent),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 0, 14),
            child: CircleAvatar(
              radius: 28,
              backgroundColor: accent.withValues(alpha: 0.16),
              child: FittedBox(
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Text(table.label, style: TextStyle(color: accent, fontWeight: FontWeight.w900, fontSize: 20)),
                ),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Row(children: [
                  Expanded(
                    child: Text('Mesa ${table.label}', maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  ),
                  if (s != null && s.due > 0) Text(formatMoney(s.due), style: text.titleMedium?.copyWith(color: t.accentText)),
                ]),
                Text(
                  [
                    area,
                    if (s != null) '${s.guestCount ?? '—'} ${s.guestCount == 1 ? 'cliente' : 'clientes'}',
                    if (s != null) elapsedLabel(s.openedAt),
                    if (s == null) '${table.seats} lugares',
                    if (showWaiter && s != null) mine ? 'tuya' : (s.waiterName ?? 'sin mesero'),
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: t.muted, fontSize: 13),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 30,
                  child: ListView(scrollDirection: Axis.horizontal, children: [
                    for (final b in badges) Padding(padding: const EdgeInsets.only(right: 6), child: b),
                  ]),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
