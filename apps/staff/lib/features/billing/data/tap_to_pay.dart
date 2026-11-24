import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mek_stripe_terminal/mek_stripe_terminal.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/api/api_exception.dart';
import 'billing_api.dart';
import 'billing_models.dart';

/// Tap to Pay solo existe en la app de Android (no en Chrome).
bool get tapToPaySupportedPlatform => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Si el aparato tiene lo necesario para Tap to Pay (sin pedir permisos).
class TapToPayHardware {
  const TapToPayHardware({required this.nfc, required this.nfcOn, required this.android13});
  final bool nfc;
  final bool nfcOn;
  final bool android13;

  /// Se muestra la opción solo si el aparato tiene NFC y Android 13+.
  bool get capable => nfc && android13;
}

const _device = MethodChannel('devepmax/device');

final tapToPayHardwareProvider = FutureProvider<TapToPayHardware>((ref) async {
  if (!tapToPaySupportedPlatform) return const TapToPayHardware(nfc: false, nfcOn: false, android13: false);
  try {
    final m = await _device.invokeMapMethod<String, bool>('tapToPayHardware') ?? const {};
    return TapToPayHardware(nfc: m['nfc'] ?? false, nfcOn: m['nfcOn'] ?? false, android13: m['android13'] ?? false);
  } on MissingPluginException {
    // App vieja sin el canal: se deja la opción y el SDK avisa al cobrar.
    return const TapToPayHardware(nfc: true, nfcOn: true, android13: true);
  }
});

enum TapToPayStatus { unavailable, idle, connecting, ready, error }

class TapToPayState {
  const TapToPayState(this.status, [this.message]);
  final TapToPayStatus status;
  final String? message;
}

final tapToPayProvider = NotifierProvider<TapToPayController, TapToPayState>(TapToPayController.new);

/// Este teléfono o tablet como lector: el cliente acerca su tarjeta o su celular al aparato.
/// Usa el SDK de Stripe Terminal. En modo prueba el lector es simulado (no hace falta tarjeta).
class TapToPayController extends Notifier<TapToPayState> {
  String? _locationId;
  bool _testMode = true;

  @override
  TapToPayState build() => tapToPaySupportedPlatform
      ? const TapToPayState(TapToPayStatus.idle)
      : const TapToPayState(TapToPayStatus.unavailable, 'Tap to Pay funciona en la app de Android');

  BillingApi get _api => ref.read(billingApiProvider);

  Future<String> _fetchToken() async {
    final token = await _api.connectionToken();
    _locationId = token.locationId;
    _testMode = token.testMode;
    return token.secret;
  }

  /// Prepara el lector del aparato (permiso de ubicación, SDK y conexión). Se llama al cobrar.
  Future<bool> ensureReady() async {
    if (!tapToPaySupportedPlatform) return false;
    if (state.status == TapToPayStatus.ready) return true;
    state = const TapToPayState(TapToPayStatus.connecting, 'Preparando Tap to Pay…');
    try {
      final hw = await ref.read(tapToPayHardwareProvider.future);
      if (!hw.capable) throw ApiException('Este aparato no tiene NFC o tiene Android anterior al 13: no puede cobrar con Tap to Pay');
      if (!hw.nfcOn) throw ApiException('Activa el NFC en los ajustes del teléfono para cobrar con Tap to Pay');
      final permission = await Permission.locationWhenInUse.request();
      if (!permission.isGranted) {
        throw ApiException('Permite la ubicación: Stripe la exige para cobrar con el teléfono');
      }
      if (!Terminal.isInitialized) {
        await Terminal.init(fetchToken: _fetchToken, shouldPrintLogs: kDebugMode);
      }
      if (_locationId == null) await _fetchToken();
      final connected = await Terminal.instance.getConnectedReader();
      if (connected == null) {
        final readers = await Terminal.instance
            .discoverReaders(TapToPayDiscoveryConfiguration(isSimulated: _testMode))
            .firstWhere((list) => list.isNotEmpty)
            .timeout(const Duration(seconds: 25));
        await Terminal.instance.connectReader(
          readers.first,
          configuration: TapToPayConnectionConfiguration(locationId: _locationId!, readerDelegate: _ReaderEvents(this)),
        );
      }
      state = const TapToPayState(TapToPayStatus.ready);
      return true;
    } on TerminalException catch (e) {
      state = TapToPayState(TapToPayStatus.error, friendlyTerminalError(e));
      return false;
    } on TimeoutException {
      state = const TapToPayState(TapToPayStatus.error, 'Este aparato no es compatible con Tap to Pay (Android 13+, NFC y Google Play)');
      return false;
    } catch (e) {
      state = TapToPayState(TapToPayStatus.error, ApiException.from(e).message);
      return false;
    }
  }

