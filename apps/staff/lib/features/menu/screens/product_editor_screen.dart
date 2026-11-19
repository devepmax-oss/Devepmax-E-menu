import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/ui/feedback.dart';
import '../data/menu_models.dart';
import '../menu_controller.dart';
import '../widgets/common.dart';

Future<void> openProductEditor(BuildContext context, {required String categoryId, Product? product}) {
  return Navigator.of(context).push(MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => ProductEditorScreen(categoryId: categoryId, product: product),
  ));
}

class ProductEditorScreen extends ConsumerStatefulWidget {
  const ProductEditorScreen({super.key, required this.categoryId, this.product});
  final String categoryId;
  final Product? product;

  @override
  ConsumerState<ProductEditorScreen> createState() => _ProductEditorScreenState();
}

class _ProductEditorScreenState extends ConsumerState<ProductEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  Product? get _p => widget.product;

  late final _name = TextEditingController(text: _p?.name);
  late final _nameEn = TextEditingController(text: translated(_p?.translations, 'en', 'name'));
  late final _description = TextEditingController(text: _p?.description);
  late final _descriptionEn = TextEditingController(text: translated(_p?.translations, 'en', 'description'));
  late final _price = TextEditingController(text: _p == null ? '' : _p!.price.toStringAsFixed(2));
  late final _prepTime = TextEditingController(text: _p?.prepTimeMinutes?.toString());

  late String _categoryId = _p?.categoryId ?? widget.categoryId;
  late String? _stationId = _p?.stationId;
  late String? _taxRateId = _p?.taxRateId;
  late final Set<String> _allergens = {...?_p?.allergens};
  late final List<String> _groupIds = [...?_p?.modifierGroupIds];
  late bool _isActive = _p?.isActive ?? true;
  late bool _isAvailable = _p?.isAvailable ?? true;
  late bool _dineIn = _p?.visibleDineIn ?? true;
  late bool _online = _p?.visibleOnline ?? true;

  Uint8List? _newImage;
  String? _newImageName;
  bool _removeImage = false;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _nameEn, _description, _descriptionEn, _price, _prepTime]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickImage() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2400);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _newImage = bytes;
      _newImageName = file.name;
      _removeImage = false;
    });
  }

  Map<String, dynamic> _payload() {
    final isNew = _p == null;
    final en = <String, String>{
      if (_nameEn.text.trim().isNotEmpty) 'name': _nameEn.text.trim(),
      if (_descriptionEn.text.trim().isNotEmpty) 'description': _descriptionEn.text.trim(),
    };
    final description = _description.text.trim();
    final prep = int.tryParse(_prepTime.text.trim());
    final data = <String, dynamic>{
      'categoryId': _categoryId,
      'name': _name.text.trim(),
      'price': double.parse(_price.text.trim().replaceAll(',', '.')),
      'description': description.isEmpty ? null : description,
      'translations': en.isEmpty ? null : {'en': en},
      'stationId': _stationId,
      'taxRateId': _taxRateId,
      'prepTimeMinutes': prep,
      'allergens': _allergens.toList(),
      'modifierGroupIds': _groupIds,
      'isActive': _isActive,
      'isAvailable': _isAvailable,
      'visibleDineIn': _dineIn,
      'visibleOnline': _online,
    };
    // Al crear, el backend no acepta null: se omiten los campos vacíos.
    if (isNew) data.removeWhere((_, value) => value == null);
    return data;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final controller = ref.read(adminMenuProvider.notifier);
    try {
      final api = controller.api;
      final data = _payload();
      final id = _p?.id ?? await api.createProduct(data);
      if (_p != null) await api.updateProduct(id, data);
      if (_newImage != null) {
        await api.uploadProductImage(id, _newImage!, _newImageName ?? 'foto.jpg');
      } else if (_removeImage && _p?.imageUrl != null) {
        await api.removeProductImage(id);
      }
      await controller.reload();
      if (mounted) {
        showSuccess(context, 'Producto guardado');
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) showError(context, error);
      // Si el producto se creó pero falló la foto, se recarga para no perderlo de vista.
      await controller.reload().catchError((_) {});
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await confirm(
      context,
      title: 'Eliminar "${_p!.name}"',
      message: 'Las órdenes anteriores conservan el nombre y precio. Si solo quieres ocultarlo, desactívalo.',
    );
    if (!ok) return;
    try {
      await ref.read(adminMenuProvider.notifier).mutate((api) => api.deleteProduct(_p!.id));
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final menu = ref.watch(adminMenuProvider).value;
    if (menu == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_p == null ? 'Nuevo producto' : 'Editar producto'),
        actions: [
          if (_p != null)
            TextButton.icon(
              onPressed: _saving ? null : _delete,
              icon: Icon(Icons.delete_outline_rounded, color: theme.colorScheme.error),
              label: Text('Eliminar', style: TextStyle(color: theme.colorScheme.error)),
            ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Guardar'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _imageSection(theme),
                    const SizedBox(height: 24),
                    _section('Información', [
                      _row([
                        _text(_name, 'Nombre', required: true),
                        _text(_nameEn, 'Nombre en inglés (opcional)'),
                      ]),
                      _row([
                        _text(_description, 'Descripción', lines: 3),
                        _text(_descriptionEn, 'Descripción en inglés', lines: 3),
                      ]),
                      _row([
                        TextFormField(
                          controller: _price,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                          decoration: const InputDecoration(
                            labelText: 'Precio',
                            prefixText: '\$ ',
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) {
                            final value = double.tryParse((v ?? '').trim().replaceAll(',', '.'));
                            return value == null || value < 0 ? 'Escribe un precio válido' : null;
                          },
                        ),
                        TextFormField(
                          controller: _prepTime,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: const InputDecoration(
                            labelText: 'Tiempo de preparación (min)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ]),
                    ]),
                    _section('Organización', [
                      _row([
                        DropdownButtonFormField<String>(
                          initialValue: _categoryId,
                          decoration: const InputDecoration(labelText: 'Categoría', border: OutlineInputBorder()),
                          items: [
                            for (final c in menu.categories) DropdownMenuItem(value: c.id, child: Text(c.name)),
                          ],
                          onChanged: (v) => setState(() => _categoryId = v ?? _categoryId),
                        ),
                        DropdownButtonFormField<String?>(
                          initialValue: _stationId,
                          decoration: const InputDecoration(
                            labelText: 'Estación de cocina',
                            helperText: 'Pantalla donde se prepara',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            const DropdownMenuItem<String?>(value: null, child: Text('Sin estación')),
                            for (final s in menu.stations) DropdownMenuItem<String?>(value: s.id, child: Text(s.name)),
                          ],
                          onChanged: (v) => setState(() => _stationId = v),
                        ),
                        DropdownButtonFormField<String?>(
                          initialValue: _taxRateId,
                          decoration: const InputDecoration(labelText: 'Impuesto', border: OutlineInputBorder()),
                          items: [
                            const DropdownMenuItem<String?>(value: null, child: Text('Predeterminado')),
                            for (final t in menu.taxRates)
                              DropdownMenuItem<String?>(
                                value: t.id,
                                child: Text('${t.name} (${(t.rate * 100).toStringAsFixed(3)} %)'),
                              ),
                          ],
                          onChanged: (v) => setState(() => _taxRateId = v),
                        ),
                      ]),
                    ]),
                    _section('Modificadores', [
                      if (menu.modifierGroups.isEmpty)
                        const Text('No hay grupos de modificadores. Créalos en la sección "Modificadores".')
                      else
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final g in menu.modifierGroups)
                              FilterChip(
                                label: Text(_groupIds.contains(g.id)
                                    ? '${_groupIds.indexOf(g.id) + 1}. ${g.name}'
                                    : g.name),
                                tooltip: g.rulesLabel,
                                selected: _groupIds.contains(g.id),
                                onSelected: (selected) => setState(
                                    () => selected ? _groupIds.add(g.id) : _groupIds.remove(g.id)),
                              ),
                          ],
                        ),
                      const SizedBox(height: 4),
                      Text('Se muestran al cliente en el orden en que los seleccionas.', style: theme.textTheme.bodySmall),
                    ]),
                    _section('Alérgenos', [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final entry in allergenLabels.entries)
                            FilterChip(
                              label: Text(entry.value),
                              selected: _allergens.contains(entry.key),
                              onSelected: (s) => setState(() => s ? _allergens.add(entry.key) : _allergens.remove(entry.key)),
                            ),
                        ],
                      ),
                    ]),
                    _section('Visibilidad', [
                      SwitchListTile(
                        title: const Text('Activo en el menú'),
                        subtitle: const Text('Si lo desactivas, desaparece del menú pero no se borra'),
                        value: _isActive,
                        onChanged: (v) => setState(() => _isActive = v),
                      ),
                      SwitchListTile(
                        title: const Text('Disponible hoy'),
                        subtitle: const Text('Desactívalo cuando se agote'),
                        value: _isAvailable,
                        onChanged: (v) => setState(() => _isAvailable = v),
                      ),
                      CheckboxListTile(
                        title: const Text('Visible en las mesas y el POS'),
                        value: _dineIn,
                        onChanged: (v) => setState(() => _dineIn = v ?? true),
                      ),
                      CheckboxListTile(
                        title: const Text('Visible en la web de pedidos'),
                        value: _online,
                        onChanged: (v) => setState(() => _online = v ?? true),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _imageSection(ThemeData theme) {
    final Widget preview;
    if (_newImage != null) {
      preview = Image.memory(_newImage!, fit: BoxFit.cover);
    } else {
      preview = ProductImage(url: _removeImage ? null : _p?.imageUrl);
    }
    final hasImage = _newImage != null || (!_removeImage && _p?.imageUrl != null);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(width: 240, height: 180, child: preview),
        ),
        const SizedBox(width: 24),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Foto', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'JPG, PNG o WebP de hasta 8 MB. Se optimiza automáticamente para que cargue rápido.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 8, children: [
                FilledButton.tonalIcon(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.photo_library_rounded),
                  label: Text(hasImage ? 'Cambiar foto' : 'Subir foto'),
                ),
                if (hasImage)
                  TextButton(
                    onPressed: () => setState(() {
                      _newImage = null;
                      _removeImage = true;
                    }),
                    child: const Text('Quitar'),
                  ),
              ]),
            ],
          ),
        ),
      ],
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _row(List<Widget> fields) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < fields.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            Expanded(child: fields[i]),
          ],
        ],
      ),
    );
  }

  Widget _text(TextEditingController controller, String label, {bool required = false, int lines = 1}) {
    return TextFormField(
      controller: controller,
      maxLines: lines,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      validator: required ? (v) => (v == null || v.trim().isEmpty) ? 'Campo obligatorio' : null : null,
    );
  }
}
