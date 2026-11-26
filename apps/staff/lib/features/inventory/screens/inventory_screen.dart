import 'package:collection/collection.dart';
import 'package:devepmax_ui/devepmax_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/ui/feedback.dart';
import '../../menu/widgets/common.dart';
import '../data/inventory_api.dart';

final _decimals = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))];
double? _num(String s) => double.tryParse(s.trim());

/// Costos por unidad pequeños ($0.012 por g) con más decimales.
String unitMoney(double v) {
  if (v == 0 || v >= 1) return formatMoney(v);
  var s = v.toStringAsFixed(4);
  while (s.endsWith('0') && !s.endsWith('.00')) {
    s = s.substring(0, s.length - 1);
  }
  return '\$$s';
}

/// Inventario: ingredientes, recetas con costo y margen, proveedores y movimientos.
class InventoryScreen extends ConsumerWidget {
  const InventoryScreen({super.key});

  void _refresh(WidgetRef ref) {
    ref.invalidate(inventorySummaryProvider);
    ref.invalidate(inventoryItemsProvider);
    ref.invalidate(recipesProvider);
    ref.invalidate(movementsProvider);
    ref.invalidate(suppliersProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Inventario'),
          actions: [
            AppBarAction(
              icon: Icons.local_shipping_rounded,
              label: 'Entrada de mercancía',
              onPressed: () async {
                final ok = await showDialog<bool>(context: context, builder: (_) => const _ReceiptDialog());
                if (ok == true) _refresh(ref);
              },
            ),
            const SizedBox(width: 16),
          ],
          bottom: const TabBar(isScrollable: true, tabs: [
            Tab(text: 'Ingredientes'),
            Tab(text: 'Recetas y costos'),
            Tab(text: 'Proveedores'),
            Tab(text: 'Movimientos'),
          ]),
        ),
        body: Column(children: [
          _SummaryBar(onChanged: () => _refresh(ref)),
          Expanded(
            child: TabBarView(children: [
              _ItemsTab(onChanged: () => _refresh(ref)),
              _RecipesTab(onChanged: () => _refresh(ref)),
              _SuppliersTab(onChanged: () => _refresh(ref)),
              const _MovementsTab(),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _SummaryBar extends ConsumerWidget {
  const _SummaryBar({required this.onChanged});
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(inventorySummaryProvider).value;
    final t = BrandTokens.of(context);
    final text = Theme.of(context).textTheme;
    if (s == null) return const LinearProgressIndicator(minHeight: 2);
    Widget stat(String label, String value, {Color? color}) => Padding(
          padding: const EdgeInsets.only(right: 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(label, style: text.bodySmall?.copyWith(color: t.muted)),
            Text(value, style: text.titleMedium?.copyWith(color: color)),
          ]),
        );
    Future<void> toggle({bool? enabled, bool? autoSoldOut}) async {
      try {
        await ref.read(inventoryApiProvider).settings(enabled: enabled, autoSoldOut: autoSoldOut);
        onChanged();
      } catch (e) {
        if (context.mounted) showError(context, e);
      }
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.line))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            stat('Valor del inventario', formatMoney(s.value)),
            stat('Bajo mínimo', '${s.low}', color: s.low > 0 ? t.danger : null),
            stat('Costo de lo vendido (7 días)', formatMoney(s.used7)),
            stat('Mermas (7 días)', formatMoney(s.waste7), color: s.waste7 > 0 ? t.danger : null),
            if (s.soldOut > 0) stat('Platos agotados por stock', '${s.soldOut}', color: t.danger),
          ]),
        ),
        Wrap(spacing: 16, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Switch(value: s.enabled, onChanged: (v) => toggle(enabled: v)),
            const Text('Descontar las ventas'),
          ]),
          if (s.enabled)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Switch(value: s.autoSoldOut, onChanged: (v) => toggle(autoSoldOut: v)),
              const Text('Agotar platos sin ingredientes'),
            ]),
        ]),
      ]),
    );
  }
}

// ───────── Ingredientes ─────────

