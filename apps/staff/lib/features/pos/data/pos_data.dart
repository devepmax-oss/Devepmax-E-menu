import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/realtime/realtime.dart';
import '../../../core/ui/feedback.dart';

typedef PJson = Map<String, dynamic>;

Future<T> _call<T>(Future<T> Function() request) async {
  try {
    return await request();
  } catch (error) {
    throw ApiException.from(error);
  }
}

// ───────────────────────── Menú para vender ─────────────────────────

class PosOption {
  const PosOption({required this.id, required this.name, required this.price, required this.isDefault, required this.isAvailable});
  final String id;
  final String name;
  final double price;
  final bool isDefault;
  final bool isAvailable;

  factory PosOption.fromJson(PJson j) => PosOption(
        id: j['id'] as String,
        name: j['name'] as String,
        price: parseMoney(j['priceAdjustment']),
        isDefault: j['isDefault'] as bool? ?? false,
        isAvailable: j['isAvailable'] as bool? ?? true,
      );
}

class PosGroup {
  const PosGroup({required this.id, required this.name, required this.single, required this.minSelect, this.maxSelect, required this.options});
  final String id;
  final String name;
  final bool single;
  final int minSelect;
  final int? maxSelect;
  final List<PosOption> options;

  int? get max => single ? 1 : maxSelect;
  bool get required => minSelect > 0;

  String get rule {
    final m = max;
    if (minSelect > 0 && m == minSelect) return 'Elige $minSelect';
    if (minSelect > 0) return 'Al menos $minSelect${m != null ? ' (hasta $m)' : ''}';
    return m != null ? 'Opcional · hasta $m' : 'Opcional';
  }

  factory PosGroup.fromJson(PJson j) => PosGroup(
        id: j['id'] as String,
        name: j['name'] as String,
        single: j['selectionType'] == 'SINGLE',
        minSelect: (j['minSelect'] as num?)?.toInt() ?? 0,
        maxSelect: (j['maxSelect'] as num?)?.toInt(),
        options: [for (final o in j['options'] as List? ?? const []) PosOption.fromJson(o as PJson)],
      );
}

class PosProduct {
  const PosProduct({required this.id, required this.name, required this.price, this.imageUrl, required this.isAvailable, required this.groups, this.sku});
  final String id;
  final String name;
  final double price;
  final String? imageUrl;
  final bool isAvailable;
  final List<PosGroup> groups;
  final String? sku;

  /// Se agrega con un toque si no tiene opciones que elegir.
  bool get quickAdd => groups.isEmpty;

  factory PosProduct.fromJson(PJson j) => PosProduct(
        id: j['id'] as String,
        name: j['name'] as String,
        price: parseMoney(j['price']),
        imageUrl: j['imageUrl'] as String?,
        isAvailable: j['isAvailable'] as bool? ?? true,
        groups: [for (final g in j['modifierGroups'] as List? ?? const []) PosGroup.fromJson(g as PJson)],
        sku: j['sku'] as String?,
      );
}

class PosCategory {
  const PosCategory({required this.id, required this.name, required this.products});
  final String id;
  final String name;
  final List<PosProduct> products;

  factory PosCategory.fromJson(PJson j) => PosCategory(
        id: j['id'] as String,
        name: j['name'] as String,
        products: [for (final p in j['products'] as List? ?? const []) PosProduct.fromJson(p as PJson)],
      );
}

/// Menú de salón para la caja. Se recarga si algo se agota o vuelve.
final posMenuProvider = AsyncNotifierProvider<PosMenuController, List<PosCategory>>(PosMenuController.new);

class PosMenuController extends AsyncNotifier<List<PosCategory>> {
  Timer? _debounce;

  @override
  Future<List<PosCategory>> build() async {
    final sub = ref.read(realtimeProvider.notifier).events.listen((e) {
      if (e.name == 'product.availability' || e.name == 'option.availability') {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 500), reload);
      }
    });
    ref.onDispose(() {
      sub.cancel();
      _debounce?.cancel();
    });
    return _load();
  }

  Future<List<PosCategory>> _load() => _call(() async {
        final data = (await ref.read(dioProvider).get<PJson>('/menu', queryParameters: {'channel': 'dine_in'})).data!;
        return [for (final c in data['categories'] as List? ?? const []) PosCategory.fromJson(c as PJson)];
      });

  Future<void> reload() async {
    try {
      state = AsyncData(await _load());
    } catch (error, stack) {
      if (!state.hasValue) state = AsyncError(error, stack);
    }
  }
}

