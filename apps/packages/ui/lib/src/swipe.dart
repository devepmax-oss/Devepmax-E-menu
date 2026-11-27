import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';

/// Botón de "desliza para confirmar": una píldora del color de la marca con una perilla
/// que se arrastra hasta el final. Sirve para acciones que no se deben hacer por un toque
/// accidental (cobrar, enviar a cocina, marcar entregado).
///
/// - Arrastrar la perilla más del 85 % confirma; si se suelta antes, regresa.
/// - Un toque sin arrastrar solo hace un pequeño amago para enseñar el gesto.
/// - Con teclado (Enter o Espacio) o con lector de pantalla se confirma directo,
///   para que nadie quede sin poder usarlo.
/// - Mientras [onConfirm] trabaja, la perilla se queda al final con un indicador.
///
/// No usa LayoutBuilder, así que se puede poner dentro de un AlertDialog.
class SwipeToConfirm extends StatefulWidget {
  const SwipeToConfirm({
    super.key,
    required this.label,
    required this.onConfirm,
    this.busy = false,
    this.busyLabel,
    this.hint = 'Desliza para confirmar',
    this.height = 64,
    this.icon,
  });

  /// Texto del centro: "Desliza para cobrar $24.50".
  final String label;

  /// null = desactivado.
  final FutureOr<void> Function()? onConfirm;

  /// Ocupado desde fuera (por ejemplo, ya se está enviando).
  final bool busy;
  final String? busyLabel;

  /// Lo que oye el lector de pantalla y lo que se ve en el amago.
  final String hint;
  final double height;

  /// Ícono de la perilla; por defecto, flechas dobles.
  final IconData? icon;

  @override
  State<SwipeToConfirm> createState() => _SwipeToConfirmState();
}

