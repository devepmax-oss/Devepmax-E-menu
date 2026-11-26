import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/ui/feedback.dart';
import '../../menu/widgets/common.dart';
import '../data/admin_api.dart';
import '../data/admin_models.dart';
import '../data/staff_labels.dart';
import 'employee_detail_screen.dart';

/// Empleados: el personal (fichas, bajas, acceso, historial) y los roles con sus permisos.
class EmployeesScreen extends ConsumerWidget {
  const EmployeesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(authControllerProvider).value?.employee;
    final canRoles = me?.can('roles.manage') ?? false;

    return DefaultTabController(
      length: canRoles ? 2 : 1,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Empleados'),
          bottom: canRoles
              ? const TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
                  Tab(icon: Icon(Icons.groups_rounded), text: 'Personal'),
                  Tab(icon: Icon(Icons.admin_panel_settings_rounded), text: 'Roles y permisos'),
                ])
              : null,
          actions: [
            AppBarAction(
              icon: Icons.person_add_alt_1_rounded,
              label: 'Nuevo empleado',
              onPressed: () => _newEmployee(context),
            ),
            const SizedBox(width: 16),
          ],
        ),
        body: canRoles
            ? const TabBarView(children: [_StaffTab(), _RolesTab()])
            : const _StaffTab(),
      ),
    );
  }

  Future<void> _newEmployee(BuildContext context) async {
    final id = await showDialog<String>(context: context, builder: (_) => const _NewEmployeeDialog());
    if (id != null && context.mounted) openEmployee(context, id);
  }
}

void openEmployee(BuildContext context, String id) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => EmployeeDetailScreen(employeeId: id)));
}

/// Foto o inicial del empleado.
class EmployeeAvatar extends StatelessWidget {
  const EmployeeAvatar({super.key, required this.name, this.photoUrl, this.radius = 20});
  final String name;
  final String? photoUrl;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return CircleAvatar(
      radius: radius,
      foregroundImage: photoUrl == null ? null : NetworkImage(photoUrl!),
      onForegroundImageError: photoUrl == null ? null : (_, __) {},
      child: Text(initial, style: TextStyle(fontSize: radius * 0.8)),
    );
  }
}

const _staffFilters = [('active', 'Activos'), ('inactive', 'De baja'), ('all', 'Todos')];

class _StaffTab extends ConsumerStatefulWidget {
  const _StaffTab();

  @override
  ConsumerState<_StaffTab> createState() => _StaffTabState();
}

class _StaffTabState extends ConsumerState<_StaffTab> {
  final _search = TextEditingController();
  String _q = '';
  String _filter = 'active';
  String? _roleId;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final employees = ref.watch(employeesProvider);
    final roles = ref.watch(rolesProvider).value ?? const <Role>[];
    final me = ref.watch(authControllerProvider).value?.employee;
    final scheme = Theme.of(context).colorScheme;

