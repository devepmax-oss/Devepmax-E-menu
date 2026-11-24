import 'package:collection/collection.dart';
import 'package:devepmax_ui/devepmax_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/widgets.dart';
import '../table/service_actions.dart';
import '../table/table_data.dart';
import 'cart.dart';
import 'cart_panel.dart';
import 'menu_data.dart';
import 'product_sheet.dart';

/// El menú de la mesa. En tablet horizontal: categorías a la izquierda, platos al centro y el
/// pedido a la derecha. En pantallas angostas, categorías arriba y el pedido en una barra abajo.
class MenuScreen extends ConsumerStatefulWidget {
  const MenuScreen({super.key});

  @override
  ConsumerState<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends ConsumerState<MenuScreen> {
  String? _categoryId;
  final _grid = ScrollController();

  @override
  void dispose() {
    _grid.dispose();
    super.dispose();
  }

  void _select(String id) {
    setState(() => _categoryId = id);
    if (_grid.hasClients) _grid.jumpTo(0);
  }

  Future<void> _open(MenuCategory category, MenuProduct product, MenuData menu) async {
    final added = await showProductSheet(context, product, menu.promotionsFor(category, product));
    if (added == true && mounted) showMessage(context, '${product.name} agregado a tu pedido');
  }

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final menu = ref.watch(menuProvider);
    final wide = MediaQuery.sizeOf(context).width >= 1000;

    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: menu.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _Problem(message: '$error', onRetry: () => ref.read(menuProvider.notifier).reload()),
          data: (data) {
            if (data.categories.isEmpty) {
              return const _Problem(message: 'El menú todavía no tiene platos para mesa.');
            }
            final category = data.categories.firstWhereOrNull((c) => c.id == _categoryId) ?? data.categories.first;
            final grid = _ProductGrid(
              controller: _grid,
              category: category,
              menu: data,
              onOpen: (p) => _open(category, p, data),
              wide: wide,
            );
            if (wide) {
              return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _CategoryRail(categories: data.categories, selected: category.id, onSelect: _select),
                Expanded(child: grid),
                Container(
                  width: 380,
                  decoration: BoxDecoration(color: t.surface, border: Border(left: BorderSide(color: t.line))),
                  child: const CartPanel(),
                ),
              ]);
            }
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _TopBar(categories: data.categories, selected: category.id, onSelect: _select),
              Expanded(child: grid),
              const _CartBar(),
            ]);
          },
        ),
      ),
    );
  }
}

// ───────────────────────── Categorías ─────────────────────────

class _CategoryRail extends ConsumerWidget {
  const _CategoryRail({required this.categories, required this.selected, required this.onSelect});
  final List<MenuCategory> categories;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = BrandTokens.of(context);
    final table = ref.watch(tableProvider).value;
    return Container(
      width: 250,
      decoration: BoxDecoration(color: t.rail, border: Border(right: BorderSide(color: t.line))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Padding(padding: EdgeInsets.fromLTRB(20, 24, 20, 8), child: Center(child: StaffLogo(height: 64))),
        if (table?.label != null) Center(child: DmPill('Mesa ${table!.label}', tone: DmTone.accent, icon: Icons.table_restaurant_rounded)),
        const SizedBox(height: 16),
        Expanded(
          child: ListView(padding: const EdgeInsets.symmetric(horizontal: 12), children: [
            for (final c in categories)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _CategoryTile(category: c, selected: c.id == selected, onTap: () => onSelect(c.id)),
              ),
          ]),
        ),
        const Padding(padding: EdgeInsets.fromLTRB(12, 8, 12, 16), child: ServiceActions()),
      ]),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category, required this.selected, required this.onTap});
  final MenuCategory category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    return Material(
      color: selected ? t.primary : Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 44,
                height: 44,
                child: ProductPhoto(url: category.imageUrl ?? category.products.firstOrNull?.imageUrl, iconSize: 20),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                category.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: selected ? t.onPrimary : t.text,
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _TopBar extends ConsumerWidget {
  const _TopBar({required this.categories, required this.selected, required this.onSelect});
  final List<MenuCategory> categories;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = BrandTokens.of(context);
    final table = ref.watch(tableProvider).value;
    return Container(
      color: t.rail,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const StaffLogo(height: 40),
          const SizedBox(width: 12),
          if (table?.label != null) DmPill('Mesa ${table!.label}', tone: DmTone.accent),
          const SizedBox(width: 12),
          const Expanded(child: ServiceActions(vertical: false, compact: true)),
        ]),
        const SizedBox(height: 10),
        SizedBox(
          height: 44,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final c in categories)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(c.name),
                  selected: c.id == selected,
                  showCheckmark: false,
                  onSelected: (_) => onSelect(c.id),
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}

// ───────────────────────── Platos ─────────────────────────

