import 'package:collection/collection.dart';
import 'package:devepmax_ui/devepmax_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/ui/feedback.dart';
import '../../menu/widgets/common.dart';
import '../data/billing_api.dart';
import '../data/billing_models.dart';
import '../printing/printer.dart';

/// Recibo de una cuenta: enviarlo por email o SMS, imprimir el ticket o mostrar el QR.
Future<void> showReceiptDialog(BuildContext context, BillView bill) =>
    showDialog<void>(context: context, builder: (_) => _ReceiptDialog(bill: bill));

class _ReceiptDialog extends ConsumerStatefulWidget {
  const _ReceiptDialog({required this.bill});
  final BillView bill;

  @override
  ConsumerState<_ReceiptDialog> createState() => _ReceiptDialogState();
}

class _ReceiptDialogState extends ConsumerState<_ReceiptDialog> {
  late final Future<Map<String, dynamic>> _receipt = ref.read(billingApiProvider).receipt(widget.bill.id);
  final _email = TextEditingController();
  late final _phone = TextEditingController(text: widget.bill.orders.map((o) => o.customerPhone).firstWhereOrNull((p) => p != null && p.isNotEmpty) ?? '');
  String? _busy;
  bool _showQr = false;

  @override
  void dispose() {
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _run(String what, Future<void> Function() action) async {
    setState(() => _busy = what);
    try {
      await action();
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _send({bool email = false, bool sms = false}) => _run(email ? 'email' : 'sms', () async {
        final sent = await ref.read(billingApiProvider).sendReceipt(
              widget.bill.id,
              email: email ? _email.text : null,
              phone: sms ? _phone.text : null,
            );
        if (mounted) showSuccess(context, sent.contains('email') ? 'Recibo enviado a ${_email.text.trim()}' : 'Recibo enviado por SMS');
      });

  Future<void> _print() => _run('print', () async {
        await ref.read(printerProvider.notifier).printReceipt(await _receipt);
        if (mounted) showSuccess(context, 'Ticket impreso');
      });

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final text = Theme.of(context).textTheme;
    final config = ref.watch(receiptConfigProvider).value ?? (email: false, sms: false);
    final printer = ref.watch(printerProvider).value;

    Widget section(String title, List<Widget> children) => Padding(
          padding: const EdgeInsets.only(top: 18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: text.titleMedium),
            const SizedBox(height: 8),
            ...children,
          ]),
        );

    Widget sendRow(TextEditingController c, String label, TextInputType type, bool enabled, VoidCallback onSend, String what) =>
        AdaptiveRow(children: [
          TextField(
            controller: c,
            enabled: enabled,
            keyboardType: type,
            decoration: InputDecoration(labelText: label),
          ),
          FilledButton.tonalIcon(
            onPressed: !enabled || _busy != null ? null : onSend,
            icon: _busy == what ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send_rounded),
            label: const Text('Enviar'),
          ),
        ]);

