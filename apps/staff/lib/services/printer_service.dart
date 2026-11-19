import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:esc_pos_printer_plus/esc_pos_printer_plus.dart';

import '../screens/orders_dashboard_screen.dart';

class PrinterService {
  PrinterService._();

  static final PrinterService instance = PrinterService._();

  static const _keyPrinterIp = 'printer_ip';
  static const _keyPrinterPort = 'printer_port';
  static const _keyAutoPrint = 'printer_auto_print';

  String printerIp = '192.168.1.100';
  int port = 9100;
  bool autoPrintNewOrders = false;

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    final prefs = await SharedPreferences.getInstance();

    printerIp = prefs.getString(_keyPrinterIp) ?? printerIp;
    port = prefs.getInt(_keyPrinterPort) ?? port;
    autoPrintNewOrders = prefs.getBool(_keyAutoPrint) ?? autoPrintNewOrders;

    _initialized = true;

    debugPrint(
      '🖨️ Printer settings loaded => ip=$printerIp port=$port autoPrint=$autoPrintNewOrders',
    );
  }

  Future<void> saveSettings({
    required String ip,
    required int port,
    required bool autoPrint,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(_keyPrinterIp, ip);
    await prefs.setInt(_keyPrinterPort, port);
    await prefs.setBool(_keyAutoPrint, autoPrint);

    printerIp = ip;
    this.port = port;
    autoPrintNewOrders = autoPrint;

    debugPrint(
      '🖨️ Printer settings saved => ip=$printerIp port=$port autoPrint=$autoPrintNewOrders',
    );
  }

  Future<Map<String, dynamic>> getSettings() async {
    await init();
    return {
      'ip': printerIp,
      'port': port,
      'autoPrint': autoPrintNewOrders,
    };
  }

  Future<NetworkPrinter?> _connect() async {
    await init();

    try {
      final profile = await CapabilityProfile.load();
      final printer = NetworkPrinter(PaperSize.mm80, profile);

      final result = await printer.connect(printerIp, port: port);

      if (result != PosPrintResult.success) {
        debugPrint(
          '❌ Error conectando impresora => result=${result.toString()} ip=$printerIp port=$port',
        );
        return null;
      }

      debugPrint('✅ Impresora conectada => ip=$printerIp port=$port');
      return printer;
    } catch (e) {
      debugPrint('❌ Excepción conectando impresora: $e');
      return null;
    }
  }

  Future<bool> testPrint() async {
    final printer = await _connect();
    if (printer == null) return false;

    try {
      printer.text(
        'TEST IMPRESION',
        styles: const PosStyles(
          bold: true,
          align: PosAlign.center,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ),
      );

      printer.feed(1);

      printer.text(
        'GO PICADERA',
        styles: const PosStyles(
          bold: true,
          align: PosAlign.center,
        ),
      );

      printer.text(
        'Si ves este ticket, la impresora funciona correctamente.',
        styles: const PosStyles(align: PosAlign.center),
      );

      printer.feed(2);
      printer.cut();
      printer.disconnect();
      return true;
    } catch (e) {
      debugPrint('❌ Error en impresión de prueba: $e');
      printer.disconnect();
      return false;
    }
  }

  Future<bool> printOrder(AppOrder order) async {
    final printer = await _connect();
    if (printer == null) return false;

    try {
      printer.text(
        'GO PICADERA',
        styles: const PosStyles(
          bold: true,
          align: PosAlign.center,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ),
      );

      printer.text(
        'ORDEN #${order.id}',
        styles: const PosStyles(
          bold: true,
          align: PosAlign.center,
        ),
      );

      printer.feed(1);
      printer.hr();

      printer.text('Cliente: ${order.customerName}');
      printer.text('Telefono: ${order.phone}');
      printer.text(
        'Tipo: ${order.fulfillmentType == 'pickup' ? 'PICKUP' : 'DELIVERY'}',
        styles: const PosStyles(bold: true),
      );

      if (order.address.trim().isNotEmpty &&
          order.fulfillmentType != 'pickup') {
        printer.text('Direccion: ${order.address}');
      }

      if (order.paymentMethod.trim().isNotEmpty) {
        printer.text('Pago: ${order.paymentMethod.toUpperCase()}');
      }

      printer.hr();

      for (final item in order.items) {
        printer.row([
          PosColumn(
            text: '${item.qty}x ${item.name}',
            width: 8,
            styles: const PosStyles(bold: true),
          ),
          PosColumn(
            text: '\$${item.price}',
            width: 4,
            styles: const PosStyles(align: PosAlign.right),
          ),
        ]);

        if (item.notes.trim().isNotEmpty) {
          printer.text('  * ${item.notes}');
        }
      }

      printer.hr();

      if (order.subtotalValue > 0) {
        printer.row([
          PosColumn(text: 'Subtotal', width: 6),
          PosColumn(
            text: '\$${order.subtotal}',
            width: 6,
            styles: const PosStyles(align: PosAlign.right),
          ),
        ]);
      }

      if (order.deliveryFeeValue > 0) {
        printer.row([
          PosColumn(text: 'Delivery', width: 6),
          PosColumn(
            text: '\$${order.deliveryFee}',
            width: 6,
            styles: const PosStyles(align: PosAlign.right),
          ),
        ]);
      }

      if (order.transactionFeeValue > 0) {
        printer.row([
          PosColumn(text: 'Transaction fee', width: 6),
          PosColumn(
            text: '\$${order.transactionFee}',
            width: 6,
            styles: const PosStyles(align: PosAlign.right),
          ),
        ]);
      }

      if (order.taxTotalValue > 0) {
        printer.row([
          PosColumn(text: 'Tax', width: 6),
          PosColumn(
            text: '\$${order.taxTotal}',
            width: 6,
            styles: const PosStyles(align: PosAlign.right),
          ),
        ]);
      }

      if (order.discountTotalValue > 0) {
        printer.row([
          PosColumn(text: 'Discount', width: 6),
          PosColumn(
            text: '-\$${order.discountTotal}',
            width: 6,
            styles: const PosStyles(align: PosAlign.right),
          ),
        ]);
      }

      printer.hr();

      printer.row([
        PosColumn(
          text: 'TOTAL',
          width: 5,
          styles: const PosStyles(
            bold: true,
            height: PosTextSize.size2,
            width: PosTextSize.size2,
          ),
        ),
        PosColumn(
          text: '\$${order.total}',
          width: 7,
          styles: const PosStyles(
            bold: true,
            align: PosAlign.right,
            height: PosTextSize.size2,
            width: PosTextSize.size2,
          ),
        ),
      ]);

      printer.feed(1);

      if (order.note.trim().isNotEmpty) {
        printer.hr();
        printer.text(
          'NOTAS:',
          styles: const PosStyles(bold: true),
        );
        printer.text(order.note);
      }

      if (order.estimatedReadyMinutes > 0) {
        printer.feed(1);
        printer.text(
          'Tiempo estimado: ${order.estimatedReadyMinutes} min',
          styles: const PosStyles(bold: true),
        );
      }

      printer.feed(2);
      printer.cut();
      printer.disconnect();
      return true;
    } catch (e) {
      debugPrint('❌ Error imprimiendo orden: $e');
      printer.disconnect();
      return false;
    }
  }
}