class _ItemsTab extends ConsumerStatefulWidget {
  const _ItemsTab({required this.onChanged});
  final VoidCallback onChanged;

  @override
  ConsumerState<_ItemsTab> createState() => _ItemsTabState();
}

class _ItemsTabState extends ConsumerState<_ItemsTab> {
  bool _lowOnly = false;

  Future<void> _open(InventoryItem? item) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => _ItemDialog(item: item));
    if (ok == true) widget.onChanged();
  }

  Future<void> _action(String action, InventoryItem item) async {
    bool? ok;
    if (action == 'count') ok = await showDialog<bool>(context: context, builder: (_) => _CountDialog(item: item));
    if (action == 'waste') ok = await showDialog<bool>(context: context, builder: (_) => _WasteDialog(item: item));
    if (action == 'history') {
      await showDialog<void>(context: context, builder: (_) => _HistoryDialog(item: item));
      return;
    }
    if (ok == true) widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(inventoryItemsProvider);
    final t = BrandTokens.of(context);
    final text = Theme.of(context).textTheme;
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(inventoryItemsProvider)),
      data: (all) {
        final list = _lowOnly ? all.where((i) => i.low && i.isActive).toList() : all;
        return ListView(padding: const EdgeInsets.fromLTRB(24, 12, 24, 24), children: [
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            FilledButton.icon(onPressed: () => _open(null), icon: const Icon(Icons.add_rounded), label: const Text('Nuevo ingrediente')),
            FilterChip(label: const Text('Solo bajo mínimo'), selected: _lowOnly, onSelected: (v) => setState(() => _lowOnly = v)),
          ]),
          const SizedBox(height: 12),
          if (list.isEmpty)
            const EmptyState(
              icon: Icons.inventory_2_rounded,
              message: 'Agrega tus ingredientes (carne, pan, queso…) con su unidad. Luego arma la receta de cada plato.',
            ),
          for (final i in list)
            Card(
              child: ListTile(
                onTap: () => _open(i),
                leading: Icon(Icons.inventory_2_rounded, color: !i.isActive ? t.muted : (i.low ? t.danger : t.accentText)),
                title: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text(i.name, style: TextStyle(fontWeight: FontWeight.w600, color: i.isActive ? null : t.muted)),
                  if (!i.isActive) const DmPill('Inactivo'),
                  if (i.isActive && i.low) const DmPill('Bajo mínimo', tone: DmTone.danger),
                ]),
                subtitle: Text([
                  '${unitMoney(i.costPerUnit)} por ${i.unitLabel}',
                  if (i.minLevel != null) 'mínimo ${qty(i.minLevel!)} ${i.unitLabel}',
                  if (i.supplierName != null) i.supplierName!,
                  if (i.usedIn > 0) 'en ${i.usedIn} ${i.usedIn == 1 ? 'receta' : 'recetas'}',
                ].join(' · ')),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('${qty(i.onHand)} ${i.unitLabel}', style: text.titleMedium?.copyWith(color: i.onHand < 0 ? t.danger : null)),
                    Text(formatMoney(i.value), style: text.bodySmall?.copyWith(color: t.muted)),
                  ]),
                  PopupMenuButton<String>(
                    tooltip: 'Más',
                    onSelected: (a) => _action(a, i),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'count', child: ListTile(leading: Icon(Icons.fact_check_rounded), title: Text('Conteo físico'))),
                      PopupMenuItem(value: 'waste', child: ListTile(leading: Icon(Icons.delete_sweep_rounded), title: Text('Registrar merma'))),
                      PopupMenuItem(value: 'history', child: ListTile(leading: Icon(Icons.history_rounded), title: Text('Movimientos'))),
                    ],
                  ),
                ]),
              ),
            ),
        ]);
      },
    );
  }
}

class _ItemDialog extends ConsumerStatefulWidget {
  const _ItemDialog({this.item});
  final InventoryItem? item;

  @override
  ConsumerState<_ItemDialog> createState() => _ItemDialogState();
}

