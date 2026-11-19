import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'driver_api_service.dart';

const AndroidNotificationChannel _driverOrdersChannel =
    AndroidNotificationChannel(
  'driver_orders_v2',
  'Órdenes para drivers',
  description: 'Avisos de nuevas órdenes disponibles para entregar.',
  importance: Importance.max,
  playSound: true,
  enableVibration: true,
);

enum DriverOrderNotificationSource {
  socket,
  foregroundPush,
  notificationTap,
  initialNotification,
  localNotificationTap,
}

extension DriverOrderNotificationSourceValue on DriverOrderNotificationSource {
  String get value {
    switch (this) {
      case DriverOrderNotificationSource.socket:
        return 'socket';
      case DriverOrderNotificationSource.foregroundPush:
        return 'foreground_push';
      case DriverOrderNotificationSource.notificationTap:
        return 'notification_tap';
      case DriverOrderNotificationSource.initialNotification:
        return 'initial_notification';
      case DriverOrderNotificationSource.localNotificationTap:
        return 'local_notification_tap';
    }
  }

  bool get shouldPlayInAppSound {
    return this == DriverOrderNotificationSource.socket ||
        this == DriverOrderNotificationSource.foregroundPush;
  }
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();

  debugPrint(
    'FCM background message: ${message.messageId} ${message.data}',
  );
}

typedef DriverOrderNotificationCallback = FutureOr<void> Function(
  String orderId,
  Map<String, dynamic> data,
);

class DriverNotificationService {
  DriverNotificationService._();

  static final DriverNotificationService instance =
      DriverNotificationService._();

  static const String _deviceIdKey = 'driver_notification_device_id';
  static const String _processedOrdersKey = 'processed_driver_order_pushes';
  static const Duration _dedupWindow = Duration(minutes: 10);

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  DriverOrderNotificationCallback? _onOrderAvailable;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;
  StreamSubscription<String>? _tokenRefreshSubscription;

  String? _driverId;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    await Firebase.initializeApp();

    FirebaseMessaging.onBackgroundMessage(
      firebaseMessagingBackgroundHandler,
    );

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();

    await _localNotifications.initialize(
      const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
      onDidReceiveNotificationResponse: (response) async {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;

        try {
          final decoded = jsonDecode(payload);
          if (decoded is! Map) return;

          final data = Map<String, dynamic>.from(decoded);

          await _dispatchOrder(
            data,
            source: DriverOrderNotificationSource.localNotificationTap,
            force: true,
          );
        } catch (error) {
          debugPrint(
            'Invalid local notification payload: $error',
          );
        }
      },
    );

    final androidPlugin =
        _localNotifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.createNotificationChannel(
      _driverOrdersChannel,
    );

    await androidPlugin?.requestNotificationsPermission();

    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    await _messaging.setForegroundNotificationPresentationOptions(
      alert: false,
      badge: true,
      sound: false,
    );

    _foregroundSubscription =
        FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    _openedSubscription =
        FirebaseMessaging.onMessageOpenedApp.listen((message) async {
      await _dispatchOrder(
        message.data,
        source: DriverOrderNotificationSource.notificationTap,
        force: true,
      );
    });

    _tokenRefreshSubscription = _messaging.onTokenRefresh.listen((token) async {
      await _registerToken(token);
    });