class _ProductGrid extends StatelessWidget {
  const _ProductGrid({required this.controller, required this.category, required this.menu, required this.onOpen, required this.wide});
  final ScrollController controller;
  final MenuCategory category;
  final MenuData menu;
  final ValueChanged<MenuProduct> onOpen;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final t = BrandTokens.of(context);
    return CustomScrollView(controller: controller, slivers: [
      SliverPadding(
        padding: EdgeInsets.fromLTRB(wide ? 28 : 16, wide ? 28 : 16, wide ? 28 : 16, 8),
        sliver: SliverToBoxAdapter(
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(child: Text(category.name, style: text.displaySmall)),
            Text('${category.products.length} ${category.products.length == 1 ? 'plato' : 'platos'}', style: TextStyle(color: t.muted)),
          ]),
        ),
      ),
      SliverPadding(
        padding: EdgeInsets.fromLTRB(wide ? 28 : 16, 12, wide ? 28 : 16, 28),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 290,
            mainAxisSpacing: 18,
            crossAxisSpacing: 18,
            childAspectRatio: 0.74,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, i) {
              final p = category.products[i];
              return _ProductCard(product: p, promotions: menu.promotionsFor(category, p), onTap: () => onOpen(p));
            },
            childCount: category.products.length,
          ),
        ),
      ),
    ]);
  }
}

class _ProductCard extends ConsumerWidget {
  const _ProductCard({required this.product, required this.promotions, required this.onTap});
  final MenuProduct product;
  final List<Promotion> promotions;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = BrandTokens.of(context);
    final text = Theme.of(context).textTheme;
    final inCart = ref.watch(cartProvider).where((l) => l.product.id == product.id).fold<int>(0, (s, l) => s + l.quantity);
    final soldOut = !product.isAvailable;

    return Material(
      color: t.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: inCart > 0 ? t.primary : t.line, width: inCart > 0 ? 2 : 1),
      ),
      child: InkWell(
        onTap: soldOut ? null : onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            flex: 11,
            child: Stack(fit: StackFit.expand, children: [
              ColorFiltered(
                colorFilter: soldOut
                    ? const ColorFilter.matrix([0.33, 0.33, 0.33, 0, 0, 0.33, 0.33, 0.33, 0, 0, 0.33, 0.33, 0.33, 0, 0, 0, 0, 0, 1, 0])
                    : const ColorFilter.mode(Colors.transparent, BlendMode.dst),
                child: ProductPhoto(url: product.imageUrl),
              ),
              if (promotions.isNotEmpty && !soldOut)
                Positioned(left: 10, top: 10, child: DmPill(promotions.first.badge, tone: DmTone.accent)),
              if (soldOut)
                Container(
                  color: Colors.black45,
                  alignment: Alignment.center,
                  child: const DmPill('Agotado', tone: DmTone.danger),
                ),
              if (inCart > 0)
                Positioned(
                  right: 10,
                  top: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: t.primary, borderRadius: BorderRadius.circular(99)),
                    child: Text('$inCart en tu pedido',
                        style: TextStyle(color: t.onPrimary, fontWeight: FontWeight.w800, fontSize: 12.5)),
                  ),
                ),
            ]),
          ),
          Expanded(
            flex: 9,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(product.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.titleMedium),
                const SizedBox(height: 4),
                if (product.description != null)
                  Expanded(
                    child: Text(product.description!,
                        maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.muted, fontSize: 13.5)),
                  )
                else
                  const Spacer(),
                Row(children: [
                  Expanded(
                    child: Text(formatMoney(product.price),
                        style: text.titleLarge?.copyWith(color: soldOut ? t.faint : t.accentText)),
                  ),
                  if (!soldOut)
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: t.primary, shape: BoxShape.circle),
                      child: Icon(Icons.add_rounded, color: t.onPrimary),
                    ),
                ]),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

// ───────────────────────── Pantalla angosta ─────────────────────────

class _CartBar extends ConsumerWidget {
  const _CartBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = BrandTokens.of(context);
    final lines = ref.watch(cartProvider);
    final count = lines.fold<int>(0, (s, l) => s + l.quantity);
    final total = lines.fold<double>(0, (s, l) => s + l.total);
    final hasOrders = ref.watch(tableProvider).value?.session?.orders.isNotEmpty ?? false;
    if (count == 0 && !hasOrders) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: BoxDecoration(color: t.surface, border: Border(top: BorderSide(color: t.line))),
      child: FilledButton(
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(58)),
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: t.surface,
          builder: (context) => SizedBox(height: MediaQuery.sizeOf(context).height * 0.85, child: const CartPanel(inSheet: true)),
        ),
        child: Text(
          count > 0 ? 'Ver tu pedido ($count) · ${formatMoney(total)}' : 'Tus pedidos y la cuenta',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _Problem extends StatelessWidget {
  const _Problem({required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.cloud_off_rounded, size: 56, color: t.faint),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
        if (onRetry != null) ...[
          const SizedBox(height: 16),
          FilledButton(onPressed: onRetry, child: const Text('Reintentar')),
        ],
      ]),
    );
  }
}
