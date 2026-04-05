import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cryptography/cryptography.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../utils/globals.dart';
import '../widgets/ui_core.dart';
import 'main_gate.dart';

class AuthScreen extends StatefulWidget {
  final String deviceId, publicKey;
  final Function(String) onSuccess;
  const AuthScreen({super.key, required this.deviceId, required this.publicKey, required this.onSuccess});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  // 0=login, 1=register_form, 2=verify_code, 3=restore_backup
  int _step = 0;
  bool isLoading = false;
  bool _showLoginPassword = false;
  bool _showRegisterPassword = false;
  bool _showRestorePassword = false;

  String get _serverUrl => 'https://aether-backend-hrmq.onrender.com';

  final _nameController = TextEditingController();
  final _passController = TextEditingController();
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _restoreTokenController = TextEditingController();
  final _restorePasswordController = TextEditingController();

  String? _pendingEmail;

  String _deviceName() {
    final platform = Platform.isAndroid
        ? 'Android'
        : Platform.isIOS
            ? 'iPhone'
            : Platform.isWindows
                ? 'Windows'
                : Platform.operatingSystem;
    return '$platform ${widget.deviceId.substring(0, 6)}';
  }

  Future<void> _applyLinkedKeysAndFinish(String userName, dynamic response) async {
    final prefs = await SharedPreferences.getInstance();
    final storage = const FlutterSecureStorage();
    if (response is Map<String, dynamic>) {
      final newPub = response['publicKey'];
      final newPriv = response['privateKey'];
      if (newPub is String && newPub.isNotEmpty) await prefs.setString('public_key', newPub);
      if (newPriv is String && newPriv.isNotEmpty) await storage.write(key: 'private_key', value: newPriv);
    }
    await prefs.setString('user_name', userName);
    widget.onSuccess(userName);
  }

  Future<void> _waitForDeviceApproval(io.Socket socket, String requestId, String userName) async {
    for (int i = 0; i < 90; i++) {
      final completer = Completer<Map<String, dynamic>>();
      socket.emitWithAck('check_device_link_status', {'requestId': requestId, 'userName': userName}, ack: (dynamic data) {
        completer.complete(Map<String, dynamic>.from(data as Map));
      });
      final status = await completer.future;
      if (status['success'] == true && status['status'] == 'approved') {
        await _applyLinkedKeysAndFinish(userName, status);
        socket.dispose();
        return;
      }
      if (status['status'] == 'rejected' || status['status'] == 'expired' || status['status'] == 'missing') {
        socket.dispose();
        if (mounted) {
          setState(() => isLoading = false);
          _showSnack((status['message'] ?? t('Запит на підключення відхилено', 'Device link request was rejected')).toString(), isError: true);
        }
        return;
      }
      await Future.delayed(const Duration(seconds: 2));
    }
    socket.dispose();
    if (mounted) {
      setState(() => isLoading = false);
      _showSnack(t('Час очікування підтвердження минув', 'Approval timed out'), isError: true);
    }
  }

