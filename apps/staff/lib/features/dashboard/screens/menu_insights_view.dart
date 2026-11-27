import 'dart:math' as math;

import 'package:devepmax_ui/devepmax_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/ui/feedback.dart';
import '../../menu/widgets/common.dart';

typedef MJson = Map<String, dynamic>;

double _d(Object? v) => v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);
int _i(Object? v) => (v as num?)?.toInt() ?? 0;
String _iso(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);
const _monthsShort = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
String _short(DateTime d) => '${d.day} ${_monthsShort[d.month - 1]} ${d.year}';
String _pct(Object? v) => v == null ? '—' : '${_d(v).toStringAsFixed(_d(v).abs() < 10 ? 1 : 0)} %';

/// Período para Menú y Promociones (días de operación, ambos incluidos).
class MenuPeriod {
  const MenuPeriod(this.from, this.to, this.label);
  final DateTime from;
  final DateTime to;
  final String label;

  (String, String) get key => (_iso(from), _iso(to));

  static List<MenuPeriod> presets() {
    final today = _dayOnly(DateTime.now().subtract(const Duration(hours: 4)));
    final monthStart = DateTime(today.year, today.month, 1);
    final lastMonthEnd = monthStart.subtract(const Duration(days: 1));
    return [
      MenuPeriod(today.subtract(const Duration(days: 6)), today, '7 días'),
      MenuPeriod(today.subtract(const Duration(days: 29)), today, '30 días'),
      MenuPeriod(today.subtract(const Duration(days: 89)), today, '90 días'),
      MenuPeriod(monthStart, today, 'Este mes'),
      MenuPeriod(DateTime(lastMonthEnd.year, lastMonthEnd.month, 1), lastMonthEnd, 'Mes pasado'),
    ];
  }
}

final menuInsightsProvider = FutureProvider.autoDispose.family<MJson, (String, String)>((ref, period) async {
  final dio = ref.watch(dioProvider);
  try {
    return (await dio.get<MJson>('/dashboard/menu', queryParameters: {'from': period.$1, 'to': period.$2})).data!;
  } catch (error) {
    throw ApiException.from(error);
  }
});

const _classLabels = {'star': 'Estrella', 'plowhorse': 'Caballo de batalla', 'puzzle': 'Enigma', 'dog': 'Perro'};
const _classIcons = {
  'star': Icons.star_rounded,
  'plowhorse': Icons.agriculture_rounded,
  'puzzle': Icons.help_center_rounded,
  'dog': Icons.pets_rounded,
};
const _classAdvice = {
  'star': 'Se venden mucho y dejan buen margen. Cuídalos y que se vean primero.',
  'plowhorse': 'Se venden mucho pero dejan poco. Revisa precio, porción o receta.',
  'puzzle': 'Dejan buen margen pero se venden poco. Promuévelos: mejor foto, lugar o sugerencia del mesero.',
  'dog': 'Se venden poco y dejan poco. Cámbialos o quítalos del menú.',
};
const _promoTypes = {'PERCENT_OFF': '% de descuento', 'AMOUNT_OFF': '\$ de descuento', 'BUY_X_GET_Y': 'Compra y lleva', 'COMBO_PRICE': 'Combo'};
const _couponTypes = {'PERCENT': '% de descuento', 'AMOUNT': '\$ de descuento', 'FREE_DELIVERY': 'Envío gratis'};

Color _classColor(BrandTokens t, String? c) => switch (c) {
      'star' => t.success,
      'plowhorse' => t.warning,
      'puzzle' => t.info,
      'dog' => t.danger,
      _ => t.muted,
    };

Color _foodCostColor(BrandTokens t, Object? pct) {
  if (pct == null) return t.muted;
  final v = _d(pct);
  return v <= 30 ? t.success : (v <= 40 ? t.warning : t.danger);
}

// ───────────────────────── Piezas compartidas ─────────────────────────

