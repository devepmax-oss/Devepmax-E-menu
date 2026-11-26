import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/ui/feedback.dart';

typedef IJson = Map<String, dynamic>;

double _d(Object? v) => parseMoney(v);
double? _dn(Object? v) => v == null ? null : parseMoney(v);

/// Unidades con su nombre corto.
const unitLabels = <String, String>{
  'unit': 'unidad',
  'g': 'g',
  'kg': 'kg',
  'oz': 'oz',
  'lb': 'lb',
  'ml': 'ml',
  'l': 'L',
  'fl_oz': 'fl oz',
};

/// 1500 → "1,500"; 0.25 → "0.25".
String qty(double v) {
  final rounded = (v * 1000).round() / 1000;
  if (rounded == rounded.roundToDouble()) return rounded.toStringAsFixed(0).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  return rounded.toString();
}

class InventorySummary {
  const InventorySummary({
    required this.enabled,
    required this.autoSoldOut,
    required this.items,
    required this.low,
    required this.value,
    required this.used7,
    required this.waste7,
    required this.soldOut,
  });
  final bool enabled;
  final bool autoSoldOut;
  final int items;
  final int low;
  final double value;
  final double used7;
  final double waste7;
  final int soldOut;

  factory InventorySummary.fromJson(IJson j) => InventorySummary(
        enabled: j['enabled'] as bool? ?? false,
        autoSoldOut: j['autoSoldOut'] as bool? ?? true,
        items: (j['items'] as num?)?.toInt() ?? 0,
        low: (j['low'] as num?)?.toInt() ?? 0,
        value: _d(j['value']),
        used7: _d(j['usedLast7Days']),
        waste7: _d(j['wasteLast7Days']),
        soldOut: (j['soldOutByStock'] as num?)?.toInt() ?? 0,
      );
}

class InventoryItem {
  const InventoryItem({
    required this.id,
    required this.name,
    required this.unit,
    required this.onHand,
    this.minLevel,
    required this.low,
    required this.costPerUnit,
    required this.value,
    this.supplierId,
    this.supplierName,
    this.sku,
    required this.isActive,
    required this.usedIn,
  });
  final String id;
  final String name;
  final String unit;
  final double onHand;
  final double? minLevel;
  final bool low;
  final double costPerUnit;
  final double value;
  final String? supplierId;
  final String? supplierName;
  final String? sku;
  final bool isActive;
  final int usedIn;

  String get unitLabel => unitLabels[unit] ?? unit;

  factory InventoryItem.fromJson(IJson j) => InventoryItem(
        id: j['id'] as String,
        name: j['name'] as String,
        unit: j['unit'] as String,
        onHand: _d(j['onHand']),
        minLevel: _dn(j['minLevel']),
        low: j['low'] as bool? ?? false,
        costPerUnit: _d(j['costPerUnit']),
        value: _d(j['value']),
        supplierId: (j['supplier'] as IJson?)?['id'] as String?,
        supplierName: (j['supplier'] as IJson?)?['name'] as String?,
        sku: j['sku'] as String?,
        isActive: j['isActive'] as bool? ?? true,
        usedIn: (j['usedIn'] as num?)?.toInt() ?? 0,
      );
}

class Supplier {
  const Supplier({required this.id, required this.name, this.contactName, this.phone, this.email, this.notes, required this.isActive, required this.items, required this.receipts});
  final String id;
  final String name;
  final String? contactName;
  final String? phone;
  final String? email;
  final String? notes;
  final bool isActive;
  final int items;
  final int receipts;

  factory Supplier.fromJson(IJson j) => Supplier(
        id: j['id'] as String,
        name: j['name'] as String,
        contactName: j['contactName'] as String?,
        phone: j['phone'] as String?,
        email: j['email'] as String?,
        notes: j['notes'] as String?,
        isActive: j['isActive'] as bool? ?? true,
        items: (j['items'] as num?)?.toInt() ?? 0,
        receipts: (j['receipts'] as num?)?.toInt() ?? 0,
      );
}

class RecipeLineView {
  const RecipeLineView({required this.itemId, required this.item, required this.unit, required this.quantity, required this.cost});
  final String itemId;
  final String item;
  final String unit;
  final double quantity;
  final double cost;
}

class PlateCost {
  const PlateCost({
    required this.productId,
    required this.name,
    required this.category,
    required this.price,
    required this.isAvailable,
    required this.soldOutByStock,
    required this.lines,
    required this.cost,
    required this.margin,
    this.foodCostPct,
  });
  final String productId;
  final String name;
  final String category;
  final double price;
  final bool isAvailable;
  final bool soldOutByStock;
  final List<RecipeLineView> lines;
  final double cost;
  final double margin;
  final double? foodCostPct;

  factory PlateCost.fromJson(IJson j) => PlateCost(
        productId: j['productId'] as String,
        name: j['name'] as String,
        category: j['category'] as String? ?? '',
        price: _d(j['price']),
        isAvailable: j['isAvailable'] as bool? ?? true,
        soldOutByStock: j['soldOutByStock'] as bool? ?? false,
        lines: [
          for (final l in j['lines'] as List? ?? const [])
            RecipeLineView(
              itemId: (l as IJson)['itemId'] as String,
              item: l['item'] as String,
              unit: l['unit'] as String,
              quantity: _d(l['quantity']),
              cost: _d(l['cost']),
            ),
        ],
        cost: _d(j['cost']),
        margin: _d(j['margin']),
        foodCostPct: (j['foodCostPct'] as num?)?.toDouble(),
      );
}

