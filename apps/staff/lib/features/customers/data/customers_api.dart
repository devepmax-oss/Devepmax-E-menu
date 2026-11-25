import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/ui/feedback.dart';

typedef CJson = Map<String, dynamic>;

DateTime? _date(Object? v) => v == null ? null : DateTime.parse(v as String).toLocal();

class CustomerSummary {
  const CustomerSummary({
    required this.id,
    required this.name,
    this.phone,
    this.email,
    required this.hasAccount,
    required this.visits,
    required this.spent,
    this.lastVisitAt,
    required this.marketingOptIn,
  });

  final String id;
  final String name;
  final String? phone;
  final String? email;

  /// Entró alguna vez a su cuenta en la web.
  final bool hasAccount;
  final int visits;
  final double spent;
  final DateTime? lastVisitAt;
  final bool marketingOptIn;

  factory CustomerSummary.fromJson(CJson j) => CustomerSummary(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        phone: j['phone'] as String?,
        email: j['email'] as String?,
        hasAccount: j['hasAccount'] as bool? ?? false,
        visits: (j['visits'] as num?)?.toInt() ?? 0,
        spent: parseMoney(j['spent']),
        lastVisitAt: _date(j['lastVisitAt']),
        marketingOptIn: j['marketingOptIn'] as bool? ?? false,
      );
}

/// (305) 555-0123 a partir de +13055550123.
String prettyPhone(String? phone) {
  if (phone == null) return '';
  final d = phone.replaceAll(RegExp(r'\D'), '');
  if (d.length == 11 && d.startsWith('1')) return '(${d.substring(1, 4)}) ${d.substring(4, 7)}-${d.substring(7)}';
  return phone;
}

class CustomerAddress {
  const CustomerAddress({this.label, required this.line});
  final String? label;
  final String line;

  factory CustomerAddress.fromJson(CJson j) => CustomerAddress(
        label: j['label'] as String?,
        line: [j['street'], j['city'], '${j['state']} ${j['zipCode']}'].whereType<String>().join(', '),
      );
}

String _itemLine(CJson i) {
  final quantity = (i['quantity'] as num?)?.toInt() ?? 1;
  final name = i['name'] as String? ?? '';
  return quantity > 1 ? '$quantity× $name' : name;
}

class CustomerVisit {
  const CustomerVisit({
    required this.id,
    required this.date,
    required this.kind,
    this.table,
    required this.orderNumbers,
    required this.status,
    required this.total,
    required this.items,
  });

  final String id;
  final DateTime date;
  final String kind;
  final String? table;
  final List<int> orderNumbers;
  final String status;
  final double total;
  final List<String> items;

  String get kindLabel => switch (kind) {
        'TABLE' => table == null ? 'Mesa' : 'Mesa $table',
        'DELIVERY' => 'Delivery',
        'PICKUP' => 'Para recoger',
        _ => 'Mostrador / para llevar',
      };

  factory CustomerVisit.fromJson(CJson j) => CustomerVisit(
        id: j['id'] as String,
        date: _date(j['date'])!,
        kind: j['kind'] as String,
        table: j['table'] as String?,
        orderNumbers: [for (final n in j['orderNumbers'] as List? ?? const []) (n as num).toInt()],
        status: j['status'] as String,
        total: parseMoney(j['total']),
        items: [for (final i in j['items'] as List? ?? const []) _itemLine(i as CJson)],
      );
}

class CustomerDetail {
  const CustomerDetail({
    required this.summary,
    this.notes,
    this.createdAt,
    required this.addresses,
    required this.history,
    this.points = 0,
    this.birthMonth,
    this.birthDay,
  });
  final CustomerSummary summary;
  final String? notes;
  final DateTime? createdAt;
  final List<CustomerAddress> addresses;
  final List<CustomerVisit> history;
  final int points;
  final int? birthMonth;
  final int? birthDay;

  factory CustomerDetail.fromJson(CJson j) => CustomerDetail(
        points: (j['points'] as num?)?.toInt() ?? 0,
        birthMonth: ((j['birthday'] as CJson?)?['month'] as num?)?.toInt(),
        birthDay: ((j['birthday'] as CJson?)?['day'] as num?)?.toInt(),
        summary: CustomerSummary.fromJson(j),
        notes: j['notes'] as String?,
        createdAt: _date(j['createdAt']),
        addresses: [for (final a in j['addresses'] as List? ?? const []) CustomerAddress.fromJson(a as CJson)],
        history: [for (final h in j['history'] as List? ?? const []) CustomerVisit.fromJson(h as CJson)],
      );
}

/// Premio vigente (cupón personal) de un cliente.
class LoyaltyReward {
  const LoyaltyReward({required this.code, required this.name, this.value, this.endsAt});
  final String code;
  final String name;
  final double? value;
  final DateTime? endsAt;
}

class LoyaltyInfo {
  const LoyaltyInfo({required this.enabled, required this.points, required this.rewardPoints, required this.rewards});
  final bool enabled;
  final int points;
  final int rewardPoints;
  final List<LoyaltyReward> rewards;

