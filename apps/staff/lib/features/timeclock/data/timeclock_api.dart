import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';

typedef TJson = Map<String, dynamic>;

DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();
int _int(Object? v) => (v as num?)?.toInt() ?? 0;

class PersonBrief {
  const PersonBrief({required this.id, required this.name, this.photoUrl, this.jobTitle, required this.roleName});
  final String id;
  final String name;
  final String? photoUrl;
  final String? jobTitle;
  final String roleName;

  factory PersonBrief.fromJson(TJson j) => PersonBrief(
        id: j['id'] as String,
        name: j['name'] as String,
        photoUrl: j['photoUrl'] as String?,
        jobTitle: j['jobTitle'] as String?,
        roleName: j['roleName'] as String? ?? '',
      );
}

/// Un turno del horario. Día y horas en la zona del restaurante.
class ShiftView {
  const ShiftView({
    required this.id,
    required this.employeeId,
    required this.day,
    required this.start,
    required this.end,
    required this.minutes,
    this.position,
    this.note,
  });
  final String id;
  final String employeeId;
  final String day;
  final String start;
  final String end;
  final int minutes;
  final String? position;
  final String? note;

  factory ShiftView.fromJson(TJson j) => ShiftView(
        id: j['id'] as String,
        employeeId: j['employeeId'] as String,
        day: j['day'] as String,
        start: j['start'] as String,
        end: j['end'] as String,
        minutes: _int(j['minutes']),
        position: j['position'] as String?,
        note: j['note'] as String?,
      );
}

class WeekSchedule {
  const WeekSchedule({required this.weekStart, required this.days, required this.employees, required this.shifts, required this.totals});
  final String weekStart;
  final List<String> days;
  final List<PersonBrief> employees;
  final List<ShiftView> shifts;
  final Map<String, int> totals;

  factory WeekSchedule.fromJson(TJson j) => WeekSchedule(
        weekStart: j['weekStart'] as String,
        days: (j['days'] as List).cast<String>(),
        employees: [for (final e in j['employees'] as List) PersonBrief.fromJson(e as TJson)],
        shifts: [for (final s in j['shifts'] as List) ShiftView.fromJson(s as TJson)],
        totals: {for (final e in (j['totals'] as Map).entries) '${e.key}': _int(e.value)},
      );
}

class BreakView {
  const BreakView({required this.startTime, this.endTime});
  final String startTime;
  final String? endTime;
  factory BreakView.fromJson(TJson j) => BreakView(startTime: j['startTime'] as String, endTime: j['endTime'] as String?);
}

/// Una jornada del reloj checador.
class EntryView {
  const EntryView({
    required this.id,
    required this.employeeId,
    this.employee,
    required this.day,
    required this.inTime,
    this.outTime,
    required this.breaks,
    required this.source,
    this.editedAt,
    this.editedBy,
    this.editReason,
    required this.open,
    required this.missingOut,
    this.shift,
    required this.lateMinutes,
    required this.breakMinutes,
    required this.unpaidBreakMinutes,
    required this.workedMinutes,
  });
  final String id;
  final String employeeId;
  final PersonBrief? employee;
  final String day;
  final String inTime;
  final String? outTime;
  final List<BreakView> breaks;
  final String source;
  final DateTime? editedAt;
  final String? editedBy;
  final String? editReason;
  final bool open;
  final bool missingOut;
  final ShiftView? shift;
  final int lateMinutes;
  final int breakMinutes;
  final int unpaidBreakMinutes;
  final int workedMinutes;

  bool get edited => editedAt != null;

