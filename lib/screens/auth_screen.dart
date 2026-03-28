import 'dart:ui'; 
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../utils/globals.dart';
import '../widgets/ui_core.dart';

class AuthScreen extends StatefulWidget {
  final String deviceId, publicKey;
  final Function(String) onSuccess;
  const AuthScreen({super.key, required this.deviceId, required this.publicKey, required this.onSuccess});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  // 0=login, 1=register_form, 2=verify_code
  int _step = 0;
  bool isLoading = false;
  final _nameController = TextEditingController();
  final _passController = TextEditingController();
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  String? _pendingEmail;

  void _login() async {
    final name = _nameController.text.trim();
    final pass = _passController.text.trim();
    if (name.isEmpty || pass.isEmpty) return;
    setState(() => isLoading = true);
    io.Socket s = io.io('https://aether-backend-hrmq.onrender.com', {'transports': ['websocket'], 'forceNew': true});
    s.connect();
    s.onConnect((_) {
      s.emitWithAck('login', {'userName': name, 'password': pass, 'publicKey': widget.publicKey}, ack: (dynamic response) async {
        s.dispose();
        if (response['success'] == true) {
          await (await SharedPreferences.getInstance()).setString('user_name', name);
          widget.onSuccess(name);
        } else {
          setState(() => isLoading = false);
          _showSnack(response['message'] ?? t('Помилка', 'Error'), isError: true);
        }
      });
    });
  }

  void _sendCode() async {
    final name = _nameController.text.trim();
    final pass = _passController.text.trim();
    final email = _emailController.text.trim();
    if (name.isEmpty || pass.isEmpty || email.isEmpty) return;
    if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(email)) {
      _showSnack(t('Невірний формат email', 'Invalid email format'), isError: true);
      return;
    }
    setState(() => isLoading = true);
    io.Socket s = io.io('https://aether-backend-hrmq.onrender.com', {'transports': ['websocket'], 'forceNew': true});
    s.connect();
    s.onConnect((_) {
      s.emitWithAck('send_verification_email', {
        'userName': name, 'email': email, 'password': pass, 'publicKey': widget.publicKey,
      }, ack: (dynamic response) {
        s.dispose();
        setState(() => isLoading = false);
        if (response['success'] == true) {
          _pendingEmail = email;
          setState(() => _step = 2);
        } else {
          _showSnack(response['message'] ?? t('Помилка', 'Error'), isError: true);
        }
      });
    });
  }

  void _verifyCode() async {
    final code = _codeController.text.trim();
    if (code.length != 6) return;
    setState(() => isLoading = true);
    io.Socket s = io.io('https://aether-backend-hrmq.onrender.com', {'transports': ['websocket'], 'forceNew': true});
    s.connect();
    s.onConnect((_) {
      s.emitWithAck('verify_email_code', {'email': _pendingEmail, 'code': code}, ack: (dynamic response) async {
        s.dispose();
        setState(() => isLoading = false);
        if (response['success'] == true) {
          final name = _nameController.text.trim();
          await (await SharedPreferences.getInstance()).setString('user_name', name);
          widget.onSuccess(name);
        } else {
          _showSnack(response['message'] ?? t('Невірний код', 'Invalid code'), isError: true);
        }
      });
    });
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: isError ? Colors.red.shade900 : const Color(0xFF333333),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: LiquidBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween(begin: const Offset(0.05, 0), end: Offset.zero).animate(anim),
                  child: child,
                ),
              ),
              child: _step == 2 ? _buildCodeStep() : (_step == 1 ? _buildRegisterStep() : _buildLoginStep()),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginStep() {
    return Column(
      key: const ValueKey('login'),
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t("З поверненням.", "Welcome back."), style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: -1, color: Colors.white)),
        const SizedBox(height: 8),
        const Text("Aether Core Protocol", style: TextStyle(fontSize: 16, color: Colors.white70)),
        const SizedBox(height: 48),
        GlassInput(controller: _nameController, hintText: t("Нікнейм", "Username"), inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_.\-]'))]),
        const SizedBox(height: 16),
        GlassInput(controller: _passController, hintText: t("Пароль", "Password"), obscureText: true),
        const SizedBox(height: 32),
        ShineButton(text: t("Увійти", "Sign In"), isLoading: isLoading, onPressed: _login),
        const SizedBox(height: 24),
        GestureDetector(
          onTap: () => setState(() => _step = 1),
          child: Text(t("Немає акаунту? Створити", "Don't have an account? Register"), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }

  Widget _buildRegisterStep() {
    return Column(
      key: const ValueKey('register'),
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t("Створити акаунт.", "Create account."), style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: -1, color: Colors.white)),
        const SizedBox(height: 8),
        const Text("Aether Core Protocol", style: TextStyle(fontSize: 16, color: Colors.white70)),
        const SizedBox(height: 48),
        GlassInput(controller: _nameController, hintText: t("Нікнейм", "Username"), inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_.\-]'))]),
        const SizedBox(height: 16),
        GlassInput(controller: _emailController, hintText: t("Email адреса", "Email address"), keyboardType: TextInputType.emailAddress),
        const SizedBox(height: 16),
        GlassInput(controller: _passController, hintText: t("Пароль", "Password"), obscureText: true),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            t("На вказаний email прийде код підтвердження", "A verification code will be sent to your email"),
            style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
          ),
        ),
        const SizedBox(height: 24),
        ShineButton(text: t("Отримати код", "Get Code"), isLoading: isLoading, onPressed: _sendCode),
        const SizedBox(height: 24),
        GestureDetector(
          onTap: () => setState(() => _step = 0),
          child: Text(t("Вже є акаунт? Увійти", "Already have an account? Sign In"), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }

  Widget _buildCodeStep() {
    return Column(
      key: const ValueKey('code'),
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.email_outlined, color: Colors.white70, size: 48),
        const SizedBox(height: 24),
        Text(t("Перевір пошту.", "Check your email."), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -1, color: Colors.white)),
        const SizedBox(height: 8),
        Text(t("Код надіслано на", "Code sent to"), style: const TextStyle(color: Colors.white70, fontSize: 14)),
        Text(_pendingEmail ?? '', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 48),
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: TextField(
                controller: _codeController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: 16),
                decoration: InputDecoration(
                  hintText: '000000',
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.2), fontSize: 32, letterSpacing: 16),
                  border: InputBorder.none,
                  counterText: '',
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                ),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
            ),
          ),
        ),
        const SizedBox(height: 32),
        ShineButton(text: t("Підтвердити", "Verify"), isLoading: isLoading, onPressed: _verifyCode),
        const SizedBox(height: 16),
        TextButton(
          onPressed: () => setState(() { _step = 1; _codeController.clear(); }),
          child: Text(t("← Назад", "← Back"), style: const TextStyle(color: Colors.white70)),
        ),
      ],
    );
  }
}