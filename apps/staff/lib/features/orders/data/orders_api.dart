import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/realtime/realtime.dart';
import 'orders_models.dart';

final ordersApiProvider = Provider<OrdersApi>((ref) => OrdersApi(ref.watch(dioProvider)));

class OrdersApi {
  OrdersApi(this._dio);
  final Dio _dio;

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } catch (error) {
      throw ApiException.from(error);
    }
  }

  Future<List<OrderView>> list(String scope) => _call(() async {
        final response = await _dio.get<List<dynamic>>('/orders', queryParameters: {'scope': scope});
        return response.data!.map((o) => OrderView.fromJson(o as Map<String, dynamic>)).toList();
      });

  Future<OrderView> get(String id) => _call(() async =>
      OrderView.fromJson((await _dio.get<Map<String, dynamic>>('/orders/$id')).data!));

  Future<OrderView> approve(String id) => _call(() async =>
      OrderView.fromJson((await _dio.post<Map<String, dynamic>>('/orders/$id/approve')).data!));

  Future<OrderView> complete(String id) => _call(() async =>
      OrderView.fromJson((await _dio.post<Map<String, dynamic>>('/orders/$id/complete')).data!));

  /// Cocina: mueve un ticket (NEW → PREPARING → READY). La orden llega actualizada por tiempo real.
  Future<void> moveTicket(String ticketId, String status) => _call(() async {
        await _dio.patch<Map<String, dynamic>>('/kitchen/tickets/$ticketId', data: {'status': status});
      });

  Future<OrderView> cancel(String id, String reason) => _call(() async => OrderView.fromJson(
      (await _dio.post<Map<String, dynamic>>('/orders/$id/cancel', data: {'reason': reason})).data!));
}

/// Tablero de órdenes en curso, al día en tiempo real.
///
/// - Carga la lista completa al abrir y cada vez que el socket avisa `ready`
///   (al conectar o reconectar), así nunca queda desfasado.
/// - Cada `order.created` / `order.updated` reemplaza la orden si es más nueva.
/// - Las entregadas o canceladas salen del tablero.
class OrdersBoard {
  const OrdersBoard({required this.orders, required this.arrivedAt});

  /// Ordenadas de la más antigua a la más nueva.
  final List<OrderView> orders;

  /// Cuándo llegó cada orden nueva (para resaltarla unos segundos).
  final Map<String, DateTime> arrivedAt;
}

final ordersBoardProvider = AsyncNotifierProvider<OrdersBoardController, OrdersBoard>(OrdersBoardController.new);

class OrdersBoardController extends AsyncNotifier<OrdersBoard> {
  final Map<String, OrderView> _byId = {};
  final Map<String, DateTime> _arrived = {};

  @override
  Future<OrdersBoard> build() async {
    final sub = ref.read(realtimeProvider.notifier).events.listen(_onEvent);
    ref.onDispose(sub.cancel);
    await _reload();
    return _snapshot();
  }

  Future<void> _reload() async {
    final orders = await ref.read(ordersApiProvider).list('active');
    _byId
      ..clear()
      ..addEntries(orders.map((o) => MapEntry(o.id, o)));
  }

  OrdersBoard _snapshot() {
    final list = _byId.values.toList()..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    return OrdersBoard(orders: list, arrivedAt: Map.unmodifiable(_arrived));
  }

  void _onEvent(RealtimeEvent event) {
    switch (event.name) {
      case 'ready':
        unawaited(refresh());
      case 'order.created':
      case 'order.updated':
        final json = event.json;
        if (json == null) return;
        apply(OrderView.fromJson(json), isNew: event.name == 'order.created');
    }
  }

  /// Aplica una versión de la orden (llegada por el socket o por una acción propia).
  void apply(OrderView order, {bool isNew = false}) {
    final current = _byId[order.id];
    if (current != null && order.updatedAt.isBefore(current.updatedAt)) return; // aviso viejo
    if (order.isFinished) {
      _byId.remove(order.id);
    } else {
      if (current == null && isNew) _arrived[order.id] = DateTime.now();
      _byId[order.id] = order;
    }
    _arrived.removeWhere((_, at) => DateTime.now().difference(at) > const Duration(seconds: 20));
    state = AsyncData(_snapshot());
  }

  /// Vuelve a pedir la lista completa (resincronizar).
  Future<void> refresh() async {
    try {
      await _reload();
      state = AsyncData(_snapshot());
    } catch (error, stack) {
      if (!state.hasValue) state = AsyncError(error, stack);
    }
  }
}

/// Órdenes del día (todas, también entregadas y canceladas).
final todayOrdersProvider = FutureProvider<List<OrderView>>((ref) async {
  final orders = await ref.watch(ordersApiProvider).list('today');
  return orders..sort((a, b) => b.createdAt.compareTo(a.createdAt));
});

/// Una orden por id, pedida al servidor. El detalle la usa cuando la orden ya no está en el
/// tablero (se entregó o se canceló mientras el panel estaba abierto, o se abrió desde "Hoy").
final orderByIdProvider = FutureProvider.autoDispose.family<OrderView, String>(
  (ref, id) => ref.watch(ordersApiProvider).get(id),
);
