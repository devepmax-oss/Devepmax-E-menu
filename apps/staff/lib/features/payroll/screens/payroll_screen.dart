import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/ui/feedback.dart';
import '../../admin/screens/employees_screen.dart' show EmployeeAvatar;
import '../../menu/widgets/common.dart';
import '../../timeclock/data/timeclock_api.dart' show dayLabel, hoursLabel, isoDay, mondayOf, parseDay;
import '../../timeclock/screens/entry_dialog.dart' show EmptyNote;
import '../data/payroll_api.dart';

final _money = NumberFormat.simpleCurrency(locale: 'en_US');
String money(double v) => _money.format(v);

/// Nómina (horas normales, extra, sueldo y propinas), desempeño por empleado y tarifas por hora.
class PayrollScreen extends ConsumerWidget {
  const PayrollScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Nómina y desempeño'),
          bottom: const TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
            Tab(icon: Icon(Icons.payments_rounded), text: 'Nómina'),
            Tab(icon: Icon(Icons.insights_rounded), text: 'Desempeño'),
            Tab(icon: Icon(Icons.attach_money_rounded), text: 'Tarifas'),
          ]),
          actions: [
            TextButton.icon(
              onPressed: () => showDialog<void>(context: context, builder: (_) => const _RuleDialog()),
              icon: const Icon(Icons.rule_rounded),
              label: const Text('Horas extra'),
            ),
            const SizedBox(width: 16),
          ],
        ),
        body: const TabBarView(children: [_PayrollTab(), _PerformanceTab(), _RatesTab()]),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, {this.hint});
  final String label;
  final String value;
  final String? hint;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 200,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 4),
              Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              if (hint != null) Text(hint!, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ]),
          ),
        ),
      );
}

// ───────── Nómina ─────────

class _PayrollTab extends ConsumerStatefulWidget {
  const _PayrollTab();

  @override
  ConsumerState<_PayrollTab> createState() => _PayrollTabState();
}

class _PayrollTabState extends ConsumerState<_PayrollTab> {
  // Por defecto la semana pasada: la que ya terminó y se paga.
  DateTime _monday = mondayOf(DateTime.now()).subtract(const Duration(days: 7));
  int _weeks = 1;
  bool _exporting = false;