// ───────────────────────── La orden que se arma ─────────────────────────

class PosLine {
  const PosLine({required this.key, required this.product, required this.options, required this.quantity, this.notes, this.seat});
  final String key;
  final PosProduct product;
  final List<PosOption> options;
  final int quantity;
  final String? notes;
  final int? seat;

  double get unitPrice => product.price + options.fold<double>(0, (s, o) => s + o.price);
  double get total => unitPrice * quantity;
  List<String> get optionIds => [for (final o in options) o.id]..sort();

  PosLine copyWith({int? quantity, String? notes, bool clearNotes = false}) => PosLine(
        key: key,
        product: product,
        options: options,
        quantity: quantity ?? this.quantity,
        notes: clearNotes ? null : (notes ?? this.notes),
        seat: seat,
      );

  PJson toOrderLine() => {
        'productId': product.id,
        'quantity': quantity,
        'optionIds': optionIds,
        if (notes != null && notes!.isNotEmpty) 'notes': notes,
        if (seat != null) 'seat': seat,
      };
}

/// Para qué es la orden.
enum PosMode { here, takeout, table, pickup }

extension PosModeInfo on PosMode {
  String get label => switch (this) {
        PosMode.here => 'Comer aquí',
        PosMode.takeout => 'Para llevar',
        PosMode.table => 'Mesa',
        PosMode.pickup => 'Recoger después',
      };

  String get fulfillment => switch (this) {
        PosMode.here || PosMode.table => 'DINE_IN',
        PosMode.takeout => 'TAKEOUT',
        PosMode.pickup => 'PICKUP',
      };
}

class PosOrder {
  const PosOrder({this.lines = const [], this.mode = PosMode.here, this.tableId, this.customerName = '', this.customerPhone = '', this.notes = ''});
  final List<PosLine> lines;
  final PosMode mode;
  final String? tableId;
  final String customerName;
  final String customerPhone;
  final String notes;

  int get count => lines.fold(0, (s, l) => s + l.quantity);
  double get estimate => lines.fold(0, (s, l) => s + l.total);

  PosOrder copyWith({
    List<PosLine>? lines,
    PosMode? mode,
    String? tableId,
    bool clearTable = false,
    String? customerName,
    String? customerPhone,
    String? notes,
  }) =>
      PosOrder(
        lines: lines ?? this.lines,
        mode: mode ?? this.mode,
        tableId: clearTable ? null : (tableId ?? this.tableId),
        customerName: customerName ?? this.customerName,
        customerPhone: customerPhone ?? this.customerPhone,
        notes: notes ?? this.notes,
      );

  /// Qué falta para poder enviarla (null = lista).
  String? get problem {
    if (lines.isEmpty) return 'Agrega algo a la orden';
    if (mode == PosMode.table && tableId == null) return 'Elige la mesa';
    if (mode == PosMode.pickup && customerName.trim().isEmpty) return 'Escribe el nombre de quien recoge';
    return null;
  }
}

final posOrderProvider = NotifierProvider<PosOrderController, PosOrder>(PosOrderController.new);

class PosOrderController extends Notifier<PosOrder> {
  final _random = Random();
  String? _requestId;
  String? _requestFor;

  @override
  PosOrder build() => const PosOrder();

  void start({String? tableId}) {
    if (tableId != null) state = state.copyWith(mode: PosMode.table, tableId: tableId);
  }

  void add(PosProduct product, List<PosOption> options, {int quantity = 1, String? notes}) {
    final ids = ([for (final o in options) o.id]..sort()).join(',');
    final note = notes?.trim();
    final index = state.lines.indexWhere((l) => l.product.id == product.id && l.optionIds.join(',') == ids && (l.notes ?? '') == (note ?? ''));
    if (index >= 0) {
      final lines = [...state.lines];
      lines[index] = lines[index].copyWith(quantity: (lines[index].quantity + quantity).clamp(1, 99));
      state = state.copyWith(lines: lines);
      return;
    }
    state = state.copyWith(lines: [
      ...state.lines,
      PosLine(
        key: '${DateTime.now().microsecondsSinceEpoch}${_random.nextInt(9999)}',
        product: product,
        options: options,
        quantity: quantity,
        notes: note == null || note.isEmpty ? null : note,
      ),
    ]);
  }

