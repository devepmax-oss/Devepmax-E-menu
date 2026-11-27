import 'dart:async';
import 'dart:math' as math;

import 'package:devepmax_ui/devepmax_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/ui/feedback.dart';
import '../../menu/widgets/common.dart';
import '../../reports/screens/reports_screen.dart';
import 'menu_insights_view.dart';

typedef DJson = Map<String, dynamic>;

double _d(Object? v) => v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);
int _i(Object? v) => (v as num?)?.toInt() ?? 0;

const _channelLabels = {'TABLET': 'Tablet de mesa', 'POS': 'Caja', 'WAITER': 'Mesero', 'ONLINE': 'Web'};
const _weekdays = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
const _months = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];

final dashboardTodayProvider = FutureProvider.autoDispose<DJson>((ref) async {
  final dio = ref.watch(dioProvider);
  try {
    return (await dio.get<DJson>('/dashboard/today')).data!;
  } catch (e) {
    throw ApiException.from(e);
  }
});

String _hourLabel(int h) {
  final suffix = h < 12 ? 'a' : 'p';
  final twelve = h % 12 == 0 ? 12 : h % 12;
  return '$twelve$suffix';
}

String _dayTitle(String iso) {
  final d = DateTime.parse('${iso}T00:00:00');
  final w = _weekdays[d.weekday - 1];
  return '${w[0].toUpperCase()}${w.substring(1)} ${d.day} de ${_months[d.month - 1]}';
}

String _percent(double v) => '${v.toStringAsFixed(v.abs() < 10 ? 1 : 0)} %';

/// Pestañas del Panel, en orden. `/dashboard?tab=ventas` abre directo una de ellas.
const panelTabs = ['hoy', 'ventas', 'menu', 'promociones', 'cocina'];

/// Panel del dueño: Hoy (alertas y lo que pasa ahora), Ventas (los reportes por período),
/// Menú (qué platos venden y cuánto dejan), Promociones (cuánto cuestan los descuentos) y
/// Cocina (cuánto tarda cada ticket).
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, this.initialTab});
  final String? initialTab;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // Menú, Promociones y Cocina comparten el período.
  MenuPeriod _menuPeriod = MenuPeriod.presets()[1];

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final initial = panelTabs.indexOf(widget.initialTab ?? 'hoy');
    return DefaultTabController(
      length: panelTabs.length,
      initialIndex: initial < 0 ? 0 : initial,
      child: Scaffold(
        backgroundColor: t.bg,
        appBar: AppBar(
          title: const Text('Panel'),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(icon: Icon(Icons.today_rounded), text: 'Hoy'),
              Tab(icon: Icon(Icons.insights_rounded), text: 'Ventas'),
              Tab(icon: Icon(Icons.restaurant_menu_rounded), text: 'Menú'),
              Tab(icon: Icon(Icons.local_offer_rounded), text: 'Promociones'),
              Tab(icon: Icon(Icons.soup_kitchen_rounded), text: 'Cocina'),
            ],
          ),
        ),
        body: TabBarView(
          physics: const NeverScrollableScrollPhysics(),
          children: [
            const TodayView(),
            const _KeepAlive(child: ReportsScreen(embedded: true)),
            MenuInsightsView(period: _menuPeriod, onPeriod: (p) => setState(() => _menuPeriod = p)),
            PromotionsInsightsView(period: _menuPeriod, onPeriod: (p) => setState(() => _menuPeriod = p)),
            KitchenTimesView(period: _menuPeriod, onPeriod: (p) => setState(() => _menuPeriod = p)),
          ],
        ),
      ),
    );
  }
}

/// Conserva el estado de una pestaña (por ejemplo, el período elegido en Ventas) al cambiar de pestaña.
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});
  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

/// Pestaña Hoy: cómo va hoy contra la semana pasada, qué pasa ahora y qué pide atención.
/// Se actualiza sola cada minuto.
class TodayView extends ConsumerStatefulWidget {
  const TodayView({super.key});

  @override
  ConsumerState<TodayView> createState() => _TodayViewState();
}

