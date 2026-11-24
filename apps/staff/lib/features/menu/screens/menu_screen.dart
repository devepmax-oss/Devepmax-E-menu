import 'package:devepmax_ui/devepmax_ui.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/feedback.dart';
import '../../promotions/data/promotions_api.dart';
import '../data/menu_models.dart';
import '../menu_controller.dart';
import '../widgets/common.dart';
import 'category_dialog.dart';
import 'product_editor_screen.dart';

class MenuScreen extends ConsumerStatefulWidget {
  const MenuScreen({super.key});

  @override
  ConsumerState<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends ConsumerState<MenuScreen> {
  String? _selectedCategoryId;

  AdminMenuController get _controller => ref.read(adminMenuProvider.notifier);

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final menu = ref.watch(adminMenuProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Menú'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              ref.invalidate(promotionsProvider);
              _run(_controller.reload);
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: menu.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorView(error: error, onRetry: () => ref.invalidate(adminMenuProvider)),
        data: _buildContent,
      ),
    );
  }

  Widget _buildContent(AdminMenu menu) {
    if (menu.categories.isEmpty) {
      return EmptyState(
        icon: Icons.menu_book_rounded,
        message: 'Todavía no hay categorías.\nEmpieza creando una (por ejemplo "Hamburguesas").',
        action: FilledButton.icon(
          onPressed: () => showCategoryDialog(context),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Crear categoría'),
        ),
      );
    }
    final selected = menu.categories.firstWhereOrNull((c) => c.id == _selectedCategoryId) ?? menu.categories.first;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 300, child: _buildCategoryList(menu, selected)),
        const VerticalDivider(width: 1),
        Expanded(child: _buildProducts(menu, selected)),
      ],
    );
  }

  Widget _buildCategoryList(AdminMenu menu, Category selected) {
    final categories = menu.categories;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(
            children: [
              Expanded(child: Text('Categorías', style: Theme.of(context).textTheme.titleMedium)),
              IconButton(
                tooltip: 'Nueva categoría',
                icon: const Icon(Icons.add_rounded),
                onPressed: () => showCategoryDialog(context),
              ),
            ],
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            buildDefaultDragHandles: false,
            itemCount: categories.length,
            onReorderItem: (oldIndex, newIndex) {
              final ids = categories.map((c) => c.id).toList();
              ids.insert(newIndex, ids.removeAt(oldIndex));
              _run(() => _controller.mutate((api) => api.reorderCategories(ids)));
            },
            itemBuilder: (context, index) {
              final category = categories[index];
              final hidden = !category.isActive;
              // Material propio: el color de selección se pinta bien sobre el panel.
              return Material(
                key: ValueKey(category.id),
                type: MaterialType.transparency,
                child: ListTile(
                selected: category.id == selected.id,
                leading: ReorderableDragStartListener(
                  index: index,
                  child: const Icon(Icons.drag_indicator_rounded),
                ),
                title: Text(category.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('${category.products.length} productos${hidden ? ' · Inactiva' : ''}'),
                onTap: () => setState(() => _selectedCategoryId = category.id),
                trailing: PopupMenuButton<String>(
                  onSelected: (action) => _onCategoryAction(action, category),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Editar')),
                    PopupMenuItem(value: 'delete', child: Text('Eliminar')),
                  ],
                ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _onCategoryAction(String action, Category category) async {
    if (action == 'edit') {
      await showCategoryDialog(context, category: category);
      return;
    }
    final ok = await confirm(
      context,
      title: 'Eliminar "${category.name}"',
      message: category.products.isEmpty
          ? 'Esta acción no se puede deshacer.'
          : 'La categoría tiene productos. Muévelos o elimínalos primero, o desactívala.',
    );
    if (ok) await _run(() => _controller.mutate((api) => api.deleteCategory(category.id)));
  }

  Widget _buildProducts(AdminMenu menu, Category category) {
    final theme = Theme.of(context);
    // Si el usuario no puede ver promociones (o falla la carga), simplemente no hay etiquetas.
    final promotions = ref.watch(promotionsProvider).value ?? const <Promotion>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
          child: Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(category.name, style: theme.textTheme.headlineSmall),
                    if (!category.isActive) const StatusChip('Inactiva'),
                    if (!category.visibleOnline) const StatusChip('No visible en la web'),
                    if (!category.visibleDineIn) const StatusChip('No visible en mesas'),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: () => openProductEditor(context, categoryId: category.id),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Nuevo producto'),
              ),
            ],
          ),
        ),
        Expanded(
          child: category.products.isEmpty
              ? const EmptyState(icon: Icons.fastfood_rounded, message: 'Esta categoría no tiene productos todavía.')
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 260,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 0.68,
                  ),
                  itemCount: category.products.length,
                  itemBuilder: (context, index) => _ProductCard(
                    product: category.products[index],
                    promotions: activePromotionsFor(promotions, category.products[index]),
                    station: menu.stations.firstWhereOrNull((s) => s.id == category.products[index].stationId),
                    onTap: () => openProductEditor(
                      context,
                      categoryId: category.id,
                      product: category.products[index],
                    ),
                    onAvailabilityChanged: (value) => _run(() => _controller
                        .mutate((api) => api.setProductAvailability(category.products[index].id, value))),
                  ),
                ),
        ),
      ],
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.promotions,
    required this.station,
    required this.onTap,
    required this.onAvailabilityChanged,
  });

  final Product product;
  final List<Promotion> promotions;
  final Station? station;
  final VoidCallback onTap;
  final ValueChanged<bool> onAvailabilityChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // La foto toma el espacio que sobra; el texto siempre cabe completo.
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Opacity(
                    opacity: product.isAvailable && product.isActive ? 1 : 0.45,
                    child: ProductImage(url: product.imageUrl),
                  ),
                  if (promotions.isNotEmpty)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: _PromotionBadge(promotions: promotions),
                    ),
                ],
              ),
            ),
            Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(formatMoney(product.price), style: theme.textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Wrap(spacing: 4, runSpacing: 4, children: [
                      if (!product.isActive) const StatusChip('Oculto'),
                      if (station != null) StatusChip(station!.name, color: colorFromHex(station!.color)),
                      if (station == null) StatusChip('Sin estación', color: theme.colorScheme.error),
                    ]),
                  ],
                ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 4, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      product.isAvailable ? 'Disponible' : 'Agotado',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: product.isAvailable ? BrandTokens.of(context).success : BrandTokens.of(context).danger,
                      ),
                    ),
                  ),
                  Switch(value: product.isAvailable, onChanged: onAvailabilityChanged),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Etiqueta roja sobre la foto del producto. Al pasar el mouse muestra
/// el nombre de cada promoción que le aplica.
class _PromotionBadge extends StatelessWidget {
  const _PromotionBadge({required this.promotions});
  final List<Promotion> promotions;

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final extra = promotions.length > 1 ? ' +${promotions.length - 1}' : '';
    return Tooltip(
      message: promotions.map((p) => 'Promo: ${p.name}').join('\n'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: t.accent,
          borderRadius: BorderRadius.circular(999),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 1))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.local_offer_rounded, size: 14, color: t.onAccent),
            const SizedBox(width: 4),
            Text(
              '${promotionBadge(promotions.first)}$extra',
              style: TextStyle(color: t.onAccent, fontWeight: FontWeight.w800, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
