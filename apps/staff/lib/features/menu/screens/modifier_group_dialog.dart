import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/feedback.dart';
import '../data/menu_models.dart';
import '../menu_controller.dart';
import '../widgets/common.dart';

Future<void> showModifierGroupDialog(BuildContext context, {ModifierGroup? group}) {
  return showDialog<void>(context: context, builder: (_) => _ModifierGroupDialog(group: group));
}

class _OptionDraft {
  _OptionDraft({this.id, String name = '', String nameEn = '', double price = 0, this.isDefault = false, this.isAvailable = true})
      : name = TextEditingController(text: name),
        nameEn = TextEditingController(text: nameEn),
        price = TextEditingController(text: price == 0 ? '' : price.toStringAsFixed(2));

  factory _OptionDraft.from(ModifierOption o) => _OptionDraft(
        id: o.id,
        name: o.name,
        nameEn: translated(o.translations, 'en', 'name') ?? '',
        price: o.priceAdjustment,
        isDefault: o.isDefault,
        isAvailable: o.isAvailable,
      );

  final String? id;
  final TextEditingController name;
  final TextEditingController nameEn;
  final TextEditingController price;
  bool isDefault;
  bool isAvailable;

  double get priceValue => double.tryParse(price.text.trim().replaceAll(',', '.')) ?? 0;

  Map<String, dynamic> toJson(int sortOrder, {required bool isNew}) {
    final en = nameEn.text.trim();
    return {
      'name': name.text.trim(),
      'priceAdjustment': priceValue,
      'isDefault': isDefault,
      'isAvailable': isAvailable,
      'sortOrder': sortOrder,
      if (en.isNotEmpty) 'translations': {'en': {'name': en}} else if (!isNew) 'translations': null,
    };
  }

  void dispose() {
    name.dispose();
    nameEn.dispose();
    price.dispose();
  }
}

class _ModifierGroupDialog extends ConsumerStatefulWidget {
  const _ModifierGroupDialog({this.group});
  final ModifierGroup? group;

  @override
  ConsumerState<_ModifierGroupDialog> createState() => _ModifierGroupDialogState();
}

class _ModifierGroupDialogState extends ConsumerState<_ModifierGroupDialog> {
  final _formKey = GlobalKey<FormState>();
  ModifierGroup? get _g => widget.group;

  late final _name = TextEditingController(text: _g?.name);
  late final _nameEn = TextEditingController(text: translated(_g?.translations, 'en', 'name'));
  late String _type = _g?.selectionType ?? 'SINGLE';
  late int _min = _g?.minSelect ?? 0;
  late int _max = _g?.maxSelect ?? 1;
  late bool _isActive = _g?.isActive ?? true;
  late final List<_OptionDraft> _options =
      _g?.options.map(_OptionDraft.from).toList() ?? [_OptionDraft()];
  final List<_OptionDraft> _removed = [];
  bool _saving = false;

  bool get _single => _type == 'SINGLE';

  @override
  void dispose() {
    _name.dispose();
    _nameEn.dispose();
    for (final o in [..._options, ..._removed]) {
      o.dispose();
    }
    super.dispose();
  }

