import 'package:devepmax_ui/devepmax_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: StaffApp()));
}

class StaffApp extends ConsumerWidget {
  const StaffApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Devepmax E-Menu',
      debugShowCheckedModeBanner: false,
      // Fase 1: colores fijos. Luego vendrán de la marca del restaurante (/settings/public).
      theme: buildBrandTheme(
        primary: const Color(0xFFFF6A3D),
        accent: const Color(0xFFFACC15),
      ),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
