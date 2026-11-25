import 'dart:math' as math;

import 'package:devepmax_ui/devepmax_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/ui/feedback.dart';
import '../../billing/data/billing_models.dart' show paymentMethodLabels;
import '../../billing/printing/printer.dart';
import '../../billing/screens/receipt_dialog.dart' show showPrinterSetup;
import '../../menu/widgets/common.dart';

typedef RJson = Map<String, dynamic>;

const _channelLabels = {'TABLET': 'Tablet de mesa', 'POS': 'Caja', 'WAITER': 'Mesero', 'ONLINE': 'Web'};
const _fulfillmentLabels = {'DINE_IN': 'Comer aquí', 'TAKEOUT': 'Para llevar', 'PICKUP': 'Recoger', 'DELIVERY': 'Delivery'};
const _weekdaysShort = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
const _weekdays = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
const _months = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];
const _monthsShort = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

String _iso(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
DateTime _date(String iso) => DateTime.parse('${iso}T00:00:00');
DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Hoy como día de operación (termina a las 4 a. m.).
DateTime _businessToday() => _dayOnly(DateTime.now().subtract(const Duration(hours: 4)));

String _longDate(DateTime d) {
  final w = _weekdays[d.weekday - 1];
  return '${w[0].toUpperCase()}${w.substring(1)} ${d.day} de ${_months[d.month - 1]} de ${d.year}';
}

String _shortDate(DateTime d, {bool year = false}) => '${d.day} ${_monthsShort[d.month - 1]}${year ? ' ${d.year}' : ''}';

/// Un período de días de operación (ambos incluidos).
class _Period {
  const _Period(this.from, this.to, this.label);
  final DateTime from;
  final DateTime to;
  final String label;

  bool get singleDay => from == to;
  (String, String) get key => (_iso(from), _iso(to));

  String get title {
    if (singleDay) return _longDate(from);
    final sameYear = from.year == to.year;
    return '${_shortDate(from, year: !sameYear)} – ${_shortDate(to, year: true)}';
  }
}

List<_Period> _presets() {
  final today = _businessToday();
  final monthStart = DateTime(today.year, today.month, 1);
  final lastMonthEnd = monthStart.subtract(const Duration(days: 1));
  return [
    _Period(today, today, 'Hoy'),
    _Period(today.subtract(const Duration(days: 1)), today.subtract(const Duration(days: 1)), 'Ayer'),
    _Period(today.subtract(const Duration(days: 6)), today, '7 días'),
    _Period(today.subtract(const Duration(days: 29)), today, '30 días'),
    _Period(monthStart, today, 'Este mes'),
    _Period(DateTime(lastMonthEnd.year, lastMonthEnd.month, 1), lastMonthEnd, 'Mes pasado'),
    _Period(DateTime(today.year, 1, 1), today, 'Este año'),
  ];
}

/// Reporte de ventas de un período (del, al: AAAA-MM-DD).
final salesReportProvider = FutureProvider.autoDispose.family<RJson, (String, String)>((ref, period) async {
  final dio = ref.watch(dioProvider);
  try {
    return (await dio.get<RJson>('/reports/sales', queryParameters: {'from': period.$1, 'to': period.$2})).data!;
  } catch (error) {
    throw ApiException.from(error);
  }
});

/// Reportes: ventas de un día (cierre del día) o de un período, con gráficas, comparación con el
/// período anterior, exportar a Excel e imprimir el cierre en la impresora de tickets.
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  late _Period _period = _presets().first;
  bool _busy = false;

  Future<void> _custom() async {
    final today = _businessToday();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: today,
      initialDateRange: DateTimeRange(start: _period.from, end: _period.to),
      helpText: 'Elige el período',
      saveText: 'Ver',
    );
    if (range == null) return;
    if (range.end.difference(range.start).inDays > 399) {
      if (mounted) showError(context, 'El período puede tener hasta 400 días');
      return;
    }
    setState(() => _period = _Period(_dayOnly(range.start), _dayOnly(range.end), 'Personalizado'));
  }

  void _step(int direction) {
    final days = _period.to.difference(_period.from).inDays + 1;
    final shift = Duration(days: days * direction);
    final from = _period.from.add(shift), to = _period.to.add(shift);
    if (to.isAfter(_businessToday())) return;
    setState(() => _period = _Period(from, to, ''));
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final data = (await ref.read(dioProvider).post<RJson>('/reports/export-link', data: {'from': _iso(_period.from), 'to': _iso(_period.to)})).data!;
      final ok = await launchUrl(Uri.parse(data['url'] as String), mode: LaunchMode.externalApplication);
      if (!ok && mounted) showError(context, 'No se pudo abrir la descarga');
    } catch (error) {
      if (mounted) showError(context, ApiException.from(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _print(RJson report) async {
    if (ref.read(printerProvider).value == null) {
      await showPrinterSetup(context);
      if (ref.read(printerProvider).value == null) return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(printerProvider.notifier).printReport(report);
      if (mounted) showSuccess(context, 'Cierre del día impreso');
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final async = ref.watch(salesReportProvider(_period.key));
    final report = async.value;
    final presets = _presets();
    final today = _businessToday();

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        title: const Text('Reportes'),
        actions: [
          IconButton(tooltip: 'Actualizar', icon: const Icon(Icons.refresh_rounded), onPressed: () => ref.invalidate(salesReportProvider(_period.key))),
          AppBarAction(icon: Icons.table_view_rounded, label: 'Excel', filled: false, onPressed: _busy || report == null ? null : _export),
          if (canPrintHere && _period.singleDay && report != null) ...[
            const SizedBox(width: 8),
            AppBarAction(icon: Icons.print_rounded, label: 'Imprimir cierre', filled: false, onPressed: _busy ? null : () => _print(report)),
          ],
          const SizedBox(width: 12),
        ],
      ),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: pagePadding(context)),
            children: [
              for (final p in presets)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(p.label),
                    selected: _period.from == p.from && _period.to == p.to,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _period = p),
                  ),
                ),
              ActionChip(avatar: const Icon(Icons.date_range_rounded, size: 18), label: const Text('Elegir fechas'), onPressed: _custom),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(pagePadding(context), 4, pagePadding(context), 4),
          child: Row(children: [
            IconButton(tooltip: 'Período anterior', onPressed: () => _step(-1), icon: const Icon(Icons.chevron_left_rounded)),
            Expanded(
              child: Column(children: [
                Text(_period.title, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium),
                if (report != null)
                  Text(
                    _period.singleDay
                        ? (_period.from == today ? 'Cierre del día · en curso' : 'Cierre del día')
                        : '${report['days']} días · comparado con ${_shortDate(_date(report['previous']['from'] as String))} – ${_shortDate(_date(report['previous']['to'] as String))}',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: t.muted, fontSize: 12.5),
                  ),
              ]),
            ),
            IconButton(
              tooltip: 'Período siguiente',
              onPressed: _period.to.isBefore(today) ? () => _step(1) : null,
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ]),
        ),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(salesReportProvider(_period.key))),
            data: (r) => _ReportBody(report: r),
          ),
        ),
      ]),
    );
  }
}

