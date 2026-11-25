import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/device_session.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/realtime.dart';

typedef Json = Map<String, dynamic>;

class MenuOption {
  const MenuOption({required this.id, required this.name, required this.price, required this.isDefault, required this.isAvailable});
  final String id;
  final String name;
  final double price;
  final bool isDefault;
  final bool isAvailable;

  factory MenuOption.fromJson(Json j, [String lang = 'es']) => MenuOption(
        id: j['id'] as String,
        name: translated(j['translations'], lang, 'name', j['name'] as String),
        price: parseMoney(j['priceAdjustment']),
        isDefault: j['isDefault'] as bool? ?? false,
        isAvailable: j['isAvailable'] as bool? ?? true,
      );
}

class ModifierGroup {
  const ModifierGroup({
    required this.id,
    required this.name,
    required this.single,
    required this.minSelect,
    this.maxSelect,
    required this.options,
  });
  final String id;
  final String name;
  final bool single;
  final int minSelect;
  final int? maxSelect;
  final List<MenuOption> options;

  /// Máximo de opciones (null = sin límite).
  int? get max => single ? 1 : maxSelect;
  bool get required => minSelect > 0;

  String rule([String lang = 'es']) {
    final m = max;
    final en = lang == 'en';
    if (minSelect > 0 && m == minSelect) return en ? 'Choose $minSelect' : 'Elige $minSelect';
    if (minSelect > 0) {
      return en
          ? 'Choose at least $minSelect${m != null ? ' (up to $m)' : ''}'
          : 'Elige al menos $minSelect${m != null ? ' (hasta $m)' : ''}';
    }
    if (en) return m != null ? 'Optional · up to $m' : 'Optional';
    return m != null ? 'Opcional · hasta $m' : 'Opcional';
  }

  factory ModifierGroup.fromJson(Json j, [String lang = 'es']) => ModifierGroup(
        id: j['id'] as String,
        name: translated(j['translations'], lang, 'name', j['name'] as String),
        single: j['selectionType'] == 'SINGLE',
        minSelect: (j['minSelect'] as num?)?.toInt() ?? 0,
        maxSelect: (j['maxSelect'] as num?)?.toInt(),
        options: [for (final o in j['options'] as List? ?? const []) MenuOption.fromJson(o as Json, lang)],
      );
}

class MenuProduct {
  const MenuProduct({
    required this.id,
    required this.name,
    this.description,
    required this.price,
    this.imageUrl,
    required this.isAvailable,
    required this.allergens,
    this.prepTimeMinutes,
    required this.groups,
  });
  final String id;
  final String name;
  final String? description;
  final double price;
  final String? imageUrl;
  final bool isAvailable;
  final List<String> allergens;
  final int? prepTimeMinutes;
  final List<ModifierGroup> groups;

  factory MenuProduct.fromJson(Json j, [String lang = 'es']) {
    final description = translated(j['translations'], lang, 'description', (j['description'] as String?)?.trim() ?? '');
    return MenuProduct(
        id: j['id'] as String,
        name: translated(j['translations'], lang, 'name', j['name'] as String),
        description: description.isEmpty ? null : description,
        price: parseMoney(j['price']),
        imageUrl: j['imageUrl'] as String?,
        isAvailable: j['isAvailable'] as bool? ?? true,
        allergens: [for (final a in j['allergens'] as List? ?? const []) '$a'],
        prepTimeMinutes: (j['prepTimeMinutes'] as num?)?.toInt(),
        groups: [for (final g in j['modifierGroups'] as List? ?? const []) ModifierGroup.fromJson(g as Json, lang)],
      );
  }
}

class MenuCategory {
  const MenuCategory({required this.id, required this.name, this.imageUrl, required this.products});
  final String id;
  final String name;
  final String? imageUrl;
  final List<MenuProduct> products;

  factory MenuCategory.fromJson(Json j, [String lang = 'es']) => MenuCategory(
        id: j['id'] as String,
        name: translated(j['translations'], lang, 'name', j['name'] as String),
        imageUrl: j['imageUrl'] as String?,
        products: [for (final p in j['products'] as List? ?? const []) MenuProduct.fromJson(p as Json, lang)],
      );
}

class Promotion {
  const Promotion({
    required this.id,
    required this.name,
    this.description,
    required this.type,
    required this.value,
    this.buyQuantity,
    this.getQuantity,
    required this.productIds,
    required this.categoryIds,
  });
  final String id;
  final String name;
  final String? description;
  final String type;
  final double value;
  final int? buyQuantity;
  final int? getQuantity;
  final List<String> productIds;
  final List<String> categoryIds;