class _ItemDialogState extends ConsumerState<_ItemDialog> {
  final _form = GlobalKey<FormState>();
  InventoryItem? get _i => widget.item;
  late final _name = TextEditingController(text: _i?.name ?? '');
  late final _min = TextEditingController(text: _i?.minLevel == null ? '' : qty(_i!.minLevel!).replaceAll(',', ''));
  late final _cost = TextEditingController(text: _i == null ? '' : _i!.costPerUnit.toString());
  late final _onHand = TextEditingController();
  late final _sku = TextEditingController(text: _i?.sku ?? '');
  late String _unit = _i?.unit ?? 'unit';
  late String? _supplierId = _i?.supplierId;
  late bool _active = _i?.isActive ?? true;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _min, _cost, _onHand, _sku]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(inventoryApiProvider).saveItem(_i?.id, {
        'name': _name.text.trim(),
        'unit': _unit,
        'minLevel': _num(_min.text),
        if (_num(_cost.text) != null) 'costPerUnit': _num(_cost.text),
        'supplierId': _supplierId,
        'sku': _sku.text.trim().isEmpty ? null : _sku.text.trim(),
        'isActive': _active,
        if (_i == null && _num(_onHand.text) != null) 'onHand': _num(_onHand.text),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await confirm(context, title: 'Borrar ingrediente', message: 'Se borra "${_i!.name}". Si ya tiene movimientos, desactívalo en vez de borrarlo.');
    if (!ok) return;
    try {
      await ref.read(inventoryApiProvider).removeItem(_i!.id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final suppliers = ref.watch(suppliersProvider).value ?? const <Supplier>[];
    String? optional(String? v) => (v ?? '').trim().isEmpty || _num(v!) != null ? null : 'Número inválido';
    return AlertDialog(
      scrollable: true,
      title: Text(_i == null ? 'Nuevo ingrediente' : _i!.name),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _form,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Nombre', hintText: 'Carne molida'),
              validator: (v) => (v ?? '').trim().length < 2 ? 'Escribe el nombre' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _unit,
              decoration: const InputDecoration(labelText: 'Unidad (las recetas y compras usan esta unidad)'),
              items: [for (final e in unitLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => setState(() => _unit = v ?? 'unit'),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _cost,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: _decimals,
                  decoration: InputDecoration(labelText: 'Costo por ${unitLabels[_unit]}', prefixText: '\$ ', helperText: 'Se actualiza con cada compra'),
                  validator: optional,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _min,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: _decimals,
                  decoration: InputDecoration(labelText: 'Mínimo (${unitLabels[_unit]})', helperText: 'Para avisar'),
                  validator: optional,
                ),
              ),
            ]),
            if (_i == null) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _onHand,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: _decimals,
                decoration: InputDecoration(labelText: 'Existencia actual (${unitLabels[_unit]})', hintText: '0'),
                validator: optional,
              ),
            ],
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              isExpanded: true,
              initialValue: suppliers.any((s) => s.id == _supplierId) ? _supplierId : null,
              decoration: const InputDecoration(labelText: 'Proveedor (opcional)'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('—')),
                for (final s in suppliers.where((s) => s.isActive || s.id == _supplierId)) DropdownMenuItem<String?>(value: s.id, child: Text(s.name)),
              ],
              onChanged: (v) => setState(() => _supplierId = v),
            ),
            const SizedBox(height: 12),
            TextFormField(controller: _sku, decoration: const InputDecoration(labelText: 'Código o SKU (opcional)')),
            if (_i != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _active,
                onChanged: (v) => setState(() => _active = v),
                title: const Text('Activo'),
              ),
          ]),
        ),
      ),
      actions: [
        if (_i != null) TextButton(onPressed: _saving ? null : _delete, child: const Text('Borrar')),
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('Guardar')),
      ],
    );
  }
}

class _CountDialog extends ConsumerStatefulWidget {
  const _CountDialog({required this.item});
  final InventoryItem item;

  @override
  ConsumerState<_CountDialog> createState() => _CountDialogState();
}

