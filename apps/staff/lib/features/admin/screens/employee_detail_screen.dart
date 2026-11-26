import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/ui/feedback.dart';
import '../../menu/widgets/common.dart';
import '../data/admin_api.dart';
import '../data/admin_models.dart';
import '../data/staff_labels.dart';
import 'employees_screen.dart';

final _dateTime = DateFormat('M/d/yyyy h:mm a');
final _date = DateFormat('M/d/yyyy');

String _prettyDay(String? iso) {
  if (iso == null) return '';
  final d = DateTime.tryParse(iso);
  return d == null ? iso : _date.format(d);
}

/// Ficha de un empleado: datos, acceso (contraseña, PIN, sesiones) e historial.
class EmployeeDetailScreen extends ConsumerWidget {
  const EmployeeDetailScreen({super.key, required this.employeeId});
  final String employeeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(employeeDetailProvider(employeeId));
    final canHistory = ref.watch(authControllerProvider).value?.employee.can('audit.view') ?? false;

    return async.when(
      loading: () => Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(
        appBar: AppBar(),
        body: ErrorView(error: error, onRetry: () => ref.invalidate(employeeDetailProvider(employeeId))),
      ),
      data: (e) => DefaultTabController(
        length: canHistory ? 3 : 2,
        child: Scaffold(
          appBar: AppBar(
            title: Text(e.name),
            bottom: TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
              const Tab(icon: Icon(Icons.badge_rounded), text: 'Ficha'),
              const Tab(icon: Icon(Icons.key_rounded), text: 'Acceso'),
              if (canHistory) const Tab(icon: Icon(Icons.history_rounded), text: 'Historial'),
            ]),
          ),
          body: TabBarView(children: [
            _ProfileTab(employee: e),
            _AccessTab(employee: e),
            if (canHistory) _HistoryTab(employeeId: e.id),
          ]),
        ),
      ),
    );
  }
}

/// Contenido centrado con ancho cómodo de lectura.
class _Page extends StatelessWidget {
  const _Page({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
            ),
          ),
        ],
      );
}

// ───────── Ficha ─────────

class _ProfileTab extends ConsumerStatefulWidget {
  const _ProfileTab({required this.employee});
  final EmployeeView employee;

