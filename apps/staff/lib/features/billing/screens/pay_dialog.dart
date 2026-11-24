import 'dart:async';

import 'package:collection/collection.dart';
import 'package:devepmax_ui/devepmax_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/feedback.dart';
import '../data/billing_api.dart';
import '../data/billing_models.dart';
import '../data/tap_to_pay.dart';
import '../../menu/widgets/common.dart';

/// Opción "este teléfono" entre los lectores.
const _tapId = 'tap-to-pay';

/// Cobrar: cuánto (todo, una parte o partes iguales), propina y forma de pago.
/// Devuelve la cuenta actualizada y el cambio a entregar.
Future<({BillView bill, double change})?> showPayDialog(BuildContext context, BillView bill) =>
    showDialog<({BillView bill, double change})>(
        context: context, barrierDismissible: false, builder: (_) => _PayDialog(bill: bill));

class _PayDialog extends ConsumerStatefulWidget {
  const _PayDialog({required this.bill});
  final BillView bill;

  @override
  ConsumerState<_PayDialog> createState() => _PayDialogState();
}

class _PayDialogState extends ConsumerState<_PayDialog> {
  String _requestId = newRequestId();
  final _amount = TextEditingController();
  final _tip = TextEditingController();
  final _tendered = TextEditingController();
  final _reference = TextEditingController();
  int _parts = 1; // 0 = otro monto
  int? _tipPercent; // null = sin propina, -1 = otra
  String _method = 'CASH';
  bool _busy = false;

  // Lector integrado
  String? _readerId;
  bool _tipOnReader = true;
  bool _manualCard = false; // cobro hecho en otro aparato: solo se anota
  TerminalCharge? _charge; // cobro en curso en el lector
  Timer? _poll;
  CardReader? _activeReader;

  double get _due => widget.bill.due;

  double get _amountValue {
    if (_parts == 0) return double.tryParse(_amount.text.replaceAll(',', '.')) ?? 0;
    if (_parts == 1) return _due;
    // Partes iguales: se redondea hacia arriba al centavo (la última parte paga lo que falte).
    return ((_due / _parts) * 100).ceilToDouble() / 100;
  }

  double get _tipValue {
    if (_method == 'CARD_TERMINAL' &&
        !_manualCard &&
        _tipOnReader &&
        _readerId != _tapId &&
        (ref.read(cardReadersProvider).value ?? const []).any((r) => r.online)) {
      return 0; // la propina la elige el cliente en el lector
    }
    final p = _tipPercent;
    if (p == null) return 0;
    if (p == -1) return double.tryParse(_tip.text.replaceAll(',', '.')) ?? 0;
    return ((_amountValue * p / 100) * 100).roundToDouble() / 100;
  }

  double get _charged => _amountValue + _tipValue;
  double get _tenderedValue => double.tryParse(_tendered.text.replaceAll(',', '.')) ?? _charged;
  double get _change => (_tenderedValue - _charged).clamp(0, double.infinity);

  String? get _problem {
    final a = _amountValue;
    if (a <= 0) return 'Escribe el monto';
    if (a > _due + 0.001) return 'Es más de lo que se debe (${formatMoney(_due)})';
    if (_method == 'CASH' && _tenderedValue + 0.001 < _charged) return 'El efectivo recibido no alcanza';
    return null;
  }

  @override
  void dispose() {
    _poll?.cancel();
    _amount.dispose();
    _tip.dispose();
    _tendered.dispose();
    _reference.dispose();
    super.dispose();
  }

  bool _useReader(List<CardReader> readers) =>
      _method == 'CARD_TERMINAL' && !_manualCard && readers.any((r) => r.online);

