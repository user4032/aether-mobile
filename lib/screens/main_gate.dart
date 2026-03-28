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

class _MainGateState extends State<MainGate> {
  bool _isLoading = true;
  String? _deviceId, _userName, _publicKey;
  final _storage = const FlutterSecureStorage();

  @override
  void initState() { super.initState(); _init(); }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    lang = prefs.getString('lang') ?? 'uk';
    String? id = prefs.getString('device_id');
    String? pub = prefs.getString('public_key');
    String? priv = await _storage.read(key: 'private_key');
    if (id == null || pub == null || priv == null) {
      id = const Uuid().v4();
      final keyPair = await X25519().newKeyPair();
      final pubKeyBytes = await keyPair.extractPublicKey();
      final privKeyBytes = await keyPair.extractPrivateKeyBytes();
      await prefs.setString('device_id', id);
      await prefs.setString('public_key', base64Encode(pubKeyBytes.bytes));
      await _storage.write(key: 'private_key', value: base64Encode(privKeyBytes));
      pub = base64Encode(pubKeyBytes.bytes);
    }
    setState(() { _deviceId = id; _publicKey = pub; _userName = prefs.getString('user_name'); _isLoading = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return Scaffold(body: Center(child: AetherLoader(size: 34, color: Colors.white)));
    if (_userName == null) return AuthScreen(deviceId: _deviceId!, publicKey: _publicKey!, onSuccess: (name) { setState(() { _userName = name; }); });
    return ContactsScreen(deviceId: _deviceId!, userName: _userName!, publicKey: _publicKey!);
  }
}