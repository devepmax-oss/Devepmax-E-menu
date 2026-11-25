import 'package:devepmax_ui/devepmax_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

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

String _day(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

/// Cierre del día de un día de operación (AAAA-MM-DD; null = hoy).
final dayReportProvider = FutureProvider.autoDispose.family<RJson, String?>((ref, day) async {
  final dio = ref.watch(dioProvider);
  try {
    return (await dio.get<RJson>('/reports/day', queryParameters: {if (day != null) 'date': day})).data!;
  } catch (error) {
    throw ApiException.from(error);
  }
});

/// Cierre del día: ventas, cobros por forma de pago, propinas, productos, personas, descuentos,
/// reembolsos, cancelaciones y turnos de caja. Se puede imprimir en la impresora de tickets.
class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({super.key});

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  String? _date; // null = hoy (día de operación según el servidor)
  bool _allProducts = false;
  bool _printing = false;

  void _shift(RJson report, int days) {
    final current = DateTime.parse(report['date'] as String);
    final next = current.add(Duration(days: days));
    setState(() => _date = _day(next));
  }

  Future<void> _pick(RJson report) async {
    final current = DateTime.parse(report['date'] as String);
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      helpText: 'Día de operación',
    );
    if (picked != null) setState(() => _date = _day(picked));
  }

  Future<void> _print(RJson report) async {
    if (ref.read(printerProvider).value == null) {
      await showPrinterSetup(context);
      if (ref.read(printerProvider).value == null) return;
    }
    setState(() => _printing = true);
    try {
      await ref.read(printerProvider.notifier).printReport(report);
      if (mounted) showSuccess(context, 'Cierre impreso');
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final async = ref.watch(dayReportProvider(_date));
    final report = async.value;

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        title: const Text('Cierre del día'),
        actions: [
          IconButton(tooltip: 'Actualizar', icon: const Icon(Icons.refresh_rounded), onPressed: () => ref.invalidate(dayReportProvider(_date))),
          if (canPrintHere && report != null)
            AppBarAction(
              icon: Icons.print_rounded,
              label: 'Imprimir',
              filled: false,
              onPressed: _printing ? null : () => _print(report),
            ),
          const SizedBox(width: 12),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(dayReportProvider(_date))),
        data: (r) => _ReportBody(
          report: r,
          allProducts: _allProducts,
          onAllProducts: () => setState(() => _allProducts = !_allProducts),
          onPrev: () => _shift(r, -1),
          onNext: () => _shift(r, 1),
          onPick: () => _pick(r),
          onToday: _date == null ? null : () => setState(() => _date = null),
        ),
      ),
    );
  }
}

class _ReportBody extends StatelessWidget {
  const _ReportBody({
    required this.report,
    required this.allProducts,
    required this.onAllProducts,
    required this.onPrev,
    required this.onNext,
    required this.onPick,
    required this.onToday,
  });
  final RJson report;
  final bool allProducts;
  final VoidCallback onAllProducts;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onPick;
  final VoidCallback? onToday;

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final text = Theme.of(context).textTheme;
    final s = report['summary'] as RJson;
    double m(Object? v) => parseMoney(v);
    String f(Object? v) => formatMoney(parseMoney(v));
    final date = DateTime.parse(report['date'] as String);
    final isToday = onToday == null;
    List<RJson> list(String key) => (report[key] as List? ?? const []).cast<RJson>();