class _PeriodBar extends StatelessWidget {
  const _PeriodBar({required this.period, required this.onPeriod, required this.data});
  final MenuPeriod period;
  final ValueChanged<MenuPeriod> onPeriod;
  final MJson? data;

  Future<void> _custom(BuildContext context) async {
    final today = _dayOnly(DateTime.now().subtract(const Duration(hours: 4)));
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: today,
      initialDateRange: DateTimeRange(start: period.from, end: period.to),
      helpText: 'Elige el período',
      saveText: 'Ver',
    );
    if (range == null) return;
    if (range.end.difference(range.start).inDays > 399) {
      if (context.mounted) showError(context, 'El período puede tener hasta 400 días');
      return;
    }
    onPeriod(MenuPeriod(_dayOnly(range.start), _dayOnly(range.end), 'Personalizado'));
  }

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        height: 48,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: pagePadding(context)),
          children: [
            for (final p in MenuPeriod.presets())
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(p.label),
                  selected: period.from == p.from && period.to == p.to,
                  showCheckmark: false,
                  onSelected: (_) => onPeriod(p),
                ),
              ),
            ActionChip(avatar: const Icon(Icons.date_range_rounded, size: 18), label: const Text('Elegir fechas'), onPressed: () => _custom(context)),
          ],
        ),
      ),
      Padding(
        padding: EdgeInsets.fromLTRB(pagePadding(context), 2, pagePadding(context), 6),
        child: Text(
          '${_short(period.from)} – ${_short(period.to)}${data == null ? '' : ' · ${_i(data!['days'])} días'}',
          style: TextStyle(color: t.muted, fontSize: 12.5),
        ),
      ),
    ]);
  }
}

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
  const _Kpi({required this.label, required this.value, required this.icon, this.note, this.noteColor});
  final String label;
  final String value;
  final IconData icon;
  final String? note;
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
        if (note != null) ...[
          const SizedBox(height: 2),
          Text(note!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: noteColor ?? t.faint, fontSize: 12.5, fontWeight: FontWeight.w700)),
        ],
      ]),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(color: t.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: t.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              if (subtitle != null) Text(subtitle!, style: TextStyle(color: t.muted, fontSize: 12.5)),
            ]),
          ),
          if (trailing != null) trailing!,
        ]),
        const SizedBox(height: 10),
        ...children,
      ]),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.label, this.color, {this.icon});
  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 14, color: color), const SizedBox(width: 4)],
        Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800)),
      ]),
    );
  }
}

/// Esqueleto común: período arriba y el contenido del análisis abajo.
class _InsightsFrame extends ConsumerWidget {
  const _InsightsFrame({required this.period, required this.onPeriod, required this.builder});
  final MenuPeriod period;
  final ValueChanged<MenuPeriod> onPeriod;
  final Widget Function(BuildContext context, MJson data) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = BrandTokens.of(context);
    final async = ref.watch(menuInsightsProvider(period.key));
    return ColoredBox(
      color: t.bg,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: 8),
        _PeriodBar(period: period, onPeriod: onPeriod, data: async.value),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(menuInsightsProvider(period.key))),
            data: (d) => RefreshIndicator(
              onRefresh: () async => ref.invalidate(menuInsightsProvider(period.key)),
              child: builder(context, d),
            ),
          ),
        ),
      ]),
    );
  }
}

// ───────────────────────── Menú ─────────────────────────

/// Pestaña Menú: qué platos venden, cuánto dejan y en qué cuadrante quedan.
class MenuInsightsView extends StatefulWidget {
  const MenuInsightsView({super.key, required this.period, required this.onPeriod});
  final MenuPeriod period;
  final ValueChanged<MenuPeriod> onPeriod;

  @override
  State<MenuInsightsView> createState() => _MenuInsightsViewState();
}

class _MenuInsightsViewState extends State<MenuInsightsView> {
  /// null = todos; 'none' = sin receta; o un cuadrante.
  String? _filter;
  String _sort = 'margin';