class _TodayViewState extends ConsumerState<TodayView> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => ref.invalidate(dashboardTodayProvider));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final async = ref.watch(dashboardTodayProvider);
    final data = async.value;
    return ColoredBox(
      color: t.bg,
      child: data != null
          ? _DashboardBody(data: data, refreshing: async.isLoading, onRefresh: () => ref.invalidate(dashboardTodayProvider))
          : async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(dashboardTodayProvider)),
              data: (d) => _DashboardBody(data: d, refreshing: false, onRefresh: () => ref.invalidate(dashboardTodayProvider)),
            ),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({required this.data, required this.refreshing, required this.onRefresh});
  final DJson data;
  final bool refreshing;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final pad = pagePadding(context);
    final sales = (data['sales'] as DJson?) ?? const {};
    final labor = (data['labor'] as DJson?) ?? const {};
    final food = data['foodCost'] as DJson?;
    final now = (data['now'] as DJson?) ?? const {};
    final alerts = ((data['alerts'] as List?) ?? const []).cast<DJson>();
    final hourly = ((data['hourly'] as List?) ?? const []).cast<DJson>();
    final channels = ((data['channels'] as List?) ?? const []).cast<DJson>();
    final products = ((data['topProducts'] as List?) ?? const []).cast<DJson>();
    final change = sales['change'] as num?;
    final at = DateTime.tryParse('${data['at']}')?.toLocal();

    final kpis = <Widget>[
      _Kpi(
        label: 'Ventas de hoy',
        value: formatMoney(_d(sales['net'])),
        icon: Icons.trending_up_rounded,
        note: change == null
            ? 'la semana pasada a esta hora: ${formatMoney(_d(sales['lastWeekSoFar']))}'
            : '${change >= 0 ? '▲' : '▼'} ${_percent(change.abs().toDouble())} vs. ${formatMoney(_d(sales['lastWeekSoFar']))} la semana pasada',
        noteColor: change == null ? t.faint : (change >= 0 ? t.success : t.danger),
      ),
      _Kpi(
        label: 'Órdenes',
        value: '${_i(sales['orders'])}',
        icon: Icons.receipt_long_rounded,
        note: 'semana pasada a esta hora: ${_i(sales['lastWeekOrders'])}',
      ),
      _Kpi(
        label: 'Ticket promedio',
        value: formatMoney(_d(sales['averageTicket'])),
        icon: Icons.functions_rounded,
        note: '${_i(sales['bills'])} cuentas',
      ),
      _Kpi(
        label: 'Propinas',
        value: formatMoney(_d(sales['tips'])),
        icon: Icons.volunteer_activism_rounded,
        note: 'cobrado ${formatMoney(_d(sales['collected']))}',
      ),
      _Kpi(
        label: 'Costo de personal',
        value: formatMoney(_d(labor['cost'])),
        icon: Icons.badge_rounded,
        note: labor['percent'] == null ? '${_i(labor['working'])} trabajando ahora' : '${_percent(_d(labor['percent']))} de las ventas',
        noteColor: _d(labor['percent']) > 35 ? t.danger : null,
      ),
      if (food != null)
        _Kpi(
          label: 'Costo de comida',
          value: formatMoney(_d(food['cost'])),
          icon: Icons.inventory_2_rounded,
          note: food['percent'] == null ? 'según el inventario' : '${_percent(_d(food['percent']))} de las ventas',
          noteColor: _d(food['percent']) > 35 ? t.danger : null,
        ),
    ];

    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: ListView(
        padding: EdgeInsets.fromLTRB(pad, 12, pad, 32),
        children: [
          Row(children: [
            Expanded(child: Text(_dayTitle('${data['businessDate']}'), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
            if (refreshing)
              const Padding(padding: EdgeInsets.all(12), child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)))
            else
              IconButton(tooltip: 'Actualizar', icon: const Icon(Icons.refresh_rounded), onPressed: onRefresh),
          ]),
          Text(
            'Día de operación desde las 4 a. m.${at == null ? '' : ' · actualizado ${_clock(at)}'} · comparado con el ${_dayTitle('${data['compareDate']}').toLowerCase()}',
            style: TextStyle(color: t.muted, fontSize: 12.5),
          ),
          const SizedBox(height: 14),
          if (alerts.isEmpty)
            const _CalmBanner()
          else
            for (final a in alerts) Padding(padding: const EdgeInsets.only(bottom: 8), child: _AlertTile(alert: a)),
          const SizedBox(height: 8),
          _Grid(minWidth: 210, children: kpis),
          const SizedBox(height: 14),
          _Section(
            title: 'Ahora mismo',
            children: [
              Wrap(spacing: 10, runSpacing: 10, children: [
                if (_i(now['approval']) > 0) _NowChip(icon: Icons.pending_actions_rounded, label: 'Por aprobar', value: _i(now['approval']), color: t.warning, path: '/orders'),
                _NowChip(icon: Icons.soup_kitchen_rounded, label: 'En cocina', value: _i(now['kitchen']), path: '/orders'),
                if (_i(now['lateTickets']) > 0) _NowChip(icon: Icons.timer_off_rounded, label: 'Atrasadas', value: _i(now['lateTickets']), color: t.danger, path: '/orders'),
                _NowChip(icon: Icons.check_circle_rounded, label: 'Listas', value: _i(now['ready']), path: '/orders'),
                if (_i(now['onTheWay']) > 0) _NowChip(icon: Icons.delivery_dining_rounded, label: 'En camino', value: _i(now['onTheWay']), path: '/orders'),
                _NowChip(icon: Icons.table_restaurant_rounded, label: 'Mesas abiertas', value: _i(now['openTables']), path: '/tables', detail: _i(now['guests']) > 0 ? '${_i(now['guests'])} personas' : null),
                _NowChip(icon: Icons.punch_clock_rounded, label: 'Trabajando', value: _i(labor['working']), path: '/attendance'),
                if (_i(sales['scheduledToday']) > 0) _NowChip(icon: Icons.event_rounded, label: 'Programadas', value: _i(sales['scheduledToday']), path: '/orders'),
                if (_i(sales['cancellations']) > 0) _NowChip(icon: Icons.cancel_rounded, label: 'Canceladas hoy', value: _i(sales['cancellations']), path: '/reports'),
              ]),
            ],
          ),
          const SizedBox(height: 14),
          _Section(
            title: 'Ventas por hora',
            children: [
              Row(children: [
                _Legend(color: t.primary, label: 'Hoy'),
                const SizedBox(width: 16),
                _Legend(color: t.lineStrong, label: 'Semana pasada (día completo ${formatMoney(_d(sales['lastWeekDay']))})'),
              ]),
              const SizedBox(height: 10),
              _HourChart(hours: hourly),
            ],
          ),
          const SizedBox(height: 14),
          _Grid(minWidth: 320, children: [
            _Section(
              title: 'Por canal',
              children: channels.isEmpty
                  ? [Text('Todavía no hay ventas hoy.', style: TextStyle(color: t.muted))]
                  : [
                      _HBars(
                        color: t.accent,
                        items: [
                          for (final c in channels)
                            _Bar('${_channelLabels[c['channel']] ?? c['channel']} · ${_i(c['orders'])} órdenes', _d(c['net']), formatMoney(_d(c['net']))),
                        ],
                      ),
                    ],
            ),
            _Section(
              title: 'Lo más pedido hoy',
              children: products.isEmpty
                  ? [Text('Todavía no hay platos vendidos hoy.', style: TextStyle(color: t.muted))]
                  : [
                      _HBars(
                        color: t.primary,
                        items: [for (final p in products) _Bar('${_i(p['quantity'])}× ${p['name']}', _d(p['quantity']), formatMoney(_d(p['net'])))],
                      ),
                    ],
            ),
          ]),
        ],
      ),
    );
  }
}

