import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';

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

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: selected < 0 ? 0 : selected,
            labelType: NavigationRailLabelType.all,
            onDestinationSelected: (i) => context.go(destinations[i].path),
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Icon(Icons.restaurant_rounded, color: Theme.of(context).colorScheme.primary, size: 32),
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
                          child: CircleAvatar(
                            child: Text(employee.name.isEmpty ? '?' : employee.name[0].toUpperCase()),
                          ),
                        ),
                      const SizedBox(height: 8),
                      IconButton(
                        tooltip: 'Cerrar sesión',
                        icon: const Icon(Icons.logout_rounded),
                        onPressed: () => ref.read(authControllerProvider.notifier).logout(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            destinations: [
              for (final d in destinations)
                NavigationRailDestination(icon: Icon(d.icon), label: Text(d.label)),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: child),
        ],
      ),
    );
  }
}
