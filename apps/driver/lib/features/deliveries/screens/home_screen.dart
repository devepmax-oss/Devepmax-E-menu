import 'package:devepmax_ui/devepmax_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/realtime/realtime.dart';
import '../../../core/ui/feedback.dart';
import '../data/deliveries_api.dart';
import '../data/deliveries_controller.dart';
import '../data/delivery_models.dart';
import 'delivery_actions.dart';
import 'delivery_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = BrandTokens.of(context);
    final text = Theme.of(context).textTheme;
    final brand = ref.watch(brandProvider).value;
    final me = ref.watch(driverMeProvider);
    final deliveries = ref.watch(deliveriesProvider);
    final live = ref.watch(realtimeProvider);
    final location = ref.watch(locationSharingProvider);
    ref.listen(driverNoticeProvider, (_, message) {
      if (message == null) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 6)));
      ref.read(driverNoticeProvider.notifier).clear();
    });

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(children: [
          BrandMark(logoUrl: brand?['logoUrl'] as String?, name: brand?['name'] as String? ?? 'Repartidor', height: 36),
          const SizedBox(width: 10),
          Expanded(child: Text('Mis entregas', style: text.titleLarge, overflow: TextOverflow.ellipsis)),
        ]),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: DmPill(
              live == RealtimeStatus.live ? 'En vivo' : 'Conectando',
              tone: live == RealtimeStatus.live ? DmTone.success : DmTone.warning,
              icon: Icons.circle,
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'vehicle') await showVehicleDialog(context, ref);
              if (v == 'logout') {
                await ref.read(driverMeProvider.notifier).save({'status': 'OFFLINE'}).catchError((_) {});
                await ref.read(authControllerProvider.notifier).logout();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'vehicle', child: Text('Mi vehículo')),
              PopupMenuItem(value: 'logout', child: Text('Cerrar sesión')),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(deliveriesProvider.notifier).refresh(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            me.when(
              loading: () => const SizedBox(height: 88, child: Center(child: CircularProgressIndicator())),
              error: (e, _) => DmPanel(child: Text('No se pudo cargar tu perfil: $e')),
              data: (m) => _AvailabilityCard(me: m),
            ),
            if (location == LocationState.sharing || location == LocationState.denied || location == LocationState.disabled) ...[
              const SizedBox(height: 12),
              _LocationBanner(state: location),
            ],
            const SizedBox(height: 20),
            deliveries.when(
              loading: () => const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
              error: (e, _) => DmPanel(child: Text('No se pudieron cargar tus entregas: $e')),
              data: (list) => list.isEmpty
                  ? _Empty(available: me.value?.available ?? false)
                  : Column(children: [for (final d in list) _DeliveryCard(delivery: d)]),
            ),
            const SizedBox(height: 8),
            Text('Tus entregas se actualizan solas.', style: text.bodySmall?.copyWith(color: t.faint), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _AvailabilityCard extends ConsumerStatefulWidget {
  const _AvailabilityCard({required this.me});
  final DriverMe me;

  @override
  ConsumerState<_AvailabilityCard> createState() => _AvailabilityCardState();
}

class _AvailabilityCardState extends ConsumerState<_AvailabilityCard> {
  bool _busy = false;

  Future<void> _toggle(bool on) async {
    setState(() => _busy = true);
    try {
      await ref.read(driverMeProvider.notifier).save({'status': on ? 'AVAILABLE' : 'OFFLINE'});
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final text = Theme.of(context).textTheme;
    final m = widget.me;
    return DmPanel(
      color: m.available ? t.successSoft : null,
      padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Hola, ${m.name.split(' ').first}', style: text.titleLarge),
            Text(
              m.available ? 'Disponible: te pueden asignar entregas' : 'Desconectado: no te asignarán entregas',
              style: text.bodyMedium?.copyWith(color: m.available ? t.success : t.muted),
            ),
            if (m.vehicle.isNotEmpty) Text(m.vehicle, style: text.bodySmall),
          ]),
        ),
        _busy
            ? const Padding(padding: EdgeInsets.all(12), child: SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2.5)))
            : Transform.scale(scale: 1.2, child: Switch(value: m.available, onChanged: _toggle)),
      ]),
    );
  }
}

