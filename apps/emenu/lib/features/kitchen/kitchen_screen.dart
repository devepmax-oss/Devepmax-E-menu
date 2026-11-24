import 'dart:async';

import 'package:devepmax_ui/devepmax_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/device_session.dart';
import '../../core/realtime.dart';
import '../../core/widgets.dart';
import '../menu/menu_data.dart' show brandProvider;
import 'kitchen_data.dart';

/// Pantalla de cocina (KDS): los tickets de esta estación en orden de llegada, con tiempo,
/// colores cuando se atrasan, sonido al llegar y botones grandes de Empezar y Listo.
class KitchenScreen extends ConsumerStatefulWidget {
  const KitchenScreen({super.key});

  @override
  ConsumerState<KitchenScreen> createState() => _KitchenScreenState();
}

class _KitchenScreenState extends ConsumerState<KitchenScreen> {
  Timer? _clock;
  StreamSubscription<int>? _cancelled;
  bool _allDay = false;

  /// Platos ya terminados dentro de un ticket (solo en esta pantalla, para no perderse).
  final Set<String> _doneItems = {};

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _cancelled?.cancel();
    super.dispose();
  }

  Future<void> _move(KitchenTicket ticket, String status) async {
    try {
      await ref.read(kitchenProvider.notifier).move(ticket.id, status);
      if (status == 'READY') _doneItems.removeAll(ticket.items.map((i) => i.id));
    } catch (error) {
      if (mounted) showMessage(context, '$error', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    ref.listen(kitchenCancelledProvider, (_, next) {
      final number = next.value;
      if (number != null) showMessage(context, 'Orden #$number cancelada: ya no la prepares', error: true);
    });
    final async = ref.watch(kitchenProvider);
    final status = ref.watch(realtimeProvider);
    final prep = ((ref.watch(brandProvider).value?['prepTimeMinutes'] as num?)?.toInt() ?? 15).clamp(3, 120);
    final width = MediaQuery.sizeOf(context).width;

    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.wifi_off_rounded, size: 56, color: t.faint),
              const SizedBox(height: 12),
              Text('$e', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              FilledButton(onPressed: () => ref.invalidate(kitchenProvider), child: const Text('Reintentar')),
            ]),
          ),
          data: (k) {
            final todo = k.todo;
            final ready = k.ready;
            final header = _Header(state: k, status: status, allDay: _allDay, onAllDay: () => setState(() => _allDay = !_allDay));
            if (k.station == null) {
              return Column(children: [
                header,
                const Expanded(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('Esta pantalla no tiene estación. En la app Staff → Dispositivos, asígnale una (Cocina, Bar…).',
                          textAlign: TextAlign.center, style: TextStyle(fontSize: 18)),
                    ),
                  ),
                ),
              ]);
            }

            Widget todoGrid() => todo.isEmpty
                ? const _Empty(icon: Icons.soup_kitchen_rounded, message: 'Todo al día. Los pedidos nuevos aparecen aquí.')
                : LayoutBuilder(builder: (context, box) {
                    const gap = 12.0;
                    final cols = (box.maxWidth / 300).floor().clamp(1, 6);
                    final cardWidth = (box.maxWidth - 24 - gap * (cols - 1)) / cols;
                    return SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                      child: Wrap(spacing: gap, runSpacing: gap, children: [
                        for (final ticket in todo)
                          SizedBox(
                            width: cardWidth,
                            child: _TicketCard(
                              ticket: ticket,
                              prepMinutes: prep,
                              fresh: k.arrived[ticket.id] != null && DateTime.now().difference(k.arrived[ticket.id]!).inSeconds < 20,
                              doneItems: _doneItems,
                              onToggleItem: (id) => setState(() => _doneItems.contains(id) ? _doneItems.remove(id) : _doneItems.add(id)),
                              onMove: (s) => _move(ticket, s),
                            ),
                          ),
                      ]),
                    );
                  });

            Widget readyList() => ready.isEmpty
                ? const _Empty(icon: Icons.check_circle_outline_rounded, message: 'Lo que marques "Listo" queda aquí hasta que lo entreguen.')
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                    itemCount: ready.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _ReadyTile(ticket: ready[i], onUndo: () => _move(ready[i], 'PREPARING')),
                  );

            // Teléfono o tablet chica: pestañas.
            if (width < 760) {
              return DefaultTabController(
                length: 2,
                child: Column(children: [
                  header,
                  TabBar(tabs: [Tab(text: 'Por hacer · ${todo.length}'), Tab(text: 'Listos · ${ready.length}')]),
                  Expanded(child: TabBarView(children: [todoGrid(), readyList()])),
                ]),
              );
            }

            final readyWidth = width >= 1400 ? 340.0 : 280.0;
            return Column(children: [
              header,
              Expanded(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (_allDay) SizedBox(width: 260, child: _AllDay(tickets: todo)),
                  if (_allDay) VerticalDivider(width: 1, color: t.line),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      _ColumnTitle(title: 'Por hacer', count: todo.length),
                      Expanded(child: todoGrid()),
                    ]),
                  ),
                  VerticalDivider(width: 1, color: t.line),
                  SizedBox(
                    width: readyWidth,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      _ColumnTitle(title: 'Listos', count: ready.length, color: t.success),
                      Expanded(child: readyList()),
                    ]),
                  ),
                ]),
              ),
            ]);
          },
        ),
      ),
    );
  }
}

