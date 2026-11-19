import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AppSidebar extends StatelessWidget {
  const AppSidebar({super.key});

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();

    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text(
              'Go Picadera',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
          ),
          _NavItem(
            title: 'Pedidos',
            icon: Icons.receipt_long_outlined,
            selected: location.startsWith('/orders'),
            onTap: () => context.go('/orders'),
          ),
          _NavItem(
            title: 'Menú',
            icon: Icons.restaurant_menu,
            selected: location.startsWith('/menu'),
            onTap: () => context.go('/menu'),
          ),
          _NavItem(
            title: 'Delivery',
            icon: Icons.delivery_dining,
            selected: location.startsWith('/delivery'),
            onTap: () => context.go('/delivery'),
          ),
          _NavItem(
            title: 'Clientes',
            icon: Icons.people_alt_outlined,
            selected: location.startsWith('/customers'),
            onTap: () => context.go('/customers'),
          ),
          _NavItem(
            title: 'Configuración',
            icon: Icons.settings_outlined,
            selected: location.startsWith('/settings'),
            onTap: () => context.go('/settings'),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.title,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      selected: selected,
      selectedTileColor: Colors.teal.withValues(alpha: 0.08),
      leading: Icon(icon),
      title: Text(title),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onTap: onTap,
    );
  }
}
