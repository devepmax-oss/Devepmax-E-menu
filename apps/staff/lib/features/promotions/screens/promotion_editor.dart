import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/ui/feedback.dart';
import '../../menu/data/menu_models.dart';
import '../../menu/menu_controller.dart';
import '../data/promotions_api.dart';

Future<void> openPromotionEditor(BuildContext context, {Promotion? promotion}) {
  return Navigator.of(context).push(MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => _PromotionEditor(promotion: promotion),
  ));
}

class _PromotionEditor extends ConsumerStatefulWidget {
  const _PromotionEditor({this.promotion});
  final Promotion? promotion;

  @override
  ConsumerState<_PromotionEditor> createState() => _PromotionEditorState();
}

class _PromotionEditorState extends ConsumerState<_PromotionEditor> {
  final _formKey = GlobalKey<FormState>();
  Promotion? get _p => widget.promotion;

  late final _name = TextEditingController(text: _p?.name);
  late final _description = TextEditingController(text: _p?.description);
  late final _value = TextEditingController(text: _p?.value == null ? '' : _trim(_p!.value!));
  late final _buy = TextEditingController(text: '${_p?.buyQuantity ?? 1}');
  late final _get = TextEditingController(text: '${_p?.getQuantity ?? 1}');
  late final _comboPrice = TextEditingController(text: _p?.comboPrice == null ? '' : _p!.comboPrice!.toStringAsFixed(2));

  late String _type = _p?.type ?? 'PERCENT_OFF';
  late final Set<String> _productIds = {...?_p?.productIds};
  late final Set<String> _categoryIds = {...?_p?.categoryIds};
  late final List<ComboSlot> _slots = _p?.comboSlots.toList() ??
      [ComboSlot(name: 'Plato principal', quantity: 1), ComboSlot(name: 'Bebida', quantity: 1)];
  late final List<TextEditingController> _slotNames = _slots.map((s) => TextEditingController(text: s.name)).toList();
  late DateTime? _startsAt = _p?.startsAt;
  late DateTime? _endsAt = _p?.endsAt;
  late bool _dineIn = _p?.appliesDineIn ?? true;
  late bool _online = _p?.appliesOnline ?? true;
  late bool _isActive = _p?.isActive ?? true;
  bool _saving = false;