  String? _validateRules() {
    if (_options.isEmpty) return 'Agrega al menos una opción';
    if (_min > _max) return 'El mínimo no puede ser mayor que el máximo';
    if (_min > _options.length) return 'El mínimo es mayor que la cantidad de opciones';
    final defaults = _options.where((o) => o.isDefault).length;
    if (defaults > _max) return 'Hay más opciones por defecto ($defaults) que el máximo ($_max)';
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final problem = _validateRules();
    if (problem != null) {
      showError(context, problem);
      return;
    }
    setState(() => _saving = true);
    final controller = ref.read(adminMenuProvider.notifier);
    final api = controller.api;
    final en = _nameEn.text.trim();
    final groupData = <String, dynamic>{
      'name': _name.text.trim(),
      'selectionType': _type,
      'minSelect': _min,
      'maxSelect': _max,
      'isActive': _isActive,
      if (en.isNotEmpty) 'translations': {'en': {'name': en}} else if (_g != null) 'translations': null,
    };

    try {
      final existing = _g;
      if (existing == null) {
        await api.createModifierGroup({
          ...groupData,
          'options': [for (var i = 0; i < _options.length; i++) _options[i].toJson(i, isNew: true)],
        });
      } else {
        // Orden pensado para no violar las reglas del grupo a mitad de camino.
        final growing = _max >= existing.maxSelect;
        if (growing) await api.updateModifierGroup(existing.id, groupData);

        final keptIds = _options.map((o) => o.id).whereType<String>().toSet();
        for (final removed in existing.options.where((o) => !keptIds.contains(o.id))) {
          await api.deleteModifierOption(removed.id);
        }
        final indexed = [for (var i = 0; i < _options.length; i++) (i, _options[i])];
        final updates = indexed.where((e) => e.$2.id != null).toList()
          ..sort((a, b) => (a.$2.isDefault ? 1 : 0).compareTo(b.$2.isDefault ? 1 : 0));
        for (final (index, option) in updates) {
          await api.updateModifierOption(option.id!, option.toJson(index, isNew: false));
        }
        for (final (index, option) in indexed.where((e) => e.$2.id == null)) {
          await api.addModifierOption(existing.id, option.toJson(index, isNew: true));
        }

        if (!growing) await api.updateModifierGroup(existing.id, groupData);
      }
      await controller.reload();
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) showError(context, error);
      await controller.reload().catchError((_) {});
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _setType(String type) {
    setState(() {
      _type = type;
      if (_single) {
        _max = 1;
        _min = _min > 0 ? 1 : 0;
        var seenDefault = false;
        for (final o in _options) {
          if (o.isDefault && seenDefault) o.isDefault = false;
          if (o.isDefault) seenDefault = true;
        }
      } else if (_max < 2) {
        _max = _options.length.clamp(2, 50);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(_g == null ? 'Nuevo grupo de modificadores' : 'Editar grupo'),
      content: SizedBox(
        width: 680,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: _name,
                      autofocus: _g == null,
                      decoration: const InputDecoration(labelText: 'Nombre (ej. Tamaño)', border: OutlineInputBorder()),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Escribe un nombre' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _nameEn,
                      decoration: const InputDecoration(labelText: 'Nombre en inglés', border: OutlineInputBorder()),
                    ),
                  ),
                ]),
                const SizedBox(height: 16),
                FitSegmented(SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'SINGLE', label: Text('Elige una'), icon: Icon(Icons.radio_button_checked)),
                    ButtonSegment(value: 'MULTIPLE', label: Text('Elige varias'), icon: Icon(Icons.check_box)),
                  ],
                  selected: {_type},
                  onSelectionChanged: (s) => _setType(s.first),
                )),
                const SizedBox(height: 8),
                if (_single)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Obligatorio (el cliente debe elegir una)'),
                    value: _min == 1,
                    onChanged: (v) => setState(() => _min = (v ?? false) ? 1 : 0),
                  )
                else
                  Row(children: [
                    Expanded(child: _counter('Mínimo', _min, 0, 50, (v) => setState(() => _min = v))),
                    const SizedBox(width: 12),
                    Expanded(child: _counter('Máximo', _max, 1, 50, (v) => setState(() => _max = v))),
                  ]),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Activo'),
                  value: _isActive,
                  onChanged: (v) => setState(() => _isActive = v),
                ),
                const Divider(),
                Text('Opciones', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                for (var i = 0; i < _options.length; i++) _optionRow(i),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _options.add(_OptionDraft())),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Agregar opción'),
                  ),
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

  Widget _optionRow(int index) {
    final option = _options[index];
    final name = TextFormField(
      controller: option.name,
      decoration: const InputDecoration(labelText: 'Opción', isDense: true, border: OutlineInputBorder()),
      validator: (v) => (v == null || v.trim().isEmpty) ? 'Obligatorio' : null,
    );
    return Padding(
      key: ObjectKey(option),
      padding: const EdgeInsets.only(bottom: 8),
      child: LayoutBuilder(builder: (context, box) {
        final controls = <Widget>[
          SizedBox(
            width: 110,
            child: TextFormField(
              controller: option.price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[-0-9.,]'))],
              decoration: const InputDecoration(
                labelText: 'Precio +/-',
                prefixText: '\$ ',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Tooltip(
            message: 'Seleccionada por defecto',
            child: Checkbox(
              value: option.isDefault,
              onChanged: (v) => setState(() {
                if (_single && (v ?? false)) {
                  for (final o in _options) {
                    o.isDefault = false;
                  }
                }
                option.isDefault = v ?? false;
              }),
            ),
          ),
          Tooltip(
            message: option.isAvailable ? 'Disponible' : 'Agotada',
            child: Switch(value: option.isAvailable, onChanged: (v) => setState(() => option.isAvailable = v)),
          ),
          IconButton(
            tooltip: 'Quitar',
            icon: const Icon(Icons.close_rounded),
            onPressed: () => setState(() => _removed.add(_options.removeAt(index))),
          ),
        ];
        final english = TextFormField(
          controller: option.nameEn,
          decoration: const InputDecoration(labelText: 'En inglés', isDense: true, border: OutlineInputBorder()),
        );
        // Angosto: nombre y nombre en inglés arriba, precio y controles abajo.
        if (box.maxWidth < 560) {
          return Column(children: [
            Row(children: [Expanded(child: name), const SizedBox(width: 8), Expanded(child: english)]),
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: controls),
          ]);
        }
        return Row(children: [
          Expanded(flex: 3, child: name),
          const SizedBox(width: 8),
          Expanded(flex: 3, child: english),
          const SizedBox(width: 8),
          ...controls,
        ]);
      }),
    );
  }


  Widget _counter(String label, int value, int min, int max, ValueChanged<int> onChanged) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.remove_rounded),
            onPressed: value > min ? () => onChanged(value - 1) : null,
          ),
          Expanded(child: Text('$value', textAlign: TextAlign.center)),
          IconButton(
            icon: const Icon(Icons.add_rounded),
            onPressed: value < max ? () => onChanged(value + 1) : null,
          ),
        ],
      ),
    );
  }
}