  factory EntryView.fromJson(TJson j) {
    final edited = j['edited'] as TJson?;
    return EntryView(
      id: j['id'] as String,
      employeeId: j['employeeId'] as String,
      employee: j['employee'] == null ? null : PersonBrief.fromJson(j['employee'] as TJson),
      day: j['day'] as String,
      inTime: j['inTime'] as String,
      outTime: j['outTime'] as String?,
      breaks: [for (final b in (j['breaks'] as List?) ?? const []) BreakView.fromJson(b as TJson)],
      source: j['source'] as String? ?? 'CLOCK',
      editedAt: _date(edited?['at']),
      editedBy: edited?['byName'] as String?,
      editReason: edited?['reason'] as String?,
      open: j['open'] as bool? ?? false,
      missingOut: j['missingOut'] as bool? ?? false,
      shift: j['shift'] == null ? null : ShiftView.fromJson(j['shift'] as TJson),
      lateMinutes: _int(j['lateMinutes']),
      breakMinutes: _int(j['breakMinutes']),
      unpaidBreakMinutes: _int(j['unpaidBreakMinutes']),
      workedMinutes: _int(j['workedMinutes']),
    );
  }
}

class EntryTotals {
  const EntryTotals({required this.employee, required this.entries, required this.workedMinutes, required this.lateCount, required this.lateMinutes});
  final PersonBrief employee;
  final int entries;
  final int workedMinutes;
  final int lateCount;
  final int lateMinutes;

  factory EntryTotals.fromJson(TJson j) => EntryTotals(
        employee: PersonBrief.fromJson(j['employee'] as TJson),
        entries: _int(j['entries']),
        workedMinutes: _int(j['workedMinutes']),
        lateCount: _int(j['lateCount']),
        lateMinutes: _int(j['lateMinutes']),
      );
}

class EntriesResult {
  const EntriesResult({required this.from, required this.to, required this.entries, required this.totals});
  final String from;
  final String to;
  final List<EntryView> entries;
  final List<EntryTotals> totals;

  factory EntriesResult.fromJson(TJson j) => EntriesResult(
        from: j['from'] as String,
        to: j['to'] as String,
        entries: [for (final e in j['entries'] as List) EntryView.fromJson(e as TJson)],
        totals: [for (final t in j['totals'] as List) EntryTotals.fromJson(t as TJson)],
      );
}

class WorkingNow {
  const WorkingNow({required this.entryId, required this.employee, required this.state, required this.since, this.breakSince, required this.workedMinutes});
  final String entryId;
  final PersonBrief employee;
  final String state;
  final DateTime since;
  final DateTime? breakSince;
  final int workedMinutes;

  factory WorkingNow.fromJson(TJson j) => WorkingNow(
        entryId: j['entryId'] as String,
        employee: PersonBrief.fromJson(j['employee'] as TJson),
        state: j['state'] as String,
        since: _date(j['since'])!,
        breakSince: _date(j['breakSince']),
        workedMinutes: _int(j['workedMinutes']),
      );
}

class NowView {
  const NowView({required this.working, required this.notClockedIn, required this.missingOut});
  final List<WorkingNow> working;
  final List<(PersonBrief, ShiftView)> notClockedIn;
  final List<EntryView> missingOut;

  factory NowView.fromJson(TJson j) => NowView(
        working: [for (final w in j['working'] as List) WorkingNow.fromJson(w as TJson)],
        notClockedIn: [
          for (final n in j['notClockedIn'] as List)
            (PersonBrief.fromJson((n as TJson)['employee'] as TJson), ShiftView.fromJson(n['shift'] as TJson)),
        ],
        missingOut: [for (final e in j['missingOut'] as List) EntryView.fromJson(e as TJson)],
      );
}

typedef EntriesQuery = ({String from, String to, String? employeeId});

final timeclockApiProvider = Provider<TimeclockApi>((ref) => TimeclockApi(ref.watch(dioProvider)));
final nowProvider = FutureProvider.autoDispose<NowView>((ref) => ref.watch(timeclockApiProvider).now());
final weekProvider = FutureProvider.autoDispose.family<WeekSchedule, String>((ref, week) => ref.watch(timeclockApiProvider).week(week));
final entriesProvider =
    FutureProvider.autoDispose.family<EntriesResult, EntriesQuery>((ref, q) => ref.watch(timeclockApiProvider).entries(q));
