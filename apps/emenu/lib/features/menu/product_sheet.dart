import 'package:devepmax_ui/devepmax_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/widgets.dart';
import 'cart.dart';
import 'menu_data.dart';
import '../../core/i18n.dart';

/// Detalle del plato: foto grande, opciones, nota para la cocina y cantidad.
Future<bool?> showProductSheet(BuildContext context, MenuProduct product, List<Promotion> promotions) =>
    showDialog<bool>(context: context, builder: (_) => _ProductSheet(product: product, promotions: promotions));

class _ProductSheet extends ConsumerStatefulWidget {
  const _ProductSheet({required this.product, required this.promotions});
  final MenuProduct product;
  final List<Promotion> promotions;

  @override
  ConsumerState<_ProductSheet> createState() => _ProductSheetState();
}

class _ProductSheetState extends ConsumerState<_ProductSheet> {
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

  List<MenuOption> get _chosen => [
        for (final g in widget.product.groups)
          for (final o in g.options)
            if (_selected[g.id]!.contains(o.id)) o,
      ];

  bool _groupOk(ModifierGroup g) => _selected[g.id]!.length >= g.minSelect;
  bool get _valid => widget.product.groups.every(_groupOk);
  double get _unit => widget.product.price + _chosen.fold<double>(0, (s, o) => s + o.price);

  void _toggle(ModifierGroup g, MenuOption o) {
    final current = _selected[g.id]!;
    setState(() {
      if (g.single) {
        _selected[g.id] = current.contains(o.id) && g.minSelect == 0 ? [] : [o.id];
      } else if (current.contains(o.id)) {
        _selected[g.id] = [...current]..remove(o.id);
      } else if (g.max == null || current.length < g.max!) {
        _selected[g.id] = [...current, o.id];
      }
    });
  }

  void _add() {
    if (!_valid) {
      setState(() => _showErrors = true);
      return;
    }
    ref.read(cartProvider.notifier).add(widget.product, _chosen, _quantity, _notes.text);
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final text = Theme.of(context).textTheme;
    final p = widget.product;
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 900;

    final photo = Stack(fit: StackFit.expand, children: [
      ProductPhoto(url: p.imageUrl, iconSize: 72),
      if (widget.promotions.isNotEmpty)
        Positioned(
          left: 16,
          top: 16,
          child: Wrap(spacing: 6, children: [
            for (final promo in widget.promotions) DmPill(promo.badge, tone: DmTone.accent, icon: Icons.local_offer_rounded),
          ]),
        ),
    ]);

    final details = ListView(padding: const EdgeInsets.fromLTRB(28, 24, 28, 16), children: [
      Text(p.name, style: text.headlineMedium),
      const SizedBox(height: 6),
      Text(formatMoney(p.price), style: text.titleLarge?.copyWith(color: t.accentText)),
      if (p.description != null) ...[
        const SizedBox(height: 12),
        Text(p.description!, style: text.bodyLarge?.copyWith(color: t.muted, height: 1.4)),
      ],
      if (p.allergens.isNotEmpty || p.prepTimeMinutes != null) ...[
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 6, children: [
          for (final a in p.allergens) DmPill(a, tone: DmTone.warning, icon: Icons.info_outline_rounded),
          if (p.prepTimeMinutes != null) DmPill('${p.prepTimeMinutes} min', icon: Icons.schedule_rounded),
        ]),
      ],
      for (final promo in widget.promotions)
        if (promo.description != null && promo.description!.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text('${promo.name}: ${promo.description}', style: TextStyle(color: t.accentText, fontWeight: FontWeight.w600)),
          ),
      for (final g in p.groups) ...[
        const SizedBox(height: 24),
        Row(children: [
          Expanded(child: Text(g.name, style: text.titleLarge)),
          DmPill(
            g.rule(context.lang),
            tone: g.required ? (_showErrors && !_groupOk(g) ? DmTone.danger : DmTone.primary) : DmTone.neutral,
          ),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (final o in g.options)
            _OptionTile(
              option: o,
              selected: _selected[g.id]!.contains(o.id),
              single: g.single,
              disabled: !o.isAvailable ||
                  (!g.single && !_selected[g.id]!.contains(o.id) && g.max != null && _selected[g.id]!.length >= g.max!),
              onTap: () => _toggle(g, o),
            ),
        ]),
      ],
      const SizedBox(height: 24),
      Text(context.tr('¿Alguna indicación para la cocina?', 'Any notes for the kitchen?'), style: text.titleMedium),
      const SizedBox(height: 8),
      TextField(
        controller: _notes,
        maxLength: 200,
        maxLines: 2,
        minLines: 1,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: context.tr('Sin cebolla, término medio, aparte la salsa…', 'No onion, medium, sauce on the side…'), border: const OutlineInputBorder()),
      ),
    ]);

    final footer = Container(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
      decoration: BoxDecoration(color: t.surface, border: Border(top: BorderSide(color: t.line))),
      child: Row(children: [
        QuantityStepper(value: _quantity, onChanged: (v) => setState(() => _quantity = v)),
        const SizedBox(width: 16),
        Expanded(
          child: FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(60),
              textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            onPressed: p.isAvailable ? _add : null,
            child: Text(p.isAvailable ? context.tr('Agregar · ${formatMoney(_unit * _quantity)}', 'Add · ${formatMoney(_unit * _quantity)}') : context.tr('Agotado por hoy', 'Sold out today')),
          ),
        ),
      ]),
    );

    return Dialog(
      insetPadding: const EdgeInsets.all(28),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: wide ? 1000 : 620, maxHeight: size.height * 0.9),
        child: Stack(children: [
          wide
              ? Row(children: [
                  Expanded(flex: 5, child: photo),
                  Expanded(flex: 6, child: Column(children: [Expanded(child: details), footer])),
                ])
              : Column(children: [
                  SizedBox(height: 220, width: double.infinity, child: photo),
                  Expanded(child: details),
                  footer,
                ]),
          Positioned(
            right: 12,
            top: 12,
            child: Material(
              color: Colors.black45,
              shape: const CircleBorder(),
              child: IconButton(
                tooltip: context.tr('Cerrar', 'Close'),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({required this.option, required this.selected, required this.single, required this.disabled, required this.onTap});
  final MenuOption option;
  final bool selected;
  final bool single;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final fg = disabled && !selected ? t.faint : (selected ? t.primaryText : t.text);
    final icon = single
        ? (selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded)
        : (selected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded);
    return Material(
      color: selected ? t.primarySoft : t.surface2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: selected ? t.primary : t.line, width: 2),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: disabled && !selected ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: fg, size: 22),
            const SizedBox(width: 8),
            Text(option.name, style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 15)),
            if (!option.isAvailable) ...[
              const SizedBox(width: 6),
              Text(context.tr('· agotado', '· sold out'), style: TextStyle(color: t.faint, fontSize: 13)),
            ] else if (option.price != 0) ...[
              const SizedBox(width: 6),
              Text('${option.price > 0 ? '+' : '−'}${formatMoney(option.price.abs())}',
                  style: TextStyle(color: fg.withValues(alpha: 0.8), fontSize: 13.5)),
            ],
          ]),
        ),
      ),
    );
  }
}