  @override
  Widget build(BuildContext context) {
    return _InsightsFrame(period: widget.period, onPeriod: widget.onPeriod, builder: _content);
  }

  Widget _content(BuildContext context, MJson data) {
    final t = BrandTokens.of(context);
    final pad = pagePadding(context);
    final s = (data['summary'] as MJson?) ?? const {};
    final classes = (s['classes'] as MJson?) ?? const {};
    final dishes = ((data['dishes'] as List?) ?? const []).cast<MJson>();
    final unsold = ((data['unsold'] as List?) ?? const []).cast<MJson>();

    if (dishes.isEmpty && unsold.isEmpty) {
      return ListView(children: const [SizedBox(height: 60), EmptyState(icon: Icons.restaurant_menu_rounded, message: 'No hay ventas en este período.')]);
    }

    final shown = dishes.where((d) => _filter == null || (_filter == 'none' ? d['cost'] == null : d['class'] == _filter)).toList()
      ..sort((a, b) => switch (_sort) {
            'quantity' => _i(b['quantity']).compareTo(_i(a['quantity'])),
            'foodCost' => (b['foodCostPct'] == null ? -1.0 : _d(b['foodCostPct'])).compareTo(a['foodCostPct'] == null ? -1.0 : _d(a['foodCostPct'])),
            'net' => _d(b['net']).compareTo(_d(a['net'])),
            _ => (b['margin'] == null ? -1e12 : _d(b['margin'])).compareTo(a['margin'] == null ? -1e12 : _d(a['margin'])),
          });
    final unsoldShown = unsold.where((u) => _filter == null || (_filter == 'none' ? u['unitMargin'] == null : u['class'] == _filter)).toList();
    final withoutRecipe = _i(s['withoutRecipe']);

    return ListView(
      padding: EdgeInsets.fromLTRB(pad, 4, pad, 32),
      children: [
        _Grid(minWidth: 200, children: [
          _Kpi(label: 'Ventas de platos', value: formatMoney(_d(s['net'])), icon: Icons.trending_up_rounded, note: '${_i(s['units'])} platos · ${_i(s['orders'])} órdenes'),
          _Kpi(
            label: 'Costo de ingredientes',
            value: formatMoney(_d(s['cost'])),
            icon: Icons.inventory_2_rounded,
            note: s['foodCostPct'] == null ? 'sin recetas todavía' : 'food cost ${_pct(s['foodCostPct'])}',
            noteColor: _foodCostColor(t, s['foodCostPct']),
          ),
          _Kpi(
            label: 'Margen bruto',
            value: formatMoney(_d(s['margin'])),
            icon: Icons.savings_rounded,
            note: 'promedio ${formatMoney(_d(s['marginLine']))} por plato',
          ),
          _Kpi(
            label: 'Platos vendidos',
            value: '${_i(s['dishesSold'])}',
            icon: Icons.restaurant_rounded,
            note: '${unsold.length} sin venta',
            noteColor: unsold.isEmpty ? null : t.warning,
          ),
        ]),
        if (withoutRecipe > 0 || (s['costCoverage'] != null && _d(s['costCoverage']) < 99.5)) ...[
          const SizedBox(height: 12),
          Material(
            color: t.infoSoft,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => context.go('/inventory'),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  Icon(Icons.info_rounded, color: t.info),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '$withoutRecipe ${withoutRecipe == 1 ? 'plato vendido no tiene' : 'platos vendidos no tienen'} receta: su costo y margen no se calculan '
                      '(${_pct(s['costCoverage'])} de las ventas tiene costo). Agrega las recetas en Inventario → Recetas y costos.',
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: t.muted),
                ]),
              ),
            ),
          ),
        ],
        const SizedBox(height: 14),
        _Section(
          title: 'Ingeniería de menú',
          subtitle: 'Cada plato contra el promedio: popular si vende al menos ${_d(s['popularityLine']).toStringAsFixed(1)} unidades; rentable si deja ${formatMoney(_d(s['marginLine']))} o más por plato.',
          children: [
            _Grid(minWidth: 260, children: [
              for (final c in const ['star', 'plowhorse', 'puzzle', 'dog'])
                _Quadrant(
                  kind: c,
                  count: _i(classes[c]),
                  names: [
                    ...dishes.where((d) => d['class'] == c).map((d) => '${d['name']}'),
                    ...unsold.where((u) => u['class'] == c).map((u) => '${u['name']}'),
                  ],
                  selected: _filter == c,
                  onTap: () => setState(() => _filter = _filter == c ? null : c),
                ),
            ]),
          ],
        ),
        const SizedBox(height: 14),
        _Section(
          title: 'Platos vendidos',
          subtitle: 'Ventas después de promociones; costo del inventario o, si no hay, de la receta.',
          children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              ChoiceChip(label: const Text('Todos'), selected: _filter == null, showCheckmark: false, onSelected: (_) => setState(() => _filter = null)),
              for (final c in const ['star', 'plowhorse', 'puzzle', 'dog'])
                ChoiceChip(label: Text(_classLabels[c]!), selected: _filter == c, showCheckmark: false, onSelected: (_) => setState(() => _filter = c)),
              ChoiceChip(label: const Text('Sin receta'), selected: _filter == 'none', showCheckmark: false, onSelected: (_) => setState(() => _filter = 'none')),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Text('Ordenar por', style: TextStyle(color: t.muted)),
              const SizedBox(width: 8),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    for (final (key, label) in const [('margin', 'Margen'), ('quantity', 'Vendidos'), ('net', 'Ventas'), ('foodCost', 'Food cost')])
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(label),
                          selected: _sort == key,
                          showCheckmark: false,
                          visualDensity: VisualDensity.compact,
                          onSelected: (_) => setState(() => _sort = key),
                        ),
                      ),
                  ]),
                ),
              ),
            ]),
            const SizedBox(height: 6),
            if (shown.isEmpty)
              Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text('Ningún plato vendido en este grupo.', style: TextStyle(color: t.muted)))
            else
              for (final d in shown) _DishRow(dish: d),
          ],
        ),
        const SizedBox(height: 14),
        _Section(
          title: 'Sin venta en el período',
          subtitle: 'Platos activos que nadie pidió.',
          children: [
            if (unsoldShown.isEmpty)
              Text(unsold.isEmpty ? 'Todos los platos activos se vendieron al menos una vez. 🎉' : 'Ninguno en este grupo.', style: TextStyle(color: t.muted))
            else
              for (final u in unsoldShown)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${u['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text(
                          [
                            '${u['category']}',
                            formatMoney(_d(u['price'])),
                            if (u['unitMargin'] != null) 'deja ${formatMoney(_d(u['unitMargin']))} c/u' else 'sin receta',
                            if (_i(u['addedDaysAgo']) < 14) 'nuevo (hace ${_i(u['addedDaysAgo'])} días)',
                          ].join(' · '),
                          style: TextStyle(color: t.muted, fontSize: 13),
                        ),
                      ]),
                    ),
                    if (u['available'] == false) ...[_Tag('Agotado', t.danger), const SizedBox(width: 6)],
                    if (u['class'] != null) _Tag(_classLabels[u['class']]!, _classColor(t, u['class'] as String?), icon: _classIcons[u['class']]),
                  ]),
                ),
          ],
        ),
      ],
    );
  }
}

