import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../timeclock/data/timeclock_api.dart' show PersonBrief;

typedef PJson = Map<String, dynamic>;

double _d(Object? v) => v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);
int _i(Object? v) => (v as num?)?.toInt() ?? 0;

class OvertimeRule {
  const OvertimeRule({
    required this.weeklyHours,
    required this.dailyHours,
    required this.doubleDailyHours,
    required this.overtimeMultiplier,
    required this.doubleMultiplier,
    this.preset = 'custom',
  });
  final int weeklyHours;
  final int dailyHours;
  final int doubleDailyHours;
  final double overtimeMultiplier;
  final double doubleMultiplier;

  /// federal, california, none o custom.
  final String preset;

  factory OvertimeRule.fromJson(PJson j) => OvertimeRule(
        weeklyHours: _i(j['weeklyHours']),
        dailyHours: _i(j['dailyHours']),
        doubleDailyHours: _i(j['doubleDailyHours']),
        overtimeMultiplier: _d(j['overtimeMultiplier']),
        doubleMultiplier: _d(j['doubleMultiplier']),
        preset: j['preset'] as String? ?? 'custom',
      );

  PJson toJson() => {
        'weeklyHours': weeklyHours,
        'dailyHours': dailyHours,
        'doubleDailyHours': doubleDailyHours,
        'overtimeMultiplier': overtimeMultiplier,
        'doubleMultiplier': doubleMultiplier,
      };

  /// "Extra después de 40 h por semana (1.5x)".
  String get description {
    final parts = [
      if (weeklyHours > 0) 'después de $weeklyHours h por semana',
      if (dailyHours > 0) 'después de $dailyHours h por día',
    ];
    if (parts.isEmpty && doubleDailyHours == 0) return 'Sin horas extra';
    final extra = parts.isEmpty ? '' : 'Extra ${parts.join(' y ')} (${_x(overtimeMultiplier)})';
    final dbl = doubleDailyHours > 0 ? 'doble después de $doubleDailyHours h por día (${_x(doubleMultiplier)})' : '';
    return [extra, dbl].where((s) => s.isNotEmpty).join('; ');
  }
}

String _x(double v) => '${v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString()}x';

class PayrollRow {
  const PayrollRow({
    required this.employee,
    this.currentRate,
    required this.daysWithoutRate,
    required this.openEntries,
    required this.entries,
    required this.regularMinutes,
    required this.overtimeMinutes,
    required this.doubleMinutes,
    required this.regularPay,
    required this.overtimePay,
    required this.doublePay,
    required this.wages,
    required this.cardTips,
    required this.cashTips,
    required this.total,
    required this.weeks,
  });
  final PersonBrief employee;
  final double? currentRate;
  final int daysWithoutRate;
  final int openEntries;
  final int entries;
  final int regularMinutes;
  final int overtimeMinutes;
  final int doubleMinutes;
  final double regularPay;
  final double overtimePay;
  final double doublePay;
  final double wages;
  final double cardTips;
  final double cashTips;
  final double total;
  final List<({String weekStart, int regular, int overtime, int dbl})> weeks;

  factory PayrollRow.fromJson(PJson j) {
    final tips = j['tips'] as PJson? ?? const {};
    return PayrollRow(
      employee: PersonBrief.fromJson(j['employee'] as PJson),
      currentRate: j['currentRate'] == null ? null : _d(j['currentRate']),
      daysWithoutRate: _i(j['daysWithoutRate']),
      openEntries: _i(j['openEntries']),
      entries: _i(j['entries']),
      regularMinutes: _i(j['regularMinutes']),
      overtimeMinutes: _i(j['overtimeMinutes']),
      doubleMinutes: _i(j['doubleMinutes']),
      regularPay: _d(j['regularPay']),
      overtimePay: _d(j['overtimePay']),
      doublePay: _d(j['doublePay']),
      wages: _d(j['wages']),
      cardTips: _d(tips['card']),
      cashTips: _d(tips['cash']),
      total: _d(j['total']),
      weeks: [
        for (final w in (j['weeks'] as List?) ?? const [])
          (
            weekStart: (w as PJson)['weekStart'] as String,
            regular: _i(w['regularMinutes']),
            overtime: _i(w['overtimeMinutes']),
            dbl: _i(w['doubleMinutes']),
          ),
      ],
    );
  }
}

class PayrollResult {
  const PayrollResult({
    required this.from,
    required this.to,
    required this.weeks,
    required this.rule,
    required this.rows,
    required this.wages,
    required this.cardTips,
    required this.cashTips,
    required this.total,
    required this.regularMinutes,
    required this.overtimeMinutes,
    required this.doubleMinutes,
    required this.unassignedTips,
  });
  final String from;
  final String to;
  final int weeks;
  final OvertimeRule rule;
  final List<PayrollRow> rows;
  final double wages;
  final double cardTips;
  final double cashTips;
  final double total;
  final int regularMinutes;
  final int overtimeMinutes;
  final int doubleMinutes;
  final double unassignedTips;

