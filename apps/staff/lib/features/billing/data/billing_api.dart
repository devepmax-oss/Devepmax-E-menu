import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/realtime/realtime.dart';
import 'billing_models.dart';

final billingApiProvider = Provider<BillingApi>((ref) => BillingApi(ref.watch(dioProvider)));

/// Identificador único de un cobro: si la red falla y se reintenta, no se cobra dos veces.
String newRequestId() {
  final r = Random.secure();
  return List.generate(24, (_) => r.nextInt(36).toRadixString(36)).join();
}

class BillingApi {
  BillingApi(this._dio);
  final Dio _dio;

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } catch (error) {
      throw ApiException.from(error);
    }
  }

  Future<BillView> _bill(Future<Response<Map<String, dynamic>>> request) =>
      _call(() async => BillView.fromJson((await request).data!));

  Future<List<BillView>> list({String? tableId}) => _call(() async {
        final response = await _dio.get<List<dynamic>>('/billing/bills', queryParameters: {if (tableId != null) 'tableId': tableId});
        return response.data!.map((b) => BillView.fromJson(b as BJson)).toList();
      });

  Future<BillView> get(String id) => _bill(_dio.get<Map<String, dynamic>>('/billing/bills/$id'));

  Future<BillView> pay(
    String billId, {
    required String requestId,
    required String method,
    required double amount,
    double tip = 0,
    double? cashTendered,
    String? reference,
  }) =>
      _bill(_dio.post<Map<String, dynamic>>('/billing/bills/$billId/payments', data: {
        'clientRequestId': requestId,
        'method': method,
        'amount': amount,
        if (tip > 0) 'tip': tip,
        if (cashTendered != null) 'cashTendered': cashTendered,
        if (reference != null && reference.trim().isNotEmpty) 'reference': reference.trim(),
      }));

  Future<BillView> discount(String billId,
          {required String type, required double value, required String reason, String? itemId, String? managerPin}) =>
      _bill(_dio.post<Map<String, dynamic>>('/billing/bills/$billId/discounts', data: {
        'type': type,
        'value': value,
        'reason': reason,
        if (itemId != null) 'itemId': itemId,
        if (managerPin != null && managerPin.isNotEmpty) 'managerPin': managerPin,
      }));

  Future<BillView> removeDiscount(String discountId, {String? managerPin}) => _bill(_dio.delete<Map<String, dynamic>>(
      '/billing/discounts/$discountId',
      data: {if (managerPin != null && managerPin.isNotEmpty) 'managerPin': managerPin}));

  Future<BillView> split(String billId, List<String> itemIds) =>
      _bill(_dio.post<Map<String, dynamic>>('/billing/bills/$billId/split', data: {'itemIds': itemIds}));

  Future<BillView> merge(String billId, String targetBillId) =>
      _bill(_dio.post<Map<String, dynamic>>('/billing/bills/$billId/merge', data: {'targetBillId': targetBillId}));

  // Caja
  Future<CashShiftView?> shift() => _call(() async {
        final data = (await _dio.get<Map<String, dynamic>>('/cash/shift')).data!;
        return data['shift'] == null ? null : CashShiftView.fromJson(data['shift'] as BJson);
      });

  Future<CashShiftView> openShift(double openingCash) => _call(() async =>
      CashShiftView.fromJson((await _dio.post<Map<String, dynamic>>('/cash/shift/open', data: {'openingCash': openingCash})).data!));

  Future<CashShiftView> movement(String type, double amount, String reason) => _call(() async => CashShiftView.fromJson(
      (await _dio.post<Map<String, dynamic>>('/cash/shift/movements', data: {'type': type, 'amount': amount, 'reason': reason})).data!));

  Future<CashShiftView> closeShift(double countedCash, String? notes) => _call(() async => CashShiftView.fromJson(
      (await _dio.post<Map<String, dynamic>>('/cash/shift/close', data: {
        'countedCash': countedCash,
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      }))
          .data!));
}

const _billEvents = {'ready', 'bill.updated', 'order.created', 'order.updated', 'table.updated'};

/// Cuentas por cobrar, al día con cada cambio de pedidos y cuentas.
final openBillsProvider = AsyncNotifierProvider<OpenBillsController, List<BillView>>(OpenBillsController.new);

class OpenBillsController extends AsyncNotifier<List<BillView>> {
  Timer? _debounce;

  @override
  Future<List<BillView>> build() async {
    final sub = ref.read(realtimeProvider.notifier).events.listen((e) {
      if (!_billEvents.contains(e.name)) return;
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 400), refresh);
    });
    ref.onDispose(() {
      sub.cancel();
      _debounce?.cancel();
    });
    return ref.read(billingApiProvider).list();
  }

  Future<void> refresh() async {
    try {
      state = AsyncData(await ref.read(billingApiProvider).list());
    } catch (error, stack) {
      if (!state.hasValue) state = AsyncError(error, stack);
    }
  }
}

/// Una cuenta, también al día en vivo (por si cambia mientras la caja la tiene abierta).
final billProvider = FutureProvider.autoDispose.family<BillView, String>((ref, id) async {
  Timer? debounce;
  final sub = ref.read(realtimeProvider.notifier).events.listen((e) {
    if (!_billEvents.contains(e.name)) return;
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 400), ref.invalidateSelf);
  });
  ref.onDispose(() {
    sub.cancel();
    debounce?.cancel();
  });
  return ref.read(billingApiProvider).get(id);
});

/// Las cuentas de una mesa (para "Cuenta 1 / Cuenta 2" al dividir).
final tableBillsProvider = FutureProvider.autoDispose.family<List<BillView>, String>((ref, tableId) async {
  ref.watch(openBillsProvider); // se recalcula junto con la lista
  return ref.read(billingApiProvider).list(tableId: tableId);
});

/// Turno de caja abierto (o null).
final cashShiftProvider = FutureProvider<CashShiftView?>((ref) async {
  ref.watch(openBillsProvider); // los cobros cambian el efectivo esperado
  return ref.read(billingApiProvider).shift();
});
