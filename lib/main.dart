import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui'; 
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart'; // ДЛЯ ЛІНКІВ
import 'package:url_launcher/url_launcher.dart'; // ДЛЯ ЛІНКІВ
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:uuid/uuid.dart';
import 'package:cryptography/cryptography.dart';
import 'package:image_picker/image_picker.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

String? currentActiveChat;

String lang = 'uk';
String t(String uk, String en) => lang == 'uk' ? uk : en;

const String kAdminUsername = 'den';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light, 
  ));
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Aether',
      theme: ThemeData(
        scaffoldBackgroundColor: Colors.black, 
        fontFamily: 'Inter', 
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        colorScheme: const ColorScheme.dark(
          primary: Colors.white,
          secondary: Color(0xFF888888),
          surface: Colors.transparent,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          iconTheme: IconThemeData(color: Colors.white),
          titleTextStyle: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
      home: const MainGate(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ДИЗАЙН & БАЗОВІ ВІДЖЕТИ
// ─────────────────────────────────────────────────────────────────────────────

class LiquidBackground extends StatelessWidget {
  final Widget child;
  final Color accentColor;
  const LiquidBackground({super.key, required this.child, this.accentColor = const Color(0xFF1E1E2C)});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(seconds: 1),
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(-0.8, -0.5),
          radius: 1.5,
          colors: [accentColor, Colors.black],
        ),
      ),
      child: child,
    );
  }
}

class GlassContainer extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;
  final Color? color;

  const GlassContainer({super.key, required this.child, this.borderRadius = 20, this.padding, this.margin, this.width, this.height, this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width, height: height, margin: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: (color ?? Colors.white).withValues(alpha: 0.08),
              border: Border.all(color: (color ?? Colors.white).withValues(alpha: 0.18), width: 1.5),
              borderRadius: BorderRadius.circular(borderRadius),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 32, offset: const Offset(0, 8))],
            ),
            child: Stack(
              children: [
                Positioned(top: 0, left: 0, right: 0,
                  child: Container(
                    height: 32,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter, end: Alignment.bottomCenter,
                        colors: [Colors.white.withValues(alpha: 0.12), Colors.transparent],
                      ),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(borderRadius)),
                    ),
                  ),
                ),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class VerifiedBadge extends StatelessWidget {
  final double size;
  const VerifiedBadge({super.key, this.size = 14});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(colors: [Color(0xFF1DA1F2), Color(0xFF0066CC)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        boxShadow: [BoxShadow(color: const Color(0xFF1DA1F2).withValues(alpha: 0.5), blurRadius: 6)],
      ),
      child: Icon(Icons.check, color: Colors.white, size: size * 0.65),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ШЛЮЗ & АВТОРИЗАЦІЯ
// ─────────────────────────────────────────────────────────────────────────────
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
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator(color: Colors.white)));
    if (_userName == null) return AuthScreen(deviceId: _deviceId!, publicKey: _publicKey!, onSuccess: (name) { setState(() { _userName = name; }); });
    return ContactsScreen(deviceId: _deviceId!, userName: _userName!, publicKey: _publicKey!);
  }
}

