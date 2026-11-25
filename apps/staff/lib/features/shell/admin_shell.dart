import 'package:devepmax_ui/devepmax_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../admin/data/admin_api.dart';
import '../tables/service_call_alerts.dart';

class _Destination {
  const _Destination(this.path, this.label, this.icon, this.permission);
  final String path;
  final String label;
  final IconData icon;

  /// Permiso necesario para ver la sección.
  final String permission;
}

const _allDestinations = [
  _Destination('/orders', 'Órdenes', Icons.receipt_long_rounded, 'orders.create'),
  _Destination('/tables', 'Mesas', Icons.table_restaurant_rounded, 'tables.operate'),
  _Destination('/billing', 'Caja', Icons.point_of_sale_rounded, 'payments.take'),
  _Destination('/waiter', 'Mis mesas', Icons.room_service_rounded, 'tables.operate'),
  _Destination('/reports', 'Cierre del día', Icons.insights_rounded, 'reports.view'),
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
    // Un mesero (no cobra) tiene sus mesas como primera opción.
    if (employee != null && employee.can('tables.operate') && !employee.can('payments.take')) {
      final waiter = destinations.indexWhere((d) => d.path == '/waiter');
      if (waiter > 0) destinations.insert(0, destinations.removeAt(waiter));
    }
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
    final content = (employee?.can('tables.operate') ?? false) ? ServiceCallAlerts(child: child) : child;

    // Teléfono: barra abajo con lo más usado y "Más" para el resto.
    if (MediaQuery.sizeOf(context).width < 700) {
      return _CompactShell(
        destinations: destinations,
        selected: selected,
        employeeName: employee?.name ?? '',
        roleName: employee?.roleName ?? '',
        child: content,
      );
    }
    final initial = (employee?.name.isNotEmpty ?? false) ? employee!.name[0].toUpperCase() : '?';

    return Scaffold(
      body: Row(
        children: [
          // Si la pantalla no es tan alta, la barra se desplaza en vez de cortarse.
          LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: NavigationRail(
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
                          padding: const EdgeInsets.symmetric(vertical: 2),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          VerticalDivider(width: 1, color: t.line),
          // Quien atiende mesas recibe los llamados de las tablets en cualquier pantalla.
          Expanded(child: content),
        ],
      ),
    );
  }
}

/// Marco para teléfonos: hasta 4 secciones abajo (las de operación primero) y "Más".
class _CompactShell extends ConsumerWidget {
  const _CompactShell({
    required this.destinations,
    required this.selected,
    required this.employeeName,
    required this.roleName,
    required this.child,
  });

  final List<_Destination> destinations;
  final int selected;
  final String employeeName;
  final String roleName;
  final Widget child;

  static const _priority = ['/orders', '/tables', '/billing', '/menu'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final primary = [
      for (final path in _priority) ...destinations.where((d) => d.path == path),
    ].take(destinations.length > 4 ? 3 : 4).toList();
    final rest = destinations.where((d) => !primary.contains(d)).toList();
    final current = selected >= 0 ? destinations[selected] : null;
    final index = current == null ? -1 : primary.indexOf(current);
    final showMore = rest.isNotEmpty;

    Future<void> openMore() => showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          builder: (sheet) => SafeArea(
            child: ListView(shrinkWrap: true, children: [
              ListTile(
                leading: const Icon(Icons.person_rounded),
                title: Text(employeeName),
                subtitle: Text(roleName),
              ),
              const Divider(),
              for (final d in rest)
                ListTile(
                  leading: Icon(d.icon),
                  title: Text(d.label),
                  selected: d == current,
                  onTap: () {
                    Navigator.pop(sheet);
                    context.go(d.path);
                  },
                ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.logout_rounded),
                title: const Text('Cerrar sesión'),
                onTap: () {
                  Navigator.pop(sheet);
                  ref.read(authControllerProvider.notifier).logout();
                },
              ),
            ]),
          ),
        );

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index >= 0 ? index : (showMore ? primary.length : 0),
        onDestinationSelected: (i) {
          if (i < primary.length) {
            context.go(primary[i].path);
          } else {
            openMore();
          }
        },
        destinations: [
          for (final d in primary) NavigationDestination(icon: Icon(d.icon), label: d.label),
          if (showMore) const NavigationDestination(icon: Icon(Icons.menu_rounded), label: 'Más'),
        ],
      ),
    );
  }
}
