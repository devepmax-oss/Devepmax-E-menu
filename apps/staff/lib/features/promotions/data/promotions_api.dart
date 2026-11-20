import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/ui/feedback.dart';
import '../../menu/data/menu_models.dart' show Json, Product;

const promotionTypeLabels = <String, String>{
  'PERCENT_OFF': '% de descuento',
  'AMOUNT_OFF': '\$ de descuento',
  'BUY_X_GET_Y': 'Lleva X, paga Y',
  'COMBO_PRICE': 'Combo a precio fijo',
};

class ComboSlot {
  ComboSlot({required this.name, required this.quantity, Set<String>? productIds, Set<String>? categoryIds})
      : productIds = productIds ?? {},
        categoryIds = categoryIds ?? {};
  String name;
  int quantity;
  final Set<String> productIds;
  final Set<String> categoryIds;

  factory ComboSlot.fromJson(Json j) => ComboSlot(
        name: j['name'] as String,
        quantity: j['quantity'] as int,
        productIds: ((j['productIds'] as List?) ?? const []).cast<String>().toSet(),
        categoryIds: ((j['categoryIds'] as List?) ?? const []).cast<String>().toSet(),
      );

  Json toJson() => {
        'name': name,
        'quantity': quantity,
        'productIds': productIds.toList(),
        'categoryIds': categoryIds.toList(),
      };
}

class Promotion {
  const Promotion({
    required this.id,
    required this.name,
    this.description,
    required this.type,
    this.value,
    this.buyQuantity,
    this.getQuantity,
    this.comboPrice,
    required this.appliesDineIn,
    required this.appliesOnline,
    this.startsAt,
    this.endsAt,
    required this.isActive,
    required this.state,
    required this.productIds,
    required this.categoryIds,
    required this.comboSlots,
    required this.timesApplied,
  });

  final String id;
  final String name;
  final String? description;
  final String type;
  final double? value;
  final int? buyQuantity;
  final int? getQuantity;
  final double? comboPrice;
  final bool appliesDineIn;
  final bool appliesOnline;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final bool isActive;

  /// ACTIVE, SCHEDULED, EXPIRED o INACTIVE
  final String state;
  final List<String> productIds;
  final List<String> categoryIds;
  final List<ComboSlot> comboSlots;
  final int timesApplied;

  factory Promotion.fromJson(Json j) => Promotion(
        id: j['id'] as String,
        name: j['name'] as String,
        description: j['description'] as String?,
        type: j['type'] as String,
        value: j['value'] == null ? null : parseMoney(j['value']),
        buyQuantity: j['buyQuantity'] as int?,
        getQuantity: j['getQuantity'] as int?,
        comboPrice: j['comboPrice'] == null ? null : parseMoney(j['comboPrice']),
        appliesDineIn: j['appliesDineIn'] as bool? ?? true,
        appliesOnline: j['appliesOnline'] as bool? ?? true,
        startsAt: DateTime.tryParse(j['startsAt'] as String? ?? '')?.toLocal(),
        endsAt: DateTime.tryParse(j['endsAt'] as String? ?? '')?.toLocal(),
        isActive: j['isActive'] as bool? ?? true,
        state: j['state'] as String? ?? 'ACTIVE',
        productIds: ((j['productIds'] as List?) ?? const []).cast<String>(),
        categoryIds: ((j['categoryIds'] as List?) ?? const []).cast<String>(),
        comboSlots: ((j['comboSlots'] as List?) ?? const []).map((s) => ComboSlot.fromJson(s as Json)).toList(),
        timesApplied: j['timesApplied'] as int? ?? 0,
      );
}

/// Etiqueta corta para poner sobre un producto: "2x1", "-10%", "-$2.00" o "Combo".
String promotionBadge(Promotion p) {
  switch (p.type) {
    case 'PERCENT_OFF':
      return '-${p.value?.toStringAsFixed(0)}%';
    case 'AMOUNT_OFF':
      return '-${formatMoney(p.value ?? 0)}';
    case 'BUY_X_GET_Y':
      final buy = p.buyQuantity ?? 1;
      return '${buy + (p.getQuantity ?? 1)}x$buy';
    case 'COMBO_PRICE':
      return 'Combo';
  }
  return 'Promo';
}

/// Promociones vigentes ahora mismo que tocan a un producto: directamente,
/// por su categoría o como parte de un combo.
List<Promotion> activePromotionsFor(List<Promotion> promotions, Product product) => promotions
    .where((p) =>
        p.state == 'ACTIVE' &&
        (p.productIds.contains(product.id) ||
            p.categoryIds.contains(product.categoryId) ||
            p.comboSlots.any((s) => s.productIds.contains(product.id) || s.categoryIds.contains(product.categoryId))))
    .toList();

final promotionsApiProvider = Provider<PromotionsApi>((ref) => PromotionsApi(ref.watch(dioProvider)));
final promotionsProvider = FutureProvider<List<Promotion>>((ref) => ref.watch(promotionsApiProvider).list());

class PromotionsApi {
  PromotionsApi(this._dio);
  final Dio _dio;

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } catch (error) {
      throw ApiException.from(error);
    }
  }

  Future<List<Promotion>> list() => _call(() async {
        final response = await _dio.get<List<dynamic>>('/promotions');
        return response.data!.map((p) => Promotion.fromJson(p as Json)).toList();
      });

  Future<void> create(Json data) => _call(() => _dio.post('/promotions', data: data));
  Future<void> update(String id, Json data) => _call(() => _dio.patch('/promotions/$id', data: data));
  Future<void> delete(String id) => _call(() => _dio.delete('/promotions/$id'));
}
