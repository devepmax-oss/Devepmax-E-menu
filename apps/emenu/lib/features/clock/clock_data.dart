import 'package:dio/dio.dart';

import '../../core/api_exception.dart';

typedef CJson = Map<String, dynamic>;

DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();

/// Un turno programado (horas locales del restaurante, "HH:mm").
class ClockShift {
  const ClockShift({required this.day, required this.start, required this.end, this.position});
  final String day;
  final String start;
  final String end;
  final String? position;

  factory ClockShift.fromJson(CJson j) => ClockShift(
        day: j['day'] as String,
        start: j['start'] as String,
        end: j['end'] as String,
        position: j['position'] as String?,
      );
}

/// Lo que ve el empleado después de escribir su PIN.
class ClockStatus {
  const ClockStatus({
    required this.name,
    this.photoUrl,
    this.jobTitle,
    required this.state,
    this.since,
    this.breakSince,
    required this.actions,
    required this.todayWorkedMinutes,
    this.currentShift,
    required this.lateMinutes,
    required this.upcoming,
    this.done,
  });

  final String name;
  final String? photoUrl;
  final String? jobTitle;

  /// OUT, IN o BREAK.
  final String state;
  final DateTime? since;
  final DateTime? breakSince;
  final List<String> actions;
  final int todayWorkedMinutes;
  final ClockShift? currentShift;
  final int lateMinutes;
  final List<ClockShift> upcoming;

  /// Mensaje de lo que se acaba de marcar.
  final String? done;

  factory ClockStatus.fromJson(CJson j) {
    final e = j['employee'] as CJson;
    return ClockStatus(
      name: e['name'] as String,
      photoUrl: e['photoUrl'] as String?,
      jobTitle: e['jobTitle'] as String?,
      state: j['state'] as String,
      since: _date(j['since']),
      breakSince: _date(j['breakSince']),
      actions: ((j['actions'] as List?) ?? const []).cast<String>(),
      todayWorkedMinutes: (j['todayWorkedMinutes'] as num?)?.toInt() ?? 0,
      currentShift: j['currentShift'] == null ? null : ClockShift.fromJson(j['currentShift'] as CJson),
      lateMinutes: (j['lateMinutes'] as num?)?.toInt() ?? 0,
      upcoming: [for (final s in (j['upcomingShifts'] as List?) ?? const []) ClockShift.fromJson(s as CJson)],
      done: j['done'] as String?,
    );
  }
}

/// El PIN equivocado no desvincula la tablet (por eso `extra: pin`).
final _pinOptions = Options(extra: {'pin': true});

Future<ClockStatus> clockLookup(Dio dio, String pin) async {
  try {
    final r = await dio.post<CJson>('/timeclock/device/lookup', data: {'pin': pin}, options: _pinOptions);
    return ClockStatus.fromJson(r.data!);
  } catch (error) {
    throw ApiException.from(error);
  }
}

Future<ClockStatus> clockPunch(Dio dio, String pin, String action) async {
  try {
    final r = await dio.post<CJson>('/timeclock/device/punch', data: {'pin': pin, 'action': action}, options: _pinOptions);
    return ClockStatus.fromJson(r.data!);
  } catch (error) {
    throw ApiException.from(error);
  }
}

// ───────── Formato ─────────

const _weekdays = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
const _months = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];

/// "9:05 AM".
String clockTime(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
}

/// "17:30" → "5:30 PM".
String hm12(String hm) {
  final parts = hm.split(':');
  final h = int.tryParse(parts.first) ?? 0;
  return clockTime(DateTime(2000, 1, 1, h, int.tryParse(parts.last) ?? 0));
}

/// "Miércoles 25 de noviembre".
String longDate(DateTime d) {
  final w = _weekdays[d.weekday - 1];
  return '${w[0].toUpperCase()}${w.substring(1)} ${d.day} de ${_months[d.month - 1]}';
}

/// "2026-11-27" → "Hoy", "Mañana" o "Vie 27".
String shiftDay(String day) {
  final d = DateTime.tryParse(day);
  if (d == null) return day;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final diff = DateTime(d.year, d.month, d.day).difference(today).inDays;
  if (diff == 0) return 'Hoy';
  if (diff == 1) return 'Mañana';
  final w = _weekdays[d.weekday - 1];
  return '${w[0].toUpperCase()}${w.substring(1, 3)} ${d.day}';
}

/// 125 → "2 h 05 min".
String hoursLabel(int minutes) {
  if (minutes < 60) return '$minutes min';
  return '${minutes ~/ 60} h ${(minutes % 60).toString().padLeft(2, '0')} min';
}