  void _login() async {
    final name = _nameController.text.trim();
    final pass = _passController.text.trim();
    if (name.isEmpty || pass.isEmpty) return;
    setState(() => isLoading = true);
    
    io.Socket s = io.io(_serverUrl, {
      'transports': ['websocket'],
      'forceNew': true,
      'reconnection': false,
      'reconnectionDelay': 0,
    });
    
    // Set connection timeout
    final timeout = Future.delayed(const Duration(seconds: 30), () {
      if (mounted) {
        setState(() => isLoading = false);
        _showSnack(t('Помилка підключення до сервера', 'Connection timeout'), isError: true);
      }
      s.dispose();
    });
    
    s.onConnect((_) {
      s.emitWithAck('login_device_request', {
        'userName': name, 'password': pass, 'publicKey': widget.publicKey,
        'deviceId': widget.deviceId, 'deviceName': _deviceName(),
      }, ack: (dynamic responseRaw) async {
        final response = Map<String, dynamic>.from(responseRaw as Map);
        if (response['success'] == true) { s.dispose(); await _applyLinkedKeysAndFinish(name, response); return; }
        if (response['requiresApproval'] == true) {
          s.emitWithAck('login', {
            'userName': name, 'password': pass, 'publicKey': widget.publicKey,
            'deviceId': widget.deviceId, 'deviceName': _deviceName(),
          }, ack: (dynamic legacyRaw) async {
            final legacyResponse = Map<String, dynamic>.from(legacyRaw as Map);
            if (legacyResponse['success'] == true) { s.dispose(); await _applyLinkedKeysAndFinish(name, legacyResponse); return; }
            if (mounted) _showSnack('${t('Підтвердіть новий пристрій у вже авторизованому акаунті', 'Approve this device from your existing logged-in device')} (${response['code'] ?? '----'})');
            unawaited(_waitForDeviceApproval(s, (response['requestId'] ?? '').toString(), name));
          });
          return;
        }
        s.dispose();
        if (mounted) setState(() => isLoading = false);
        _showSnack((response['message'] ?? t('Помилка', 'Error')).toString(), isError: true);
      });
    });
    
    s.onError((dynamic error) {
      if (mounted) {
        setState(() => isLoading = false);
        _showSnack(t('Сервер недоступний. Спробуйте пізніше', 'Server unavailable. Try again later'), isError: true);
      }
      s.dispose();
    });
    
    s.onConnectError((dynamic error) {
      if (mounted) {
        setState(() => isLoading = false);
        _showSnack(t('Помилка підключення', 'Connection error'), isError: true);
      }
      s.dispose();
    });
    
    s.connect();
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
    
    io.Socket s = io.io(_serverUrl, {
      'transports': ['websocket'],
      'forceNew': true,
      'reconnection': false,
      'reconnectionDelay': 0,
    });
    
    // Set connection timeout
    final timeout = Future.delayed(const Duration(seconds: 30), () {
      if (mounted) {
        setState(() => isLoading = false);
        _showSnack(t('Помилка підключення до сервера', 'Connection timeout'), isError: true);
      }
      s.dispose();
    });
    
    s.onConnect((_) {
      s.emitWithAck('send_verification_email', {
        'userName': name, 'email': email, 'password': pass,
        'publicKey': widget.publicKey, 'deviceId': widget.deviceId, 'deviceName': _deviceName(),
      }, ack: (dynamic response) {
        timeout.ignore();
        s.dispose();
        if (mounted) {
          setState(() => isLoading = false);
          if (response['success'] == true) {
            _pendingEmail = email;
            setState(() => _step = 2);
          } else {
            _showSnack(response['message'] ?? t('Помилка', 'Error'), isError: true);
          }
        }
      });
    });
    
    s.onError((dynamic error) {
      timeout.ignore();
      if (mounted) {
        setState(() => isLoading = false);
        _showSnack(t('Сервер недоступний. Спробуйте пізніше', 'Server unavailable. Try again later'), isError: true);
      }
      s.dispose();
    });
    
    s.onConnectError((dynamic error) {
      timeout.ignore();
      if (mounted) {
        setState(() => isLoading = false);
        _showSnack(t('Помилка підключення', 'Connection error'), isError: true);
      }
      s.dispose();
    });
    
    s.connect();
  }

  void _verifyCode() async {
    final code = _codeController.text.trim();
    if (code.length != 6) return;
    setState(() => isLoading = true);
    
    io.Socket s = io.io(_serverUrl, {
      'transports': ['websocket'],
      'forceNew': true,
      'reconnection': false,
      'reconnectionDelay': 0,
    });
    
    // Set connection timeout
    final timeout = Future.delayed(const Duration(seconds: 30), () {
      if (mounted) {
        setState(() => isLoading = false);
        _showSnack(t('Помилка підключення до сервера', 'Connection timeout'), isError: true);
      }
      s.dispose();
    });
    
    s.onConnect((_) {
      s.emitWithAck('verify_email_code', {'email': _pendingEmail, 'code': code}, ack: (dynamic response) async {
        timeout.ignore();
        s.dispose();
        if (mounted) setState(() => isLoading = false);
        if (response['success'] == true) {
          final name = _nameController.text.trim();
          await (await SharedPreferences.getInstance()).setString('user_name', name);
          widget.onSuccess(name);
        } else {
          _showSnack(response['message'] ?? t('Невірний код', 'Invalid code'), isError: true);
        }
      });
    });
    
    s.onError((dynamic error) {
      timeout.ignore();
      if (mounted) {
        setState(() => isLoading = false);
        _showSnack(t('Сервер недоступний. Спробуйте пізніше', 'Server unavailable. Try again later'), isError: true);
      }
      s.dispose();
    });
    
    s.onConnectError((dynamic error) {
      timeout.ignore();
      if (mounted) {
        setState(() => isLoading = false);
        _showSnack(t('Помилка підключення', 'Connection error'), isError: true);
      }
      s.dispose();
    });
    
    s.connect();
  }

