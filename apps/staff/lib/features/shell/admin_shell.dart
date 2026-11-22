import 'package:devepmax_ui/devepmax_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../admin/data/admin_api.dart';

class _Destination {
  const _Destination(this.path, this.label, this.icon, this.permission);
  final String path;
  final String label;
  final IconData icon;

  /// Permiso necesario para ver la sección.
  final String permission;
}

const _allDestinations = [
  _Destination('/menu', 'Menú', Icons.restaurant_menu_rounded, 'menu.manage'),
  _Destination('/modifiers', 'Modificadores', Icons.tune_rounded, 'menu.manage'),
  _Destination('/menu-setup', 'Cocina e impuestos', Icons.soup_kitchen_rounded, 'menu.manage'),
  _Destination('/promotions', 'Promociones', Icons.local_offer_rounded, 'menu.manage'),
  _Destination('/employees', 'Empleados', Icons.badge_rounded, 'employees.manage'),
  _Destination('/devices', 'Dispositivos', Icons.devices_rounded, 'devices.manage'),
  _Destination('/settings', 'Ajustes', Icons.settings_rounded, 'settings.manage'),
];

/// Marco del panel: barra lateral de navegación + contenido.
class AdminShell extends ConsumerWidget {
  const AdminShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final employee = ref.watch(authControllerProvider).value?.employee;
    final destinations = _allDestinations.where((d) => employee?.can(d.permission) ?? false).toList();
    final selected = destinations.indexWhere((d) => location == d.path || location.startsWith('${d.path}/'));

    if (destinations.isEmpty) {
      return Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Tu rol no tiene acceso al panel de administración.'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => ref.read(authControllerProvider.notifier).logout(),
              child: const Text('Cerrar sesión'),
            ),
          ]),
        ),
      );
    }

    final brand = BrandConfig.fromJson(ref.watch(publicSettingsProvider).value);
    final t = BrandTokens.of(context);
    final initial = (employee?.name.isNotEmpty ?? false) ? employee!.name[0].toUpperCase() : '?';

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: selected < 0 ? 0 : selected,
            labelType: NavigationRailLabelType.all,
            groupAlignment: -0.85,
            onDestinationSelected: (i) => context.go(destinations[i].path),
            leading: Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 20),
              child: Tooltip(message: brand.name, child: BrandMark(name: brand.name, logoUrl: brand.logoUrl, height: 52)),
            ),
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (employee != null)
                        Tooltip(
                          message: '${employee.name} · ${employee.roleName}',
                          child: Container(
                            width: 48,
                            height: 48,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: t.surface2,
                              shape: BoxShape.circle,
                              border: Border.all(color: t.lineStrong, width: 2),
                            ),
                            child: Text(
                              initial,
                              style: brandFont(t.headingFamily, weight: t.headingWeight, size: 20, color: t.accentText),
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      IconButton(
                        tooltip: 'Cerrar sesión',
                        icon: Icon(Icons.logout_rounded, color: t.muted),
                        onPressed: () => ref.read(authControllerProvider.notifier).logout(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            destinations: [
              for (final d in destinations)
                NavigationRailDestination(
                  icon: Icon(d.icon),
                  label: Text(d.label, textAlign: TextAlign.center),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                ),
            ],
          ),
          VerticalDivider(width: 1, color: t.line),
          Expanded(child: child),
        ],
      ),
    );
  }
}