  Future<void> _sendToReader(CardReader reader) async {
    if (_problem != null || _busy) return;
    setState(() => _busy = true);
    try {
      final amount = double.parse(_amountValue.clamp(0, _due).toStringAsFixed(2));
      final charge = await ref.read(billingApiProvider).terminalCharge(
            widget.bill.id,
            requestId: _requestId,
            readerId: reader.id,
            amount: amount,
            tipOnReader: _tipOnReader,
          );
      if (!mounted) return;
      setState(() {
        _charge = charge;
        _activeReader = reader;
      });
      _poll?.cancel();
      _poll = Timer.periodic(const Duration(milliseconds: 1200), (_) => _check());
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _check() async {
    final current = _charge;
    if (current == null || current.status != 'waiting') return;
    try {
      final next = await ref.read(billingApiProvider).terminalStatus(current.paymentId);
      if (!mounted) return;
      setState(() => _charge = next);
      if (next.status != 'waiting') _poll?.cancel();
      if (next.status == 'succeeded') {
        ref.invalidate(openBillsProvider);
        ref.invalidate(cashShiftProvider);
      }
    } catch (_) {
      // Se reintenta en el siguiente ciclo.
    }
  }

  /// Tap to Pay: cobra con el NFC de este aparato (Stripe muestra su pantalla para acercar la tarjeta).
  Future<void> _chargeHere() async {
    if (_problem != null || _busy) return;
    setState(() => _busy = true);
    try {
      final amount = double.parse(_amountValue.clamp(0, _due).toStringAsFixed(2));
      final result = await ref.read(tapToPayProvider.notifier).charge(widget.bill, amount: amount, tip: _tipValue, requestId: _requestId);
      if (!mounted) return;
      setState(() {
        _charge = result;
        _activeReader = null;
      });
      if (result.status == 'succeeded') {
        ref.invalidate(openBillsProvider);
        ref.invalidate(cashShiftProvider);
      }
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelOnReader() async {
    final current = _charge;
    if (current == null) return;
    setState(() => _busy = true);
    try {
      final next = await ref.read(billingApiProvider).terminalCancel(current.paymentId);
      if (mounted) setState(() => _charge = next);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _retry() {
    _poll?.cancel();
    setState(() {
      _charge = null;
      _requestId = newRequestId();
    });
  }

  Future<void> _confirm() async {
    if (_problem != null || _busy) return;
    setState(() => _busy = true);
    try {
      final amount = double.parse(_amountValue.clamp(0, _due).toStringAsFixed(2));
      final updated = await ref.read(billingApiProvider).pay(
            widget.bill.id,
            requestId: _requestId,
            method: _method,
            amount: amount,
            tip: _tipValue,
            cashTendered: _method == 'CASH' ? _tenderedValue : null,
            reference: _method == 'CASH' ? null : _reference.text,
          );
      ref.invalidate(openBillsProvider);
      ref.invalidate(cashShiftProvider);
      if (!mounted) return;
      Navigator.pop(context, (bill: updated, change: _method == 'CASH' ? _change : 0.0));
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final text = Theme.of(context).textTheme;
    final problem = _problem;
    final charge = _charge;
    if (charge != null) return this._readerView(charge); // ignore: unnecessary_this

    final compact = MediaQuery.sizeOf(context).width < 600;
    final readers = ref.watch(cardReadersProvider).value ?? const <CardReader>[];
    final online = readers.where((r) => r.online).toList();
    final tapAvailable = tapToPaySupportedPlatform && (ref.watch(terminalConfigProvider).value?.enabled ?? false);
    final tap = ref.watch(tapToPayProvider);
    final useTap = _method == 'CARD_TERMINAL' && !_manualCard && tapAvailable && (_readerId == _tapId || online.isEmpty);
    final useReader = !useTap && _useReader(readers);
    final reader = online.firstWhere((r) => r.id == _readerId, orElse: () => online.isEmpty ? _noReader : online.first);

    Widget section(String title, Widget child) => Padding(
          padding: const EdgeInsets.only(top: 18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: text.titleSmall?.copyWith(color: t.muted)),
            const SizedBox(height: 8),
            child,
          ]),
        );

    final quickCash = <double>{
      _charged,
      (_charged / 5).ceil() * 5.0,
      (_charged / 10).ceil() * 10.0,
      (_charged / 20).ceil() * 20.0,
      50,
      100,
    }.where((v) => v + 0.001 >= _charged).toList()
      ..sort();

    return AlertDialog(
      title: Wrap(spacing: 12, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text('Cobrar · ${widget.bill.label}'),
        Text('Debe ${formatMoney(_due)}', style: text.titleMedium?.copyWith(color: t.accentText)),
      ]),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            section(
              '¿Cuánto paga?',
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final (parts, label) in const [(1, 'Todo'), (2, '½'), (3, '⅓'), (4, '¼'), (0, 'Otro monto')])
                    ChoiceChip(
                      label: Text(label),
                      selected: _parts == parts,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _parts = parts),
                    ),
                ]),
                if (_parts == 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: TextField(
                      controller: _amount,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                      decoration: const InputDecoration(prefixText: '\$ ', labelText: 'Monto', border: OutlineInputBorder()),
                      onChanged: (_) => setState(() {}),
                    ),
                  )
                else if (_parts > 1)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('Cada parte: ${formatMoney(_amountValue)}', style: TextStyle(color: t.muted)),
                  ),
              ]),
            ),
            if (useReader && _tipOnReader && !useTap)
              section(
                'Propina',
                Row(children: [
                  Icon(Icons.touch_app_rounded, color: t.accentText),
                  const SizedBox(width: 8),
                  Expanded(child: Text('El cliente la elige en la pantalla del lector (15 %, 18 %, 20 % u otra).', style: TextStyle(color: t.muted))),
                ]),
              )
            else
            section(
              'Propina',
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final (p, label) in const [(null, 'Sin propina'), (15, '15%'), (18, '18%'), (20, '20%'), (-1, 'Otra')])
                    ChoiceChip(
                      label: Text(p != null && p > 0 ? '$label · ${formatMoney(((_amountValue * p / 100) * 100).roundToDouble() / 100)}' : label),
                      selected: _tipPercent == p,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _tipPercent = p),
                    ),
                ]),
                if (_tipPercent == -1)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: TextField(
                      controller: _tip,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                      decoration: const InputDecoration(prefixText: '\$ ', labelText: 'Propina', border: OutlineInputBorder()),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
              ]),
            ),
            section(
              'Forma de pago',
              FitSegmented(SegmentedButton<String>(
                showSelectedIcon: false,
                // En el teléfono, solo el texto para que quepan las tres opciones.
                segments: [
                  ButtonSegment(value: 'CASH', label: const Text('Efectivo'), icon: compact ? null : const Icon(Icons.payments_rounded)),
                  ButtonSegment(value: 'CARD_TERMINAL', label: const Text('Tarjeta'), icon: compact ? null : const Icon(Icons.credit_card_rounded)),
                  ButtonSegment(value: 'OTHER', label: const Text('Otro'), icon: compact ? null : const Icon(Icons.more_horiz_rounded)),
                ],
                selected: {_method},
                onSelectionChanged: (v) => setState(() => _method = v.first),
              )),
            ),
            if (_method == 'CASH')
              section(
                '¿Con cuánto paga?',
                Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final v in quickCash)
                      ActionChip(
                        label: Text(v == _charged ? 'Exacto' : formatMoney(v)),
                        onPressed: () => setState(() => _tendered.text = v.toStringAsFixed(2)),
                      ),
                  ]),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _tendered,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                    decoration: InputDecoration(
                      prefixText: '\$ ',
                      labelText: 'Efectivo recibido',
                      hintText: _charged.toStringAsFixed(2),
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: t.successSoft, borderRadius: BorderRadius.circular(14)),
                    child: Row(children: [
                      Text('Cambio', style: text.titleMedium?.copyWith(color: t.success)),
                      const Spacer(),
                      Text(formatMoney(_change), style: text.headlineSmall?.copyWith(color: t.success, fontWeight: FontWeight.w800)),
                    ]),
                  ),
                ]),
              )
            else if (useReader || useTap)
              section(
                'Lector',
                Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final r in online)
                      ChoiceChip(
                        avatar: Icon(Icons.contactless_rounded, size: 18, color: t.accentText),
                        label: Text(r.simulated ? '${r.label} · prueba' : r.label),
                        selected: !useTap && r.id == reader.id,
                        showCheckmark: false,
                        onSelected: (_) => setState(() => _readerId = r.id),
                      ),
                    if (tapAvailable)
                      ChoiceChip(
                        avatar: Icon(Icons.phone_android_rounded, size: 18, color: t.accentText),
                        label: const Text('Este teléfono · Tap to Pay'),
                        selected: useTap,
                        showCheckmark: false,
                        onSelected: (_) => setState(() => _readerId = _tapId),
                      ),
                  ]),
                  if (useTap)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        tap.status == TapToPayStatus.error
                            ? tap.message ?? 'Tap to Pay no está disponible'
                            : (tap.status == TapToPayStatus.connecting
                                ? 'Preparando Tap to Pay…'
                                : 'El cliente acerca su tarjeta, celular o reloj a este teléfono.'),
                        style: TextStyle(color: tap.status == TapToPayStatus.error ? t.danger : t.muted, fontWeight: FontWeight.w600),
                      ),
                    ),
                  if (!useTap)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _tipOnReader,
                    onChanged: (v) => setState(() => _tipOnReader = v),
                    title: const Text('Que el cliente elija la propina en el lector'),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => setState(() => _manualCard = true),
                      child: const Text('Ya cobré en otro aparato: solo anotar'),
                    ),
                  ),
                ]),
              )
            else
              section(
                _method == 'CARD_TERMINAL'
                    ? (readers.isEmpty ? 'Sin lector conectado: cobra aparte y anota (opcional)' : 'Cobra en el lector y anota (opcional)')
                    : 'Cómo pagó (opcional)',
                TextField(
                  controller: _reference,
                  maxLength: 60,
                  decoration: InputDecoration(
                    hintText: _method == 'CARD_TERMINAL' ? 'Últimos 4 dígitos o autorización' : 'Zelle, transferencia, cortesía…',
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: t.surface2, borderRadius: BorderRadius.circular(14)),
              child: Column(children: [
                _Line('A la cuenta', _amountValue),
                if (_tipValue > 0) _Line('Propina', _tipValue),
                _Line('Total a cobrar', _charged, bold: true),
                if (_amountValue > 0 && _amountValue < _due - 0.001)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('Quedan ${formatMoney(_due - _amountValue)} por cobrar', style: TextStyle(color: t.muted)),
                  ),
              ]),
            ),
            if (problem != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(problem, style: TextStyle(color: t.danger, fontWeight: FontWeight.w700)),
              ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: Size(compact ? 0 : 200, 52)),
          onPressed: problem == null && !_busy
              ? (useTap ? _chargeHere : (useReader ? () => _sendToReader(reader) : _confirm))
              : null,
          icon: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(useTap || useReader ? Icons.contactless_rounded : Icons.check_rounded),
          label: Text(useTap
              ? 'Cobrar con este teléfono ${formatMoney(_charged)}'
              : (useReader ? 'Enviar al lector ${formatMoney(_charged)}' : 'Cobrar ${formatMoney(_charged)}')),
        ),
      ],
    );
  }
}