  void _restoreAccount() async {
    final token = _restoreTokenController.text.trim();
    final pass = _restorePasswordController.text.trim();
    if (token.isEmpty || pass.isEmpty) return;
    setState(() => isLoading = true);
    try {
      final parts = token.split('.');
      if (parts.length != 3) throw Exception("Invalid format");
      final nonce = base64Decode(parts[0]);
      final cipherText = base64Decode(parts[1]);
      final mac = base64Decode(parts[2]);
      final aes = AesGcm.with256bits();
      final passHash = await Sha256().hash(utf8.encode(pass));
      final key = await aes.newSecretKeyFromBytes(passHash.bytes);
      final box = SecretBox(cipherText, nonce: nonce, mac: Mac(mac));
      final decryptedBytes = await aes.decrypt(box, secretKey: key);
      final payload = jsonDecode(utf8.decode(decryptedBytes));
      final prefs = await SharedPreferences.getInstance();
      final storage = const FlutterSecureStorage();
      await storage.write(key: 'private_key', value: payload['priv']);
      await prefs.setString('public_key', payload['pub']);
      await prefs.setString('user_name', payload['name']);
      if (!mounted) return;
      _showSnack(t("Успішно відновлено!", "Restored successfully!"));
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const MainGate()), (route) => false);
      });
    } catch (e) {
      if (mounted) {
        setState(() => isLoading = false);
        _showSnack(t("Невірний токен або пароль", "Invalid token or password"), isError: true);
      }
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    final isDesktop = LumynTheme.isDesktop(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        msg,
        style: TextStyle(
          color: Colors.white,
          fontSize: isDesktop ? 13 : 14,
          fontFamily: 'Inter',
        ),
      ),
      backgroundColor: isError
          ? (isDesktop ? const Color(0xFF1A0000) : Colors.red.shade900)
          : (isDesktop ? const Color(0xFF0A0A0A) : const Color(0xFF1A1A2E)),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(isDesktop ? 8 : 14),
        side: isDesktop
            ? BorderSide(color: isError ? const Color(0xFF3A0000) : const Color(0xFF1A1A1A))
            : BorderSide.none,
      ),
      duration: const Duration(seconds: 3),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = LumynTheme.isDesktop(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: isDesktop ? _buildDesktopLayout() : _buildMobileLayout(),
    );
  }

  // ─── DESKTOP LAYOUT ──────────────────────────────────────
  Widget _buildDesktopLayout() {
    return Row(
      children: [
        // Left panel — branding
        Container(
          width: 380,
          decoration: const BoxDecoration(
            color: Color(0xFF050505),
            border: Border(right: BorderSide(color: Color(0xFF1A1A1A))),
          ),
          child: Stack(
            children: [
              // Grid
              const Positioned.fill(child: _DesktopGridBg()),
              // Content
              Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Logo
                    Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: Colors.black,
                            borderRadius: BorderRadius.circular(7),
                            border: Border.all(color: const Color(0xFF2A2A2A)),
                          ),
                          child: const Center(child: _LumynLogoMark(size: 14)),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'Lumyn',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Inter',
                            letterSpacing: -0.2,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    // Quote / tagline
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t('"Повністю зашифровано.\nПовністю приватно."', '"Fully encrypted.\nFully private."'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w500,
                            fontFamily: 'Inter',
                            letterSpacing: -0.5,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: Color(0xFF22C55E),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              t('End-to-end шифрування', 'End-to-end encrypted'),
                              style: const TextStyle(
                                color: Color(0xFF666666),
                                fontSize: 12,
                                fontFamily: 'Inter',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 40),
                    // Footer
                    Text(
                      'LUMYN Protocol · ${DateTime.now().year}',
                      style: const TextStyle(
                        color: Color(0xFF333333),
                        fontSize: 11,
                        fontFamily: 'Inter',
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Right panel — form
        Expanded(
          child: Center(
            child: SizedBox(
              width: 360,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween(begin: const Offset(0.03, 0), end: Offset.zero).animate(anim),
                    child: child,
                  ),
                ),
                child: _step == 3
                    ? _buildDesktopRestoreStep()
                    : _step == 2
                        ? _buildDesktopCodeStep()
                        : _step == 1
                            ? _buildDesktopRegisterStep()
                            : _buildDesktopLoginStep(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopLoginStep() {
    return Column(
      key: const ValueKey('desktop_login'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Sign in',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w600,
            fontFamily: 'Inter',
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          t('Введіть ваш нікнейм та пароль', 'Enter your username and password'),
          style: const TextStyle(color: Color(0xFF666666), fontSize: 13, fontFamily: 'Inter'),
        ),
        const SizedBox(height: 28),
        _dsLabel(t('Нікнейм', 'Username')),
        const SizedBox(height: 6),
        GlassInput(
          controller: _nameController,
          hintText: 'username',
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_.\-]'))],
        ),
        const SizedBox(height: 16),
        _dsLabel(t('Пароль', 'Password')),
        const SizedBox(height: 6),
        GlassInput(
          controller: _passController,
          hintText: '••••••••',
          obscureText: !_showLoginPassword,
          suffixIcon: IconButton(
            onPressed: () => setState(() => _showLoginPassword = !_showLoginPassword),
            icon: Icon(_showLoginPassword ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: const Color(0xFF666666), size: 18),
          ),
        ),
        const SizedBox(height: 24),
        ShineButton(text: t('Увійти', 'Sign in'), isLoading: isLoading, onPressed: _login),
        const SizedBox(height: 16),
        const _DsDivider(),
        const SizedBox(height: 16),
        Row(
          children: [
            GestureDetector(
              onTap: () => setState(() => _step = 1),
              child: Text(
                t("Немає акаунту? Зареєструватись", "No account? Register"),
                style: const TextStyle(color: Color(0xFF888888), fontSize: 13, fontFamily: 'Inter'),
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () => setState(() => _step = 3),
              child: Text(
                t("Відновити", "Restore"),
                style: const TextStyle(color: Color(0xFF888888), fontSize: 13, fontFamily: 'Inter'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDesktopRegisterStep() {
    return Column(
      key: const ValueKey('desktop_register'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Create account',
          style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w600, fontFamily: 'Inter', letterSpacing: -0.5),
        ),
        const SizedBox(height: 4),
        Text(
          t('Заповніть форму для реєстрації', 'Fill the form to get started'),
          style: const TextStyle(color: Color(0xFF666666), fontSize: 13, fontFamily: 'Inter'),
        ),
        const SizedBox(height: 28),
        _dsLabel(t('Нікнейм', 'Username')),
        const SizedBox(height: 6),
        GlassInput(controller: _nameController, hintText: 'username', inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_.\-]'))]),
        const SizedBox(height: 14),
        _dsLabel('Email'),
        const SizedBox(height: 6),
        GlassInput(controller: _emailController, hintText: 'you@example.com', keyboardType: TextInputType.emailAddress),
        const SizedBox(height: 14),
        _dsLabel(t('Пароль', 'Password')),
        const SizedBox(height: 6),
        GlassInput(
          controller: _passController,
          hintText: '••••••••',
          obscureText: !_showRegisterPassword,
          suffixIcon: IconButton(
            onPressed: () => setState(() => _showRegisterPassword = !_showRegisterPassword),
            icon: Icon(_showRegisterPassword ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: const Color(0xFF666666), size: 18),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          t('Код підтвердження буде відправлено на вказаний email', 'A verification code will be sent to your email'),
          style: const TextStyle(color: Color(0xFF444444), fontSize: 11, fontFamily: 'Inter'),
        ),
        const SizedBox(height: 24),
        ShineButton(text: t('Отримати код', 'Get code'), isLoading: isLoading, onPressed: _sendCode),
        const SizedBox(height: 16),
        const _DsDivider(),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: () => setState(() => _step = 0),
          child: Text(t('Вже є акаунт? Увійти', 'Already have an account? Sign in'), style: const TextStyle(color: Color(0xFF888888), fontSize: 13, fontFamily: 'Inter')),
        ),
      ],
    );
  }

  Widget _buildDesktopCodeStep() {
    return Column(
      key: const ValueKey('desktop_code'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFF0A0A0A),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF1A1A1A)),
          ),
          child: const Center(child: Icon(Icons.mail_outline_rounded, color: Colors.white, size: 20)),
        ),
        const SizedBox(height: 20),
        const Text('Check your email', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w600, fontFamily: 'Inter', letterSpacing: -0.5)),
        const SizedBox(height: 4),
        RichText(
          text: TextSpan(
            style: const TextStyle(color: Color(0xFF666666), fontSize: 13, fontFamily: 'Inter'),
            children: [
              TextSpan(text: t('Код відправлено на ', 'Code sent to ')),
              TextSpan(text: _pendingEmail ?? '', style: const TextStyle(color: Colors.white)),
            ],
          ),
        ),
        const SizedBox(height: 28),
        _dsLabel(t('6-значний код', '6-digit code')),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0A0A0A),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF1A1A1A)),
          ),
          child: TextField(
            controller: _codeController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w600, letterSpacing: 12, fontFamily: 'Inter'),
            decoration: InputDecoration(
              hintText: '000000',
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.15), fontSize: 28, letterSpacing: 12),
              border: InputBorder.none,
              counterText: '',
              contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            ),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
        ),
        const SizedBox(height: 24),
        ShineButton(text: t('Підтвердити', 'Verify'), isLoading: isLoading, onPressed: _verifyCode),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: () => setState(() { _step = 1; _codeController.clear(); }),
          child: Text(t('← Назад', '← Back'), style: const TextStyle(color: Color(0xFF666666), fontSize: 13, fontFamily: 'Inter')),
        ),
      ],
    );
  }

  Widget _buildDesktopRestoreStep() {
    return Column(
      key: const ValueKey('desktop_restore'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Restore account', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w600, fontFamily: 'Inter', letterSpacing: -0.5)),
        const SizedBox(height: 4),
        Text(
          t('Введіть токен та пароль дешифрування', 'Enter your backup token and decryption password'),
          style: const TextStyle(color: Color(0xFF666666), fontSize: 13, fontFamily: 'Inter'),
        ),
        const SizedBox(height: 28),
        _dsLabel('Backup Token'),
        const SizedBox(height: 6),
        GlassInput(controller: _restoreTokenController, hintText: 'xxxx.xxxx.xxxx'),
        const SizedBox(height: 14),
        _dsLabel(t('Пароль дешифрування', 'Decryption password')),
        const SizedBox(height: 6),
        GlassInput(
          controller: _restorePasswordController,
          hintText: '••••••••',
          obscureText: !_showRestorePassword,
          suffixIcon: IconButton(
            onPressed: () => setState(() => _showRestorePassword = !_showRestorePassword),
            icon: Icon(_showRestorePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: const Color(0xFF666666), size: 18),
          ),
        ),
        const SizedBox(height: 24),
        ShineButton(text: t('Відновити', 'Restore'), isLoading: isLoading, onPressed: _restoreAccount),
        const SizedBox(height: 16),
        const _DsDivider(),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: () => setState(() { _step = 0; _restoreTokenController.clear(); _restorePasswordController.clear(); }),
          child: Text(t('← До входу', '← Back to sign in'), style: const TextStyle(color: Color(0xFF666666), fontSize: 13, fontFamily: 'Inter')),
        ),
      ],
    );
  }

  Widget _dsLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF888888),
        fontSize: 12,
        fontWeight: FontWeight.w500,
        fontFamily: 'Inter',
      ),
    );
  }

  // ─── MOBILE LAYOUT ──────────────────────────────────────
  Widget _buildMobileLayout() {
    return LiquidBackground(
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 30),
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 350),
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween(begin: const Offset(0.05, 0), end: Offset.zero).animate(anim),
                          child: child,
                        ),
                      ),
                      child: _step == 3
                          ? _buildRestoreStep()
                          : _step == 2
                              ? _buildCodeStep()
                              : _step == 1
                                  ? _buildRegisterStep()
                                  : _buildLoginStep(),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildLoginStep() {
    return Column(
      key: const ValueKey('login'),
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 60),
        Text(t("З поверненням.", "Welcome back."), style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: -1, color: Colors.white)),
        const SizedBox(height: 8),
        const Text("LUMYN Protocol", style: TextStyle(fontSize: 16, color: Colors.white70)),
        const SizedBox(height: 48),
        GlassInput(controller: _nameController, hintText: t("Нікнейм", "Username"), inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_.\-]'))]),
        const SizedBox(height: 16),
        GlassInput(
          controller: _passController,
          hintText: t("Пароль", "Password"),
          obscureText: !_showLoginPassword,
          suffixIcon: IconButton(
            onPressed: () => setState(() => _showLoginPassword = !_showLoginPassword),
            icon: Icon(_showLoginPassword ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: Colors.white70, size: 20),
          ),
        ),
        const SizedBox(height: 32),
        ShineButton(text: t("Увійти", "Sign In"), isLoading: isLoading, onPressed: _login),
        const SizedBox(height: 24),
        GestureDetector(
          onTap: () => setState(() => _step = 1),
          child: Text(t("Немає акаунту? Створити", "Don't have an account? Register"), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w500)),
        ),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: () => setState(() => _step = 3),
          child: Text(t("Відновити з копії", "Restore from backup"), textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFB026FF), fontSize: 14, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(height: 60),
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
        const Text("LUMYN Protocol", style: TextStyle(fontSize: 16, color: Colors.white70)),
        const SizedBox(height: 48),
        GlassInput(controller: _nameController, hintText: t("Нікнейм", "Username"), inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_.\-]'))]),
        const SizedBox(height: 16),
        GlassInput(controller: _emailController, hintText: t("Email адреса", "Email address"), keyboardType: TextInputType.emailAddress),
        const SizedBox(height: 16),
        GlassInput(
          controller: _passController,
          hintText: t("Пароль", "Password"),
          obscureText: !_showRegisterPassword,
          suffixIcon: IconButton(
            onPressed: () => setState(() => _showRegisterPassword = !_showRegisterPassword),
            icon: Icon(_showRegisterPassword ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: Colors.white70, size: 20),
          ),
        ),
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

  Widget _buildRestoreStep() {
    return Column(
      key: const ValueKey('restore'),
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.restore, color: Color(0xFFB026FF), size: 48),
        const SizedBox(height: 24),
        Text(t("Відновлення.", "Restore."), style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: -1, color: Colors.white)),
        const SizedBox(height: 8),
        Text(t("Введіть ваш токен та пароль дешифрування.", "Enter your Backup Token and decryption password."), style: const TextStyle(color: Colors.white70, fontSize: 14)),
        const SizedBox(height: 48),
        GlassInput(controller: _restoreTokenController, hintText: t("Backup Token", "Backup Token")),
        const SizedBox(height: 16),
        GlassInput(
          controller: _restorePasswordController,
          hintText: t("Пароль", "Password"),
          obscureText: !_showRestorePassword,
          suffixIcon: IconButton(
            onPressed: () => setState(() => _showRestorePassword = !_showRestorePassword),
            icon: Icon(_showRestorePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: Colors.white70, size: 20),
          ),
        ),
        const SizedBox(height: 32),
        ShineButton(text: t("Відновити", "Restore"), isLoading: isLoading, onPressed: _restoreAccount),
        const SizedBox(height: 24),
        GestureDetector(
          onTap: () => setState(() { _step = 0; _restoreTokenController.clear(); _restorePasswordController.clear(); }),
          child: Text(t("← Повернутися до входу", "← Back to login"), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────
// DESKTOP HELPERS
// ─────────────────────────────────────────────────────────
class _DsDivider extends StatelessWidget {
  const _DsDivider();
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Container(height: 1, color: const Color(0xFF1A1A1A))),
      ],
    );
  }
}

class _DesktopGridBg extends StatelessWidget {
  const _DesktopGridBg();
  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _DesktopGridPainter());
  }
}

class _DesktopGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.03)
      ..strokeWidth = 0.5;
    const step = 32.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _LumynLogoMark extends StatelessWidget {
  final double size;
  const _LumynLogoMark({this.size = 14});
  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size(size, size), painter: _LogoPainter());
  }
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width * 0.42;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = Colors.white
      ..strokeWidth = size.width * 0.12;
    final path = Path();
    path.moveTo(cx - r * 0.55, cy - r * 0.55);
    path.lineTo(cx - r * 0.55, cy + r * 0.55);
    path.lineTo(cx + r * 0.55, cy + r * 0.55);
    canvas.drawPath(path, paint);
    canvas.drawCircle(Offset(cx + r * 0.55, cy - r * 0.1), size.width * 0.07, Paint()..color = const Color(0xFFB026FF));
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}