class _LocationBanner extends ConsumerWidget {
  const _LocationBanner({required this.state});
  final LocationState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = BrandTokens.of(context);
    final text = Theme.of(context).textTheme;
    final sharing = state == LocationState.sharing;
    return DmPanel(
      color: sharing ? t.infoSoft : t.warningSoft,
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        Icon(sharing ? Icons.my_location_rounded : Icons.location_disabled_rounded, color: sharing ? t.info : t.warning),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            sharing
                ? 'Compartiendo tu ubicación con el cliente mientras vas en camino.'
                : state == LocationState.disabled
                    ? 'Activa el GPS para que el cliente vea dónde vas.'
                    : 'Permite el acceso a tu ubicación para que el cliente vea dónde vas.',
            style: text.bodyMedium?.copyWith(color: sharing ? t.info : t.warning),
          ),
        ),
        if (!sharing) TextButton(onPressed: () => ref.read(locationSharingProvider.notifier).retry(), child: const Text('Reintentar')),
      ]),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.available});
  final bool available;

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(color: t.primarySoft, shape: BoxShape.circle),
          child: Icon(Icons.delivery_dining_rounded, size: 44, color: t.primaryText),
        ),
        const SizedBox(height: 16),
        Text('No tienes entregas', style: text.titleLarge),
        const SizedBox(height: 6),
        Text(
          available
              ? 'Cuando te asignen una, suena y aparece aquí.'
              : 'Actívate como disponible para recibir entregas.',
          style: text.bodyMedium?.copyWith(color: t.muted),
          textAlign: TextAlign.center,
        ),
      ]),
    );
  }
}

class _DeliveryCard extends StatelessWidget {
  const _DeliveryCard({required this.delivery});
  final Delivery delivery;

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final text = Theme.of(context).textTheme;
    final d = delivery;
    final isNew = d.status == 'PENDING';
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: t.surface,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => DeliveryScreen(assignmentId: d.assignmentId))),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: isNew ? t.accent : t.line, width: isNew ? 2 : 1),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Text('#${d.number}', style: text.headlineMedium),
                const SizedBox(width: 10),
                DmPill(
                  deliveryStatusLabels[d.status] ?? d.status,
                  tone: switch (d.status) { 'PENDING' => DmTone.accent, 'PICKED_UP' => DmTone.info, _ => DmTone.primary },
                ),
                const Spacer(),
                if (d.paid) const DmPill('Pagado', tone: DmTone.success) else DmPill('Cobrar ${formatMoney(d.amountDue)}', tone: DmTone.warning),
              ]),
              const SizedBox(height: 10),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.location_on_rounded, color: t.accentText, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(d.street, style: text.titleMedium),
                    if (d.cityLine.isNotEmpty) Text(d.cityLine, style: text.bodyMedium?.copyWith(color: t.muted)),
                  ]),
                ),
              ]),
              const SizedBox(height: 8),
              Text(
                '${d.customerName ?? 'Cliente'} · ${d.itemCount} producto${d.itemCount == 1 ? '' : 's'}'
                '${d.status == 'ACCEPTED' ? ' · ${kitchenLabels[d.orderStatus] ?? d.orderStatus}' : ''}',
                style: text.bodyMedium,
              ),
              if (d.status == 'PENDING' && d.offerExpiresAt != null) ...[
                const SizedBox(height: 12),
                OfferCountdown(key: ValueKey(d.offerExpiresAt), expiresAt: d.offerExpiresAt!),
              ],
              const SizedBox(height: 14),
              DeliveryActionButton(delivery: d),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Tipo, color y placa del vehículo (el cliente ve tipo y color).
Future<void> showVehicleDialog(BuildContext context, WidgetRef ref) async {
  final me = ref.read(driverMeProvider).value;
  final type = TextEditingController(text: me?.vehicleType ?? '');
  final color = TextEditingController(text: me?.vehicleColor ?? '');
  final plate = TextEditingController(text: me?.vehiclePlate ?? '');
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Mi vehículo'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: type, decoration: const InputDecoration(labelText: 'Tipo (moto, carro, bici)')),
        const SizedBox(height: 12),
        TextField(controller: color, decoration: const InputDecoration(labelText: 'Color')),
        const SizedBox(height: 12),
        TextField(controller: plate, decoration: const InputDecoration(labelText: 'Placa (opcional)')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Guardar')),
      ],
    ),
  );
  if (ok == true) {
    try {
      await ref.read(driverMeProvider.notifier).save({'vehicleType': type.text, 'vehicleColor': color.text, 'vehiclePlate': plate.text});
      if (context.mounted) showSuccess(context, 'Vehículo guardado');
    } catch (error) {
      if (context.mounted) showError(context, error);
    }
  }
  type.dispose();
  color.dispose();
  plate.dispose();
}