class StockMove {
  const StockMove({required this.id, required this.item, required this.unit, required this.type, required this.quantity, required this.cost, this.reason, this.employee, required this.createdAt});
  final String id;
  final String item;
  final String unit;
  final String type;
  final double quantity;
  final double cost;
  final String? reason;
  final String? employee;
  final DateTime createdAt;

  factory StockMove.fromJson(IJson j) => StockMove(
        id: j['id'] as String,
        item: j['item'] as String,
        unit: j['unit'] as String,
        type: j['type'] as String,
        quantity: _d(j['quantity']),
        cost: _d(j['cost']),
        reason: j['reason'] as String?,
        employee: j['employee'] as String?,
        createdAt: DateTime.parse(j['createdAt'] as String).toLocal(),
      );
}

const moveLabels = <String, String>{
  'SALE': 'Venta',
  'RECEIPT': 'Entrada',
  'COUNT': 'Conteo',
  'WASTE': 'Merma',
  'ADJUST': 'Ajuste',
};

final inventoryApiProvider = Provider<InventoryApi>((ref) => InventoryApi(ref.watch(dioProvider)));
final inventorySummaryProvider = FutureProvider.autoDispose<InventorySummary>((ref) => ref.watch(inventoryApiProvider).summary());
final inventoryItemsProvider = FutureProvider.autoDispose<List<InventoryItem>>((ref) => ref.watch(inventoryApiProvider).items());
final suppliersProvider = FutureProvider.autoDispose<List<Supplier>>((ref) => ref.watch(inventoryApiProvider).suppliers());
final recipesProvider = FutureProvider.autoDispose<List<PlateCost>>((ref) => ref.watch(inventoryApiProvider).recipes());
final movementsProvider = FutureProvider.autoDispose.family<List<StockMove>, String?>((ref, itemId) => ref.watch(inventoryApiProvider).movements(itemId: itemId));

class InventoryApi {
  InventoryApi(this._dio);
  final Dio _dio;

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } catch (error) {
      throw ApiException.from(error);
    }
  }

  Future<List<T>> _list<T>(String path, T Function(IJson) parse, [Map<String, dynamic>? query]) => _call(() async {
        final r = await _dio.get<List<dynamic>>(path, queryParameters: query);
        return [for (final x in r.data!) parse(x as IJson)];
      });

  Future<InventorySummary> summary() => _call(() async => InventorySummary.fromJson((await _dio.get<IJson>('/inventory/summary')).data!));
  Future<void> settings({bool? enabled, bool? autoSoldOut}) =>
      _call(() => _dio.patch<IJson>('/inventory/settings', data: {if (enabled != null) 'enabled': enabled, if (autoSoldOut != null) 'autoSoldOut': autoSoldOut}));

  Future<List<InventoryItem>> items() => _list('/inventory/items', InventoryItem.fromJson);
  Future<void> saveItem(String? id, IJson data) => _call(() => id == null ? _dio.post<IJson>('/inventory/items', data: data) : _dio.patch<IJson>('/inventory/items/$id', data: data));
  Future<void> removeItem(String id) => _call(() => _dio.delete<void>('/inventory/items/$id'));
  Future<void> count(String id, double onHand, String? reason) =>
      _call(() => _dio.post<IJson>('/inventory/items/$id/count', data: {'onHand': onHand, if (reason != null && reason.isNotEmpty) 'reason': reason}));
  Future<void> waste(String id, double quantity, String reason) => _call(() => _dio.post<IJson>('/inventory/items/$id/waste', data: {'quantity': quantity, 'reason': reason}));

  Future<List<StockMove>> movements({String? itemId}) => _list('/inventory/movements', StockMove.fromJson, {if (itemId != null) 'itemId': itemId});

  Future<void> receive({String? supplierId, String? reference, required List<IJson> lines}) => _call(() => _dio.post<IJson>('/inventory/receipts', data: {
        if (supplierId != null) 'supplierId': supplierId,
        if (reference != null && reference.trim().isNotEmpty) 'reference': reference.trim(),
        'lines': lines,
      }));

  Future<List<Supplier>> suppliers() => _list('/inventory/suppliers', Supplier.fromJson);
  Future<void> saveSupplier(String? id, IJson data) =>
      _call(() => id == null ? _dio.post<IJson>('/inventory/suppliers', data: data) : _dio.patch<IJson>('/inventory/suppliers/$id', data: data));
  Future<void> removeSupplier(String id) => _call(() => _dio.delete<void>('/inventory/suppliers/$id'));

  Future<List<PlateCost>> recipes() => _list('/inventory/recipes', PlateCost.fromJson);
  Future<void> saveRecipe(String productId, List<IJson> lines) => _call(() => _dio.put<IJson>('/inventory/recipes/$productId', data: {'lines': lines}));
}