// ───────────────────────── Barra superior ─────────────────────────

class _Header extends ConsumerWidget {
  const _Header({required this.state, required this.status, required this.allDay, required this.onAllDay});
  final KitchenState state;
  final RealtimeStatus status;
  final bool allDay;
  final VoidCallback onAllDay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = BrandTokens.of(context);
    final sound = ref.watch(kitchenSoundProvider);
    final compact = MediaQuery.sizeOf(context).width < 760;
    final station = state.station;
    final stationColor = _hex(station?.color) ?? t.accent;
    final live = status == RealtimeStatus.live;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      decoration: BoxDecoration(color: t.surface, border: Border(bottom: BorderSide(color: t.line))),
      child: Row(children: [
        const StaffLogo(height: 34),
        const SizedBox(width: 14),
        Container(width: 12, height: 12, decoration: BoxDecoration(color: stationColor, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Flexible(
          child: Text(station?.name ?? 'Cocina',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 12),
        Tooltip(
          message: live ? 'Conectada' : 'Sin conexión, reintentando…',
          child: Icon(live ? Icons.wifi_rounded : Icons.wifi_off_rounded, color: live ? t.success : t.danger, size: 22),
        ),
        const Spacer(),
        if (!compact) ...[
          Text(DateFormat.jm().format(DateTime.now()), style: TextStyle(color: t.muted, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(width: 12),
          _HeaderButton(icon: Icons.format_list_numbered_rounded, label: 'Todo el día', selected: allDay, onTap: onAllDay),
          const SizedBox(width: 8),
        ],
        _HeaderButton(icon: Icons.block_rounded, label: compact ? null : 'Agotados', onTap: () => _showSoldOut(context)),
        const SizedBox(width: 8),
        _HeaderButton(
          icon: sound ? Icons.volume_up_rounded : Icons.volume_off_rounded,
          selected: !sound,
          onTap: () => ref.read(kitchenSoundProvider.notifier).toggle(),
          tooltip: sound ? 'Silenciar' : 'Activar sonido',
        ),
      ]),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({required this.icon, this.label, required this.onTap, this.selected = false, this.tooltip});
  final IconData icon;
  final String? label;
  final VoidCallback onTap;
  final bool selected;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final child = Material(
      color: selected ? t.primarySoft : t.surface2,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: label == null ? 12 : 14, vertical: 10),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 22, color: selected ? t.primaryText : t.text),
            if (label != null) ...[
              const SizedBox(width: 8),
              Text(label!, style: TextStyle(fontWeight: FontWeight.w700, color: selected ? t.primaryText : t.text)),
            ],
          ]),
        ),
      ),
    );
    return tooltip == null ? child : Tooltip(message: tooltip!, child: child);
  }
}

class _ColumnTitle extends StatelessWidget {
  const _ColumnTitle({required this.title, this.count, this.color});
  final String title;
  final int? count;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: color)),
        if (count != null) ...[
          const SizedBox(width: 8),
          DmPill('$count', color: color ?? t.muted),
        ],
      ]),
    );
  }
}

// ───────────────────────── Ticket ─────────────────────────