  void _disconnected() => state = const TapToPayState(TapToPayStatus.idle);

  /// Cobra en este aparato. Stripe muestra su pantalla para acercar la tarjeta y, al terminar,
  /// el servidor confirma el pago (igual que con el lector).
  Future<TerminalCharge> charge(BillView bill, {required double amount, required double tip, required String requestId}) async {
    if (!await ensureReady()) throw ApiException(state.message ?? 'Tap to Pay no está disponible');
    final created = await _api.tapToPay(bill.id, requestId: requestId, amount: amount, tip: tip);
    try {
      final intent = await Terminal.instance.retrievePaymentIntent(created.clientSecret);
      await Terminal.instance.processPaymentIntent(intent);
    } on TerminalException catch (e) {
      final cancelled = await _api.terminalCancel(created.paymentId).catchError((_) => TerminalCharge(
            paymentId: created.paymentId,
            status: 'cancelled',
            message: '',
          ));
      if (cancelled.status == 'succeeded') return cancelled; // se aprobó justo antes del error
      final userCancelled = e.code.name.toLowerCase().contains('cancel');
      return TerminalCharge(
        paymentId: created.paymentId,
        status: userCancelled ? 'cancelled' : 'failed',
        message: userCancelled ? 'Cobro cancelado' : friendlyTerminalError(e),
      );
    }
    // El servidor confirma con Stripe y suma el pago a la cuenta.
    for (var i = 0; i < 12; i++) {
      final status = await _api.terminalStatus(created.paymentId);
      if (status.status != 'waiting') return status;
      await Future<void>.delayed(const Duration(milliseconds: 800));
    }
    return _api.terminalStatus(created.paymentId);
  }
}

/// Errores del SDK en palabras para la caja.
String friendlyTerminalError(TerminalException e) {
  final code = e.code.name.toLowerCase();
  if (code.contains('declined')) return 'La tarjeta fue rechazada';
  if (code.contains('nfc')) return 'Activa el NFC del teléfono (Ajustes → Conexiones → NFC)';
  if (code.contains('location')) return 'Permite la ubicación para cobrar con el teléfono';
  if (code.contains('unsupported') || code.contains('attestation') || code.contains('insecure')) {
    return 'Este aparato no cumple los requisitos de Tap to Pay: ${e.message}';
  }
  if (code.contains('timeout')) return 'Se acabó el tiempo para acercar la tarjeta';
  return e.message;
}

/// Avisos del lector del aparato (desconexión, reconexión). No hace falta mostrar nada más.
class _ReaderEvents extends TapToPayReaderDelegate {
  _ReaderEvents(this._controller);
  final TapToPayController _controller;

  @override
  void onAcceptTermsOfService() {}

  @override
  void onDisconnect(DisconnectReason reason) => _controller._disconnected();

  @override
  void onReaderReconnectFailed(Reader reader) => _controller._disconnected();

  @override
  void onReaderReconnectStarted(Reader reader, Cancellable cancelReconnect, DisconnectReason reason) {}

  @override
  void onReaderReconnectSucceeded(Reader reader) {}

  @override
  void onFinishInstallingUpdate(ReaderSoftwareUpdate? update, TerminalException? exception) {}

  @override
  void onReportReaderSoftwareUpdateProgress(double progress) {}

  @override
  void onRequestReaderDisplayMessage(ReaderDisplayMessage message) {}

  @override
  void onRequestReaderInput(List<ReaderInputOption> options) {}

  @override
  void onStartInstallingUpdate(ReaderSoftwareUpdate update, Cancellable cancelUpdate) {}
}
