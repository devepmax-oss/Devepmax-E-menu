import 'package:devepmax_ui/devepmax_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/ui/feedback.dart';
import '../../customers/data/customers_api.dart';
import '../../menu/widgets/common.dart';
import '../data/coupons_api.dart';

const _states = <String, (String, DmTone)>{
  'ACTIVE': ('Activo', DmTone.success),
  'SCHEDULED': ('Programado', DmTone.warning),
  'EXPIRED': ('Vencido', DmTone.neutral),
  'USED_UP': ('Agotado', DmTone.neutral),
  'PAUSED': ('Pausado', DmTone.neutral),
};

/// Cupones: códigos de descuento para la web y la caja.
class CouponsScreen extends ConsumerWidget {
  const CouponsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(couponsProvider);
    final text = Theme.of(context).textTheme;
    final t = BrandTokens.of(context);
    final date = DateFormat.yMd();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cupones'),
        actions: [
          AppBarAction(icon: Icons.add_rounded, label: 'Nuevo cupón', onPressed: () => _edit(context, ref, null)),
          const SizedBox(width: 16),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(couponsProvider)),
        data: (list) => list.isEmpty
            ? EmptyState(
                icon: Icons.confirmation_number_rounded,
                message: 'Todavía no hay cupones. Crea uno: el cliente lo escribe al pagar en la web o lo da en la caja.',
                action: FilledButton.icon(onPressed: () => _edit(context, ref, null), icon: const Icon(Icons.add_rounded), label: const Text('Nuevo cupón')),
              )
            : ListView.separated(
                padding: const EdgeInsets.all(24),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final c = list[i];
                  final (label, tone) = _states[c.state] ?? (c.state, DmTone.neutral);
                  final where = [if (c.appliesOnline) 'web', if (c.appliesInStore) 'restaurante'].join(' y ');
                  return Card(
                    child: ListTile(
                      leading: Icon(Icons.confirmation_number_rounded, color: c.state == 'ACTIVE' ? t.accentText : t.muted),
                      title: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        Text(c.code, style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1)),
                        DmPill(label, tone: tone),
                        if (c.customerName != null) DmPill('Solo ${c.customerName}', icon: Icons.person_rounded),
                      ]),
                      subtitle: Text([
                        c.rule,
                        if (c.name.isNotEmpty) c.name,
                        'en $where',
                        if (c.minOrderTotal != null) 'mínimo ${formatMoney(c.minOrderTotal!)}',
                        if (c.firstOrderOnly) 'solo primer pedido',
                        if (c.endsAt != null) 'hasta ${date.format(c.endsAt!.subtract(const Duration(seconds: 1)))}',
                      ].join(' · ')),
                      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text('${c.uses}${c.maxUses != null ? ' / ${c.maxUses}' : ''} usos', style: text.titleSmall),
                        if (c.saved > 0) Text('ahorro ${formatMoney(c.saved)}', style: text.bodySmall?.copyWith(color: t.muted)),
                      ]),
                      onTap: () => _edit(context, ref, c),
                    ),
                  );
                },
              ),
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, CouponView? coupon) async {
    final changed = await showDialog<bool>(context: context, builder: (_) => _CouponEditor(coupon: coupon));
    if (changed == true) ref.invalidate(couponsProvider);
  }
}

class _CouponEditor extends ConsumerStatefulWidget {
  const _CouponEditor({this.coupon});
  final CouponView? coupon;

  @override
  ConsumerState<_CouponEditor> createState() => _CouponEditorState();
}

class _CouponEditorState extends ConsumerState<_CouponEditor> {
  final _form = GlobalKey<FormState>();
  CouponView? get _c => widget.coupon;

  late final _code = TextEditingController(text: _c?.code ?? '');
  late final _name = TextEditingController(text: _c?.name ?? '');
  late final _value = TextEditingController(text: _num(_c?.value));
  late final _maxDiscount = TextEditingController(text: _num(_c?.maxDiscount));
  late final _minOrder = TextEditingController(text: _num(_c?.minOrderTotal));
  late final _maxUses = TextEditingController(text: _c?.maxUses?.toString() ?? '');
  late final _perCustomer = TextEditingController(text: _c?.maxUsesPerCustomer?.toString() ?? '');
  late final _phone = TextEditingController();
  late String _type = _c?.type ?? 'PERCENT';
  late bool _online = _c?.appliesOnline ?? true;
  late bool _inStore = _c?.appliesInStore ?? true;
  late bool _firstOrder = _c?.firstOrderOnly ?? false;
  late bool _active = _c?.isActive ?? true;
  late DateTime? _starts = _c?.startsAt;
  late DateTime? _ends = _c?.endsAt;
  late String? _customerId = _c?.customerId;
  late String? _customerName = _c?.customerName;
  bool _saving = false;