class AuthScreen extends StatefulWidget {
  final String deviceId, publicKey;
  final Function(String) onSuccess;
  const AuthScreen({super.key, required this.deviceId, required this.publicKey, required this.onSuccess});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
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
    setState(() => isLoading = true);
    io.Socket s = io.io('https://aether-backend-hrmq.onrender.com', {'transports': ['websocket'], 'forceNew': true});
    s.connect();
    s.onConnect((_) {
      s.emitWithAck('send_verification_email', {'userName': name, 'email': email, 'password': pass, 'publicKey': widget.publicKey}, ack: (dynamic response) {
        s.dispose();
        setState(() => isLoading = false);
        if (response['success'] == true) { _pendingEmail = email; setState(() => _step = 2); } else { _showSnack(response['message'] ?? t('Помилка', 'Error'), isError: true); }
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
        } else { _showSnack(response['message'] ?? t('Невірний код', 'Invalid code'), isError: true); }
      });
    });
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg, style: const TextStyle(color: Colors.white)), backgroundColor: isError ? Colors.red.shade900 : const Color(0xFF333333), behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50))));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: LiquidBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30),
            child: AnimatedSwitcher(duration: const Duration(milliseconds: 350), child: _step == 2 ? _buildCodeStep() : (_step == 1 ? _buildRegisterStep() : _buildLoginStep())),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginStep() {
    return Column(
      key: const ValueKey('login'), mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t("З поверненням.", "Welcome back."), style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: -1, color: Colors.white)),
        const SizedBox(height: 8), const Text("Aether Core Protocol", style: TextStyle(fontSize: 16, color: Colors.white70)), const SizedBox(height: 48),
        _GlassInput(controller: _nameController, hintText: t("Нікнейм", "Username")), const SizedBox(height: 16),
        _GlassInput(controller: _passController, hintText: t("Пароль", "Password"), obscureText: true), const SizedBox(height: 32),
        _ShineButton(text: t("Увійти", "Sign In"), isLoading: isLoading, onPressed: _login), const SizedBox(height: 24),
        GestureDetector(onTap: () => setState(() => _step = 1), child: Text(t("Немає акаунту? Створити", "Don't have an account? Register"), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 14))),
      ],
    );
  }

  Widget _buildRegisterStep() {
    return Column(
      key: const ValueKey('reg'), mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t("Створити акаунт.", "Create account."), style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: -1, color: Colors.white)),
        const SizedBox(height: 48),
        _GlassInput(controller: _nameController, hintText: t("Нікнейм", "Username")), const SizedBox(height: 16),
        _GlassInput(controller: _emailController, hintText: t("Email адреса", "Email")), const SizedBox(height: 16),
        _GlassInput(controller: _passController, hintText: t("Пароль", "Password"), obscureText: true), const SizedBox(height: 24),
        _ShineButton(text: t("Отримати код", "Get Code"), isLoading: isLoading, onPressed: _sendCode), const SizedBox(height: 24),
        GestureDetector(onTap: () => setState(() => _step = 0), child: Text(t("Вже є акаунт? Увійти", "Already have an account? Sign In"), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 14))),
      ],
    );
  }

  Widget _buildCodeStep() {
    return Column(
      key: const ValueKey('code'), mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t("Перевір пошту.", "Check your email."), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: Colors.white)),
        const SizedBox(height: 8), Text(_pendingEmail ?? '', style: const TextStyle(color: Colors.white, fontSize: 14)), const SizedBox(height: 48),
        _GlassInput(controller: _codeController, hintText: "000000", keyboardType: TextInputType.number), const SizedBox(height: 32),
        _ShineButton(text: t("Підтвердити", "Verify"), isLoading: isLoading, onPressed: _verifyCode),
      ],
    );
  }
}

