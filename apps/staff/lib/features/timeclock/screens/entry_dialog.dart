import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/feedback.dart';
import '../../admin/data/admin_api.dart';
import '../data/timeclock_api.dart';

String _two(int n) => n.toString().padLeft(2, '0');
String _hm(TimeOfDay t) => '${_two(t.hour)}:${_two(t.minute)}';
TimeOfDay _tod(String hm) {
  final p = hm.split(':');
  return TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
}

/// Vuelve a pedir todo lo de asistencia (después de marcar o corregir).
void refreshAttendance(WidgetRef ref) {
  ref.invalidate(nowProvider);
  ref.invalidate(weekProvider);
  ref.invalidate(entriesProvider);
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key, required this.icon, this.color});
  final String text;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          Flexible(child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: color))),
        ]),
      );
}

class EmptyNote extends StatelessWidget {
  const EmptyNote(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Text(text, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
}

/// Botón grande con una hora ("Entra 9:00 AM").
class _TimeButton extends StatelessWidget {
  const _TimeButton({required this.label, required this.value, required this.onTap});
  final String label;
  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => OutlinedButton(
        onPressed: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(children: [
            Text(label),
            Text(value == null ? 'Sin marcar' : hm12(value!), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ]),
        ),
      );
}

// ───────── Turno del horario ─────────

const _positions = ['Caja', 'Cocina', 'Sala', 'Barra', 'Delivery', 'Limpieza'];

class ShiftDialog extends ConsumerStatefulWidget {
  const ShiftDialog({super.key, this.shift, required this.employeeId, required this.day, required this.people});
  final ShiftView? shift;
  final String employeeId;
  final String day;
  final List<PersonBrief> people;

  @override
  ConsumerState<ShiftDialog> createState() => _ShiftDialogState();
}

class _ShiftDialogState extends ConsumerState<ShiftDialog> {
  late String _start = widget.shift?.start ?? '09:00';
  late String _end = widget.shift?.end ?? '17:00';
  late final _position = TextEditingController(text: widget.shift?.position);
  late final _note = TextEditingController(text: widget.shift?.note);
  bool _saving = false;

  @override
  void dispose() {
    _position.dispose();
    _note.dispose();
    super.dispose();
  }

  int get _minutes {
    final s = _tod(_start), e = _tod(_end);
    var m = (e.hour * 60 + e.minute) - (s.hour * 60 + s.minute);
    if (m <= 0) m += 24 * 60;
    return m;
  }

  Future<void> _pick(bool start) async {
    final picked = await showTimePicker(context: context, initialTime: _tod(start ? _start : _end));
    if (picked == null) return;
    setState(() {
      if (start) {
        _start = _hm(picked);
      } else {
        _end = _hm(picked);
      }
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _saving = true);
    try {
      await action();
      ref.invalidate(weekProvider);
      ref.invalidate(nowProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final person = widget.people.where((p) => p.id == widget.employeeId).firstOrNull;
    final overnight = _end.compareTo(_start) <= 0;
    final api = ref.read(timeclockApiProvider);
    return AlertDialog(
      scrollable: true,
      title: Text(widget.shift == null ? 'Nuevo turno' : 'Turno'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${person?.name ?? ''} · ${dayLabel(widget.day)}', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: _TimeButton(label: 'Entra', value: _start, onTap: () => _pick(true))),
            const SizedBox(width: 12),
            Expanded(child: _TimeButton(label: 'Sale', value: _end, onTap: () => _pick(false))),
          ]),
          const SizedBox(height: 8),
          Text('${hoursLabel(_minutes)}${overnight ? ' · termina al día siguiente' : ''}', textAlign: TextAlign.center),
          const SizedBox(height: 16),
          TextField(
            controller: _position,
            decoration: const InputDecoration(labelText: 'Puesto en este turno (opcional)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 6),
          Wrap(spacing: 6, children: [
            for (final p in _positions) ActionChip(label: Text(p), onPressed: () => setState(() => _position.text = p)),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            decoration: const InputDecoration(labelText: 'Nota (opcional)', border: OutlineInputBorder()),
          ),
        ]),
      ),
      actions: [
        if (widget.shift != null)
          TextButton(
            onPressed: _saving ? null : () => _run(() => api.deleteShift(widget.shift!.id)),
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Quitar turno'),
          ),
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: _saving
              ? null
              : () => _run(() => api.saveShift(widget.shift?.id, {
                    'employeeId': widget.employeeId,
                    'day': widget.day,
                    'start': _start,
                    'end': _end,
                    if (_position.text.trim().isNotEmpty) 'position': _position.text.trim(),
                    if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
                  })),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

// ───────── Jornada ─────────

/// Agregar o corregir una jornada. Siempre con motivo (queda en el historial del empleado).
class EntryDialog extends ConsumerStatefulWidget {
  const EntryDialog({super.key, this.entry, this.employeeId});
  final EntryView? entry;
  final String? employeeId;

  @override
  ConsumerState<EntryDialog> createState() => _EntryDialogState();
}

class _EntryDialogState extends ConsumerState<EntryDialog> {
  EntryView? get _e => widget.entry;
  late String? _employeeId = _e?.employeeId ?? widget.employeeId;
  late DateTime _day = _e == null ? DateTime.now() : parseDay(_e!.day);
  late String _in = _e?.inTime ?? '09:00';
  late String? _out = _e == null ? '17:00' : _e!.outTime;
  late final List<(String, String?)> _breaks = [for (final b in _e?.breaks ?? const <BreakView>[]) (b.startTime, b.endTime)];
  final _reason = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<String?> _pickTime(String? current) async {
    final picked = await showTimePicker(context: context, initialTime: _tod(current ?? _in));
    return picked == null ? null : _hm(picked);
  }

  bool _hasReason(String message) {
    if (_reason.text.trim().length >= 3) return true;
    showError(context, message);
    return false;
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _saving = true);
    try {
      await action();
      refreshAttendance(ref);
      if (mounted) {
        Navigator.pop(context);
        showSuccess(context, done);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    if (_employeeId == null) {
      showError(context, 'Elige el empleado');
      return;
    }
    if (!_hasReason('Escribe el motivo de la corrección')) return;
    final data = {
      'employeeId': _employeeId,
      'day': isoDay(_day),
      'clockIn': _in,
      if (_out != null) 'clockOut': _out,
      'breaks': [
        for (final (s, e) in _breaks) {'start': s, if (e != null) 'end': e},
      ],
      'reason': _reason.text.trim(),
    };
    await _run(() => ref.read(timeclockApiProvider).saveEntry(_e?.id, data), _e == null ? 'Jornada agregada' : 'Jornada corregida');
  }

  Future<void> _delete() async {
    if (!_hasReason('Escribe el motivo para borrarla')) return;
    final ok = await confirm(
      context,
      title: 'Borrar la jornada',
      message: 'Sus horas dejan de contar. Queda registrado en el historial.',
    );
    if (!ok || !mounted) return;
    await _run(() => ref.read(timeclockApiProvider).deleteEntry(_e!.id, _reason.text.trim()), 'Jornada borrada');
  }

  @override
  Widget build(BuildContext context) {
    final people = (ref.watch(employeesProvider).value ?? const []).where((p) => p.isActive || p.id == _employeeId).toList();
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      scrollable: true,
      title: Text(_e == null ? 'Agregar jornada' : 'Corregir jornada'),
      content: SizedBox(
        width: 460,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DropdownButtonFormField<String>(
            key: ValueKey('emp-${people.length}'),
            isExpanded: true,
            initialValue: people.any((p) => p.id == _employeeId) ? _employeeId : null,
            decoration: const InputDecoration(labelText: 'Empleado', border: OutlineInputBorder()),
            items: [for (final p in people) DropdownMenuItem(value: p.id, child: Text(p.name))],
            onChanged: _e != null ? null : (v) => setState(() => _employeeId = v),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _day,
                firstDate: DateTime(2024),
                lastDate: DateTime.now(),
              );
              if (picked != null) setState(() => _day = picked);
            },
            icon: const Icon(Icons.calendar_month_rounded),
            label: Text('Día de entrada: ${dayLabel(isoDay(_day))}'),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: _TimeButton(
                label: 'Entrada',
                value: _in,
                onTap: () async {
                  final t = await _pickTime(_in);
                  if (t != null) setState(() => _in = t);
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _TimeButton(
                label: 'Salida',
                value: _out,
                onTap: () async {
                  final t = await _pickTime(_out);
                  if (t != null) setState(() => _out = t);
                },
              ),
            ),
          ]),
          if (_out != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: () => setState(() => _out = null), child: const Text('Sigue trabajando (sin salida)')),
            ),
          if (_out != null && _out!.compareTo(_in) <= 0)
            const Text('La salida es al día siguiente (turno de noche).', textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Text('Descansos', style: Theme.of(context).textTheme.titleSmall),
          for (final (i, (s, e)) in _breaks.indexed)
            Row(children: [
              Expanded(
                child: TextButton(
                  onPressed: () async {
                    final t = await _pickTime(s);
                    if (t != null) setState(() => _breaks[i] = (t, e));
                  },
                  child: Text('Desde ${hm12(s)}'),
                ),
              ),
              Expanded(
                child: TextButton(
                  onPressed: () async {
                    final t = await _pickTime(e ?? s);
                    if (t != null) setState(() => _breaks[i] = (s, t));
                  },
                  child: Text(e == null ? 'Sin terminar' : 'Hasta ${hm12(e)}'),
                ),
              ),
              IconButton(
                tooltip: 'Quitar descanso',
                onPressed: () => setState(() => _breaks.removeAt(i)),
                icon: const Icon(Icons.close_rounded),
              ),
            ]),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _breaks.length >= 10 ? null : () => setState(() => _breaks.add(('12:00', '12:30'))),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Agregar descanso'),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _reason,
            maxLength: 200,
            decoration: const InputDecoration(
              labelText: 'Motivo',
              hintText: 'Ej. Olvidó marcar la salida',
              border: OutlineInputBorder(),
            ),
          ),
          Wrap(spacing: 6, children: [
            for (final r in const ['Olvidó marcar la salida', 'Olvidó marcar la entrada', 'Se equivocó al marcar'])
              ActionChip(label: Text(r), onPressed: () => setState(() => _reason.text = r)),
          ]),
          if (_e?.edited ?? false) ...[
            const SizedBox(height: 8),
            Text(
              'Última corrección${_e!.editedBy == null ? '' : ' por ${_e!.editedBy}'}: ${_e!.editReason ?? ''}',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ]),
      ),
      actions: [
        if (_e != null)
          TextButton(
            onPressed: _saving ? null : _delete,
            style: TextButton.styleFrom(foregroundColor: scheme.error),
            child: const Text('Borrar'),
          ),
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('Guardar')),
      ],
    );
  }
}

// ───────── Marcar por alguien ─────────

const _punchActions = [
  ('IN', 'Entrada'),
  ('BREAK_START', 'Iniciar descanso'),
  ('BREAK_END', 'Terminar descanso'),
  ('OUT', 'Salida'),
];

class PunchForDialog extends ConsumerStatefulWidget {
  const PunchForDialog({super.key});

  @override
  ConsumerState<PunchForDialog> createState() => _PunchForDialogState();
}

class _PunchForDialogState extends ConsumerState<PunchForDialog> {
  String? _employeeId;
  String _action = 'IN';
  final _reason = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_employeeId == null) {
      showError(context, 'Elige el empleado');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(timeclockApiProvider).punchFor(_employeeId!, _action, reason: _reason.text.trim());
      refreshAttendance(ref);
      if (mounted) {
        Navigator.pop(context);
        showSuccess(context, 'Listo, quedó marcado');
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final people = (ref.watch(employeesProvider).value ?? const []).where((p) => p.isActive).toList();
    return AlertDialog(
      scrollable: true,
      title: const Text('Marcar por alguien'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Se marca con la hora de ahora y queda registrado que lo hiciste tú. '
              'Para otra hora usa "Agregar jornada" en Asistencia.'),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey('p-${people.length}'),
            isExpanded: true,
            initialValue: _employeeId,
            decoration: const InputDecoration(labelText: 'Empleado', border: OutlineInputBorder()),
            items: [for (final p in people) DropdownMenuItem(value: p.id, child: Text(p.name))],
            onChanged: (v) => setState(() => _employeeId = v),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final (code, label) in _punchActions)
              ChoiceChip(label: Text(label), selected: _action == code, onSelected: (_) => setState(() => _action = code)),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _reason,
            maxLength: 200,
            decoration: const InputDecoration(labelText: 'Motivo (opcional)', border: OutlineInputBorder()),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('Marcar')),
      ],
    );
  }
}

// ───────── Ajustes del reloj ─────────

const _breakOptions = [
  (0, 'No se pagan'),
  (10, 'Hasta 10 min'),
  (15, 'Hasta 15 min'),
  (20, 'Hasta 20 min'),
  (30, 'Hasta 30 min'),
  (1440, 'Siempre'),
];
const _graceOptions = [0, 5, 10, 15];

class SettingsDialog extends ConsumerStatefulWidget {
  const SettingsDialog({super.key});