// ───────────────────────── Cuerpo del reporte ─────────────────────────

class _ReportBody extends StatefulWidget {
  const _ReportBody({required this.report});
  final RJson report;

  @override
  State<_ReportBody> createState() => _ReportBodyState();
}

class _ReportBodyState extends State<_ReportBody> {
  bool _allProducts = false;

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final text = Theme.of(context).textTheme;
    final r = widget.report;
    final s = r['summary'] as RJson;
    final prev = (r['previous'] as RJson?)?['summary'] as RJson? ?? const {};
    double m(Object? v) => parseMoney(v);
    String f(Object? v) => formatMoney(parseMoney(v));
    List<RJson> list(String key) => (r[key] as List? ?? const []).cast<RJson>();
    final palette = [t.primary, t.info, t.success, t.accent, t.warning, t.danger, t.muted];

    Widget row(String label, String value, {bool bold = false, Color? color, String? hint}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: (bold ? text.titleMedium : text.bodyLarge)?.copyWith(color: color)),
                if (hint != null && hint.isNotEmpty) Text(hint, style: TextStyle(color: t.muted, fontSize: 12.5)),
              ]),
            ),
            const SizedBox(width: 12),
            Text(value, style: (bold ? text.titleMedium : text.bodyLarge)?.copyWith(color: color, fontFeatures: const [FontFeature.tabularFigures()])),
          ]),
        );
    Widget empty(String message) => Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(message, style: TextStyle(color: t.muted)));

    if ((s['orders'] as num? ?? 0) == 0 && (s['cancelledOrders'] as num? ?? 0) == 0) {
      return const EmptyState(icon: Icons.insights_rounded, message: 'No hay ventas en este período.');
    }

    // Tarjetas con la comparación contra el período anterior.
    final kpis = <(String, String, IconData, double, double)>[
      ('Ventas netas', f(s['netSales']), Icons.trending_up_rounded, m(s['netSales']), m(prev['netSales'])),
      ('Cobrado (neto)', f(s['netCollected']), Icons.payments_rounded, m(s['netCollected']), m(prev['netCollected'])),
      ('Propinas', f(s['tips']), Icons.volunteer_activism_rounded, m(s['tips']), m(prev['tips'])),
      ('Órdenes', '${s['orders']}', Icons.receipt_long_rounded, m(s['orders']), m(prev['orders'])),
      ('Ticket promedio', f(s['averageCheck']), Icons.functions_rounded, m(s['averageCheck']), m(prev['averageCheck'])),
      ('Clientes en mesa', '${s['guests']}', Icons.people_alt_rounded, m(s['guests']), m(prev['guests'])),
    ];

    // Ventas en el tiempo: por día, por semana o por mes según el largo del período.
    final days = list('byDay');
    final timeBars = _groupDays(days);

    final hours = list('hours');
    final hourBars = <_Bar>[];
    if (hours.isNotEmpty) {
      final first = hours.map((h) => (h['hour'] as num).toInt()).reduce(math.min);
      final last = hours.map((h) => (h['hour'] as num).toInt()).reduce(math.max);
      for (var hour = first; hour <= last; hour++) {
        final h = hours.where((x) => x['hour'] == hour).firstOrNull;
        final label = DateFormat.j().format(DateTime(2000, 1, 1, hour));
        hourBars.add(_Bar(label, m(h?['net']), '$label · ${f(h?['net'])} · ${h?['orders'] ?? 0} órdenes'));
      }
    }
    final weekdayBars = [
      for (var w = 0; w < 7; w++)
        () {
          final x = list('byWeekday').where((e) => e['weekday'] == w).firstOrNull;
          return _Bar(_weekdaysShort[w], m(x?['net']), '${_weekdaysShort[w]} · ${f(x?['net'])} · ${x?['orders'] ?? 0} órdenes');
        }(),
    ];

    final payments = list('payments');
    final channels = list('channels');
    final products = list('products');
    final categories = list('categories');

    final charts = <Widget>[
      if (timeBars.length > 1)
        _Section(
          title: (r['days'] as num) <= 31 ? 'Ventas por día' : ((r['days'] as num) <= 120 ? 'Ventas por semana' : 'Ventas por mes'),
          wide: true,
          children: [_BarChart(bars: timeBars, color: t.primary, money: true)],
        ),
      _Section(title: 'Formas de pago', children: [
        if (payments.isEmpty)
          empty('Sin cobros.')
        else
          _Donut(entries: [
            for (final (i, p) in payments.indexed) _Slice(paymentMethodLabels[p['method']] ?? '${p['method']}', m(p['amount']), palette[i % palette.length], '${p['count']} cobros'),
          ]),
      ]),
      _Section(title: 'Por canal', children: [
        if (channels.isEmpty)
          empty('Sin ventas.')
        else
          _Donut(entries: [
            for (final (i, c) in channels.indexed) _Slice(_channelLabels[c['channel']] ?? '${c['channel']}', m(c['net']), palette[i % palette.length], '${c['orders']} órdenes'),
          ]),
      ]),
      if (hourBars.isNotEmpty) _Section(title: 'Horas pico', children: [_BarChart(bars: hourBars, color: t.accent, money: true)]),
      if ((r['days'] as num) >= 7) _Section(title: 'Día de la semana', children: [_BarChart(bars: weekdayBars, color: t.info, money: true)]),
      _Section(title: 'Productos más vendidos', children: [
        if (products.isEmpty) empty('Sin ventas.'),
        _HBars(items: [
          for (final p in (_allProducts ? products : products.take(10))) _Bar('${p['quantity']}× ${p['name']}', m(p['net']), f(p['net'])),
        ], color: t.success),
        if (products.length > 10)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: () => setState(() => _allProducts = !_allProducts), child: Text(_allProducts ? 'Ver menos' : 'Ver los ${products.length}')),
          ),
      ]),
      _Section(title: 'Por categoría', children: [
        if (categories.isEmpty) empty('Sin ventas.'),
        _HBars(items: [for (final c in categories) _Bar('${c['name']} · ${c['quantity']}', m(c['net']), f(c['net']))], color: t.info),
      ]),
    ];

    final tables = <Widget>[
      _Section(title: 'Cobros', children: [
        for (final p in payments)
          row(
            '${paymentMethodLabels[p['method']] ?? p['method']} · ${p['count']}',
            f(p['amount']),
            hint: [if (m(p['tips']) > 0) 'propinas ${f(p['tips'])}', if (m(p['refunded']) > 0) 'reembolsado ${f(p['refunded'])}'].join(' · '),
          ),
        Divider(color: t.line),
        row('Total cobrado', f(s['collected']), bold: true),
        if (m(s['refunded']) > 0) row('Reembolsos', '−${f(s['refunded'])}', color: t.danger),
        row('Neto', f(s['netCollected']), bold: true),
        if (m(s['pending']) > 0) row('Por cobrar (${s['openBills']} cuentas abiertas)', f(s['pending']), color: t.accentText),
      ]),
      _Section(title: 'Ventas', children: [
        row('Ventas brutas', f(s['grossSales'])),
        row('Descuentos y promociones', '−${f(s['discounts'])}', color: t.success),
        row('Ventas netas', f(s['netSales']), bold: true),
        row('Impuestos', f(s['tax'])),
        if (m(s['deliveryFees']) > 0) row('Envíos', f(s['deliveryFees'])),
        row('Propinas', f(s['tips'])),
        row('Total de las cuentas', f(s['total']), bold: true),
        for (final c in list('fulfillment')) row('${_fulfillmentLabels[c['type']] ?? c['type']} · ${c['orders']}', f(c['net'])),
        if (s['cancelledOrders'] != 0) row('Órdenes canceladas', '${s['cancelledOrders']}', color: t.danger),
      ]),
      _Section(title: 'Quién atendió', children: [
        if (list('servers').isEmpty) empty('Sin cuentas.'),
        for (final p in list('servers'))
          row('${p['name']} · ${p['bills']} ${p['bills'] == 1 ? 'cuenta' : 'cuentas'}', f(p['net']), hint: m(p['tips']) > 0 ? 'propinas ${f(p['tips'])}' : null),
      ]),
      _Section(title: 'Quién cobró', children: [
        if (list('cashiers').isEmpty) empty('Sin cobros.'),
        for (final p in list('cashiers'))
          row('${p['name']} · ${p['payments']} ${p['payments'] == 1 ? 'cobro' : 'cobros'}', f(p['amount']), hint: m(p['tips']) > 0 ? 'propinas ${f(p['tips'])}' : null),
      ]),
      _Section(title: 'Descuentos', children: [
        if (list('discounts').isEmpty && list('promotions').isEmpty) empty('Sin descuentos.'),
        for (final p in list('promotions')) row('Promoción: ${p['name']} · ${p['count']}', '−${f(p['amount'])}', color: t.success),
        for (final d in list('discounts'))
          row('${d['bill']} · ${d['reason']}', '−${f(d['amount'])}',
              hint: 'Aplicó ${d['appliedBy']}${d['authorizedBy'] != null ? ' · autorizó ${d['authorizedBy']}' : ''}'),
      ]),
      _Section(title: 'Reembolsos y cancelaciones', children: [
        if (list('refunds').isEmpty && list('cancellations').isEmpty) empty('Sin reembolsos ni cancelaciones.'),
        for (final x in list('refunds'))
          row('Reembolso ${x['bill']} · ${paymentMethodLabels[x['method']] ?? x['method']}', '−${f(x['amount'])}',
              color: t.danger, hint: '${x['reason']} · ${x['employee']} · ${DateFormat.MMMd().add_jm().format(DateTime.parse(x['createdAt'] as String).toLocal())}'),
        for (final c in list('cancellations'))
          row('Orden #${c['number']} cancelada', f(c['amount']), hint: [c['reason'] ?? 'Sin motivo', if (c['by'] != null) c['by']].join(' · ')),
      ]),
      _Section(title: 'Caja', children: [
        if (list('shifts').isEmpty) empty('No se abrió la caja en este período.'),
        for (final sh in list('shifts'))
          row(
            'Turno de ${sh['openedBy'] ?? '—'}',
            sh['difference'] == null ? (sh['closedAt'] == null ? 'abierto' : '—') : 'dif. ${f(sh['difference'])}',
            color: sh['difference'] == null ? null : (m(sh['difference']).abs() < 0.005 ? t.success : t.danger),
            hint: '${DateFormat.MMMd().add_jm().format(DateTime.parse(sh['openedAt'] as String).toLocal())}'
                ' · esperado ${f(sh['expectedCash'])}${sh['countedCash'] != null ? ' · contado ${f(sh['countedCash'])}' : ''}',
          ),
      ]),
    ];

    return LayoutBuilder(builder: (context, box) {
      final pad = pagePadding(context);
      final width = box.maxWidth - pad * 2;
      final kpiCols = width < 600 ? 2 : (width < 1000 ? 3 : 6);
      final kpiWidth = (width - 10 * (kpiCols - 1)) / kpiCols;
      final cols = width >= 1000 ? 2 : 1;
      final half = cols == 2 ? (width - 16) / 2 : width;
      return ListView(padding: EdgeInsets.fromLTRB(pad, 4, pad, 32), children: [
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (final (label, value, icon, now, before) in kpis) SizedBox(width: kpiWidth, child: _Kpi(label: label, value: value, icon: icon, now: now, before: before)),
        ]),
        const SizedBox(height: 16),
        Wrap(spacing: 16, runSpacing: 16, children: [
          for (final c in charts) SizedBox(width: c is _Section && c.wide ? width : half, child: c),
          for (final c in tables) SizedBox(width: half, child: c),
        ]),
        const SizedBox(height: 12),
        Text(
          'Cada día de operación termina a las 4:00 a. m. · generado ${DateFormat.jm().format(DateTime.parse(r['generatedAt'] as String).toLocal())}',
          textAlign: TextAlign.center,
          style: TextStyle(color: t.faint, fontSize: 12),
        ),
      ]);
    });
  }

  /// Hasta 31 días: uno por día. Hasta 120: por semana (lunes). Más: por mes.
  List<_Bar> _groupDays(List<RJson> days) {
    final total = days.length;
    String f(double v) => formatMoney(v);
    if (total <= 31) {
      return [
        for (final d in days)
          () {
            final date = _date(d['date'] as String);
            return _Bar('${date.day}', parseMoney(d['net']), '${_shortDate(date)} · ${f(parseMoney(d['net']))} · ${d['orders']} órdenes');
          }(),
      ];
    }
    final groups = <String, (DateTime, double, int)>{};
    for (final d in days) {
      final date = _date(d['date'] as String);
      final start = total <= 120 ? date.subtract(Duration(days: date.weekday - 1)) : DateTime(date.year, date.month, 1);
      final key = _iso(start);
      final current = groups[key] ?? (start, 0.0, 0);
      groups[key] = (start, current.$2 + parseMoney(d['net']), current.$3 + (d['orders'] as num).toInt());
    }
    final weekly = total <= 120;
    return [
      for (final g in groups.values)
        _Bar(
          weekly ? _shortDate(g.$1) : _monthsShort[g.$1.month - 1],
          g.$2,
          '${weekly ? 'Semana del ${_shortDate(g.$1)}' : '${_months[g.$1.month - 1]} ${g.$1.year}'} · ${f(g.$2)} · ${g.$3} órdenes',
        ),
    ];
  }
}