    return AlertDialog(
      title: Text('Recibo · ${widget.bill.label}'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Total ${formatMoney(widget.bill.total)}${widget.bill.refundedTotal > 0 ? ' · reembolsado ${formatMoney(widget.bill.refundedTotal)}' : ''}',
                style: TextStyle(color: t.muted)),
            section('Enviar al cliente', [
              sendRow(_email, 'Email', TextInputType.emailAddress, config.email, () => _send(email: true), 'email'),
              const SizedBox(height: 10),
              sendRow(_phone, 'Teléfono (SMS)', TextInputType.phone, config.sms, () => _send(sms: true), 'sms'),
              if (!config.email || !config.sms)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    !config.email && !config.sms
                        ? 'El envío por email y SMS se activa al configurar Resend y Twilio en el servidor.'
                        : !config.email
                            ? 'El envío por email se activa al configurar Resend en el servidor.'
                            : 'El envío por SMS se activa al configurar Twilio en el servidor.',
                    style: TextStyle(color: t.muted, fontSize: 13),
                  ),
                ),
            ]),
            section('Ticket impreso', [
              if (!canPrintHere)
                Text('Para imprimir tickets usa la app instalada en la caja (Android o Windows).', style: TextStyle(color: t.muted))
              else ...[
                Row(children: [
                  Icon(Icons.print_rounded, color: printer == null ? t.faint : t.accentText),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(printer == null ? 'Sin impresora en este aparato' : '${printer.host} · ${printer.paper}',
                        style: TextStyle(color: printer == null ? t.muted : t.text)),
                  ),
                  TextButton(onPressed: () => showPrinterSetup(context), child: Text(printer == null ? 'Configurar' : 'Cambiar')),
                ]),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: printer == null || _busy != null ? null : _print,
                  icon: _busy == 'print' ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.print_rounded),
                  label: const Text('Imprimir ticket'),
                ),
              ],
            ]),
            section('Mostrar en pantalla', [
              if (!_showQr)
                OutlinedButton.icon(onPressed: () => setState(() => _showQr = true), icon: const Icon(Icons.qr_code_2_rounded), label: const Text('Mostrar QR del recibo'))
              else
                FutureBuilder<Map<String, dynamic>>(
                  future: _receipt,
                  builder: (context, snap) {
                    final url = snap.data?['url'] as String?;
                    if (snap.hasError) return Text('No se pudo cargar el recibo', style: TextStyle(color: t.danger));
                    if (url == null) return const Center(child: CircularProgressIndicator());
                    return Column(children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                        child: QrImageView(data: url, size: 200, backgroundColor: Colors.white, semanticsLabel: 'QR del recibo'),
                      ),
                      const SizedBox(height: 8),
                      Text('El cliente lo escanea y se lleva el recibo en su celular.', style: TextStyle(color: t.muted, fontSize: 13), textAlign: TextAlign.center),
                      TextButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: url));
                          if (context.mounted) showSuccess(context, 'Enlace copiado');
                        },
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        label: const Text('Copiar enlace'),
                      ),
                    ]);
                  },
                ),
            ]),
          ]),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))],
    );
  }
}

/// Dirección de la impresora térmica de red de este aparato, tamaño del papel y prueba.
Future<void> showPrinterSetup(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _PrinterSetup());

class _PrinterSetup extends ConsumerStatefulWidget {
  const _PrinterSetup();

  @override
  ConsumerState<_PrinterSetup> createState() => _PrinterSetupState();
}

class _PrinterSetupState extends ConsumerState<_PrinterSetup> {
  late final PrinterConfig? _current = ref.read(printerProvider).value;
  late final _host = TextEditingController(text: _current?.host ?? '');
  late final _port = TextEditingController(text: '${_current?.port ?? 9100}');
  late int _columns = _current?.columns ?? 48;
  bool _busy = false;

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  PrinterConfig? get _config {
    final host = _host.text.trim();
    final port = int.tryParse(_port.text.trim()) ?? 0;
    if (!RegExp(r'^[A-Za-z0-9.\-]{3,}$').hasMatch(host) || port < 1 || port > 65535) return null;
    return PrinterConfig(host: host, port: port, columns: _columns);
  }

  Future<void> _test() async {
    final config = _config;
    if (config == null) {
      showError(context, 'Revisa la dirección y el puerto');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(printerProvider.notifier).test(config);
      if (mounted) showSuccess(context, 'Listo: revisa el ticket de prueba');
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    return AlertDialog(
      title: const Text('Impresora de tickets'),
      content: SizedBox(
        width: 440,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Impresora térmica de red (Wi-Fi o cable). La dirección sale en el ticket de configuración de la impresora.',
              style: TextStyle(color: t.muted)),
          const SizedBox(height: 14),
          AdaptiveRow(children: [
            TextField(
              controller: _host,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'Dirección IP', hintText: '192.168.1.50'),
              onChanged: (_) => setState(() {}),
            ),
            TextField(
              controller: _port,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Puerto'),
              onChanged: (_) => setState(() {}),
            ),
          ]),
          const SizedBox(height: 14),
          LabeledControl(
            label: 'Papel',
            child: FitSegmented<int>(SegmentedButton<int>(
              segments: const [ButtonSegment(value: 48, label: Text('80 mm')), ButtonSegment(value: 32, label: Text('58 mm'))],
              selected: {_columns},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _columns = s.first),
            )),
          ),
        ]),
      ),
      actions: [
        if (_current != null)
          TextButton(
            onPressed: () async {
              await ref.read(printerProvider.notifier).save(null);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Quitar'),
          ),
        OutlinedButton(onPressed: _busy || _config == null ? null : _test, child: const Text('Imprimir prueba')),
        FilledButton(
          onPressed: _config == null
              ? null
              : () async {
                  await ref.read(printerProvider.notifier).save(_config);
                  if (context.mounted) Navigator.pop(context);
                },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
