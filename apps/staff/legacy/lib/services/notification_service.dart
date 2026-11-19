import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  } on FirebaseException catch (e) {
    if (e.code != 'duplicate-app') {
      rethrow;
    }
  }

  await NotificationService.ensureBackgroundReady();
  await NotificationService.showIncomingOrderNotification(message);
}

typedef ForegroundOrderPushHandler = Future<void> Function({
  String? orderId,
  String? publicCode,
});

class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  static final AudioPlayer _audioPlayer = AudioPlayer();

  static const String _baseUrl =
      'https://gopicaderabackend-production.up.railway.app';

  static const String ordersChannelId = 'new_orders';

  static const AndroidNotificationChannel _ordersChannel =
      AndroidNotificationChannel(
    ordersChannelId,
    'Nuevas órdenes',
    description: 'Alertas críticas para nuevas órdenes del restaurante',
    importance: Importance.max,
    playSound: true,
    sound: RawResourceAndroidNotificationSound('alert'),
    enableVibration: true,
  );

  static bool _initialized = false;
  static bool _localNotificationsInitialized = false;
  static bool _soundPlaying = false;
  static Timer? _soundStopTimer;

  static String? _lastRegisteredToken;
  static bool _registeringToken = false;
  static ForegroundOrderPushHandler? _foregroundOrderPushHandler;

  static String? _pendingOrderId;
  static String? _pendingPublicCode;
  static bool _consumingPendingPush = false;

  static void setForegroundOrderPushHandler(
    ForegroundOrderPushHandler? handler,
  ) {
    _foregroundOrderPushHandler = handler;
  }

  static Future<void> init() async {
    if (_initialized) return;

    await _initializeLocalNotifications();
    await _initializeFirebaseMessaging();

    _initialized = true;
  }

  static Future<void> ensureBackgroundReady() async {
    await _initializeLocalNotifications();
  }

  static Future<void> consumeInitialOrderPush() async {
    if (_consumingPendingPush) return;
    if (_foregroundOrderPushHandler == null) return;
    if ((_pendingOrderId == null || _pendingOrderId!.isEmpty) &&
        (_pendingPublicCode == null || _pendingPublicCode!.isEmpty)) {
      return;
    }

    _consumingPendingPush = true;

    final orderId = _pendingOrderId;
    final publicCode = _pendingPublicCode;

    _pendingOrderId = null;
    _pendingPublicCode = null;

    try {
      await _foregroundOrderPushHandler?.call(
        orderId: orderId,
        publicCode: publicCode,
      );
    } catch (e) {
      debugPrint('Error consumiendo push inicial: $e');
    } finally {
      _consumingPendingPush = false;
    }
  }

  static Future<void> _initializeLocalNotifications() async {
    if (_localNotificationsInitialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const initSettings = InitializationSettings(
      android: androidSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    final androidPlugin =
        _localNotifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.createNotificationChannel(_ordersChannel);

    _localNotificationsInitialized = true;
  }

  static Future<void> _initializeFirebaseMessaging() async {
    final messaging = FirebaseMessaging.instance;

    await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    await messaging.setForegroundNotificationPresentationOptions(
      alert: false,
      badge: true,
      sound: false,
    );

    final token = await messaging.getToken();
    debugPrint('FCM token: $token');

    if (token != null && token.isNotEmpty) {
      await _registerTokenInBackend(token, force: true);
    }

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    FirebaseMessaging.onMessage.listen((message) async {
      debugPrint('Push recibida en foreground: ${message.messageId}');
      await _dispatchOrderPush(message);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) async {
      debugPrint('Notificación abierta: ${message.messageId}');
      await stopIncomingLoopSound();
      await _dispatchOrderPush(message, storeIfNoHandler: true);
    });

    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) {
      debugPrint('App abierta desde push: ${initialMessage.messageId}');
      _storePendingPush(initialMessage);
    }

    messaging.onTokenRefresh.listen((newToken) async {
      debugPrint('FCM token refreshed: $newToken');
      await _registerTokenInBackend(newToken, force: true);
    });
  }

  static Future<void> _dispatchOrderPush(
    RemoteMessage message, {
    bool storeIfNoHandler = false,
  }) async {
    final data = message.data;
    final orderId = data['orderId']?.toString();
    final publicCode = data['publicCode']?.toString();

    if (_foregroundOrderPushHandler != null) {
      await _foregroundOrderPushHandler?.call(
        orderId: orderId,
        publicCode: publicCode,
      );
      return;
    }

    if (storeIfNoHandler) {
      _pendingOrderId = orderId;
      _pendingPublicCode = publicCode;
    }
  }

  static void _storePendingPush(RemoteMessage message) {
    final data = message.data;
    _pendingOrderId = data['orderId']?.toString();
    _pendingPublicCode = data['publicCode']?.toString();
  }

  static Future<void> _registerTokenInBackend(
    String token, {
    bool force = false,
  }) async {
    if (token.isEmpty) return;
    if (_registeringToken) return;
    if (!force && _lastRegisteredToken == token) return;

    _registeringToken = true;

    try {
      final url = Uri.parse('$_baseUrl/api/notifications/register-token');

      debugPrint('POST => $url');

      final response = await http
          .post(
            url,
            headers: const {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              'User-Agent': 'Mozilla/5.0 Flutter Restaurant App',
            },
            body: jsonEncode({
              'token': token,
              'platform': defaultTargetPlatform.name,
            }),
          )
          .timeout(const Duration(seconds: 15));

      debugPrint(
        'register-token response => ${response.statusCode} ${response.body}',
      );

      if (response.statusCode >= 400) {
        throw Exception(
          'Backend respondió ${response.statusCode}: ${response.body}',
        );
      }

      _lastRegisteredToken = token;
      debugPrint('FCM token registrado en backend correctamente');
    } catch (e) {
      debugPrint('Error registrando FCM token en backend: $e');
    } finally {
      _registeringToken = false;
    }
  }

  static Future<void> showIncomingOrderNotification(
    RemoteMessage message,
  ) async {
    await _initializeLocalNotifications();

    final data = message.data;

    final title = message.notification?.title ??
        data['title']?.toString() ??
        'Nueva orden';

    final body = message.notification?.body ??
        data['body']?.toString() ??
        'Tienes una orden entrante';

    const androidDetails = AndroidNotificationDetails(
      ordersChannelId,
      'Nuevas órdenes',
      channelDescription:
          'Alertas críticas para nuevas órdenes del restaurante',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('alert'),
      enableVibration: true,
      category: AndroidNotificationCategory.alarm,
      fullScreenIntent: true,
      ticker: 'Nueva orden',
      visibility: NotificationVisibility.public,
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
    );

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      notificationDetails,
      payload: data['orderId']?.toString(),
    );
  }

  static Future<void> playIncomingLoopSound() async {
    try {
      _soundStopTimer?.cancel();

      if (!_soundPlaying) {
        await _audioPlayer.stop();
        await _audioPlayer.setAsset('assets/sounds/alert.mp3');
        await _audioPlayer.setLoopMode(LoopMode.one);
        await _audioPlayer.play();
        _soundPlaying = true;
      }

      _soundStopTimer = Timer(const Duration(seconds: 45), () async {
        await stopIncomingLoopSound();
      });
    } catch (e) {
      debugPrint('Error reproduciendo sonido de orden: $e');
    }
  }

  static Future<void> stopIncomingLoopSound() async {
    try {
      _soundStopTimer?.cancel();
      _soundStopTimer = null;
      _soundPlaying = false;
      await _audioPlayer.stop();
    } catch (e) {
      debugPrint('Error deteniendo sonido: $e');
    }
  }

  static void _onNotificationTap(NotificationResponse response) {
    debugPrint('Notificación local tocada. Payload: ${response.payload}');
    stopIncomingLoopSound();
  }
}
