import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';

/// Datos de Firebase de esta instalación. Se pasan al compilar:
///   flutter run --dart-define-from-file=firebase.local.json
/// (ese archivo no se sube a GitHub; cada restaurante tiene el suyo).
class FirebaseConfig {
  static const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const messagingSenderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  static const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const authDomain = String.fromEnvironment('FIREBASE_AUTH_DOMAIN');
  static const storageBucket = String.fromEnvironment('FIREBASE_STORAGE_BUCKET');
  static const vapidKey = String.fromEnvironment('FIREBASE_VAPID_KEY');

  static bool get configured => apiKey.isNotEmpty && appId.isNotEmpty && projectId.isNotEmpty && messagingSenderId.isNotEmpty;

  static FirebaseOptions get options => FirebaseOptions(
        apiKey: apiKey,
        appId: appId,
        messagingSenderId: messagingSenderId,
        projectId: projectId,
        authDomain: authDomain.isEmpty ? null : authDomain,
        storageBucket: storageBucket.isEmpty ? null : storageBucket,
      );
}

/// unavailable: sin Firebase configurado · off: falta activarlas · on: activas · blocked: el usuario las bloqueó.
enum PushStatus { unavailable, off, on, blocked }

final pushProvider = NotifierProvider<PushController, PushStatus>(PushController.new);

/// Notificaciones push: pedir permiso, registrar el token en el servidor y quitarlo al salir.
class PushController extends Notifier<PushStatus> {
  String? _token;
  bool _ready = false;
  StreamSubscription<String>? _refresh;

  @override
  PushStatus build() {
    ref.onDispose(() => _refresh?.cancel());
    if (!FirebaseConfig.configured) return PushStatus.unavailable;
    // Si ya dio permiso antes, se registra solo (sin volver a preguntar).
    Future.microtask(_resume);
    return PushStatus.off;
  }

  Future<bool> _ensureFirebase() async {
    if (_ready) return true;
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp(options: FirebaseConfig.options);
      _ready = true;
    } catch (error) {
      debugPrint('Firebase no se pudo iniciar: $error');
      state = PushStatus.unavailable;
    }
    return _ready;
  }

  bool _allowed(NotificationSettings s) =>
      s.authorizationStatus == AuthorizationStatus.authorized || s.authorizationStatus == AuthorizationStatus.provisional;

  Future<void> _resume() async {
    if (!await _ensureFirebase()) return;
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    if (_allowed(settings)) {
      await _register();
    } else if (settings.authorizationStatus == AuthorizationStatus.denied) {
      state = PushStatus.blocked;
    }
  }

  /// Botón "Activar notificaciones".
  Future<void> enable() async {
    if (!await _ensureFirebase()) return;
    final settings = await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);
    if (_allowed(settings)) {
      await _register();
    } else {
      state = PushStatus.blocked;
    }
  }

  Future<void> _register() async {
    try {
      // firebase_messaging 17 marca getToken/onTokenRefresh como obsoletos en favor del nuevo
      // modelo (register/onRegistered con IDs de instalación). Siguen funcionando y son lo que
      // usa el servidor (firebase-admin) para enviar; se migra cuando el servidor lo soporte.
      // ignore: deprecated_member_use
      final token = await FirebaseMessaging.instance.getToken(
        vapidKey: kIsWeb && FirebaseConfig.vapidKey.isNotEmpty ? FirebaseConfig.vapidKey : null,
      );
      if (token == null) return;
      await _send(token);
      // ignore: deprecated_member_use
      _refresh ??= FirebaseMessaging.instance.onTokenRefresh.listen((t) => _send(t));
      state = PushStatus.on;
    } catch (error) {
      debugPrint('No se pudo registrar para notificaciones: $error');
    }
  }

  Future<void> _send(String token) async {
    _token = token;
    final platform = kIsWeb ? 'web' : (defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android');
    await ref.read(dioProvider).post<void>('/notifications/token', data: {'token': token, 'platform': platform});
  }

  /// Al cerrar sesión: este dispositivo deja de recibir los pedidos de esta cuenta.
  Future<void> unregister() async {
    final token = _token;
    if (token == null) return;
    try {
      await ref.read(dioProvider).delete<void>('/notifications/token', data: {'token': token});
    } catch (_) {
      // sin red: el servidor lo desactiva cuando Firebase diga que ya no sirve
    }
    _token = null;
    state = FirebaseConfig.configured ? PushStatus.off : PushStatus.unavailable;
  }
}
