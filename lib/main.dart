import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_web_config.dart';
import 'screens/main_gate.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb && WebFirebaseConfig.isConfigured) {
    await Firebase.initializeApp(options: WebFirebaseConfig.options);
  }
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.black, // Vercel style dark nav bar
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Lumyn',
      theme: ThemeData(
        scaffoldBackgroundColor: Colors.black,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        colorScheme: const ColorScheme.dark(
          primary: Colors.white,
          secondary: Color(0xFF888888),
          surface: Color(0xFF0A0A0A),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          iconTheme: IconThemeData(color: Colors.white),
          titleTextStyle: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
        ),
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
            TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
            TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
          },
        ),
      ),
      home: const MainGate(), // Відразу показуємо головний екран
    );
  }
} 