import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/auth_controller.dart';
import '../features/auth/login_screen.dart';
import '../features/menu/screens/menu_screen.dart';
import '../features/menu/screens/menu_setup_screen.dart';
import '../features/menu/screens/modifier_groups_screen.dart';
import '../features/shell/admin_shell.dart';

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
      if (location == '/login' || location == '/splash') return '/menu';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const _SplashScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      ShellRoute(
        builder: (context, state, child) => AdminShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(path: '/menu', builder: (_, __) => const MenuScreen()),
          GoRoute(path: '/modifiers', builder: (_, __) => const ModifierGroupsScreen()),
          GoRoute(path: '/menu-setup', builder: (_, __) => const MenuSetupScreen()),
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