class _Quadrant extends StatelessWidget {
  const _Quadrant({required this.kind, required this.count, required this.names, required this.selected, required this.onTap});
  final String kind;
  final int count;
  final List<String> names;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final color = _classColor(t, kind);
    return Material(
      color: color.withValues(alpha: selected ? 0.2 : 0.09),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: selected ? color : Colors.transparent, width: 2)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(_classIcons[kind], color: color),
              const SizedBox(width: 8),
              Expanded(child: Text(_classLabels[kind]!, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 16))),
              Text('$count', style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 22)),
            ]),
            const SizedBox(height: 6),
            Text(_classAdvice[kind]!, style: TextStyle(color: t.muted, fontSize: 12.5)),
            if (names.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                names.length <= 4 ? names.join(', ') : '${names.take(4).join(', ')} y ${names.length - 4} más',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

class _DishRow extends StatelessWidget {
  const _DishRow({required this.dish});
  final MJson dish;

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final d = dish;
    final cls = d['class'] as String?;
    final margin = d['margin'];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.line))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text('${d['name']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              if (cls != null) _Tag(_classLabels[cls]!, _classColor(t, cls), icon: _classIcons[cls]),
              if (d['active'] == false) _Tag('Inactivo', t.muted),
            ]),
            const SizedBox(height: 2),
            Text(
              [
                if (d['category'] != null) '${d['category']}',
                '${_i(d['quantity'])} vendidos (${_pct(d['mix'])})',
                if (d['unitMargin'] != null) 'deja ${formatMoney(_d(d['unitMargin']))} c/u',
                if (d['costSource'] == 'recipe') 'costo según receta',
              ].join(' · '),
              style: TextStyle(color: t.muted, fontSize: 13),
            ),
          ]),
        ),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(formatMoney(_d(d['net'])), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          Text(
            margin == null ? 'sin receta' : 'margen ${formatMoney(_d(margin))}',
            style: TextStyle(color: margin == null ? t.faint : (_d(margin) >= 0 ? t.success : t.danger), fontSize: 13, fontWeight: FontWeight.w700),
          ),
          if (d['foodCostPct'] != null)
            Text('food cost ${_pct(d['foodCostPct'])}', style: TextStyle(color: _foodCostColor(t, d['foodCostPct']), fontSize: 12.5, fontWeight: FontWeight.w700)),
        ]),
      ]),
    );
  }
}