String _clock(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'a. m.' : 'p. m.'}';
}

// ───────────────────────── Piezas ─────────────────────────

class _CalmBanner extends StatelessWidget {
  const _CalmBanner();

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: t.successSoft, borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        Icon(Icons.verified_rounded, color: t.success),
        const SizedBox(width: 10),
        const Expanded(child: Text('Todo en orden: no hay nada que pida tu atención.', style: TextStyle(fontWeight: FontWeight.w600))),
      ]),
    );
  }
}

class _AlertTile extends StatelessWidget {
  const _AlertTile({required this.alert});
  final DJson alert;

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final (color, soft, icon) = switch (alert['level']) {
      'danger' => (t.danger, t.dangerSoft, Icons.error_rounded),
      'warning' => (t.warning, t.warningSoft, Icons.warning_amber_rounded),
      _ => (t.info, t.infoSoft, Icons.info_rounded),
    };
    final action = alert['action'] as String?;
    return Material(
      color: soft,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: action == null ? null : () => context.go(action),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${alert['title']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                if ('${alert['detail'] ?? ''}'.isNotEmpty) Text('${alert['detail']}', style: TextStyle(color: t.muted, fontSize: 13)),
              ]),
            ),
            if (action != null) Icon(Icons.chevron_right_rounded, color: t.muted),
          ]),
        ),
      ),
    );
  }
}