const _noReader = CardReader(id: '', label: '', deviceType: '', simulated: false, busy: false);

extension on _PayDialogState {
  /// Pantalla mientras el cliente paga en el lector.
  Widget _readerView(TerminalCharge charge) {
    final t = BrandTokens.of(context);
    final text = Theme.of(context).textTheme;
    final reader = _activeReader;
    final testMode = ref.watch(terminalConfigProvider).value?.testMode ?? false;
    final tipBase = _amountValue;

    final Widget body;
    final List<Widget> actions;
    switch (charge.status) {
      case 'succeeded':
        final bill = charge.bill;
        final card = bill?.payments.where((p) => p.status == 'SUCCEEDED').lastOrNull?.reference;
        body = Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.check_circle_rounded, size: 96, color: t.success),
          const SizedBox(height: 12),
          Text('Aprobado', style: text.headlineMedium),
          if (card != null) Text(card, style: TextStyle(color: t.muted, fontSize: 16)),
          if (charge.tip > 0) Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Propina ${formatMoney(charge.tip)}', style: text.titleMedium?.copyWith(color: t.success)),
          ),
          if (bill != null && bill.due > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Quedan ${formatMoney(bill.due)} por cobrar', style: TextStyle(color: t.muted)),
            ),
        ]);
        actions = [
          FilledButton(
            onPressed: () => Navigator.pop(context, bill == null ? null : (bill: bill, change: 0.0)),
            child: const Text('Listo'),
          ),
        ];
      case 'failed':
      case 'cancelled':
        body = Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(charge.status == 'failed' ? Icons.credit_card_off_rounded : Icons.cancel_rounded, size: 80, color: t.danger),
          const SizedBox(height: 12),
          Text(charge.status == 'failed' ? 'No se aprobó' : 'Cobro cancelado', style: text.headlineSmall),
          const SizedBox(height: 6),
          Text(charge.message, textAlign: TextAlign.center, style: TextStyle(color: t.muted)),
        ]);
        actions = [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
          FilledButton(onPressed: _retry, child: const Text('Intentar de nuevo')),
        ];
      default:
        body = Column(mainAxisSize: MainAxisSize.min, children: [
          const _Pulse(icon: Icons.contactless_rounded),
          const SizedBox(height: 16),
          Text(formatMoney(_charged), style: text.displaySmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('Acerca, inserta o desliza la tarjeta o el celular en «${reader?.label ?? 'el lector'}»',
              textAlign: TextAlign.center, style: text.titleMedium),
          if (_tipOnReader)
            Text('El cliente elige la propina en el lector', style: TextStyle(color: t.muted)),
          if (testMode && (reader?.simulated ?? false)) ...[
            const SizedBox(height: 20),
            Text('Modo prueba: simula al cliente', style: TextStyle(color: t.muted)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
              ActionChip(
                avatar: const Icon(Icons.contactless_rounded, size: 18),
                label: const Text('Tarjeta sin propina'),
                onPressed: () => ref.read(billingApiProvider).terminalSimulate(charge.paymentId),
              ),
              if (_tipOnReader)
                ActionChip(
                  avatar: const Icon(Icons.volunteer_activism_rounded, size: 18),
                  label: Text('Con propina 18% · ${formatMoney(((tipBase * 0.18) * 100).roundToDouble() / 100)}'),
                  onPressed: () => ref
                      .read(billingApiProvider)
                      .terminalSimulate(charge.paymentId, tip: ((tipBase * 0.18) * 100).roundToDouble() / 100),
                ),
              ActionChip(
                avatar: const Icon(Icons.credit_card_off_rounded, size: 18),
                label: const Text('Tarjeta rechazada'),
                onPressed: () => ref.read(billingApiProvider).terminalSimulate(charge.paymentId, declined: true),
              ),
            ]),
          ],
        ]);
        actions = [
          TextButton(onPressed: _busy ? null : _cancelOnReader, child: const Text('Cancelar cobro')),
        ];
    }

    return AlertDialog(
      title: Text('Cobrar · ${widget.bill.label}'),
      content: SizedBox(width: 480, child: Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: body)),
      actions: actions,
    );
  }
}

/// Ícono que late suavemente mientras se espera la tarjeta.
class _Pulse extends StatefulWidget {
  const _Pulse({required this.icon});
  final IconData icon;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    return ScaleTransition(
      scale: Tween(begin: 0.9, end: 1.08).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
      child: Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(color: t.primarySoft, shape: BoxShape.circle),
        child: Icon(widget.icon, size: 64, color: t.primary),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value, {this.bold = false});
  final String label;
  final double value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final style = bold ? text.titleLarge : text.bodyLarge;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(children: [Expanded(child: Text(label, style: style)), Text(formatMoney(value), style: style)]),
    );
  }
}

/// "Entrega de cambio: $X" en grande.
Future<void> showChangeDialog(BuildContext context, double change) {
  final t = BrandTokens.of(context);
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.payments_rounded, size: 56, color: t.success),
        const SizedBox(height: 12),
        const Text('Entrega de cambio'),
        const SizedBox(height: 6),
        Text(formatMoney(change), style: Theme.of(context).textTheme.displayMedium?.copyWith(fontWeight: FontWeight.w800)),
      ]),
      actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Listo'))],
    ),
  );
}