  @override
  ConsumerState<_ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends ConsumerState<_ProfileTab> {
  final _formKey = GlobalKey<FormState>();
  EmployeeView get _e => widget.employee;

  late final _name = TextEditingController(text: _e.name);
  late final _jobTitle = TextEditingController(text: _e.jobTitle);
  late final _email = TextEditingController(text: _e.email);
  late final _phone = TextEditingController(text: _e.phone);
  late final _address = TextEditingController(text: _e.address);
  late final _emergencyName = TextEditingController(text: _e.emergencyName);
  late final _emergencyPhone = TextEditingController(text: _e.emergencyPhone);
  late final _notes = TextEditingController(text: _e.notes);
  late String _roleId = _e.roleId;
  late String? _hireDate = _e.hireDate;
  bool _saving = false;
  bool _photoBusy = false;

  @override
  void dispose() {
    for (final c in [_name, _jobTitle, _email, _phone, _address, _emergencyName, _emergencyPhone, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  void _refresh() {
    ref.invalidate(employeeDetailProvider(_e.id));
    ref.invalidate(employeesProvider);
    ref.invalidate(rolesProvider);
  }

  Future<void> _save({required bool isMe}) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    String? text(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    final data = <String, dynamic>{
      'name': _name.text.trim(),
      'jobTitle': text(_jobTitle),
      'email': text(_email),
      'phone': text(_phone),
      'hireDate': _hireDate,
      'address': text(_address),
      'emergencyName': text(_emergencyName),
      'emergencyPhone': text(_emergencyPhone),
      'notes': text(_notes),
      if (!isMe && _roleId != _e.roleId) 'roleId': _roleId,
    };
    try {
      await ref.read(adminApiProvider).updateEmployee(_e.id, data);
      _refresh();
      if (mounted) showSuccess(context, 'Ficha guardada');
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickPhoto() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1200);
    if (file == null) return;
    setState(() => _photoBusy = true);
    try {
      await ref.read(adminApiProvider).uploadEmployeePhoto(_e.id, await file.readAsBytes(), file.name);
      _refresh();
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  Future<void> _removePhoto() async {
    setState(() => _photoBusy = true);
    try {
      await ref.read(adminApiProvider).removeEmployeePhoto(_e.id);
      _refresh();
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  Future<void> _pickHireDate() async {
    final initial = DateTime.tryParse(_hireDate ?? '') ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1970),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _hireDate = DateFormat('yyyy-MM-dd').format(picked));
  }

  Future<void> _terminate() async {
    final reason = await showDialog<String>(context: context, builder: (_) => _TerminateDialog(name: _e.name));
    if (reason == null || !mounted) return;
    setState(() => _saving = true);
    try {
      await ref.read(adminApiProvider).updateEmployee(_e.id, {
        'isActive': false,
        if (reason.isNotEmpty) 'terminationReason': reason,
      });
      _refresh();
      if (mounted) showSuccess(context, '${_e.name} quedó dado de baja');
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reactivate() async {
    setState(() => _saving = true);
    try {
      await ref.read(adminApiProvider).updateEmployee(_e.id, {'isActive': true});
      _refresh();
      if (mounted) showSuccess(context, '${_e.name} está activo otra vez');
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authControllerProvider).value?.employee;
    final isMe = me?.id == _e.id;
    final roles = ref.watch(rolesProvider).value ?? const <Role>[];
    final needsPassword = roleNeedsPassword(roles.firstWhereOrNull((r) => r.id == _roleId));
    final scheme = Theme.of(context).colorScheme;
    const gap = SizedBox(height: 12);
    InputDecoration field(String label, {String? hint, String? helper}) =>
        InputDecoration(labelText: label, hintText: hint, helperText: helper, border: const OutlineInputBorder());

    return Form(
      key: _formKey,
      child: _Page(children: [
        Row(children: [
          EmployeeAvatar(name: _e.name, photoUrl: _e.photoUrl, radius: 40),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_e.name, style: Theme.of(context).textTheme.titleLarge),
              Text([_e.jobTitle, _e.roleName].whereType<String>().join(' · ')),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                OutlinedButton.icon(
                  onPressed: _photoBusy ? null : _pickPhoto,
                  icon: const Icon(Icons.photo_camera_rounded),
                  label: Text(_e.photoUrl == null ? 'Poner foto' : 'Cambiar foto'),
                ),
                if (_e.photoUrl != null)
                  TextButton(onPressed: _photoBusy ? null : _removePhoto, child: const Text('Quitar foto')),
              ]),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        Card(
          color: _e.isActive ? null : scheme.errorContainer,
          child: ListTile(
            leading: Icon(_e.isActive ? Icons.check_circle_rounded : Icons.person_off_rounded,
                color: _e.isActive ? Colors.green : scheme.error),
            title: Text(_e.isActive ? 'Activo' : 'De baja'),
            subtitle: Text(_e.isActive
                ? 'Puede entrar con su contraseña o PIN'
                : [
                    if (_e.terminatedAt != null) 'Desde el ${_date.format(_e.terminatedAt!)}',
                    if (_e.terminationReason != null) _e.terminationReason!,
                    'No puede entrar. Su historial se conserva.',
                  ].join(' · ')),
            trailing: isMe
                ? null
                : _e.isActive
                    ? OutlinedButton(
                        onPressed: _saving ? null : _terminate,
                        style: OutlinedButton.styleFrom(foregroundColor: scheme.error),
                        child: const Text('Dar de baja'),
                      )
                    : FilledButton(onPressed: _saving ? null : _reactivate, child: const Text('Reactivar')),
          ),
        ),
        const SizedBox(height: 16),
        Text('Datos', style: Theme.of(context).textTheme.titleMedium),
        gap,
        TextFormField(
          controller: _name,
          decoration: field('Nombre'),
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Escribe el nombre' : null,
        ),
        gap,
        Row(children: [
          Expanded(child: TextFormField(controller: _jobTitle, decoration: field('Puesto', hint: 'Ej. Chef de línea'))),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<String>(
              key: ValueKey('rol-${roles.length}'),
              isExpanded: true,
              initialValue: roles.any((r) => r.id == _roleId) ? _roleId : null,
              decoration: field('Rol', helper: isMe ? 'No puedes cambiar tu propio rol' : null),
              items: [for (final r in roles) DropdownMenuItem(value: r.id, child: Text(r.name))],
              onChanged: isMe ? null : (v) => setState(() => _roleId = v ?? _roleId),
            ),
          ),
        ]),
        gap,
        Row(children: [
          Expanded(
            child: TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: field('Email'),
              validator: (v) {
                final value = (v ?? '').trim();
                if (value.isEmpty) return needsPassword && _e.hasPassword ? 'Necesario para entrar al panel' : null;
                return value.contains('@') ? null : 'Email inválido';
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: field('Teléfono'),
            ),
          ),
        ]),
        gap,
        InkWell(
          onTap: _pickHireDate,
          child: InputDecorator(
            decoration: field('Fecha de ingreso').copyWith(
              suffixIcon: _hireDate == null
                  ? const Icon(Icons.calendar_month_rounded)
                  : IconButton(
                      tooltip: 'Quitar fecha',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => setState(() => _hireDate = null),
                    ),
            ),
            child: Text(_hireDate == null ? 'Sin fecha' : _prettyDay(_hireDate)),
          ),
        ),
        gap,
        TextFormField(controller: _address, decoration: field('Dirección')),
        const SizedBox(height: 16),
        Text('Contacto de emergencia', style: Theme.of(context).textTheme.titleMedium),
        gap,
        Row(children: [
          Expanded(child: TextFormField(controller: _emergencyName, decoration: field('Nombre'))),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              controller: _emergencyPhone,
              keyboardType: TextInputType.phone,
              decoration: field('Teléfono'),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        TextFormField(
          controller: _notes,
          minLines: 3,
          maxLines: 6,
          decoration: field('Notas internas', helper: 'Solo las ve quien administra empleados'),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _saving ? null : () => _save(isMe: isMe),
            icon: const Icon(Icons.save_rounded),
            label: const Text('Guardar ficha'),
          ),
        ),
      ]),
    );
  }
}

class _TerminateDialog extends StatefulWidget {
  const _TerminateDialog({required this.name});
  final String name;

  @override
  State<_TerminateDialog> createState() => _TerminateDialogState();
}

class _TerminateDialogState extends State<_TerminateDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      scrollable: true,
      title: Text('Dar de baja a ${widget.name}'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Se cierran sus sesiones y ya no podrá entrar. Sus ventas, propinas e historial se conservan. '
              'Puedes reactivarlo cuando quieras.'),
          const SizedBox(height: 12),
          TextField(
            controller: _reason,
            autofocus: true,
            maxLength: 300,
            decoration: const InputDecoration(labelText: 'Motivo (opcional)', border: OutlineInputBorder()),
          ),
          Wrap(spacing: 8, children: [
            for (final r in const ['Renuncia', 'Fin de temporada', 'Despido'])
              ActionChip(label: Text(r), onPressed: () => setState(() => _reason.text = r)),
          ]),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError),
          onPressed: () => Navigator.pop(context, _reason.text.trim()),
          child: const Text('Dar de baja'),
        ),
      ],
    );
  }
}

// ───────── Acceso ─────────

class _AccessTab extends ConsumerStatefulWidget {
  const _AccessTab({required this.employee});
  final EmployeeView employee;

