import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';

class _Destination {
  const _Destination(this.path, this.label, this.icon);
  final String path;
  final String label;
  final IconData icon;
}

const _destinations = [
  _Destination('/menu', 'Menú', Icons.restaurant_menu_rounded),
  _Destination('/modifiers', 'Modificadores', Icons.tune_rounded),
  _Destination('/menu-setup', 'Cocina e impuestos', Icons.soup_kitchen_rounded),
];

/// Marco del panel: barra lateral de navegación + contenido.
class AdminShell extends ConsumerWidget {
  const AdminShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final employee = ref.watch(authControllerProvider).value?.employee;
    final selected = _destinations.indexWhere((d) => location.startsWith(d.path));

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: selected < 0 ? 0 : selected,
            labelType: NavigationRailLabelType.all,
            onDestinationSelected: (i) => context.go(_destinations[i].path),
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
              for (final d in _destinations)
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