// ───────────────────────── Piezas ─────────────────────────

class _Kpi extends StatelessWidget {
  const _Kpi({required this.label, required this.value, required this.icon, required this.now, required this.before});
  final String label;
  final String value;
  final IconData icon;
  final double now;
  final double before;

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final change = before.abs() < 0.005 ? null : (now - before) / before.abs();
    final up = (change ?? 0) >= 0;
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
        Text(
          change == null ? 'sin datos antes' : '${up ? '▲' : '▼'} ${(change.abs() * 100).toStringAsFixed(change.abs() < 0.1 ? 1 : 0)} % vs. anterior',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: change == null ? t.faint : (up ? t.success : t.danger), fontSize: 12.5, fontWeight: FontWeight.w700),
        ),
      ]),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children, this.wide = false});
  final String title;
  final List<Widget> children;

  /// Ocupa todo el ancho (gráfica de ventas en el tiempo).
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(color: t.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: t.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        ...children,
      ]),
    );
  }
}

class _Bar {
  const _Bar(this.label, this.value, this.tooltip);
  final String label;
  final double value;
  final String tooltip;
}

/// Columnas verticales con etiqueta abajo; tocar o pasar el mouse muestra el detalle.
class _BarChart extends StatelessWidget {
  const _BarChart({required this.bars, required this.color, this.money = false});
  final List<_Bar> bars;
  final Color color;
  final bool money;

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final max = bars.fold<double>(0, (a, b) => math.max(a, b.value));
    final every = (bars.length / 8).ceil().clamp(1, 1000);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(money ? 'máx. ${formatMoney(max)}' : 'máx. ${max.toStringAsFixed(0)}', style: TextStyle(color: t.faint, fontSize: 12)),
      const SizedBox(height: 6),
      SizedBox(
        height: 170,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (final b in bars)
            Expanded(
              child: Tooltip(
                message: b.tooltip,
                triggerMode: TooltipTriggerMode.tap,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: bars.length > 40 ? 0.5 : 2),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: FractionallySizedBox(
                      heightFactor: max <= 0 ? 0.01 : (b.value / max).clamp(0.01, 1.0),
                      widthFactor: 1,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: b.value <= 0 ? t.line : color,
                          borderRadius: BorderRadius.vertical(top: Radius.circular(bars.length > 40 ? 2 : 6)),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 6),
      Row(children: [
        for (final (i, b) in bars.indexed)
          Expanded(
            child: Text(
              i % every == 0 ? b.label : '',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.visible,
              softWrap: false,
              style: TextStyle(color: t.muted, fontSize: 11),
            ),
          ),
      ]),
    ]);
  }
}