  @override
  ConsumerState<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends ConsumerState<SettingsDialog> {
  int? _paid;
  int? _grace;
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(timeclockApiProvider).updateSettings({
        if (_paid != null) 'paidBreakMinutes': _paid,
        if (_grace != null) 'clockGraceMinutes': _grace,
      });
      ref.invalidate(timeclockSettingsProvider);
      refreshAttendance(ref);
      if (mounted) {
        Navigator.pop(context);
        showSuccess(context, 'Ajustes guardados');
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(timeclockSettingsProvider).value;
    final paid = _paid ?? (current?['paidBreakMinutes'] as num?)?.toInt() ?? 0;
    final grace = _grace ?? (current?['clockGraceMinutes'] as num?)?.toInt() ?? 5;
    return AlertDialog(
      scrollable: true,
      title: const Text('Ajustes del reloj checador'),
      content: SizedBox(
        width: 480,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Descansos pagados', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          const Text('Un descanso que dura hasta lo que elijas cuenta como trabajado; uno más largo se descuenta completo.'),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final (value, label) in _breakOptions)
              ChoiceChip(label: Text(label), selected: paid == value, onSelected: (_) => setState(() => _paid = value)),
          ]),
          const SizedBox(height: 20),
          Text('Tolerancia para llegar tarde', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          const Text('Minutos después de la hora del turno antes de marcarlo como tarde.'),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final g in _graceOptions)
              ChoiceChip(label: Text('$g min'), selected: grace == g, onSelected: (_) => setState(() => _grace = g)),
          ]),
        ]),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _saving || current == null ? null : _save, child: const Text('Guardar')),
      ],
    );
  }
}
