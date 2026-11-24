import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/device_session.dart';
import '../../core/format.dart';
import 'menu_data.dart';

/// Una línea del pedido que el cliente está armando.
class CartLine {
  const CartLine({
    required this.key,
    required this.product,
    required this.optionIds,
    required this.optionNames,
    required this.optionsTotal,
    required this.quantity,
    this.notes,
  });

  final String key;
  final MenuProduct product;
  final List<String> optionIds;
  final List<String> optionNames;
  final double optionsTotal;
  final int quantity;
  final String? notes;

  double get unitPrice => product.price + optionsTotal;
  double get total => unitPrice * quantity;

  CartLine withQuantity(int q) => CartLine(
        key: key,
        product: product,
        optionIds: optionIds,
        optionNames: optionNames,
        optionsTotal: optionsTotal,
        quantity: q,
        notes: notes,
      );

  Json toOrderLine() => {
        'productId': product.id,
        'quantity': quantity,
        'optionIds': optionIds,
        if (notes != null && notes!.isNotEmpty) 'notes': notes,
      };
}

final cartProvider = NotifierProvider<CartController, List<CartLine>>(CartController.new);

class CartController extends Notifier<List<CartLine>> {
  final _random = Random();

  @override
  List<CartLine> build() => const [];

  int get count => state.fold(0, (sum, l) => sum + l.quantity);

  /// Si ya hay una línea igual (mismas opciones y nota), se suma la cantidad.
  void add(MenuProduct product, List<MenuOption> options, int quantity, String? notes) {
    final ids = [for (final o in options) o.id]..sort();
    final note = notes?.trim();
    final same = state.indexWhere((l) =>
        l.product.id == product.id && l.optionIds.join(',') == ids.join(',') && (l.notes ?? '') == (note ?? ''));
    if (same >= 0) {
      final line = state[same];
      state = [...state]..[same] = line.withQuantity((line.quantity + quantity).clamp(1, 99));
      return;
    }
    state = [
      ...state,
      CartLine(
        key: '${DateTime.now().microsecondsSinceEpoch}${_random.nextInt(9999)}',
        product: product,
        optionIds: ids,
        optionNames: [for (final o in options) o.name],
        optionsTotal: options.fold<double>(0, (sum, o) => sum + o.price),
        quantity: quantity,
        notes: note == null || note.isEmpty ? null : note,
      ),
    ];
  }

  void setQuantity(String key, int quantity) {
    if (quantity <= 0) {
      remove(key);
      return;
    }
    state = [for (final l in state) l.key == key ? l.withQuantity(quantity.clamp(1, 99)) : l];
  }

  void remove(String key) => state = state.where((l) => l.key != key).toList();
  void clear() => state = const [];
}

/// Totales calculados por el servidor (precios, promociones e impuestos reales).
class Quote {
  const Quote({required this.subtotal, required this.discountTotal, required this.taxTotal, required this.total, required this.promotions});
  final double subtotal;
  final double discountTotal;
  final double taxTotal;
  final double total;
  final List<({String name, double amount})> promotions;

  factory Quote.fromJson(Json j) {
    final totals = j['totals'] as Json? ?? const {};
    return Quote(
      subtotal: parseMoney(totals['subtotal']),
      discountTotal: parseMoney(totals['discountTotal']),
      taxTotal: parseMoney(totals['taxTotal']),
      total: parseMoney(totals['total']),
      promotions: [
        for (final p in j['promotions'] as List? ?? const [])
          (name: (p as Json)['name'] as String? ?? 'Promoción', amount: parseMoney(p['amount'])),
      ],
    );
  }
}

final quoteProvider = FutureProvider.autoDispose<Quote?>((ref) async {
  final lines = ref.watch(cartProvider);
  if (lines.isEmpty) return null;
  var cancelled = false;
  ref.onDispose(() => cancelled = true);
  // Espera a que el cliente termine de tocar + / − antes de preguntar.
  await Future<void>.delayed(const Duration(milliseconds: 350));
  if (cancelled) return null;
  final dio = ref.read(dioProvider);
  final data = await apiCall(() async =>
      (await dio.post<Json>('/orders/quote', data: {'items': [for (final l in lines) l.toOrderLine()]})).data!);
  return Quote.fromJson(data);
});

/// Envía el pedido. El identificador se conserva hasta que el envío funcione, así un reintento
/// (por ejemplo, si se cortó el wifi) nunca duplica el pedido en cocina.
final orderSenderProvider = NotifierProvider<OrderSender, bool>(OrderSender.new);

class OrderSender extends Notifier<bool> {
  String? _requestId;
  String? _requestFor;

  @override
  bool build() => false; // enviando

  String _idFor(List<CartLine> lines) {
    final signature = lines.map((l) => '${l.key}:${l.quantity}').join('|');
    if (_requestId == null || _requestFor != signature) {
      final r = Random.secure();
      _requestId = List.generate(24, (_) => r.nextInt(36).toRadixString(36)).join();
      _requestFor = signature;
    }
    return _requestId!;
  }

  /// Devuelve el estado de la orden creada (PLACED o PENDING_APPROVAL).
  Future<String> send() async {
    final lines = ref.read(cartProvider);
    if (lines.isEmpty || state) return '';
    state = true;
    try {
      final dio = ref.read(dioProvider);
      final order = await apiCall(() async => (await dio.post<Json>('/orders', data: {
            'clientRequestId': _idFor(lines),
            'fulfillmentType': 'DINE_IN',
            'items': [for (final l in lines) l.toOrderLine()],
          }))
              .data!);
      _requestId = null;
      ref.read(cartProvider.notifier).clear();
      return order['status'] as String? ?? 'PLACED';
    } finally {
      state = false;
    }
  }
}
