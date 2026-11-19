import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import 'screens/home/driver_shell_screen.dart';
import 'services/driver_notification_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(
  RemoteMessage message,
) async {
  await Firebase.initializeApp();

  debugPrint(
    'FCM background message: ${message.messageId} '
    '${message.data}',
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase debe inicializarse antes de acceder a FirebaseMessaging.instance.
  await Firebase.initializeApp();

  // Registra el procesamiento de mensajes cuando la app está
  // en segundo plano o cerrada.
  FirebaseMessaging.onBackgroundMessage(
    firebaseMessagingBackgroundHandler,
  );

  // Ahora el servicio puede acceder de forma segura a Firebase Messaging.
  await DriverNotificationService.instance.initialize();

  runApp(const DriverApp());
}

class DriverApp extends StatelessWidget {
  const DriverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GoPicadera Driver',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF4D4F),
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F7FB),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const DriverShellScreen(),
    );
  }
}