class _CountDialogState extends ConsumerState<_CountDialog> {
  final _value = TextEditingController();
  final _reason = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _value.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final v = _num(_value.text);
    if (v == null) return;
    setState(() => _saving = true);
    try {
      await ref.read(inventoryApiProvider).count(widget.item.id, v, _reason.text.trim());
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final i = widget.item;
    final v = _num(_value.text);
    final diff = v == null ? null : v - i.onHand;
    return AlertDialog(
      scrollable: true,
      title: Text('Conteo · ${i.name}'),
      content: SizedBox(
        width: 380,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('El sistema dice: ${qty(i.onHand)} ${i.unitLabel}'),
          const SizedBox(height: 12),
          TextField(
            controller: _value,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: _decimals,
            decoration: InputDecoration(labelText: 'Lo que hay de verdad (${i.unitLabel})'),
            onChanged: (_) => setState(() {}),
          ),
          if (diff != null && diff != 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Diferencia: ${diff > 0 ? '+' : ''}${qty(diff)} ${i.unitLabel} (${formatMoney(diff * i.costPerUnit)})'),
            ),
          const SizedBox(height: 12),
          TextField(controller: _reason, decoration: const InputDecoration(labelText: 'Nota (opcional)')),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(onPressed: _saving || v == null ? null : _save, child: const Text('Guardar conteo')),
      ],
    );
  }
}

class _WasteDialog extends ConsumerStatefulWidget {
  const _WasteDialog({required this.item});
  final InventoryItem item;

  @override
  ConsumerState<_WasteDialog> createState() => _WasteDialogState();
}

class _WasteDialogState extends ConsumerState<_WasteDialog> {
  final _value = TextEditingController();
  final _reason = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _value.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final i = widget.item;
    final v = _num(_value.text);
    final ok = v != null && v > 0 && _reason.text.trim().length >= 3;
    return AlertDialog(
      scrollable: true,
      title: Text('Merma · ${i.name}'),
      content: SizedBox(
        width: 380,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            controller: _value,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: _decimals,
            decoration: InputDecoration(labelText: 'Cantidad (${i.unitLabel})', helperText: v == null ? null : 'Costo: ${formatMoney(v * i.costPerUnit)}'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final r in const ['Se venció', 'Se quemó', 'Se cayó', 'Mal estado'])
              ActionChip(label: Text(r), onPressed: () => setState(() => _reason.text = r)),
          ]),
          const SizedBox(height: 8),
          TextField(controller: _reason, decoration: const InputDecoration(labelText: 'Motivo'), onChanged: (_) => setState(() {})),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(
          onPressed: _saving || !ok
              ? null
              : () async {
                  setState(() => _saving = true);
                  try {
                    await ref.read(inventoryApiProvider).waste(i.id, v!, _reason.text.trim());
                    if (context.mounted) Navigator.pop(context, true);
                  } catch (e) {
                    if (context.mounted) showError(context, e);
                  } finally {
                    if (mounted) setState(() => _saving = false);
                  }
                },
          child: const Text('Registrar merma'),
        ),
      ],
    );
  }
}

class _HistoryDialog extends ConsumerWidget {
  const _HistoryDialog({required this.item});
  final InventoryItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(movementsProvider(item.id));
    return AlertDialog(
      title: Text('Movimientos · ${item.name}'),
      content: SizedBox(
        width: 520,
        height: 420,
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(movementsProvider(item.id))),
          data: (moves) => moves.isEmpty ? const Center(child: Text('Sin movimientos')) : _MovesList(moves: moves, showItem: false),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))],
    );
  }
}

// ───────── Entrada de mercancía ─────────

class _ReceiptLine {
  String? itemId;
  final qty = TextEditingController();
  final cost = TextEditingController();
  bool totalMode = true; // el costo escrito es el total de la línea (como viene en la factura)
}

class _ReceiptDialog extends ConsumerStatefulWidget {
  const _ReceiptDialog();

  @override
  ConsumerState<_ReceiptDialog> createState() => _ReceiptDialogState();
}