  PayrollQuery get _query => (week: isoDay(_monday), weeks: _weeks);

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final url = await ref.read(payrollApiProvider).exportLink(_query);
      final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!ok && mounted) showError(context, 'No se pudo abrir la descarga');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(payrollProvider(_query));
    final scheme = Theme.of(context).colorScheme;
    final step = Duration(days: 7 * _weeks);
    final end = _monday.add(Duration(days: 7 * _weeks - 1));

    return ListView(padding: const EdgeInsets.all(24), children: [
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        IconButton(
          tooltip: 'Período anterior',
          onPressed: () => setState(() => _monday = _monday.subtract(step)),
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Text('${dayLabel(isoDay(_monday))} – ${dayLabel(isoDay(end))}', style: Theme.of(context).textTheme.titleMedium),
        IconButton(
          tooltip: 'Período siguiente',
          onPressed: () => setState(() => _monday = _monday.add(step)),
          icon: const Icon(Icons.chevron_right_rounded),
        ),
        ChoiceChip(label: const Text('1 semana'), selected: _weeks == 1, onSelected: (_) => setState(() => _weeks = 1)),
        ChoiceChip(label: const Text('2 semanas'), selected: _weeks == 2, onSelected: (_) => setState(() => _weeks = 2)),
        TextButton(
          onPressed: () => setState(() => _monday = mondayOf(DateTime.now()).subtract(const Duration(days: 7))),
          child: const Text('Semana pasada'),
        ),
        TextButton(onPressed: () => setState(() => _monday = mondayOf(DateTime.now())), child: const Text('Esta semana')),
        FilledButton.icon(
          onPressed: _exporting ? null : _export,
          icon: const Icon(Icons.table_view_rounded),
          label: const Text('Excel para la nómina'),
        ),
      ]),
      const SizedBox(height: 16),
      async.when(
        loading: () => const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator())),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(payrollProvider(_query))),
        data: (p) {
          final noRate = p.rows.where((r) => r.daysWithoutRate > 0).toList();
          final open = p.rows.fold<int>(0, (a, r) => a + r.openEntries);
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(p.rule.description, style: TextStyle(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            Wrap(spacing: 12, runSpacing: 12, children: [
              _Stat('Sueldos', money(p.wages), hint: '${hoursLabel(p.regularMinutes)} normales'),
              _Stat('Horas extra', hoursLabel(p.overtimeMinutes + p.doubleMinutes),
                  hint: p.doubleMinutes > 0 ? '${hoursLabel(p.doubleMinutes)} dobles' : null),
              _Stat('Propinas con tarjeta', money(p.cardTips), hint: 'Se pagan en la nómina'),
              _Stat('Propinas en efectivo', money(p.cashTips), hint: 'Ya se las llevaron; se declaran'),
              _Stat('Total', money(p.total)),
            ]),
            if (noRate.isNotEmpty)
              Card(
                color: scheme.errorContainer,
                child: ListTile(
                  leading: const Icon(Icons.warning_amber_rounded),
                  title: Text('${noRate.length} ${noRate.length == 1 ? 'empleado no tiene' : 'empleados no tienen'} tarifa: '
                      'sus horas no suman al sueldo'),
                  subtitle: Text(noRate.map((r) => r.employee.name).join(', ')),
                  trailing: TextButton(
                    onPressed: () => DefaultTabController.of(context).animateTo(2),
                    child: const Text('Poner tarifa'),
                  ),
                ),
              ),
            if (open > 0)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.info_outline_rounded),
                  title: Text('$open ${open == 1 ? 'jornada sin salida no cuenta' : 'jornadas sin salida no cuentan'} todavía'),
                  subtitle: const Text('Corrígelas en Horarios → Asistencia para que se paguen.'),
                ),
              ),
            if (p.unassignedTips > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Propinas sin asignar (pedidos web sin empleado): ${money(p.unassignedTips)}',
                    style: TextStyle(color: scheme.onSurfaceVariant)),
              ),
            const SizedBox(height: 16),
            if (p.rows.isEmpty) const EmptyNote('Nadie trabajó ni recibió propinas en este período'),
            for (final r in p.rows) _PayrollCard(row: r, weeks: p.weeks),
          ]);
        },
      ),
    ]);
  }
}

class _PayrollCard extends StatelessWidget {
  const _PayrollCard({required this.row, required this.weeks});
  final PayrollRow row;
  final int weeks;

