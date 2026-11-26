import 'dart:async';

import 'package:devepmax_ui/devepmax_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_exception.dart';
import '../../core/device_session.dart';
import '../../core/format.dart';
import '../../core/widgets.dart';
import '../kiosk/staff_menu.dart' show NumericKeypad;
import 'clock_data.dart';

/// Reloj checador: el empleado escribe su PIN, ve cómo está y marca entrada, descanso o salida.
/// Vuelve sola al teclado después de marcar o si nadie la toca.
class ClockScreen extends ConsumerStatefulWidget {
  const ClockScreen({super.key});

  @override
  ConsumerState<ClockScreen> createState() => _ClockScreenState();
}

enum _Stage { pin, employee, done }

class _ClockScreenState extends ConsumerState<ClockScreen> {
  _Stage _stage = _Stage.pin;
  String _pin = '';
  String? _error;
  bool _busy = false;
  ClockStatus? _status;
  DateTime _now = DateTime.now();
  Timer? _tick;
  Timer? _idle;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _idle?.cancel();
    super.dispose();
  }

  void _reset() {
    _idle?.cancel();
    if (!mounted) return;
    setState(() {
      _stage = _Stage.pin;
      _pin = '';
      _status = null;
      _error = null;
      _busy = false;
    });
  }

  /// Vuelve al teclado si nadie toca la pantalla.
  void _armIdle(Duration after) {
    _idle?.cancel();
    _idle = Timer(after, _reset);
  }

  Future<void> _handleError(Object error) async {
    final e = ApiException.from(error);
    // 401 que no es por el PIN: la tablet fue desvinculada en el panel.
    if (e.statusCode == 401 && !e.message.contains('PIN')) {
      await ref.read(deviceSessionProvider.notifier).forget();
      return;
    }
    if (!mounted) return;
    setState(() {
      _error = e.message;
      if (_stage == _Stage.pin) _pin = '';
    });
  }

  Future<void> _lookup() async {
    if (_pin.length < 4 || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final status = await clockLookup(ref.read(dioProvider), _pin);
      if (!mounted) return;
      setState(() {
        _status = status;
        _stage = _Stage.employee;
      });
      _armIdle(const Duration(seconds: 25));
    } catch (error) {
      await _handleError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _punch(String action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final status = await clockPunch(ref.read(dioProvider), _pin, action);
      if (!mounted) return;
      setState(() {
        _status = status;
        _stage = _Stage.done;
        _pin = '';
      });
      _armIdle(const Duration(seconds: 4));
    } catch (error) {
      await _handleError(error);
      _armIdle(const Duration(seconds: 25));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _tap(String key) {
    setState(() {
      _error = null;
      if (key == '⌫') {
        if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1);
      } else if (_pin.length < 6) {
        _pin += key;
      }
    });
    if (_pin.length == 6) _lookup();
  }

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: Row(children: [
          Expanded(
            flex: 5,
            child: Container(
              color: t.surface,
              padding: const EdgeInsets.all(40),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const StaffLogo(height: 56),
                const Spacer(),
                Text('Reloj checador', style: TextStyle(color: t.muted, fontSize: 20, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(clockTime(_now),
                      style: TextStyle(fontSize: 96, fontWeight: FontWeight.w800, color: t.text, height: 1)),
                ),
                const SizedBox(height: 8),
                Text(longDate(_now), style: TextStyle(fontSize: 24, color: t.muted)),
                const Spacer(),
                Text('Escribe tu PIN para marcar entrada, descanso o salida.',
                    style: TextStyle(color: t.faint, fontSize: 16)),
              ]),
            ),
          ),
          Expanded(
            flex: 6,
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(32),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: switch (_stage) {
                    _Stage.pin => _pinPanel(t),
                    _Stage.employee => _employeePanel(t, _status!),
                    _Stage.done => _donePanel(t, _status!),
                  },
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _pinPanel(BrandTokens t) => Column(key: const ValueKey('pin'), mainAxisSize: MainAxisSize.min, children: [
        Text('Tu PIN', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: t.text)),
        const SizedBox(height: 16),
        Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < 6; i++)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < _pin.length ? t.primary : Colors.transparent,
                border: Border.all(color: i < _pin.length ? t.primary : t.lineStrong, width: 2),
              ),
            ),
        ]),
        SizedBox(
          height: 40,
          child: Center(
            child: _busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                : Text(_error ?? '', style: TextStyle(color: t.danger, fontWeight: FontWeight.w700, fontSize: 18)),
          ),
        ),
        SizedBox(width: 360, child: NumericKeypad(onKey: _tap, keySize: 104)),
        const SizedBox(height: 16),
        if (_pin.length >= 4 && _pin.length < 6)
          FilledButton(
            onPressed: _busy ? null : _lookup,
            style: FilledButton.styleFrom(minimumSize: const Size(220, 56)),
            child: const Text('Continuar', style: TextStyle(fontSize: 18)),
          ),
      ]);

  Widget _employeePanel(BrandTokens t, ClockStatus s) {
    final photo = mediaUrl(s.photoUrl, ref.watch(apiBaseProvider));
    final stateText = switch (s.state) {
      'IN' => 'Trabajando desde las ${clockTime(s.since!)}',
      'BREAK' => 'En descanso desde las ${clockTime(s.breakSince!)}',
      _ => 'Estás fuera',
    };
    final stateColor = switch (s.state) { 'IN' => t.success, 'BREAK' => t.warning, _ => t.muted };

    Widget action(String code) {
      final (label, icon, color) = switch (code) {
        'IN' => ('Marcar entrada', Icons.login_rounded, t.success),
        'BREAK_START' => ('Iniciar descanso', Icons.free_breakfast_rounded, t.warning),
        'BREAK_END' => ('Terminar descanso', Icons.play_arrow_rounded, t.primary),
        _ => ('Marcar salida', Icons.logout_rounded, t.danger),
      };
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: FilledButton.icon(
          onPressed: _busy ? null : () => _punch(code),
          style: FilledButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(72),
            textStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          icon: Icon(icon, size: 28),
          label: Text(label),
        ),
      );
    }

    return SizedBox(
      key: const ValueKey('employee'),
      width: 480,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          CircleAvatar(
            radius: 40,
            backgroundColor: t.surface2,
            foregroundImage: photo == null ? null : NetworkImage(photo),
            onForegroundImageError: photo == null ? null : (_, __) {},
            child: Text(s.name.isEmpty ? '?' : s.name[0].toUpperCase(),
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: t.text)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Hola, ${s.name.split(' ').first}',
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: t.text)),
              Text(stateText, style: TextStyle(fontSize: 18, color: stateColor, fontWeight: FontWeight.w600)),
            ]),
          ),
        ]),
        const SizedBox(height: 20),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (s.currentShift != null)
            DmPill('Tu turno: ${hm12(s.currentShift!.start)} – ${hm12(s.currentShift!.end)}'),
          if (s.todayWorkedMinutes > 0) DmPill('Hoy: ${hoursLabel(s.todayWorkedMinutes)}'),
          if (s.lateMinutes > 0) DmPill('Llegaste ${s.lateMinutes} min tarde', tone: DmTone.warning),
        ]),
        const SizedBox(height: 20),
        for (final a in s.actions) action(a),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: t.danger, fontWeight: FontWeight.w700)),
          ),
        if (s.upcoming.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Mis turnos', style: TextStyle(fontWeight: FontWeight.w700, color: t.muted)),
          const SizedBox(height: 6),
          for (final sh in s.upcoming.take(7))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                SizedBox(width: 90, child: Text(shiftDay(sh.day), style: TextStyle(fontWeight: FontWeight.w600, color: t.text))),
                Text('${hm12(sh.start)} – ${hm12(sh.end)}', style: TextStyle(color: t.text)),
                if (sh.position != null) Text('  ·  ${sh.position}', style: TextStyle(color: t.muted)),
              ]),
            ),
        ],
        const SizedBox(height: 12),
        TextButton(onPressed: _reset, child: const Text('No soy yo / Cancelar', style: TextStyle(fontSize: 16))),
      ]),
    );
  }

  Widget _donePanel(BrandTokens t, ClockStatus s) => Column(
        key: const ValueKey('done'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_rounded, size: 120, color: t.success),
          const SizedBox(height: 16),
          Text(s.done ?? 'Listo', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: t.text)),
          const SizedBox(height: 8),
          Text('${s.name} · ${clockTime(_now)}', style: TextStyle(fontSize: 22, color: t.muted)),
          if (s.state == 'OUT' && s.todayWorkedMinutes > 0) ...[
            const SizedBox(height: 8),
            Text('Hoy trabajaste ${hoursLabel(s.todayWorkedMinutes)}', style: TextStyle(fontSize: 20, color: t.muted)),
          ],
          const SizedBox(height: 24),
          TextButton(onPressed: _reset, child: const Text('Listo', style: TextStyle(fontSize: 18))),
        ],
      );
}
