import 'package:devepmax_ui/devepmax_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/feedback.dart';
import '../data/deliveries_api.dart';
import '../data/deliveries_controller.dart';
import '../data/delivery_models.dart';
import 'delivery_actions.dart';

/// Detalle de una entrega: a dónde va, quién la recibe, qué lleva y el siguiente paso.
class DeliveryScreen extends ConsumerWidget {
  const DeliveryScreen({super.key, required this.assignmentId});
  final String assignmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = BrandTokens.of(context);
    final text = Theme.of(context).textTheme;
    final d = ref.watch(deliveriesProvider).value?.where((x) => x.assignmentId == assignmentId).firstOrNull;

    if (d == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.task_alt_rounded, size: 56, color: t.success),
              const SizedBox(height: 12),
              Text('Esta entrega ya no está en tu lista', style: text.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Text('Se entregó, se canceló o se asignó a otro repartidor.', style: text.bodyMedium, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Volver')),
            ]),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Pedido #${d.number}'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: DmPill(deliveryStatusLabels[d.status] ?? d.status, tone: d.status == 'PICKED_UP' ? DmTone.info : DmTone.primary),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
        // Dirección y navegación
        DmPanel(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Entregar en', style: text.labelLarge?.copyWith(color: t.muted)),
            const SizedBox(height: 4),
            Text(d.street, style: text.headlineSmall),
            if (d.cityLine.isNotEmpty) Text(d.cityLine, style: text.titleMedium?.copyWith(color: t.muted)),
            if (d.instructions != null && d.instructions!.isNotEmpty) ...[
              const SizedBox(height: 10),
              DmPanel(
                color: t.warningSoft,
                padding: const EdgeInsets.all(10),
                child: Text(d.instructions!, style: text.bodyMedium?.copyWith(color: t.warning)),
              ),
            ],
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => openExternal(context, googleMapsUri(d)),
                  icon: const Icon(Icons.map_rounded),
                  label: const Text('Google Maps'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => openExternal(context, wazeUri(d)),
                  icon: const Icon(Icons.navigation_rounded),
                  label: const Text('Waze'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                ),
              ),
            ]),
          ]),
        ),
        const SizedBox(height: 12),

        // Cliente
        DmPanel(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: t.primarySoft,
              child: Text((d.customerName ?? 'C').characters.first.toUpperCase(), style: text.titleLarge?.copyWith(color: t.primaryText)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(d.customerName ?? 'Cliente', style: text.titleMedium),
                if (d.customerPhone != null) Text(d.customerPhone!, style: text.bodyMedium?.copyWith(color: t.muted)),
              ]),
            ),
            if (d.customerPhone != null)
              IconButton.filled(
                tooltip: 'Llamar al cliente',
                iconSize: 24,
                onPressed: () => openExternal(context, phoneUri(d.customerPhone!)),
                icon: const Icon(Icons.call_rounded),
              ),
          ]),
        ),
        const SizedBox(height: 12),

        // Pago
        DmPanel(
          color: d.paid ? t.successSoft : t.warningSoft,
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Icon(d.paid ? Icons.verified_rounded : Icons.payments_rounded, color: d.paid ? t.success : t.warning),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                d.paid ? 'Pagado en línea: no cobres nada' : 'Cobra ${formatMoney(d.amountDue)} al entregar',
                style: text.titleMedium?.copyWith(color: d.paid ? t.success : t.warning),
              ),
            ),
            if (d.tip > 0) Text('Propina ${formatMoney(d.tip)}', style: text.bodyMedium?.copyWith(color: d.paid ? t.success : t.warning)),
          ]),
        ),
        const SizedBox(height: 20),

        // Productos
        Text('Lleva ${d.itemCount} producto${d.itemCount == 1 ? '' : 's'}', style: text.titleLarge),
        const SizedBox(height: 8),
        for (final item in d.items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 36, child: Text('${item.quantity}×', style: text.titleMedium?.copyWith(color: t.accentText))),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(item.name, style: text.titleSmall),
                  if (item.modifiers.isNotEmpty) Text(item.modifiers.join(' · '), style: text.bodySmall),
                ]),
              ),
            ]),
          ),
        if (d.notes != null && d.notes!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Nota: ${d.notes}', style: text.bodyMedium?.copyWith(color: t.warning)),
        ],
        if (d.status == 'PENDING' || d.status == 'ACCEPTED') ...[
          const SizedBox(height: 24),
          Center(
            child: TextButton(
              onPressed: () => _decline(context, ref, d),
              style: TextButton.styleFrom(foregroundColor: t.danger),
              child: const Text('No puedo llevar este pedido'),
            ),
          ),
        ],
      ]),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: DeliveryActionButton(delivery: d, large: true),
      ),
    );
  }

  Future<void> _decline(BuildContext context, WidgetRef ref, Delivery d) async {
    final ok = await confirm(
      context,
      title: '¿Devolver el pedido #${d.number}?',
      message: 'El encargado lo asignará a otro repartidor.',
      confirmLabel: 'Devolver',
    );
    if (!ok) return;
    try {
      await ref.read(deliveriesApiProvider).decline(d.assignmentId);
      await ref.read(deliveriesProvider.notifier).refresh();
      if (context.mounted) Navigator.pop(context);
    } catch (error) {
      if (context.mounted) showError(context, error);
    }
  }
}