// Мінімалістичні версії інпутів для авторизації
class _GlassInput extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final bool obscureText;
  final TextInputType? keyboardType;
  const _GlassInput({required this.controller, required this.hintText, this.obscureText = false, this.keyboardType});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withValues(alpha: 0.1))),
      child: TextField(controller: controller, obscureText: obscureText, keyboardType: keyboardType, style: const TextStyle(color: Colors.white), decoration: InputDecoration(hintText: hintText, hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)), border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18))),
    );
  }
}
class _ShineButton extends StatelessWidget {
  final String text; final VoidCallback onPressed; final bool isLoading;
  const _ShineButton({required this.text, required this.onPressed, required this.isLoading});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onPressed,
      child: Container(
        height: 54, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(50), border: Border.all(color: Colors.white.withValues(alpha: 0.2))),
        child: Center(child: isLoading ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : Text(text, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ГОЛОВНИЙ ЕКРАН КОНТАКТІВ
// ─────────────────────────────────────────────────────────────────────────────
class ContactsScreen extends StatefulWidget {
  final String deviceId, userName, publicKey;
  const ContactsScreen({super.key, required this.deviceId, required this.userName, required this.publicKey});
  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  int _currentIndex = 0;
  late io.Socket _bgSocket;
  final AudioPlayer _audioPlayer = AudioPlayer();
  List<Map<String, dynamic>> _recentChats = [], _friends = [], _pendingRequests = [];
  String? _myAvatar;
  String _myBio = "";
  bool _myVerified = false;

  @override
  void initState() {
    super.initState();
    _bgSocket = io.io('https://aether-backend-hrmq.onrender.com', {'transports': ['websocket'], 'forceNew': true});
    _bgSocket.connect();
    _bgSocket.onConnect((_) { _bgSocket.emit('set_active', widget.userName); _loadData(); });
    _bgSocket.on('message', (data) { _loadData(); });
    _bgSocket.on('refresh_chats', (data) { _loadData(); });
    _bgSocket.on('friends_data', (data) {
      if (mounted) setState(() { _myAvatar = data['myAvatar']; _myBio = data['myBio'] ?? ""; _myVerified = data['myVerified'] == true; _friends = List<Map<String, dynamic>>.from(data['friends']); _pendingRequests = List<Map<String, dynamic>>.from(data['pending']); });
    });
  }

  void _loadData() {
    _bgSocket.emitWithAck('get_recent_chats', widget.userName, ack: (dynamic data) {
      if (mounted) setState(() { _recentChats = List<Map<String, dynamic>>.from(data)..removeWhere((c) => c['isHidden'] == true); });
    });
    _bgSocket.emit('get_friends_data', widget.userName);
  }

  void _openChatScreen(String targetName, String targetKey, {String? avatar, bool isVerified = false}) {
    Navigator.push(context, MaterialPageRoute(builder: (context) => ChatScreen(deviceId: widget.deviceId, userName: widget.userName, myPublicKey: widget.publicKey, partnerName: targetName, partnerPublicKey: targetKey, partnerAvatar: avatar, partnerIsVerified: isVerified, friends: _friends))).then((_) => _loadData());
  }

  @override
  void dispose() { _bgSocket.dispose(); _audioPlayer.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: Text(t("Чати", "Chats")), flexibleSpace: ClipRect(child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20), child: Container(color: Colors.black.withValues(alpha: 0.5))))),
      body: LiquidBackground(
        child: ListView.separated(
          padding: const EdgeInsets.only(top: 20, bottom: 100), itemCount: _recentChats.length,
          separatorBuilder: (c, i) => Divider(height: 1, color: Colors.white.withValues(alpha: 0.05), indent: 76),
          itemBuilder: (context, index) {
            final chat = _recentChats[index];
            final isSelf = chat['partnerName'] == widget.userName;
            return ListTile(
              leading: CircleAvatar(radius: 24, backgroundColor: Colors.white.withValues(alpha: 0.1), backgroundImage: chat['avatar'] != null ? MemoryImage(base64Decode(chat['avatar'])) : null, child: chat['avatar'] == null ? Text(chat['partnerName'][0].toUpperCase(), style: const TextStyle(color: Colors.white)) : null),
              title: Text(isSelf ? t("Нотатник", "Saved Messages") : chat['partnerName'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              subtitle: Text(chat['lastMessage']?['type'] == 'image' ? 'Фото' : (chat['lastMessage']?['type'] == 'audio' ? 'Голосове' : 'Повідомлення'), style: TextStyle(color: Colors.white.withValues(alpha: 0.5)), maxLines: 1),
              onTap: () => _openChatScreen(chat['partnerName'], chat['publicKey'], avatar: chat['avatar'], isVerified: chat['isVerified'] == true),
            );
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ЧАТ ЕКРАН (З фіксами лінків, аудіо та лагів)
// ─────────────────────────────────────────────────────────────────────────────
class ChatScreen extends StatefulWidget {
  final String deviceId, userName, myPublicKey, partnerName, partnerPublicKey;
  final String? partnerAvatar;
  final bool partnerIsVerified;
  final List<Map<String, dynamic>> friends;

  const ChatScreen({
    super.key, required this.deviceId, required this.userName, required this.myPublicKey,
    required this.partnerName, required this.partnerPublicKey, this.partnerAvatar,
    this.partnerIsVerified = false, this.friends = const [],
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late io.Socket socket;
  final List<Map<String, dynamic>> _messages = [];
  final TextEditingController _c = TextEditingController();
  final AesGcm _aes = AesGcm.with256bits();
  final _storage = const FlutterSecureStorage();
  final ImagePicker _picker = ImagePicker();
  final AudioRecorder _audioRecorder = AudioRecorder();
  final ScrollController _scrollController = ScrollController();

  bool _isRecordingAudio = false;
  late String _currentPartnerKey;

  @override
  void initState() {
    super.initState();
    _currentPartnerKey = widget.partnerPublicKey;
    currentActiveChat = widget.partnerPublicKey.startsWith('GROUP_') ? widget.partnerPublicKey : widget.partnerName;
    _connect();
  }

  Future<SecretKey> _getSecretKey(String remotePub) async {
    final priv = await _storage.read(key: 'private_key');
    final secret = await X25519().sharedSecretKey(keyPair: SimpleKeyPairData(base64Decode(priv!), publicKey: SimplePublicKey(base64Decode(widget.myPublicKey), type: KeyPairType.x25519), type: KeyPairType.x25519), remotePublicKey: SimplePublicKey(base64Decode(remotePub), type: KeyPairType.x25519));
    return await _aes.newSecretKeyFromBytes(await secret.extractBytes());
  }

  // ФІКС 1: ЗАПИС АУДІО НА WEB/IOS
  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final dir = await getApplicationDocumentsDirectory();
        final path = '${dir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
        // Safari PWA любить AAC в m4a контейнері
        await _audioRecorder.start(const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000, sampleRate: 44100), path: path);
        setState(() => _isRecordingAudio = true);
      }
    } catch (e) { debugPrint("Recording error: $e"); }
  }

  Future<void> _stopRecording() async {
    try {
      final path = await _audioRecorder.stop();
      setState(() => _isRecordingAudio = false);
      if (path != null) { final bytes = await File(path).readAsBytes(); _send(textOverride: base64Encode(bytes), type: 'audio'); }
    } catch (e) { debugPrint(e.toString()); }
  }

  // ФІКС 2: ІДЕАЛЬНЕ ВІДПРАВЛЕННЯ ФОТО БЕЗ КРОПЕРА
  Future<void> _pickAndSendImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, maxWidth: 1600, maxHeight: 1600, imageQuality: 80);
    if (image == null || !context.mounted) return;
    
    final bytes = await image.readAsBytes();
    final base64Image = base64Encode(bytes);
    final captionController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: GlassContainer(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.memory(bytes, height: 300, fit: BoxFit.contain)),
              const SizedBox(height: 16),
              TextField(controller: captionController, style: const TextStyle(color: Colors.white), decoration: InputDecoration(hintText: t("Підпис...", "Caption..."), hintStyle: const TextStyle(color: Colors.white54), border: InputBorder.none)),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Скасувати", style: TextStyle(color: Colors.white54))),
                  TextButton(onPressed: () { Navigator.pop(ctx); _sendWithImage(captionController.text.trim(), base64Image); }, child: const Text("Відправити", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                ],
              )
            ],
          ),
        ),
      )
    );
  }

  void _sendWithImage(String caption, String base64Image) async {
    final key = await _getSecretKey(_currentPartnerKey);
    String payloadStr = jsonEncode({'text': caption, 'imageBytes': base64Image});
    final box = await _aes.encrypt(utf8.encode(payloadStr), secretKey: key);
    socket.emit('message', {'type': 'image', 'text': 'encrypted_payload', 'ciphertext': base64Encode(box.cipherText), 'nonce': base64Encode(box.nonce), 'mac': base64Encode(box.mac.bytes), 'senderName': widget.userName, 'receiverName': widget.partnerName});
  }

  void _send({String? textOverride, String type = 'text'}) async {
    final text = textOverride ?? _c.text.trim();
    if (text.isEmpty && type == 'text') return;
    if (type == 'text') _c.clear();
    final key = await _getSecretKey(_currentPartnerKey);
    final box = await _aes.encrypt(utf8.encode(text), secretKey: key);
    socket.emit('message', {'type': type, 'text': text, 'ciphertext': base64Encode(box.cipherText), 'nonce': base64Encode(box.nonce), 'mac': base64Encode(box.mac.bytes), 'senderName': widget.userName, 'receiverName': widget.partnerName});
  }

  void _connect() {
    socket = io.io('https://aether-backend-hrmq.onrender.com', {'transports': ['websocket'], 'forceNew': true});
    socket.connect();
    socket.onConnect((_) {
      socket.emitWithAck('get_direct_history', {'me': widget.userName, 'partner': widget.partnerName}, ack: (dynamic data) async {
        List<Map<String, dynamic>> temp = [];
        for (var m in (data as List)) {
          var msgMap = Map<String, dynamic>.from(m);
          if (msgMap['ciphertext'] != null) {
            try {
              final key = await _getSecretKey(msgMap['senderName'] == widget.partnerName ? (msgMap['publicKey'] ?? _currentPartnerKey) : _currentPartnerKey);
              final box = SecretBox(base64Decode(msgMap['ciphertext']), nonce: base64Decode(msgMap['nonce']), mac: Mac(base64Decode(msgMap['mac'])));
              String dec = utf8.decode(await _aes.decrypt(box, secretKey: key));
              if (dec.startsWith('{')) { final p = jsonDecode(dec); msgMap['text'] = p['text']; msgMap['imageBytes'] = p['imageBytes'] != null ? base64Decode(p['imageBytes']) : null; } else { msgMap['text'] = dec; }
            } catch (e) { msgMap['text'] = "Encrypted"; }
          }
          temp.add(msgMap);
        }
        if (mounted) setState(() { _messages.addAll(temp); });
        WidgetsBinding.instance.addPostFrameCallback((_) { if (_scrollController.hasClients) _scrollController.jumpTo(_scrollController.position.maxScrollExtent); });
      });
    });

    socket.on('message', (data) async {
      var msg = Map<String, dynamic>.from(data);
      if ((msg['senderName'] == widget.userName && msg['receiverName'] == widget.partnerName) || (msg['senderName'] == widget.partnerName && msg['receiverName'] == widget.userName)) {
        if (msg['ciphertext'] != null) {
          try {
            final key = await _getSecretKey(msg['senderName'] == widget.partnerName ? (msg['publicKey'] ?? _currentPartnerKey) : _currentPartnerKey);
            final box = SecretBox(base64Decode(msg['ciphertext']), nonce: base64Decode(msg['nonce']), mac: Mac(base64Decode(msg['mac'])));
            String dec = utf8.decode(await _aes.decrypt(box, secretKey: key));
            if (dec.startsWith('{')) { final p = jsonDecode(dec); msg['text'] = p['text']; msg['imageBytes'] = p['imageBytes'] != null ? base64Decode(p['imageBytes']) : null; } else { msg['text'] = dec; }
          } catch (e) { msg['text'] = "Encrypted"; }
        }
        if (mounted) setState(() => _messages.add(msg));
        WidgetsBinding.instance.addPostFrameCallback((_) { if (_scrollController.hasClients) _scrollController.animateTo(_scrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut); });
      }
    });
  }

  @override
  void dispose() { socket.dispose(); super.dispose(); }

  // ФІКС 3: ПАРСЕР ЛІНКІВ (Робить посилання клікабельними)
  Widget _buildMessageText(String text) {
    final urlRegExp = RegExp(r'(https?:\/\/[^\s]+)');
    final matches = urlRegExp.allMatches(text);
    if (matches.isEmpty) return Text(text, style: const TextStyle(color: Colors.white, fontSize: 15));

    List<TextSpan> spans = [];
    int lastMatchEnd = 0;
    for (var match in matches) {
      if (match.start > lastMatchEnd) spans.add(TextSpan(text: text.substring(lastMatchEnd, match.start)));
      final url = match.group(0)!;
      spans.add(TextSpan(
        text: url,
        style: const TextStyle(color: Color(0xFF00C7FF), decoration: TextDecoration.underline),
        recognizer: TapGestureRecognizer()..onTap = () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      ));
      lastMatchEnd = match.end;
    }
    if (lastMatchEnd < text.length) spans.add(TextSpan(text: text.substring(lastMatchEnd)));
    return RichText(text: TextSpan(style: const TextStyle(color: Colors.white, fontSize: 15), children: spans));
  }

  // ФІКС 4: АНТИ-ЛАГ ДЛЯ ФОТО (cacheWidth)
  Widget _buildImage(dynamic bytesOrString) {
    Uint8List bytes = bytesOrString is Uint8List ? bytesOrString : base64Decode(bytesOrString);
    return Image.memory(
      bytes, 
      fit: BoxFit.cover, 
      gaplessPlayback: true,
      cacheWidth: 800, // ФІКС ЛАГІВ ПРИ СКРОЛІ
      errorBuilder: (ctx, err, stack) => const Icon(Icons.broken_image, color: Colors.white70)
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: Text(widget.partnerName), flexibleSpace: ClipRect(child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20), child: Container(color: Colors.black.withValues(alpha: 0.5))))),
      body: LiquidBackground(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(12),
                itemCount: _messages.length,
                itemBuilder: (context, i) {
                  final m = _messages[i];
                  final isMe = m['senderName'] == widget.userName;
                  return Align(
                    alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(color: isMe ? Colors.white.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(20)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (m['type'] == 'image') ClipRRect(borderRadius: BorderRadius.circular(12), child: _buildImage(m['imageBytes'] ?? m['text'])),
                          if (m['type'] == 'audio') const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.mic, color: Colors.white), SizedBox(width: 8), Text("Голосове повідомлення", style: TextStyle(color: Colors.white))]),
                          if (m['type'] == 'text' || (m['type'] == 'image' && m['text'] != 'encrypted_payload' && m['text'] != null && m['text'].toString().isNotEmpty)) 
                            Padding(padding: EdgeInsets.only(top: m['type'] == 'image' ? 8.0 : 0), child: _buildMessageText(m['text'] ?? '')),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 16, 24),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.1)))),
                child: Row(children: [
                  GestureDetector(onTap: _pickAndSendImage, child: const Icon(Icons.add, color: Colors.white, size: 26)),
                  const SizedBox(width: 8),
                  Expanded(child: Container(padding: const EdgeInsets.symmetric(horizontal: 14), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(20)), child: TextField(controller: _c, style: const TextStyle(color: Colors.white), decoration: InputDecoration(hintText: t("Повідомлення...", "Message..."), hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)), border: InputBorder.none)))),
                  const SizedBox(width: 8),
                  GestureDetector(onTap: _send, onLongPress: _startRecording, onLongPressUp: _stopRecording, child: Container(height: 44, width: 44, decoration: BoxDecoration(color: _isRecordingAudio ? Colors.red : Colors.white, shape: BoxShape.circle), child: Icon(_isRecordingAudio ? Icons.mic : Icons.arrow_upward, color: _isRecordingAudio ? Colors.white : Colors.black))),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}