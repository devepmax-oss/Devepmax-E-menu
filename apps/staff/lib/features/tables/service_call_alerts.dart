import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/realtime/realtime.dart';
import 'data/tables_api.dart';
import 'data/tables_models.dart';
import 'screens/table_panel.dart';

/// Cuando una tablet llama al mesero o pide la cuenta, o la cocina termina un pedido de una
/// mesa, suena y aparece un aviso en cualquier pantalla, con un botón para abrir la mesa.
class ServiceCallAlerts extends ConsumerStatefulWidget {
  const ServiceCallAlerts({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<ServiceCallAlerts> createState() => _ServiceCallAlertsState();
}

class _ServiceCallAlertsState extends ConsumerState<ServiceCallAlerts> {
  StreamSubscription<RealtimeEvent>? _sub;
  final AudioPlayer _player = AudioPlayer();

  /// Pedidos ya avisados como listos (cada aviso de cocina llega varias veces).
  final Set<String> _readyAlerted = {};

  @override
  void initState() {
    super.initState();
    _sub = ref.read(realtimeProvider.notifier).events.listen(_onEvent);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _player.dispose();
    super.dispose();
  }

  void _onEvent(RealtimeEvent event) {
    if (event.name == 'order.updated') {
      _onOrder(event.json);
      return;
    }
    if (event.name != 'service_request.created' || !mounted) return;
    final json = event.json;
    final table = json?['table'] as Map?;
    if (json == null || table == null) return;
    final label = table['label'] as String? ?? '';
    final tableId = table['id'] as String? ?? '';
    final what = serviceRequestLabels[json['type']] ?? 'Necesita ayuda';
    _alert(
      tableId: tableId,
      icon: json['type'] == 'REQUEST_BILL' ? Icons.receipt_long_rounded : Icons.notifications_active_rounded,
      message: 'Mesa $label · $what',
    );
  }

  /// La cocina terminó un pedido de una mesa: avisa a quien la atiende (o a todos si no tiene mesero).
  void _onOrder(Map<String, dynamic>? json) {
    if (json == null || !mounted || json['status'] != 'READY' || json['fulfillmentType'] != 'DINE_IN') return;
    final table = json['table'] as Map?;
    final id = json['id'] as String?;
    if (table == null || id == null || !_readyAlerted.add(id)) return;
    final tableId = table['id'] as String? ?? '';
    final me = ref.read(authControllerProvider).value?.employee.id;
    final session = (ref.read(floorProvider).value ?? const <AreaView>[])
        .expand((a) => a.tables)
        .where((t) => t.id == tableId)
        .map((t) => t.session)
        .firstOrNull;
    if (session?.waiterId != null && session!.waiterId != me) return;
    _alert(tableId: tableId, icon: Icons.room_service_rounded, message: 'Mesa ${table['label']} · pedido #${json['number']} listo para llevar');
  }

  void _alert({required String tableId, required IconData icon, required String message}) {
    unawaited(_play());
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      duration: const Duration(seconds: 12),
      behavior: SnackBarBehavior.floating,
      width: MediaQuery.sizeOf(context).width < 600 ? null : 460,
      content: Row(children: [
        Icon(icon, color: Colors.white),
        const SizedBox(width: 12),
        Expanded(
          child: Text(message, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        ),
      ]),
      action: SnackBarAction(label: 'Ver mesa', onPressed: () => showTablePanel(context, tableId)),
    ));
  }

  Future<void> _play() async {
    try {
      await _player.stop();
      await _player.play(AssetSource('sounds/alert.mp3'));
    } catch (_) {
      // Si el navegador bloquea el sonido (sin interacción previa), queda el aviso visual.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
