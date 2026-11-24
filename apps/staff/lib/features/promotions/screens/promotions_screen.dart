import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/ui/feedback.dart';
import '../../menu/data/menu_models.dart';
import '../../menu/menu_controller.dart';
import '../../menu/widgets/common.dart';
import '../data/promotions_api.dart';
import 'promotion_editor.dart';

const _stateLabels = <String, (String, Color)>{
  'ACTIVE': ('Activa', Color(0xFF15803D)),
  'SCHEDULED': ('Programada', Color(0xFFB45309)),
  'EXPIRED': ('Vencida', Color(0xFF6B7280)),
  'INACTIVE': ('Desactivada', Color(0xFF6B7280)),
};

/// Texto corto de la regla: "10 % en Hamburguesas", "2x1 en Picadera Burger", "Combo a $15.00".
String promotionSummary(Promotion p, AdminMenu? menu) {
  final names = <String>[
    for (final id in p.categoryIds) menu?.categories.firstWhereOrNull((c) => c.id == id)?.name ?? 'categoría',
    for (final id in p.productIds)
      menu?.categories.expand((c) => c.products).firstWhereOrNull((x) => x.id == id)?.name ?? 'producto',
  ];
  final target = names.isEmpty ? '' : ' en ${names.take(3).join(', ')}${names.length > 3 ? '…' : ''}';
  switch (p.type) {
    case 'PERCENT_OFF':
      return '${p.value?.toStringAsFixed(0)} % de descuento$target';
    case 'AMOUNT_OFF':
      return '${formatMoney(p.value ?? 0)} menos por unidad$target';
    case 'BUY_X_GET_Y':
      final buy = p.buyQuantity ?? 1;
      final get = p.getQuantity ?? 1;
      return '${buy + get}x$buy (lleva ${buy + get}, paga $buy)$target';
    case 'COMBO_PRICE':
      return 'Combo a ${formatMoney(p.comboPrice ?? 0)}: ${p.comboSlots.map((s) => '${s.quantity} ${s.name}').join(' + ')}';
  }
  return p.type;
}

class PromotionsScreen extends ConsumerWidget {
  const PromotionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final promotions = ref.watch(promotionsProvider);
    final menu = ref.watch(adminMenuProvider).value;

    Future<void> run(Future<void> Function(PromotionsApi api) action) async {
      try {
        await action(ref.read(promotionsApiProvider));
        ref.invalidate(promotionsProvider);
      } catch (error) {
        if (context.mounted) showError(context, error);
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Promociones'),
        actions: [
          AppBarAction(
            icon: Icons.add_rounded,
            label: 'Nueva promoción',
            onPressed: menu == null ? null : () => openPromotionEditor(context),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: promotions.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorView(error: error, onRetry: () => ref.invalidate(promotionsProvider)),
        data: (list) {
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.local_offer_rounded,
              message: 'Crea descuentos, 2x1 o combos.\nSe aplican solos en cada orden, en mesas, caja y web.',
            );
          }
          return ListView.separated(
            padding: EdgeInsets.all(pagePadding(context)),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final p = list[index];
              final (stateLabel, stateColor) = _stateLabels[p.state] ?? ('', Colors.grey);
              final dates = DateFormat.yMMMd();
              final validity = [
                if (p.startsAt != null) 'desde ${dates.format(p.startsAt!)}',
                if (p.endsAt != null) 'hasta ${dates.format(p.endsAt!)}',
              ].join(' ');
              final actions = <Widget>[
                    Switch(
                      value: p.isActive,
                      onChanged: (v) => run((api) => api.update(p.id, {'isActive': v})),
                    ),
                    IconButton(
                      tooltip: 'Editar',
                      icon: const Icon(Icons.edit_rounded),
                      onPressed: menu == null ? null : () => openPromotionEditor(context, promotion: p),
                    ),
                    IconButton(
                      tooltip: 'Eliminar',
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: () async {
                        final ok = await confirm(
                          context,
                          title: 'Eliminar "${p.name}"',
                          message: 'Las órdenes anteriores conservan su descuento. Si solo quieres pausarla, desactívala.',
                        );
                        if (ok) await run((api) => api.delete(p.id));
                      },
                    ),
              ];
              final compact = isCompact(context);
              return Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Icon(Icons.local_offer_rounded, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                          Text(p.name, style: Theme.of(context).textTheme.titleMedium),
                          StatusChip(stateLabel, color: stateColor),
                        ]),
                        const SizedBox(height: 4),
                        Text(promotionSummary(p, menu)),
                        const SizedBox(height: 4),
                        Text(
                          [
                            [if (p.appliesDineIn) 'Mesas y caja', if (p.appliesOnline) 'Web'].join(' · '),
                            if (validity.isNotEmpty) validity else 'Sin fecha de fin',
                            'Usada ${p.timesApplied} ${p.timesApplied == 1 ? 'vez' : 'veces'}',
                          ].join('  ·  '),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ]),
                    ),
                    if (!compact) ...actions,
                  ]),
                  if (compact) Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
                  ]),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
