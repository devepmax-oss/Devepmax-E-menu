import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/ui/feedback.dart';
import 'escpos.dart';
import 'printer_stub.dart' if (dart.library.io) 'printer_io.dart' as transport;

/// Se puede imprimir desde este aparato (app instalada, no el navegador).
const bool canPrintHere = transport.canPrintHere;

/// Impresora de tickets de este aparato (cada caja puede tener la suya).
class PrinterConfig {
  const PrinterConfig({required this.host, this.port = 9100, this.columns = 48});
  final String host;
  final int port;

  /// 48 = papel de 80 mm, 32 = papel de 58 mm.
  final int columns;

  String get paper => columns <= 32 ? '58 mm' : '80 mm';

  Map<String, dynamic> toJson() => {'host': host, 'port': port, 'columns': columns};
  factory PrinterConfig.fromJson(Map<String, dynamic> j) =>
      PrinterConfig(host: j['host'] as String, port: (j['port'] as num?)?.toInt() ?? 9100, columns: (j['columns'] as num?)?.toInt() ?? 48);
}

final printerProvider = AsyncNotifierProvider<PrinterController, PrinterConfig?>(PrinterController.new);

class PrinterController extends AsyncNotifier<PrinterConfig?> {
  static const _key = 'devepmax.printer';
  final _storage = const FlutterSecureStorage();

