import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/device_session.dart';
import '../../core/format.dart';
import '../../core/realtime.dart';

typedef Json = Map<String, dynamic>;

/// Cómo ve el cliente el estado de su pedido, en su idioma.
String guestOrderStatus(String status, String lang) {
  final en = lang == 'en';
  return switch (status) {
    'PENDING_APPROVAL' => en ? 'Waiting for your server' : 'Esperando al mesero',
    'PLACED' || 'ACCEPTED' => en ? 'Received in the kitchen' : 'Recibido en cocina',
    'PREPARING' => en ? 'Being prepared' : 'Preparándose',
    'READY' => en ? 'Ready! On its way' : '¡Listo! Ya te lo llevan',
    'COMPLETED' => en ? 'Served' : 'Servido',
    'CANCELLED' => en ? 'Cancelled' : 'Cancelado',
    _ => status,
  };
}

class GuestItem {
  const GuestItem({required this.name, required this.quantity, required this.lineTotal, required this.discount, this.notes, required this.modifiers});
  final String name;
  final int quantity;
  final double lineTotal;
  final double discount;
  final String? notes;
  final List<String> modifiers;

  factory GuestItem.fromJson(Json j) => GuestItem(
        name: j['name'] as String,
        quantity: (j['quantity'] as num).toInt(),
        lineTotal: parseMoney(j['lineTotal']),
        discount: parseMoney(j['discount']),
        notes: j['notes'] as String?,
        modifiers: [for (final m in j['modifiers'] as List? ?? const []) '$m'],
      );
}

class GuestOrder {
  const GuestOrder({required this.id, required this.number, required this.status, required this.createdAt, required this.items});
  final String id;
  final int number;
  final String status;
  final DateTime createdAt;
  final List<GuestItem> items;

  bool get isActive => status != 'COMPLETED' && status != 'CANCELLED';

  factory GuestOrder.fromJson(Json j) => GuestOrder(
        id: j['id'] as String,
        number: (j['number'] as num).toInt(),
        status: j['status'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String).toLocal(),
        items: [for (final i in j['items'] as List? ?? const []) GuestItem.fromJson(i as Json)],
      );
}

class GuestRequest {
  const GuestRequest({required this.id, required this.type, required this.status});
  final String id;
  final String type;
  final String status;

  factory GuestRequest.fromJson(Json j) =>
      GuestRequest(id: j['id'] as String, type: j['type'] as String, status: j['status'] as String);
}

class GuestBill {
  const GuestBill({required this.subtotal, required this.discountTotal, required this.taxTotal, required this.tipTotal, required this.total, required this.paid, required this.due});
  final double subtotal;
  final double discountTotal;
  final double taxTotal;
  final double tipTotal;
  final double total;
  final double paid;
  final double due;

  factory GuestBill.fromJson(Json j) => GuestBill(
        subtotal: parseMoney(j['subtotal']),
        discountTotal: parseMoney(j['discountTotal']),
        taxTotal: parseMoney(j['taxTotal']),
        tipTotal: parseMoney(j['tipTotal']),
        total: parseMoney(j['total']),
        paid: parseMoney(j['paid']),
        due: parseMoney(j['due']),
      );
}

class GuestSession {
  const GuestSession({required this.id, required this.status, required this.openedAt, required this.requests, required this.orders, required this.bill, this.payUrl});
  final String id;
  final String status;
  final DateTime openedAt;
  final List<GuestRequest> requests;
  final List<GuestOrder> orders;
  final GuestBill bill;

  /// Enlace del QR "Paga con tu celular" (null si el restaurante no tiene pagos en línea).
  final String? payUrl;

  GuestRequest? request(String type) {
    for (final r in requests) {
      if (r.type == type) return r;
    }
    return null;
  }

  factory GuestSession.fromJson(Json j) => GuestSession(
        id: j['id'] as String,
        status: j['status'] as String,
        openedAt: DateTime.parse(j['openedAt'] as String).toLocal(),
        requests: [for (final r in j['requests'] as List? ?? const []) GuestRequest.fromJson(r as Json)],
        orders: [for (final o in j['orders'] as List? ?? const []) GuestOrder.fromJson(o as Json)],
        bill: GuestBill.fromJson(j['bill'] as Json),
        payUrl: j['payUrl'] as String?,
      );
}

class TabletTable {
  const TabletTable({this.label, this.area, this.session});
  final String? label;
  final String? area;
  final GuestSession? session;

  bool get hasTable => label != null;

  factory TabletTable.fromJson(Json j) {
    final table = j['table'] as Json?;
    return TabletTable(
      label: table?['label'] as String?,
      area: table?['area'] as String?,
      session: j['session'] == null ? null : GuestSession.fromJson(j['session'] as Json),
    );
  }
}

/// La mesa de esta tablet, al día: se recarga con cada aviso en vivo de su mesa y, por las
/// dudas, cada minuto.
final tableProvider = AsyncNotifierProvider<TableController, TabletTable>(TableController.new);

const _tableEvents = {
  'ready',
  'table.updated',
  'order.created',
  'order.updated',
  'bill.updated',
  'service_request.created',
  'service_request.updated',
};

class TableController extends AsyncNotifier<TabletTable> {
  Timer? _debounce;
  Timer? _poll;

  @override
  Future<TabletTable> build() async {
    // Si se vuelve a vincular (otro token o servidor), se carga de nuevo.
    ref.watch(deviceSessionProvider.select((s) => s.value?.token));
    final sub = ref.read(realtimeProvider.notifier).events.listen((e) {
      if (!_tableEvents.contains(e.name)) return;
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 300), refresh);
    });
    _poll = Timer.periodic(const Duration(seconds: 60), (_) => refresh());
    ref.onDispose(() {
      sub.cancel();
      _debounce?.cancel();
      _poll?.cancel();
    });
    return _load();
  }

  Future<TabletTable> _load() async {
    final dio = ref.read(dioProvider);
    return TabletTable.fromJson(await apiCall(() async => (await dio.get<Json>('/emenu/table')).data!));
  }

  Future<void> refresh() async {
    try {
      state = AsyncData(await _load());
    } catch (error, stack) {
      if (!state.hasValue) state = AsyncError(error, stack);
    }
  }

  Future<void> _post(String path, [Object? body]) async {
    final dio = ref.read(dioProvider);
    final data = await apiCall(() async => (await dio.post<Json>(path, data: body)).data!);
    state = AsyncData(TabletTable.fromJson(data));
  }

  Future<void> callWaiter() => _post('/emenu/requests', {'type': 'CALL_WAITER'});
  Future<void> requestBill() => _post('/emenu/requests', {'type': 'REQUEST_BILL'});
  Future<void> cancelRequest(String id) => _post('/emenu/requests/$id/cancel');
}
