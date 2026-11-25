import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/feedback.dart';
import '../data/customers_api.dart';

/// Identificar al cliente de una cuenta o una mesa por su teléfono (o darlo de alta).
/// [attach] liga el cliente elegido (o lo quita con null). Devuelve true si cambió algo.
Future<bool> showCustomerPicker(
  BuildContext context, {
  String? currentName,
  required Future<void> Function(WidgetRef ref, String? customerId) attach,
}) async {
  final changed = await showDialog<bool>(
    context: context,
    builder: (_) => _CustomerPicker(currentName: currentName, attach: attach),
  );
  return changed ?? false;
}

class _CustomerPicker extends ConsumerStatefulWidget {
  const _CustomerPicker({this.currentName, required this.attach});
  final String? currentName;
  final Future<void> Function(WidgetRef ref, String? customerId) attach;

  @override
  ConsumerState<_CustomerPicker> createState() => _CustomerPickerState();
}

class _CustomerPickerState extends ConsumerState<_CustomerPicker> {
  final _phone = TextEditingController();
  final _name = TextEditingController();
  bool _busy = false;
  bool _searched = false;
  CustomerSummary? _found;

  @override
  void dispose() {
    _phone.dispose();
    _name.dispose();
    super.dispose();
  }

  bool get _phoneOk => _phone.text.replaceAll(RegExp(r'\D'), '').length >= 10;

  Future<void> _search() async {
    if (!_phoneOk) return;
    setState(() => _busy = true);
    try {
      final c = await ref.read(customersApiProvider).lookup(_phone.text);
      if (!mounted) return;
      setState(() {
        _found = c;
        _searched = true;
      });
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _use(String? id) async {
    setState(() => _busy = true);
    try {
      await widget.attach(ref, id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createAndUse() async {
    if (_name.text.trim().length < 2) return;
    setState(() => _busy = true);
    try {
      final c = await ref.read(customersApiProvider).create(name: _name.text.trim(), phone: _phone.text);
      await widget.attach(ref, c.id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final f = _found;
    return AlertDialog(
      scrollable: true,
      title: const Text('Cliente'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (widget.currentName != null) ...[
            Row(children: [
              const Icon(Icons.person_rounded),
              const SizedBox(width: 8),
              Expanded(child: Text(widget.currentName!, style: text.titleMedium)),
              TextButton(onPressed: _busy ? null : () => _use(null), child: const Text('Quitar')),
            ]),
            const Divider(height: 24),
          ],
          Text('Busca al cliente por su teléfono. Así su visita queda en su historial.', style: text.bodyMedium),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _phone,
                autofocus: true,
                keyboardType: TextInputType.phone,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+()\-.\s]'))],
                decoration: const InputDecoration(labelText: 'Teléfono', hintText: '(305) 555-0123'),
                onChanged: (_) => setState(() {
                  _searched = false;
                  _found = null;
                }),
                onSubmitted: (_) => _search(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(onPressed: _busy || !_phoneOk ? null : _search, child: const Text('Buscar')),
          ]),
          if (_searched && f != null) ...[
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: CircleAvatar(child: Text(f.name.isEmpty ? '?' : f.name[0].toUpperCase())),
                title: Text(f.name.isEmpty ? 'Sin nombre' : f.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text([
                  prettyPhone(f.phone),
                  '${f.visits} ${f.visits == 1 ? 'visita' : 'visitas'}',
                  if (f.spent > 0) formatMoney(f.spent),
                ].join(' · ')),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(onPressed: _busy ? null : () => _use(f.id), child: const Text('Usar este cliente')),
          ],
          if (_searched && f == null) ...[
            const SizedBox(height: 16),
            Text('No hay cliente con ese teléfono. Dalo de alta:', style: text.bodyMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nombre'),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _createAndUse(),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy || _name.text.trim().length < 2 ? null : _createAndUse,
              child: const Text('Crear y usar'),
            ),
          ],
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cerrar'))],
    );
  }
}