/// Reparte las tarjetas en columnas según el ancho disponible.
class _Grid extends StatelessWidget {
  const _Grid({required this.children, required this.minWidth});
  final List<Widget> children;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final columns = math.max(1, math.min(children.length, (c.maxWidth / minWidth).floor()));
      const gap = 12.0;
      final width = (c.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(spacing: gap, runSpacing: gap, children: [for (final w in children) SizedBox(width: width, child: w)]);
    });
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({required this.label, required this.value, required this.icon, required this.note, this.noteColor});
  final String label;
  final String value;
  final IconData icon;
  final String note;
  final Color? noteColor;

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: t.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: t.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 18, color: t.accentText),
          const SizedBox(width: 6),
          Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.muted))),
        ]),
        const SizedBox(height: 6),
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: Theme.of(context).textTheme.headlineSmall)),
        const SizedBox(height: 2),
        Text(note, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: noteColor ?? t.faint, fontSize: 12.5, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(color: t.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: t.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        ...children,
      ]),
    );
  }
}

class _NowChip extends StatelessWidget {
  const _NowChip({required this.icon, required this.label, required this.value, required this.path, this.color, this.detail});
  final IconData icon;
  final String label;
  final int value;
  final String path;
  final Color? color;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final c = color ?? t.accentText;
    return Material(
      color: t.surface2,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.go(path),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 20, color: c),
            const SizedBox(width: 8),
            Text('$value', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(label, style: TextStyle(color: t.muted)),
              if (detail != null) Text(detail!, style: TextStyle(color: t.faint, fontSize: 12)),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    return Flexible(
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.muted, fontSize: 12.5))),
      ]),
    );
  }
}

/// Columnas por hora: la de hoy al frente y, detrás, la misma hora de la semana pasada.
class _HourChart extends StatelessWidget {
  const _HourChart({required this.hours});
  final List<DJson> hours;

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    if (hours.isEmpty) return Text('Todavía no hay ventas hoy.', style: TextStyle(color: t.muted));
    final max = hours.fold<double>(0, (a, h) => math.max(a, math.max(_d(h['today']), _d(h['lastWeek']))));
    double factor(double v) => max <= 0 ? 0.01 : (v / max).clamp(0.01, 1.0);
    final every = (hours.length / 12).ceil().clamp(1, 24);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('máx. ${formatMoney(max)}', style: TextStyle(color: t.faint, fontSize: 12)),
      const SizedBox(height: 6),
      SizedBox(
        height: 170,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (final h in hours)
            Expanded(
              child: Tooltip(
                message: '${_hourLabel(_i(h['hour']))} · hoy ${formatMoney(_d(h['today']))} · semana pasada ${formatMoney(_d(h['lastWeek']))}',
                triggerMode: TooltipTriggerMode.tap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Stack(alignment: Alignment.bottomCenter, children: [
                    FractionallySizedBox(
                      heightFactor: factor(_d(h['lastWeek'])),
                      widthFactor: 1,
                      child: DecoratedBox(decoration: BoxDecoration(color: t.lineStrong.withValues(alpha: 0.55), borderRadius: const BorderRadius.vertical(top: Radius.circular(6)))),
                    ),
                    FractionallySizedBox(
                      heightFactor: factor(_d(h['today'])),
                      widthFactor: 0.6,
                      child: DecoratedBox(decoration: BoxDecoration(color: _d(h['today']) <= 0 ? t.line : t.primary, borderRadius: const BorderRadius.vertical(top: Radius.circular(5)))),
                    ),
                  ]),
                ),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 4),
      Row(children: [
        for (var i = 0; i < hours.length; i++)
          Expanded(
            child: Text(
              i % every == 0 ? _hourLabel(_i(hours[i]['hour'])) : '',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: TextStyle(color: t.faint, fontSize: 11),
            ),
          ),
      ]),
    ]);
  }
}

class _Bar {
  const _Bar(this.label, this.value, this.tooltip);
  final String label;
  final double value;
  final String tooltip;
}

class _HBars extends StatelessWidget {
  const _HBars({required this.items, required this.color});
  final List<_Bar> items;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final max = items.fold<double>(0, (a, b) => math.max(a, b.value));
    return Column(children: [
      for (final b in items)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(b.label, maxLines: 1, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 8),
              Text(b.tooltip, style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(value: max <= 0 ? 0 : b.value / max, minHeight: 8, color: color, backgroundColor: t.surface2),
            ),
          ]),
        ),
    ]);
  }
}
