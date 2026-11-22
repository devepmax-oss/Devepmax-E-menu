import 'package:devepmax_ui/devepmax_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router.dart';
import 'features/admin/data/admin_api.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: StaffApp()));
}

class StaffApp extends ConsumerWidget {
  const StaffApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Marca del restaurante (Ajustes): colores, fondo y tipografía. Mientras carga, la de fábrica.
    final brand = ref.watch(publicSettingsProvider).value;
    return MaterialApp.router(
      title: (brand?['name'] as String?) ?? 'Devepmax E-Menu',
      debugShowCheckedModeBanner: false,
      theme: buildBrandTheme(BrandConfig.fromJson(brand)),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
