import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/menu_api.dart';
import 'data/menu_models.dart';

final adminMenuProvider = AsyncNotifierProvider<AdminMenuController, AdminMenu>(AdminMenuController.new);

/// Catálogo completo del panel. Cada cambio se envía al backend y luego se recarga.
class AdminMenuController extends AsyncNotifier<AdminMenu> {
  MenuApi get api => ref.read(menuApiProvider);

  @override
  Future<AdminMenu> build() => ref.read(menuApiProvider).fetchAdmin();

  /// Ejecuta un cambio y recarga el catálogo. Los errores se propagan para mostrarlos.
  Future<T> mutate<T>(Future<T> Function(MenuApi api) action) async {
    final result = await action(api);
    await reload();
    return result;
  }

  Future<void> reload() async {
    state = AsyncData(await api.fetchAdmin());
  }
}
