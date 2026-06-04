import 'package:firebase_core/firebase_core.dart';

class WebFirebaseConfig {
  static const String apiKey = String.fromEnvironment(
    'FIREBASE_WEB_API_KEY',
    defaultValue: '', // ⚠️ Set via environment variable only
  );

  static const String appId = String.fromEnvironment(
    'FIREBASE_WEB_APP_ID',
    defaultValue: '', // ⚠️ Set via environment variable only
  );

  static const String messagingSenderId = String.fromEnvironment(
    'FIREBASE_WEB_MESSAGING_SENDER_ID',
    defaultValue: '382977539313',
  );

  static const String projectId = String.fromEnvironment(
    'FIREBASE_WEB_PROJECT_ID',
    defaultValue: 'aether-9105e',
  );

  static const String storageBucket = String.fromEnvironment(
    'FIREBASE_WEB_STORAGE_BUCKET',
    defaultValue: 'aether-9105e.firebasestorage.app',
  );

  static const String authDomain = String.fromEnvironment(
    'FIREBASE_WEB_AUTH_DOMAIN',
    defaultValue: 'aether-9105e.firebaseapp.com',
  );

  static const String measurementId = String.fromEnvironment(
    'FIREBASE_WEB_MEASUREMENT_ID',
    defaultValue: '',
  );

  static const String vapidKey = String.fromEnvironment(
    'FIREBASE_WEB_VAPID_KEY',
    defaultValue: '',
  );

  static bool get isConfigured {
    return apiKey.isNotEmpty &&
        appId.isNotEmpty &&
        messagingSenderId.isNotEmpty &&
        projectId.isNotEmpty;
  }

  static FirebaseOptions get options {
    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: messagingSenderId,
      projectId: projectId,
      storageBucket: storageBucket,
      authDomain: authDomain,
      measurementId: measurementId.isEmpty ? null : measurementId,
    );
  }
}