import 'dart:async';

import 'package:devepmax_ui/devepmax_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/ui/feedback.dart';
import '../data/deliveries_api.dart';
import '../data/deliveries_controller.dart';
import '../data/delivery_models.dart';

/// Abre la ruta en Google Maps o Waze, o llama al cliente.
Future<void> openExternal(BuildContext context, Uri uri) async {
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) showError(context, 'No se pudo abrir ${uri.scheme == 'tel' ? 'el teléfono' : 'el mapa'}');
}

Uri googleMapsUri(Delivery d) =>
    Uri.https('www.google.com', '/maps/dir/', {'api': '1', 'destination': d.fullAddress, 'travelmode': 'driving'});

Uri wazeUri(Delivery d) => Uri.https('waze.com', '/ul', {'q': d.fullAddress, 'navigate': 'yes'});

Uri phoneUri(String phone) => Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'[^0-9+]'), ''));

/// El siguiente paso de la entrega, como un botón grande: Aceptar → Lo recogí → Entregado.
class DeliveryActionButton extends ConsumerStatefulWidget {
  const DeliveryActionButton({super.key, required this.delivery, this.large = false});
  final Delivery delivery;
  final bool large;

  @override
  ConsumerState<DeliveryActionButton> createState() => _DeliveryActionButtonState();
}

class _DeliveryActionButtonState extends ConsumerState<DeliveryActionButton> {
  bool _busy = false;

  Future<void> _run(Future<Delivery> Function(DeliveriesApi api) action, {String? done}) async {
    setState(() => _busy = true);
    try {
      final updated = await action(ref.read(deliveriesApiProvider));
      ref.read(deliveriesProvider.notifier).apply(updated);
      if (done != null && mounted) showSuccess(context, done);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deliver() async {
    final d = widget.delivery;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('¿Entregaste el pedido #${d.number}?'),
        content: Text(d.paid
            ? 'Ya está pagado: no cobres nada.'
            : 'Cobra ${formatMoney(d.amountDue)} antes de marcarlo como entregado.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Todavía no')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sí, entregado')),
        ],
      ),
    );
    if (ok != true) return;
    await _run((api) => api.delivered(d.assignmentId), done: 'Pedido #${d.number} entregado');
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.delivery;
    final size = Size.fromHeight(widget.large ? 60 : 50);
    final style = FilledButton.styleFrom(minimumSize: size, textStyle: TextStyle(fontSize: widget.large ? 18 : 16, fontWeight: FontWeight.w800));
    Widget label(IconData icon, String text) => _busy
        ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
        : Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon), const SizedBox(width: 10), Text(text)]);

    switch (d.status) {
      case 'PENDING':
        return FilledButton(
          style: style,
          onPressed: _busy ? null : () => _run((api) => api.accept(d.assignmentId)),
          child: label(Icons.check_circle_rounded, 'Aceptar entrega'),
        );
      case 'ACCEPTED':
        if (!d.readyToPickUp) {
          return FilledButton.tonal(
            style: style,
            onPressed: null,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.hourglass_top_rounded),
              const SizedBox(width: 10),
              Flexible(child: Text('Esperando a la cocina · ${kitchenLabels[d.orderStatus] ?? d.orderStatus}', overflow: TextOverflow.ellipsis)),
            ]),
          );
        }
        return FilledButton(
          style: style,
          onPressed: _busy ? null : () => _run((api) => api.pickedUp(d.assignmentId), done: '¡Buen viaje! El cliente ya ve que vas en camino'),
          child: label(Icons.shopping_bag_rounded, 'Lo recogí'),
        );
      case 'PICKED_UP':
        return FilledButton(
          style: style,
          onPressed: _busy ? null : _deliver,
          child: label(Icons.where_to_vote_rounded, 'Entregado'),
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

/// Cuenta regresiva de una oferta automática: "Acepta en 45 s".
class OfferCountdown extends StatefulWidget {
  const OfferCountdown({super.key, required this.expiresAt});
  final DateTime expiresAt;

  @override
  State<OfferCountdown> createState() => _OfferCountdownState();
}

class _OfferCountdownState extends State<OfferCountdown> {
  Timer? _timer;
  late final Duration _total = widget.expiresAt.difference(DateTime.now());

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final text = Theme.of(context).textTheme;
    final left = widget.expiresAt.difference(DateTime.now());
    final seconds = left.inSeconds.clamp(0, 999);
    final ratio = _total.inMilliseconds <= 0 ? 0.0 : (left.inMilliseconds / _total.inMilliseconds).clamp(0.0, 1.0);
    final urgent = seconds <= 15;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Icon(Icons.timer_rounded, size: 18, color: urgent ? t.danger : t.accentText),
        const SizedBox(width: 6),
        Text(
          seconds > 0 ? 'Acepta en $seconds s' : 'Pasando a otro repartidor…',
          style: text.titleSmall?.copyWith(color: urgent ? t.danger : t.accentText),
        ),
      ]),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: LinearProgressIndicator(
          value: ratio,
          minHeight: 6,
          backgroundColor: t.surface3,
          color: urgent ? t.danger : t.accent,
        ),
      ),
    ]);
  }
}
