import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../menu/cart.dart';
import '../table/table_data.dart';

enum KioskStage { welcome, menu }

/// Bienvenida o menú. Cuando el mesero cierra la mesa, la tablet vuelve sola a la bienvenida
/// y se vacía el pedido a medio armar, lista para los próximos clientes.
final kioskStageProvider = NotifierProvider<KioskStageController, KioskStage>(KioskStageController.new);

class KioskStageController extends Notifier<KioskStage> {
  @override
  KioskStage build() {
    ref.listen(tableProvider, (previous, next) {
      final before = previous?.value?.session;
      final now = next.value?.session;
      if (before != null && now == null) reset();
    });
    return KioskStage.welcome;
  }

  void start() => state = KioskStage.menu;

  void reset() {
    ref.read(cartProvider.notifier).clear();
    state = KioskStage.welcome;
  }
}

/// Si nadie toca la tablet por un rato y la mesa no tiene clientes, vuelve a la bienvenida.
class IdleWatcher extends ConsumerStatefulWidget {
  const IdleWatcher({super.key, required this.child, this.timeout = const Duration(minutes: 3)});
  final Widget child;
  final Duration timeout;

  @override
  ConsumerState<IdleWatcher> createState() => _IdleWatcherState();
}

class _IdleWatcherState extends ConsumerState<IdleWatcher> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _restart();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _restart() {
    _timer?.cancel();
    _timer = Timer(widget.timeout, _idle);
  }

  void _idle() {
    if (!mounted) return;
    final seated = ref.read(tableProvider).value?.session != null;
    if (ref.read(kioskStageProvider) == KioskStage.menu && !seated) {
      // Cierra cualquier ventana abierta (detalle de un plato, la cuenta…).
      Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
      ref.read(kioskStageProvider.notifier).reset();
    }
    _restart();
  }

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _restart(),
        child: widget.child,
      );
}