class _ReceiptDialogState extends ConsumerState<_ReceiptDialog> {
  final _lines = [_ReceiptLine()];
  final _reference = TextEditingController();
  String? _supplierId;
  bool _saving = false;

  @override
  void dispose() {
    for (final l in _lines) {
      l.qty.dispose();
      l.cost.dispose();
    }
    _reference.dispose();
    super.dispose();
  }

  double? _unitCost(_ReceiptLine l) {
    final q = _num(l.qty.text);
    final c = _num(l.cost.text);
    if (q == null || c == null || q <= 0) return null;
    return l.totalMode ? c / q : c;
  }

  double get _total => _lines.fold(0, (s, l) {
        final q = _num(l.qty.text) ?? 0;
        final u = _unitCost(l) ?? 0;
        return s + q * u;
      });

  bool get _valid => _lines.every((l) => l.itemId != null && (_num(l.qty.text) ?? 0) > 0 && _unitCost(l) != null);

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(inventoryApiProvider).receive(
        supplierId: _supplierId,
        reference: _reference.text,
        lines: [
          for (final l in _lines)
            {'itemId': l.itemId, 'quantity': _num(l.qty.text), 'unitCost': double.parse(_unitCost(l)!.toStringAsFixed(4))},
        ],
      );
      if (mounted) {
        showSuccess(context, 'Entrada registrada');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = (ref.watch(inventoryItemsProvider).value ?? const <InventoryItem>[]).where((i) => i.isActive).toList();
    final suppliers = (ref.watch(suppliersProvider).value ?? const <Supplier>[]).where((s) => s.isActive).toList();
    return AlertDialog(
      scrollable: true,
      title: const Text('Entrada de mercancía'),
      content: SizedBox(
        width: 620,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String?>(
                isExpanded: true,
                initialValue: _supplierId,
                decoration: const InputDecoration(labelText: 'Proveedor'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('—')),
                  for (final s in suppliers) DropdownMenuItem<String?>(value: s.id, child: Text(s.name)),
                ],
                onChanged: (v) => setState(() => _supplierId = v),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: _reference, decoration: const InputDecoration(labelText: 'Factura (opcional)'))),
          ]),
          const SizedBox(height: 16),
          if (items.isEmpty) const Text('Primero agrega ingredientes en la pestaña Ingredientes.'),
          for (final (index, l) in _lines.indexed) ...[
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                flex: 4,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: l.itemId,
                  decoration: const InputDecoration(labelText: 'Ingrediente'),
                  items: [for (final i in items) DropdownMenuItem(value: i.id, child: Text('${i.name} (${i.unitLabel})', overflow: TextOverflow.ellipsis))],
                  onChanged: (v) => setState(() => l.itemId = v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: l.qty,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: _decimals,
                  decoration: InputDecoration(labelText: 'Cantidad', suffixText: items.firstWhereOrNull((i) => i.id == l.itemId)?.unitLabel),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: TextField(
                  controller: l.cost,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: _decimals,
                  decoration: InputDecoration(
                    labelText: l.totalMode ? 'Costo total' : 'Costo por unidad',
                    prefixText: '\$ ',
                    helperText: _unitCost(l) == null ? null : (l.totalMode ? '${unitMoney(_unitCost(l)!)} c/u' : 'total ${formatMoney(_unitCost(l)! * (_num(l.qty.text) ?? 0))}'),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              IconButton(
                tooltip: l.totalMode ? 'Escribir costo por unidad' : 'Escribir costo total',
                onPressed: () => setState(() => l.totalMode = !l.totalMode),
                icon: const Icon(Icons.swap_horiz_rounded),
              ),
              if (_lines.length > 1)
                IconButton(
                  tooltip: 'Quitar',
                  onPressed: () => setState(() => _lines.removeAt(index)),
                  icon: const Icon(Icons.close_rounded),
                ),
            ]),
            const SizedBox(height: 8),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(onPressed: () => setState(() => _lines.add(_ReceiptLine())), icon: const Icon(Icons.add_rounded), label: const Text('Otro ingrediente')),
          ),
          const Divider(),
          Text('Total: ${formatMoney(_total)}', textAlign: TextAlign.right, style: Theme.of(context).textTheme.titleLarge),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(onPressed: _saving || !_valid ? null : _save, child: const Text('Registrar entrada')),
      ],
    );
  }
}