  @override
  ConsumerState<_AccessTab> createState() => _AccessTabState();
}

class _AccessTabState extends ConsumerState<_AccessTab> {
  bool _busy = false;
  EmployeeView get _e => widget.employee;

  void _refresh() {
    ref.invalidate(employeeDetailProvider(_e.id));
    ref.invalidate(employeesProvider);
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      _refresh();
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _password({required bool isMe}) async {
    final password = await showDialog<String>(context: context, builder: (_) => _PasswordDialog(isMe: isMe));
    if (password == null || !mounted) return;
    await _run(() async {
      await ref.read(adminApiProvider).updateEmployee(_e.id, {'password': password});
      if (mounted) showSuccess(context, 'Contraseña cambiada. Sus sesiones abiertas se cerraron.');
    });
  }

  Future<void> _newPin() async {
    if (_e.hasPin) {
      final ok = await confirm(
        context,
        title: 'Generar un PIN nuevo',
        message: 'El PIN actual de ${_e.name} deja de funcionar al instante.',
        confirmLabel: 'Generar',
      );
      if (!ok || !mounted) return;
    }
    await _run(() async {
      final saved = await ref.read(adminApiProvider).updateEmployee(_e.id, {'regeneratePin': true});
      final pin = saved['generatedPin'] as String?;
      if (pin != null && mounted) await showGeneratedPin(context, name: _e.name, pin: pin);
    });
  }

  Future<void> _removePin() async {
    final ok = await confirm(
      context,
      title: 'Quitar el PIN',
      message: '${_e.name} ya no podrá entrar en caja ni en cocina con PIN.',
      confirmLabel: 'Quitar',
    );
    if (!ok || !mounted) return;
    await _run(() => ref.read(adminApiProvider).updateEmployee(_e.id, {'removePin': true}));
  }

  Future<void> _logoutAll() async {
    final ok = await confirm(
      context,
      title: 'Cerrar todas sus sesiones',
      message: 'Se cierra su sesión en el panel y en la app del repartidor, y se desconectan sus pantallas. '
          'Podrá volver a entrar con su contraseña o PIN.',
      confirmLabel: 'Cerrar sesiones',
    );
    if (!ok || !mounted) return;
    await _run(() async {
      final closed = await ref.read(adminApiProvider).logoutAll(_e.id);
      if (mounted) {
        showSuccess(context, closed == 1 ? 'Se cerró 1 sesión' : 'Se cerraron $closed sesiones');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isMe = ref.watch(authControllerProvider).value?.employee.id == _e.id;
    final sessions = _e.activeSessions ?? 0;

    return _Page(children: [
      if (!_e.isActive)
        const Card(
          child: ListTile(
            leading: Icon(Icons.info_outline_rounded),
            title: Text('Está de baja: no puede entrar aunque tenga contraseña o PIN.'),
          ),
        ),
      Card(
        child: ListTile(
          leading: const Icon(Icons.password_rounded),
          title: const Text('Contraseña'),
          subtitle: Text(_e.hasPassword
              ? 'Tiene contraseña para el panel${_e.email == null ? '' : ' (${_e.email})'}'
              : (_e.email == null
                  ? 'Sin contraseña. Para ponerle una, primero agrega su email en la Ficha.'
                  : 'Sin contraseña: no entra al panel')),
          trailing: OutlinedButton(
            onPressed: _busy || _e.email == null ? null : () => _password(isMe: isMe),
            child: Text(_e.hasPassword ? 'Cambiar' : 'Poner contraseña'),
          ),
        ),
      ),
      Card(
        child: ListTile(
          leading: const Icon(Icons.pin_rounded),
          title: const Text('PIN para caja y cocina'),
          subtitle: Text(_e.hasPin
              ? 'Tiene PIN. Por seguridad no se puede ver: si lo olvidó, genera uno nuevo.'
              : 'Sin PIN'),
          trailing: Wrap(spacing: 8, children: [
            if (_e.hasPin)
              TextButton(onPressed: _busy ? null : _removePin, child: const Text('Quitar')),
            OutlinedButton(
              onPressed: _busy ? null : _newPin,
              child: Text(_e.hasPin ? 'Generar nuevo' : 'Generar PIN'),
            ),
          ]),
        ),
      ),
      Card(
        child: ListTile(
          leading: const Icon(Icons.devices_rounded),
          title: Text(sessions == 0
              ? 'Sin sesiones abiertas'
              : sessions == 1
                  ? '1 sesión abierta'
                  : '$sessions sesiones abiertas'),
          subtitle: Text(_e.lastLoginAt == null
              ? 'Todavía no ha entrado'
              : 'Último ingreso: ${_dateTime.format(_e.lastLoginAt!)}'),
          trailing: isMe
              ? null
              : OutlinedButton(
                  onPressed: _busy ? null : _logoutAll,
                  child: const Text('Cerrar todas'),
                ),
        ),
      ),
    ]);
  }
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.isMe});
  final bool isMe;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _repeat = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    _repeat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        scrollable: true,
        title: const Text('Nueva contraseña'),
        content: SizedBox(
          width: 400,
          child: Form(
            key: _formKey,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(widget.isMe
                  ? 'Es tu propia contraseña: al guardarla tendrás que volver a entrar.'
                  : 'Entrégasela en persona. Al guardarla se cierran sus sesiones abiertas.'),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                obscureText: true,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Contraseña (mín. 8)', border: OutlineInputBorder()),
                validator: (v) => (v ?? '').length < 8 ? 'Mínimo 8 caracteres' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _repeat,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Repítela', border: OutlineInputBorder()),
                validator: (v) => v != _password.text ? 'No coinciden' : null,
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              if (_formKey.currentState!.validate()) Navigator.pop(context, _password.text);
            },
            child: const Text('Guardar'),
          ),
        ],
      );
}

// ───────── Historial ─────────

const _scopes = [('all', 'Todo'), ('about', 'Cambios y accesos'), ('actions', 'Lo que hizo')];

class _HistoryTab extends ConsumerStatefulWidget {
  const _HistoryTab({required this.employeeId});
  final String employeeId;

