import 'package:devepmax_ui/devepmax_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/widgets.dart';
import '../table/service_actions.dart';
import '../table/table_data.dart';
import 'cart.dart';
import '../../core/i18n.dart';

/// Panel de la derecha: el pedido que están armando, o el estado de lo ya pedido.
class CartPanel extends ConsumerWidget {
  const CartPanel({super.key, this.inSheet = false});
  final bool inSheet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lines = ref.watch(cartProvider);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: lines.isEmpty ? const OrdersTracker(key: ValueKey('orders')) : _Cart(key: const ValueKey('cart'), inSheet: inSheet),
    );
  }
}

class _Cart extends ConsumerWidget {
  const _Cart({super.key, required this.inSheet});
  final bool inSheet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = BrandTokens.of(context);
    final text = Theme.of(context).textTheme;
    final lines = ref.watch(cartProvider);
    final quote = ref.watch(quoteProvider);
    final sending = ref.watch(orderSenderProvider);
    final cart = ref.read(cartProvider.notifier);
    final estimate = lines.fold<double>(0, (s, l) => s + l.total);
    final q = quote.value;

    Widget row(String label, double value, {Color? color, bool bold = false}) => Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(children: [
            Expanded(child: Text(label, style: (bold ? text.titleLarge : text.bodyMedium)?.copyWith(color: color))),
            Text(formatMoney(value), style: (bold ? text.titleLarge : text.bodyMedium)?.copyWith(color: color)),
          ]),
        );

    Future<void> send() async {
      try {
        final status = await ref.read(orderSenderProvider.notifier).send();
        if (!context.mounted) return;
        if (inSheet) Navigator.pop(context);
        await showOrderSent(context, pending: status == 'PENDING_APPROVAL');
      } catch (error) {
        if (context.mounted) showMessage(context, '$error', error: true);
      }
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 12, 8),
        child: Row(children: [
          Expanded(child: Text(context.tr('Tu pedido', 'Your order'), style: text.headlineSmall)),
          TextButton(onPressed: sending ? null : cart.clear, child: Text(context.tr('Vaciar', 'Clear'))),
        ]),
      ),
      Expanded(
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          itemCount: lines.length,
          separatorBuilder: (_, __) => Divider(color: t.line, height: 20),
          itemBuilder: (context, i) {
            final l = lines[i];
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Text(l.product.name, style: text.titleMedium)),
                Text(formatMoney(l.total), style: text.titleMedium),
              ]),
              if (l.optionNames.isNotEmpty) Text(l.optionNames.join(' · '), style: TextStyle(color: t.muted)),
              if (l.notes != null) Text('“${l.notes}”', style: TextStyle(color: t.muted, fontStyle: FontStyle.italic)),
              const SizedBox(height: 8),
              QuantityStepper(
                value: l.quantity,
                min: 0,
                compact: true,
                onChanged: sending ? (_) {} : (v) => cart.setQuantity(l.key, v),
              ),
            ]);
          },
        ),
      ),
      Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: t.line))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (q != null) ...[
            row('Subtotal', q.subtotal),
            for (final p in q.promotions) row(p.name, -p.amount, color: t.success),
            row(context.tr('Impuestos', 'Tax'), q.taxTotal),
            const SizedBox(height: 4),
            row('Total', q.total, bold: true),
          ] else
            row(quote.isLoading ? context.tr('Calculando…', 'Calculating…') : context.tr('Total aprox.', 'Estimated total'), estimate, bold: true),
          const SizedBox(height: 14),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(64),
              textStyle: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
            onPressed: sending ? null : send,
            icon: sending
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                : const Icon(Icons.send_rounded),
            label: Text(sending ? context.tr('Enviando…', 'Sending…') : context.tr('Enviar a cocina', 'Send to the kitchen')),
          ),
        ]),
      ),
    ]);
  }
}