    return employees.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => ErrorView(error: error, onRetry: () => ref.invalidate(employeesProvider)),
      data: (all) {
        final q = _q.toLowerCase();
        final list = all.where((e) {
          if (_filter == 'active' && !e.isActive) return false;
          if (_filter == 'inactive' && e.isActive) return false;
          if (_roleId != null && e.roleId != _roleId) return false;
          if (q.isEmpty) return true;
          return [e.name, e.email, e.phone, e.jobTitle, e.roleName]
              .whereType<String>()
              .any((v) => v.toLowerCase().contains(q));
        }).toList();
        final inactive = all.where((e) => !e.isActive).length;

        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              SizedBox(
                width: 320,
                child: TextField(
                  controller: _search,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded),
                    hintText: 'Buscar por nombre, puesto, email o teléfono',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _q = v.trim()),
                ),
              ),
              for (final (value, label) in _staffFilters)
                ChoiceChip(
                  label: Text(value == 'inactive' && inactive > 0 ? '$label ($inactive)' : label),
                  selected: _filter == value,
                  onSelected: (_) => setState(() => _filter = value),
                ),
              PopupMenuButton<String>(
                tooltip: 'Filtrar por rol',
                onSelected: (v) => setState(() => _roleId = v.isEmpty ? null : v),
                itemBuilder: (_) => [
                  const PopupMenuItem<String>(value: '', child: Text('Todos los roles')),
                  for (final r in roles) PopupMenuItem<String>(value: r.id, child: Text(r.name)),
                ],
                child: Chip(
                  avatar: const Icon(Icons.filter_list_rounded, size: 18),
                  label: Text(roles.firstWhereOrNull((r) => r.id == _roleId)?.name ?? 'Todos los roles'),
                ),
              ),
            ]),
            const SizedBox(height: 16),
            if (list.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: Text('No hay empleados con estos filtros')),
              ),
            for (final e in list)
              Card(
                child: ListTile(
                  leading: EmployeeAvatar(name: e.name, photoUrl: e.photoUrl),
                  title: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text(e.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    StatusChip(e.roleName, color: scheme.primary),
                    if (e.id == me?.id) const StatusChip('Tú'),
                    if (!e.isActive) StatusChip('De baja', color: scheme.error),
                  ]),
                  subtitle: Text([
                    if (e.jobTitle != null) e.jobTitle!,
                    if (e.phone != null) e.phone!,
                    if (e.email != null) e.email!,
                    if (!e.hasPassword && !e.hasPin) 'Sin acceso',
                  ].join(' · ')),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => openEmployee(context, e.id),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Alta rápida: lo básico para que pueda entrar. El resto de la ficha se llena después.
class _NewEmployeeDialog extends ConsumerStatefulWidget {
  const _NewEmployeeDialog();

  @override
  ConsumerState<_NewEmployeeDialog> createState() => _NewEmployeeDialogState();
}

class _NewEmployeeDialogState extends ConsumerState<_NewEmployeeDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _jobTitle = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  String? _roleId;
  bool _generatePin = true;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _jobTitle, _email, _phone, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    String text(TextEditingController c) => c.text.trim();
    final data = <String, dynamic>{
      'name': text(_name),
      'roleId': _roleId,
      if (text(_jobTitle).isNotEmpty) 'jobTitle': text(_jobTitle),
      if (text(_email).isNotEmpty) 'email': text(_email),
      if (text(_phone).isNotEmpty) 'phone': text(_phone),
      if (_password.text.isNotEmpty) 'password': _password.text,
      if (_generatePin) 'generatePin': true,
    };
    try {
      final saved = await ref.read(adminApiProvider).createEmployee(data);
      ref.invalidate(employeesProvider);
      ref.invalidate(rolesProvider);
      if (!mounted) return;
      final navigator = Navigator.of(context);
      final pin = saved['generatedPin'] as String?;
      if (pin != null) await showGeneratedPin(context, name: saved['name'] as String, pin: pin);
      navigator.pop(saved['id'] as String);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final roles = ref.watch(rolesProvider).value ?? const <Role>[];
    final selectedRole = roles.firstWhereOrNull((r) => r.id == _roleId);
    final needsPassword = roleNeedsPassword(selectedRole);

    return AlertDialog(
      scrollable: true,
      title: const Text('Nuevo empleado'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Nombre', border: OutlineInputBorder()),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Escribe el nombre' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _roleId,
                decoration: const InputDecoration(labelText: 'Rol', border: OutlineInputBorder()),
                items: [for (final r in roles) DropdownMenuItem(value: r.id, child: Text(r.name))],
                onChanged: (v) => setState(() => _roleId = v),
                validator: (v) => v == null ? 'Elige un rol' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _jobTitle,
                decoration: const InputDecoration(
                  labelText: 'Puesto (opcional)',
                  hintText: 'Ej. Chef de línea, Hostess',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
                validator: (v) {
                  final value = (v ?? '').trim();
                  if (value.isEmpty) return needsPassword ? 'Necesario para este rol' : null;
                  return value.contains('@') ? null : 'Email inválido';
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Teléfono', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Contraseña',
                  helperText: 'Para entrar al panel o a la app de repartidor (mín. 8)',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final value = v ?? '';
                  if (value.isEmpty) return needsPassword ? 'Este rol necesita contraseña' : null;
                  return value.length < 8 ? 'Mínimo 8 caracteres' : null;
                },
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Generar PIN para caja y cocina'),
                subtitle: const Text('El sistema crea un PIN único de 6 dígitos y te lo muestra una sola vez'),
                value: _generatePin,
                onChanged: (v) => setState(() => _generatePin = v ?? false),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('Crear')),
      ],
    );
  }
}

/// Roles que entran al panel o a la app del repartidor necesitan email y contraseña.
bool roleNeedsPassword(Role? role) =>
    role?.permissions.any(
      (p) => const ['settings.manage', 'employees.manage', 'menu.manage', 'delivery.own'].contains(p),
    ) ??
    false;

// ───────── Roles ─────────

class _RolesTab extends ConsumerWidget {
  const _RolesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roles = ref.watch(rolesProvider);
    final scheme = Theme.of(context).colorScheme;
    return roles.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => ErrorView(error: error, onRetry: () => ref.invalidate(rolesProvider)),
      data: (list) => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Row(children: [
            const Expanded(
              child: Text(
                'Cada empleado tiene un rol. Lo que el rol permite aplica al instante, sin volver a entrar.',
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: () => _open(context, null),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Nuevo rol'),
            ),
          ]),
          const SizedBox(height: 16),
          for (final r in list)
            Card(
              child: ListTile(
                leading: Icon(r.isAdmin ? Icons.shield_rounded : Icons.badge_outlined, color: scheme.primary),
                title: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text(r.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (r.isSystem) const StatusChip('De fábrica'),
                ]),
                subtitle: Text([
                  if (r.description != null && r.description!.isNotEmpty) r.description!,
                  '${r.employeeCount} ${r.employeeCount == 1 ? 'empleado' : 'empleados'}',
                  r.isAdmin ? 'Todos los permisos' : '${r.permissions.length} permisos',
                ].join(' · ')),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _open(context, r),
              ),
            ),
        ],
      ),
    );
  }

  void _open(BuildContext context, Role? role) {
    showDialog<void>(context: context, builder: (_) => _RoleDialog(role: role));
  }
}