    _initialized = true;
  }

  Future<void> bindDriver({
    required String driverId,
    required DriverOrderNotificationCallback onOrderAvailable,
  }) async {
    _driverId = driverId;
    _onOrderAvailable = onOrderAvailable;

    final token = await _messaging.getToken();

    if (token != null && token.isNotEmpty) {
      await _registerToken(token);
    }

    final initialMessage = await _messaging.getInitialMessage();

    if (initialMessage != null) {
      await _dispatchOrder(
        initialMessage.data,
        source: DriverOrderNotificationSource.initialNotification,
        force: true,
      );
    }
  }

  Future<bool> processSocketOrder(dynamic payload) async {
    final data = _normalizePayload(payload);

    return _dispatchOrder(
      data,
      source: DriverOrderNotificationSource.socket,
    );
  }

  Future<void> _handleForegroundMessage(
    RemoteMessage message,
  ) async {
    if (message.data['type'] != 'driver_order_available') return;

    final processed = await _dispatchOrder(
      message.data,
      source: DriverOrderNotificationSource.foregroundPush,
    );

    if (!processed) return;

    final orderId = '${message.data['orderId'] ?? ''}'.trim();
    final publicCode = '${message.data['publicCode'] ?? orderId}'.trim();

    await _localNotifications.show(
      _stableNotificationId(orderId),
      message.notification?.title ?? 'Nueva orden disponible',
      message.notification?.body ?? '$publicCode está lista para entrega',
      NotificationDetails(
        android: AndroidNotificationDetails(
          _driverOrdersChannel.id,
          _driverOrdersChannel.name,
          channelDescription: _driverOrdersChannel.description,
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.message,
          visibility: NotificationVisibility.public,
          fullScreenIntent: false,
          playSound: false,
          enableVibration: false,
          onlyAlertOnce: true,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: false,
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }

  Future<bool> _dispatchOrder(
    Map<String, dynamic> data, {
    required DriverOrderNotificationSource source,
    bool force = false,
  }) async {
    if (data['type'] != null && data['type'] != 'driver_order_available') {
      return false;
    }

    final orderId = '${data['orderId'] ?? data['id'] ?? ''}'.trim();

    if (orderId.isEmpty) return false;

    if (!force && !await _markAsNew(orderId)) {
      return false;
    }

    final callback = _onOrderAvailable;

    if (callback != null) {
      await callback(
        orderId,
        <String, dynamic>{
          ...data,
          'notificationSource': source.value,
          'shouldPlayInAppSound': source.shouldPlayInAppSound,
          'openedFromNotification':
              source == DriverOrderNotificationSource.notificationTap ||
                  source == DriverOrderNotificationSource.initialNotification ||
                  source == DriverOrderNotificationSource.localNotificationTap,
        },
      );
    }

    return true;
  }

  Future<void> _registerToken(String token) async {
    final driverId = _driverId;

    if (driverId == null || driverId.isEmpty) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      var deviceId = prefs.getString(_deviceIdKey);

      if (deviceId == null || deviceId.isEmpty) {
        deviceId = '${DateTime.now().microsecondsSinceEpoch}-'
            '${Random.secure().nextInt(1 << 32)}';

        await prefs.setString(_deviceIdKey, deviceId);
      }

      await DriverApiService.instance.registerNotificationToken(
        token: token,
        driverId: driverId,
        deviceId: deviceId,
      );
    } catch (error) {
      debugPrint(
        'Driver FCM token registration failed: $error',
      );
    }
  }

  Future<bool> _markAsNew(String orderId) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final raw = prefs.getString(_processedOrdersKey);
    final retained = <String, int>{};

    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);

        if (decoded is Map) {
          for (final entry in decoded.entries) {
            final timestamp = int.tryParse('${entry.value}');

            if (timestamp == null) continue;

            final time = DateTime.fromMillisecondsSinceEpoch(timestamp);

            if (now.difference(time) <= _dedupWindow) {
              retained['${entry.key}'] = timestamp;
            }
          }
        }
      } catch (_) {}
    }

    if (retained.containsKey(orderId)) return false;

    retained[orderId] = now.millisecondsSinceEpoch;

    await prefs.setString(
      _processedOrdersKey,
      jsonEncode(retained),
    );

    return true;
  }

  Map<String, dynamic> _normalizePayload(dynamic payload) {
    if (payload is Map) {
      final data = Map<String, dynamic>.from(payload);

      return {
        ...data,
        'type': data['type'] ?? 'driver_order_available',
        'orderId': data['orderId'] ?? data['id'],
      };
    }

    return <String, dynamic>{};
  }

  int _stableNotificationId(String value) {
    var hash = 0;

    for (final codeUnit in value.codeUnits) {
      hash = 0x1fffffff & (hash * 31 + codeUnit);
    }

    return hash;
  }

  Future<void> dispose() async {
    await _foregroundSubscription?.cancel();
    await _openedSubscription?.cancel();
    await _tokenRefreshSubscription?.cancel();
  }
}