  factory LoyaltyInfo.fromJson(CJson j) => LoyaltyInfo(
        enabled: j['enabled'] as bool? ?? false,
        points: (j['points'] as num?)?.toInt() ?? 0,
        rewardPoints: (j['rewardPoints'] as num?)?.toInt() ?? 0,
        rewards: [
          for (final r in j['rewards'] as List? ?? const [])
            LoyaltyReward(
              code: (r as CJson)['code'] as String,
              name: r['name'] as String? ?? '',
              value: r['value'] == null ? null : parseMoney(r['value']),
              endsAt: _date(r['endsAt']),
            ),
        ],
      );
}

final customerLoyaltyProvider = FutureProvider.autoDispose.family<LoyaltyInfo, String>(
  (ref, id) => ref.watch(customersApiProvider).loyalty(id),
);

final customersApiProvider = Provider<CustomersApi>((ref) => CustomersApi(ref.watch(dioProvider)));

/// Búsqueda, filtro y orden de la pantalla Clientes.
typedef CustomerQuery = ({String q, String filter, String sort});

final customerSearchProvider = FutureProvider.autoDispose.family<(int, List<CustomerSummary>), CustomerQuery>(
  (ref, query) => ref.watch(customersApiProvider).list(q: query.q, filter: query.filter, sort: query.sort),
);

final customerDetailProvider = FutureProvider.autoDispose.family<CustomerDetail, String>(
  (ref, id) => ref.watch(customersApiProvider).detail(id),
);

class CustomersApi {
  CustomersApi(this._dio);
  final Dio _dio;

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } catch (error) {
      throw ApiException.from(error);
    }
  }

  Future<(int, List<CustomerSummary>)> list({String q = '', String filter = 'all', String sort = 'recent', int offset = 0}) => _call(() async {
        final r = await _dio.get<CJson>('/customers', queryParameters: {
          if (q.trim().isNotEmpty) 'q': q.trim(),
          'filter': filter,
          'sort': sort,
          'offset': offset,
          'limit': 100,
        });
        final data = r.data!;
        return (
          (data['total'] as num).toInt(),
          [for (final c in data['customers'] as List) CustomerSummary.fromJson(c as CJson)],
        );
      });

  Future<CustomerDetail> detail(String id) => _call(() async => CustomerDetail.fromJson((await _dio.get<CJson>('/customers/$id')).data!));

  Future<CustomerDetail> update(
    String id, {
    String? name,
    String? notes,
    bool clearNotes = false,
    bool? marketingOptIn,
    String? phone,
    String? email,
  }) =>
      _call(() async {
        final r = await _dio.patch<CJson>('/customers/$id', data: {
          if (name != null) 'name': name,
          if (phone != null) 'phone': phone.trim().isEmpty ? null : phone.trim(),
          if (email != null) 'email': email.trim().isEmpty ? null : email.trim(),
          if (notes != null || clearNotes) 'notes': clearNotes ? null : notes,
          if (marketingOptIn != null) 'marketingOptIn': marketingOptIn,
        });
        return CustomerDetail.fromJson(r.data!);
      });

  Future<void> remove(String id) => _call(() => _dio.delete<void>('/customers/$id'));

  Future<LoyaltyInfo> loyalty(String id) => _call(() async => LoyaltyInfo.fromJson((await _dio.get<CJson>('/customers/$id/loyalty')).data!));

  Future<void> adjustPoints(String id, int points, String reason) =>
      _call(() => _dio.post<CJson>('/customers/$id/loyalty/adjust', data: {'points': points, 'reason': reason}));

  Future<void> setBirthday(String id, int? month, int? day) =>
      _call(() => _dio.patch<CJson>('/customers/$id', data: {'birthMonth': month, 'birthDay': day}));

  /// Junta [fromId] dentro de [id]: todo pasa a [id] y [fromId] se borra.
  Future<CustomerDetail> merge(String id, String fromId) =>
      _call(() async => CustomerDetail.fromJson((await _dio.post<CJson>('/customers/$id/merge', data: {'fromId': fromId})).data!));

  /// Enlace de descarga del Excel (vale 10 minutos).
  Future<String> exportLink({String q = '', String filter = 'all'}) => _call(() async {
        final r = await _dio.post<CJson>('/customers/export-link', data: {if (q.trim().isNotEmpty) 'q': q.trim(), 'filter': filter});
        return r.data!['url'] as String;
      });

  /// null = no hay cliente con ese teléfono.
  Future<CustomerSummary?> lookup(String phone) => _call(() async {
        final r = await _dio.get<CJson>('/customers/lookup', queryParameters: {'phone': phone});
        final c = r.data!['customer'] as CJson?;
        return c == null ? null : CustomerSummary.fromJson(c);
      });

  Future<CustomerSummary> create({required String name, required String phone, String? email}) => _call(() async {
        final r = await _dio.post<CJson>('/customers', data: {
          'name': name,
          'phone': phone,
          if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
        });
        return CustomerSummary.fromJson(r.data!['customer'] as CJson);
      });

  Future<void> attachToBill(String billId, String? customerId) =>
      _call(() => _dio.patch<CJson>('/billing/bills/$billId/customer', data: {'customerId': customerId}));

  Future<void> attachToTable(String tableId, String? customerId) =>
      _call(() => _dio.patch<CJson>('/tables/$tableId/customer', data: {'customerId': customerId}));
}