class _TicketCard extends StatelessWidget {
  const _TicketCard({
    required this.ticket,
    required this.prepMinutes,
    required this.fresh,
    required this.doneItems,
    required this.onToggleItem,
    required this.onMove,
  });
  final KitchenTicket ticket;
  final int prepMinutes;
  final bool fresh;
  final Set<String> doneItems;
  final ValueChanged<String> onToggleItem;
  final ValueChanged<String> onMove;

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final text = Theme.of(context).textTheme;
    final elapsed = DateTime.now().difference(ticket.createdAt);
    final late = elapsed.inSeconds >= prepMinutes * 60;
    final warn = !late && elapsed.inSeconds >= prepMinutes * 45; // 75 % del tiempo
    final tone = late ? t.danger : (warn ? t.warning : (ticket.isCooking ? t.accent : t.info));
    final mm = elapsed.inMinutes.toString().padLeft(2, '0');
    final ss = (elapsed.inSeconds % 60).toString().padLeft(2, '0');

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fresh ? t.primary : (late || warn ? tone : t.line), width: fresh || late ? 3 : 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          color: tone.withValues(alpha: 0.18),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Row(children: [
            Text('#${ticket.orderNumber}', style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(ticket.destination, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                Text(
                  [ticket.channelLabel, if (ticket.customerName != null) ticket.customerName!].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: t.muted, fontSize: 13),
                ),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('$mm:$ss', style: text.titleLarge?.copyWith(color: tone, fontWeight: FontWeight.w900, fontFeatures: const [FontFeature.tabularFigures()])),
              Text(
                fresh ? 'NUEVO' : (ticket.isCooking ? 'Preparando' : 'Por empezar'),
                style: TextStyle(color: fresh ? t.primaryText : t.muted, fontSize: 12, fontWeight: FontWeight.w800),
              ),
            ]),
          ]),
        ),
        if (ticket.scheduledFor != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            child: DmPill('Para las ${DateFormat.jm().format(ticket.scheduledFor!)}', tone: DmTone.accent, icon: Icons.schedule_rounded),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 2),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final item in ticket.items)
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => onToggleItem(item.id),
                child: Opacity(
                  opacity: doneItems.contains(item.id) ? 0.4 : 1,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SizedBox(
                        width: 40,
                        child: Text('${item.quantity}×', style: text.titleLarge?.copyWith(color: t.accentText, fontWeight: FontWeight.w900)),
                      ),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(
                            item.name,
                            style: text.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              decoration: doneItems.contains(item.id) ? TextDecoration.lineThrough : null,
                            ),
                          ),
                          for (final m in item.modifiers) Text('• $m', style: TextStyle(color: t.text.withValues(alpha: 0.85), fontSize: 15)),
                          if (item.notes != null)
                            Container(
                              margin: const EdgeInsets.only(top: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(color: t.warningSoft, borderRadius: BorderRadius.circular(8)),
                              child: Text('“${item.notes}”', style: TextStyle(color: t.warning, fontWeight: FontWeight.w800, fontSize: 15)),
                            ),
                          if (item.seat != null) Text('Asiento ${item.seat}', style: TextStyle(color: t.muted, fontSize: 12.5)),
                        ]),
                      ),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
        if (ticket.orderNotes != null)
          Container(
            margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: t.infoSoft, borderRadius: BorderRadius.circular(12)),
            child: Text('Nota: ${ticket.orderNotes}', style: TextStyle(color: t.info, fontWeight: FontWeight.w700)),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Row(children: [
            if (ticket.isPending) ...[
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(54), textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  onPressed: () => onMove('PREPARING'),
                  child: const Text('Empezar'),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                  backgroundColor: t.success,
                  foregroundColor: Colors.white,
                  textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
                onPressed: () => onMove('READY'),
                icon: const Icon(Icons.check_rounded),
                label: const Text('Listo'),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _ReadyTile extends StatelessWidget {
  const _ReadyTile({required this.ticket, required this.onUndo});
  final KitchenTicket ticket;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final since = DateTime.now().difference(ticket.readyAt ?? ticket.updatedAt);
    final ago = since.inMinutes < 1 ? 'recién' : 'hace ${since.inMinutes} min';
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(color: t.successSoft, borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        Icon(Icons.check_circle_rounded, color: t.success),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('#${ticket.orderNumber} · ${ticket.destination}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            Text('${ticket.itemCount} ${ticket.itemCount == 1 ? 'plato' : 'platos'} · listo $ago', style: TextStyle(color: t.muted, fontSize: 13)),
          ]),
        ),
        TextButton(onPressed: onUndo, child: const Text('Deshacer')),
      ]),
    );
  }
}