// ───────────────────────── Promociones ─────────────────────────

/// Pestaña Promociones: cuánto costaron las promociones, los cupones y los descuentos manuales.
class PromotionsInsightsView extends StatelessWidget {
  const PromotionsInsightsView({super.key, required this.period, required this.onPeriod});
  final MenuPeriod period;
  final ValueChanged<MenuPeriod> onPeriod;

  @override
  Widget build(BuildContext context) => _InsightsFrame(period: period, onPeriod: onPeriod, builder: _content);

  Widget _content(BuildContext context, MJson data) {
    final t = BrandTokens.of(context);
    final pad = pagePadding(context);
    final p = (data['promotions'] as MJson?) ?? const {};
    final promos = ((p['promotions'] as List?) ?? const []).cast<MJson>();
    final coupons = ((p['coupons'] as List?) ?? const []).cast<MJson>();
    final manual = (p['manual'] as MJson?) ?? const {};
    final avg = _d(p['averageOrder']);

    Widget ticket(Object? value) {
      if (value == null || avg <= 0) return const SizedBox.shrink();
      final diff = (_d(value) - avg) / avg * 100;
      final up = diff >= 0;
      return Text(
        'ticket ${formatMoney(_d(value))} ${up ? '▲' : '▼'} ${diff.abs().toStringAsFixed(0)} % vs. promedio',
        style: TextStyle(color: up ? t.success : t.warning, fontSize: 12.5, fontWeight: FontWeight.w700),
      );
    }

    Widget row({required String title, required List<Widget> tags, required String detail, required double discount, required double sales, Object? averageOrder, String? note}) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.line))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ...tags,
              ]),
              const SizedBox(height: 2),
              Text(detail, style: TextStyle(color: t.muted, fontSize: 13)),
              if (note != null) Text(note, style: TextStyle(color: t.faint, fontSize: 12.5)),
            ]),
          ),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('−${formatMoney(discount)}', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: discount > 0 ? t.danger : t.muted)),
            Text('ventas ${formatMoney(sales)}', style: TextStyle(color: t.muted, fontSize: 13)),
            ticket(averageOrder),
          ]),
        ]),
      );
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(pad, 4, pad, 32),
      children: [
        _Grid(minWidth: 200, children: [
          _Kpi(
            label: 'Descuentos totales',
            value: formatMoney(_d(p['totalDiscount'])),
            icon: Icons.percent_rounded,
            note: p['discountPct'] == null ? null : '${_pct(p['discountPct'])} de las ventas',
            noteColor: _d(p['discountPct']) > 10 ? t.danger : null,
          ),
          _Kpi(label: 'Promociones', value: formatMoney(_d(p['promotionsTotal'])), icon: Icons.local_offer_rounded, note: '${promos.where((x) => _i(x['orders']) > 0).length} usadas'),
          _Kpi(label: 'Cupones', value: formatMoney(_d(p['couponsTotal'])), icon: Icons.confirmation_number_rounded, note: '${coupons.fold<int>(0, (a, c) => a + _i(c['uses']))} usos'),
          _Kpi(
            label: 'Descuentos manuales',
            value: formatMoney(_d(manual['amount'])),
            icon: Icons.pin_rounded,
            note: '${_i(manual['count'])} aplicados con PIN',
          ),
        ]),
        const SizedBox(height: 6),
        Text('Ticket promedio de todas las órdenes: ${formatMoney(avg)}', style: TextStyle(color: t.muted, fontSize: 12.5)),
        const SizedBox(height: 14),
        _Section(
          title: 'Promociones',
          subtitle: 'Cuánto costó cada una y cuánto se vendió en las órdenes donde se aplicó.',
          trailing: TextButton(onPressed: () => context.go('/promotions'), child: const Text('Administrar')),
          children: [
            if (promos.isEmpty)
              Text('No hay promociones activas ni usadas en el período.', style: TextStyle(color: t.muted))
            else
              for (final x in promos)
                row(
                  title: '${x['name']}',
                  tags: [
                    _Tag(_promoTypes[x['type']] ?? '${x['type']}', t.info),
                    if (x['active'] == false) _Tag('Pausada', t.muted),
                    if (x['byCoupon'] == true) _Tag('Con cupón', t.accentText),
                  ],
                  detail: _i(x['orders']) == 0
                      ? 'Sin usos en el período'
                      : '${_i(x['orders'])} órdenes · ${_i(x['units'])} platos${x['discountPct'] == null ? '' : ' · descuento del ${_pct(x['discountPct'])}'}',
                  discount: _d(x['discount']),
                  sales: _d(x['sales']),
                  averageOrder: x['averageOrder'],
                ),
          ],
        ),
        const SizedBox(height: 14),
        _Section(
          title: 'Cupones',
          subtitle: 'Usos en órdenes no canceladas del período.',
          trailing: TextButton(onPressed: () => context.go('/coupons'), child: const Text('Administrar')),
          children: [
            if (coupons.isEmpty)
              Text('Ningún cupón se usó en este período.', style: TextStyle(color: t.muted))
            else
              for (final c in coupons)
                row(
                  title: '${c['code']}',
                  tags: [
                    _Tag(_couponTypes[c['type']] ?? '${c['type']}', t.info),
                    if (c['active'] == false) _Tag('Pausado', t.muted),
                  ],
                  detail: '${_i(c['uses'])} usos · ${_i(c['customers'])} clientes',
                  note: '${c['name'] ?? ''}'.isEmpty ? null : '${c['name']}',
                  discount: _d(c['discount']),
                  sales: _d(c['sales']),
                  averageOrder: c['averageOrder'],
                ),
          ],
        ),
      ],
    );
  }
}
