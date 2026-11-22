import 'package:devepmax_ui/devepmax_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/auth/auth_controller.dart';
import 'features/auth/login_screen.dart';
import 'features/deliveries/data/deliveries_api.dart';
import 'features/deliveries/screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: DriverApp()));
}

class DriverApp extends ConsumerWidget {
  const DriverApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Marca del restaurante (Ajustes): colores, fondo y tipografía.
    final brand = ref.watch(brandProvider).value;
    return MaterialApp(
      title: brand?['name'] != null ? '${brand!['name']} · Repartidor' : 'Repartidor',
      debugShowCheckedModeBanner: false,
      theme: buildBrandTheme(BrandConfig.fromJson(brand)),
      home: const _Root(),
    );
  }
}

/// Login, o la app si la sesión es de un repartidor.
class _Root extends ConsumerWidget {
  const _Root();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authControllerProvider);
    return session.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, __) => const LoginScreen(),
      data: (s) {
        if (s == null) return const LoginScreen();
        if (!s.employee.can('delivery.own')) return const _NotADriver();
        return const HomeScreen();
      },
    );
  }
}

class _NotADriver extends ConsumerWidget {
  const _NotADriver();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.no_accounts_rounded, size: 56),
            const SizedBox(height: 16),
            Text('Esta app es para repartidores', style: text.headlineSmall, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text('Tu cuenta no tiene el rol Repartidor. Pídele al encargado que te lo asigne en Empleados.',
                style: text.bodyMedium, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => ref.read(authControllerProvider.notifier).logout(),
              child: const Text('Cerrar sesión'),
            ),
          ]),
        ),
      ),
    );
  }
}