final timeclockSettingsProvider = FutureProvider.autoDispose<TJson>((ref) => ref.watch(timeclockApiProvider).settings());

class TimeclockApi {
  TimeclockApi(this._dio);
  final Dio _dio;

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } catch (error) {
      throw ApiException.from(error);
    }
  }

  Future<NowView> now() => _call(() async => NowView.fromJson((await _dio.get<TJson>('/timeclock/now')).data!));
  Future<WeekSchedule> week(String week) =>
      _call(() async => WeekSchedule.fromJson((await _dio.get<TJson>('/schedule', queryParameters: {'week': week})).data!));
  Future<EntriesResult> entries(EntriesQuery q) => _call(() async => EntriesResult.fromJson((await _dio.get<TJson>(
        '/timeclock/entries',
        queryParameters: {'from': q.from, 'to': q.to, if (q.employeeId != null) 'employeeId': q.employeeId},
      ))
          .data!));
  Future<void> saveEntry(String? id, TJson data) =>
      _call(() => id == null ? _dio.post('/timeclock/entries', data: data) : _dio.put('/timeclock/entries/$id', data: data));
  Future<void> deleteEntry(String id, String reason) =>
      _call(() => _dio.delete('/timeclock/entries/$id', data: {'reason': reason}));
  Future<void> punchFor(String employeeId, String action, {String? reason}) => _call(() =>
      _dio.post('/timeclock/employees/$employeeId/punch', data: {'action': action, if (reason != null && reason.isNotEmpty) 'reason': reason}));
  Future<void> saveShift(String? id, TJson data) =>
      _call(() => id == null ? _dio.post('/schedule/shifts', data: data) : _dio.put('/schedule/shifts/$id', data: data));
  Future<void> deleteShift(String id) => _call(() => _dio.delete('/schedule/shifts/$id'));
  Future<(int, int)> copyWeek(String fromWeek, String toWeek) => _call(() async {
        final r = await _dio.post<TJson>('/schedule/copy-week', data: {'fromWeek': fromWeek, 'toWeek': toWeek});
        return (_int(r.data?['copied']), _int(r.data?['skipped']));
      });
  Future<TJson> settings() => _call(() async => (await _dio.get<TJson>('/timeclock/settings')).data!);
  Future<void> updateSettings(TJson data) => _call(() => _dio.patch('/timeclock/settings', data: data));
}

// ───────── Formato ─────────

/// "17:30" → "5:30 PM".
String hm12(String hm) {
  final parts = hm.split(':');
  final h = int.tryParse(parts.first) ?? 0;
  final m = parts.length > 1 ? parts[1] : '00';
  return '${h % 12 == 0 ? 12 : h % 12}:$m ${h < 12 ? 'AM' : 'PM'}';
}

/// "17:30" → "5:30p" (para celdas pequeñas).
String hmShort(String hm) {
  final parts = hm.split(':');
  final h = int.tryParse(parts.first) ?? 0;
  final m = parts.length > 1 ? parts[1] : '00';
  return '${h % 12 == 0 ? 12 : h % 12}${m == '00' ? '' : ':$m'}${h < 12 ? 'a' : 'p'}';
}

/// 450 → "7 h 30".
String hoursLabel(int minutes) {
  if (minutes < 60) return '$minutes min';
  final m = minutes % 60;
  return m == 0 ? '${minutes ~/ 60} h' : '${minutes ~/ 60} h ${m.toString().padLeft(2, '0')}';
}

/// AAAA-MM-DD de una fecha local.
String isoDay(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime parseDay(String day) {
  final p = day.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

const weekdayShort = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
const monthShort = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

/// "Lun 23 nov".
String dayLabel(String day) {
  final d = parseDay(day);
  return '${weekdayShort[d.weekday - 1]} ${d.day} ${monthShort[d.month - 1]}';
}

/// Lunes de la semana de [d].
DateTime mondayOf(DateTime d) => DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));