  /// Etiqueta corta para la foto: 2x1, −15%, −$2, Combo.
  String get badge => switch (type) {
        'BUY_X_GET_Y' => '${(buyQuantity ?? 1) + (getQuantity ?? 1)}x${buyQuantity ?? 1}',
        'PERCENT_OFF' => '−${value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 1)}%',
        'AMOUNT_OFF' => '−${formatMoney(value).replaceAll('.00', '')}',
        _ => 'Combo',
      };

  factory Promotion.fromJson(Json j, [String lang = 'es']) => Promotion(
        id: j['id'] as String,
        name: translated(j['translations'], lang, 'name', j['name'] as String),
        description: (j['description'] as String?) == null ? null : translated(j['translations'], lang, 'description', j['description'] as String),
        type: j['type'] as String,
        value: parseMoney(j['value']),
        buyQuantity: (j['buyQuantity'] as num?)?.toInt(),
        getQuantity: (j['getQuantity'] as num?)?.toInt(),
        productIds: [for (final p in j['productIds'] as List? ?? const []) '$p'],
        categoryIds: [for (final c in j['categoryIds'] as List? ?? const []) '$c'],
      );
}

class MenuData {
  const MenuData({required this.categories, required this.promotions});
  final List<MenuCategory> categories;
  final List<Promotion> promotions;

  /// Promociones que aplican a un producto (por producto o por su categoría; los combos no).
  List<Promotion> promotionsFor(MenuCategory category, MenuProduct product) => [
        for (final p in promotions)
          if (p.type != 'COMBO_PRICE' && (p.productIds.contains(product.id) || p.categoryIds.contains(category.id))) p,
      ];
}

/// Marca del restaurante (logo, colores, tipografía).
final brandProvider = FutureProvider<Json?>((ref) async {
  try {
    return (await ref.watch(dioProvider).get<Json>('/settings/public')).data;
  } catch (_) {
    return null;
  }
});

/// Menú de salón + promociones. Se recarga si cambia la disponibilidad o al reconectar.
final menuProvider = AsyncNotifierProvider<MenuController, MenuData>(MenuController.new);

class MenuController extends AsyncNotifier<MenuData> {
  Timer? _debounce;

  /// Lo último que mandó el servidor: al cambiar de idioma se vuelve a armar sin pedirlo otra vez.
  Json? _menu;
  List<dynamic>? _promotions;
  String? _token;

  @override
  Future<MenuData> build() async {
    // Si se vuelve a vincular (otro token o servidor), se carga de nuevo.
    final token = ref.watch(deviceSessionProvider.select((s) => s.value?.token));
    final lang = ref.watch(languageProvider);
    final sub = ref.read(realtimeProvider.notifier).events.listen((e) {
      if (e.name == 'ready' || e.name == 'product.availability' || e.name == 'option.availability') {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 500), reload);
      }
    });
    ref.onDispose(() {
      sub.cancel();
      _debounce?.cancel();
    });
    if (_menu == null || token != _token) {
      _token = token;
      await _fetch();
    }
    return _build(lang);
  }

  Future<void> _fetch() async {
    final dio = ref.read(dioProvider);
    final promosRequest = _fetchPromotions();
    _menu = await apiCall(() async => (await dio.get<Json>('/menu', queryParameters: {'channel': 'dine_in'})).data!);
    _promotions = await promosRequest;
  }

  MenuData _build(String lang) => MenuData(
        categories: [for (final c in _menu?['categories'] as List? ?? const []) MenuCategory.fromJson(c as Json, lang)],
        promotions: [for (final p in _promotions ?? const []) Promotion.fromJson(p as Json, lang)],
      );

  /// Si las promociones fallan, el menú se muestra igual (sin etiquetas).
  Future<List<dynamic>> _fetchPromotions() async {
    try {
      final response = await ref.read(dioProvider).get<List<dynamic>>('/promotions/public', queryParameters: {'channel': 'dine_in'});
      return response.data ?? const [];
    } catch (_) {
      return const [];
    }
  }

  Future<void> reload() async {
    try {
      await _fetch();
      state = AsyncData(_build(ref.read(languageProvider)));
    } catch (error, stack) {
      if (!state.hasValue) state = AsyncError(error, stack);
    }
  }
}
