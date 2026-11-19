import '../../../core/ui/feedback.dart';

typedef Json = Map<String, dynamic>;

/// Texto traducido: translations = { "en": { "name": "…" } }
String? translated(Json? translations, String locale, String field) {
  final values = translations?[locale];
  return values is Map ? values[field] as String? : null;
}

/// Los 9 alérgenos principales (FDA) con su nombre para mostrar.
const allergenLabels = <String, String>{
  'milk': 'Lácteos',
  'eggs': 'Huevo',
  'fish': 'Pescado',
  'shellfish': 'Mariscos',
  'tree_nuts': 'Nueces',
  'peanuts': 'Maní',
  'wheat': 'Trigo / gluten',
  'soybeans': 'Soya',
  'sesame': 'Ajonjolí',
};

class Station {
  const Station({required this.id, required this.name, this.color, required this.isActive});
  final String id;
  final String name;
  final String? color;
  final bool isActive;

  factory Station.fromJson(Json j) => Station(
        id: j['id'] as String,
        name: j['name'] as String,
        color: j['color'] as String?,
        isActive: j['isActive'] as bool? ?? true,
      );
}

class TaxRate {
  const TaxRate({required this.id, required this.name, required this.rate, required this.isDefault});
  final String id;
  final String name;

  /// Fracción: 0.08875 = 8.875 %
  final double rate;
  final bool isDefault;

  factory TaxRate.fromJson(Json j) => TaxRate(
        id: j['id'] as String,
        name: j['name'] as String,
        rate: parseMoney(j['rate']),
        isDefault: j['isDefault'] as bool? ?? false,
      );
}

class ModifierOption {
  const ModifierOption({
    required this.id,
    required this.name,
    this.translations,
    required this.priceAdjustment,
    required this.isDefault,
    required this.isAvailable,
    required this.sortOrder,
  });
  final String id;
  final String name;
  final Json? translations;
  final double priceAdjustment;
  final bool isDefault;
  final bool isAvailable;
  final int sortOrder;

  factory ModifierOption.fromJson(Json j) => ModifierOption(
        id: j['id'] as String,
        name: j['name'] as String,
        translations: j['translations'] as Json?,
        priceAdjustment: parseMoney(j['priceAdjustment']),
        isDefault: j['isDefault'] as bool? ?? false,
        isAvailable: j['isAvailable'] as bool? ?? true,
        sortOrder: j['sortOrder'] as int? ?? 0,
      );
}

class ModifierGroup {
  const ModifierGroup({
    required this.id,
    required this.name,
    this.translations,
    required this.selectionType,
    required this.minSelect,
    required this.maxSelect,
    required this.isActive,
    required this.options,
    required this.productCount,
  });
  final String id;
  final String name;
  final Json? translations;

  /// SINGLE o MULTIPLE
  final String selectionType;
  final int minSelect;
  final int maxSelect;
  final bool isActive;
  final List<ModifierOption> options;
  final int productCount;

  bool get isSingle => selectionType == 'SINGLE';

  String get rulesLabel {
    final required = minSelect > 0;
    if (isSingle) return required ? 'Elige 1 (obligatorio)' : 'Elige 1 (opcional)';
    if (minSelect == maxSelect) return 'Elige $maxSelect';
    return required ? 'Elige de $minSelect a $maxSelect' : 'Hasta $maxSelect';
  }

  factory ModifierGroup.fromJson(Json j) => ModifierGroup(
        id: j['id'] as String,
        name: j['name'] as String,
        translations: j['translations'] as Json?,
        selectionType: j['selectionType'] as String,
        minSelect: j['minSelect'] as int,
        maxSelect: j['maxSelect'] as int,
        isActive: j['isActive'] as bool? ?? true,
        options: ((j['options'] as List?) ?? const [])
            .map((o) => ModifierOption.fromJson(o as Json))
            .toList(),
        productCount: ((j['_count'] as Json?)?['products'] as int?) ?? 0,
      );
}

