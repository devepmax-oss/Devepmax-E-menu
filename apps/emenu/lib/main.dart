import 'package:devepmax_ui/devepmax_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'core/device_session.dart';
import 'core/realtime.dart';
import 'features/kitchen/kitchen_screen.dart';
import 'features/kiosk/kiosk.dart';
import 'features/kiosk/welcome_screen.dart';
import 'features/menu/menu_data.dart';
import 'features/menu/menu_screen.dart';
import 'features/pairing/pairing_screen.dart';
import 'features/table/table_data.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Tablet de mesa: horizontal, pantalla completa y siempre encendida.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  try {
    await WakelockPlus.enable();
  } catch (_) {
    // Algunos navegadores no lo permiten; no es grave.
  }
  runApp(const ProviderScope(child: EmenuApp()));
}

class EmenuApp extends ConsumerWidget {
  const EmenuApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = ref.watch(brandProvider).value;
    return MaterialApp(
      title: brand?['name'] as String? ?? 'E-Menu',
      debugShowCheckedModeBanner: false,
      theme: buildBrandTheme(BrandConfig.fromJson(brand)),
      home: const _Root(),
    );
  }
}

/// Sin vincular → vincular. Tablet de mesa → la mesa. Pantalla de cocina → los tickets.
class _Root extends ConsumerWidget {
  const _Root();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(deviceSessionProvider);
    return session.when(
      loading: () => const _Splash(),
      error: (_, __) => const PairingScreen(),
      data: (s) => s == null
          ? const PairingScreen()
          : s.isKitchen
              ? const _KitchenShell()
              : const _TabletShell(),
    );
  }
}

class _KitchenShell extends ConsumerWidget {
  const _KitchenShell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(realtimeProvider); // mantiene el socket abierto
    return const KitchenScreen();
  }
}

class _TabletShell extends ConsumerWidget {
  const _TabletShell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(realtimeProvider); // mantiene el socket abierto
    final table = ref.watch(tableProvider);
    final stage = ref.watch(kioskStageProvider);
    return IdleWatcher(
      child: table.when(
        loading: () => const _Splash(),
        error: (error, _) => _Offline(message: '$error', onRetry: () => ref.invalidate(tableProvider)),
        data: (t) {
          if (!t.hasTable) return const NoTableScreen();
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            child: stage == KioskStage.welcome
                ? WelcomeScreen(key: const ValueKey('welcome'), table: t)
                : const MenuScreen(key: ValueKey('menu')),
          );
        },
      ),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class _Offline extends StatelessWidget {
  const _Offline({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    return Scaffold(
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.wifi_off_rounded, size: 56, color: t.faint),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          FilledButton(onPressed: onRetry, child: const Text('Reintentar')),
        ]),
      ),
    );
  }
}