  @override
  Widget build(BuildContext context) {
    final r = row;
    final scheme = Theme.of(context).colorScheme;
    final extra = r.overtimeMinutes + r.doubleMinutes;
    final tips = r.cardTips + r.cashTips;
    return Card(
      child: ExpansionTile(
        leading: EmployeeAvatar(name: r.employee.name, photoUrl: r.employee.photoUrl),
        title: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(r.employee.name, style: const TextStyle(fontWeight: FontWeight.w600)),
          if (r.currentRate == null)
            StatusChip('Sin tarifa', color: scheme.error)
          else
            StatusChip('${money(r.currentRate!)}/h'),
        ]),
        subtitle: Text([
          '${hoursLabel(r.regularMinutes)} normales',
          if (extra > 0) '${hoursLabel(extra)} extra',
          if (tips > 0) 'propinas ${money(tips)}',
        ].join(' · ')),
        trailing: Text(money(r.total), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _line('Horas normales', hoursLabel(r.regularMinutes), money(r.regularPay)),
          if (r.overtimeMinutes > 0) _line('Horas extra', hoursLabel(r.overtimeMinutes), money(r.overtimePay)),
          if (r.doubleMinutes > 0) _line('Horas dobles', hoursLabel(r.doubleMinutes), money(r.doublePay)),
          _line('Sueldo', '', money(r.wages), strong: true),
          _line('Propinas con tarjeta', '', money(r.cardTips)),
          _line('Propinas en efectivo', '', money(r.cashTips)),
          const Divider(),
          _line('Total', '', money(r.total), strong: true),
          if (weeks > 1)
            for (final w in r.weeks)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Semana del ${dayLabel(w.weekStart)}: ${hoursLabel(w.regular)} normales'
                  '${w.overtime > 0 ? ' · ${hoursLabel(w.overtime)} extra' : ''}'
                  '${w.dbl > 0 ? ' · ${hoursLabel(w.dbl)} dobles' : ''}',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
          if (r.daysWithoutRate > 0)
            Text('${r.daysWithoutRate} días sin tarifa no se pagaron', style: TextStyle(color: scheme.error)),
          if (r.openEntries > 0)
            Text('${r.openEntries} jornadas sin salida no cuentan', style: TextStyle(color: scheme.error)),
        ],
      ),
    );
  }

  Widget _line(String label, String hours, String amount, {bool strong = false}) {
    final style = TextStyle(fontWeight: strong ? FontWeight.w800 : FontWeight.w500);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Expanded(child: Text(label, style: style)),
        SizedBox(width: 90, child: Text(hours, textAlign: TextAlign.right)),
        SizedBox(width: 110, child: Text(amount, textAlign: TextAlign.right, style: style)),
      ]),
    );
  }
}

// ───────── Desempeño ─────────

const _sorts = [('sales', 'Ventas'), ('tips', 'Propinas'), ('hours', 'Horas'), ('perHour', 'Ventas por hora'), ('ticket', 'Ticket promedio')];

class _PerformanceTab extends ConsumerStatefulWidget {
  const _PerformanceTab();

  @override
  ConsumerState<_PerformanceTab> createState() => _PerformanceTabState();
}

class _PerformanceTabState extends ConsumerState<_PerformanceTab> {
  DateTime _from = mondayOf(DateTime.now());
  DateTime _to = DateTime.now();
  String _sort = 'sales';

  RangeQuery get _query => (from: isoDay(_from), to: isoDay(_to));

  void _range(String which) {
    final now = DateTime.now();
    final monday = mondayOf(now);
    setState(() {
      switch (which) {
        case 'today':
          _from = now;
          _to = now;
        case 'week':
          _from = monday;
          _to = now;
        case 'last':
          _from = monday.subtract(const Duration(days: 7));
          _to = monday.subtract(const Duration(days: 1));
        case 'month':
          _from = DateTime(now.year, now.month, 1);
          _to = now;
      }
    });
  }

  Future<void> _custom() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _from, end: _to),
    );
    if (picked != null) {
      setState(() {
        _from = picked.start;
        _to = picked.end;
      });
    }
  }

  double _key(PerformanceRow r) => switch (_sort) {
        'tips' => r.tips,
        'hours' => r.workedMinutes.toDouble(),
        'perHour' => r.salesPerHour,
        'ticket' => r.averageTicket,
        _ => r.netSales,
      };

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(performanceProvider(_query));
    return ListView(padding: const EdgeInsets.all(24), children: [
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        ActionChip(label: const Text('Hoy'), onPressed: () => _range('today')),
        ActionChip(label: const Text('Esta semana'), onPressed: () => _range('week')),
        ActionChip(label: const Text('Semana pasada'), onPressed: () => _range('last')),
        ActionChip(label: const Text('Este mes'), onPressed: () => _range('month')),
        ActionChip(
          avatar: const Icon(Icons.date_range_rounded, size: 18),
          label: Text('${dayLabel(_query.from)} – ${dayLabel(_query.to)}'),
          onPressed: _custom,
        ),
        PopupMenuButton<String>(
          tooltip: 'Ordenar',
          onSelected: (v) => setState(() => _sort = v),
          itemBuilder: (_) => [for (final (v, l) in _sorts) PopupMenuItem(value: v, child: Text(l))],
          child: Chip(
            avatar: const Icon(Icons.sort_rounded, size: 18),
            label: Text('Por ${_sorts.firstWhere((s) => s.$1 == _sort).$2.toLowerCase()}'),
          ),
        ),
      ]),
      const SizedBox(height: 16),
      async.when(
        loading: () => const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator())),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(performanceProvider(_query))),
        data: (rows) {
          if (rows.isEmpty) return const EmptyNote('Sin movimiento de empleados en estas fechas');
          final sorted = [...rows]..sort((a, b) => _key(b).compareTo(_key(a)));
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final r in sorted) _PerformanceCard(row: r),
          ]);
        },
      ),
    ]);
  }
}

