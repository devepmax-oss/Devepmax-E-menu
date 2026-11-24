import 'package:devepmax_ui/devepmax_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/feedback.dart';
import '../../billing/data/billing_api.dart';
import '../../billing/screens/pay_dialog.dart';
import '../../menu/widgets/common.dart';
import '../../tables/data/tables_api.dart';
import '../../tables/data/tables_models.dart';
import '../data/pos_data.dart';

/// Nueva orden desde la caja: comer aquí (mostrador), para llevar, a una mesa o para recoger.
class NewOrderScreen extends ConsumerStatefulWidget {
  const NewOrderScreen({super.key, this.tableId});

  /// Abrir con la mesa ya elegida (desde el plano de mesas).
  final String? tableId;

  @override
  ConsumerState<NewOrderScreen> createState() => _NewOrderScreenState();
}

class _NewOrderScreenState extends ConsumerState<NewOrderScreen> {
  String? _category;
  String _query = '';
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(posOrderProvider.notifier).start(tableId: widget.tableId));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _pick(PosProduct p) async {
    if (!p.isAvailable) return;
    if (p.quickAdd) {
      HapticFeedback.selectionClick();
      ref.read(posOrderProvider.notifier).add(p, const []);
      return;
    }
    await showDialog<void>(context: context, builder: (_) => _OptionsDialog(product: p));
  }

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final menu = ref.watch(posMenuProvider);
    final order = ref.watch(posOrderProvider);
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 900;

    final menuPane = menu.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(posMenuProvider)),
      data: (categories) {
        final q = _query.trim().toLowerCase();
        final products = <PosProduct>[
          for (final c in categories)
            if (q.isNotEmpty || _category == null || _category == c.id)
              for (final p in c.products)
                if (q.isEmpty || p.name.toLowerCase().contains(q) || (p.sku ?? '').toLowerCase() == q) p,
        ];
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: EdgeInsets.fromLTRB(pagePadding(context), 8, pagePadding(context), 8),
            child: TextField(
              controller: _search,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Buscar producto',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Borrar',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => setState(() {
                          _search.clear();
                          _query = '';
                        }),
                      ),
              ),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: pagePadding(context)),
              children: [
                for (final (id, name) in [(null, 'Todo'), for (final c in categories) (c.id, c.name)])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(name),
                      selected: _category == id && _query.isEmpty,
                      showCheckmark: false,
                      onSelected: (_) => setState(() {
                        _category = id;
                        _search.clear();
                        _query = '';
                      }),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: products.isEmpty
                ? const EmptyState(icon: Icons.search_off_rounded, message: 'No hay productos con ese nombre.')
                : GridView.builder(
                    padding: EdgeInsets.fromLTRB(pagePadding(context), 4, pagePadding(context), 24),
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: width < 600 ? 170 : 200,
                      mainAxisExtent: 150,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    itemCount: products.length,
                    itemBuilder: (context, i) {
                      final p = products[i];
                      final inOrder = order.lines.where((l) => l.product.id == p.id).fold(0, (s, l) => s + l.quantity);
                      return _ProductTile(product: p, inOrder: inOrder, onTap: () => _pick(p));
                    },
                  ),
          ),
        ]);
      },
    );

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        title: const Text('Nueva orden'),
        actions: [
          if (order.lines.isNotEmpty)
            AppBarAction(
              icon: Icons.delete_sweep_rounded,
              label: 'Vaciar',
              onPressed: () async {
                final ok = await confirm(context, title: 'Vaciar la orden', message: 'Se quitan todos los productos.', confirmLabel: 'Vaciar');
                if (ok) ref.read(posOrderProvider.notifier).clear();
              },
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: wide
          ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: menuPane),
              VerticalDivider(width: 1, color: t.line),
              SizedBox(width: width >= 1400 ? 440 : 380, child: const PosOrderPanel()),
            ])
          : Column(children: [
              Expanded(child: menuPane),
              if (order.lines.isNotEmpty)
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56), textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => Scaffold(appBar: AppBar(title: const Text('La orden')), body: const PosOrderPanel(closeOnSend: true)),
                      )),
                      icon: const Icon(Icons.receipt_long_rounded),
                      label: Text('Ver orden · ${order.count} · ${formatMoney(order.estimate)}'),
                    ),
                  ),
                ),
            ]),
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.product, required this.inOrder, required this.onTap});
  final PosProduct product;
  final int inOrder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final available = product.isAvailable;
    return Material(
      color: inOrder > 0 ? t.primarySoft : t.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: inOrder > 0 ? t.primary : t.line, width: inOrder > 0 ? 2 : 1),
      ),
      child: InkWell(
        onTap: available ? onTap : null,
        child: Opacity(
          opacity: available ? 1 : 0.45,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: Stack(fit: StackFit.expand, children: [
                ProductImage(url: product.imageUrl),
                if (inOrder > 0)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: CircleAvatar(
                      radius: 14,
                      backgroundColor: t.primary,
                      child: Text('$inOrder', style: TextStyle(color: t.onPrimary, fontWeight: FontWeight.w800, fontSize: 13)),
                    ),
                  ),
                if (!available) const Center(child: DmPill('Agotado', tone: DmTone.danger)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                Text(
                  product.groups.isEmpty ? formatMoney(product.price) : '${formatMoney(product.price)} · opciones',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: t.accentText, fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// ───────────────────────── Opciones del producto ─────────────────────────

class _OptionsDialog extends ConsumerStatefulWidget {
  const _OptionsDialog({required this.product});
  final PosProduct product;

  @override
  ConsumerState<_OptionsDialog> createState() => _OptionsDialogState();
}

class _OptionsDialogState extends ConsumerState<_OptionsDialog> {
  late final Map<String, List<String>> _selected = {
    for (final g in widget.product.groups)
      g.id: g.options.where((o) => o.isDefault && o.isAvailable).map((o) => o.id).take(g.max ?? 99).toList(),
  };
  final _notes = TextEditingController();
  int _quantity = 1;
  bool _showErrors = false;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  List<PosOption> get _chosen => [
        for (final g in widget.product.groups)
          for (final o in g.options)
            if (_selected[g.id]!.contains(o.id)) o,
      ];
  bool _ok(PosGroup g) => _selected[g.id]!.length >= g.minSelect;
  double get _unit => widget.product.price + _chosen.fold<double>(0, (s, o) => s + o.price);

  void _toggle(PosGroup g, PosOption o) => setState(() {
        final current = _selected[g.id]!;
        if (g.single) {
          _selected[g.id] = current.contains(o.id) && g.minSelect == 0 ? [] : [o.id];
        } else if (current.contains(o.id)) {
          _selected[g.id] = [...current]..remove(o.id);
        } else if (g.max == null || current.length < g.max!) {
          _selected[g.id] = [...current, o.id];
        }
      });

  void _add() {
    if (!widget.product.groups.every(_ok)) return setState(() => _showErrors = true);
    ref.read(posOrderProvider.notifier).add(widget.product, _chosen, quantity: _quantity, notes: _notes.text);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final text = Theme.of(context).textTheme;
    final p = widget.product;
    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 620, maxHeight: MediaQuery.sizeOf(context).height * 0.9),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 8, 0),
            child: Row(children: [
              Expanded(child: Text(p.name, style: text.headlineSmall)),
              IconButton(tooltip: 'Cerrar', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
            ]),
          ),
          Flexible(
            child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(24, 4, 24, 12), children: [
              for (final g in p.groups) ...[
                const SizedBox(height: 14),
                Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text(g.name, style: text.titleMedium),
                  DmPill(g.rule, tone: g.required ? (_showErrors && !_ok(g) ? DmTone.danger : DmTone.primary) : DmTone.neutral),
                ]),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final o in g.options)
                    FilterChip(
                      showCheckmark: !g.single,
                      label: Text([
                        o.name,
                        if (!o.isAvailable) 'agotado' else if (o.price != 0) '${o.price > 0 ? '+' : '−'}${formatMoney(o.price.abs())}',
                      ].join(' · ')),
                      selected: _selected[g.id]!.contains(o.id),
                      onSelected: !o.isAvailable ? null : (_) => _toggle(g, o),
                    ),
                ]),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: _notes,
                maxLength: 200,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Nota para la cocina (opcional)', hintText: 'Sin cebolla, bien cocido…'),
              ),
            ]),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: t.line))),
            child: Row(children: [
              _Stepper(value: _quantity, onChanged: (v) => setState(() => _quantity = v.clamp(1, 99))),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                  onPressed: _add,
                  child: Text('Agregar · ${formatMoney(_unit * _quantity)}', maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.value, required this.onChanged, this.min = 1});
  final int value;
  final int min;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    return Container(
      decoration: BoxDecoration(color: t.surface2, borderRadius: BorderRadius.circular(999), border: Border.all(color: t.line)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          tooltip: value <= 1 && min == 0 ? 'Quitar' : 'Uno menos',
          visualDensity: VisualDensity.compact,
          onPressed: value <= min ? null : () => onChanged(value - 1),
          icon: Icon(value <= 1 && min == 0 ? Icons.delete_outline_rounded : Icons.remove_rounded),
        ),
        SizedBox(width: 26, child: Text('$value', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
        IconButton(tooltip: 'Uno más', visualDensity: VisualDensity.compact, onPressed: value >= 99 ? null : () => onChanged(value + 1), icon: const Icon(Icons.add_rounded)),
      ]),
    );
  }
}

