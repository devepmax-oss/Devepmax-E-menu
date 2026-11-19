import 'package:flutter/material.dart';

import 'app_sidebar.dart';

class AppScaffoldShell extends StatelessWidget {
  final Widget child;

  const AppScaffoldShell({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width >= 900;

    if (!isTablet) {
      return Scaffold(
        drawer: const Drawer(child: SafeArea(child: AppSidebar())),
        appBar: AppBar(title: const Text('Restaurant Ops')),
        body: child,
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            const SizedBox(
              width: 280,
              child: AppSidebar(),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}