class Product {
  const Product({
    required this.id,
    required this.categoryId,
    required this.name,
    this.description,
    this.translations,
    required this.price,
    this.imageUrl,
    this.stationId,
    this.taxRateId,
    required this.isActive,
    required this.isAvailable,
    required this.visibleDineIn,
    required this.visibleOnline,
    required this.allergens,
    this.prepTimeMinutes,
    required this.modifierGroupIds,
  });
  final String id;
  final String categoryId;
  final String name;
  final String? description;
  final Json? translations;
  final double price;
  final String? imageUrl;
  final String? stationId;
  final String? taxRateId;
  final bool isActive;
  final bool isAvailable;
  final bool visibleDineIn;
  final bool visibleOnline;
  final List<String> allergens;
  final int? prepTimeMinutes;
  final List<String> modifierGroupIds;

  factory Product.fromJson(Json j) {
    final links = ((j['modifierGroups'] as List?) ?? const []).cast<Json>()
      ..sort((a, b) => (a['sortOrder'] as int? ?? 0).compareTo(b['sortOrder'] as int? ?? 0));
    return Product(
      id: j['id'] as String,
      categoryId: j['categoryId'] as String,
      name: j['name'] as String,
      description: j['description'] as String?,
      translations: j['translations'] as Json?,
      price: parseMoney(j['price']),
      imageUrl: j['imageUrl'] as String?,
      stationId: j['stationId'] as String?,
      taxRateId: j['taxRateId'] as String?,
      isActive: j['isActive'] as bool? ?? true,
      isAvailable: j['isAvailable'] as bool? ?? true,
      visibleDineIn: j['visibleDineIn'] as bool? ?? true,
      visibleOnline: j['visibleOnline'] as bool? ?? true,
      allergens: ((j['allergens'] as List?) ?? const []).cast<String>(),
      prepTimeMinutes: j['prepTimeMinutes'] as int?,
      modifierGroupIds: links.map((l) => l['modifierGroupId'] as String).toList(),
    );
  }
}

class Category {
  const Category({
    required this.id,
    required this.name,
    this.translations,
    this.imageUrl,
    required this.isActive,
    required this.visibleDineIn,
    required this.visibleOnline,
    required this.products,
  });
  final String id;
  final String name;
  final Json? translations;
  final String? imageUrl;
  final bool isActive;
  final bool visibleDineIn;
  final bool visibleOnline;
  final List<Product> products;

  factory Category.fromJson(Json j) => Category(
        id: j['id'] as String,
        name: j['name'] as String,
        translations: j['translations'] as Json?,
        imageUrl: j['imageUrl'] as String?,
        isActive: j['isActive'] as bool? ?? true,
        visibleDineIn: j['visibleDineIn'] as bool? ?? true,
        visibleOnline: j['visibleOnline'] as bool? ?? true,
        products: ((j['products'] as List?) ?? const []).map((p) => Product.fromJson(p as Json)).toList(),
      );
}

/// Todo el catálogo para el panel (GET /menu/admin).
class AdminMenu {
  const AdminMenu({
    required this.categories,
    required this.modifierGroups,
    required this.stations,
    required this.taxRates,
  });
  final List<Category> categories;
  final List<ModifierGroup> modifierGroups;
  final List<Station> stations;
  final List<TaxRate> taxRates;

  factory AdminMenu.fromJson(Json j) => AdminMenu(
        categories: (j['categories'] as List).map((c) => Category.fromJson(c as Json)).toList(),
        modifierGroups: (j['modifierGroups'] as List).map((g) => ModifierGroup.fromJson(g as Json)).toList(),
        stations: (j['stations'] as List).map((s) => Station.fromJson(s as Json)).toList(),
        taxRates: (j['taxRates'] as List).map((t) => TaxRate.fromJson(t as Json)).toList(),
      );
}