// ───────────────────────── La orden ─────────────────────────

/// Tipo de orden, mesa o cliente, lo pedido, totales reales y los botones para enviar y cobrar.
class PosOrderPanel extends ConsumerStatefulWidget {
  const PosOrderPanel({super.key, this.closeOnSend = false});

  /// En el teléfono el panel es una página aparte: al enviar, vuelve al menú.
  final bool closeOnSend;

  @override
  ConsumerState<PosOrderPanel> createState() => _PosOrderPanelState();
}

class _PosOrderPanelState extends ConsumerState<PosOrderPanel> {
  bool _busy = false;
  late final _name = TextEditingController(text: ref.read(posOrderProvider).customerName);
  late final _phone = TextEditingController(text: ref.read(posOrderProvider).customerPhone);

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _editNotes(PosLine line) async {
    final controller = TextEditingController(text: line.notes ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(line.product.name),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 200,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Nota para la cocina'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Guardar')),
        ],
      ),
    );
    controller.dispose();
    if (result != null) ref.read(posOrderProvider.notifier).setNotes(line.key, result);
  }

  Future<void> _send({required bool charge}) async {
    setState(() => _busy = true);
    // En el teléfono este panel se cierra al enviar: lo que sigue (cobro y avisos) usa la
    // pantalla de abajo, que sigue abierta.
    final navigator = Navigator.of(context);
    final host = widget.closeOnSend ? navigator.context : context;
    final api = ref.read(billingApiProvider);
    final orders = ref.read(posOrderProvider.notifier);
    try {
      final sent = await orders.send();
      _name.clear();
      _phone.clear();
      ref.invalidate(openBillsProvider);
      if (widget.closeOnSend && navigator.mounted) navigator.pop();
      if (!charge) {
        if (host.mounted) showSuccess(host, 'Orden #${sent.number} enviada a cocina');
        return;
      }
      final bill = await api.get(sent.billId);
      if (!host.mounted) return;
      final result = await showPayDialog(host, bill);
      if (!host.mounted) return;
      if (result != null && result.change > 0.004) await showChangeDialog(host, result.change);
      if (!host.mounted) return;
      showSuccess(
        host,
        result?.bill.status == 'PAID' ? 'Orden #${sent.number} pagada y en cocina' : 'Orden #${sent.number} en cocina · la cuenta queda en Caja',
      );
    } catch (error) {
      if (host.mounted) showError(host, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final text = Theme.of(context).textTheme;
    final order = ref.watch(posOrderProvider);
    final quote = ref.watch(posQuoteProvider);
    final controller = ref.read(posOrderProvider.notifier);
    final tables = [for (final a in ref.watch(floorProvider).value ?? const <AreaView>[]) for (final tb in a.tables) (area: a.name, table: tb)];
    final q = quote.value;
    final problem = order.problem;

    Widget total(String label, double value, {bool bold = false, Color? color}) => Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(children: [
            Expanded(child: Text(label, style: (bold ? text.titleLarge : text.bodyLarge)?.copyWith(color: color))),
            Text(formatMoney(value), style: (bold ? text.headlineSmall : text.bodyLarge)?.copyWith(color: color)),
          ]),
        );

    final atTable = order.mode == PosMode.table;
    final totalLabel = formatMoney(q?.total ?? order.estimate);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 12), children: [
          FitSegmented<PosMode>(SegmentedButton<PosMode>(
            segments: [for (final m in PosMode.values) ButtonSegment(value: m, label: Text(m.label))],
            selected: {order.mode},
            showSelectedIcon: false,
            onSelectionChanged: (s) => controller.setMode(s.first),
          )),
          const SizedBox(height: 12),
          if (atTable)
            DropdownButtonFormField<String>(
              key: ValueKey('table-${order.tableId}'),
              isExpanded: true,
              initialValue: tables.any((e) => e.table.id == order.tableId) ? order.tableId : null,
              decoration: const InputDecoration(labelText: 'Mesa'),
              items: [
                for (final e in tables)
                  DropdownMenuItem(
                    value: e.table.id,
                    child: Text(
                      'Mesa ${e.table.label} · ${e.area}${e.table.session != null ? ' · ocupada' : ''}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: controller.setTable,
            )
          else ...[
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              onChanged: (v) => controller.setCustomer(name: v),
              decoration: InputDecoration(labelText: order.mode == PosMode.pickup ? 'Nombre de quien recoge' : 'Nombre (opcional, para llamarlo)'),
            ),
            if (order.mode != PosMode.here) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                onChanged: (v) => controller.setCustomer(phone: v),
                decoration: const InputDecoration(labelText: 'Teléfono (opcional)'),
              ),
            ],
          ],
          const SizedBox(height: 14),
          if (order.lines.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Column(children: [
                Icon(Icons.touch_app_rounded, size: 40, color: t.faint),
                const SizedBox(height: 8),
                Text('Toca un producto para agregarlo.', style: TextStyle(color: t.muted), textAlign: TextAlign.center),
              ]),
            ),
          for (final l in order.lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _Stepper(value: l.quantity, min: 0, onChanged: (v) => controller.setQuantity(l.key, v)),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => _editNotes(l),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(l.product.name, style: text.titleSmall),
                        if (l.options.isNotEmpty) Text(l.options.map((o) => o.name).join(' · '), style: TextStyle(color: t.muted, fontSize: 13)),
                        Text(l.notes != null ? '“${l.notes}”' : 'Agregar nota',
                            style: TextStyle(color: l.notes != null ? t.muted : t.accentText, fontSize: 12.5, fontStyle: l.notes != null ? FontStyle.italic : null)),
                      ]),
                    ),
                  ),
                ),
                Padding(padding: const EdgeInsets.only(top: 6), child: Text(formatMoney(l.total), style: text.titleSmall)),
              ]),
            ),
          if (order.lines.isNotEmpty) ...[
            Divider(height: 24, color: t.line),
            if (quote.hasError)
              Text(quote.error.toString(), style: TextStyle(color: t.danger))
            else if (q == null)
              const Padding(padding: EdgeInsets.all(8), child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))))
            else ...[
              total('Subtotal', q.subtotal),
              for (final p in q.promotions) total(p.name, -p.amount, color: t.success),
              total('Impuestos', q.taxTotal),
              total('Total', q.total, bold: true),
            ],
          ],
        ]),
      ),
      Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(color: t.surface, border: Border(top: BorderSide(color: t.line))),
        child: SafeArea(
          top: false,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            if (problem != null && order.lines.isNotEmpty)
              Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(problem, textAlign: TextAlign.center, style: TextStyle(color: t.muted))),
            if (atTable)
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56), textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                onPressed: _busy || problem != null ? null : () => _send(charge: false),
                icon: const Icon(Icons.send_rounded),
                label: const Text('Enviar a cocina'),
              )
            else ...[
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56), textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                onPressed: _busy || problem != null ? null : () => _send(charge: true),
                icon: const Icon(Icons.point_of_sale_rounded),
                label: Text('Cobrar $totalLabel', maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _busy || problem != null ? null : () => _send(charge: false),
                icon: const Icon(Icons.send_rounded),
                label: const Text('Enviar a cocina sin cobrar'),
              ),
            ],
          ]),
        ),
      ),
    ]);
  }
}

/// Atajo para abrir la pantalla con la mesa elegida.
String newOrderPath({String? tableId}) => tableId == null ? '/pos' : '/pos?table=$tableId';