/// Cuántos de cada plato hay por hacer en total (para cocinar por tandas).
class _AllDay extends StatelessWidget {
  const _AllDay({required this.tickets});
  final List<KitchenTicket> tickets;

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final totals = <String, int>{};
    for (final ticket in tickets) {
      for (final i in ticket.items) {
        totals[i.name] = (totals[i.name] ?? 0) + i.quantity;
      }
    }
    final rows = totals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const _ColumnTitle(title: 'Todo el día'),
      Expanded(
        child: rows.isEmpty
            ? Center(child: Text('Nada por hacer', style: TextStyle(color: t.muted)))
            : ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
                for (final r in rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(children: [
                      SizedBox(width: 44, child: Text('${r.value}', style: TextStyle(color: t.accentText, fontWeight: FontWeight.w900, fontSize: 20))),
                      Expanded(child: Text(r.key, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                    ]),
                  ),
              ]),
      ),
    ]);
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 56, color: t.faint),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center, style: TextStyle(color: t.muted, fontSize: 16)),
        ]),
      ),
    );
  }
}

// ───────────────────────── Agotados ─────────────────────────

Future<void> _showSoldOut(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _SoldOutDialog());

class _SoldOutDialog extends ConsumerStatefulWidget {
  const _SoldOutDialog();

  @override
  ConsumerState<_SoldOutDialog> createState() => _SoldOutDialogState();
}

class _SoldOutDialogState extends ConsumerState<_SoldOutDialog> {
  late Future<List<KitchenProduct>> _products = loadKitchenProducts(ref.read(dioProvider));
  final Map<String, bool> _changed = {};
  final Set<String> _busy = {};
  String _query = '';

  Future<void> _toggle(KitchenProduct p, bool available) async {
    setState(() {
      _busy.add(p.id);
      _changed[p.id] = available;
    });
    try {
      await setProductAvailable(ref.read(dioProvider), p.id, available);
    } catch (error) {
      if (mounted) {
        setState(() => _changed.remove(p.id));
        showMessage(context, '$error', error: true);
      }
    } finally {
      if (mounted) setState(() => _busy.remove(p.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 560, maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 8, 4),
            child: Row(children: [
              Expanded(child: Text('Agotados', style: Theme.of(context).textTheme.headlineSmall)),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text('Apaga lo que se acabó: deja de ofrecerse en las mesas, la caja y la web al instante.', style: TextStyle(color: t.muted)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: TextField(
              decoration: const InputDecoration(hintText: 'Buscar', prefixIcon: Icon(Icons.search_rounded)),
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            ),
          ),
          const SizedBox(height: 8),
          Flexible(
            child: FutureBuilder<List<KitchenProduct>>(
              future: _products,
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(
                    child: TextButton(
                      onPressed: () => setState(() => _products = loadKitchenProducts(ref.read(dioProvider))),
                      child: const Text('No se pudo cargar. Reintentar'),
                    ),
                  );
                }
                final list = (snap.data ?? const <KitchenProduct>[]).where((p) => _query.isEmpty || p.name.toLowerCase().contains(_query)).toList()
                  ..sort((a, b) => (_changed[a.id] ?? a.isAvailable) == (_changed[b.id] ?? b.isAvailable)
                      ? a.name.compareTo(b.name)
                      : ((_changed[a.id] ?? a.isAvailable) ? 1 : -1));
                if (!snap.hasData) return const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()));
                return ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final p = list[i];
                    final available = _changed[p.id] ?? p.isAvailable;
                    return SwitchListTile(
                      value: available,
                      onChanged: _busy.contains(p.id) ? null : (v) => _toggle(p, v),
                      title: Text(p.name, style: TextStyle(fontWeight: FontWeight.w700, color: available ? null : t.danger)),
                      subtitle: Text(available ? p.category : '${p.category} · agotado'),
                    );
                  },
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}

Color? _hex(String? value) {
  if (value == null) return null;
  final hex = value.replaceAll('#', '');
  if (hex.length != 6) return null;
  final n = int.tryParse(hex, radix: 16);
  return n == null ? null : Color(0xFF000000 | n);
}