  static String _trim(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  @override
  void dispose() {
    for (final c in [_name, _description, _value, _buy, _get, _comboPrice, ..._slotNames]) {
      c.dispose();
    }
    super.dispose();
  }

  double? _number(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '.'));

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_dineIn && !_online) {
      showError(context, 'Elige al menos un canal: mesas y caja, o web');
      return;
    }
    for (var i = 0; i < _slots.length; i++) {
      _slots[i].name = _slotNames[i].text.trim();
    }
    final isCombo = _type == 'COMBO_PRICE';
    final isNew = _p == null;
    final data = <String, dynamic>{
      'name': _name.text.trim(),
      'description': _description.text.trim().isEmpty ? null : _description.text.trim(),
      'type': _type,
      'value': _type == 'PERCENT_OFF' || _type == 'AMOUNT_OFF' ? _number(_value) : null,
      'buyQuantity': _type == 'BUY_X_GET_Y' ? int.tryParse(_buy.text) : null,
      'getQuantity': _type == 'BUY_X_GET_Y' ? int.tryParse(_get.text) : null,
      'comboPrice': isCombo ? _number(_comboPrice) : null,
      'productIds': isCombo ? <String>[] : _productIds.toList(),
      'categoryIds': isCombo ? <String>[] : _categoryIds.toList(),
      'comboSlots': isCombo ? _slots.map((s) => s.toJson()).toList() : <Json>[],
      'startsAt': _startsAt?.toUtc().toIso8601String(),
      'endsAt': _endsAt?.toUtc().toIso8601String(),
      'appliesDineIn': _dineIn,
      'appliesOnline': _online,
      'isActive': _isActive,
    };
    if (isNew) data.removeWhere((_, v) => v == null);

    setState(() => _saving = true);
    try {
      final api = ref.read(promotionsApiProvider);
      if (isNew) {
        await api.create(data);
      } else {
        await api.update(_p!.id, data);
      }
      ref.invalidate(promotionsProvider);
      if (mounted) {
        showSuccess(context, 'Promoción guardada');
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickDate(bool start) async {
    final now = DateTime.now();
    final current = start ? _startsAt : _endsAt;
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _startsAt = DateTime(picked.year, picked.month, picked.day);
      } else {
        _endsAt = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final menu = ref.watch(adminMenuProvider).value;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_p == null ? 'Nueva promoción' : 'Editar promoción'),
        actions: [
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Guardar'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: menu == null
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(padding: const EdgeInsets.all(24), children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 860),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      _card('Promoción', [
                        TextFormField(
                          controller: _name,
                          decoration: const InputDecoration(
                            labelText: 'Nombre (lo ve el cliente)',
                            hintText: '2x1 en tacos los martes',
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Escribe un nombre' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _description,
                          maxLines: 2,
                          decoration: const InputDecoration(labelText: 'Descripción (opcional)', border: OutlineInputBorder()),
                        ),
                        const SizedBox(height: 16),
                        SegmentedButton<String>(
                          segments: [
                            for (final e in promotionTypeLabels.entries) ButtonSegment(value: e.key, label: Text(e.value)),
                          ],
                          selected: {_type},
                          onSelectionChanged: (s) => setState(() => _type = s.first),
                        ),
                        const SizedBox(height: 16),
                        ..._ruleFields(),
                      ]),
                      if (_type == 'COMBO_PRICE')
                        _card('Partes del combo', [
                          Text(
                            'El combo se aplica cuando la orden tiene un producto de cada parte. '
                            'Cada plato sigue llegando a su estación de cocina.',
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: 12),
                          for (var i = 0; i < _slots.length; i++) _slotEditor(i, menu),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: _slots.length >= 8
                                  ? null
                                  : () => setState(() {
                                        _slots.add(ComboSlot(name: 'Parte ${_slots.length + 1}', quantity: 1));
                                        _slotNames.add(TextEditingController(text: 'Parte ${_slots.length}'));
                                      }),
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('Agregar parte'),
                            ),
                          ),
                        ])
                      else
                        _card('¿A qué productos aplica?', [
                          _TargetPicker(
                            menu: menu,
                            productIds: _productIds,
                            categoryIds: _categoryIds,
                            onChanged: () => setState(() {}),
                          ),
                        ]),
                      _card('Cuándo y dónde', [
                        Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                          _dateButton('Desde', _startsAt, () => _pickDate(true), () => setState(() => _startsAt = null)),
                          _dateButton('Hasta', _endsAt, () => _pickDate(false), () => setState(() => _endsAt = null)),
                        ]),
                        const SizedBox(height: 8),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('En mesas y caja'),
                          value: _dineIn,
                          onChanged: (v) => setState(() => _dineIn = v ?? true),
                        ),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('En la web de pedidos'),
                          value: _online,
                          onChanged: (v) => setState(() => _online = v ?? true),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Activa'),
                          value: _isActive,
                          onChanged: (v) => setState(() => _isActive = v),
                        ),
                      ]),
                    ]),
                  ),
                ),
              ]),
            ),
    );
  }

  List<Widget> _ruleFields() {
    final digits = [FilteringTextInputFormatter.digitsOnly];
    final decimal = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];
    switch (_type) {
      case 'PERCENT_OFF':
      case 'AMOUNT_OFF':
        final percent = _type == 'PERCENT_OFF';
        return [
          SizedBox(
            width: 220,
            child: TextFormField(
              controller: _value,
              inputFormatters: decimal,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: percent ? 'Porcentaje' : 'Descuento por unidad',
                prefixText: percent ? null : '\$ ',
                suffixText: percent ? '%' : null,
                border: const OutlineInputBorder(),
              ),
              validator: (v) {
                final n = double.tryParse((v ?? '').replaceAll(',', '.'));
                if (n == null || n <= 0) return 'Escribe un valor';
                if (percent && n > 100) return 'Máximo 100';
                return null;
              },
            ),
          ),
        ];
      case 'BUY_X_GET_Y':
        return [
          Row(children: [
            SizedBox(
              width: 140,
              child: TextFormField(
                controller: _buy,
                inputFormatters: digits,
                decoration: const InputDecoration(labelText: 'Paga', border: OutlineInputBorder()),
                validator: (v) => (int.tryParse(v ?? '') ?? 0) < 1 ? 'Mínimo 1' : null,
                onChanged: (_) => setState(() {}),
              ),
            ),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('y lleva gratis')),
            SizedBox(
              width: 140,
              child: TextFormField(
                controller: _get,
                inputFormatters: digits,
                decoration: const InputDecoration(labelText: 'Gratis', border: OutlineInputBorder()),
                validator: (v) => (int.tryParse(v ?? '') ?? 0) < 1 ? 'Mínimo 1' : null,
                onChanged: (_) => setState(() {}),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Text(
            () {
              final buy = int.tryParse(_buy.text) ?? 1;
              final get = int.tryParse(_get.text) ?? 1;
              return 'Ejemplo: lleva ${buy + get}, paga $buy. Sale gratis el más barato.';
            }(),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ];
      case 'COMBO_PRICE':
        return [
          SizedBox(
            width: 220,
            child: TextFormField(
              controller: _comboPrice,
              inputFormatters: decimal,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Precio del combo', prefixText: '\$ ', border: OutlineInputBorder()),
              validator: (v) => (double.tryParse((v ?? '').replaceAll(',', '.')) ?? 0) <= 0 ? 'Escribe el precio' : null,
            ),
          ),
        ];
    }
    return const [];
  }

  Widget _slotEditor(int index, AdminMenu menu) {
    final slot = _slots[index];
    return Card(
      key: ObjectKey(slot),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: _slotNames[index],
                decoration: const InputDecoration(labelText: 'Nombre de la parte', isDense: true, border: OutlineInputBorder()),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Obligatorio' : null,
              ),
            ),
            const SizedBox(width: 12),
            const Text('Cantidad'),
            IconButton(
              icon: const Icon(Icons.remove_rounded),
              onPressed: slot.quantity > 1 ? () => setState(() => slot.quantity--) : null,
            ),
            Text('${slot.quantity}'),
            IconButton(
              icon: const Icon(Icons.add_rounded),
              onPressed: slot.quantity < 10 ? () => setState(() => slot.quantity++) : null,
            ),
            IconButton(
              tooltip: 'Quitar parte',
              icon: const Icon(Icons.close_rounded),
              onPressed: _slots.length <= 2
                  ? null
                  : () => setState(() {
                        _slots.removeAt(index);
                        _slotNames.removeAt(index);
                      }),
            ),
          ]),
          const SizedBox(height: 8),
          _TargetPicker(
            menu: menu,
            productIds: slot.productIds,
            categoryIds: slot.categoryIds,
            onChanged: () => setState(() {}),
          ),
        ]),
      ),
    );
  }

  Widget _dateButton(String label, DateTime? value, VoidCallback onPick, VoidCallback onClear) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      OutlinedButton.icon(
        onPressed: onPick,
        icon: const Icon(Icons.event_rounded),
        label: Text(value == null ? '$label: sin fecha' : '$label: ${DateFormat.yMMMd().format(value)}'),
      ),
      if (value != null) IconButton(tooltip: 'Quitar fecha', icon: const Icon(Icons.close_rounded), onPressed: onClear),
    ]);
  }

  Widget _card(String title, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          ...children,
        ]),
      ),
    );
  }
}

/// Selección de categorías completas o productos sueltos.
class _TargetPicker extends StatelessWidget {
  const _TargetPicker({
    required this.menu,
    required this.productIds,
    required this.categoryIds,
    required this.onChanged,
  });

  final AdminMenu menu;
  final Set<String> productIds;
  final Set<String> categoryIds;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final category in menu.categories)
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Row(children: [
            Checkbox(
              value: categoryIds.contains(category.id),
              onChanged: (v) {
                v == true ? categoryIds.add(category.id) : categoryIds.remove(category.id);
                onChanged();
              },
            ),
            Expanded(child: Text('${category.name} (toda la categoría)')),
          ]),
          subtitle: Text(
            '${category.products.where((p) => productIds.contains(p.id)).length} producto(s) elegido(s)',
          ),
          children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final product in category.products)
                FilterChip(
                  label: Text(product.name),
                  selected: productIds.contains(product.id) || categoryIds.contains(category.id),
                  onSelected: categoryIds.contains(category.id)
                      ? null
                      : (s) {
                          s ? productIds.add(product.id) : productIds.remove(product.id);
                          onChanged();
                        },
                ),
            ]),
            const SizedBox(height: 8),
          ],
        ),
    ]);
  }
}