    Widget row(String label, String value, {bool bold = false, Color? color, String? hint}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: (bold ? text.titleMedium : text.bodyLarge)?.copyWith(color: color)),
                if (hint != null) Text(hint, style: TextStyle(color: t.muted, fontSize: 12.5)),
              ]),
            ),
            const SizedBox(width: 12),
            Text(value, style: (bold ? text.titleMedium : text.bodyLarge)?.copyWith(color: color, fontFeatures: const [FontFeature.tabularFigures()])),
          ]),
        );

    Widget empty(String message) => Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(message, style: TextStyle(color: t.muted)));

    final kpis = <(String, String, IconData)>[
      ('Ventas netas', f(s['netSales']), Icons.trending_up_rounded),
      ('Cobrado (neto)', f(s['netCollected']), Icons.payments_rounded),
      ('Propinas', f(s['tips']), Icons.volunteer_activism_rounded),
      ('Órdenes', '${s['orders']}', Icons.receipt_long_rounded),
      ('Ticket promedio', f(s['averageCheck']), Icons.functions_rounded),
      ('Clientes en mesa', '${s['guests']}', Icons.people_alt_rounded),
    ];

    final hours = list('hours');
    final maxHour = hours.fold<double>(0, (a, h) => m(h['net']) > a ? m(h['net']) : a);
    final products = list('products');

    final sections = <Widget>[
      _Section(title: 'Formas de pago', children: [
        if (list('payments').isEmpty) empty('Sin cobros.'),
        for (final p in list('payments'))
          row(
            '${paymentMethodLabels[p['method']] ?? p['method']} · ${p['count']}',
            f(p['amount']),
            hint: [
              if (m(p['tips']) > 0) 'propinas ${f(p['tips'])}',
              if (m(p['refunded']) > 0) 'reembolsado ${f(p['refunded'])}',
            ].join(' · ').ifEmpty(),
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
        if (s['cancelledOrders'] != 0) row('Órdenes canceladas', '${s['cancelledOrders']}', color: t.danger),
      ]),
      _Section(title: 'Productos más vendidos', children: [
        if (products.isEmpty) empty('Todavía no hay ventas.'),
        for (final p in allProducts ? products : products.take(10)) row('${p['quantity']}× ${p['name']}', f(p['net'])),
        if (products.length > 10)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: onAllProducts, child: Text(allProducts ? 'Ver menos' : 'Ver los ${products.length}')),
          ),
      ]),
      _Section(title: 'Por categoría', children: [
        if (list('categories').isEmpty) empty('Sin ventas.'),
        for (final c in list('categories')) row('${c['name']} · ${c['quantity']}', f(c['net'])),
      ]),
      _Section(title: 'Por canal y tipo de pedido', children: [
        for (final c in list('channels')) row('${_channelLabels[c['channel']] ?? c['channel']} · ${c['orders']} órdenes', f(c['net'])),
        if (list('channels').isNotEmpty) Divider(color: t.line),
        for (final c in list('fulfillment')) row('${_fulfillmentLabels[c['type']] ?? c['type']} · ${c['orders']}', f(c['net'])),
        if (list('channels').isEmpty) empty('Sin ventas.'),
      ]),
      _Section(title: 'Ventas por hora', children: [
        if (hours.isEmpty) empty('Sin ventas.'),
        for (final h in hours)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              SizedBox(
                width: 58,
                child: Text(DateFormat.j().format(DateTime(2000, 1, 1, (h['hour'] as num).toInt())), style: TextStyle(color: t.muted)),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) => Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      height: 14,
                      width: maxHour <= 0 ? 0 : (box.maxWidth * m(h['net']) / maxHour).clamp(2, box.maxWidth),
                      decoration: BoxDecoration(color: t.primary, borderRadius: BorderRadius.circular(7)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(width: 86, child: Text(f(h['net']), textAlign: TextAlign.right)),
            ]),
          ),
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
          row(
            '${d['bill']} · ${d['reason']}',
            '−${f(d['amount'])}',
            hint: 'Aplicó ${d['appliedBy']}${d['authorizedBy'] != null ? ' · autorizó ${d['authorizedBy']}' : ''}',
          ),
      ]),
      _Section(title: 'Reembolsos', children: [
        if (list('refunds').isEmpty) empty('Sin reembolsos.'),
        for (final r in list('refunds'))
          row(
            '${r['bill']} · ${paymentMethodLabels[r['method']] ?? r['method']}',
            '−${f(r['amount'])}',
            color: t.danger,
            hint: '${r['reason']} · ${r['employee']} · ${DateFormat.jm().format(DateTime.parse(r['createdAt'] as String).toLocal())}',
          ),
      ]),
      _Section(title: 'Cancelaciones', children: [
        if (list('cancellations').isEmpty) empty('Sin cancelaciones.'),
        for (final c in list('cancellations'))
          row('Orden #${c['number']}', f(c['amount']), hint: [c['reason'] ?? 'Sin motivo', if (c['by'] != null) c['by']].join(' · ')),
      ]),
      _Section(title: 'Caja', children: [
        if (list('shifts').isEmpty) empty('No se abrió la caja este día.'),
        for (final sh in list('shifts')) ...[
          row(
            'Turno de ${sh['openedBy'] ?? '—'}',
            sh['closedAt'] == null ? 'abierto' : 'cerrado',
            bold: true,
            hint: '${DateFormat.jm().format(DateTime.parse(sh['openedAt'] as String).toLocal())}'
                '${sh['closedAt'] != null ? ' a ${DateFormat.jm().format(DateTime.parse(sh['closedAt'] as String).toLocal())}' : ''}',
          ),
          row('Fondo inicial', f(sh['openingCash'])),
          row('Efectivo esperado', f(sh['expectedCash'])),
          if (sh['countedCash'] != null) row('Contado', f(sh['countedCash'])),
          if (sh['difference'] != null)
            row('Diferencia', f(sh['difference']), color: m(sh['difference']).abs() < 0.005 ? t.success : t.danger, bold: true),
          const SizedBox(height: 8),
        ],
      ]),
    ];

    return LayoutBuilder(builder: (context, box) {
      final pad = pagePadding(context);
      final width = box.maxWidth - pad * 2;
      final kpiCols = width < 600 ? 2 : (width < 1000 ? 3 : 6);
      final kpiWidth = (width - 10 * (kpiCols - 1)) / kpiCols;
      final twoColumns = width >= 1000;
      final sectionWidth = twoColumns ? (width - 16) / 2 : width;
      return ListView(padding: EdgeInsets.fromLTRB(pad, 8, pad, 32), children: [
        Row(children: [
          IconButton.filledTonal(tooltip: 'Día anterior', onPressed: onPrev, icon: const Icon(Icons.chevron_left_rounded)),
          const SizedBox(width: 8),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onPick,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(children: [
                  Text(_longDate(date),
                      textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleMedium),
                  Text(isToday ? 'Hoy · en curso' : 'Toca para elegir otro día', style: TextStyle(color: t.muted, fontSize: 12.5)),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(tooltip: 'Día siguiente', onPressed: isToday ? null : onNext, icon: const Icon(Icons.chevron_right_rounded)),
          if (onToday != null) ...[
            const SizedBox(width: 8),
            TextButton(onPressed: onToday, child: const Text('Hoy')),
          ],
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (final (label, value, icon) in kpis)
            SizedBox(
              width: kpiWidth,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: t.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: t.line)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(icon, size: 18, color: t.accentText),
                    const SizedBox(width: 6),
                    Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.muted))),
                  ]),
                  const SizedBox(height: 6),
                  FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: text.headlineSmall)),
                ]),
              ),
            ),
        ]),
        const SizedBox(height: 16),
        Wrap(spacing: 16, runSpacing: 16, children: [
          for (final section in sections) SizedBox(width: sectionWidth, child: section),
        ]),
        const SizedBox(height: 12),
        Text(
          'Día de operación hasta las 4:00 a. m. · generado ${DateFormat.jm().format(DateTime.parse(report['generatedAt'] as String).toLocal())}',
          textAlign: TextAlign.center,
          style: TextStyle(color: t.faint, fontSize: 12),
        ),
      ]);
    });
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
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(color: t.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: t.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        ...children,
      ]),
    );
  }
}

const _weekdays = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
const _months = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];

/// "Martes 24 de noviembre de 2026" (sin depender de los datos de idioma de intl).
String _longDate(DateTime d) {
  final w = _weekdays[d.weekday - 1];
  return '${w[0].toUpperCase()}${w.substring(1)} ${d.day} de ${_months[d.month - 1]} de ${d.year}';
}

extension on String {
  String? ifEmpty() => isEmpty ? null : this;
}
