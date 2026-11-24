import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/feedback.dart';
import '../data/menu_models.dart';
import '../menu_controller.dart';
import '../widgets/common.dart';
import 'modifier_group_dialog.dart';

class ModifierGroupsScreen extends ConsumerWidget {
  const ModifierGroupsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final menu = ref.watch(adminMenuProvider);
    final controller = ref.read(adminMenuProvider.notifier);

    Future<void> run(Future<void> Function() action) async {
      try {
        await action();
      } catch (error) {
        if (context.mounted) showError(context, error);
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Modificadores'),
        actions: [
          AppBarAction(
            icon: Icons.add_rounded,
            label: 'Nuevo grupo',
            onPressed: () => showModifierGroupDialog(context),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: menu.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorView(error: error, onRetry: () => ref.invalidate(adminMenuProvider)),
        data: (data) {
          if (data.modifierGroups.isEmpty) {
            return const EmptyState(
              icon: Icons.tune_rounded,
              message: 'Crea grupos como "Tamaño", "Extras" o "Quitar ingredientes"\ny asígnalos a tus productos.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(24),
            itemCount: data.modifierGroups.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final group = data.modifierGroups[index];
              return _GroupCard(
                group: group,
                onEdit: () => showModifierGroupDialog(context, group: group),
                onDelete: () async {
                  final ok = await confirm(
                    context,
                    title: 'Eliminar "${group.name}"',
                    message: group.productCount == 0
                        ? 'Esta acción no se puede deshacer.'
                        : 'Se quitará de ${group.productCount} producto(s). Esta acción no se puede deshacer.',
                  );
                  if (ok) await run(() => controller.mutate((api) => api.deleteModifierGroup(group.id)));
                },
                onToggleOption: (option) => run(() =>
                    controller.mutate((api) => api.setOptionAvailability(option.id, !option.isAvailable))),
              );
            },
          );
        },
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.group,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleOption,
  });

  final ModifierGroup group;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<ModifierOption> onToggleOption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(group.name, style: theme.textTheme.titleMedium),
                      StatusChip(group.rulesLabel, color: theme.colorScheme.primary),
                      if (!group.isActive) const StatusChip('Inactivo'),
                      Text('Usado en ${group.productCount} producto(s)', style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                IconButton(tooltip: 'Editar', icon: const Icon(Icons.edit_rounded), onPressed: onEdit),
                IconButton(tooltip: 'Eliminar', icon: const Icon(Icons.delete_outline_rounded), onPressed: onDelete),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in group.options)
                  Tooltip(
                    message: option.isAvailable ? 'Toca para marcar agotada' : 'Toca para marcar disponible',
                    child: InputChip(
                      avatar: option.isDefault ? const Icon(Icons.star_rounded, size: 18) : null,
                      label: Text(
                        option.priceAdjustment == 0
                            ? option.name
                            : '${option.name}  ${option.priceAdjustment > 0 ? '+' : '−'}${formatMoney(option.priceAdjustment.abs())}',
                        style: option.isAvailable
                            ? null
                            : TextStyle(decoration: TextDecoration.lineThrough, color: theme.colorScheme.error),
                      ),
                      onPressed: () => onToggleOption(option),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