// ───────── Recetas y costos ─────────

class _RecipesTab extends ConsumerWidget {
  const _RecipesTab({required this.onChanged});
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(recipesProvider);
    final t = BrandTokens.of(context);
    final text = Theme.of(context).textTheme;
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(recipesProvider)),
      data: (list) {
        if (list.isEmpty) return const EmptyState(icon: Icons.menu_book_rounded, message: 'No hay productos en el menú.');
        String? lastCategory;
        final children = <Widget>[];
        for (final p in list) {
          if (p.category != lastCategory) {
            lastCategory = p.category;
            children.add(Padding(padding: const EdgeInsets.fromLTRB(4, 16, 4, 6), child: Text(p.category, style: text.titleSmall?.copyWith(color: t.muted))));
          }
          final pct = p.foodCostPct;
          final tone = pct == null || p.lines.isEmpty ? DmTone.neutral : (pct <= 30 ? DmTone.success : (pct <= 40 ? DmTone.warning : DmTone.danger));
          children.add(Card(
            child: ListTile(
              onTap: () async {
                final ok = await showDialog<bool>(context: context, builder: (_) => _RecipeDialog(plate: p));
                if (ok == true) onChanged();
              },
              title: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                if (!p.isAvailable && p.soldOutByStock) const DmPill('Agotado por stock', tone: DmTone.danger),
              ]),
              subtitle: Text(p.lines.isEmpty ? 'Sin receta: toca para agregar ingredientes' : p.lines.map((l) => '${qty(l.quantity)} ${unitLabels[l.unit] ?? l.unit} ${l.item}').join(' · '),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: p.lines.isEmpty
                  ? Text(formatMoney(p.price), style: text.titleMedium)
                  : Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('${formatMoney(p.cost)} de ${formatMoney(p.price)}', style: text.bodyMedium),
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Text('gana ${formatMoney(p.margin)} ', style: text.bodySmall),
                        if (pct != null) DmPill('${pct.toStringAsFixed(0)} %', tone: tone),
                      ]),
                    ]),
            ),
          ));
        }
        return ListView(padding: const EdgeInsets.fromLTRB(24, 0, 24, 24), children: [
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text('El % es lo que se va en ingredientes ("food cost"). Verde hasta 30 %, amarillo hasta 40 %.', style: text.bodySmall?.copyWith(color: t.muted)),
          ),
          ...children,
        ]);
      },
    );
  }
}

class _RecipeRow {
  _RecipeRow(this.itemId, String quantity) : qty = TextEditingController(text: quantity);
  String? itemId;
  final TextEditingController qty;
}

class _RecipeDialog extends ConsumerStatefulWidget {
  const _RecipeDialog({required this.plate});
  final PlateCost plate;

  @override
  ConsumerState<_RecipeDialog> createState() => _RecipeDialogState();
}

class _RecipeDialogState extends ConsumerState<_RecipeDialog> {
  late final List<_RecipeRow> _rows = [
    for (final l in widget.plate.lines) _RecipeRow(l.itemId, qty(l.quantity).replaceAll(',', '')),
    if (widget.plate.lines.isEmpty) _RecipeRow(null, ''),
  ];
  bool _saving = false;

