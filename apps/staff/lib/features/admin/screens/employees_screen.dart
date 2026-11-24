import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/ui/feedback.dart';
import '../../menu/widgets/common.dart';
import '../data/admin_api.dart';
import '../data/admin_models.dart';

class EmployeesScreen extends ConsumerWidget {
  const EmployeesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final employees = ref.watch(employeesProvider);
    final me = ref.watch(authControllerProvider).value?.employee;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Empleados'),
        actions: [
          AppBarAction(
            icon: Icons.person_add_alt_1_rounded,
            label: 'Nuevo empleado',
            onPressed: () => _openEditor(context),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: employees.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorView(error: error, onRetry: () => ref.invalidate(employeesProvider)),
        data: (list) => ListView.separated(
          padding: const EdgeInsets.all(24),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final e = list[index];
            final isMe = e.id == me?.id;
            return Card(
              child: ListTile(
                leading: CircleAvatar(child: Text(e.name.isEmpty ? '?' : e.name[0].toUpperCase())),
                title: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text(e.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  StatusChip(e.roleName, color: Theme.of(context).colorScheme.primary),
                  if (isMe) const StatusChip('Tú'),
                  if (!e.isActive) StatusChip('Inactivo', color: Theme.of(context).colorScheme.error),
                ]),
                subtitle: Text([
                  if (e.email != null) e.email!,
                  e.hasPassword ? 'Con contraseña' : 'Sin contraseña',
                  e.hasPin ? 'Con PIN' : 'Sin PIN',
                ].join(' · ')),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _openEditor(context, employee: e, isMe: isMe),
              ),
            );
          },
        ),
      ),
    );
  }

  void _openEditor(BuildContext context, {EmployeeView? employee, bool isMe = false}) {
    showDialog<void>(context: context, builder: (_) => _EmployeeDialog(employee: employee, isMe: isMe));
  }
}

class _EmployeeDialog extends ConsumerStatefulWidget {
  const _EmployeeDialog({this.employee, required this.isMe});
  final EmployeeView? employee;
  final bool isMe;

  @override
  ConsumerState<_EmployeeDialog> createState() => _EmployeeDialogState();
}

class _EmployeeDialogState extends ConsumerState<_EmployeeDialog> {
  final _formKey = GlobalKey<FormState>();
  EmployeeView? get _e => widget.employee;

  late final _name = TextEditingController(text: _e?.name);
  late final _email = TextEditingController(text: _e?.email);
  late final _phone = TextEditingController(text: _e?.phone);
  final _password = TextEditingController();
  late String? _roleId = _e?.roleId;
  late bool _isActive = _e?.isActive ?? true;

  /// Para empleados nuevos: generar PIN. Para existentes: 'keep', 'new' o 'remove'.
  late bool _generatePin = _e == null;
  String _pinAction = 'keep';
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final email = _email.text.trim();
    final phone = _phone.text.trim();
    final isNew = _e == null;
    final data = <String, dynamic>{
      'name': _name.text.trim(),
      'roleId': _roleId,
      if (email.isNotEmpty) 'email': email else if (!isNew) 'email': null,
      if (phone.isNotEmpty) 'phone': phone else if (!isNew) 'phone': null,
      if (_password.text.isNotEmpty) 'password': _password.text,
      if (isNew && _generatePin) 'generatePin': true,
      if (!isNew && _pinAction == 'new') 'regeneratePin': true,
      if (!isNew && _pinAction == 'remove') 'removePin': true,
      if (!isNew && !widget.isMe) 'isActive': _isActive,
    };
    if (widget.isMe) data.remove('roleId');
    try {
      final api = ref.read(adminApiProvider);
      final saved = isNew ? await api.createEmployee(data) : await api.updateEmployee(_e!.id, data);
      ref.invalidate(employeesProvider);
      if (!mounted) return;
      final navigator = Navigator.of(context);
      final pin = saved['generatedPin'] as String?;
      navigator.pop();
      if (pin != null) {
        await showGeneratedPin(navigator.context, name: saved['name'] as String, pin: pin);
      } else if (navigator.context.mounted) {
        showSuccess(navigator.context, isNew ? 'Empleado creado' : 'Cambios guardados');
      }
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
    final needsPassword = selectedRole?.permissions.any(
          (p) => const ['settings.manage', 'employees.manage', 'menu.manage', 'delivery.own'].contains(p),
        ) ??
        false;

    return AlertDialog(
      title: Text(_e == null ? 'Nuevo empleado' : 'Editar empleado'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _name,
                  autofocus: _e == null,
                  decoration: const InputDecoration(labelText: 'Nombre', border: OutlineInputBorder()),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Escribe el nombre' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _roleId,
                  decoration: InputDecoration(
                    labelText: 'Rol',
                    border: const OutlineInputBorder(),
                    helperText: widget.isMe ? 'No puedes cambiar tu propio rol' : null,
                  ),
                  items: [for (final r in roles) DropdownMenuItem(value: r.id, child: Text(r.name))],
                  onChanged: widget.isMe ? null : (v) => setState(() => _roleId = v),
                  validator: (v) => v == null ? 'Elige un rol' : null,
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
                      validator: (v) {
                        final value = (v ?? '').trim();
                        if (value.isEmpty) return needsPassword && _e == null ? 'Necesario para este rol' : null;
                        return value.contains('@') ? null : 'Email inválido';
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(labelText: 'Teléfono', border: OutlineInputBorder()),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _password,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: _e == null ? 'Contraseña' : 'Nueva contraseña',
                    helperText: _e == null
                        ? 'Para entrar al panel o a la app de repartidor (mín. 8)'
                        : (_e!.hasPassword ? 'Déjala vacía para no cambiarla' : 'Sin contraseña todavía'),
                    border: const OutlineInputBorder(),
                  ),
                  validator: (v) {
                    final value = v ?? '';
                    if (value.isEmpty) {
                      return needsPassword && _e == null ? 'Este rol necesita contraseña' : null;
                    }
                    return value.length < 8 ? 'Mínimo 8 caracteres' : null;
                  },
                ),
                const SizedBox(height: 12),
                if (_e == null)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Generar PIN para caja y cocina'),
                    subtitle: const Text('El sistema crea un PIN único de 6 dígitos y te lo muestra una sola vez'),
                    value: _generatePin,
                    onChanged: (v) => setState(() => _generatePin = v ?? false),
                  )
                else ...[
                  Text('PIN para caja y cocina', style: Theme.of(context).textTheme.titleSmall),
                  RadioGroup<String>(
                    groupValue: _pinAction,
                    onChanged: (v) => setState(() => _pinAction = v ?? 'keep'),
                    child: Column(children: [
                      RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        value: 'keep',
                        title: Text(_e!.hasPin ? 'Mantener el PIN actual' : 'Sin PIN'),
                      ),
                      RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        value: 'new',
                        title: Text(_e!.hasPin ? 'Generar un PIN nuevo (el actual deja de funcionar)' : 'Generar PIN'),
                      ),
                      if (_e!.hasPin)
                        const RadioListTile<String>(
                          contentPadding: EdgeInsets.zero,
                          value: 'remove',
                          title: Text('Quitar el PIN'),
                        ),
                    ]),
                  ),
                ],
                if (_e != null && !widget.isMe)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Activo'),
                    subtitle: const Text('Si lo desactivas, se cierran sus sesiones y no podrá entrar'),
                    value: _isActive,
                    onChanged: (v) => setState(() => _isActive = v),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('Guardar')),
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