  @override
  ConsumerState<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends ConsumerState<_HistoryTab> {
  String _scope = 'all';
  final List<EmployeeEvent> _items = [];
  String? _cursor;
  bool _loading = false;
  bool _done = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _items.clear();
        _cursor = null;
        _done = false;
      }
    });
    try {
      final (items, next) =
          await ref.read(adminApiProvider).history(widget.employeeId, scope: _scope, cursor: _cursor);
      if (!mounted) return;
      setState(() {
        _items.addAll(items);
        _cursor = next;
        _done = next == null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _detail(EmployeeEvent e) {
    final data = e.data ?? const {};
    switch (e.action) {
      case 'employee.update':
        final fields = ((data['fields'] as List?) ?? const [])
            .map((f) => employeeFieldLabels[f] ?? '')
            .where((f) => f.isNotEmpty)
            .toSet()
            .toList();
        if (data['passwordChanged'] == true) fields.add('contraseña');
        if (data['pinGenerated'] == true && !fields.contains('PIN nuevo')) fields.add('PIN nuevo');
        return fields.isEmpty ? '' : 'Cambió: ${fields.join(', ')}';
      case 'employee.terminate':
        return data['reason'] is String ? 'Motivo: ${data['reason']}' : '';
      case 'employee.create':
        return data['role'] is String ? 'Rol: ${data['role']}' : '';
      case 'employee.logout_all':
        return '${data['sessions'] ?? 0} sesiones';
      case 'role.update':
        final added = ((data['added'] as List?) ?? const []).map((p) => permissionLabels[p] ?? p).join(', ');
        final removed = ((data['removed'] as List?) ?? const []).map((p) => permissionLabels[p] ?? p).join(', ');
        return [
          if (data['name'] != null) '${data['name']}',
          if (added.isNotEmpty) 'Agregó: $added',
          if (removed.isNotEmpty) 'Quitó: $removed',
        ].join(' · ');
      case 'role.create' || 'role.delete':
        return data['name'] is String ? '${data['name']}' : '';
      default:
        return '';
    }
  }

  IconData _icon(EmployeeEvent e) {
    final a = e.action;
    if (a.startsWith('auth.')) return a.endsWith('failed') ? Icons.gpp_maybe_rounded : Icons.login_rounded;
    if (a.startsWith('employee.')) return Icons.badge_rounded;
    if (a.startsWith('payment.') || a.startsWith('cash.')) return Icons.payments_rounded;
    if (a.startsWith('bill.')) return Icons.receipt_long_rounded;
    if (a.startsWith('order.') || a.startsWith('ticket.')) return Icons.restaurant_menu_rounded;
    if (a.startsWith('table.')) return Icons.table_restaurant_rounded;
    if (a.startsWith('delivery.')) return Icons.delivery_dining_rounded;
    if (a.startsWith('role.')) return Icons.admin_panel_settings_rounded;
    return Icons.history_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _Page(children: [
      Wrap(spacing: 8, children: [
        for (final (value, label) in _scopes)
          ChoiceChip(
            label: Text(label),
            selected: _scope == value,
            onSelected: (_) {
              setState(() => _scope = value);
              _load(reset: true);
            },
          ),
      ]),
      const SizedBox(height: 12),
      if (_error != null) ErrorView(error: _error!, onRetry: () => _load(reset: _items.isEmpty)),
      if (_items.isEmpty && !_loading && _error == null)
        const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('Sin movimientos todavía'))),
      for (final e in _items)
        Card(
          child: ListTile(
            leading: Icon(_icon(e), color: e.action.endsWith('failed') ? scheme.error : scheme.primary),
            title: Text(actionLabels[e.action] ?? e.action),
            subtitle: Text([
              _dateTime.format(e.at),
              if (!e.byThisEmployee && e.actorName != null) 'por ${e.actorName}',
              _detail(e),
            ].where((s) => s.isNotEmpty).join(' · ')),
          ),
        ),
      if (_loading) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
      if (!_loading && !_done && _items.isNotEmpty)
        Center(child: TextButton(onPressed: _load, child: const Text('Ver más'))),
    ]);
  }
}