  @override
  void dispose() {
    for (final r in _rows) {
      r.qty.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final lines = [
      for (final r in _rows)
        if (r.itemId != null && (_num(r.qty.text) ?? 0) > 0) {'itemId': r.itemId, 'quantity': _num(r.qty.text)},
    ];
    if (lines.map((l) => l['itemId']).toSet().length != lines.length) {
      showError(context, 'Un ingrediente aparece dos veces');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(inventoryApiProvider).saveRecipe(widget.plate.productId, lines);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = (ref.watch(inventoryItemsProvider).value ?? const <InventoryItem>[]);
    final byId = {for (final i in items) i.id: i};
    final cost = _rows.fold<double>(0, (s, r) => s + (_num(r.qty.text) ?? 0) * (byId[r.itemId]?.costPerUnit ?? 0));
    final price = widget.plate.price;
    final text = Theme.of(context).textTheme;
    return AlertDialog(
      scrollable: true,
      title: Text('Receta · ${widget.plate.name}'),
      content: SizedBox(
        width: 520,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Cuánto de cada ingrediente lleva UNA porción. Al vender, se descuenta del inventario.', style: text.bodySmall),
          const SizedBox(height: 12),
          for (final (index, r) in _rows.indexed) ...[
            Row(children: [
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: byId.containsKey(r.itemId) ? r.itemId : null,
                  decoration: const InputDecoration(labelText: 'Ingrediente'),
                  items: [
                    for (final i in items.where((i) => i.isActive || i.id == r.itemId))
                      DropdownMenuItem(value: i.id, child: Text(i.name, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setState(() => r.itemId = v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: r.qty,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: _decimals,
                  decoration: InputDecoration(labelText: 'Cantidad', suffixText: byId[r.itemId]?.unitLabel),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              IconButton(
                tooltip: 'Quitar',
                onPressed: () => setState(() => _rows.removeAt(index)),
                icon: const Icon(Icons.close_rounded),
              ),
            ]),
            const SizedBox(height: 8),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(onPressed: () => setState(() => _rows.add(_RecipeRow(null, ''))), icon: const Icon(Icons.add_rounded), label: const Text('Agregar ingrediente')),
          ),
          if (items.isEmpty) const Text('Primero agrega ingredientes en la pestaña Ingredientes.'),
          const Divider(),
          Text(
            'Costo ${formatMoney(cost)} · precio ${formatMoney(price)} · gana ${formatMoney(price - cost)}'
            '${price > 0 ? ' · ${(cost / price * 100).toStringAsFixed(1)} % en ingredientes' : ''}',
            style: text.titleSmall,
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('Guardar receta')),
      ],
    );
  }
}

// ───────── Proveedores ─────────

class _SuppliersTab extends ConsumerWidget {
  const _SuppliersTab({required this.onChanged});
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(suppliersProvider);
    final t = BrandTokens.of(context);
    Future<void> open(Supplier? s) async {
      final ok = await showDialog<bool>(context: context, builder: (_) => _SupplierDialog(supplier: s));
      if (ok == true) onChanged();
    }

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(suppliersProvider)),
      data: (list) => ListView(padding: const EdgeInsets.fromLTRB(24, 12, 24, 24), children: [
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(onPressed: () => open(null), icon: const Icon(Icons.add_rounded), label: const Text('Nuevo proveedor')),
        ),
        const SizedBox(height: 12),
        if (list.isEmpty) const EmptyState(icon: Icons.local_shipping_rounded, message: 'Agrega a quién le compras: carnicería, panadería, distribuidora…'),
        for (final s in list)
          Card(
            child: ListTile(
              onTap: () => open(s),
              leading: Icon(Icons.storefront_rounded, color: s.isActive ? t.accentText : t.muted),
              title: Wrap(spacing: 8, children: [
                Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                if (!s.isActive) const DmPill('Inactivo'),
              ]),
              subtitle: Text([
                if (s.contactName != null) s.contactName!,
                if (s.phone != null) s.phone!,
                if (s.email != null) s.email!,
                '${s.items} ingredientes · ${s.receipts} compras',
              ].join(' · ')),
            ),
          ),
      ]),
    );
  }
}

class _SupplierDialog extends ConsumerStatefulWidget {
  const _SupplierDialog({this.supplier});
  final Supplier? supplier;

  @override
  ConsumerState<_SupplierDialog> createState() => _SupplierDialogState();
}

class _SupplierDialogState extends ConsumerState<_SupplierDialog> {
  final _form = GlobalKey<FormState>();
  Supplier? get _s => widget.supplier;
  late final _name = TextEditingController(text: _s?.name ?? '');
  late final _contact = TextEditingController(text: _s?.contactName ?? '');
  late final _phone = TextEditingController(text: _s?.phone ?? '');
  late final _email = TextEditingController(text: _s?.email ?? '');
  late final _notes = TextEditingController(text: _s?.notes ?? '');
  late bool _active = _s?.isActive ?? true;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _contact, _phone, _email, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(inventoryApiProvider).saveSupplier(_s?.id, {
        'name': _name.text.trim(),
        'contactName': _contact.text.trim(),
        'phone': _phone.text.trim(),
        'email': _email.text.trim(),
        'notes': _notes.text.trim(),
        'isActive': _active,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await confirm(context, title: 'Borrar proveedor', message: 'Se borra "${_s!.name}". Si ya tiene compras, desactívalo en vez de borrarlo.');
    if (!ok) return;
    try {
      await ref.read(inventoryApiProvider).removeSupplier(_s!.id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: Text(_s == null ? 'Nuevo proveedor' : _s!.name),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _form,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Nombre'), validator: (v) => (v ?? '').trim().length < 2 ? 'Escribe el nombre' : null),
            const SizedBox(height: 12),
            TextFormField(controller: _contact, decoration: const InputDecoration(labelText: 'Contacto (opcional)')),
            const SizedBox(height: 12),
            TextFormField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Teléfono (opcional)')),
            const SizedBox(height: 12),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email (opcional)'),
              validator: (v) => (v ?? '').trim().isEmpty || RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v!.trim()) ? null : 'Revisa el email',
            ),
            const SizedBox(height: 12),
            TextFormField(controller: _notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Notas (días de entrega, pedidos…)')),
            if (_s != null)
              SwitchListTile(contentPadding: EdgeInsets.zero, value: _active, onChanged: (v) => setState(() => _active = v), title: const Text('Activo')),
          ]),
        ),
      ),
      actions: [
        if (_s != null) TextButton(onPressed: _saving ? null : _delete, child: const Text('Borrar')),
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('Guardar')),
      ],
    );
  }
}

