import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cryptography/cryptography.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:audioplayers/audioplayers.dart';
import '../utils/globals.dart';
import '../widgets/ui_core.dart';
import 'chat_screen.dart';
import 'dart:math' show pi;
import 'main_gate.dart';

// ─────────────────────────────────────────────────────────
// КАСТОМНА ІКОНКА ЗАМКА (APPLE STYLE)
// ─────────────────────────────────────────────────────────
class _AppleLockIcon extends StatelessWidget {
  const _AppleLockIcon();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      height: 72,
      child: CustomPaint(painter: _LockPainter()),
    );
  }
}

class _LockPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Glow
    canvas.drawCircle(
      Offset(cx, cy), 32,
      Paint()
        ..color = const Color(0xFFB026FF).withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );

    // Фон кола
    canvas.drawCircle(
      Offset(cx, cy), 32,
      Paint()..color = Colors.white.withValues(alpha: 0.07),
    );

    // Обводка
    canvas.drawCircle(
      Offset(cx, cy), 31.5,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    // Тіло замка
    const bw = 18.0;
    const bh = 12.0;
    final bx = cx - bw / 2;
    final by = cy + 3.0;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(bx, by, bw, bh), const Radius.circular(4)),
      Paint()..color = Colors.white,
    );

    // Дужка
    final arcPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;
    final arcRect = Rect.fromCenter(center: Offset(cx, by + 0.5), width: 11, height: 12);
    canvas.drawArc(arcRect, pi, pi, false, arcPaint);

    // Отвір — кружечок
    canvas.drawCircle(
      Offset(cx, by + bh * 0.42),
      2.2,
      Paint()..color = const Color(0xFF0A0A0A),
    );

    // Отвір — лінія вниз
    canvas.drawLine(
      Offset(cx, by + bh * 0.42 + 2.2),
      Offset(cx, by + bh * 0.42 + 5.0),
      Paint()
        ..color = const Color(0xFF0A0A0A)
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─────────────────────────────────────────────────────────
// MAIN SCREEN
// ─────────────────────────────────────────────────────────
class ContactsScreen extends StatefulWidget {
  final String deviceId, userName, publicKey;
  const ContactsScreen({
    super.key,
    required this.deviceId,
    required this.userName,
    required this.publicKey,
  });

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;
  late io.Socket _bgSocket;
  final AudioPlayer _audioPlayer = AudioPlayer();
  final ImagePicker _picker = ImagePicker();
  final AesGcm _aes = AesGcm.with256bits();
  bool _isSearching = false;

  List<Map<String, dynamic>> _recentChats = [];
  List<Map<String, dynamic>> _friends = [];
  List<Map<String, dynamic>> _pendingRequests = [];
  String? _myAvatar;
  String _myBio = "";
  bool _myVerified = false;
  bool get _isAdmin => widget.userName == kAdminUsername;

  final _addFriendController = TextEditingController();
  final _searchController = TextEditingController();
  final _verifySearchController = TextEditingController();
  List<Map<String, dynamic>> _verifyResults = [];

  // --- PIN-LOCK ---
  bool _isAppLocked = false;
  String? _savedPin;
  String _enteredPin = '';
  bool _isSettingPin = false;
  String _tempNewPin = '';

  // --- НАЛАШТУВАННЯ ---
  bool _notificationsEnabled = true;
  bool _soundEnabled = true;
  bool _vibrationEnabled = true;
  bool _messagePreview = true;
  bool _readReceipts = true;
  bool _onlineStatus = true;
  bool _typingIndicator = true;
  String _accentColor = 'purple';
  double _chatFontSize = 14.0;
  String _chatBubbleStyle = 'rounded';
  bool _compactMode = false;

  static const _accentColors = {
    'purple': Color(0xFFB026FF),
    'blue':   Color(0xFF007AFF),
    'green':  Color(0xFF34C759),
    'orange': Color(0xFFFF9500),
  };

  // ─────────────────────────────────────────────────────────
  // INIT / DISPOSE
  // ─────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initLockState();
    _loadSettings();

    _bgSocket = io.io('https://aether-backend-hrmq.onrender.com', {
      'transports': ['websocket'],
      'forceNew': true,
    });
    _bgSocket.connect();
    _bgSocket.onConnect((_) {
      _bgSocket.emit('set_active', widget.userName);
      _loadData();
    });

    _bgSocket.on('message', (data) {
      var msg = Map<String, dynamic>.from(data);
      if (msg['receiverName'] == widget.userName ||
          (msg['receiverName'].toString().startsWith('GROUP_') &&
              msg['senderName'] != widget.userName)) {
        if (currentActiveChat != msg['senderName'] &&
            currentActiveChat != msg['receiverName']) {
          _audioPlayer.play(AssetSource('ding.mp3'));
        }
        _loadData();
      }
    });

    _bgSocket.on('refresh_chats', (data) {
      if (data['userName'] == widget.userName || data['userName'] == 'all') _loadData();
    });

    _bgSocket.on('messages_read', (data) { _loadData(); });

    _bgSocket.on('friends_data', (data) {
      if (mounted) {
        setState(() {
          _myAvatar = data['myAvatar'];
          _myBio = data['myBio'] ?? "";
          _myVerified = data['myVerified'] == true;
          _friends = List<Map<String, dynamic>>.from(data['friends']);
          _pendingRequests = List<Map<String, dynamic>>.from(data['pending']);
        });
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    currentActiveChat = null;
    _bgSocket.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────
  // SETTINGS PERSISTENCE
  // ─────────────────────────────────────────────────────────
  Future<void> _loadSettings() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _notificationsEnabled = p.getBool('notif_enabled') ?? true;
      _soundEnabled         = p.getBool('sound_enabled') ?? true;
      _vibrationEnabled     = p.getBool('vibration_enabled') ?? true;
      _messagePreview       = p.getBool('message_preview') ?? true;
      _readReceipts         = p.getBool('read_receipts') ?? true;
      _onlineStatus         = p.getBool('online_status') ?? true;
      _typingIndicator      = p.getBool('typing_indicator') ?? true;
      _accentColor          = p.getString('accent_color') ?? 'purple';
      _chatFontSize         = p.getDouble('chat_font_size') ?? 14.0;
      _chatBubbleStyle      = p.getString('bubble_style') ?? 'rounded';
      _compactMode          = p.getBool('compact_mode') ?? false;
    });
  }

  Future<void> _saveSetting(String key, dynamic value) async {
    final p = await SharedPreferences.getInstance();
    if (value is bool)   await p.setBool(key, value);
    if (value is double) await p.setDouble(key, value);
    if (value is String) await p.setString(key, value);
  }

  // ─────────────────────────────────────────────────────────
  // PIN LOCK
  // ─────────────────────────────────────────────────────────
  Future<void> _initLockState() async {
    final storage = const FlutterSecureStorage();
    _savedPin = await storage.read(key: 'app_pin');
    if (_savedPin != null && _savedPin!.isNotEmpty) {
      setState(() { _isAppLocked = true; });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      if (_savedPin != null && _savedPin!.isNotEmpty) {
        setState(() {
          _isAppLocked = true;
          _enteredPin = '';
          _isSettingPin = false;
          _tempNewPin = '';
        });
      }
    }
  }

  void _onPinTap(String val) {
    if (val == 'back') {
      if (_enteredPin.isNotEmpty) {
        setState(() { _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1); });
      }
      return;
    }
    if (_enteredPin.length < 4) {
      setState(() { _enteredPin += val; });
      if (_enteredPin.length == 4) _verifyPin();
    }
  }

  void _verifyPin() async {
    await Future.delayed(const Duration(milliseconds: 200));
    if (_isSettingPin) {
      if (_tempNewPin.isEmpty) {
        setState(() { _tempNewPin = _enteredPin; _enteredPin = ''; });
      } else {
        if (_tempNewPin == _enteredPin) {
          await const FlutterSecureStorage().write(key: 'app_pin', value: _enteredPin);
          setState(() {
            _savedPin = _enteredPin;
            _isSettingPin = false;
            _tempNewPin = '';
            _enteredPin = '';
            _isAppLocked = false;
          });
          _showSnack(t("PIN-код встановлено", "PIN code set successfully"));
        } else {
          setState(() { _tempNewPin = ''; _enteredPin = ''; });
          HapticFeedback.heavyImpact();
          _showSnack(t("Коди не співпадають", "PIN codes do not match"));
        }
      }
    } else if (_isAppLocked) {
      if (_enteredPin == _savedPin) {
        setState(() { _isAppLocked = false; _enteredPin = ''; });
      } else {
        setState(() { _enteredPin = ''; });
        HapticFeedback.heavyImpact();
      }
    }
  }

  // ─────────────────────────────────────────────────────────
  // CRYPTO
  // ─────────────────────────────────────────────────────────
  Future<SecretKey> _getSecretKey(String remotePub, bool isGroup) async {
    if (isGroup) {
      final hash = await Sha256().hash(utf8.encode(remotePub));
      return await _aes.newSecretKeyFromBytes(hash.bytes);
    } else {
      final priv = await const FlutterSecureStorage().read(key: 'private_key');
      final secret = await X25519().sharedSecretKey(
        keyPair: SimpleKeyPairData(
          base64Decode(priv!),
          publicKey: SimplePublicKey(base64Decode(widget.publicKey), type: KeyPairType.x25519),
          type: KeyPairType.x25519,
        ),
        remotePublicKey: SimplePublicKey(base64Decode(remotePub), type: KeyPairType.x25519),
      );
      return await _aes.newSecretKeyFromBytes(await secret.extractBytes());
    }
  }

  Future<String> _decrypt(String cipher, String nonce, String macString, String remotePub, bool isGroup) async {
    try {
      final key = await _getSecretKey(remotePub, isGroup);
      final box = SecretBox(base64Decode(cipher), nonce: base64Decode(nonce), mac: Mac(base64Decode(macString)));
      return utf8.decode(await _aes.decrypt(box, secretKey: key));
    } catch (e) { return "Encrypted"; }
  }

  // ─────────────────────────────────────────────────────────
  // DATA
  // ─────────────────────────────────────────────────────────
  void _loadData() {
    _bgSocket.emitWithAck('get_recent_chats', widget.userName, ack: (dynamic data) async {
      List<Map<String, dynamic>> tempChats = List<Map<String, dynamic>>.from(data);
      for (var chat in tempChats) {
        if (chat['lastMessage'] != null) {
          var m = Map<String, dynamic>.from(chat['lastMessage']);
          String msgType = m['type'] ?? 'text';
          bool isEph = m['isEphemeral'] == true || msgType.startsWith('ephemeral_');
          msgType = msgType.replaceFirst('ephemeral_', '');
          if (isEph) {
            chat['decryptedText'] = "✨ ${t('Ефірне повідомлення', 'Aether message')}";
          } else if (msgType == 'audio') {
            chat['decryptedText'] = t("Голосове повідомлення", "Voice message");
          } else if (msgType == 'image') {
            chat['decryptedText'] = t("Фотографія", "Image");
          } else if (m['ciphertext'] != null && chat['publicKey'] != null) {
            String dec = await _decrypt(m['ciphertext'], m['nonce'], m['mac'], chat['publicKey'], chat['isGroup'] == true);
            try {
              if (dec.startsWith('{') && dec.endsWith('}')) {
                chat['decryptedText'] = jsonDecode(dec)['text'];
              } else {
                chat['decryptedText'] = dec;
              }
            } catch (e) {
              chat['decryptedText'] = t("🔒 Повідомлення зашифровано", "🔒 Message encrypted");
            }
          } else {
            chat['decryptedText'] = m['text'] ?? t("Повідомлення", "Message");
          }
          if (m['senderName'] == widget.userName) {
            chat['decryptedText'] = "${t('Ви', 'You')}: ${chat['decryptedText']}";
          } else if (chat['isGroup'] == true) {
            chat['decryptedText'] = "${m['senderName']}: ${chat['decryptedText']}";
          }
        }
      }
      tempChats.removeWhere((c) => c['isHidden'] == true);
      if (mounted) setState(() { _recentChats = tempChats; });
    });
    _bgSocket.emit('get_friends_data', widget.userName);
  }

  Future<void> _updateAvatar() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery, imageQuality: 50, maxWidth: 500, maxHeight: 500);
    if (image == null || !mounted) return;
    final bytes = await image.readAsBytes();
    final base64String = base64Encode(bytes);
    setState(() { _myAvatar = base64String; });
    _bgSocket.emit('update_avatar', {'userName': widget.userName, 'avatar': base64String});
    _loadData();
  }

  void _sendFriendRequest() {
    final target = _addFriendController.text.trim();
    if (target.isEmpty) return;
    _bgSocket.emitWithAck('send_friend_request', {'requester': widget.userName, 'receiver': target},
        ack: (dynamic data) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(data['message'], style: const TextStyle(color: Colors.white)),
          backgroundColor: data['success'] ? const Color(0xFF333333) : Colors.red.shade900,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
        ));
        _addFriendController.clear();
      }
    });
  }

  void _respondToRequest(String requester, String action) {
    _bgSocket.emit('respond_friend_request', {
      'requester': requester, 'receiver': widget.userName, 'action': action,
    });
    _loadData();
  }

  void _logout() async {
    await (await SharedPreferences.getInstance()).remove('user_name');
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const MainGate()), (r) => false);
    }
  }

  void _changeLanguage(String newLang) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lang', newLang);
    setState(() { lang = newLang; });
    _loadData();
  }

  void _searchUsersForVerify() {
    final q = _verifySearchController.text.trim();
    if (q.isEmpty) return;
    _bgSocket.emitWithAck('search_users_for_verify', {'adminName': widget.userName, 'query': q},
        ack: (dynamic data) {
      if (mounted) setState(() { _verifyResults = List<Map<String, dynamic>>.from(data); });
    });
  }

  void _toggleVerification(String targetName, bool currentlyVerified) {
    final event = currentlyVerified ? 'revoke_verification' : 'grant_verification';
    _bgSocket.emitWithAck(event, {'adminName': widget.userName, 'targetName': targetName},
        ack: (dynamic data) {
      if (context.mounted) {
        _showSnack(data['success']
            ? (currentlyVerified
                ? t('Верифікацію знято', 'Verification revoked')
                : t('Верифіковано!', 'Verified!'))
            : (data['message'] ?? 'Error'));
        _searchUsersForVerify();
      }
    });
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: const Color(0xFF333333),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
    ));
  }

  // ─────────────────────────────────────────────────────────
  // DIALOGS
  // ─────────────────────────────────────────────────────────
  void _showCreateGroupDialog() {
    if (_friends.isEmpty) {
      _showSnack(t('Спочатку додайте друзів!', 'Add friends first!'));
      return;
    }
    final groupNameController = TextEditingController();
    List<String> selectedFriends = [];
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateSB) => AlertDialog(
          backgroundColor: Colors.transparent,
          contentPadding: EdgeInsets.zero,
          content: GlassContainer(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(t('Створити групу', 'Create Group'),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 20),
                GlassInput(controller: groupNameController, hintText: t('Назва групи', 'Group Name')),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(t("Учасники", "Members"),
                      style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.white70, fontSize: 13)),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 150,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _friends.length,
                    itemBuilder: (context, index) {
                      final friend = _friends[index]['userName'];
                      return CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(friend, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                        value: selectedFriends.contains(friend),
                        fillColor: WidgetStateProperty.resolveWith((states) =>
                            states.contains(WidgetState.selected) ? Colors.white : Colors.transparent),
                        checkColor: Colors.black,
                        side: const BorderSide(color: Colors.white54),
                        checkboxShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                        onChanged: (bool? value) {
                          setStateSB(() {
                            if (value == true) { selectedFriends.add(friend); }
                            else { selectedFriends.remove(friend); }
                          });
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(t('Скасувати', 'Cancel'),
                          style: const TextStyle(color: Colors.white70, fontSize: 14)),
                    ),
                    TextButton(
                      onPressed: () {
                        if (groupNameController.text.trim().isNotEmpty && selectedFriends.isNotEmpty) {
                          _bgSocket.emitWithAck('create_group', {
                            'name': groupNameController.text.trim(),
                            'participants': selectedFriends,
                            'creator': widget.userName,
                          }, ack: (dynamic data) {
                            if (data['success'] == true) _loadData();
                          });
                          Navigator.pop(context);
                        }
                      },
                      child: Text(t('Створити', 'Create'),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showEditBioDialog() {
    final bioController = TextEditingController(text: _myBio);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.transparent,
        contentPadding: EdgeInsets.zero,
        content: GlassContainer(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(t("Про себе", "About"),
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              TextField(
                controller: bioController,
                maxLength: 100,
                maxLines: null,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: t("Напишіть щось...", "Write something..."),
                  hintStyle: const TextStyle(color: Colors.white54),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2))),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.4))),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  counterStyle: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(t("Скасувати", "Cancel"), style: const TextStyle(color: Colors.white70)),
                  ),
                  TextButton(
                    onPressed: () {
                      _bgSocket.emit('update_bio', {'userName': widget.userName, 'bio': bioController.text.trim()});
                      setState(() => _myBio = bioController.text.trim());
                      Navigator.pop(context);
                    },
                    child: Text(t("Зберегти", "Save"),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showExportDialog() {
    final passwordController = TextEditingController();
    String? backupToken;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateSB) => AlertDialog(
          backgroundColor: Colors.transparent,
          contentPadding: EdgeInsets.zero,
          content: GlassContainer(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(t("Експорт акаунта", "Export Account"),
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Text(
                  t("Увага! Створіть пароль. Якщо ви його забудете, відновити акаунт буде неможливо.",
                      "Warning! Create a password. If you lose it, recovery is impossible."),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.red.withValues(alpha: 0.8), fontSize: 12),
                ),
                const SizedBox(height: 20),
                if (backupToken == null) ...[
                  GlassInput(
                    controller: passwordController,
                    hintText: t("Придумайте пароль", "Create password"),
                    obscureText: true,
                  ),
                  const SizedBox(height: 20),
                  ShineButton(
                    text: t("Згенерувати ключ", "Generate Backup"),
                    onPressed: () async {
                      if (passwordController.text.trim().isEmpty) return;
                      try {
                        final storage = const FlutterSecureStorage();
                        final priv = await storage.read(key: 'private_key');
                        final payloadStr = jsonEncode({
                          'priv': priv, 'pub': widget.publicKey,
                          'dev': widget.deviceId, 'name': widget.userName,
                        });
                        final passHash = await Sha256().hash(utf8.encode(passwordController.text.trim()));
                        final key = await _aes.newSecretKeyFromBytes(passHash.bytes);
                        final box = await _aes.encrypt(utf8.encode(payloadStr), secretKey: key);
                        setStateSB(() {
                          backupToken =
                              '${base64Encode(box.nonce)}.${base64Encode(box.cipherText)}.${base64Encode(box.mac.bytes)}';
                        });
                      } catch (e) { _showSnack("Encryption error"); }
                    },
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFB026FF).withValues(alpha: 0.5)),
                    ),
                    child: SelectableText(backupToken!,
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontFamily: 'monospace')),
                  ),
                  const SizedBox(height: 16),
                  ElegantButton(
                    text: t("Скопіювати ключ", "Copy Backup Key"),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: backupToken!));
                      _showSnack(t("Скопійовано в буфер", "Copied to clipboard"));
                      Navigator.pop(context);
                    },
                  ),
                ],
                if (backupToken == null)
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(t('Скасувати', 'Cancel'), style: const TextStyle(color: Colors.white70)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showUserProfile(String partnerName, String? initialAvatar, String? publicKey, bool isGroup) {
    if (isGroup || partnerName == widget.userName) return;
    String? currentBio;
    String? currentAvatar = initialAvatar;
    bool isVerifiedUser = false;
    bool fetched = false;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        Map<String, dynamic>? chatSettings;
        try { chatSettings = _recentChats.firstWhere((c) => c['partnerName'] == partnerName); }
        catch (e) { /* ignore */ }
        bool isBlocked = chatSettings?['isBlocked'] == true;
        bool isPinned = chatSettings?['isPinned'] == true;
        return StatefulBuilder(
          builder: (context, setStateSB) {
            if (!fetched) {
              fetched = true;
              _bgSocket.emitWithAck('get_user_profile', partnerName, ack: (dynamic data) {
                if (data['success'] == true) {
                  setStateSB(() {
                    currentBio = data['bio'];
                    currentAvatar = data['avatar'] ?? currentAvatar;
                    isVerifiedUser = data['isVerified'] == true;
                  });
                }
              });
            }
            return Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SafeAvatar(avatarBase64: currentAvatar, fallbackName: partnerName, radius: 46),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(partnerName,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 24,
                                    fontWeight: FontWeight.bold, letterSpacing: -0.5)),
                            if (isVerifiedUser) ...[const SizedBox(width: 8), const VerifiedBadge(size: 22)],
                          ],
                        ),
                        if (currentBio != null && currentBio!.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(currentBio!, textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 15)),
                        ],
                        const SizedBox(height: 32),
                        GlassContainer(
                          child: Column(children: [
                            ListTile(
                              leading: const Icon(Icons.chat_bubble_outline, color: Colors.white),
                              title: Text(t("Написати", "Message"),
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                              onTap: () {
                                Navigator.pop(context);
                                _startChat(partnerName, publicKey,
                                    targetAvatar: currentAvatar, isVerified: isVerifiedUser);
                              },
                            ),
                            Divider(height: 1, indent: 50, color: Colors.white.withValues(alpha: 0.1)),
                            ListTile(
                              leading: Icon(isPinned ? Icons.push_pin : Icons.push_pin_outlined, color: Colors.white),
                              title: Text(isPinned ? t("Відкріпити чат", "Unpin Chat") : t("Закріпити чат", "Pin Chat"),
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                              onTap: () {
                                _bgSocket.emit('update_chat_settings', {
                                  'userName': widget.userName, 'partnerName': partnerName,
                                  'isPinned': !isPinned, 'isHidden': chatSettings?['isHidden'] == true,
                                  'isDeleted': false, 'isBlocked': isBlocked,
                                });
                                Navigator.pop(context);
                              },
                            ),
                            Divider(height: 1, indent: 50, color: Colors.white.withValues(alpha: 0.1)),
                            ListTile(
                              leading: const Icon(Icons.visibility_off, color: Colors.white),
                              title: Text(t("Приховати чат", "Hide Chat"),
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                              onTap: () {
                                _bgSocket.emit('update_chat_settings', {
                                  'userName': widget.userName, 'partnerName': partnerName,
                                  'isPinned': isPinned, 'isHidden': true,
                                  'isDeleted': false, 'isBlocked': isBlocked,
                                });
                                Navigator.pop(context);
                              },
                            ),
                          ]),
                        ),
                        const SizedBox(height: 16),
                        GlassContainer(
                          child: Column(children: [
                            ListTile(
                              leading: Icon(isBlocked ? Icons.lock_open : Icons.block,
                                  color: const Color(0xFFFF3B30)),
                              title: Text(isBlocked ? t("Розблокувати", "Unblock") : t("Заблокувати", "Block"),
                                  style: const TextStyle(color: Color(0xFFFF3B30), fontWeight: FontWeight.w500)),
                              onTap: () {
                                _bgSocket.emit('update_chat_settings', {
                                  'userName': widget.userName, 'partnerName': partnerName,
                                  'isPinned': isPinned, 'isHidden': chatSettings?['isHidden'] == true,
                                  'isDeleted': false, 'isBlocked': !isBlocked,
                                });
                                setStateSB(() { isBlocked = !isBlocked; });
                                _loadData();
                              },
                            ),
                            Divider(height: 1, indent: 50, color: Colors.white.withValues(alpha: 0.1)),
                            ListTile(
                              leading: const Icon(Icons.delete_outline, color: Color(0xFFFF3B30)),
                              title: Text(t("Видалити історію", "Delete History"),
                                  style: const TextStyle(color: Color(0xFFFF3B30), fontWeight: FontWeight.w500)),
                              onTap: () {
                                _bgSocket.emit('update_chat_settings', {
                                  'userName': widget.userName, 'partnerName': partnerName,
                                  'isPinned': false, 'isHidden': false,
                                  'isDeleted': true, 'isBlocked': isBlocked,
                                });
                                Navigator.pop(context);
                              },
                            ),
                          ]),
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showChatOptions(Map<String, dynamic> chat) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      builder: (context) => Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: Icon(
                        chat['isPinned'] == true ? Icons.push_pin : Icons.push_pin_outlined,
                        color: Colors.white),
                    title: Text(chat['isPinned'] == true ? t('Відкріпити', 'Unpin') : t('Закріпити', 'Pin'),
                        style: const TextStyle(color: Colors.white)),
                    onTap: () {
                      Navigator.pop(context);
                      _bgSocket.emit('update_chat_settings', {
                        'userName': widget.userName, 'partnerName': chat['partnerName'],
                        'isPinned': !(chat['isPinned'] == true), 'isHidden': chat['isHidden'] == true,
                        'isDeleted': false, 'isBlocked': chat['isBlocked'] == true,
                      });
                    },
                  ),
                  Divider(height: 1, color: Colors.white.withValues(alpha: 0.1)),
                  ListTile(
                    leading: const Icon(Icons.visibility_off, color: Colors.white),
                    title: Text(t('Приховати чат', 'Hide Chat'), style: const TextStyle(color: Colors.white)),
                    subtitle: Text(t('Можна знайти через пошук', 'Can be found via search'),
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12)),
                    onTap: () {
                      Navigator.pop(context);
                      _bgSocket.emit('update_chat_settings', {
                        'userName': widget.userName, 'partnerName': chat['partnerName'],
                        'isPinned': chat['isPinned'] == true, 'isHidden': true,
                        'isDeleted': false, 'isBlocked': chat['isBlocked'] == true,
                      });
                    },
                  ),
                  Divider(height: 1, color: Colors.white.withValues(alpha: 0.1)),
                  ListTile(
                    leading: const Icon(Icons.delete_outline, color: Color(0xFFFF3B30)),
                    title: Text(t('Видалити', 'Delete'), style: const TextStyle(color: Color(0xFFFF3B30))),
                    onTap: () {
                      Navigator.pop(context);
                      _bgSocket.emit('update_chat_settings', {
                        'userName': widget.userName, 'partnerName': chat['partnerName'],
                        'isPinned': false, 'isHidden': false,
                        'isDeleted': true, 'isBlocked': chat['isBlocked'] == true,
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showBlockedUsersSheet() {
    final blocked = _recentChats.where((c) => c['isBlocked'] == true).toList();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.5,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Column(children: [
              const SizedBox(height: 12),
              Container(
                width: 36, height: 4,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 16),
              Text(t("Заблоковані", "Blocked Users"),
                  style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              Expanded(
                child: blocked.isEmpty
                    ? Center(
                        child: Text(t("Список порожній", "No blocked users"),
                            style: const TextStyle(color: Colors.white38)))
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: blocked.length,
                        separatorBuilder: (_, __) => _divider(),
                        itemBuilder: (context, i) {
                          final u = blocked[i];
                          return ListTile(
                            leading: SafeAvatar(
                                avatarBase64: u['avatar'], fallbackName: u['partnerName'], radius: 20),
                            title: Text(u['partnerName'],
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                            trailing: GestureDetector(
                              onTap: () {
                                _bgSocket.emit('update_chat_settings', {
                                  'userName': widget.userName, 'partnerName': u['partnerName'],
                                  'isPinned': false, 'isHidden': false,
                                  'isDeleted': false, 'isBlocked': false,
                                });
                                Navigator.pop(context);
                                _loadData();
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(50),
                                  border: Border.all(color: Colors.white12),
                                ),
                                child: Text(t("Розблок.", "Unblock"),
                                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  void _startChat(String targetName, String? targetKey, {String? targetAvatar, bool isVerified = false}) {
    if (targetName.isEmpty) return;
    if (targetKey != null) {
      _openChatScreen(targetName, targetKey, avatar: targetAvatar, isVerified: isVerified);
      return;
    }
    setState(() => _isSearching = true);
    _bgSocket.emitWithAck('get_key', targetName, ack: (dynamic response) {
      if (mounted) setState(() { _isSearching = false; });
      if (response['success'] == true) {
        _bgSocket.emit('update_chat_settings', {
          'userName': widget.userName, 'partnerName': targetName,
          'isPinned': false, 'isHidden': false, 'isDeleted': false, 'isBlocked': false,
        });
        _openChatScreen(targetName, response['publicKey'],
            avatar: response['avatar'], isVerified: response['isVerified'] == true);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(response['message'] ?? t('Не знайдено', 'Not found'),
              style: const TextStyle(color: Colors.white)),
          backgroundColor: Colors.red.shade900,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
        ));
      }
    });
  }

  void _openChatScreen(String targetName, String targetKey, {String? avatar, bool isVerified = false}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(
          deviceId: widget.deviceId,
          userName: widget.userName,
          myPublicKey: widget.publicKey,
          partnerName: targetName,
          partnerPublicKey: targetKey,
          partnerAvatar: avatar,
          partnerIsVerified: isVerified,
          friends: _friends,
        ),
      ),
    ).then((_) => _loadData());
  }

  // ─────────────────────────────────────────────────────────
  // LOCK SCREEN
  // ─────────────────────────────────────────────────────────
  Widget _buildLockScreen() {
    final isPinConfirmStep = _isSettingPin && _tempNewPin.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned(
            top: -80, left: -60,
            child: Container(
              width: 280, height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFB026FF).withValues(alpha: 0.08),
              ),
            ),
          ),
          Positioned(
            bottom: -100, right: -80,
            child: Container(
              width: 320, height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFB026FF).withValues(alpha: 0.05),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 2),
                // Кастомна іконка замка
                const _AppleLockIcon(),
                const SizedBox(height: 24),
                // Заголовок
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Text(
                    key: ValueKey(_isSettingPin
                        ? (_tempNewPin.isEmpty ? 'create' : 'confirm')
                        : 'enter'),
                    _isSettingPin
                        ? (_tempNewPin.isEmpty
                            ? t("Створіть PIN-код", "Create PIN code")
                            : t("Підтвердіть PIN-код", "Confirm PIN code"))
                        : t("Введіть PIN-код", "Enter PIN code"),
                    style: const TextStyle(
                      color: Colors.white, fontSize: 22,
                      fontWeight: FontWeight.w700, letterSpacing: -0.5,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _isSettingPin
                      ? (isPinConfirmStep
                          ? t("Введіть PIN ще раз", "Enter PIN again")
                          : t("4 цифри для захисту додатку", "4 digits to protect the app"))
                      : t("Ваш особистий код безпеки", "Your personal security code"),
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 14),
                ),
                const Spacer(),
                // Крапки
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(4, (index) {
                    final filled = _enteredPin.length > index;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      curve: Curves.easeOutBack,
                      margin: const EdgeInsets.symmetric(horizontal: 10),
                      width: filled ? 18 : 14,
                      height: filled ? 18 : 14,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: filled ? const Color(0xFFB026FF) : Colors.transparent,
                        border: Border.all(
                          color: filled ? const Color(0xFFB026FF) : Colors.white.withValues(alpha: 0.3),
                          width: 2,
                        ),
                        boxShadow: filled
                            ? [BoxShadow(
                                color: const Color(0xFFB026FF).withValues(alpha: 0.5),
                                blurRadius: 8, spreadRadius: 1)]
                            : [],
                      ),
                    );
                  }),
                ),
                const Spacer(),
                // Клавіатура
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Column(
                    children: [
                      for (final row in [
                        ['1', '2', '3'],
                        ['4', '5', '6'],
                        ['7', '8', '9'],
                        ['', '0', 'back'],
                      ])
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: row.map((val) => _numButton(val)).toList(),
                          ),
                        ),
                    ],
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _numButton(String val) {
    if (val.isEmpty) return const SizedBox(width: 72, height: 72);
    return GestureDetector(
      onTap: () => _onPinTap(val),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        width: 72, height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.07),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1),
        ),
        child: Center(
          child: val == 'back'
              ? Icon(Icons.backspace_outlined, color: Colors.white.withValues(alpha: 0.8), size: 24)
              : Text(val,
                  style: const TextStyle(
                    color: Colors.white, fontSize: 28,
                    fontWeight: FontWeight.w400, letterSpacing: -0.5,
                  )),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // TABS
  // ─────────────────────────────────────────────────────────
  Widget _buildChatsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10),
          child: Center(
            child: AnimatedSearchInput(
              controller: _searchController,
              onSubmitted: (_) =>
                  _isSearching ? null : _startChat(_searchController.text.trim(), null),
            ),
          ),
        ),
        if (_isSearching)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(10),
              child: SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
            ),
          ),
        Expanded(
          child: _recentChats.isEmpty
              ? Center(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(t("Чатів поки що немає.", "No chats yet."),
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 16)),
                    const SizedBox(height: 4),
                    Text(t("Напишіть щось друзям.", "Write something to friends."),
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 16)),
                  ]),
                )
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 120),
                  itemCount: _recentChats.length,
                  separatorBuilder: (context, index) => Padding(
                    padding: const EdgeInsets.only(left: 76.0),
                    child: Divider(height: 1, color: Colors.white.withValues(alpha: 0.05)),
                  ),
                  itemBuilder: (context, index) {
                    final chat = _recentChats[index];
                    final isGroup = chat['isGroup'] == true;
                    final unreadCount = chat['unreadCount'] ?? 0;
                    final isSelf = chat['partnerName'] == widget.userName;
                    final chatVerified = chat['isVerified'] == true;
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      leading: GestureDetector(
                        onTap: () => isSelf
                            ? null
                            : _showUserProfile(chat['partnerName'], chat['avatar'], chat['publicKey'], isGroup),
                        child: isSelf
                            ? CircleAvatar(
                                radius: 24,
                                backgroundColor: Colors.white.withValues(alpha: 0.1),
                                child: const Icon(Icons.bookmark, color: Colors.white70),
                              )
                            : StoryRingAvatar(
                                avatarBase64: chat['avatar'],
                                fallbackName: chat['partnerName'],
                                radius: 24,
                                isGroup: isGroup,
                                hasUnread: unreadCount > 0,
                              ),
                      ),
                      title: Row(children: [
                        Expanded(
                          child: Text(
                            isSelf ? t("Нотатник", "Saved Messages") : chat['partnerName'],
                            style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.w600,
                              fontSize: 16, letterSpacing: -0.2,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (!isGroup && chatVerified) ...[
                          const SizedBox(width: 4), const VerifiedBadge(size: 14),
                        ],
                        if (chat['isPinned'] == true) ...[
                          const SizedBox(width: 4),
                          Icon(Icons.push_pin, color: Colors.white.withValues(alpha: 0.5), size: 14),
                        ],
                      ]),
                      subtitle: Text(
                        chat['decryptedText'] ??
                            (isGroup ? t("Груповий чат", "Group Chat") : t("Почніть чат", "Start chatting")),
                        style: TextStyle(
                          color: unreadCount > 0 ? Colors.white : Colors.white.withValues(alpha: 0.6),
                          fontWeight: unreadCount > 0 ? FontWeight.w500 : FontWeight.normal,
                          fontSize: 14,
                        ),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (chat['lastMessage'] != null)
                            Text(
                              DateFormat('HH:mm').format(DateTime.parse(chat['timestamp']).toLocal()),
                              style: TextStyle(
                                fontSize: 12,
                                color: unreadCount > 0 ? Colors.white : Colors.white.withValues(alpha: 0.5),
                              ),
                            ),
                          const SizedBox(height: 4),
                          if (unreadCount > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white, borderRadius: BorderRadius.circular(50)),
                              child: Text('$unreadCount',
                                  style: const TextStyle(
                                    color: Colors.black, fontSize: 11, fontWeight: FontWeight.bold)),
                            ),
                        ],
                      ),
                      onLongPress: () => _showChatOptions(chat),
                      onTap: () => _startChat(chat['partnerName'], chat['publicKey'],
                          targetAvatar: chat['avatar'], isVerified: chatVerified),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildFriendsTab() {
    return ListView(
      padding: const EdgeInsets.only(top: 20, bottom: 120),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(t("ДОДАТИ ДРУГА", "ADD FRIEND"),
              style: TextStyle(
                fontSize: 12, color: Colors.white.withValues(alpha: 0.5),
                fontWeight: FontWeight.bold, letterSpacing: 1,
              )),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Expanded(
              child: GlassInput(
                controller: _addFriendController,
                hintText: t("Нікнейм", "Username"),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_.\-]'))],
              ),
            ),
            const SizedBox(width: 10),
            ElegantButton(text: t("ДОДАТИ", "ADD"), onPressed: _sendFriendRequest),
          ]),
        ),
        const SizedBox(height: 32),
        if (_pendingRequests.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(t("ЗАПИТИ В ДРУЗІ", "REQUESTS"),
                style: TextStyle(
                  fontSize: 12, color: Colors.white.withValues(alpha: 0.5),
                  fontWeight: FontWeight.bold, letterSpacing: 1,
                )),
          ),
          GlassContainer(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: _pendingRequests.asMap().entries.map((entry) {
                int idx = entry.key;
                var req = entry.value;
                return Column(children: [
                  ListTile(
                    leading: GestureDetector(
                      onTap: () => _showUserProfile(req['userName'], req['avatar'], null, false),
                      child: SafeAvatar(avatarBase64: req['avatar'], fallbackName: req['userName'], radius: 20),
                    ),
                    title: Row(children: [
                      Text(req['userName'],
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 16)),
                      if (req['isVerified'] == 1) ...[const SizedBox(width: 5), const VerifiedBadge(size: 13)],
                    ]),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: () => _respondToRequest(req['userName'], 'accept'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(50)),
                            child: Text(t("Прийняти", "Accept"),
                                style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => _respondToRequest(req['userName'], 'reject'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.1),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                              borderRadius: BorderRadius.circular(50),
                            ),
                            child: Text(t("Сховати", "Deny"), style: const TextStyle(color: Colors.white, fontSize: 12)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (idx != _pendingRequests.length - 1)
                    Divider(height: 1, indent: 60, color: Colors.white.withValues(alpha: 0.05)),
                ]);
              }).toList(),
            ),
          ),
          const SizedBox(height: 24),
        ],
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(t("ДРУЗІ", "FRIENDS"),
              style: TextStyle(
                fontSize: 12, color: Colors.white.withValues(alpha: 0.5),
                fontWeight: FontWeight.bold, letterSpacing: 1,
              )),
        ),
        _friends.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(t("У вас ще немає друзів.", "No friends yet."),
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 14)),
              )
            : GlassContainer(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: _friends.asMap().entries.map((entry) {
                    int idx = entry.key;
                    var f = entry.value;
                    return Column(children: [
                      ListTile(
                        leading: GestureDetector(
                          onTap: () => _showUserProfile(f['userName'], f['avatar'], f['publicKey'], false),
                          child: SafeAvatar(avatarBase64: f['avatar'], fallbackName: f['userName'], radius: 20),
                        ),
                        title: Row(children: [
                          Text(f['userName'],
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 16)),
                          if (f['isVerified'] == true || f['isVerified'] == 1) ...[
                            const SizedBox(width: 5), const VerifiedBadge(size: 13),
                          ],
                        ]),
                        onTap: () => _startChat(f['userName'], f['publicKey'],
                            targetAvatar: f['avatar'],
                            isVerified: (f['isVerified'] == true || f['isVerified'] == 1)),
                      ),
                      if (idx != _friends.length - 1)
                        Divider(height: 1, indent: 60, color: Colors.white.withValues(alpha: 0.05)),
                    ]);
                  }).toList(),
                ),
              ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────
  // SETTINGS TAB
  // ─────────────────────────────────────────────────────────
  Widget _buildSettingsTab() {
    final accent = _accentColors[_accentColor]!;

    return ListView(
      padding: const EdgeInsets.only(top: 0, bottom: 120),
      children: [
        // ── ПРОФІЛЬ ───────────────────────────────────────────
        Container(
          margin: const EdgeInsets.fromLTRB(16, 20, 16, 0),
          child: GlassContainer(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Stack(children: [
                  SafeAvatar(avatarBase64: _myAvatar, fallbackName: widget.userName, radius: 34),
                  Positioned(
                    bottom: 0, right: 0,
                    child: GestureDetector(
                      onTap: _updateAvatar,
                      child: Container(
                        width: 22, height: 22,
                        decoration: BoxDecoration(
                          color: accent, shape: BoxShape.circle,
                          border: Border.all(color: Colors.black, width: 2),
                        ),
                        child: const Icon(Icons.camera_alt_rounded, size: 11, color: Colors.white),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Flexible(
                          child: Text(widget.userName,
                              style: const TextStyle(
                                color: Colors.white, fontSize: 18,
                                fontWeight: FontWeight.w700, letterSpacing: -0.4,
                              ),
                              overflow: TextOverflow.ellipsis),
                        ),
                        if (_myVerified) ...[const SizedBox(width: 6), const VerifiedBadge(size: 16)],
                      ]),
                      const SizedBox(height: 3),
                      GestureDetector(
                        onTap: _showEditBioDialog,
                        child: Row(children: [
                          Flexible(
                            child: Text(
                              _myBio.isEmpty ? t("Додати опис...", "Add a bio...") : _myBio,
                              style: TextStyle(
                                color: _myBio.isEmpty ? Colors.white30 : Colors.white54,
                                fontSize: 13,
                                fontStyle: _myBio.isEmpty ? FontStyle.italic : FontStyle.normal,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.edit_rounded, size: 12, color: accent.withValues(alpha: 0.7)),
                        ]),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: Colors.white24, size: 20),
              ],
            ),
          ),
        ),

        // ── СПОВІЩЕННЯ ────────────────────────────────────────
        _sectionHeader(t("СПОВІЩЕННЯ", "NOTIFICATIONS")),
        GlassContainer(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(children: [
            _settingToggle(
              icon: Icons.notifications_rounded, iconColor: const Color(0xFFFF3B30),
              title: t("Сповіщення", "Notifications"),
              value: _notificationsEnabled,
              onChanged: (v) { setState(() => _notificationsEnabled = v); _saveSetting('notif_enabled', v); },
              accent: accent,
            ),
            _divider(),
            _settingToggle(
              icon: Icons.volume_up_rounded, iconColor: const Color(0xFF007AFF),
              title: t("Звук", "Sound"),
              value: _soundEnabled, enabled: _notificationsEnabled,
              onChanged: (v) { setState(() => _soundEnabled = v); _saveSetting('sound_enabled', v); },
              accent: accent,
            ),
            _divider(),
            _settingToggle(
              icon: Icons.vibration_rounded, iconColor: const Color(0xFF34C759),
              title: t("Вібрація", "Vibration"),
              value: _vibrationEnabled, enabled: _notificationsEnabled,
              onChanged: (v) { setState(() => _vibrationEnabled = v); _saveSetting('vibration_enabled', v); },
              accent: accent,
            ),
            _divider(),
            _settingToggle(
              icon: Icons.chat_bubble_outline_rounded, iconColor: const Color(0xFFFF9500),
              title: t("Попередній перегляд", "Message Preview"),
              subtitle: t("Показувати текст у сповіщенні", "Show text in notification"),
              value: _messagePreview, enabled: _notificationsEnabled,
              onChanged: (v) { setState(() => _messagePreview = v); _saveSetting('message_preview', v); },
              accent: accent,
            ),
          ]),
        ),

        // ── КОНФІДЕНЦІЙНІСТЬ ──────────────────────────────────
        _sectionHeader(t("КОНФІДЕНЦІЙНІСТЬ", "PRIVACY")),
        GlassContainer(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(children: [
            _settingToggle(
              icon: Icons.done_all_rounded, iconColor: const Color(0xFF007AFF),
              title: t("Прочитано", "Read Receipts"),
              subtitle: t("Показувати коли прочитали", "Show when you've read messages"),
              value: _readReceipts,
              onChanged: (v) {
                setState(() => _readReceipts = v);
                _saveSetting('read_receipts', v);
                _bgSocket.emit('update_privacy', {'userName': widget.userName, 'readReceipts': v});
              },
              accent: accent,
            ),
            _divider(),
            _settingToggle(
              icon: Icons.circle_rounded, iconColor: const Color(0xFF34C759),
              title: t("Статус онлайн", "Online Status"),
              subtitle: t("Показувати коли ви в мережі", "Show when you're online"),
              value: _onlineStatus,
              onChanged: (v) {
                setState(() => _onlineStatus = v);
                _saveSetting('online_status', v);
                _bgSocket.emit('update_privacy', {'userName': widget.userName, 'onlineStatus': v});
              },
              accent: accent,
            ),
            _divider(),
            _settingToggle(
              icon: Icons.keyboard_rounded, iconColor: const Color(0xFFFF9500),
              title: t("Введення...", "Typing Indicator"),
              subtitle: t("Показувати коли пишете", "Show when you're typing"),
              value: _typingIndicator,
              onChanged: (v) {
                setState(() => _typingIndicator = v);
                _saveSetting('typing_indicator', v);
                _bgSocket.emit('update_privacy', {'userName': widget.userName, 'typingIndicator': v});
              },
              accent: accent,
            ),
          ]),
        ),

        // ── БЕЗПЕКА ───────────────────────────────────────────
        _sectionHeader(t("БЕЗПЕКА", "SECURITY")),
        GlassContainer(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(children: [
            _settingToggle(
              icon: Icons.lock_rounded, iconColor: const Color(0xFFB026FF),
              title: t("PIN-код", "App Lock"),
              subtitle: _savedPin != null
                  ? t("Увімкнено", "Enabled")
                  : t("Вимкнено", "Disabled"),
              value: _savedPin != null && _savedPin!.isNotEmpty,
              onChanged: (val) async {
                if (val) {
                  setState(() {
                    _isAppLocked = true; _isSettingPin = true;
                    _enteredPin = ''; _tempNewPin = '';
                  });
                } else {
                  await const FlutterSecureStorage().delete(key: 'app_pin');
                  setState(() => _savedPin = null);
                  _showSnack(t("PIN-код вимкнено", "PIN disabled"));
                }
              },
              accent: accent,
            ),
            _divider(),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              leading: _settingIcon(Icons.vpn_key_rounded, const Color(0xFFFF9500)),
              title: Text(t("Резервна копія", "Account Backup"),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 15)),
              subtitle: Text(t("Експорт зашифрованих ключів", "Export encrypted keys"),
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12)),
              trailing: Icon(Icons.chevron_right_rounded, color: Colors.white24, size: 20),
              onTap: _showExportDialog,
            ),
            _divider(),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              leading: _settingIcon(Icons.block_rounded, const Color(0xFFFF3B30)),
              title: Text(t("Заблоковані", "Blocked Users"),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 15)),
              subtitle: Text(
                _recentChats.where((c) => c['isBlocked'] == true).isEmpty
                    ? t("Немає заблокованих", "No blocked users")
                    : "${_recentChats.where((c) => c['isBlocked'] == true).length} ${t('користувач(ів)', 'user(s)')}",
                style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
              ),
              trailing: Icon(Icons.chevron_right_rounded, color: Colors.white24, size: 20),
              onTap: _showBlockedUsersSheet,
            ),
          ]),
        ),

        // ── ЗОВНІШНІЙ ВИГЛЯД ──────────────────────────────────
        _sectionHeader(t("ЗОВНІШНІЙ ВИГЛЯД", "APPEARANCE")),
        GlassContainer(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(children: [
            // Акцентний колір
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    _settingIcon(Icons.palette_rounded, accent),
                    const SizedBox(width: 14),
                    Text(t("Акцентний колір", "Accent Color"),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 15)),
                  ]),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: _accentColors.entries.map((e) {
                      final isSelected = _accentColor == e.key;
                      return GestureDetector(
                        onTap: () { setState(() => _accentColor = e.key); _saveSetting('accent_color', e.key); },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: isSelected ? 38 : 32,
                          height: isSelected ? 38 : 32,
                          decoration: BoxDecoration(
                            color: e.value,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected ? Colors.white : Colors.transparent, width: 2.5),
                            boxShadow: isSelected
                                ? [BoxShadow(color: e.value.withValues(alpha: 0.6), blurRadius: 12, spreadRadius: 1)]
                                : [],
                          ),
                          child: isSelected
                              ? const Icon(Icons.check_rounded, color: Colors.white, size: 16)
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            _divider(),
            // Розмір шрифту
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    _settingIcon(Icons.format_size_rounded, const Color(0xFF007AFF)),
                    const SizedBox(width: 14),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(t("Розмір шрифту", "Font Size"),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 15)),
                      Text('${_chatFontSize.round()} px',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12)),
                    ]),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    Text('A', style: TextStyle(color: Colors.white54, fontSize: 12)),
                    Expanded(
                      child: SliderTheme(
                        data: SliderThemeData(
                          activeTrackColor: accent,
                          inactiveTrackColor: Colors.white12,
                          thumbColor: Colors.white,
                          overlayColor: accent.withValues(alpha: 0.2),
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                        ),
                        child: Slider(
                          value: _chatFontSize, min: 12, max: 18, divisions: 6,
                          onChanged: (v) { setState(() => _chatFontSize = v); _saveSetting('chat_font_size', v); },
                        ),
                      ),
                    ),
                    Text('A', style: TextStyle(color: Colors.white54, fontSize: 18)),
                  ]),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(12)),
                    child: Text(
                      t("Привіт! Як справи? 👋", "Hey there! How are you? 👋"),
                      style: TextStyle(color: Colors.white70, fontSize: _chatFontSize),
                    ),
                  ),
                ],
              ),
            ),
            _divider(),
            // Стиль бульок
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    _settingIcon(Icons.chat_bubble_rounded, const Color(0xFF34C759)),
                    const SizedBox(width: 14),
                    Text(t("Стиль бульок", "Bubble Style"),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 15)),
                  ]),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _bubbleOption('rounded', t("Округлі", "Rounded"), accent),
                      _bubbleOption('sharp', t("Гострі", "Sharp"), accent),
                      _bubbleOption('minimal', t("Мінімал", "Minimal"), accent),
                    ],
                  ),
                ],
              ),
            ),
            _divider(),
            _settingToggle(
              icon: Icons.view_compact_rounded, iconColor: const Color(0xFFFF9500),
              title: t("Компактний режим", "Compact Mode"),
              subtitle: t("Менші відступи у чатах", "Smaller padding in chats"),
              value: _compactMode,
              onChanged: (v) { setState(() => _compactMode = v); _saveSetting('compact_mode', v); },
              accent: accent,
            ),
          ]),
        ),

        // ── МОВА ──────────────────────────────────────────────
        _sectionHeader(t("МОВА", "LANGUAGE")),
        GlassContainer(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(children: [
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              leading: const Text("🇺🇦", style: TextStyle(fontSize: 22)),
              title: const Text("Українська",
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 15)),
              trailing: lang == 'uk' ? Icon(Icons.check_rounded, color: accent) : null,
              onTap: () => _changeLanguage('uk'),
            ),
            _divider(),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              leading: const Text("🇬🇧", style: TextStyle(fontSize: 22)),
              title: const Text("English",
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 15)),
              trailing: lang == 'en' ? Icon(Icons.check_rounded, color: accent) : null,
              onTap: () => _changeLanguage('en'),
            ),
          ]),
        ),

        // ── АДМІН ─────────────────────────────────────────────
        if (_isAdmin) ...[
          _sectionHeader(t("АДМІН-ПАНЕЛЬ", "ADMIN PANEL"), icon: const VerifiedBadge(size: 13)),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Expanded(
                child: GlassInput(
                  controller: _verifySearchController,
                  hintText: t("Пошук користувача...", "Search user..."),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_.\-]'))],
                ),
              ),
              const SizedBox(width: 10),
              ElegantButton(text: t("ЗНАЙТИ", "FIND"), onPressed: _searchUsersForVerify),
            ]),
          ),
          if (_verifyResults.isNotEmpty) ...[
            const SizedBox(height: 12),
            GlassContainer(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: _verifyResults.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final user = entry.value;
                  final isVerified = user['isVerified'] == 1;
                  return Column(children: [
                    ListTile(
                      leading: SafeAvatar(
                          avatarBase64: user['avatar'], fallbackName: user['userName'], radius: 18),
                      title: Row(children: [
                        Text(user['userName'],
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                        if (isVerified) ...[const SizedBox(width: 6), const VerifiedBadge(size: 13)],
                      ]),
                      trailing: GestureDetector(
                        onTap: () => _toggleVerification(user['userName'], isVerified),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(
                            color: isVerified
                                ? Colors.red.withValues(alpha: 0.12)
                                : const Color(0xFF1DA1F2).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(50),
                            border: Border.all(
                              color: isVerified
                                  ? Colors.red.withValues(alpha: 0.4)
                                  : const Color(0xFF1DA1F2).withValues(alpha: 0.4),
                            ),
                          ),
                          child: Text(
                            isVerified ? t('Зняти', 'Revoke') : t('Верифікувати', 'Verify'),
                            style: TextStyle(
                              color: isVerified ? Colors.red : const Color(0xFF1DA1F2),
                              fontSize: 12, fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (idx != _verifyResults.length - 1) _divider(),
                  ]);
                }).toList(),
              ),
            ),
          ],
        ],

        // ── ВИЙТИ ─────────────────────────────────────────────
        const SizedBox(height: 32),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GestureDetector(
            onTap: _logout,
            child: Container(
              height: 50,
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(50),
                border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
              ),
              alignment: Alignment.center,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.logout_rounded, color: Color(0xFFFF3B30), size: 18),
                const SizedBox(width: 8),
                Text(t("Вийти з акаунту", "Log Out"),
                    style: const TextStyle(color: Color(0xFFFF3B30), fontSize: 15, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text("Aether • v1.0.0",
              style: TextStyle(color: Colors.white.withValues(alpha: 0.15), fontSize: 11)),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────
  // SETTINGS HELPERS
  // ─────────────────────────────────────────────────────────
  Widget _sectionHeader(String text, {Widget? icon}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 8),
      child: Row(children: [
        if (icon != null) ...[icon, const SizedBox(width: 6)],
        Text(text,
            style: TextStyle(
              fontSize: 11, color: Colors.white.withValues(alpha: 0.4),
              fontWeight: FontWeight.w700, letterSpacing: 0.8,
            )),
      ]),
    );
  }

  Widget _divider() => Padding(
    padding: const EdgeInsets.only(left: 54),
    child: Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
  );

  Widget _settingIcon(IconData icon, Color color) {
    return Container(
      width: 32, height: 32,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
      child: Icon(icon, color: color, size: 17),
    );
  }

  Widget _settingToggle({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    required bool value,
    bool enabled = true,
    required ValueChanged<bool> onChanged,
    required Color accent,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: _settingIcon(icon, enabled ? iconColor : Colors.white24),
      title: Text(title,
          style: TextStyle(
            color: enabled ? Colors.white : Colors.white38,
            fontWeight: FontWeight.w500, fontSize: 15,
          )),
      subtitle: subtitle != null
          ? Text(subtitle,
              style: TextStyle(
                color: enabled ? Colors.white.withValues(alpha: 0.4) : Colors.white24,
                fontSize: 12,
              ))
          : null,
      trailing: Transform.scale(
        scale: 0.85,
        child: Switch(
          value: value && enabled,
          activeColor: accent,
          trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
          thumbColor: WidgetStateProperty.all(Colors.white),
          onChanged: enabled ? onChanged : null,
        ),
      ),
    );
  }

  Widget _bubbleOption(String style, String label, Color accent) {
    final isSelected = _chatBubbleStyle == style;
    return GestureDetector(
      onTap: () { setState(() => _chatBubbleStyle = style); _saveSetting('bubble_style', style); },
      child: Column(children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? accent.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
            borderRadius: style == 'rounded'
                ? BorderRadius.circular(18)
                : style == 'sharp'
                    ? BorderRadius.circular(4)
                    : BorderRadius.circular(0),
            border: Border.all(color: isSelected ? accent : Colors.white12),
          ),
          child: Text("Привіт",
              style: TextStyle(color: isSelected ? Colors.white : Colors.white54, fontSize: 12)),
        ),
        const SizedBox(height: 5),
        Text(label,
            style: TextStyle(
              color: isSelected ? accent : Colors.white38,
              fontSize: 10, fontWeight: FontWeight.w600,
            )),
      ]),
    );
  }

  // ─────────────────────────────────────────────────────────
  // MENU
  // ─────────────────────────────────────────────────────────
  Widget _buildDarkGlassMenu(int totalUnread, int totalPending) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.only(
          left: 10, right: 10,
          bottom: MediaQuery.of(context).padding.bottom + 12,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 520),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF141414).withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 30, offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Row(
                children: [
                  _menuItem(0, Icons.home_rounded, t("Чати", "Chats"), totalUnread),
                  _menuItem(1, Icons.people_rounded, t("Друзі", "Friends"), totalPending),
                  _menuItem(2, Icons.settings_rounded, t("Профіль", "Settings"), 0),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _menuItem(int index, IconData icon, String label, int badgeCount) {
    final isActive = _currentIndex == index;
    final color = isActive
        ? Colors.white.withValues(alpha: 0.95)
        : Colors.white.withValues(alpha: 0.65);

    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _currentIndex = index),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: isActive ? Colors.white.withValues(alpha: 0.12) : Colors.transparent,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Badge(
                isLabelVisible: badgeCount > 0,
                backgroundColor: Colors.white,
                textColor: Colors.black,
                label: Text('$badgeCount',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10)),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(
                    color: color, fontSize: 11,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                    height: 1,
                  )),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_isAppLocked) return _buildLockScreen();

    final totalUnread = _recentChats.fold(0, (sum, chat) => sum + ((chat['unreadCount'] ?? 0) as int));
    final totalPending = _pendingRequests.length;
    final appBarTitle = _currentIndex == 0
        ? t("Чати", "Chats")
        : (_currentIndex == 1 ? t("Друзі", "Friends") : t("Профіль", "Profile"));

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      resizeToAvoidBottomInset: false, // фікс кліку в PWA
      appBar: AppBar(
        title: Text(appBarTitle),
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(color: Colors.black.withValues(alpha: 0.5)),
          ),
        ),
        actions: _currentIndex == 0
            ? [
                Container(
                  margin: const EdgeInsets.only(right: 16),
                  child: IconButton(
                    icon: const Icon(Icons.group_add, color: Colors.white, size: 24),
                    onPressed: _showCreateGroupDialog,
                  ),
                ),
              ]
            : null,
      ),
      body: LiquidBackground(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: _currentIndex == 0
                  ? _buildChatsTab()
                  : (_currentIndex == 1 ? _buildFriendsTab() : _buildSettingsTab()),
            ),
            Positioned(
              left: 0, right: 0, bottom: 0,
              child: _buildDarkGlassMenu(totalUnread, totalPending),
            ),
          ],
        ),
      ),
    );
  }
}