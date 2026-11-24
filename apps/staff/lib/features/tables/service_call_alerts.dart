import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/realtime/realtime.dart';
import 'data/tables_models.dart';
import 'screens/table_panel.dart';

/// Cuando una tablet llama al mesero o pide la cuenta, suena y aparece un aviso
/// en cualquier pantalla, con un botón para abrir la mesa.
class ServiceCallAlerts extends ConsumerStatefulWidget {
  const ServiceCallAlerts({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<ServiceCallAlerts> createState() => _ServiceCallAlertsState();
}

class _ServiceCallAlertsState extends ConsumerState<ServiceCallAlerts> {
  StreamSubscription<RealtimeEvent>? _sub;
  final AudioPlayer _player = AudioPlayer();

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
    if (event.name != 'service_request.created' || !mounted) return;
    final json = event.json;
    final table = json?['table'] as Map?;
    if (json == null || table == null) return;
    final label = table['label'] as String? ?? '';
    final tableId = table['id'] as String? ?? '';
    final what = serviceRequestLabels[json['type']] ?? 'Necesita ayuda';

    unawaited(_play());
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      duration: const Duration(seconds: 12),
      behavior: SnackBarBehavior.floating,
      width: 460,
      content: Row(children: [
        Icon(json['type'] == 'REQUEST_BILL' ? Icons.receipt_long_rounded : Icons.notifications_active_rounded,
            color: Colors.white),
        const SizedBox(width: 12),
        Expanded(
          child: Text('Mesa $label · $what', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
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