// ───────── Movimientos ─────────

class _MovementsTab extends ConsumerWidget {
  const _MovementsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(movementsProvider(null));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(movementsProvider(null))),
      data: (moves) => moves.isEmpty
          ? const EmptyState(icon: Icons.history_rounded, message: 'Aquí verás ventas, entradas, conteos y mermas.')
          : Padding(padding: const EdgeInsets.fromLTRB(24, 12, 24, 0), child: _MovesList(moves: moves, showItem: true)),
    );
  }
}

class _MovesList extends StatelessWidget {
  const _MovesList({required this.moves, required this.showItem});
  final List<StockMove> moves;
  final bool showItem;

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final when = DateFormat.yMd().add_jm();
    return ListView.builder(
      itemCount: moves.length,
      itemBuilder: (context, i) {
        final m = moves[i];
        final unit = unitLabels[m.unit] ?? m.unit;
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            switch (m.type) {
              'SALE' => Icons.restaurant_rounded,
              'RECEIPT' => Icons.local_shipping_rounded,
              'COUNT' => Icons.fact_check_rounded,
              'WASTE' => Icons.delete_sweep_rounded,
              _ => Icons.tune_rounded,
            },
            color: m.quantity < 0 ? t.danger : t.success,
          ),
          title: Text('${moveLabels[m.type] ?? m.type}${showItem ? ' · ${m.item}' : ''}'),
          subtitle: Text([when.format(m.createdAt), if (m.reason != null) m.reason!, if (m.employee != null) m.employee!].join(' · ')),
          trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${m.quantity > 0 ? '+' : ''}${qty(m.quantity)} $unit', style: TextStyle(fontWeight: FontWeight.w700, color: m.quantity < 0 ? t.danger : t.success)),
            Text(formatMoney(m.cost), style: Theme.of(context).textTheme.bodySmall),
          ]),
        );
      },
    );
  }
}
