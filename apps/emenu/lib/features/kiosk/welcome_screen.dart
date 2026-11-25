import 'package:devepmax_ui/devepmax_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/device_session.dart';
import '../../core/widgets.dart';
import '../menu/menu_data.dart';
import '../table/service_actions.dart';
import '../table/table_data.dart';
import 'kiosk.dart';
import '../../core/i18n.dart';

/// Pantalla de bienvenida: el logo grande y un solo botón para empezar.
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key, required this.table});
  final TabletTable table;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = BrandTokens.of(context);
    final text = Theme.of(context).textTheme;
    final brand = BrandConfig.fromJson(ref.watch(brandProvider).value);
    // Se carga el menú mientras tanto, para que aparezca al instante.
    ref.watch(menuProvider);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.35),
            radius: 1.2,
            colors: [Color.alphaBlend(t.primary.withValues(alpha: 0.22), t.bg), t.bg],
          ),
        ),
        child: SafeArea(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => ref.read(kioskStageProvider.notifier).start(),
            child: Stack(children: [
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(32),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const StaffLogo(height: 132),
                    const SizedBox(height: 28),
                    Text(context.tr('Bienvenidos', 'Welcome'), style: text.displayMedium, textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    Text(brand.name, style: text.titleLarge?.copyWith(color: t.muted), textAlign: TextAlign.center),
                    const SizedBox(height: 20),
                    DmPill('${context.tr('Mesa', 'Table')} ${table.label}', tone: DmTone.accent, icon: Icons.table_restaurant_rounded),
                    const SizedBox(height: 40),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(340, 76),
                        textStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
                      ),
                      onPressed: () => ref.read(kioskStageProvider.notifier).start(),
                      icon: const Icon(Icons.restaurant_menu_rounded, size: 28),
                      label: Text(context.tr('Ver el menú', 'See the menu')),
                    ),
                    const SizedBox(height: 24),
                    const SizedBox(width: 340, child: ServiceActions(vertical: false, compact: true)),
                  ]),
                ),
              ),
              const Positioned(top: 16, right: 16, child: LanguageToggle()),
              Positioned(
                bottom: 16,
                left: 0,
                right: 0,
                child: Text(context.tr('Toca la pantalla para empezar', 'Tap the screen to start'), textAlign: TextAlign.center, style: TextStyle(color: t.faint)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// La tablet está vinculada pero no tiene mesa asignada.
class NoTableScreen extends ConsumerWidget {
  const NoTableScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = BrandTokens.of(context);
    final text = Theme.of(context).textTheme;
    final session = ref.watch(deviceSessionProvider).value;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const StaffLogo(height: 88),
            const SizedBox(height: 28),
            Icon(Icons.table_restaurant_rounded, size: 48, color: t.warning),
            const SizedBox(height: 12),
            Text('Esta tablet todavía no tiene mesa', style: text.headlineSmall, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'En la app Staff → Dispositivos, edita "${session?.deviceName ?? 'esta tablet'}" y elige su mesa.\n'
              'La pantalla cambia sola en cuanto la asignes.',
              textAlign: TextAlign.center,
              style: TextStyle(color: t.muted, fontSize: 16),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () => ref.read(tableProvider.notifier).refresh(),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Revisar de nuevo'),
            ),
          ]),
        ),
      ),
    );
  }
}