class _PerformanceCard extends StatelessWidget {
  const _PerformanceCard({required this.row});
  final PerformanceRow row;

  @override
  Widget build(BuildContext context) {
    final r = row;
    final scheme = Theme.of(context).colorScheme;
    Widget metric(String label, String value) => SizedBox(
          width: 130,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          ]),
        );
    final control = [
      if (r.cancellations > 0) '${r.cancellations} cancelaciones',
      if (r.voids > 0) '${r.voids} anulaciones (${money(r.voidAmount)})',
      if (r.discounts > 0) '${r.discounts} descuentos (${money(r.discountAmount)})',
      if (r.discountsAuthorized > 0) '${r.discountsAuthorized} descuentos autorizados',
      if (r.refunds > 0) '${r.refunds} reembolsos (${money(r.refundAmount)})',
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            EmployeeAvatar(name: r.employee.name, photoUrl: r.employee.photoUrl),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.employee.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                Text(r.employee.jobTitle ?? r.employee.roleName, style: TextStyle(color: scheme.onSurfaceVariant)),
              ]),
            ),
            Text(money(r.netSales), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 12, runSpacing: 12, children: [
            metric('Cuentas atendidas', '${r.bills}'),
            metric('Ticket promedio', money(r.averageTicket)),
            metric('Mesas · comensales', '${r.tables} · ${r.guests}'),
            metric('Propinas', '${money(r.tips)}${r.tipPercent > 0 ? ' (${r.tipPercent.toStringAsFixed(1)} %)' : ''}'),
            metric('Horas trabajadas', hoursLabel(r.workedMinutes)),
            metric('Ventas por hora', r.workedMinutes > 0 ? money(r.salesPerHour) : '—'),
            metric('Órdenes tomadas', '${r.ordersTaken}'),
            metric('Cobros', r.payments > 0 ? '${r.payments} · ${money(r.collected)}' : '0'),
          ]),
          if (control.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final c in control) StatusChip(c, color: Colors.orange),
            ]),
          ],
        ]),
      ),
    );
  }
}

// ───────── Tarifas ─────────

class _RatesTab extends ConsumerStatefulWidget {
  const _RatesTab();

  @override
  ConsumerState<_RatesTab> createState() => _RatesTabState();
}

