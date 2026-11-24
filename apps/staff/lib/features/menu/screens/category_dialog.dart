import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/feedback.dart';
import '../data/menu_models.dart';
import '../menu_controller.dart';

/// Crear o editar una categoría. Devuelve true si se guardó.
Future<bool> showCategoryDialog(BuildContext context, {Category? category}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => _CategoryDialog(category: category),
  );
  return saved ?? false;
}

class _CategoryDialog extends ConsumerStatefulWidget {
  const _CategoryDialog({this.category});
  final Category? category;

  @override
  ConsumerState<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends ConsumerState<_CategoryDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.category?.name);
  late final _nameEn = TextEditingController(text: translated(widget.category?.translations, 'en', 'name'));
  late bool _isActive = widget.category?.isActive ?? true;
  late bool _dineIn = widget.category?.visibleDineIn ?? true;
  late bool _online = widget.category?.visibleOnline ?? true;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _nameEn.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final en = _nameEn.text.trim();
    final data = <String, dynamic>{
      'name': _name.text.trim(),
      'isActive': _isActive,
      'visibleDineIn': _dineIn,
      'visibleOnline': _online,
      if (en.isNotEmpty) 'translations': {'en': {'name': en}}
      else if (widget.category != null) 'translations': null,
    };
    try {
      final controller = ref.read(adminMenuProvider.notifier);
      final existing = widget.category;
      await controller.mutate((api) =>
          existing == null ? api.createCategory(data) : api.updateCategory(existing.id, data));
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: Text(widget.category == null ? 'Nueva categoría' : 'Editar categoría'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Nombre', border: OutlineInputBorder()),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Escribe un nombre' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameEn,
                decoration: const InputDecoration(labelText: 'Nombre en inglés (opcional)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Activa'),
                value: _isActive,
                onChanged: (v) => setState(() => _isActive = v),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Visible en las mesas y el POS'),
                value: _dineIn,
                onChanged: (v) => setState(() => _dineIn = v ?? true),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Visible en la web de pedidos'),
                value: _online,
                onChanged: (v) => setState(() => _online = v ?? true),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('Guardar')),
      ],
    );
  }
}