class _SwipeToConfirmState extends State<SwipeToConfirm> with SingleTickerProviderStateMixin {
  static const _threshold = 0.85;
  static const _inset = 5.0;

  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 240));
  final FocusNode _focus = FocusNode(debugLabel: 'SwipeToConfirm');
  bool _running = false;
  bool _dragging = false;
  bool _focused = false;

  bool get _busy => widget.busy || _running;
  bool get _enabled => widget.onConfirm != null && !_busy;

  @override
  void didUpdateWidget(covariant SwipeToConfirm old) {
    super.didUpdateWidget(old);
    // Terminó el trabajo de afuera: la perilla regresa.
    if (old.busy && !widget.busy && !_running && !_dragging) _c.animateBack(0, curve: Curves.easeOutCubic);
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  double _travel() {
    final box = context.findRenderObject() as RenderBox?;
    final width = box?.hasSize == true ? box!.size.width : 0.0;
    return (width - widget.height).clamp(1.0, double.infinity);
  }

  Future<void> _confirm() async {
    final action = widget.onConfirm;
    if (action == null || _busy) return;
    HapticFeedback.mediumImpact();
    setState(() => _running = true);
    await _c.animateTo(1, curve: Curves.easeOutCubic);
    try {
      await action();
    } finally {
      if (mounted) {
        setState(() => _running = false);
        if (!widget.busy) _c.animateBack(0, curve: Curves.easeOutCubic);
      }
    }
  }

  Future<void> _nudge() async {
    if (!_enabled || _c.isAnimating) return;
    HapticFeedback.selectionClick();
    await _c.animateTo(0.16, duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
    if (mounted) await _c.animateBack(0, duration: const Duration(milliseconds: 260), curve: Curves.elasticOut);
  }

  void _dragUpdate(DragUpdateDetails d) {
    if (!_enabled) return;
    _c.value = (_c.value + d.primaryDelta! / _travel()).clamp(0.0, 1.0);
  }

  void _dragEnd(DragEndDetails d) {
    if (!_enabled) return;
    setState(() => _dragging = false);
    final fast = (d.primaryVelocity ?? 0) > 1400 && _c.value > 0.5;
    if (_c.value >= _threshold || fast) {
      _confirm();
    } else {
      _c.animateBack(0, curve: Curves.easeOutBack);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final on = widget.onConfirm != null;
    final track = on ? t.primary : t.surface3;
    final ink = on ? t.onPrimary : t.faint;
    final knob = on ? t.onPrimary : t.surface2;
    final knobInk = on ? t.primary : t.faint;
    final h = widget.height;
    final label = _busy ? (widget.busyLabel ?? widget.label) : widget.label;

    return Semantics(
      button: true,
      enabled: _enabled,
      label: widget.label,
      hint: widget.hint,
      onTap: _enabled ? _confirm : null,
      excludeSemantics: true,
      child: FocusableActionDetector(
        focusNode: _focus,
        enabled: on,
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: {ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => _confirm())},
        mouseCursor: on ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _nudge,
          onHorizontalDragStart: _enabled ? (_) => setState(() => _dragging = true) : null,
          onHorizontalDragUpdate: _dragUpdate,
          onHorizontalDragEnd: _dragEnd,
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final p = _busy ? 1.0 : _c.value;
              return Container(
                height: h,
                decoration: BoxDecoration(
                  color: track,
                  borderRadius: BorderRadius.circular(h / 2),
                  border: _focused ? Border.all(color: t.accent, width: 3) : null,
                  boxShadow: on ? [BoxShadow(color: t.primary.withValues(alpha: 0.28), blurRadius: 18, offset: const Offset(0, 8))] : null,
                ),
                child: Stack(children: [
                  // Lo recorrido se aclara un poco detrás de la perilla.
                  Positioned.fill(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: p,
                        heightFactor: 1,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: ink.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(h / 2),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: h + 4),
                      child: Center(
                        child: Opacity(
                          opacity: _busy ? 1 : (1 - p * 1.5).clamp(0.0, 1.0),
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: ink, fontSize: h >= 60 ? 18 : 16, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(_inset),
                    child: Align(
                      alignment: Alignment(-1 + 2 * p, 0),
                      child: Container(
                        width: h - _inset * 2,
                        height: h - _inset * 2,
                        decoration: BoxDecoration(
                          color: knob,
                          shape: BoxShape.circle,
                          boxShadow: on ? [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 8, offset: const Offset(0, 3))] : null,
                        ),
                        child: Center(
                          child: _busy
                              ? SizedBox.square(dimension: h * 0.36, child: CircularProgressIndicator(strokeWidth: 2.6, color: knobInk))
                              : Icon(p >= 0.98 ? Icons.check_rounded : (widget.icon ?? Icons.keyboard_double_arrow_right_rounded), color: knobInk, size: h * 0.42),
                        ),
                      ),
                    ),
                  ),
                ]),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Círculo grande del color de la marca con una palomita que aparece con un rebote.
/// Para "¡Pedido enviado!", "Aprobado", etc.
class DmSuccessMark extends StatefulWidget {
  const DmSuccessMark({super.key, this.size = 120, this.color});
  final double size;

  /// Por defecto el color principal de la marca.
  final Color? color;

  @override
  State<DmSuccessMark> createState() => _DmSuccessMarkState();
}

class _DmSuccessMarkState extends State<DmSuccessMark> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 650))..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final color = widget.color ?? t.primary;
    final on = ThemeData.estimateBrightnessForColor(color) == Brightness.dark ? Colors.white : Colors.black;
    final s = widget.size;
    return Semantics(
      image: true,
      label: 'Listo',
      child: SizedBox.square(
        dimension: s,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final circle = Curves.elasticOut.transform((_c.value * 1.4).clamp(0.0, 1.0));
            final check = Curves.easeOutBack.transform(((_c.value - 0.35) / 0.65).clamp(0.0, 1.0));
            return Transform.scale(
              scale: 0.4 + 0.6 * circle,
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: s * 0.3, offset: Offset(0, s * 0.1))],
                ),
                child: Center(
                  child: Transform.scale(
                    scale: check,
                    child: Icon(Icons.check_rounded, size: s * 0.58, color: on),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