  void setQuantity(String key, int quantity) {
    if (quantity <= 0) return remove(key);
    state = state.copyWith(lines: [for (final l in state.lines) l.key == key ? l.copyWith(quantity: quantity.clamp(1, 99)) : l]);
  }

  void setNotes(String key, String notes) {
    final n = notes.trim();
    state = state.copyWith(lines: [for (final l in state.lines) l.key == key ? l.copyWith(notes: n, clearNotes: n.isEmpty) : l]);
  }

  void remove(String key) => state = state.copyWith(lines: state.lines.where((l) => l.key != key).toList());
  void setMode(PosMode mode) => state = state.copyWith(mode: mode, clearTable: mode != PosMode.table);
  void setTable(String? id) => state = id == null ? state.copyWith(clearTable: true) : state.copyWith(tableId: id);
  void setCustomer({String? name, String? phone}) => state = state.copyWith(customerName: name, customerPhone: phone);
  void setOrderNotes(String notes) => state = state.copyWith(notes: notes);
  void clear() {
    _requestId = null;
    state = PosOrder(mode: state.mode == PosMode.table ? PosMode.here : state.mode);
  }

  /// Mismo identificador mientras la orden no cambie: reintentar nunca la duplica en cocina.
  String _idFor(PosOrder order) {
    final signature = [
      order.mode.name,
      order.tableId,
      order.customerName,
      for (final l in order.lines) '${l.key}:${l.quantity}:${l.notes}',
    ].join('|');
    if (_requestId == null || _requestFor != signature) {
      final r = Random.secure();
      _requestId = List.generate(24, (_) => r.nextInt(36).toRadixString(36)).join();
      _requestFor = signature;
    }
    return _requestId!;
  }

  /// Envía la orden a cocina. Devuelve número, cuenta y estado.
  Future<({String id, int number, String billId})> send() async {
    final order = state;
    final problem = order.problem;
    if (problem != null) throw ApiException(problem);
    final dio = ref.read(dioProvider);
    final data = await _call(() async => (await dio.post<PJson>('/orders', data: {
          'clientRequestId': _idFor(order),
          'fulfillmentType': order.mode.fulfillment,
          if (order.mode == PosMode.table) 'tableId': order.tableId,
          if (order.customerName.trim().isNotEmpty) 'customerName': order.customerName.trim(),
          if (order.customerPhone.trim().isNotEmpty) 'customerPhone': order.customerPhone.trim(),
          if (order.notes.trim().isNotEmpty) 'notes': order.notes.trim(),
          'items': [for (final l in order.lines) l.toOrderLine()],
        }))
            .data!);
    clear();
    return (
      id: data['id'] as String,
      number: (data['number'] as num).toInt(),
      billId: (data['bill'] as PJson)['id'] as String,
    );
  }
}

// ───────────────────────── Totales reales ─────────────────────────

class PosQuote {
  const PosQuote({required this.subtotal, required this.discountTotal, required this.taxTotal, required this.total, required this.promotions});
  final double subtotal;
  final double discountTotal;
  final double taxTotal;
  final double total;
  final List<({String name, double amount})> promotions;

  factory PosQuote.fromJson(PJson j) {
    final totals = j['totals'] as PJson? ?? const {};
    return PosQuote(
      subtotal: parseMoney(totals['subtotal']),
      discountTotal: parseMoney(totals['discountTotal']),
      taxTotal: parseMoney(totals['taxTotal']),
      total: parseMoney(totals['total']),
      promotions: [
        for (final p in j['promotions'] as List? ?? const []) (name: (p as PJson)['name'] as String? ?? 'Promoción', amount: parseMoney(p['amount'])),
      ],
    );
  }
}

/// Precios, promociones e impuestos según el servidor (espera a que dejen de tocar + / −).
final posQuoteProvider = FutureProvider.autoDispose<PosQuote?>((ref) async {
  final lines = ref.watch(posOrderProvider.select((o) => o.lines));
  if (lines.isEmpty) return null;
  var cancelled = false;
  ref.onDispose(() => cancelled = true);
  await Future<void>.delayed(const Duration(milliseconds: 350));
  if (cancelled) return null;
  final Dio dio = ref.read(dioProvider);
  return _call(() async => PosQuote.fromJson(
      (await dio.post<PJson>('/orders/quote', data: {'items': [for (final l in lines) l.toOrderLine()]})).data!));
});
