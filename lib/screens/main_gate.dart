import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cryptography/cryptography.dart';
import 'package:uuid/uuid.dart';
import '../utils/globals.dart';
import '../widgets/ui_core.dart';
import 'auth_screen.dart';
import 'contacts_screen.dart';

class MainGate extends StatefulWidget {
  const MainGate({super.key});
  @override
  State<MainGate> createState() => _MainGateState();
}

class _MainGateState extends State<MainGate> with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  bool _splashDone = false;
  String? _deviceId, _userName, _publicKey;
  final _storage = const FlutterSecureStorage();

  // Splash visibility controller
  late final AnimationController _splashCtrl;
  late final Animation<double> _splashOpacity;

  @override
  void initState() {
    super.initState();
    _splashCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _splashOpacity = CurvedAnimation(parent: _splashCtrl, curve: Curves.easeOut);
    _init();
  }

  @override
  void dispose() {
    _splashCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    // Show splash for at least 2 seconds for the animation
    final startTime = DateTime.now();

    final prefs = await SharedPreferences.getInstance();
    lang = prefs.getString('lang') ?? 'uk';
    String? id = prefs.getString('device_id');
    String? pub = prefs.getString('public_key');
    String? priv = await _storage.read(key: 'private_key');

    if (id == null) {
      id = const Uuid().v4();
      await prefs.setString('device_id', id);
    }
    if (pub == null || priv == null) {
      final keyPair = await X25519().newKeyPair();
      final pubKeyBytes = await keyPair.extractPublicKey();
      final privKeyBytes = await keyPair.extractPrivateKeyBytes();
      await prefs.setString('public_key', base64Encode(pubKeyBytes.bytes));
      await _storage.write(key: 'private_key', value: base64Encode(privKeyBytes));
      pub = base64Encode(pubKeyBytes.bytes);
    }

    // Ensure minimum splash duration
    final elapsed = DateTime.now().difference(startTime);
    const minDuration = Duration(milliseconds: 2200);
    if (elapsed < minDuration) {
      await Future.delayed(minDuration - elapsed);
    }

    if (mounted) {
      setState(() {
        _deviceId = id;
        _publicKey = pub;
        _userName = prefs.getString('user_name');
        _isLoading = false;
      });

      // Fade out splash
      await _splashCtrl.reverse(from: 1.0);
      if (mounted) setState(() => _splashDone = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    // After splash is fully gone, show the real screen directly
    if (_splashDone && !_isLoading) {
      return _buildContent();
    }

    // While loading or fading: show splash on top of content (or just splash)
    return Stack(
      children: [
        if (!_isLoading) _buildContent(),
        if (!_splashDone)
          FadeTransition(
            opacity: _splashOpacity.value == 0 && _isLoading
                ? const AlwaysStoppedAnimation(1.0)
                : _splashOpacity,
            child: const LumynSplashScreen(),
          ),
        if (_isLoading && _splashOpacity.value == 0)
          const LumynSplashScreen(),
      ],
    );
  }

  Widget _buildContent() {
    if (_userName == null) {
      return AuthScreen(
        deviceId: _deviceId!,
        publicKey: _publicKey!,
        onSuccess: (name) { setState(() { _userName = name; }); },
      );
    }
    return ContactsScreen(
      deviceId: _deviceId!,
      userName: _userName!,
      publicKey: _publicKey!,
    );
  }
}