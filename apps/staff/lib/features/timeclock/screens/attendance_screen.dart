import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/ui/feedback.dart';
import '../../admin/data/admin_api.dart';
import '../../admin/screens/employees_screen.dart' show EmployeeAvatar;
import '../../menu/widgets/common.dart';
import '../data/timeclock_api.dart';
import 'entry_dialog.dart';

final _clock = DateFormat('h:mm a');

/// Asistencia y horarios: quién está trabajando, el horario de la semana y las jornadas.
class AttendanceScreen extends ConsumerWidget {
  const AttendanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Horarios y asistencia'),
          bottom: const TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
            Tab(icon: Icon(Icons.how_to_reg_rounded), text: 'Ahora'),
            Tab(icon: Icon(Icons.calendar_view_week_rounded), text: 'Horario'),
            Tab(icon: Icon(Icons.fact_check_rounded), text: 'Asistencia'),
          ]),
          actions: [
            IconButton(
              tooltip: 'Ajustes del reloj',
              icon: const Icon(Icons.settings_rounded),
              onPressed: () => showDialog<void>(context: context, builder: (_) => const SettingsDialog()),
            ),
            const SizedBox(width: 8),
            AppBarAction(
              icon: Icons.punch_clock_rounded,
              label: 'Marcar por alguien',
              onPressed: () => showDialog<void>(context: context, builder: (_) => const PunchForDialog()),
            ),
            const SizedBox(width: 16),
          ],
        ),
        body: const TabBarView(children: [_NowTab(), _ScheduleTab(), _EntriesTab()]),
      ),
    );
  }
}

// ───────── Ahora ─────────

class _NowTab extends ConsumerStatefulWidget {
  const _NowTab();

  @override
  ConsumerState<_NowTab> createState() => _NowTabState();
}

class _NowTabState extends ConsumerState<_NowTab> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => ref.invalidate(nowProvider));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _punch(String employeeId, String action, String done) async {
    try {
      await ref.read(timeclockApiProvider).punchFor(employeeId, action);
      refreshAttendance(ref);
      if (mounted) showSuccess(context, done);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(nowProvider);
    final scheme = Theme.of(context).colorScheme;
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(nowProvider)),
      data: (now) => ListView(padding: const EdgeInsets.all(24), children: [
        if (now.missingOut.isNotEmpty) ...[
          SectionHeader('Sin salida marcada (${now.missingOut.length})', icon: Icons.warning_amber_rounded, color: scheme.error),
          for (final e in now.missingOut)
            Card(
              color: scheme.errorContainer,
              child: ListTile(
                leading: EmployeeAvatar(name: e.employee?.name ?? '?', photoUrl: e.employee?.photoUrl),
                title: Text(e.employee?.name ?? ''),
                subtitle: Text('Entró el ${dayLabel(e.day)} a las ${hm12(e.inTime)} y no marcó la salida'),
                trailing: FilledButton(
                  onPressed: () => showDialog<void>(context: context, builder: (_) => EntryDialog(entry: e)),
                  child: const Text('Corregir'),
                ),
              ),
            ),
          const SizedBox(height: 16),
        ],
        SectionHeader('Trabajando ahora (${now.working.length})', icon: Icons.work_history_rounded),
        if (now.working.isEmpty) const EmptyNote('Nadie tiene la entrada marcada'),
        for (final w in now.working)
          Card(
            child: ListTile(
              leading: EmployeeAvatar(name: w.employee.name, photoUrl: w.employee.photoUrl),
              title: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(w.employee.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                StatusChip(w.state == 'BREAK' ? 'En descanso' : 'Trabajando',
                    color: w.state == 'BREAK' ? Colors.orange : Colors.green),
              ]),
              subtitle: Text([
                'Entró a las ${_clock.format(w.since)}',
                if (w.breakSince != null) 'descanso desde las ${_clock.format(w.breakSince!)}',
                hoursLabel(w.workedMinutes),
              ].join(' · ')),
              trailing: PopupMenuButton<String>(
                tooltip: 'Marcar por ${w.employee.name}',
                onSelected: (a) => _punch(w.employee.id, a, switch (a) {
                  'BREAK_START' => 'Descanso iniciado',
                  'BREAK_END' => 'Descanso terminado',
                  _ => 'Salida marcada',
                }),
                itemBuilder: (_) => [
                  if (w.state == 'IN') const PopupMenuItem(value: 'BREAK_START', child: Text('Iniciar descanso')),
                  if (w.state == 'BREAK') const PopupMenuItem(value: 'BREAK_END', child: Text('Terminar descanso')),
                  const PopupMenuItem(value: 'OUT', child: Text('Marcar salida')),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        SectionHeader('Tienen turno y no han marcado (${now.notClockedIn.length})', icon: Icons.schedule_rounded),
        if (now.notClockedIn.isEmpty) const EmptyNote('Todos los que tienen turno ahora ya marcaron'),
        for (final (person, shift) in now.notClockedIn)
          Card(
            child: ListTile(
              leading: EmployeeAvatar(name: person.name, photoUrl: person.photoUrl),
              title: Text(person.name),
              subtitle: Text(
                  'Turno ${hm12(shift.start)} – ${hm12(shift.end)}${shift.position == null ? '' : ' · ${shift.position}'}'),
              trailing: OutlinedButton(
                onPressed: () => _punch(person.id, 'IN', 'Entrada marcada para ${person.name}'),
                child: const Text('Marcar entrada'),
              ),
            ),
          ),
      ]),
    );
  }
}

// ───────── Horario semanal ─────────

class _ScheduleTab extends ConsumerStatefulWidget {
  const _ScheduleTab();

