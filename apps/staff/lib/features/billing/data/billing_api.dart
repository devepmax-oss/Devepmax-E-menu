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

  Future<List<BillView>> list({String? tableId, bool paid = false}) => _call(() async {
        final response = await _dio.get<List<dynamic>>('/billing/bills', queryParameters: {
          if (tableId != null) 'tableId': tableId,
          if (paid) 'scope': 'paid',
        });
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

  /// Reembolso de un pago (todo si no se dice el monto).
  Future<BillView> refund(String paymentId, {required String requestId, double? amount, required String reason, String? managerPin}) =>
      _bill(_dio.post<Map<String, dynamic>>('/billing/payments/$paymentId/refunds', data: {
        'clientRequestId': requestId,
        if (amount != null) 'amount': amount,
        'reason': reason,
        if (managerPin != null && managerPin.isNotEmpty) 'managerPin': managerPin,
      }));

  /// Qué envíos de recibo están configurados.
  Future<({bool email, bool sms})> receiptConfig() => _call(() async {
        final data = (await _dio.get<Map<String, dynamic>>('/billing/receipts/config')).data!;
        return (email: data['email'] == true, sms: data['sms'] == true);
      });

  /// La cuenta antes de pagar: total, propinas sugeridas y, en mesas, el enlace para pagar con el celular.
  Future<Map<String, dynamic>> check(String billId) =>
      _call(() async => (await _dio.get<Map<String, dynamic>>('/billing/bills/$billId/check')).data!);

  /// El recibo para imprimir (incluye el enlace del QR).
  Future<Map<String, dynamic>> receipt(String billId) =>
      _call(() async => (await _dio.get<Map<String, dynamic>>('/billing/bills/$billId/receipt')).data!);

  Future<List<String>> sendReceipt(String billId, {String? email, String? phone}) => _call(() async {
        final data = (await _dio.post<Map<String, dynamic>>('/billing/bills/$billId/receipt', data: {
          if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
          if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
        }))
            .data!;
        return [for (final s in data['sent'] as List? ?? const []) '$s'];
      });

  Future<BillView> split(String billId, List<String> itemIds) =>
      _bill(_dio.post<Map<String, dynamic>>('/billing/bills/$billId/split', data: {'itemIds': itemIds}));

  /// Cupón en la cuenta (uno por cuenta). El servidor dice si no aplica y por qué.
  Future<BillView> applyCoupon(String billId, String code) =>
      _bill(_dio.post<Map<String, dynamic>>('/billing/bills/$billId/coupon', data: {'code': code.trim()}));

  Future<BillView> removeCoupon(String billId) => _bill(_dio.delete<Map<String, dynamic>>('/billing/bills/$billId/coupon'));

  Future<BillView> merge(String billId, String targetBillId) =>
      _bill(_dio.post<Map<String, dynamic>>('/billing/bills/$billId/merge', data: {'targetBillId': targetBillId}));

  // Lector de tarjetas (Stripe Terminal)
  Future<({bool enabled, bool testMode})> terminalConfig() => _call(() async {
        final data = (await _dio.get<Map<String, dynamic>>('/terminal/config')).data!;
        return (enabled: data['enabled'] as bool? ?? false, testMode: data['testMode'] as bool? ?? false);
      });

  Future<List<CardReader>> readers() => _call(() async {
        final response = await _dio.get<List<dynamic>>('/terminal/readers');
        return response.data!.map((r) => CardReader.fromJson(r as BJson)).toList();
      });

  Future<void> registerReader(String code, String label) =>
      _call(() => _dio.post('/terminal/readers', data: {'registrationCode': code, 'label': label}));

  Future<void> removeReader(String id) => _call(() => _dio.delete('/terminal/readers/$id'));

  Future<TerminalCharge> terminalCharge(String billId,
          {required String requestId, required String readerId, required double amount, required bool tipOnReader}) =>
      _call(() async => TerminalCharge.fromJson((await _dio.post<Map<String, dynamic>>('/billing/bills/$billId/terminal', data: {
            'clientRequestId': requestId,
            'readerId': readerId,
            'amount': amount,
            'tipOnReader': tipOnReader,
          }))
              .data!));

  Future<TerminalCharge> terminalStatus(String paymentId) => _call(
      () async => TerminalCharge.fromJson((await _dio.get<Map<String, dynamic>>('/billing/terminal/$paymentId')).data!));

  Future<TerminalCharge> terminalCancel(String paymentId) => _call(() async =>
      TerminalCharge.fromJson((await _dio.post<Map<String, dynamic>>('/billing/terminal/$paymentId/cancel')).data!));

  Future<void> terminalSimulate(String paymentId, {double tip = 0, bool declined = false}) => _call(() =>
      _dio.post('/billing/terminal/$paymentId/simulate', data: {if (tip > 0) 'tip': tip, if (declined) 'declined': true}));

  /// Tap to Pay: token para el SDK de Stripe (y la ubicación del restaurante).
  Future<({String secret, String locationId, bool testMode})> connectionToken() => _call(() async {
        final data = (await _dio.post<Map<String, dynamic>>('/terminal/connection-token')).data!;
        return (
          secret: data['secret'] as String,
          locationId: data['locationId'] as String,
          testMode: data['testMode'] as bool? ?? false,
        );
      });

  /// Tap to Pay: crea el cobro; este aparato lo cobra con su NFC.
  Future<({String paymentId, String clientSecret})> tapToPay(String billId,
          {required String requestId, required double amount, double tip = 0}) =>
      _call(() async {
        final data = (await _dio.post<Map<String, dynamic>>('/billing/bills/$billId/tap-to-pay', data: {
          'clientRequestId': requestId,
          'amount': amount,
          if (tip > 0) 'tip': tip,
        }))
            .data!;
        return (paymentId: data['paymentId'] as String, clientSecret: data['clientSecret'] as String);
      });

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

/// Configuración de Stripe Terminal (si hay claves y si es modo prueba).
final terminalConfigProvider = FutureProvider<({bool enabled, bool testMode})>((ref) async {
  try {
    return await ref.read(billingApiProvider).terminalConfig();
  } catch (_) {
    return (enabled: false, testMode: false);
  }
});

/// Lectores registrados. Si Stripe no está configurado o falta la dirección, lista vacía con el motivo.
final cardReadersProvider = FutureProvider.autoDispose<List<CardReader>>((ref) async {
  final config = await ref.watch(terminalConfigProvider.future);
  if (!config.enabled) return const [];
  return ref.read(billingApiProvider).readers();
});

/// Cuentas cobradas hoy (para reenviar el recibo o reembolsar).
final paidBillsProvider = FutureProvider.autoDispose<List<BillView>>((ref) async {
  ref.watch(openBillsProvider); // se recalcula con cada cobro
  return ref.read(billingApiProvider).list(paid: true);
});

final receiptConfigProvider = FutureProvider<({bool email, bool sms})>((ref) async {
  try {
    return await ref.read(billingApiProvider).receiptConfig();
  } catch (_) {
    return (email: false, sms: false);
  }
});
