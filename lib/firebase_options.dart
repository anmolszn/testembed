import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) throw UnsupportedError('Web not configured');
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        throw UnsupportedError('iOS not configured — Android only for now');
      default:
        throw UnsupportedError('Unsupported platform');
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCxHFzEkzbXvXEEEyxGolkhT41RHV9cacs',
    appId: '1:600215360784:android:e53ce9f31fa6fabef58195',
    messagingSenderId: '600215360784',
    projectId: 'testembed-2e60c',
    storageBucket: 'testembed-2e60c.firebasestorage.app',
  );
}