  @override
  ConsumerState<_ScheduleTab> createState() => _ScheduleTabState();
}

class _ScheduleTabState extends ConsumerState<_ScheduleTab> {
  DateTime _monday = mondayOf(DateTime.now());
  bool _copying = false;

  String get _week => isoDay(_monday);

  Future<void> _copyPrevious() async {
    final previous = isoDay(_monday.subtract(const Duration(days: 7)));
    final ok = await confirm(
      context,
      title: 'Copiar la semana anterior',
      message: 'Se copian los turnos de la semana del ${dayLabel(previous)} a esta. '
          'Se salta a quien está de baja o ya tiene un turno a esa hora.',
      confirmLabel: 'Copiar',
    );
    if (!ok || !mounted) return;
    setState(() => _copying = true);
    try {
      final (copied, skipped) = await ref.read(timeclockApiProvider).copyWeek(previous, _week);
      ref.invalidate(weekProvider);
      if (mounted) {
        showSuccess(context, skipped == 0 ? 'Se copiaron $copied turnos' : 'Se copiaron $copied turnos ($skipped se saltaron)');
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _copying = false);
    }
  }

  void _openShift({ShiftView? shift, required String employeeId, required String day, required List<PersonBrief> people}) {
    showDialog<void>(
      context: context,
      builder: (_) => ShiftDialog(shift: shift, employeeId: employeeId, day: day, people: people),
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(weekProvider(_week));
    final scheme = Theme.of(context).colorScheme;
    final today = isoDay(DateTime.now());

    return ListView(padding: const EdgeInsets.all(24), children: [
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        IconButton(
          tooltip: 'Semana anterior',
          onPressed: () => setState(() => _monday = _monday.subtract(const Duration(days: 7))),
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Text(
          'Semana del ${dayLabel(_week)} al ${dayLabel(isoDay(_monday.add(const Duration(days: 6))))}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        IconButton(
          tooltip: 'Semana siguiente',
          onPressed: () => setState(() => _monday = _monday.add(const Duration(days: 7))),
          icon: const Icon(Icons.chevron_right_rounded),
        ),
        TextButton(onPressed: () => setState(() => _monday = mondayOf(DateTime.now())), child: const Text('Esta semana')),
        OutlinedButton.icon(
          onPressed: _copying ? null : _copyPrevious,
          icon: const Icon(Icons.copy_all_rounded),
          label: const Text('Copiar semana anterior'),
        ),
      ]),
      const SizedBox(height: 12),
      async.when(
        loading: () => const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator())),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(weekProvider(_week))),
        data: (w) {
          if (w.employees.isEmpty) return const EmptyNote('No hay empleados activos');
          final totalWeek = w.totals.values.fold<int>(0, (a, b) => a + b);
          Widget headerCell(String text, {bool strong = false}) => Padding(
                padding: const EdgeInsets.all(8),
                child: Text(text, style: TextStyle(fontWeight: strong ? FontWeight.w800 : FontWeight.w600)),
              );
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Toca un día para agregar un turno; toca un turno para cambiarlo. '
                'Total programado: ${hoursLabel(totalWeek)}.'),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Table(
                defaultColumnWidth: const FixedColumnWidth(132),
                columnWidths: const {0: FixedColumnWidth(200), 8: FixedColumnWidth(90)},
                border: TableBorder.all(color: scheme.outlineVariant, borderRadius: BorderRadius.circular(8)),
                defaultVerticalAlignment: TableCellVerticalAlignment.top,
                children: [
                  TableRow(
                    decoration: BoxDecoration(color: scheme.surfaceContainerHighest),
                    children: [
                      headerCell('Empleado'),
                      for (final d in w.days) headerCell(dayLabel(d), strong: d == today),
                      headerCell('Horas'),
                    ],
                  ),
                  for (final p in w.employees)
                    TableRow(children: [
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Row(children: [
                          EmployeeAvatar(name: p.name, photoUrl: p.photoUrl, radius: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(p.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                              Text(p.jobTitle ?? p.roleName,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                            ]),
                          ),
                        ]),
                      ),
                      for (final d in w.days)
                        InkWell(
                          onTap: () => _openShift(employeeId: p.id, day: d, people: w.employees),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 56),
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                for (final s in w.shifts.where((s) => s.employeeId == p.id && s.day == d))
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Material(
                                      color: scheme.primaryContainer,
                                      borderRadius: BorderRadius.circular(8),
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(8),
                                        onTap: () => _openShift(shift: s, employeeId: p.id, day: d, people: w.employees),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                            Text('${hmShort(s.start)} – ${hmShort(s.end)}',
                                                style: TextStyle(fontWeight: FontWeight.w700, color: scheme.onPrimaryContainer)),
                                            if (s.position != null)
                                              Text(s.position!,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(fontSize: 12, color: scheme.onPrimaryContainer)),
                                          ]),
                                        ),
                                      ),
                                    ),
                                  ),
                              ]),
                            ),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(hoursLabel(w.totals[p.id] ?? 0), style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ]),
                ],
              ),
            ),
          ]);
        },
      ),
    ]);
  }
}