/// Barras horizontales (productos, categorías).
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
              child: LinearProgressIndicator(
                value: max <= 0 ? 0 : b.value / max,
                minHeight: 8,
                color: color,
                backgroundColor: t.surface2,
              ),
            ),
          ]),
        ),
    ]);
  }
}

class _Slice {
  const _Slice(this.label, this.value, this.color, this.detail);
  final String label;
  final double value;
  final Color color;
  final String detail;
}

/// Dona con su leyenda (porcentaje, monto y detalle de cada parte).
class _Donut extends StatelessWidget {
  const _Donut({required this.entries});
  final List<_Slice> entries;

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final total = entries.fold<double>(0, (a, e) => a + e.value);
    final legend = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final e in entries)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Container(width: 12, height: 12, decoration: BoxDecoration(color: e.color, borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text('${total <= 0 ? 0 : (e.value / total * 100).round()} % · ${e.detail}', style: TextStyle(color: t.muted, fontSize: 12.5)),
              ]),
            ),
            Text(formatMoney(e.value)),
          ]),
        ),
    ]);
    final donut = SizedBox(
      width: 150,
      height: 150,
      child: CustomPaint(
        painter: _DonutPainter(entries, t.surface2),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Total', style: TextStyle(color: t.muted, fontSize: 12)),
            FittedBox(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 22), child: Text(formatMoney(total), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)))),
          ]),
        ),
      ),
    );
    return LayoutBuilder(builder: (context, box) {
      if (box.maxWidth < 420) {
        return Column(children: [donut, const SizedBox(height: 12), legend]);
      }
      return Row(children: [donut, const SizedBox(width: 20), Expanded(child: legend)]);
    });
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.entries, this.track);
  final List<_Slice> entries;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 22.0;
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: math.min(size.width, size.height) / 2 - stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = track);
    final total = entries.fold<double>(0, (a, e) => a + e.value);
    if (total <= 0) return;
    var start = -math.pi / 2;
    for (final e in entries) {
      final sweep = math.pi * 2 * e.value / total;
      canvas.drawArc(rect, start, math.max(0, sweep - 0.02), false, paint..color = e.color);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => old.entries != entries || old.track != track;
}
