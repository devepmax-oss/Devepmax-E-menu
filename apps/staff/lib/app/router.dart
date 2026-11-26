import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/auth_controller.dart';
import '../features/admin/screens/devices_screen.dart';
import '../features/billing/screens/billing_screen.dart';
import '../features/admin/screens/employees_screen.dart';
import '../features/admin/screens/settings_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/menu/screens/menu_screen.dart';
import '../features/menu/screens/menu_setup_screen.dart';
import '../features/menu/screens/modifier_groups_screen.dart';
import '../features/orders/screens/orders_screen.dart';
import '../features/pos/screens/pos_screen.dart';
import '../features/promotions/screens/promotions_screen.dart';
import '../features/coupons/screens/coupons_screen.dart';
import '../features/customers/screens/customers_screen.dart';
import '../features/inventory/screens/inventory_screen.dart';
import '../features/timeclock/screens/attendance_screen.dart';
import '../features/reports/screens/reports_screen.dart';
import '../features/shell/admin_shell.dart';
import '../features/tables/screens/tables_screen.dart';
import '../features/tables/screens/waiter_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authChanges = ValueNotifier<int>(0);
  ref.listen(authControllerProvider, (_, __) => authChanges.value++);
  ref.onDispose(authChanges.dispose);

  return GoRouter(
    initialLocation: '/menu',
    refreshListenable: authChanges,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final location = state.matchedLocation;
      if (auth.isLoading && !auth.hasValue) return location == '/splash' ? null : '/splash';

      final loggedIn = auth.value != null;
      if (!loggedIn) return location == '/login' ? null : '/login';
      // Meseros (atienden mesas pero no cobran) entran a sus mesas; quien atiende órdenes, al
      // tablero; el resto, al menú.
      if (location == '/login' || location == '/splash') {
        final employee = auth.value!.employee;
        if (employee.can('tables.operate') && !employee.can('payments.take')) return '/waiter';
        if (employee.can('orders.create')) return '/orders';
        return employee.can('tables.operate') ? '/tables' : '/menu';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const _SplashScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      ShellRoute(
        builder: (context, state, child) => AdminShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(path: '/orders', builder: (_, __) => const OrdersScreen()),
          GoRoute(path: '/tables', builder: (_, __) => const TablesScreen()),
          GoRoute(path: '/waiter', builder: (_, __) => const WaiterScreen()),
          GoRoute(
            path: '/pos',
            builder: (_, state) => NewOrderScreen(key: ValueKey(state.uri.toString()), tableId: state.uri.queryParameters['table']),
          ),
          GoRoute(
            path: '/billing',
            builder: (_, state) => BillingScreen(
              key: ValueKey(state.uri.toString()),
              tableId: state.uri.queryParameters['table'],
              billId: state.uri.queryParameters['bill'],
            ),
          ),
          GoRoute(path: '/reports', builder: (_, __) => const ReportsScreen()),
          GoRoute(path: '/customers', builder: (_, __) => const CustomersScreen()),
          GoRoute(path: '/menu', builder: (_, __) => const MenuScreen()),
          GoRoute(path: '/modifiers', builder: (_, __) => const ModifierGroupsScreen()),
          GoRoute(path: '/menu-setup', builder: (_, __) => const MenuSetupScreen()),
          GoRoute(path: '/promotions', builder: (_, __) => const PromotionsScreen()),
          GoRoute(path: '/coupons', builder: (_, __) => const CouponsScreen()),
          GoRoute(path: '/inventory', builder: (_, __) => const InventoryScreen()),
          GoRoute(path: '/employees', builder: (_, __) => const EmployeesScreen()),
          GoRoute(path: '/attendance', builder: (_, __) => const AttendanceScreen()),
          GoRoute(path: '/devices', builder: (_, __) => const DevicesScreen()),
          GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
        ],
      ),
    ],
  );
});

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}