class _RatesTabState extends ConsumerState<_RatesTab> {
  bool _showInactive = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(ratesProvider);
    final scheme = Theme.of(context).colorScheme;
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(ratesProvider)),
      data: (all) {
        final list = all.where((r) => r.isActive || _showInactive).toList();
        return ListView(padding: const EdgeInsets.all(24), children: [
          Row(children: [
            const Expanded(
              child: Text('Tarifa por hora de cada empleado. Un aumento con fecha se aplica desde ese día; '
                  'las semanas anteriores se siguen pagando con la tarifa de antes.'),
            ),
            FilterChip(
              label: const Text('Ver de baja'),
              selected: _showInactive,
              onSelected: (v) => setState(() => _showInactive = v),
            ),
          ]),
          const SizedBox(height: 16),
          for (final r in list)
            Card(
              child: ListTile(
                leading: EmployeeAvatar(name: r.employee.name, photoUrl: r.employee.photoUrl),
                title: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text(r.employee.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (!r.isActive) StatusChip('De baja', color: scheme.error),
                ]),
                subtitle: Text([
                  r.employee.jobTitle ?? r.employee.roleName,
                  if (r.nextChange != null) 'pasa a ${money(r.nextChange!.rate)}/h el ${dayLabel(r.nextChange!.from)}',
                ].join(' · ')),
                trailing: Text(
                  r.currentRate == null ? 'Sin tarifa' : '${money(r.currentRate!)}/h',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: r.currentRate == null ? scheme.error : null),
                ),
                onTap: () => showDialog<void>(context: context, builder: (_) => _RateDialog(info: r)),
              ),
            ),
        ]);
      },
    );
  }
}

class _RateDialog extends ConsumerStatefulWidget {
  const _RateDialog({required this.info});
  final RateInfo info;

  @override
  ConsumerState<_RateDialog> createState() => _RateDialogState();
}