// ───────── Asistencia ─────────

class _EntriesTab extends ConsumerStatefulWidget {
  const _EntriesTab();

  @override
  ConsumerState<_EntriesTab> createState() => _EntriesTabState();
}

class _EntriesTabState extends ConsumerState<_EntriesTab> {
  DateTime _from = mondayOf(DateTime.now());
  DateTime _to = DateTime.now();
  String? _employeeId;

  EntriesQuery get _query => (from: isoDay(_from), to: isoDay(_to), employeeId: _employeeId);

  void _range(String which) {
    final now = DateTime.now();
    final monday = mondayOf(now);
    setState(() {
      switch (which) {
        case 'this':
          _from = monday;
          _to = now;
        case 'last':
          _from = monday.subtract(const Duration(days: 7));
          _to = monday.subtract(const Duration(days: 1));
        case 'two':
          _from = monday.subtract(const Duration(days: 7));
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

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(entriesProvider(_query));
    final people = ref.watch(employeesProvider).value ?? const [];
    final scheme = Theme.of(context).colorScheme;

    return ListView(padding: const EdgeInsets.all(24), children: [
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        ActionChip(label: const Text('Esta semana'), onPressed: () => _range('this')),
        ActionChip(label: const Text('Semana pasada'), onPressed: () => _range('last')),
        ActionChip(label: const Text('Últimas 2 semanas'), onPressed: () => _range('two')),
        ActionChip(
          avatar: const Icon(Icons.date_range_rounded, size: 18),
          label: Text('${dayLabel(isoDay(_from))} – ${dayLabel(isoDay(_to))}'),
          onPressed: _custom,
        ),
        PopupMenuButton<String>(
          tooltip: 'Empleado',
          onSelected: (v) => setState(() => _employeeId = v.isEmpty ? null : v),
          itemBuilder: (_) => [
            const PopupMenuItem(value: '', child: Text('Todos')),
            for (final p in people) PopupMenuItem(value: p.id, child: Text(p.name)),
          ],
          child: Chip(
            avatar: const Icon(Icons.person_search_rounded, size: 18),
            label: Text(people.where((p) => p.id == _employeeId).firstOrNull?.name ?? 'Todos'),
          ),
        ),
        FilledButton.icon(
          onPressed: () => showDialog<void>(context: context, builder: (_) => EntryDialog(employeeId: _employeeId)),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Agregar jornada'),
        ),
      ]),
      const SizedBox(height: 16),
      async.when(
        loading: () => const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator())),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(entriesProvider(_query))),
        data: (r) {
          if (r.entries.isEmpty) return const EmptyNote('No hay jornadas en estas fechas');
          final days = <String, List<EntryView>>{};
          for (final e in r.entries.reversed) {
            days.putIfAbsent(e.day, () => []).add(e);
          }
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(spacing: 12, runSpacing: 12, children: [
              for (final t in r.totals)
                SizedBox(
                  width: 240,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(children: [
                        EmployeeAvatar(name: t.employee.name, photoUrl: t.employee.photoUrl, radius: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(t.employee.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                            Text(hoursLabel(t.workedMinutes),
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                            Text(
                              [
                                '${t.entries} ${t.entries == 1 ? 'jornada' : 'jornadas'}',
                                if (t.lateCount > 0) '${t.lateCount} tarde',
                              ].join(' · '),
                              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                            ),
                          ]),
                        ),
                      ]),
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 16),
            for (final MapEntry(key: day, value: list) in days.entries) ...[
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: Text(dayLabel(day), style: Theme.of(context).textTheme.titleSmall),
              ),
              for (final e in list) _EntryTile(entry: e),
            ],
          ]);
        },
      ),
    ]);
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry});
  final EntryView entry;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        leading: EmployeeAvatar(name: e.employee?.name ?? '?', photoUrl: e.employee?.photoUrl),
        title: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(e.employee?.name ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
          Text('${hm12(e.inTime)} – ${e.outTime == null ? '…' : hm12(e.outTime!)}'),
          if (e.missingOut)
            StatusChip('Sin salida', color: scheme.error)
          else if (e.open)
            const StatusChip('Trabajando', color: Colors.green),
          if (e.lateMinutes > 0) StatusChip('${e.lateMinutes} min tarde', color: Colors.orange),
          if (e.edited)
            Tooltip(
              message: [
                if (e.editedBy != null) 'Por ${e.editedBy}',
                if (e.editReason != null) e.editReason!,
              ].join(' · '),
              child: StatusChip(e.source == 'MANUAL' ? 'Manual' : 'Corregida'),
            ),
        ]),
        subtitle: Text([
          if (e.shift != null) 'Turno ${hm12(e.shift!.start)} – ${hm12(e.shift!.end)}',
          if (e.breaks.isNotEmpty)
            '${e.breaks.length} ${e.breaks.length == 1 ? 'descanso' : 'descansos'} (${hoursLabel(e.breakMinutes)}'
                '${e.unpaidBreakMinutes > 0 ? ', ${hoursLabel(e.unpaidBreakMinutes)} sin pagar' : ', pagados'})',
        ].join(' · ')),
        trailing: Text(hoursLabel(e.workedMinutes), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        onTap: () => showDialog<void>(context: context, builder: (_) => EntryDialog(entry: e)),
      ),
    );
  }
}