  factory PayrollResult.fromJson(PJson j) {
    final t = j['totals'] as PJson;
    return PayrollResult(
      from: j['from'] as String,
      to: j['to'] as String,
      weeks: _i(j['weeks']),
      rule: OvertimeRule.fromJson(j['rule'] as PJson),
      rows: [for (final r in j['employees'] as List) PayrollRow.fromJson(r as PJson)],
      wages: _d(t['wages']),
      cardTips: _d(t['cardTips']),
      cashTips: _d(t['cashTips']),
      total: _d(t['total']),
      regularMinutes: _i(t['regularMinutes']),
      overtimeMinutes: _i(t['overtimeMinutes']),
      doubleMinutes: _i(t['doubleMinutes']),
      unassignedTips: _d(j['unassignedTips']),
    );
  }
}

class PerformanceRow {
  const PerformanceRow(this.employee, this.j);
  final PersonBrief employee;
  final PJson j;

  int get bills => _i(j['bills']);
  double get netSales => _d(j['netSales']);
  double get averageTicket => _d(j['averageTicket']);
  int get tables => _i(j['tables']);
  int get guests => _i(j['guests']);
  int get ordersTaken => _i(j['ordersTaken']);
  int get payments => _i(j['payments']);
  double get collected => _d(j['collected']);
  double get tips => _d(j['tips']);
  double get tipPercent => _d(j['tipPercent']);
  int get workedMinutes => _i(j['workedMinutes']);
  double get salesPerHour => _d(j['salesPerHour']);
  int get cancellations => _i(j['cancellations']);
  int get voids => _i(j['voids']);
  double get voidAmount => _d(j['voidAmount']);
  int get discounts => _i(j['discounts']);
  double get discountAmount => _d(j['discountAmount']);
  int get discountsAuthorized => _i(j['discountsAuthorized']);
  int get refunds => _i(j['refunds']);
  double get refundAmount => _d(j['refundAmount']);

  factory PerformanceRow.fromJson(PJson j) => PerformanceRow(PersonBrief.fromJson(j['employee'] as PJson), j);
}

class RateInfo {
  const RateInfo({required this.employee, required this.isActive, this.currentRate, this.nextChange, required this.history});
  final PersonBrief employee;
  final bool isActive;
  final double? currentRate;
  final ({String id, double rate, String from})? nextChange;
  final List<({String id, double rate, String from})> history;

  factory RateInfo.fromJson(PJson j) {
    ({String id, double rate, String from}) rate(PJson r) =>
        (id: r['id'] as String, rate: _d(r['hourlyRate']), from: r['effectiveFrom'] as String);
    final e = j['employee'] as PJson;
    return RateInfo(
      employee: PersonBrief.fromJson(e),
      isActive: e['isActive'] as bool? ?? true,
      currentRate: j['currentRate'] == null ? null : _d(j['currentRate']),
      nextChange: j['nextChange'] == null ? null : rate(j['nextChange'] as PJson),
      history: [for (final r in (j['history'] as List?) ?? const []) rate(r as PJson)],
    );
  }
}

typedef PayrollQuery = ({String week, int weeks});
typedef RangeQuery = ({String from, String to});

final payrollApiProvider = Provider<PayrollApi>((ref) => PayrollApi(ref.watch(dioProvider)));
final payrollProvider =
    FutureProvider.autoDispose.family<PayrollResult, PayrollQuery>((ref, q) => ref.watch(payrollApiProvider).payroll(q));
final performanceProvider =
    FutureProvider.autoDispose.family<List<PerformanceRow>, RangeQuery>((ref, q) => ref.watch(payrollApiProvider).performance(q));
final ratesProvider = FutureProvider.autoDispose<List<RateInfo>>((ref) => ref.watch(payrollApiProvider).rates());
final payrollRuleProvider = FutureProvider.autoDispose<OvertimeRule>((ref) => ref.watch(payrollApiProvider).rule());

class PayrollApi {
  PayrollApi(this._dio);
  final Dio _dio;

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } catch (error) {
      throw ApiException.from(error);
    }
  }

  Future<PayrollResult> payroll(PayrollQuery q) => _call(() async => PayrollResult.fromJson(
      (await _dio.get<PJson>('/payroll', queryParameters: {'week': q.week, 'weeks': q.weeks})).data!));
  Future<String> exportLink(PayrollQuery q) => _call(() async =>
      (await _dio.post<PJson>('/payroll/export-link', data: {'week': q.week, 'weeks': q.weeks})).data!['url'] as String);
  Future<List<PerformanceRow>> performance(RangeQuery q) => _call(() async {
        final r = await _dio.get<PJson>('/performance', queryParameters: {'from': q.from, 'to': q.to});
        return [for (final e in r.data!['employees'] as List) PerformanceRow.fromJson(e as PJson)];
      });
  Future<List<RateInfo>> rates() => _call(() async {
        final r = await _dio.get<List<dynamic>>('/payroll/rates');
        return [for (final e in r.data!) RateInfo.fromJson(e as PJson)];
      });
  Future<void> setRate(String employeeId, double rate, String? from) => _call(() =>
      _dio.put('/payroll/rates/$employeeId', data: {'hourlyRate': rate, if (from != null) 'effectiveFrom': from}));
  Future<void> deleteRate(String id) => _call(() => _dio.delete('/payroll/rates/$id'));
  Future<OvertimeRule> rule() =>
      _call(() async => OvertimeRule.fromJson((await _dio.get<PJson>('/payroll/settings')).data!));
  Future<OvertimeRule> saveRule(OvertimeRule rule) =>
      _call(() async => OvertimeRule.fromJson((await _dio.patch<PJson>('/payroll/settings', data: rule.toJson())).data!));
}