  static String _num(double? v) => v == null ? '' : (v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(2));

  @override
  void initState() {
    super.initState();
    if (_c == null) {
      ref.read(couponsApiProvider).suggestCode().then((code) {
        if (mounted && _code.text.isEmpty) _code.text = code;
      }).catchError((_) {});
    }
  }

  @override
  void dispose() {
    for (final c in [_code, _name, _value, _maxDiscount, _minOrder, _maxUses, _perCustomer, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  double? _parse(TextEditingController c) => c.text.trim().isEmpty ? null : double.tryParse(c.text.trim());
  int? _int(TextEditingController c) => c.text.trim().isEmpty ? null : int.tryParse(c.text.trim());

  Future<void> _pickDate(bool start) async {
    final now = DateTime.now();
    final current = start ? _starts : _ends?.subtract(const Duration(seconds: 1));
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _starts = DateTime(picked.year, picked.month, picked.day);
      } else {
        // Vale todo ese día: vence a la medianoche siguiente.
        _ends = DateTime(picked.year, picked.month, picked.day + 1);
      }
    });
  }

  Future<void> _findCustomer() async {
    try {
      final c = await ref.read(customersApiProvider).lookup(_phone.text);
      if (!mounted) return;
      if (c == null) {
        showError(context, 'No hay cliente con ese teléfono');
      } else {
        setState(() {
          _customerId = c.id;
          _customerName = c.name;
        });
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(couponsApiProvider).save(_c?.id, {
        'code': _code.text.trim(),
        'name': _name.text.trim(),
        'type': _type,
        'value': _type == 'FREE_DELIVERY' ? null : _parse(_value),
        'maxDiscount': _type == 'PERCENT' ? _parse(_maxDiscount) : null,
        'minOrderTotal': _parse(_minOrder),
        'appliesOnline': _online,
        'appliesInStore': _type == 'FREE_DELIVERY' ? false : _inStore,
        'firstOrderOnly': _firstOrder,
        'maxUses': _int(_maxUses),
        'maxUsesPerCustomer': _int(_perCustomer),
        'startsAt': _starts?.toUtc().toIso8601String(),
        'endsAt': _ends?.toUtc().toIso8601String(),
        'customerId': _customerId,
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
    final ok = await confirm(context, title: 'Borrar cupón', message: 'Se borra el cupón ${_c!.code}. Si ya se usó, mejor páusalo.');
    if (!ok) return;
    try {
      await ref.read(couponsApiProvider).remove(_c!.id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final date = DateFormat.yMd();
    final digits = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))];
    String? positive(String? v) => (double.tryParse((v ?? '').trim()) ?? 0) > 0 ? null : 'Escribe un número mayor que 0';
    String? optionalNumber(String? v) => (v ?? '').trim().isEmpty || double.tryParse(v!.trim()) != null ? null : 'Número inválido';
    String? optionalInt(String? v) => (v ?? '').trim().isEmpty || (int.tryParse(v!.trim()) ?? 0) >= 1 ? null : 'Número entero desde 1';

    return AlertDialog(
      scrollable: true,
      title: Text(_c == null ? 'Nuevo cupón' : 'Cupón ${_c!.code}'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _form,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _code,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9-]')), LengthLimitingTextInputFormatter(30)],
                  decoration: const InputDecoration(labelText: 'Código', hintText: 'VERANO10'),
                  validator: (v) => (v ?? '').trim().length < 3 ? 'De 3 a 30 letras o números' : null,
                ),
              ),
              IconButton(
                tooltip: 'Generar código',
                onPressed: () async {
                  final code = await ref.read(couponsApiProvider).suggestCode();
                  if (mounted) _code.text = code;
                },
                icon: const Icon(Icons.casino_rounded),
              ),
            ]),
            const SizedBox(height: 12),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Nombre que ve el cliente (opcional)', hintText: '10 % de bienvenida'),
            ),
            const SizedBox(height: 16),
            // Chips y no SegmentedButton: dentro de un AlertDialog no se puede usar LayoutBuilder.
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (value, label, icon) in const [
                ('PERCENT', 'Porcentaje', Icons.percent_rounded),
                ('AMOUNT', 'Monto fijo', Icons.attach_money_rounded),
                ('FREE_DELIVERY', 'Envío gratis', Icons.delivery_dining_rounded),
              ])
                ChoiceChip(
                  avatar: Icon(icon, size: 18),
                  label: Text(label),
                  selected: _type == value,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _type = value),
                ),
            ]),
            const SizedBox(height: 12),
            if (_type != 'FREE_DELIVERY')
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _value,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: digits,
                    decoration: InputDecoration(labelText: _type == 'PERCENT' ? 'Porcentaje' : 'Monto', suffixText: _type == 'PERCENT' ? '%' : null, prefixText: _type == 'AMOUNT' ? '\$ ' : null),
                    validator: positive,
                  ),
                ),
                if (_type == 'PERCENT') ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _maxDiscount,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: digits,
                      decoration: const InputDecoration(labelText: 'Tope (opcional)', prefixText: '\$ '),
                      validator: optionalNumber,
                    ),
                  ),
                ],
              ]),
            const SizedBox(height: 12),
            TextFormField(
              controller: _minOrder,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: digits,
              decoration: const InputDecoration(labelText: 'Compra mínima (opcional)', prefixText: '\$ '),
              validator: optionalNumber,
            ),
            const SizedBox(height: 16),
            Text('Dónde se usa', style: text.titleSmall),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _online,
              onChanged: (v) => setState(() => _online = v ?? true),
              title: const Text('Pedidos en la web'),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _type == 'FREE_DELIVERY' ? false : _inStore,
              onChanged: _type == 'FREE_DELIVERY' ? null : (v) => setState(() => _inStore = v ?? true),
              title: const Text('En el restaurante (caja)'),
            ),
            const SizedBox(height: 8),
            Text('Límites', style: text.titleSmall),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _maxUses,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Usos en total', hintText: 'Sin límite'),
                  validator: optionalInt,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _perCustomer,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Usos por cliente', hintText: 'Sin límite'),
                  validator: optionalInt,
                ),
              ),
            ]),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _firstOrder,
              onChanged: (v) => setState(() => _firstOrder = v),
              title: const Text('Solo para el primer pedido'),
            ),
            const SizedBox(height: 4),
            Text('Vigencia', style: text.titleSmall),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              InputChip(
                avatar: const Icon(Icons.event_rounded, size: 18),
                label: Text(_starts == null ? 'Desde: ya' : 'Desde ${date.format(_starts!)}'),
                onPressed: () => _pickDate(true),
                onDeleted: _starts == null ? null : () => setState(() => _starts = null),
              ),
              InputChip(
                avatar: const Icon(Icons.event_busy_rounded, size: 18),
                label: Text(_ends == null ? 'Hasta: sin fin' : 'Hasta ${date.format(_ends!.subtract(const Duration(seconds: 1)))}'),
                onPressed: () => _pickDate(false),
                onDeleted: _ends == null ? null : () => setState(() => _ends = null),
              ),
            ]),
            const SizedBox(height: 16),
            Text('Cupón personal (opcional)', style: text.titleSmall),
            const SizedBox(height: 8),
            if (_customerId != null)
              InputChip(
                avatar: const Icon(Icons.person_rounded, size: 18),
                label: Text('Solo ${_customerName ?? 'este cliente'}'),
                onDeleted: () => setState(() {
                  _customerId = null;
                  _customerName = null;
                }),
              )
            else
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Teléfono del cliente', hintText: 'Para todos si lo dejas vacío'),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(onPressed: _findCustomer, child: const Text('Buscar')),
              ]),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _active,
              onChanged: (v) => setState(() => _active = v),
              title: const Text('Activo'),
              subtitle: const Text('Apágalo para pausar el cupón sin borrarlo'),
            ),
          ]),
        ),
      ),
      actions: [
        if (_c != null) TextButton(onPressed: _saving ? null : _delete, child: const Text('Borrar')),
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('Guardar')),
      ],
    );
  }
}
