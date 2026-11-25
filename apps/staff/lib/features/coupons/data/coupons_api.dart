import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/ui/feedback.dart';

typedef KJson = Map<String, dynamic>;

double? _money(Object? v) => v == null ? null : parseMoney(v);
DateTime? _date(Object? v) => v == null ? null : DateTime.parse(v as String).toLocal();

class CouponView {
  const CouponView({
    required this.id,
    required this.code,
    required this.name,
    required this.type,
    this.value,
    this.maxDiscount,
    this.minOrderTotal,
    required this.appliesOnline,
    required this.appliesInStore,
    required this.firstOrderOnly,
    this.maxUses,
    this.maxUsesPerCustomer,
    this.startsAt,
    this.endsAt,
    required this.isActive,
    this.customerId,
    this.customerName,
    required this.uses,
    required this.saved,
    required this.state,
  });

  final String id;
  final String code;
  final String name;

  /// PERCENT, AMOUNT o FREE_DELIVERY.
  final String type;
  final double? value;
  final double? maxDiscount;
  final double? minOrderTotal;
  final bool appliesOnline;
  final bool appliesInStore;
  final bool firstOrderOnly;
  final int? maxUses;
  final int? maxUsesPerCustomer;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final bool isActive;
  final String? customerId;
  final String? customerName;
  final int uses;
  final double saved;

  /// ACTIVE, SCHEDULED, EXPIRED, USED_UP o PAUSED.
  final String state;

  /// "10 % (máx. $15)", "$5 menos", "Envío gratis".
  String get rule => switch (type) {
        'PERCENT' => '${value?.toStringAsFixed(value! % 1 == 0 ? 0 : 1)} %${maxDiscount != null ? ' (máx. ${formatMoney(maxDiscount!)})' : ''}',
        'AMOUNT' => '${formatMoney(value ?? 0)} menos',
        _ => 'Envío gratis',
      };

  factory CouponView.fromJson(KJson j) => CouponView(
        id: j['id'] as String,
        code: j['code'] as String,
        name: j['name'] as String? ?? '',
        type: j['type'] as String,
        value: _money(j['value']),
        maxDiscount: _money(j['maxDiscount']),
        minOrderTotal: _money(j['minOrderTotal']),
        appliesOnline: j['appliesOnline'] as bool? ?? true,
        appliesInStore: j['appliesInStore'] as bool? ?? true,
        firstOrderOnly: j['firstOrderOnly'] as bool? ?? false,
        maxUses: (j['maxUses'] as num?)?.toInt(),
        maxUsesPerCustomer: (j['maxUsesPerCustomer'] as num?)?.toInt(),
        startsAt: _date(j['startsAt']),
        endsAt: _date(j['endsAt']),
        isActive: j['isActive'] as bool? ?? true,
        customerId: (j['customer'] as KJson?)?['id'] as String?,
        customerName: (j['customer'] as KJson?)?['name'] as String?,
        uses: (j['uses'] as num?)?.toInt() ?? 0,
        saved: parseMoney(j['saved']),
        state: j['state'] as String? ?? 'ACTIVE',
      );
}

final couponsApiProvider = Provider<CouponsApi>((ref) => CouponsApi(ref.watch(dioProvider)));
final couponsProvider = FutureProvider.autoDispose<List<CouponView>>((ref) => ref.watch(couponsApiProvider).list());

class CouponsApi {
  CouponsApi(this._dio);
  final Dio _dio;

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } catch (error) {
      throw ApiException.from(error);
    }
  }

  Future<List<CouponView>> list() => _call(() async {
        final r = await _dio.get<List<dynamic>>('/coupons');
        return [for (final c in r.data!) CouponView.fromJson(c as KJson)];
      });

  Future<String> suggestCode() => _call(() async => (await _dio.get<KJson>('/coupons/suggest-code')).data!['code'] as String);

  Future<void> save(String? id, KJson data) => _call(() => id == null ? _dio.post<KJson>('/coupons', data: data) : _dio.patch<KJson>('/coupons/$id', data: data));

  Future<void> remove(String id) => _call(() => _dio.delete<void>('/coupons/$id'));
}
