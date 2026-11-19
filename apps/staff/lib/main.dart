import 'package:devepmax_ui/devepmax_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router.dart';
import 'features/admin/data/admin_api.dart';
import 'features/menu/widgets/common.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: StaffApp()));
}

class StaffApp extends ConsumerWidget {
  const StaffApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Colores de la marca del restaurante (Ajustes); valores por defecto mientras cargan.
    final brand = ref.watch(publicSettingsProvider).value;
    return MaterialApp.router(
      title: (brand?['name'] as String?) ?? 'Devepmax E-Menu',
      debugShowCheckedModeBanner: false,
      theme: buildBrandTheme(
        primary: colorFromHex(brand?['primaryColor'] as String?, fallback: const Color(0xFFFF6A3D)),
        accent: colorFromHex(brand?['accentColor'] as String?, fallback: const Color(0xFFFACC15)),
      ),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