/// Lo que ya pidió la mesa y en qué va cada pedido.
class OrdersTracker extends ConsumerWidget {
  const OrdersTracker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = BrandTokens.of(context);
    final text = Theme.of(context).textTheme;
    final session = ref.watch(tableProvider).value?.session;
    final orders = (session?.orders ?? const <GuestOrder>[]).where((o) => o.status != 'CANCELLED').toList().reversed.toList();

    if (orders.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.restaurant_menu_rounded, size: 64, color: t.faint),
          const SizedBox(height: 16),
          Text(context.tr('Elige tus platos', 'Choose your dishes'), style: text.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(context.tr('Toca un plato para verlo y agregarlo. Cuando estés listo, envía tu pedido a la cocina.', 'Tap a dish to see it and add it. When you are ready, send your order to the kitchen.'),
              style: TextStyle(color: t.muted), textAlign: TextAlign.center),
        ]),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        child: Text(context.tr('Tus pedidos', 'Your orders'), style: text.headlineSmall),
      ),
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 12), children: [
          for (final o in orders) _OrderCard(order: o),
        ]),
      ),
      Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: t.line))),
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(54)),
          onPressed: () => showBillSheet(context),
          icon: const Icon(Icons.receipt_long_rounded),
          label: Text('${context.tr('Ver la cuenta', 'View the check')} · ${formatMoney(session!.bill.total)}'),
        ),
      ),
    ]);
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order});
  final GuestOrder order;

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final text = Theme.of(context).textTheme;
    final (tone, icon) = switch (order.status) {
      'READY' => (DmTone.success, Icons.room_service_rounded),
      'COMPLETED' => (DmTone.neutral, Icons.check_rounded),
      'PENDING_APPROVAL' => (DmTone.warning, Icons.hourglass_top_rounded),
      'PREPARING' => (DmTone.accent, Icons.local_fire_department_rounded),
      _ => (DmTone.primary, Icons.soup_kitchen_rounded),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: order.status == 'READY' ? t.successSoft : t.surface2,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('${context.tr('Pedido', 'Order')} ${order.number}', style: text.titleMedium)),
          Text(_ago(context, order.createdAt), style: TextStyle(color: t.muted, fontSize: 12.5)),
        ]),
        const SizedBox(height: 6),
        DmPill(guestOrderStatus(order.status, context.lang), tone: tone, icon: icon),
        const SizedBox(height: 8),
        for (final i in order.items)
          Text('${i.quantity}× ${i.name}', style: TextStyle(color: t.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
      ]),
    );
  }
}

String _ago(BuildContext context, DateTime since) {
  final minutes = DateTime.now().difference(since).inMinutes;
  if (minutes < 1) return context.tr('Recién', 'Just now');
  if (minutes < 60) return context.tr('hace $minutes min', '$minutes min ago');
  return context.tr('hace ${minutes ~/ 60} h', '${minutes ~/ 60} h ago');
}

/// "¡Pedido enviado!" — se cierra solo a los pocos segundos.
Future<void> showOrderSent(BuildContext context, {required bool pending}) {
  return showDialog<void>(
    context: context,
    builder: (context) {
      Future.delayed(const Duration(seconds: 4), () {
        if (context.mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
      });
      final t = BrandTokens.of(context);
      return Dialog(
        child: Padding(
          padding: const EdgeInsets.all(36),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.check_circle_rounded, size: 96, color: t.success),
            const SizedBox(height: 16),
            Text(context.tr('¡Pedido enviado!', 'Order sent!'), style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text(
              pending ? context.tr('Un mesero lo confirmará en un momento.', 'A server will confirm it in a moment.') : context.tr('La cocina ya lo tiene. Aquí verás cuándo esté listo.', 'The kitchen has it. You will see here when it is ready.'),
              textAlign: TextAlign.center,
              style: TextStyle(color: t.muted, fontSize: 16),
            ),
          ]),
        ),
      );
    },
  );
}