class _RateDialogState extends ConsumerState<_RateDialog> {
  late final _rate = TextEditingController(
    text: widget.info.currentRate == null ? '' : widget.info.currentRate!.toStringAsFixed(2),
  );
  DateTime _from = DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    _rate.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final value = double.tryParse(_rate.text.trim().replaceAll(',', '.'));
    if (value == null || value < 0) {
      showError(context, 'Escribe la tarifa por hora (ej. 15.50)');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(payrollApiProvider).setRate(widget.info.employee.id, value, isoDay(_from));
      ref.invalidate(ratesProvider);
      ref.invalidate(payrollProvider);
      if (mounted) {
        Navigator.pop(context);
        showSuccess(context, 'Tarifa guardada');
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(String id) async {
    setState(() => _saving = true);
    try {
      await ref.read(payrollApiProvider).deleteRate(id);
      ref.invalidate(ratesProvider);
      ref.invalidate(payrollProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    return AlertDialog(
      scrollable: true,
      title: Text('Tarifa de ${info.employee.name}'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            controller: _rate,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            decoration: const InputDecoration(labelText: 'Dólares por hora', prefixText: '\$ ', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _from,
                firstDate: DateTime(2024),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (picked != null) setState(() => _from = picked);
            },
            icon: const Icon(Icons.calendar_month_rounded),
            label: Text('Vale desde: ${dayLabel(isoDay(_from))}'),
          ),
          const SizedBox(height: 4),
          const Text('Para corregir semanas pasadas, elige una fecha anterior.'),
          if (info.history.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Historial', style: Theme.of(context).textTheme.titleSmall),
            for (final h in info.history)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('${money(h.rate)}/h'),
                subtitle: Text('Desde el ${dayLabel(h.from)}${parseDay(h.from).isAfter(DateTime.now()) ? ' (programada)' : ''}'),
                trailing: IconButton(
                  tooltip: 'Borrar esta tarifa',
                  onPressed: _saving ? null : () => _delete(h.id),
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('Guardar')),
      ],
    );
  }
}

// ───────── Regla de horas extra ─────────

const _presets = <String, OvertimeRule>{
  'federal': OvertimeRule(weeklyHours: 40, dailyHours: 0, doubleDailyHours: 0, overtimeMultiplier: 1.5, doubleMultiplier: 2),
  'california': OvertimeRule(weeklyHours: 40, dailyHours: 8, doubleDailyHours: 12, overtimeMultiplier: 1.5, doubleMultiplier: 2),
  'none': OvertimeRule(weeklyHours: 0, dailyHours: 0, doubleDailyHours: 0, overtimeMultiplier: 1.5, doubleMultiplier: 2),
};
const _presetLabels = [
  ('federal', 'Federal', 'Más de 40 h por semana a 1.5x (Florida, Texas, Nueva York…)'),
  ('california', 'California', '40 h por semana, más de 8 h al día a 1.5x y más de 12 h al día a 2x'),
  ('none', 'Sin horas extra', 'Todas las horas a la tarifa normal'),
  ('custom', 'Personalizada', 'Tú eliges los límites y los multiplicadores'),
];

class _RuleDialog extends ConsumerStatefulWidget {
  const _RuleDialog();

  @override
  ConsumerState<_RuleDialog> createState() => _RuleDialogState();
}

class _RuleDialogState extends ConsumerState<_RuleDialog> {
  String? _preset;
  final _weekly = TextEditingController();
  final _daily = TextEditingController();
  final _double = TextEditingController();
  final _otX = TextEditingController();
  final _dtX = TextEditingController();
  bool _loaded = false;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_weekly, _daily, _double, _otX, _dtX]) {
      c.dispose();
    }
    super.dispose();
  }

  void _fill(OvertimeRule r) {
    _weekly.text = '${r.weeklyHours}';
    _daily.text = '${r.dailyHours}';
    _double.text = '${r.doubleDailyHours}';
    _otX.text = '${r.overtimeMultiplier}';
    _dtX.text = '${r.doubleMultiplier}';
  }

  Future<void> _save() async {
    final OvertimeRule rule;
    if (_preset != 'custom') {
      rule = _presets[_preset]!;
    } else {
      int i(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;
      double d(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '.')) ?? 1.5;
      rule = OvertimeRule(
        weeklyHours: i(_weekly),
        dailyHours: i(_daily),
        doubleDailyHours: i(_double),
        overtimeMultiplier: d(_otX),
        doubleMultiplier: d(_dtX),
      );
    }
    setState(() => _saving = true);
    try {
      await ref.read(payrollApiProvider).saveRule(rule);
      ref.invalidate(payrollRuleProvider);
      ref.invalidate(payrollProvider);
      if (mounted) {
        Navigator.pop(context);
        showSuccess(context, 'Regla de horas extra guardada');
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(payrollRuleProvider).value;
    if (current != null && !_loaded) {
      _loaded = true;
      _preset = current.preset;
      _fill(current);
    }
    Widget field(TextEditingController c, String label, String helper) => Expanded(
          child: TextField(
            controller: c,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: label, helperText: helper, border: const OutlineInputBorder()),
          ),
        );
    return AlertDialog(
      scrollable: true,
      title: const Text('Horas extra'),
      content: SizedBox(
        width: 520,
        child: current == null
            ? const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
            : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('Elige la regla de tu estado. Si no estás seguro, pregunta a tu contador.'),
                const SizedBox(height: 12),
                for (final (key, label, help) in _presetLabels)
                  Card(
                    color: _preset == key ? Theme.of(context).colorScheme.primaryContainer : null,
                    child: ListTile(
                      leading: Icon(_preset == key ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded),
                      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(help),
                      onTap: () => setState(() {
                        _preset = key;
                        if (key != 'custom') _fill(_presets[key]!);
                      }),
                    ),
                  ),
                if (_preset == 'custom') ...[
                  const SizedBox(height: 12),
                  Row(children: [
                    field(_weekly, 'Extra después de (h/semana)', '0 = no aplica'),
                    const SizedBox(width: 12),
                    field(_daily, 'Extra después de (h/día)', '0 = no aplica'),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    field(_double, 'Doble después de (h/día)', '0 = no aplica'),
                    const SizedBox(width: 12),
                    field(_otX, 'Multiplicador extra', 'Ej. 1.5'),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    field(_dtX, 'Multiplicador doble', 'Ej. 2'),
                    const SizedBox(width: 12),
                    const Expanded(child: SizedBox()),
                  ]),
                ],
              ]),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _saving || current == null ? null : _save, child: const Text('Guardar')),
      ],
    );
  }
}