  @override
  Future<PrinterConfig?> build() async {
    try {
      final raw = await _storage.read(key: _key);
      return raw == null ? null : PrinterConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(PrinterConfig? config) async {
    if (config == null) {
      await _storage.delete(key: _key);
    } else {
      await _storage.write(key: _key, value: jsonEncode(config.toJson()));
    }
    state = AsyncData(config);
  }

  /// Ticket de prueba para confirmar que la impresora responde.
  Future<void> test(PrinterConfig config) async {
    final p = EscPos(config.columns)
      ..center()
      ..big(true)
      ..line('Prueba')
      ..big(false)
      ..line('La impresora funciona')
      ..line('Ñ á é í ó ú ¿? ¡!')
      ..line(DateFormat('M/d/yyyy h:mm a').format(DateTime.now()))
      ..cut();
    await _send(config, p.bytes);
  }

  Future<void> printReceipt(Map<String, dynamic> receipt) async {
    final config = state.value;
    if (config == null) throw ApiException('Configura la impresora de este aparato');
    await _send(config, receiptBytes(receipt, config.columns));
  }

  /// Cierre del día (reporte Z) en papel.
  Future<void> printReport(Map<String, dynamic> report) async {
    final config = state.value;
    if (config == null) throw ApiException('Configura la impresora de este aparato');
    await _send(config, reportBytes(report, config.columns));
  }

  /// La cuenta antes de pagar (no es comprobante de pago).
  Future<void> printCheck(Map<String, dynamic> check) async {
    final config = state.value;
    if (config == null) throw ApiException('Configura la impresora de este aparato');
    await _send(config, receiptBytes(check, config.columns, check: true));
  }

  Future<void> _send(PrinterConfig config, List<int> bytes) async {
    try {
      await transport.sendToPrinter(config.host, config.port, bytes);
    } on UnsupportedError catch (e) {
      throw ApiException(e.message ?? 'No se puede imprimir desde aquí');
    } catch (_) {
      throw ApiException('No responde la impresora en ${config.host}:${config.port}. Revisa que esté encendida y en la misma red.');
    }
  }
}

/// El ticket: datos del restaurante, lo pedido, totales, pagos y un QR al recibo digital.
/// Con [check], es la cuenta antes de pagar: propinas sugeridas y QR para pagar con el celular.
List<int> receiptBytes(Map<String, dynamic> r, int columns, {bool check = false}) {
  final restaurant = r['restaurant'] as Map<String, dynamic>? ?? const {};
  String m(Object? v) => formatMoney(parseMoney(v));
  final p = EscPos(columns)
    ..center()
    ..bold(true)
    ..big(true)
    ..wrap('${restaurant['name'] ?? ''}')
    ..big(false)
    ..bold(false);
  for (final line in restaurant['address'] as List? ?? const []) {
    p.wrap('$line');
  }
  if (restaurant['phone'] != null) p.line('${restaurant['phone']}');
  if (check) {
    p
      ..feed()
      ..bold(true)
      ..big(true)
      ..line('CUENTA')
      ..big(false)
      ..bold(false);
  }
  p
    ..feed()
    ..left()
    ..bold(true)
    ..wrap('${r['label'] ?? ''}')
    ..bold(false);
  final date = DateTime.tryParse('${r['date']}')?.toLocal();
  if (date != null) p.line(DateFormat('M/d/yyyy h:mm a').format(date));
  final numbers = [for (final n in r['orderNumbers'] as List? ?? const []) '#$n'];
  if (numbers.isNotEmpty) p.line('Orden ${numbers.join(', ')}');
  p.divider();

  for (final item in r['items'] as List? ?? const []) {
    final i = item as Map<String, dynamic>;
    p.row('${i['quantity']}x ${i['name']}', m(i['lineTotal']));
    final mods = [for (final x in i['modifiers'] as List? ?? const []) '$x'];
    if (mods.isNotEmpty) p.wrap(mods.join(', '), indent: 3);
  }
  p.divider();
  p.row('Subtotal', m(r['subtotal']));
  for (final d in r['discounts'] as List? ?? const []) {
    final x = d as Map<String, dynamic>;
    p.row('Descuento ${x['item'] ?? x['reason'] ?? ''}', '-${m(x['amount'])}');
  }
  if (parseMoney(r['discountTotal']) > 0 && (r['discounts'] as List? ?? const []).isEmpty) p.row('Descuentos', '-${m(r['discountTotal'])}');
  if (parseMoney(r['deliveryFee']) > 0) p.row('Envío', m(r['deliveryFee']));
  p.row('Impuestos', m(r['taxTotal']));
  if (parseMoney(r['tipTotal']) > 0) p.row('Propina', m(r['tipTotal']));
  p
    ..bold(true)
    ..row('TOTAL', m(r['total']))
    ..bold(false);

  if (check) {
    final paidSoFar = parseMoney(r['amountPaid']);
    if (paidSoFar > 0) {
      p.row('Ya pagado', '-${m(paidSoFar)}');
      p
        ..bold(true)
        ..row('POR PAGAR', m(r['due']))
        ..bold(false);
    }
    final tips = r['tips'] as List? ?? const [];
    if (tips.isNotEmpty) {
      p
        ..divider()
        ..line('Propina sugerida:');
      for (final tip in tips) {
        final x = tip as Map<String, dynamic>;
        p.row('  ${x['percent']}%', m(x['amount']));
      }
    }
    final payUrl = r['payUrl'] as String?;
    p
      ..feed()
      ..center();
    if (payUrl != null) {
      p
        ..bold(true)
        ..line('Paga con tu celular')
        ..bold(false)
        ..line('Tarjeta, Apple Pay o Google Pay')
        ..qr(payUrl, size: columns <= 32 ? 5 : 6);
    }
    p
      ..wrap('Este documento no es un comprobante de pago.')
      ..cut();
    return p.bytes;
  }

  final payments = r['payments'] as List? ?? const [];
  if (payments.isNotEmpty) p.divider();
  for (final pay in payments) {
    final x = pay as Map<String, dynamic>;
    p.row('${x['method']}${x['reference'] != null ? ' ${x['reference']}' : ''}', m(x['amount']));
    if (parseMoney(x['changeGiven']) > 0) {
      p.row('  Recibido', m(x['cashTendered']));
      p.row('  Cambio', m(x['changeGiven']));
    }
  }
  if (parseMoney(r['refundedTotal']) > 0) p.row('Reembolsado', '-${m(r['refundedTotal'])}');
  if (parseMoney(r['due']) > 0) {
    p
      ..bold(true)
      ..row('POR PAGAR', m(r['due']))
      ..bold(false);
  }

  p
    ..feed()
    ..center();
  final footer = restaurant['footer'] as String?;
  p.wrap(footer != null && footer.trim().isNotEmpty ? footer : '¡Gracias por tu visita!');
  final url = r['url'] as String?;
  if (url != null) {
    p
      ..feed()
      ..line('Tu recibo digital:')
      ..qr(url, size: columns <= 32 ? 5 : 6);
  }
  p.cut();
  return p.bytes;
}

const _methodLabels = {
  'CASH': 'Efectivo',
  'CARD_TERMINAL': 'Tarjeta',
  'CARD_ONLINE': 'Tarjeta en línea',
  'CARD_QR': 'QR en la mesa',
  'OTHER': 'Otro',
};

/// Cierre del día para la impresora de tickets: totales, formas de pago, personas y caja.
List<int> reportBytes(Map<String, dynamic> r, int columns) {
  final s = r['summary'] as Map<String, dynamic>? ?? const {};
  String m(Object? v) => formatMoney(parseMoney(v));
  List<Map<String, dynamic>> list(String key) => (r[key] as List? ?? const []).cast<Map<String, dynamic>>();
  final p = EscPos(columns)
    ..center()
    ..bold(true)
    ..big(true)
    ..line('CIERRE DEL DIA')
    ..big(false)
    ..wrap('${r['restaurant'] ?? ''}')
    ..bold(false)
    ..line('Día ${r['date']}')
    ..line('Impreso ${DateFormat('M/d/yyyy h:mm a').format(DateTime.now())}')
    ..left()
    ..divider()
    ..row('Órdenes', '${s['orders']}')
    ..row('Canceladas', '${s['cancelledOrders']}')
    ..row('Clientes en mesa', '${s['guests']}')
    ..row('Ticket promedio', m(s['averageCheck']))
    ..divider()
    ..row('Ventas brutas', m(s['grossSales']))
    ..row('Descuentos', '-${m(s['discounts'])}')
    ..bold(true)
    ..row('VENTAS NETAS', m(s['netSales']))
    ..bold(false)
    ..row('Impuestos', m(s['tax']))
    ..row('Propinas', m(s['tips']));
  if (parseMoney(s['deliveryFees']) > 0) p.row('Envíos', m(s['deliveryFees']));
  p
    ..row('Total cuentas', m(s['total']))
    ..divider()
    ..bold(true)
    ..line('FORMAS DE PAGO')
    ..bold(false);
  for (final x in list('payments')) {
    p.row('${_methodLabels[x['method']] ?? x['method']} (${x['count']})', m(x['amount']));
    if (parseMoney(x['tips']) > 0) p.row('  propinas', m(x['tips']));
    if (parseMoney(x['refunded']) > 0) p.row('  reembolsado', '-${m(x['refunded'])}');
  }
  p
    ..row('Total cobrado', m(s['collected']))
    ..row('Reembolsos', '-${m(s['refunded'])}')
    ..bold(true)
    ..row('NETO COBRADO', m(s['netCollected']))
    ..bold(false);
  if (parseMoney(s['pending']) > 0) p.row('Por cobrar (${s['openBills']})', m(s['pending']));

  final servers = list('servers');
  if (servers.isNotEmpty) {
    p
      ..divider()
      ..bold(true)
      ..line('QUIÉN ATENDIÓ')
      ..bold(false);
    for (final x in servers) {
      p.row('${x['name']} (${x['bills']})', m(x['net']));
      if (parseMoney(x['tips']) > 0) p.row('  propinas', m(x['tips']));
    }
  }
  final products = list('products');
  if (products.isNotEmpty) {
    p
      ..divider()
      ..bold(true)
      ..line('MÁS VENDIDOS')
      ..bold(false);
    for (final x in products.take(10)) {
      p.row('${x['quantity']}x ${x['name']}', m(x['net']));
    }
  }
  final discounts = list('discounts');
  final refunds = list('refunds');
  final cancellations = list('cancellations');
  if (discounts.isNotEmpty || refunds.isNotEmpty || cancellations.isNotEmpty) {
    p
      ..divider()
      ..bold(true)
      ..line('AJUSTES')
      ..bold(false);
    for (final x in discounts) {
      p.row('Desc. ${x['bill']}', '-${m(x['amount'])}');
      p.wrap('${x['reason']} · ${x['appliedBy']}${x['authorizedBy'] != null ? ' / ${x['authorizedBy']}' : ''}', indent: 2);
    }
    for (final x in refunds) {
      p.row('Reemb. ${x['bill']}', '-${m(x['amount'])}');
      p.wrap('${x['reason']} · ${x['employee']}', indent: 2);
    }
    for (final x in cancellations) {
      p.row('Cancel. #${x['number']}', m(x['amount']));
      if (x['reason'] != null) p.wrap('${x['reason']}', indent: 2);
    }
  }
  for (final sh in list('shifts')) {
    p
      ..divider()
      ..bold(true)
      ..line('CAJA · ${sh['openedBy'] ?? ''}')
      ..bold(false)
      ..row('Fondo inicial', m(sh['openingCash']))
      ..row('Efectivo esperado', m(sh['expectedCash']));
    if (sh['countedCash'] != null) p.row('Contado', m(sh['countedCash']));
    if (sh['difference'] != null) p.row('Diferencia', m(sh['difference']));
  }
  p
    ..feed()
    ..center()
    ..line('Firma: ____________________')
    ..cut();
  return p.bytes;
}