class _RoleDialog extends ConsumerStatefulWidget {
  const _RoleDialog({this.role});
  final Role? role;

  @override
  ConsumerState<_RoleDialog> createState() => _RoleDialogState();
}

class _RoleDialogState extends ConsumerState<_RoleDialog> {
  final _formKey = GlobalKey<FormState>();
  Role? get _r => widget.role;
  late final _name = TextEditingController(text: _r?.name);
  late final _description = TextEditingController(text: _r?.description);
  late final Set<String> _perms = {...?_r?.permissions};
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final description = _description.text.trim();
      await ref.read(adminApiProvider).saveRole(_r?.id, {
        'name': _name.text.trim(),
        'description': description.isEmpty ? null : description,
        'permissions': _perms.toList(),
      });
      ref.invalidate(rolesProvider);
      if (!mounted) return;
      Navigator.pop(context);
      showSuccess(context, _r == null ? 'Rol creado' : 'Rol guardado');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await confirm(
      context,
      title: 'Borrar el rol ${_r!.name}',
      message: 'Solo se puede borrar si ningún empleado lo tiene.',
      confirmLabel: 'Borrar',
    );
    if (!ok || !mounted) return;
    setState(() => _saving = true);
    try {
      await ref.read(adminApiProvider).deleteRole(_r!.id);
      ref.invalidate(rolesProvider);
      if (!mounted) return;
      Navigator.pop(context);
      showSuccess(context, 'Rol borrado');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authControllerProvider).value?.employee;
    final isOwn = _r != null && me?.roleName == _r!.name;
    final locked = (_r?.isAdmin ?? false) || isOwn;
    final lockReason = (_r?.isAdmin ?? false)
        ? 'El rol Admin siempre tiene todos los permisos.'
        : isOwn
            ? 'Este es tu propio rol: otra persona con permiso de roles debe editarlo.'
            : null;
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      scrollable: true,
      title: Text(_r == null ? 'Nuevo rol' : (locked ? _r!.name : 'Editar rol')),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (lockReason != null) ...[
                Card(
                  color: scheme.secondaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      const Icon(Icons.lock_rounded),
                      const SizedBox(width: 8),
                      Expanded(child: Text(lockReason)),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _name,
                enabled: !locked && !(_r?.isSystem ?? false),
                autofocus: _r == null,
                decoration: InputDecoration(
                  labelText: 'Nombre del rol',
                  helperText: (_r?.isSystem ?? false) ? 'Los roles de fábrica no se renombran' : null,
                  border: const OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Escribe el nombre' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _description,
                enabled: !locked,
                decoration: const InputDecoration(
                  labelText: 'Descripción (opcional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              for (final (group, perms) in permissionGroups) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 4),
                  child: Text(group, style: Theme.of(context).textTheme.titleSmall),
                ),
                for (final (code, label, help) in perms)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: (_r?.isAdmin ?? false) || _perms.contains(code),
                    title: Text(label),
                    subtitle: Text(
                      (me?.can(code) ?? false) ? help : '$help · Tú no lo tienes, no lo puedes dar',
                    ),
                    onChanged: locked || !(me?.can(code) ?? false)
                        ? null
                        : (v) => setState(() => v == true ? _perms.add(code) : _perms.remove(code)),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (_r != null && !_r!.isSystem && !locked)
          TextButton(
            onPressed: _saving ? null : _delete,
            style: TextButton.styleFrom(foregroundColor: scheme.error),
            child: const Text('Borrar'),
          ),
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: Text(locked ? 'Cerrar' : 'Cancelar'),
        ),
        if (!locked) FilledButton(onPressed: _saving ? null : _save, child: const Text('Guardar')),
      ],
    );
  }
}

/// Muestra el PIN recién generado. Es la única vez que se puede ver.
Future<void> showGeneratedPin(BuildContext context, {required String name, required String pin}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      scrollable: true,
      title: Text('PIN de $name'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        SelectableText(
          '${pin.substring(0, 3)} ${pin.substring(3)}',
          style: Theme.of(context).textTheme.displayMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 6),
        ),
        const SizedBox(height: 16),
        const Text(
          'Entrégaselo en persona. Por seguridad no se vuelve a mostrar: '
          'si lo olvida, genera uno nuevo desde aquí.',
          textAlign: TextAlign.center,
        ),
      ]),
      actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Ya lo anoté'))],
    ),
  );
}
