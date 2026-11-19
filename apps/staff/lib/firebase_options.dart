import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  DefaultFirebaseOptions._();

  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'Firebase web no está configurado para este proyecto.',
      );
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions no soporta esta plataforma.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBnO3pY-kwkEXYB1zN5IQbcpPvA2vlH6F8',
    appId: '1:235501955057:android:5f5f5f5f5f5f5f5f5f5f5f',
    messagingSenderId: '235501955057',
    projectId: 'restaurantv1-51431',
    storageBucket: 'restaurantv1-51431.appspot.com',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyB7VY76DJ3C4WVJl2Or3RsPn-25mp0DCr4',
    appId: '1:235501955057:ios:9e9fae8d6d3a800b154650',
    messagingSenderId: '235501955057',
    projectId: 'restaurantv1-51431',
    storageBucket: 'restaurantv1-51431.firebasestorage.app',
    iosBundleId: 'Gopicadera',
  );
}