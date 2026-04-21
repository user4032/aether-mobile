import 'dart:convert';
import 'dart:async';
import 'dart:ui';
import 'dart:math' show pi, sqrt, cos, sin;
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
import 'main_gate.dart';

// ─── DESIGN TOKENS ────────────────────────────────────────────────────────────
class _D {
  static const bg0 = Color(0xFF000000);
  static const bg1 = Color(0xFF0A0A0A);
  static const bg2 = Color(0xFF111111);
  static const bg3 = Color(0xFF1A1A1A);
  static const border = Color(0xFF1A1A1A);
  static const borderMid = Color(0xFF222222);
  static const textPrimary = Color(0xFFEDEDED);
  static const textSecondary = Color(0xFF888888);
  static const textMuted = Color(0xFF444444);
  static const accent = Color(0xFF00A0FF);
  static const danger = Color(0xFFFF3B30);
  static const mono = 'monospace';
}

class ContactsScreen extends StatefulWidget {
  final String deviceId, userName, publicKey;
  const ContactsScreen({super.key, required this.deviceId, required this.userName, required this.publicKey});
  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  int _currentIndex = 0;
  late io.Socket _bgSocket;
  final AudioPlayer _audioPlayer = AudioPlayer();
  final ImagePicker _picker = ImagePicker();
  final AesGcm _aes = AesGcm.with256bits();
  bool _isSearching = false;
  String _searchQuery = '';
  String _activeFilter = 'all';

  List<Map<String, dynamic>> _recentChats = [];
  List<Map<String, dynamic>> _friends = [];
  List<Map<String, dynamic>> _pendingRequests = [];
  String? _myAvatar;
  String _myBio = '';
  bool _myVerified = false;
  bool get _isAdmin => widget.userName == kAdminUsername;

  final _addFriendController = TextEditingController();
  final _searchController = TextEditingController();
  final _verifySearchController = TextEditingController();
  List<Map<String, dynamic>> _verifyResults = [];
  Map<String, dynamic>? _selectedDesktopChat;

  // — Settings active —
  double _chatFontSize = 15.0;
  bool _compactMode = false;
  bool _animationsEnabled = true;
  bool _sendWithEnter = true;
  bool _use24hFormat = true;
  bool _showSeconds = false;
  bool _soundEnabled = true;
  bool _desktopNotifications = true;
  bool _showPreviews = true;
  bool _onlineStatus = true;
  bool _readReceipts = true;
  bool _typingIndicator = true;
  bool _autoDownloadMedia = true;
  bool _saveToGallery = false;
  int _autoLockTimeout = 0;

  // — Settings saved —
  double _sChatFontSize = 15.0;
  bool _sCompactMode = false;
  bool _sAnimationsEnabled = true;
  bool _sSendWithEnter = true;
  bool _sUse24hFormat = true;
  bool _sShowSeconds = false;
  bool _sSoundEnabled = true;
  bool _sDesktopNotifications = true;
  bool _sShowPreviews = true;
  bool _sOnlineStatus = true;
  bool _sReadReceipts = true;
  bool _sTypingIndicator = true;
  bool _sAutoDownloadMedia = true;
  bool _sSaveToGallery = false;
  int _sAutoLockTimeout = 0;

  bool _hasUnsavedSettings = false;
  bool _isCacheAvailable = false;

  // — Lock —
  bool _isAppLocked = false;
  bool _passwordEnabled = false;
  late TextEditingController _passwordController;
  DateTime? _lastPausedTime;

  // ─ NEW: Animation & UI state ─────────────────────────────────────────────
  late AnimationController _listAnimController;
  late AnimationController _cmdPaletteController;
  bool _commandPaletteOpen = false;
  bool _isLoadingChats = true;
  final FocusNode _rootFocusNode = FocusNode();
  final TextEditingController _cmdController = TextEditingController();
  String _cmdQuery = '';
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _passwordController = TextEditingController();
    _searchController.addListener(_onSearchChanged);
    WidgetsBinding.instance.addObserver(this);
    _initLockState();
    _loadSettings();
    _loadCache();

    // NEW controllers
    _listAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _cmdPaletteController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _cmdController.addListener(() => setState(() => _cmdQuery = _cmdController.text));

    _bgSocket = io.io('https://aether-backend-hrmq.onrender.com',
        {'transports': ['websocket'], 'forceNew': true});
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
          if (_soundEnabled) _audioPlayer.play(AssetSource('ding.mp3'));
        }
        _loadData();
      }
    });
    _bgSocket.on('refresh_chats', (data) {
      if (data['userName'] == widget.userName || data['userName'] == 'all') {
        _loadData();
      }
    });
    _bgSocket.on('messages_read', (data) => _loadData());
    _bgSocket.on('friends_data', (data) {
      if (mounted) {
        setState(() {
          _myAvatar = data['myAvatar'];
          _myBio = data['myBio'] ?? '';
          _myVerified = data['isVerified'] == true;
          _friends = List<Map<String, dynamic>>.from(data['friends']);
          _pendingRequests = List<Map<String, dynamic>>.from(data['pending']);
        });
      }
      _saveCache();
    });
  }

  @override
  void dispose() {
    _listAnimController.dispose();
    _cmdPaletteController.dispose();
    _cmdController.dispose();
    _rootFocusNode.dispose();
    _passwordController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    currentActiveChat = null;
    _bgSocket.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  // ─── CACHE ────────────────────────────────────────────────────────────────
  Future<void> _checkCacheStatus() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _isCacheAvailable =
          prefs.containsKey('cache_chats_${widget.userName}') ||
          prefs.containsKey('cache_friends_${widget.userName}'));
    }
  }

  Future<void> _loadCache() async {
    final prefs = await SharedPreferences.getInstance();
    final chatsJson = prefs.getString('cache_chats_${widget.userName}');
    final friendsJson = prefs.getString('cache_friends_${widget.userName}');
    if (chatsJson != null && mounted) {
      setState(() => _recentChats = List<Map<String, dynamic>>.from(jsonDecode(chatsJson)));
    }
    if (friendsJson != null && mounted) {
      setState(() => _friends = List<Map<String, dynamic>>.from(jsonDecode(friendsJson)));
    }
    _checkCacheStatus();
  }

  Future<void> _saveCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cache_chats_${widget.userName}', jsonEncode(_recentChats));
    await prefs.setString('cache_friends_${widget.userName}', jsonEncode(_friends));
    _checkCacheStatus();
  }

  Future<void> _clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('cache_chats_${widget.userName}');
    await prefs.remove('cache_friends_${widget.userName}');
    _checkCacheStatus();
    _showTopRightSnack(t('Кеш успішно очищено', 'Cache cleared successfully'));
  }

  // ─── SETTINGS ─────────────────────────────────────────────────────────────
  void _checkUnsaved() {
    _hasUnsavedSettings = _chatFontSize != _sChatFontSize ||
        _compactMode != _sCompactMode || _animationsEnabled != _sAnimationsEnabled ||
        _sendWithEnter != _sSendWithEnter || _use24hFormat != _sUse24hFormat ||
        _showSeconds != _sShowSeconds || _soundEnabled != _sSoundEnabled ||
        _desktopNotifications != _sDesktopNotifications || _showPreviews != _sShowPreviews ||
        _onlineStatus != _sOnlineStatus || _readReceipts != _sReadReceipts ||
        _typingIndicator != _sTypingIndicator || _autoDownloadMedia != _sAutoDownloadMedia ||
        _saveToGallery != _sSaveToGallery || _autoLockTimeout != _sAutoLockTimeout;
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
      _sChatFontSize = _chatFontSize = prefs.getDouble('chat_font_size') ?? 15.0;
      _sCompactMode = _compactMode = prefs.getBool('compact_mode') ?? false;
      _sAnimationsEnabled = _animationsEnabled = prefs.getBool('animations_enabled') ?? true;
      _sSendWithEnter = _sendWithEnter = prefs.getBool('send_with_enter') ?? true;
      _sUse24hFormat = _use24hFormat = prefs.getBool('use_24h_format') ?? true;
      _sShowSeconds = _showSeconds = prefs.getBool('show_seconds') ?? false;
      _sSoundEnabled = _soundEnabled = prefs.getBool('sound_enabled') ?? true;
      _sDesktopNotifications = _desktopNotifications = prefs.getBool('desktop_notifications') ?? true;
      _sShowPreviews = _showPreviews = prefs.getBool('show_previews') ?? true;
      _sOnlineStatus = _onlineStatus = prefs.getBool('online_status') ?? true;
      _sReadReceipts = _readReceipts = prefs.getBool('read_receipts') ?? true;
      _sTypingIndicator = _typingIndicator = prefs.getBool('typing_indicator') ?? true;
      _sAutoDownloadMedia = _autoDownloadMedia = prefs.getBool('auto_download_media') ?? true;
      _sSaveToGallery = _saveToGallery = prefs.getBool('save_to_gallery') ?? false;
      _sAutoLockTimeout = _autoLockTimeout = prefs.getInt('auto_lock_timeout') ?? 0;
      _hasUnsavedSettings = false;
      });
    }
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('chat_font_size', _chatFontSize);
    await prefs.setBool('compact_mode', _compactMode);
    await prefs.setBool('animations_enabled', _animationsEnabled);
    await prefs.setBool('send_with_enter', _sendWithEnter);
    await prefs.setBool('use_24h_format', _use24hFormat);
    await prefs.setBool('show_seconds', _showSeconds);
    await prefs.setBool('sound_enabled', _soundEnabled);
    await prefs.setBool('desktop_notifications', _desktopNotifications);
    await prefs.setBool('show_previews', _showPreviews);
    await prefs.setBool('online_status', _onlineStatus);
    await prefs.setBool('read_receipts', _readReceipts);
    await prefs.setBool('typing_indicator', _typingIndicator);
    await prefs.setBool('auto_download_media', _autoDownloadMedia);
    await prefs.setBool('save_to_gallery', _saveToGallery);
    await prefs.setInt('auto_lock_timeout', _autoLockTimeout);
    if (mounted) {
      setState(() {
      _sChatFontSize = _chatFontSize; _sCompactMode = _compactMode;
      _sAnimationsEnabled = _animationsEnabled; _sSendWithEnter = _sendWithEnter;
      _sUse24hFormat = _use24hFormat; _sShowSeconds = _showSeconds;
      _sSoundEnabled = _soundEnabled; _sDesktopNotifications = _desktopNotifications;
      _sShowPreviews = _showPreviews; _sOnlineStatus = _onlineStatus;
      _sReadReceipts = _readReceipts; _sTypingIndicator = _typingIndicator;
      _sAutoDownloadMedia = _autoDownloadMedia; _sSaveToGallery = _saveToGallery;
      _sAutoLockTimeout = _autoLockTimeout; _hasUnsavedSettings = false;
      });
    }
    _bgSocket.emit('set_active', {'userName': widget.userName, 'deviceId': widget.deviceId, 'onlineStatus': _onlineStatus});
    _showTopRightSnack(t('Налаштування збережено', 'Settings saved'));
  }

  void _revertSettings() {
    setState(() {
      _chatFontSize = _sChatFontSize; _compactMode = _sCompactMode;
      _animationsEnabled = _sAnimationsEnabled; _sendWithEnter = _sSendWithEnter;
      _use24hFormat = _sUse24hFormat; _showSeconds = _sShowSeconds;
      _soundEnabled = _sSoundEnabled; _desktopNotifications = _sDesktopNotifications;
      _showPreviews = _sShowPreviews; _onlineStatus = _sOnlineStatus;
      _readReceipts = _sReadReceipts; _typingIndicator = _sTypingIndicator;
      _autoDownloadMedia = _sAutoDownloadMedia; _saveToGallery = _sSaveToGallery;
      _autoLockTimeout = _sAutoLockTimeout; _hasUnsavedSettings = false;
    });
  }

  // ignore: unused_element
  void _resetSettings() {
    setState(() {
      _chatFontSize = 15.0; _compactMode = false; _animationsEnabled = true;
      _sendWithEnter = true; _use24hFormat = true; _showSeconds = false;
      _soundEnabled = true; _desktopNotifications = true; _showPreviews = true;
      _onlineStatus = true; _readReceipts = true; _typingIndicator = true;
      _autoDownloadMedia = true; _saveToGallery = false; _autoLockTimeout = 0;
      _checkUnsaved();
    });
  }

  // ─── LOCK ─────────────────────────────────────────────────────────────────
  Future<void> _initLockState() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('password_enabled') ?? false) {
      setState(() { _passwordEnabled = true; _isAppLocked = true; });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _lastPausedTime = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      if (_passwordEnabled && _lastPausedTime != null) {
        if (DateTime.now().difference(_lastPausedTime!).inSeconds >= _autoLockTimeout) {
          _passwordController.clear();
          setState(() => _isAppLocked = true);
        }
      }
    }
  }

  Future<void> _unlockWithPassword() async {
    if (_passwordController.text.isEmpty) { HapticFeedback.heavyImpact(); return; }
    final savedPassword = await const FlutterSecureStorage().read(key: 'app_password');
    if (_passwordController.text == savedPassword) {
      _passwordController.clear();
      setState(() => _isAppLocked = false);
      _showTopRightSnack(t('Розблоковано', 'Unlocked'));
    } else {
      _passwordController.clear();
      HapticFeedback.heavyImpact();
      _showTopRightSnack(t('Неправильний пароль', 'Incorrect password'));
    }
  }

  Future<void> _togglePasswordLock(bool enabled) async {
    if (enabled) {
      _showSetPasswordDialog();
    } else {
      await const FlutterSecureStorage().delete(key: 'app_password');
      await (await SharedPreferences.getInstance()).setBool('password_enabled', false);
      if (mounted) {
        setState(() => _passwordEnabled = false);
        _showTopRightSnack(t('Пароль вимкнено', 'Password protection disabled'));
      }
    }
  }

  void _showSetPasswordDialog() {
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    bool isConfirming = false;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateSB) => Dialog(
          backgroundColor: _D.bg2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: _D.border)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(isConfirming ? t('Підтвердіть пароль', 'Confirm password') : t('Встановити пароль', 'Set password'),
                    style: const TextStyle(color: _D.textPrimary, fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text(t('Захист від несанкціонованого доступу', 'Protect against unauthorized access'),
                    style: const TextStyle(color: _D.textSecondary, fontSize: 13)),
                const SizedBox(height: 20),
                _MinimalTextField(
                  controller: isConfirming ? confirmController : passwordController,
                  hint: isConfirming ? t('Повторіть пароль', 'Repeat password') : t('Пароль', 'Password'),
                  obscure: true,
                ),
                const SizedBox(height: 16),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  TextButton(onPressed: () { passwordController.dispose(); confirmController.dispose(); Navigator.pop(context); },
                    child: Text(t('Скасувати', 'Cancel'), style: const TextStyle(color: _D.textSecondary))),
                  const SizedBox(width: 8),
                  _PillButton(
                    label: isConfirming ? t('Готово', 'Done') : t('Далі', 'Next'),
                    onTap: () async {
                      if (!isConfirming) {
                        if (passwordController.text.isEmpty) { _showTopRightSnack(t('Введіть пароль', 'Enter a password')); return; }
                        confirmController.clear();
                        setStateSB(() => isConfirming = true);
                      } else {
                        if (passwordController.text == confirmController.text) {
                          await const FlutterSecureStorage().write(key: 'app_password', value: passwordController.text);
                          await (await SharedPreferences.getInstance()).setBool('password_enabled', true);
                          if (mounted) {
                            setState(() => _passwordEnabled = true);
                            passwordController.dispose();
                            confirmController.dispose();
                            if (context.mounted) {
                              Navigator.pop(context);
                            }
                            _showTopRightSnack(t('Пароль встановлено', 'Password set successfully'));
                          }
                        } else {
                          _showTopRightSnack(t('Паролі не співпадають', 'Passwords do not match'));
                          confirmController.clear();
                          setStateSB(() => isConfirming = false);
                        }
                      }
                    },
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── CRYPTO ───────────────────────────────────────────────────────────────
  Future<SecretKey> _getSecretKey(String remotePub, bool isGroup) async {
    if (isGroup) {
      final hash = await Sha256().hash(utf8.encode(remotePub));
      return await _aes.newSecretKeyFromBytes(hash.bytes);
    } else {
      final priv = await const FlutterSecureStorage().read(key: 'private_key');
      final secret = await X25519().sharedSecretKey(
        keyPair: SimpleKeyPairData(base64Decode(priv!), publicKey: SimplePublicKey(base64Decode(widget.publicKey), type: KeyPairType.x25519), type: KeyPairType.x25519),
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
    } catch (e) { return 'Encrypted'; }
  }

  // ─── DATA ─────────────────────────────────────────────────────────────────
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
            chat['decryptedText'] = t('Голосове повідомлення', 'Voice message');
          } else if (msgType == 'image') {
            chat['decryptedText'] = t('Фотографія', 'Image');
          } else if (m['ciphertext'] != null && chat['publicKey'] != null) {
            String dec = await _decrypt(m['ciphertext'], m['nonce'], m['mac'], chat['publicKey'], chat['isGroup'] == true);
            try {
              chat['decryptedText'] = dec.startsWith('{') && dec.endsWith('}') ? jsonDecode(dec)['text'] : dec;
            } catch (e) { chat['decryptedText'] = t('🔒 Повідомлення зашифровано', '🔒 Encrypted'); }
          } else {
            chat['decryptedText'] = m['text'] ?? t('Повідомлення', 'Message');
          }
          if (m['senderName'] == widget.userName) {
            chat['decryptedText'] = "${t('Ви', 'You')}: ${chat['decryptedText']}";
          } else if (chat['isGroup'] == true) {
            chat['decryptedText'] = "${m['senderName']}: ${chat['decryptedText']}";
          }
        }
      }
      tempChats.removeWhere((c) => c['isHidden'] == true);
      if (mounted) {
        setState(() { _recentChats = tempChats; _isLoadingChats = false; });
        _listAnimController.forward(from: 0); // стагер-анімація
        _saveCache();
      }
    });
    _bgSocket.emit('get_friends_data', widget.userName);
  }

  Future<void> _updateAvatar() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 50, maxWidth: 500, maxHeight: 500);
    if (image == null || !mounted) return;
    final base64String = base64Encode(await image.readAsBytes());
    setState(() => _myAvatar = base64String);
    _bgSocket.emit('update_avatar', {'userName': widget.userName, 'avatar': base64String});
    _loadData();
  }

  void _sendFriendRequest() {
    final target = _addFriendController.text.trim();
    if (target.isEmpty) return;
    _bgSocket.emitWithAck('send_friend_request', {'requester': widget.userName, 'receiver': target}, ack: (dynamic data) {
      if (mounted) { _showTopRightSnack(data['message']); _addFriendController.clear(); }
    });
  }

  void _respondToRequest(String requester, String action) {
    _bgSocket.emit('respond_friend_request', {'requester': requester, 'receiver': widget.userName, 'action': action});
    _loadData();
  }

  void _logout() async {
    await (await SharedPreferences.getInstance()).remove('user_name');
    if (mounted) Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (context) => const MainGate()), (r) => false);
  }

  // ignore: unused_element
  void _changeLanguage(String newLang) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lang', newLang);
    setState(() { lang = newLang; });
    _loadData();
  }

  void _searchUsersForVerify() {
    final q = _verifySearchController.text.trim();
    if (q.isEmpty) return;
    _bgSocket.emitWithAck('search_users_for_verify', {'adminName': widget.userName, 'query': q}, ack: (dynamic data) {
      if (mounted) setState(() => _verifyResults = List<Map<String, dynamic>>.from(data));
    });
  }

  void _toggleVerification(String targetName, bool currentlyVerified) {
    final event = currentlyVerified ? 'revoke_verification' : 'grant_verification';
    _bgSocket.emitWithAck(event, {'adminName': widget.userName, 'targetName': targetName}, ack: (dynamic data) {
      if (context.mounted) {
        _showTopRightSnack(data['success']
            ? (currentlyVerified ? t('Верифікацію знято', 'Verification revoked') : t('Верифіковано!', 'Verified!'))
            : (data['message'] ?? 'Error'));
        _searchUsersForVerify();
      }
    });
  }

  // ─── NEW: COMMAND PALETTE ─────────────────────────────────────────────────
  void _openCommandPalette() {
    _cmdController.clear();
    setState(() => _commandPaletteOpen = true);
    showDialog(
      context: context,
      builder: (context) => _buildCommandPaletteOverlay(),
      barrierColor: Colors.black.withValues(alpha: 0.7),
      barrierDismissible: true,
    ).then((_) {
      if (mounted) setState(() => _commandPaletteOpen = false);
    });
  }

  void _closeCommandPalette() {
    Navigator.of(context).pop();
  }

  // ─── NEW: KEYBOARD SHORTCUTS ──────────────────────────────────────────────
  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final isCtrl = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyK) {
      _commandPaletteOpen ? _closeCommandPalette() : _openCommandPalette();
    }
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.digit1) setState(() => _currentIndex = 0);
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.digit2) setState(() => _currentIndex = 1);
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.digit3) setState(() => _currentIndex = 2);
    if (event.logicalKey == LogicalKeyboardKey.escape && _commandPaletteOpen) _closeCommandPalette();
  }

  // ─── NOTIFICATION ─────────────────────────────────────────────────────────
  void _showTopRightSnack(String msg) {
    if (!mounted) return;
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => Positioned(
        top: 24, right: 24,
        child: Material(
          color: Colors.transparent,
          child: _ToastWidget(msg: msg),
        ),
      ),
    );
    overlay.insert(entry);
    Future.delayed(const Duration(seconds: 3), () { if (mounted) entry.remove(); });
  }

  void _showSnack(String msg) => _showTopRightSnack(msg);

  // ─── DIALOGS ──────────────────────────────────────────────────────────────
  void _showEditBioDialog() {
    final bioController = TextEditingController(text: _myBio);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.transparent, contentPadding: EdgeInsets.zero,
        content: GlassContainer(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(t('Про себе', 'About'), style: const TextStyle(color: _D.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            TextField(controller: bioController, maxLength: 100, maxLines: null,
              style: const TextStyle(color: _D.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: t('Напишіть щось...', 'Write something...'),
                hintStyle: const TextStyle(color: _D.textMuted),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _D.border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _D.border)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _D.borderMid)),
                filled: true, fillColor: _D.bg2,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                counterStyle: const TextStyle(color: _D.textMuted, fontSize: 11),
              )),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(onPressed: () => Navigator.pop(context), child: Text(t('Скасувати', 'Cancel'), style: const TextStyle(color: _D.textSecondary))),
              const SizedBox(width: 8),
              _PillButton(label: t('Зберегти', 'Save'), onTap: () {
                _bgSocket.emit('update_bio', {'userName': widget.userName, 'bio': bioController.text.trim()});
                setState(() => _myBio = bioController.text.trim());
                Navigator.pop(context);
              }),
            ]),
          ]),
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
          backgroundColor: Colors.transparent, contentPadding: EdgeInsets.zero,
          content: GlassContainer(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t('Експорт акаунта', 'Export Account'), style: const TextStyle(color: _D.textPrimary, fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: const Color(0xFF1A0000), borderRadius: BorderRadius.circular(6), border: Border.all(color: _D.danger.withValues(alpha: 0.3))),
                child: Text(t('Якщо ви забудете пароль — відновлення неможливе.', 'If you lose the password, recovery is impossible.'), style: const TextStyle(color: _D.danger, fontSize: 12)),
              ),
              const SizedBox(height: 20),
              if (backupToken == null) ...[
                _MinimalTextField(controller: passwordController, hint: t('Придумайте пароль', 'Create password'), obscure: true),
                const SizedBox(height: 16),
                _PillButton(label: t('Згенерувати ключ', 'Generate Backup'), onTap: () async {
                  if (passwordController.text.trim().isEmpty) return;
                  try {
                    final priv = await const FlutterSecureStorage().read(key: 'private_key');
                    final payloadStr = jsonEncode({'priv': priv, 'pub': widget.publicKey, 'dev': widget.deviceId, 'name': widget.userName});
                    final passHash = await Sha256().hash(utf8.encode(passwordController.text.trim()));
                    final key = await _aes.newSecretKeyFromBytes(passHash.bytes);
                    final box = await _aes.encrypt(utf8.encode(payloadStr), secretKey: key);
                    setStateSB(() => backupToken = '${base64Encode(box.nonce)}.${base64Encode(box.cipherText)}.${base64Encode(box.mac.bytes)}');
                  } catch (e) { _showSnack('Encryption error'); }
                }),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: _D.bg3, borderRadius: BorderRadius.circular(6), border: Border.all(color: _D.border)),
                  child: SelectableText(backupToken!, style: const TextStyle(color: _D.textPrimary, fontSize: 10, fontFamily: _D.mono)),
                ),
                const SizedBox(height: 12),
                _PillButton(label: t('Скопіювати ключ', 'Copy Backup Key'), onTap: () {
                  Clipboard.setData(ClipboardData(text: backupToken!));
                  _showSnack(t('Скопійовано', 'Copied'));
                  Navigator.pop(context);
                }),
              ],
              if (backupToken == null) ...[
                const SizedBox(height: 8),
                TextButton(onPressed: () => Navigator.pop(context), child: Text(t('Скасувати', 'Cancel'), style: const TextStyle(color: _D.textSecondary))),
              ],
            ]),
          ),
        ),
      ),
    );
  }

  // ─── LOCK SCREEN ──────────────────────────────────────────────────────────
  Widget _buildLockScreen() {
    return Scaffold(
      backgroundColor: _D.bg0,
      body: Stack(children: [
        Positioned(top: -100, left: -80, child: Container(width: 300, height: 300,
            decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [Colors.purple.withValues(alpha: 0.12), Colors.transparent])))),
        Positioned(bottom: -120, right: -100, child: Container(width: 350, height: 350,
            decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [_D.accent.withValues(alpha: 0.08), Colors.transparent])))),
        SafeArea(
          child: Center(
            child: SingleChildScrollView(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(width: 80, height: 80,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: _D.bg2, border: Border.all(color: _D.border, width: 1)),
                  child: const Icon(Icons.lock_outline, size: 36, color: _D.textSecondary)),
                const SizedBox(height: 32),
                Text(t('Додаток заблокований', 'App locked'), style: const TextStyle(color: _D.textPrimary, fontSize: 24, fontWeight: FontWeight.w600, letterSpacing: -0.5)),
                const SizedBox(height: 8),
                Text(t('Введіть пароль для доступу', 'Enter your password to unlock'), style: const TextStyle(color: _D.textSecondary, fontSize: 14)),
                const SizedBox(height: 40),
                SizedBox(width: 260, child: _MinimalTextField(controller: _passwordController, hint: t('Пароль', 'Password'), obscure: true, onSubmit: (_) => _unlockWithPassword())),
                const SizedBox(height: 12),
                _PillButton(label: t('Розблокувати', 'Unlock'), onTap: _unlockWithPassword),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  // ─── CREATE GROUP ─────────────────────────────────────────────────────────
  void _showCreateGroupDialog() {
    if (_friends.isEmpty) { _showSnack(t('Спочатку додайте друзів!', 'Add friends first!')); return; }
    final groupNameController = TextEditingController();
    List<String> selectedFriends = [];
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: _D.bg2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: _D.border)),
        child: StatefulBuilder(
          builder: (context, setStateSB) => Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t('Створити групу', 'Create Group'), style: const TextStyle(color: _D.textPrimary, fontWeight: FontWeight.w600, fontSize: 17)),
              const SizedBox(height: 16),
              _MinimalTextField(controller: groupNameController, hint: t('Назва групи', 'Group name')),
              const SizedBox(height: 16),
              Text(t('Учасники', 'Members'), style: const TextStyle(color: _D.textSecondary, fontSize: 12, fontWeight: FontWeight.w500, letterSpacing: 0.5)),
              const SizedBox(height: 8),
              SizedBox(height: 160, child: Theme(data: ThemeData.dark(), child: ListView.builder(
                itemCount: _friends.length,
                itemBuilder: (context, index) {
                  final friend = _friends[index]['userName'];
                  return CheckboxListTile(
                    contentPadding: EdgeInsets.zero, dense: true,
                    title: Text(friend, style: const TextStyle(color: _D.textPrimary, fontSize: 14)),
                    value: selectedFriends.contains(friend),
                    activeColor: _D.textPrimary, checkColor: _D.bg0,
                    side: const BorderSide(color: _D.textMuted),
                    checkboxShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    onChanged: (val) => setStateSB(() {
                      if (val == true) {
                        selectedFriends.add(friend);
                      } else {
                        selectedFriends.remove(friend);
                      }
                    }),
                  );
                },
              ))),
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(onPressed: () => Navigator.pop(context), child: Text(t('Скасувати', 'Cancel'), style: const TextStyle(color: _D.textSecondary))),
                const SizedBox(width: 8),
                _PillButton(label: t('Створити', 'Create'), onTap: () {
                  if (groupNameController.text.trim().isNotEmpty && selectedFriends.isNotEmpty) {
                    _bgSocket.emitWithAck('create_group', {'name': groupNameController.text.trim(), 'participants': selectedFriends, 'creator': widget.userName}, ack: (dynamic data) { if (data['success'] == true) _loadData(); });
                    Navigator.pop(context);
                  }
                }),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  // ─── USER PROFILE ─────────────────────────────────────────────────────────
  void _showUserProfile(String partnerName, String? initialAvatar, String? publicKey, bool isGroup) {
    if (isGroup || partnerName == widget.userName) return;
    String? currentBio;
    String? currentAvatar = initialAvatar;
    bool isVerifiedUser = false;
    bool fetched = false;

    Widget buildContent(BuildContext context, StateSetter setStateSB) {
      Map<String, dynamic>? chatSettings;
      try { chatSettings = _recentChats.firstWhere((c) => c['partnerName'] == partnerName); } catch (e) { /**/ }
      bool isBlocked = chatSettings?['isBlocked'] == true;

      if (!fetched) {
        fetched = true;
        _bgSocket.emitWithAck('get_user_profile', partnerName, ack: (dynamic data) {
          if (data['success'] == true && mounted) {
            setStateSB(() {
              currentBio = data['bio'];
              currentAvatar = data['avatar'] ?? currentAvatar;
              isVerifiedUser = data['isVerified'] == true;
            });
          }
        });
      }

      return Container(
        width: LumynTheme.isDesktop(context) ? 360 : double.infinity,
        height: double.infinity,
        color: _D.bg1,
        child: Column(children: [
          Container(height: 56, padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _D.border))),
            child: Row(children: [
              Text(t('Профіль', 'Profile'), style: const TextStyle(color: _D.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
              const Spacer(),
              IconButton(icon: const Icon(Icons.close, color: _D.textSecondary, size: 18), onPressed: () => Navigator.pop(context), hoverColor: _D.bg3, splashRadius: 16),
            ])),
          Expanded(child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20), child: Column(children: [
              Container(width: 96, height: 96,
                decoration: BoxDecoration(shape: BoxShape.circle, color: _getColorFromName(partnerName).withValues(alpha: 0.15)),
                child: SafeAvatar(avatarBase64: currentAvatar, fallbackName: partnerName, radius: 44)),
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Flexible(child: Text(partnerName, style: const TextStyle(color: _D.textPrimary, fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.5), textAlign: TextAlign.center, overflow: TextOverflow.ellipsis)),
                if (isVerifiedUser) ...[const SizedBox(width: 6), const VerifiedBadge(size: 16, color: Colors.white)],
              ]),
              const SizedBox(height: 4),
              Text('@$partnerName', style: const TextStyle(color: _D.textSecondary, fontSize: 13, fontFamily: _D.mono)),
              if (currentBio != null && currentBio!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: _D.bg2, border: Border.all(color: _D.border), borderRadius: BorderRadius.circular(8)),
                  child: Text(currentBio!, textAlign: TextAlign.center, style: const TextStyle(color: _D.textPrimary, fontSize: 13, height: 1.5))),
              ],
            ])),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(children: [
              Expanded(child: _ActionButton(label: t('Написати', 'Message'), icon: Icons.send, primary: true, onTap: () { Navigator.pop(context); _startChat(partnerName, publicKey); })),
              const SizedBox(width: 8),
              Expanded(child: _ActionButton(label: t('Дзвінок', 'Call'), icon: Icons.phone, onTap: () => _showTopRightSnack(t('Незабаром', 'Coming soon')))),
            ])),
            const SizedBox(height: 20),
            const Divider(height: 1, color: _D.border),
            Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 6), child: Text(t('ДІЇ', 'ACTIONS'), style: const TextStyle(color: _D.textMuted, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.8))),
            _ProfileActionRow(icon: isBlocked ? Icons.lock_open : Icons.block, label: isBlocked ? t('Розблокувати', 'Unblock') : t('Заблокувати', 'Block'), danger: !isBlocked, onTap: () {
              _bgSocket.emit('update_chat_settings', {'userName': widget.userName, 'partnerName': partnerName, 'isPinned': chatSettings?['isPinned'] ?? false, 'isHidden': chatSettings?['isHidden'] == true, 'isDeleted': false, 'isBlocked': !isBlocked});
              setStateSB(() { isBlocked = !isBlocked; });
              _loadData();
            }),
            _ProfileActionRow(icon: Icons.cleaning_services_rounded, label: t('Очистити історію', 'Clear History'), danger: true, onTap: () {
              _bgSocket.emit('update_chat_settings', {'userName': widget.userName, 'partnerName': partnerName, 'isPinned': false, 'isHidden': false, 'isDeleted': true, 'isBlocked': isBlocked});
              Navigator.pop(context); _showTopRightSnack(t('Очищено', 'Cleared'));
            }),
            _ProfileActionRow(icon: Icons.delete_outline_rounded, label: t('Видалити чат', 'Delete Chat'), danger: true, onTap: () {
              _bgSocket.emit('update_chat_settings', {'userName': widget.userName, 'partnerName': partnerName, 'isPinned': false, 'isHidden': false, 'isDeleted': true, 'isBlocked': isBlocked});
              Navigator.pop(context);
              if (_selectedDesktopChat?['targetName'] == partnerName) setState(() => _selectedDesktopChat = null);
            }),
            const SizedBox(height: 20),
          ]))),
        ]),
      );
    }

    if (LumynTheme.isDesktop(context)) {
      showGeneralDialog(context: context, barrierDismissible: true, barrierLabel: 'Close', barrierColor: Colors.black.withValues(alpha: 0.4),
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (context, a1, a2) => Align(alignment: Alignment.centerRight, child: Material(color: Colors.transparent, child: StatefulBuilder(builder: (c, setS) => buildContent(c, setS)))),
        transitionBuilder: (context, a1, a2, child) => SlideTransition(position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(CurvedAnimation(parent: a1, curve: Curves.easeOutCubic)), child: child),
      );
    } else {
      showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
        builder: (c) => StatefulBuilder(builder: (c, setS) => ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(16)), child: SizedBox(height: MediaQuery.of(context).size.height * 0.85, child: buildContent(c, setS)))));
    }
  }

  void _showChatOptions(Map<String, dynamic> chat) {
    showModalBottomSheet(
      context: context, backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) => Container(
        decoration: const BoxDecoration(color: _D.bg2, borderRadius: BorderRadius.vertical(top: Radius.circular(16)), border: Border(top: BorderSide(color: _D.border))),
        child: SafeArea(child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 36, height: 3, margin: const EdgeInsets.only(bottom: 16), decoration: BoxDecoration(color: _D.textMuted, borderRadius: BorderRadius.circular(2))),
            _SheetAction(icon: chat['isPinned'] == true ? Icons.push_pin : Icons.push_pin_outlined, label: chat['isPinned'] == true ? t('Відкріпити', 'Unpin') : t('Закріпити', 'Pin'), onTap: () { Navigator.pop(context); _bgSocket.emit('update_chat_settings', {'userName': widget.userName, 'partnerName': chat['partnerName'], 'isPinned': !(chat['isPinned'] == true), 'isHidden': chat['isHidden'] == true, 'isDeleted': false, 'isBlocked': chat['isBlocked'] == true}); }),
            _SheetAction(icon: Icons.visibility_off_outlined, label: t('Приховати чат', 'Hide Chat'), subtitle: t('Знайти через пошук', 'Find via search'), onTap: () { Navigator.pop(context); _bgSocket.emit('update_chat_settings', {'userName': widget.userName, 'partnerName': chat['partnerName'], 'isPinned': chat['isPinned'] == true, 'isHidden': true, 'isDeleted': false, 'isBlocked': chat['isBlocked'] == true}); }),
            _SheetAction(icon: Icons.delete_outline, label: t('Видалити чат', 'Delete Chat'), danger: true, onTap: () { Navigator.pop(context); _bgSocket.emit('update_chat_settings', {'userName': widget.userName, 'partnerName': chat['partnerName'], 'isPinned': false, 'isHidden': false, 'isDeleted': true, 'isBlocked': chat['isBlocked'] == true}); }),
          ]),
        )),
      ),
    );
  }

  void _startChat(String targetName, String? targetKey, {String? targetAvatar, bool isVerified = false}) {
    if (targetName.isEmpty) return;
    if (targetKey != null) { _openChatScreen(targetName, targetKey, avatar: targetAvatar, isVerified: isVerified); return; }
    setState(() => _isSearching = true);
    _bgSocket.emitWithAck('get_key', targetName, ack: (dynamic response) {
      if (mounted) setState(() => _isSearching = false);
      if (response['success'] == true) {
        _bgSocket.emit('update_chat_settings', {'userName': widget.userName, 'partnerName': targetName, 'isPinned': false, 'isHidden': false, 'isDeleted': false, 'isBlocked': false});
        _openChatScreen(targetName, response['publicKey'], avatar: response['avatar'], isVerified: response['isVerified'] == true);
      } else if (mounted) { _showTopRightSnack(response['message'] ?? t('Не знайдено', 'Not found')); }
    });
  }

  void _openChatScreen(String targetName, String targetKey, {String? avatar, bool isVerified = false}) {
    if (LumynTheme.isDesktop(context)) {
      setState(() { _selectedDesktopChat = {'targetName': targetName, 'targetKey': targetKey, 'avatar': avatar, 'isVerified': isVerified}; });
      _loadData();
    } else {
      Navigator.push(context, MaterialPageRoute(builder: (context) => ChatScreen(deviceId: widget.deviceId, userName: widget.userName, myPublicKey: widget.publicKey, partnerName: targetName, partnerPublicKey: targetKey, partnerAvatar: avatar, partnerIsVerified: isVerified, friends: _friends))).then((_) => _loadData());
    }
  }

  // ─── SEARCH & FILTER ──────────────────────────────────────────────────────
  void _onSearchChanged() => setState(() => _searchQuery = _searchController.text.trim());

  List<Map<String, dynamic>> _getFilteredChats() {
    List<Map<String, dynamic>> chats = List.from(_recentChats);
    if (_activeFilter == 'unread') {
      chats = chats.where((c) => (c['unreadCount'] ?? 0) > 0).toList();
    } else if (_activeFilter == 'groups') {
      chats = chats.where((c) => c['isGroup'] == true).toList();
    } else if (_activeFilter == 'archive') {
      chats = chats.where((c) => c['isHidden'] == true).toList();
    }
    if (_searchQuery.isNotEmpty) {
      chats = chats.where((c) {
        final name = c['partnerName']?.toString().toLowerCase() ?? '';
        final text = (c['decryptedText'] ?? '').toString().toLowerCase();
        return name.contains(_searchQuery.toLowerCase()) || text.contains(_searchQuery.toLowerCase());
      }).toList();
    }
    return chats;
  }

  String _formatRelativeTime(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final dateOnly = DateTime(date.year, date.month, date.day);
    if (dateOnly == today) return _use24hFormat ? DateFormat('HH:mm').format(date) : DateFormat('h:mm a').format(date);
    if (dateOnly == yesterday) return t('Вчора', 'Yesterday');
    if (now.difference(date).inDays < 7) return t('${now.difference(date).inDays} д', '${now.difference(date).inDays}d');
    if (now.difference(date).inDays < 30) return t('${(now.difference(date).inDays / 7).floor()} т', '${(now.difference(date).inDays / 7).floor()}w');
    return DateFormat('dd.MM.yy').format(date);
  }

  Color _getColorFromName(String name) {
    const colors = [Color(0xFF6366F1), Color(0xFF8B5CF6), Color(0xFFEC4899), Color(0xFFF43F5E), Color(0xFFFB923C), Color(0xFF34D399), Color(0xFF10B981), Color(0xFF06B6D4), Color(0xFF0EA5E9), Color(0xFF3B82F6)];
    int hash = 0;
    for (int i = 0; i < name.length; i++) { hash = ((hash << 5) - hash) + name.codeUnitAt(i); hash = hash & hash; }
    return colors[hash.abs() % colors.length];
  }

  TextSpan _highlightSearchText(String text, String query) {
    if (query.isEmpty) return TextSpan(text: text, style: const TextStyle(color: _D.textPrimary));
    final List<TextSpan> spans = [];
    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    int start = 0;
    int idx = lowerText.indexOf(lowerQuery, start);
    while (idx != -1) {
      if (idx > start) spans.add(TextSpan(text: text.substring(start, idx), style: const TextStyle(color: _D.textPrimary)));
      spans.add(TextSpan(text: text.substring(idx, idx + query.length), style: const TextStyle(color: _D.textPrimary, backgroundColor: Color(0xFF6366F1), fontWeight: FontWeight.w600)));
      start = idx + query.length;
      idx = lowerText.indexOf(lowerQuery, start);
    }
    if (start < text.length) spans.add(TextSpan(text: text.substring(start), style: const TextStyle(color: _D.textPrimary)));
    return TextSpan(children: spans);
  }

  // ─── SETTINGS HELPERS ─────────────────────────────────────────────────────
  Widget _buildSwitchRow({required String title, String? subtitle, required bool value, required ValueChanged<bool> onChanged}) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(
        title: Text(title, style: const TextStyle(color: _D.textPrimary, fontWeight: FontWeight.w500, fontSize: 14)),
        subtitle: subtitle != null ? Text(subtitle, style: const TextStyle(color: _D.textSecondary, fontSize: 12)) : null,
        trailing: Switch(value: value, activeTrackColor: _D.textPrimary, thumbColor: WidgetStateProperty.all(_D.bg0), onChanged: (v) { onChanged(v); _checkUnsaved(); }),
      ),
      const Divider(height: 1, indent: 16, color: _D.border),
    ]);
  }

  Widget _buildDropdownRow<T>({required String title, required T value, required Map<T, String> options, required ValueChanged<T> onChanged}) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(
        title: Text(title, style: const TextStyle(color: _D.textPrimary, fontWeight: FontWeight.w500, fontSize: 14)),
        trailing: DropdownButtonHideUnderline(child: DropdownButton<T>(
          dropdownColor: _D.bg3, value: value,
          icon: const Icon(Icons.unfold_more, color: _D.textSecondary, size: 16),
          items: options.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(color: _D.textPrimary, fontSize: 13)))).toList(),
          onChanged: (v) { if (v != null) { onChanged(v); _checkUnsaved(); } },
        )),
      ),
      const Divider(height: 1, indent: 16, color: _D.border),
    ]);
  }

  Widget _buildActionRow({required String title, required IconData icon, required VoidCallback onTap, String? subtitle, Color color = _D.textPrimary}) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(leading: Icon(icon, color: color, size: 18), title: Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w500, fontSize: 14)), subtitle: subtitle != null ? Text(subtitle, style: const TextStyle(color: _D.textSecondary, fontSize: 12)) : null, onTap: onTap),
      const Divider(height: 1, indent: 50, color: _D.border),
    ]);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ─── CHATS TAB (REDESIGNED) ───────────────────────────────────────────────
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildChatsTab() {
    final isDesktop = LumynTheme.isDesktop(context);
    final filteredChats = _getFilteredChats();
    final pinnedChats = filteredChats.where((c) => c['isPinned'] == true).toList();
    final unpinnedChats = filteredChats.where((c) => c['isPinned'] != true).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ── Search bar ──
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
        child: _SearchBar(
          controller: _searchController,
          isDesktop: isDesktop,
          onCmdK: _openCommandPalette,
          onSubmitted: (_) => _isSearching ? null : _startChat(_searchController.text.trim(), null),
        ),
      ),
      if (_isSearching) const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: LinearProgressIndicator(backgroundColor: Colors.transparent, color: _D.accent, minHeight: 1)),

      // ── Filter tabs ──
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            _buildFilterChip('all', t('Всі', 'All')),
            _buildFilterChip('unread', t('Непрочитані', 'Unread')),
            _buildFilterChip('groups', t('Групи', 'Groups')),
            _buildFilterChip('archive', t('Архів', 'Archive')),
          ]),
        ),
      ),

      // ── Chat list ──
      Expanded(
        child: _isLoadingChats
            ? ListView.builder(itemCount: 6, padding: const EdgeInsets.symmetric(vertical: 4), itemBuilder: (_, i) => _SkeletonTile(delay: i * 80))
            : filteredChats.isEmpty
                ? _EmptyState(
                    icon: _searchQuery.isNotEmpty ? Icons.search_off_outlined : Icons.forum_outlined,
                    title: _searchQuery.isNotEmpty ? t('Нічого не знайдено', 'Nothing found') : t('Немає чатів', 'No chats yet'),
                    subtitle: _searchQuery.isNotEmpty ? t('Спробуйте інший запит', 'Try a different query') : t('Розпочніть нову розмову', 'Start a new conversation'),
                    action: _searchQuery.isEmpty ? _PillButton(label: t('Новий чат', 'New chat'), onTap: () { _searchController.clear(); _onSearchChanged(); }) : null,
                  )
                : ListView.builder(
                    padding: EdgeInsets.only(bottom: isDesktop ? 16 : 120, top: 4),
                    itemCount: pinnedChats.length + unpinnedChats.length + (pinnedChats.isNotEmpty ? 1 : 0) + (unpinnedChats.isNotEmpty && pinnedChats.isNotEmpty ? 1 : 0),
                    itemBuilder: (context, rawIndex) {
                      // section headers
                      if (pinnedChats.isNotEmpty) {
                        if (rawIndex == 0) return _SectionLabel(label: t('ЗАКРІПЛЕНІ', 'PINNED'), icon: Icons.push_pin, iconSize: 11);
                        if (rawIndex <= pinnedChats.length) {
                          final chat = pinnedChats[rawIndex - 1];
                          return _buildAnimatedTile(chat, rawIndex - 1);
                        }
                        if (rawIndex == pinnedChats.length + 1) return _SectionLabel(label: t('ВСІ ЧАТИ', 'ALL CHATS'));
                        final chat = unpinnedChats[rawIndex - pinnedChats.length - 2];
                        return _buildAnimatedTile(chat, rawIndex);
                      }
                      return _buildAnimatedTile(unpinnedChats[rawIndex], rawIndex);
                    },
                  ),
      ),
    ]);
  }

  Widget _buildAnimatedTile(Map<String, dynamic> chat, int index) {
    return AnimatedBuilder(
      animation: _listAnimController,
      builder: (context, child) {
        final delay = (index * 0.06).clamp(0.0, 0.6);
        final raw = ((_listAnimController.value - delay) / (1.0 - delay)).clamp(0.0, 1.0);
        final t2 = Curves.easeOutCubic.transform(raw);
        return Transform.translate(
          offset: Offset(0, 16 * (1 - t2)),
          child: Opacity(opacity: t2.clamp(0.0, 1.0), child: child),
        );
      },
      child: _ChatTile(
        chat: chat,
        userName: widget.userName,
        searchQuery: _searchQuery,
        isDesktop: LumynTheme.isDesktop(context),
        isSelected: _selectedDesktopChat?['targetName'] == chat['partnerName'],
        formatTime: _formatRelativeTime,
        getColor: _getColorFromName,
        highlightText: _highlightSearchText,
        onTap: () => _startChat(chat['partnerName'], chat['publicKey'], targetAvatar: chat['avatar'], isVerified: chat['isVerified'] == true),
        onLongPress: () => _showChatOptions(chat),
        onSecondaryTap: () => _showChatOptions(chat),
        onAvatarTap: () => _showUserProfile(chat['partnerName'], chat['avatar'], chat['publicKey'], chat['isGroup'] == true),
      ),
    );
  }

  Widget _buildFilterChip(String tab, String label) {
    final isActive = _activeFilter == tab;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () { setState(() => _activeFilter = tab); _listAnimController.forward(from: 0); },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: isActive ? _D.textPrimary : Colors.transparent,
            border: Border.all(color: isActive ? _D.textPrimary : _D.border),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(label, style: TextStyle(color: isActive ? _D.bg0 : _D.textSecondary, fontSize: 12, fontWeight: isActive ? FontWeight.w600 : FontWeight.w500)),
        ),
      ),
    );
  }

  // ─── FRIENDS TAB ──────────────────────────────────────────────────────────
  Widget _buildFriendsTab() {
    final isDesktop = LumynTheme.isDesktop(context);
    return ListView(
      padding: EdgeInsets.only(top: 16, bottom: isDesktop ? 16 : 120),
      children: [
        _SectionLabel(label: t('ДОДАТИ ДРУГА', 'ADD FRIEND')),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(children: [
            Expanded(child: _MinimalTextField(controller: _addFriendController, hint: t('Нікнейм', 'Username'), inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_.\-]'))])),
            const SizedBox(width: 8),
            _PillButton(label: t('Додати', 'Add'), onTap: _sendFriendRequest),
          ])),
        if (_pendingRequests.isNotEmpty) ...[
          const SizedBox(height: 20),
          _SectionLabel(label: t('ЗАПИТИ', 'REQUESTS'), count: _pendingRequests.length),
          ..._pendingRequests.map((req) => _FriendRequestTile(req: req, onAccept: () => _respondToRequest(req['userName'], 'accept'), onDeny: () => _respondToRequest(req['userName'], 'reject'), onAvatarTap: () => _showUserProfile(req['userName'], req['avatar'], null, false))),
        ],
        const SizedBox(height: 20),
        _SectionLabel(label: t('ДРУЗІ', 'FRIENDS'), count: _friends.length),
        if (_friends.isEmpty)
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), child: Text(t('Поки що немає друзів.', 'No friends yet.'), style: const TextStyle(color: _D.textSecondary, fontSize: 14)))
        else
          ..._friends.map((f) => _FriendTile(
            friend: f,
            onTap: () => _startChat(f['userName'], f['publicKey'], targetAvatar: f['avatar'], isVerified: (f['isVerified'] == true || f['isVerified'] == 1)),
            onAvatarTap: () => _showUserProfile(f['userName'], f['avatar'], f['publicKey'], false),
          )),
      ],
    );
  }

  // ─── SETTINGS TAB ─────────────────────────────────────────────────────────
  Widget _buildSettingsTab() {
    final isDesktop = LumynTheme.isDesktop(context);
    return Stack(children: [
      ListView(
        padding: EdgeInsets.only(top: 16, bottom: isDesktop ? (_hasUnsavedSettings ? 100 : 16) : 120),
        children: [
          // Profile
          Center(child: Stack(children: [
            SafeAvatar(avatarBase64: _myAvatar, fallbackName: widget.userName, radius: 40),
            Positioned(bottom: 0, right: 0, child: GestureDetector(onTap: _updateAvatar, child: Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: _D.bg3, border: Border.all(color: _D.bg0, width: 2), shape: BoxShape.circle), child: const Icon(Icons.camera_alt, color: _D.textPrimary, size: 13)))),
          ])),
          const SizedBox(height: 10),
          Center(child: Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
            Flexible(child: Text(widget.userName, style: const TextStyle(color: _D.textPrimary, fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.5), overflow: TextOverflow.ellipsis)),
            if (_myVerified) ...[const SizedBox(width: 6), const VerifiedBadge(size: 16, color: Colors.white)],
          ])),
          const SizedBox(height: 6),
          GestureDetector(onTap: _showEditBioDialog, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 40), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Flexible(child: Text(_myBio.isEmpty ? t('Додати опис', 'Add a bio') : _myBio, textAlign: TextAlign.center, style: TextStyle(color: _D.textSecondary, fontSize: 13, fontStyle: _myBio.isEmpty ? FontStyle.italic : FontStyle.normal))),
            const SizedBox(width: 5),
            const Icon(Icons.edit, size: 12, color: _D.textMuted),
          ]))),
          const SizedBox(height: 24),

          _SectionLabel(label: t('КОНФІДЕНЦІЙНІСТЬ', 'PRIVACY & SECURITY')),
          _SettingsCard(children: [
            _buildSwitchRow(title: t('Захист паролем', 'Password'), subtitle: t('Вводити пароль при відкритті', 'Enter password on launch'), value: _passwordEnabled, onChanged: _togglePasswordLock),
            if (_passwordEnabled) _buildDropdownRow<int>(title: t('Автоблокування', 'Auto-lock'), value: _autoLockTimeout, options: {0: t('Відразу', 'Immediately'), 60: t('1 хвилина', '1 minute'), 300: t('5 хвилин', '5 minutes'), 3600: t('1 година', '1 hour')}, onChanged: (v) => setState(() => _autoLockTimeout = v)),
            _buildActionRow(title: t('Заблоковані', 'Blocked Users'), icon: Icons.block, onTap: () => _showTopRightSnack(t('Список порожній', 'List is empty'))),
            _buildSwitchRow(title: t("Статус 'В мережі'", 'Online Status'), value: _onlineStatus, onChanged: (v) => setState(() => _onlineStatus = v)),
            _buildSwitchRow(title: t('Звіти про прочитання', 'Read Receipts'), value: _readReceipts, onChanged: (v) => setState(() => _readReceipts = v)),
            _buildSwitchRow(title: t('Індикатор друкування', 'Typing Indicator'), value: _typingIndicator, onChanged: (v) => setState(() => _typingIndicator = v)),
            _buildActionRow(title: t('Експорт акаунта', 'Export Account'), subtitle: t('Резервна копія ключів', 'Backup your keys'), icon: Icons.vpn_key_outlined, onTap: _showExportDialog),
          ]),

          const SizedBox(height: 20),
          Row(children: [
            _SectionLabel(label: t("ДАНІ ТА ПАМ'ЯТЬ", 'DATA & STORAGE')),
            const Spacer(),
            if (_isCacheAvailable) Padding(padding: const EdgeInsets.only(right: 12), child: GestureDetector(onTap: _clearCache, child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(border: Border.all(color: _D.border), borderRadius: BorderRadius.circular(6)), child: Text(t('Очистити кеш', 'Clear cache'), style: const TextStyle(color: _D.textSecondary, fontSize: 11))))),
          ]),
          _SettingsCard(children: [
            _buildSwitchRow(title: t('Автозавантаження', 'Auto-download media'), value: _autoDownloadMedia, onChanged: (v) => setState(() => _autoDownloadMedia = v)),
            _buildSwitchRow(title: t('Зберігати в галерею', 'Save to Gallery'), value: _saveToGallery, onChanged: (v) => setState(() => _saveToGallery = v)),
          ]),

          const SizedBox(height: 20),
          _SectionLabel(label: t('ІНТЕРФЕЙС', 'INTERFACE')),
          _SettingsCard(children: [
            _buildSwitchRow(title: t('Компактний режим', 'Compact Mode'), value: _compactMode, onChanged: (v) => setState(() => _compactMode = v)),
            _buildSwitchRow(title: t('Анімації', 'Animations'), value: _animationsEnabled, onChanged: (v) => setState(() => _animationsEnabled = v)),
            _buildSwitchRow(title: t('Enter для відправки', 'Send with Enter'), value: _sendWithEnter, onChanged: (v) => setState(() => _sendWithEnter = v)),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Text('Масштаб тексту', style: TextStyle(color: _D.textPrimary, fontWeight: FontWeight.w500, fontSize: 14)),
                const Spacer(),
                Text('${_chatFontSize.toInt()}px', style: const TextStyle(color: _D.textSecondary, fontSize: 12, fontFamily: _D.mono)),
              ]),
              const SizedBox(height: 4),
              Text(t('Текст виглядатиме ось так', 'Text will look like this'), style: TextStyle(color: _D.textSecondary, fontSize: _chatFontSize)),
              const SizedBox(height: 8),
              Slider(value: _chatFontSize, min: 12, max: 24, divisions: 6, activeColor: _D.textPrimary, inactiveColor: _D.bg3, onChanged: (val) { setState(() { _chatFontSize = val; _checkUnsaved(); }); }),
            ])),
          ]),

          const SizedBox(height: 20),
          _SectionLabel(label: t('ЧАС І МОВА', 'TIME & LANGUAGE')),
          _SettingsCard(children: [
            ListTile(title: const Text('Формат часу', style: TextStyle(color: _D.textPrimary, fontSize: 14, fontWeight: FontWeight.w500)), trailing: Text(_use24hFormat ? '24-h' : '12-h', style: const TextStyle(color: _D.textSecondary, fontFamily: _D.mono, fontSize: 13)), onTap: () { setState(() { _use24hFormat = !_use24hFormat; _checkUnsaved(); }); }),
            const Divider(height: 1, indent: 16, color: _D.border),
            _buildSwitchRow(title: t('Показувати секунди', 'Show Seconds'), value: _showSeconds, onChanged: (v) => setState(() => _showSeconds = v)),
            _buildDropdownRow<String>(title: t('Мова', 'Language'), value: lang, options: {'uk': 'Українська', 'en': 'English'}, onChanged: (v) => setState(() => lang = v)),
          ]),

          const SizedBox(height: 20),
          _SectionLabel(label: t('СПОВІЩЕННЯ', 'NOTIFICATIONS')),
          _SettingsCard(children: [
            _buildSwitchRow(title: t('Звукові', 'Sound Notifications'), value: _soundEnabled, onChanged: (v) => setState(() => _soundEnabled = v)),
            _buildSwitchRow(title: t('Десктопні', 'Desktop Notifications'), value: _desktopNotifications, onChanged: (v) => setState(() => _desktopNotifications = v)),
            _buildSwitchRow(title: t('Попередній перегляд', 'Message Previews'), value: _showPreviews, onChanged: (v) => setState(() => _showPreviews = v)),
          ]),

          if (_isAdmin) ...[
            const SizedBox(height: 20),
            _SectionLabel(label: t('ВЕРИФІКАЦІЯ', 'VERIFICATION'), icon: Icons.verified_outlined, iconSize: 12),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), child: Row(children: [
              Expanded(child: _MinimalTextField(controller: _verifySearchController, hint: t('Знайти користувача...', 'Find user...'), inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_.\-]'))])),
              const SizedBox(width: 8),
              _PillButton(label: t('Знайти', 'Find'), onTap: _searchUsersForVerify),
            ])),
            if (_verifyResults.isNotEmpty) ...[
              const SizedBox(height: 8),
              _SettingsCard(children: _verifyResults.asMap().entries.map((entry) {
                final idx = entry.key; final user = entry.value;
                final isVerified = user['isVerified'] == 1;
                return Column(children: [
                  ListTile(
                    leading: SafeAvatar(avatarBase64: user['avatar'], fallbackName: user['userName'], radius: 16),
                    title: Row(children: [Text(user['userName'], style: const TextStyle(color: _D.textPrimary, fontWeight: FontWeight.w500, fontSize: 14)), if (isVerified) ...[const SizedBox(width: 5), const VerifiedBadge(size: 12, color: Colors.white)]]),
                    trailing: GestureDetector(onTap: () => _toggleVerification(user['userName'], isVerified), child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5), decoration: BoxDecoration(color: isVerified ? const Color(0xFF1A0000) : _D.bg3, borderRadius: BorderRadius.circular(6), border: Border.all(color: isVerified ? _D.danger.withValues(alpha: 0.4) : _D.border)), child: Text(isVerified ? t('Зняти', 'Revoke') : t('Верифікувати', 'Verify'), style: TextStyle(color: isVerified ? _D.danger : _D.textPrimary, fontSize: 12, fontWeight: FontWeight.w500)))),
                  ),
                  if (idx != _verifyResults.length - 1) const Divider(height: 1, indent: 56, color: _D.border),
                ]);
              }).toList()),
            ],
          ],

          const SizedBox(height: 28),
          _SectionLabel(label: t('ПРО ДОДАТОК', 'ABOUT')),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: _D.bg2, border: Border.all(color: _D.border), borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('LUMYN Protocol', style: TextStyle(color: _D.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                SizedBox(height: 2),
                Text('v0.1.5', style: TextStyle(color: _D.textSecondary, fontSize: 12, fontFamily: _D.mono)),
              ]),
              const Spacer(),
              Text(t('Месенджер нового покоління', 'Next-gen messenger'), style: const TextStyle(color: _D.textMuted, fontSize: 12)),
            ]),
          )),

          const SizedBox(height: 20),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: GestureDetector(onTap: _logout, child: Container(height: 44, decoration: BoxDecoration(border: Border.all(color: _D.danger.withValues(alpha: 0.4)), borderRadius: BorderRadius.circular(8)), alignment: Alignment.center, child: Text(t('Вийти з акаунту', 'Log Out'), style: const TextStyle(color: _D.danger, fontSize: 13, fontWeight: FontWeight.w500))))),
        ],
      ),

      // Unsaved changes bar (Discord style)
      if (_hasUnsavedSettings)
        Positioned(
          bottom: isDesktop ? 20 : 96, left: 12, right: 12,
          child: TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 250), tween: Tween(begin: 0, end: 1), curve: Curves.easeOutBack,
            builder: (context, v, child) => Transform.translate(offset: Offset(0, 40 * (1 - v)), child: Opacity(opacity: v.clamp(0.0, 1.0), child: child)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: _D.bg3, borderRadius: BorderRadius.circular(8), border: Border.all(color: _D.borderMid)),
              child: Row(children: [
                Expanded(child: Text(t('Є незбережені зміни', 'You have unsaved changes'), style: const TextStyle(color: _D.textPrimary, fontSize: 12, fontWeight: FontWeight.w500))),
                TextButton(onPressed: _revertSettings, style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10)), child: Text(t('Скинути', 'Reset'), style: const TextStyle(color: _D.textSecondary, fontSize: 12))),
                const SizedBox(width: 6),
                _PillButton(label: t('Зберегти', 'Save'), onTap: _saveSettings),
              ]),
            ),
          ),
        ),
    ]);
  }

  // ─── DESKTOP RAIL (REDESIGNED) ────────────────────────────────────────────
  Widget _buildDesktopRail(int totalUnread, int totalPending) {
    return Container(
      width: 56,
      decoration: const BoxDecoration(color: _D.bg0, border: Border(right: BorderSide(color: _D.border))),
      child: Column(children: [
        const SizedBox(height: 16),
        _RailLogo(),
        const SizedBox(height: 24),
        _DesktopRailItem(index: 0, currentIndex: _currentIndex, label: t('Чати', 'Chats'), badgeCount: totalUnread, offIcon: Icons.forum_outlined, onIcon: Icons.forum_rounded, isChatIcon: true, onTap: (i) => setState(() { _currentIndex = i; _selectedDesktopChat = null; })),
        const SizedBox(height: 8),
        _DesktopRailItem(index: 1, currentIndex: _currentIndex, label: t('Друзі', 'Friends'), badgeCount: totalPending, offIcon: Icons.people_outline_rounded, onIcon: Icons.people_rounded, onTap: (i) => setState(() { _currentIndex = i; _selectedDesktopChat = null; })),
        const Spacer(),
        // Ctrl+K hint
        Tooltip(message: 'Ctrl+K', child: GestureDetector(
          onTap: _openCommandPalette,
          child: Container(width: 36, height: 36, margin: const EdgeInsets.only(bottom: 8), decoration: BoxDecoration(color: _D.bg2, borderRadius: BorderRadius.circular(8), border: Border.all(color: _D.border)), child: const Icon(Icons.search, color: _D.textSecondary, size: 16)),
        )),
        _DesktopRailItem(index: 2, currentIndex: _currentIndex, label: t('Налаштування', 'Settings'), badgeCount: 0, offIcon: Icons.settings_outlined, onIcon: Icons.settings, onTap: (i) => setState(() { _currentIndex = i; _selectedDesktopChat = null; })),
        const SizedBox(height: 16),
      ]),
    );
  }

  // ─── MOBILE BOTTOM NAV (REDESIGNED) ──────────────────────────────────────
  Widget _buildDarkGlassMenu(int totalUnread, int totalPending) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.only(left: 16, right: 16, bottom: MediaQuery.of(context).padding.bottom + 10),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              decoration: BoxDecoration(color: const Color(0xFF0D0D0D).withValues(alpha: 0.92), borderRadius: BorderRadius.circular(16), border: Border.all(color: _D.border)),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(children: [
                _BottomNavItem(index: 0, currentIndex: _currentIndex, label: t('Чати', 'Chats'), icon: Icons.forum_outlined, activeIcon: Icons.forum_rounded, badge: totalUnread, onTap: (i) => setState(() { _currentIndex = i; _selectedDesktopChat = null; })),
                _BottomNavItem(index: 1, currentIndex: _currentIndex, label: t('Друзі', 'Friends'), icon: Icons.people_outline_rounded, activeIcon: Icons.people_rounded, badge: totalPending, onTap: (i) => setState(() { _currentIndex = i; _selectedDesktopChat = null; })),
                _BottomNavItem(index: 2, currentIndex: _currentIndex, label: t('Настр.', 'Settings'), icon: Icons.settings_outlined, activeIcon: Icons.settings, badge: 0, onTap: (i) => setState(() { _currentIndex = i; _selectedDesktopChat = null; })),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  // ─── COMMAND PALETTE WIDGET ───────────────────────────────────────────────
  Widget _buildCommandPaletteOverlay() {
    final query = _cmdQuery.toLowerCase();
    final chatResults = _recentChats.where((c) => c['partnerName'].toString().toLowerCase().contains(query)).take(5).toList();
    final friendResults = _friends.where((f) => f['userName'].toString().toLowerCase().contains(query)).take(3).toList();

    return Dialog(
      backgroundColor: _D.bg2,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        width: 520,
        constraints: const BoxConstraints(maxHeight: 460),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: _D.borderMid)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Input
          Row(children: [
            const Padding(padding: EdgeInsets.symmetric(horizontal: 14), child: Icon(Icons.search, color: _D.textSecondary, size: 18)),
            Expanded(child: TextField(
              controller: _cmdController,
              autofocus: true,
              onSubmitted: (val) { if (chatResults.isNotEmpty) { _closeCommandPalette(); _startChat(chatResults[0]['partnerName'], chatResults[0]['publicKey']); } },
              style: const TextStyle(color: _D.textPrimary, fontSize: 14),
              decoration: InputDecoration(hintText: t('Пошук чатів, друзів...', 'Search chats, friends...'), hintStyle: const TextStyle(color: _D.textMuted), border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(vertical: 14)),
            )),
            Container(margin: const EdgeInsets.only(right: 12), padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3), decoration: BoxDecoration(color: _D.bg3, borderRadius: BorderRadius.circular(4), border: Border.all(color: _D.border)), child: const Text('Esc', style: TextStyle(color: _D.textMuted, fontSize: 11, fontFamily: _D.mono))),
          ]),
          const Divider(height: 1, color: _D.border),
          // Results
          Flexible(child: ListView(shrinkWrap: true, children: [
            if (chatResults.isNotEmpty) ...[
              _CmdSectionLabel(label: t('ЧАТИ', 'CHATS')),
              ...chatResults.map((c) => _CmdResultTile(name: c['partnerName'], subtitle: c['decryptedText'] ?? '', avatar: c['avatar'], color: _getColorFromName(c['partnerName']), onTap: () { _closeCommandPalette(); _startChat(c['partnerName'], c['publicKey']); })),
            ],
            if (friendResults.isNotEmpty) ...[
              _CmdSectionLabel(label: t('ДРУЗІ', 'FRIENDS')),
              ...friendResults.map((f) => _CmdResultTile(name: f['userName'], subtitle: '', avatar: f['avatar'], color: _getColorFromName(f['userName']), onTap: () { _closeCommandPalette(); _startChat(f['userName'], f['publicKey']); })),
            ],
            if (chatResults.isEmpty && friendResults.isEmpty && query.isNotEmpty)
              Padding(padding: const EdgeInsets.all(24), child: Center(child: Text(t('Нічого не знайдено', 'Nothing found'), style: const TextStyle(color: _D.textSecondary, fontSize: 13)))),
            if (query.isEmpty) ...[
              _CmdSectionLabel(label: t('ДІЇ', 'QUICK ACTIONS')),
              _CmdActionTile(icon: Icons.group_add_outlined, label: t('Новий чат', 'New Chat'), kbd: 'Ctrl+1', onTap: () { _closeCommandPalette(); setState(() => _currentIndex = 0); }),
              _CmdActionTile(icon: Icons.people_outline, label: t('Друзі', 'Friends'), kbd: 'Ctrl+2', onTap: () { _closeCommandPalette(); setState(() => _currentIndex = 1); }),
              _CmdActionTile(icon: Icons.settings_outlined, label: t('Налаштування', 'Settings'), kbd: 'Ctrl+3', onTap: () { _closeCommandPalette(); setState(() => _currentIndex = 2); }),
            ],
          ])),
        ]),
      ),
    );
  }

  // ─── BUILD ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_isAppLocked) return _buildLockScreen();
    final isDesktop = LumynTheme.isDesktop(context);
    final totalUnread = _recentChats.fold<int>(0, (sum, c) => sum + ((c['unreadCount'] ?? 0) as int));
    final totalPending = _pendingRequests.length;
    final appBarTitle = _currentIndex == 0 ? t('Чати', 'Chats') : (_currentIndex == 1 ? t('Друзі', 'Friends') : t('Налаштування', 'Settings'));
    final content = _currentIndex == 0 ? _buildChatsTab() : (_currentIndex == 1 ? _buildFriendsTab() : _buildSettingsTab());

    Widget scaffold;

    if (isDesktop) {
      scaffold = Scaffold(
        backgroundColor: _D.bg0,
        body: Row(children: [
          _buildDesktopRail(totalUnread, totalPending),
          if (_currentIndex == 0) ...[
            Container(
              width: 300,
              decoration: const BoxDecoration(color: _D.bg0, border: Border(right: BorderSide(color: _D.border))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _DesktopPanelHeader(
                  title: appBarTitle,
                  action: _PillButton(label: t('+ Група', '+ Group'), onTap: _showCreateGroupDialog, small: true),
                ),
                Expanded(child: content),
              ]),
            ),
            Expanded(child: Container(
              color: _D.bg0,
              child: _selectedDesktopChat == null
                  ? _EmptyDesktopState()
                  : Navigator(key: ValueKey(_selectedDesktopChat!['targetName']), onGenerateRoute: (settings) => MaterialPageRoute(builder: (context) => ChatScreen(deviceId: widget.deviceId, userName: widget.userName, myPublicKey: widget.publicKey, partnerName: _selectedDesktopChat!['targetName'], partnerPublicKey: _selectedDesktopChat!['targetKey'], partnerAvatar: _selectedDesktopChat!['avatar'], partnerIsVerified: _selectedDesktopChat!['isVerified'], friends: _friends))),
            )),
          ] else ...[
            Expanded(child: Container(
              color: _D.bg0,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _DesktopPanelHeader(title: appBarTitle),
                Expanded(child: Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 640), child: content))),
              ]),
            )),
          ],
        ]),
      );
    } else {
      scaffold = Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: true,
        appBar: AppBar(
          title: Text(appBarTitle, style: const TextStyle(color: _D.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          flexibleSpace: ClipRect(child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20), child: Container(color: _D.bg0.withValues(alpha: 0.8)))),
          actions: _currentIndex == 0 ? [IconButton(icon: const Icon(Icons.group_add_outlined, color: _D.textPrimary, size: 22), onPressed: _showCreateGroupDialog, hoverColor: _D.bg3)] : null,
        ),
        body: LiquidBackground(child: Stack(children: [content, _buildDarkGlassMenu(totalUnread, totalPending)])),
      );
    }

    return KeyboardListener(
      focusNode: _rootFocusNode,
      onKeyEvent: _handleKeyEvent,
      child: scaffold,
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ─── HELPER WIDGETS ───────────────────────────────────────────────────────────
// ══════════════════════════════════════════════════════════════════════════════

class _DesktopPanelHeader extends StatelessWidget {
  final String title;
  final Widget? action;
  const _DesktopPanelHeader({required this.title, this.action});
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _D.border))),
      child: Row(children: [
        Text(title, style: const TextStyle(color: _D.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
        const Spacer(),
        if (action != null) action ?? const SizedBox(),
      ]),
    );
  }
}

// ─── Animated chat tile ────────────────────────────────────────────────────
class _ChatTile extends StatefulWidget {
  final Map<String, dynamic> chat;
  final String userName, searchQuery;
  final bool isDesktop, isSelected;
  final String Function(DateTime) formatTime;
  final Color Function(String) getColor;
  final TextSpan Function(String, String) highlightText;
  final VoidCallback onTap, onLongPress, onSecondaryTap, onAvatarTap;

  const _ChatTile({required this.chat, required this.userName, required this.searchQuery, required this.isDesktop, required this.isSelected, required this.formatTime, required this.getColor, required this.highlightText, required this.onTap, required this.onLongPress, required this.onSecondaryTap, required this.onAvatarTap});

  @override
  State<_ChatTile> createState() => _ChatTileState();
}

class _ChatTileState extends State<_ChatTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final chat = widget.chat;
    final isGroup = chat['isGroup'] == true;
    final unread = (chat['unreadCount'] ?? 0) as int;
    final isSelf = chat['partnerName'] == widget.userName;
    final chatVerified = chat['isVerified'] == true;
    final isSelected = widget.isSelected;
    final preview = chat['decryptedText'] ?? '';
    final isMedia = preview.contains('🎤') || preview.contains('📷');

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onLongPress: widget.isDesktop ? null : widget.onLongPress,
        onSecondaryTap: widget.isDesktop ? widget.onSecondaryTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          color: isSelected
              ? _D.bg3
              : _hovered
                  ? _D.bg2
                  : Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: widget.isDesktop ? 8 : 10),
              child: Row(children: [
                // Avatar
                GestureDetector(
                  onTap: isSelf ? null : widget.onAvatarTap,
                  child: Stack(children: [
                    isSelf
                        ? CircleAvatar(radius: 22, backgroundColor: _D.bg3, child: const Icon(Icons.bookmark_outline, color: _D.textSecondary, size: 20))
                        : StoryRingAvatar(avatarBase64: chat['avatar'], fallbackName: chat['partnerName'], radius: 22, isGroup: isGroup, hasUnread: unread > 0),
                    if (!isSelf && unread > 0)
                      Positioned(right: 0, bottom: 0, child: Container(width: 10, height: 10, decoration: BoxDecoration(color: _D.accent, shape: BoxShape.circle, border: Border.all(color: _D.bg0, width: 2)))),
                  ]),
                ),
                const SizedBox(width: 10),
                // Content
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Row(children: [
                      Flexible(child: widget.searchQuery.isNotEmpty
                          ? RichText(text: widget.highlightText(isSelf ? 'Нотатник' : chat['partnerName'], widget.searchQuery), overflow: TextOverflow.ellipsis)
                          : Text(isSelf ? 'Нотатник' : chat['partnerName'], style: TextStyle(color: _D.textPrimary, fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.w500, fontSize: 14), overflow: TextOverflow.ellipsis)),
                      if (!isGroup && chatVerified) ...[const SizedBox(width: 4), const VerifiedBadge(size: 12, color: Colors.white)],
                      if (chat['isPinned'] == true) ...[const SizedBox(width: 4), const Icon(Icons.push_pin, size: 11, color: _D.textMuted)],
                    ])),
                    if (chat['lastMessage'] != null) ...[
                      const SizedBox(width: 8),
                      Tooltip(message: DateFormat('dd.MM.yyyy HH:mm').format(DateTime.parse(chat['timestamp']).toLocal()), child: Text(widget.formatTime(DateTime.parse(chat['timestamp']).toLocal()), style: TextStyle(fontSize: 11, color: unread > 0 ? _D.textPrimary : _D.textMuted, fontFamily: _D.mono))),
                    ],
                  ]),
                  const SizedBox(height: 2),
                  Row(children: [
                    Expanded(child: widget.searchQuery.isNotEmpty
                        ? RichText(text: widget.highlightText(preview.isNotEmpty ? (preview.length > 48 ? '${preview.substring(0, 48)}…' : preview) : '', widget.searchQuery), maxLines: 1, overflow: TextOverflow.ellipsis)
                        : Text(preview.isNotEmpty ? (preview.length > 48 ? '${preview.substring(0, 48)}…' : preview) : '', style: TextStyle(color: unread > 0 ? _D.textPrimary.withValues(alpha: 0.8) : _D.textSecondary, fontSize: 12, fontWeight: unread > 0 ? FontWeight.w500 : FontWeight.normal, fontStyle: isMedia ? FontStyle.italic : FontStyle.normal), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    if (unread > 0) ...[
                      const SizedBox(width: 8),
                      Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: _D.accent, borderRadius: BorderRadius.circular(10)), child: Text('$unread', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600))),
                    ],
                  ]),
                ])),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Empty state ───────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final Widget? action;
  const _EmptyState({required this.icon, required this.title, required this.subtitle, this.action});
  @override
  Widget build(BuildContext context) {
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 40, color: _D.textMuted),
      const SizedBox(height: 14),
      Text(title, style: const TextStyle(color: _D.textPrimary, fontSize: 15, fontWeight: FontWeight.w500)),
      const SizedBox(height: 4),
      Text(subtitle, style: const TextStyle(color: _D.textSecondary, fontSize: 13)),
      if (action != null) ...[const SizedBox(height: 16), action!],
    ]));
  }
}

class _EmptyDesktopState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const _AnimatedShapeLogo(size: 72),
      const SizedBox(height: 20),
      const Text('Lumyn Desktop', style: TextStyle(color: _D.textPrimary, fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: -0.5)),
      const SizedBox(height: 6),
      const Text('Оберіть чат або почніть нову розмову', style: TextStyle(color: _D.textSecondary, fontSize: 13)),
      const SizedBox(height: 16),
      Row(mainAxisSize: MainAxisSize.min, children: const [
        _KbdHint(keys: ['Ctrl', 'K']),
        SizedBox(width: 6),
        Text('пошук', style: TextStyle(color: _D.textMuted, fontSize: 12)),
      ]),
    ]));
  }
}

// ─── Skeleton loading tile ─────────────────────────────────────────────────
class _SkeletonTile extends StatefulWidget {
  final int delay;
  const _SkeletonTile({required this.delay});
  @override
  State<_SkeletonTile> createState() => _SkeletonTileState();
}

class _SkeletonTileState extends State<_SkeletonTile> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.3, end: 0.6).animate(_anim),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(children: [
          Container(width: 44, height: 44, decoration: const BoxDecoration(color: _D.bg3, shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(height: 12, width: 100 + (widget.delay % 80).toDouble(), decoration: BoxDecoration(color: _D.bg3, borderRadius: BorderRadius.circular(4))),
            const SizedBox(height: 6),
            Container(height: 10, width: 160 + (widget.delay % 60).toDouble(), decoration: BoxDecoration(color: _D.bg3, borderRadius: BorderRadius.circular(4))),
          ])),
        ]),
      ),
    );
  }
}

// ─── Section label ─────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String label;
  final IconData? icon;
  final double iconSize;
  final int? count;
  const _SectionLabel({required this.label, this.icon, this.iconSize = 12, this.count});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Row(children: [
        if (icon != null) ...[Icon(icon, size: iconSize, color: _D.textMuted), const SizedBox(width: 4)],
        Text(label, style: const TextStyle(color: _D.textMuted, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.8)),
        if (count != null) ...[const SizedBox(width: 6), Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1), decoration: BoxDecoration(color: _D.bg3, borderRadius: BorderRadius.circular(4)), child: Text('$count', style: const TextStyle(color: _D.textSecondary, fontSize: 10, fontFamily: _D.mono)))],
      ]),
    );
  }
}

// ─── Settings card ─────────────────────────────────────────────────────────
class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: _D.bg2, borderRadius: BorderRadius.circular(8), border: Border.all(color: _D.border)),
      child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Column(children: children)),
    );
  }
}

// ─── Minimal text field ────────────────────────────────────────────────────
class _MinimalTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onSubmit;
  const _MinimalTextField({required this.controller, required this.hint, this.obscure = false, this.inputFormatters, this.onSubmit});
  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      obscuringCharacter: '●',
      inputFormatters: inputFormatters,
      onSubmitted: onSubmit,
      style: const TextStyle(color: _D.textPrimary, fontSize: 13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: _D.textMuted, fontSize: 13),
        filled: true, fillColor: _D.bg2,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: _D.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: _D.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: _D.borderMid)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        isDense: true,
      ),
    );
  }
}

// ─── Pill button ───────────────────────────────────────────────────────────
class _PillButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final bool small;
  const _PillButton({required this.label, required this.onTap, this.small = false});
  @override
  State<_PillButton> createState() => _PillButtonState();
}

class _PillButtonState extends State<_PillButton> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: EdgeInsets.symmetric(horizontal: widget.small ? 10 : 14, vertical: widget.small ? 5 : 8),
          decoration: BoxDecoration(color: _hovered ? const Color(0xFFEDEDED) : _D.textPrimary, borderRadius: BorderRadius.circular(6)),
          child: Text(widget.label, style: TextStyle(color: _D.bg0, fontSize: widget.small ? 12 : 13, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

// ─── Action button ─────────────────────────────────────────────────────────
class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool primary;
  final VoidCallback onTap;
  const _ActionButton({required this.label, required this.icon, this.primary = false, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(color: primary ? _D.accent : Colors.transparent, border: Border.all(color: primary ? _D.accent : _D.border), borderRadius: BorderRadius.circular(7)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: primary ? Colors.white : _D.textSecondary, size: 15),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: primary ? Colors.white : _D.textSecondary, fontSize: 13, fontWeight: FontWeight.w500)),
        ]),
      ),
    );
  }
}

// ─── Profile action row ────────────────────────────────────────────────────
class _ProfileActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool danger;
  final VoidCallback onTap;
  const _ProfileActionRow({required this.icon, required this.label, this.danger = false, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final color = danger ? _D.danger : _D.textPrimary;
    return Material(color: Colors.transparent, child: InkWell(onTap: onTap, hoverColor: _D.bg3, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), child: Row(children: [Icon(icon, color: color, size: 18), const SizedBox(width: 12), Expanded(child: Text(label, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w500))), Icon(Icons.chevron_right, color: _D.textMuted, size: 16)]))));
  }
}

// ─── Sheet action ─────────────────────────────────────────────────────────
class _SheetAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final bool danger;
  final VoidCallback onTap;
  const _SheetAction({required this.icon, required this.label, this.subtitle, this.danger = false, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final color = danger ? _D.danger : _D.textPrimary;
    return ListTile(leading: Icon(icon, color: color, size: 20), title: Text(label, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w500)), subtitle: subtitle != null ? Text(subtitle!, style: const TextStyle(color: _D.textSecondary, fontSize: 12)) : null, onTap: onTap);
  }
}

// ─── Friend request tile ───────────────────────────────────────────────────
class _FriendRequestTile extends StatelessWidget {
  final Map<String, dynamic> req;
  final VoidCallback onAccept, onDeny, onAvatarTap;
  const _FriendRequestTile({required this.req, required this.onAccept, required this.onDeny, required this.onAvatarTap});
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: _D.bg2, borderRadius: BorderRadius.circular(8), border: Border.all(color: _D.border)),
      child: Row(children: [
        GestureDetector(onTap: onAvatarTap, child: SafeAvatar(avatarBase64: req['avatar'], fallbackName: req['userName'], radius: 18)),
        const SizedBox(width: 10),
        Expanded(child: Row(children: [
          Flexible(child: Text(req['userName'], style: const TextStyle(color: _D.textPrimary, fontWeight: FontWeight.w500, fontSize: 14), overflow: TextOverflow.ellipsis)),
          if (req['isVerified'] == 1) ...[const SizedBox(width: 4), const VerifiedBadge(size: 12, color: Colors.white)],
        ])),
        const SizedBox(width: 8),
        _PillButton(label: t('Прийняти', 'Accept'), onTap: onAccept, small: true),
        const SizedBox(width: 6),
        GestureDetector(onTap: onDeny, child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(border: Border.all(color: _D.border), borderRadius: BorderRadius.circular(6)), child: Text(t('Сховати', 'Deny'), style: const TextStyle(color: _D.textSecondary, fontSize: 12)))),
      ]),
    );
  }
}

// ─── Friend tile ───────────────────────────────────────────────────────────
class _FriendTile extends StatefulWidget {
  final Map<String, dynamic> friend;
  final VoidCallback onTap, onAvatarTap;
  const _FriendTile({required this.friend, required this.onTap, required this.onAvatarTap});
  @override
  State<_FriendTile> createState() => _FriendTileState();
}

class _FriendTileState extends State<_FriendTile> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    final f = widget.friend;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        decoration: BoxDecoration(color: _hovered ? _D.bg2 : Colors.transparent, borderRadius: BorderRadius.circular(8)),
        child: ListTile(
          dense: true,
          onTap: widget.onTap,
          leading: GestureDetector(onTap: widget.onAvatarTap, child: SafeAvatar(avatarBase64: f['avatar'], fallbackName: f['userName'], radius: 18)),
          title: Row(children: [
            Flexible(child: Text(f['userName'], style: const TextStyle(color: _D.textPrimary, fontWeight: FontWeight.w500, fontSize: 14), overflow: TextOverflow.ellipsis)),
            if (f['isVerified'] == true || f['isVerified'] == 1) ...[const SizedBox(width: 4), const VerifiedBadge(size: 12, color: Colors.white)],
          ]),
        ),
      ),
    );
  }
}

// ─── Search bar ────────────────────────────────────────────────────────────
class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final bool isDesktop;
  final VoidCallback onCmdK;
  final ValueChanged<String> onSubmitted;
  const _SearchBar({required this.controller, required this.isDesktop, required this.onCmdK, required this.onSubmitted});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isDesktop ? onCmdK : null,
      child: Container(
        height: 34,
        decoration: BoxDecoration(color: _D.bg2, borderRadius: BorderRadius.circular(6), border: Border.all(color: _D.border)),
        child: Row(children: [
          const Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Icon(Icons.search, color: _D.textMuted, size: 16)),
          Expanded(child: isDesktop
              ? Text(t('Пошук...', 'Search...'), style: const TextStyle(color: _D.textMuted, fontSize: 13))
              : TextField(controller: controller, onSubmitted: onSubmitted, style: const TextStyle(color: _D.textPrimary, fontSize: 13), decoration: InputDecoration(hintText: t('Пошук...', 'Search...'), hintStyle: const TextStyle(color: _D.textMuted), border: InputBorder.none, contentPadding: EdgeInsets.zero, isDense: true))),
          if (isDesktop) Container(margin: const EdgeInsets.only(right: 8), padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: _D.bg3, borderRadius: BorderRadius.circular(4), border: Border.all(color: _D.border)), child: const Text('⌘K', style: TextStyle(color: _D.textMuted, fontSize: 11, fontFamily: _D.mono))),
        ]),
      ),
    );
  }
}

// ─── Command palette helpers ───────────────────────────────────────────────
class _CmdSectionLabel extends StatelessWidget {
  final String label;
  const _CmdSectionLabel({required this.label});
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.fromLTRB(14, 10, 14, 4), child: Text(label, style: const TextStyle(color: _D.textMuted, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.8)));
}

class _CmdResultTile extends StatefulWidget {
  final String name, subtitle;
  final String? avatar;
  final Color color;
  final VoidCallback onTap;
  const _CmdResultTile({required this.name, required this.subtitle, this.avatar, required this.color, required this.onTap});
  @override
  State<_CmdResultTile> createState() => _CmdResultTileState();
}
class _CmdResultTileState extends State<_CmdResultTile> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(onTap: widget.onTap, child: AnimatedContainer(duration: const Duration(milliseconds: 100), color: _hovered ? _D.bg3 : Colors.transparent, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), child: Row(children: [
        SafeAvatar(avatarBase64: widget.avatar, fallbackName: widget.name, radius: 14),
        const SizedBox(width: 10),
        Expanded(child: Text(widget.name, style: const TextStyle(color: _D.textPrimary, fontSize: 13, fontWeight: FontWeight.w500))),
        if (widget.subtitle.isNotEmpty) Text(widget.subtitle.length > 30 ? '${widget.subtitle.substring(0, 30)}…' : widget.subtitle, style: const TextStyle(color: _D.textSecondary, fontSize: 12)),
      ]))),
    );
  }
}

class _CmdActionTile extends StatefulWidget {
  final IconData icon;
  final String label, kbd;
  final VoidCallback onTap;
  const _CmdActionTile({required this.icon, required this.label, required this.kbd, required this.onTap});
  @override
  State<_CmdActionTile> createState() => _CmdActionTileState();
}
class _CmdActionTileState extends State<_CmdActionTile> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(onTap: widget.onTap, child: AnimatedContainer(duration: const Duration(milliseconds: 100), color: _hovered ? _D.bg3 : Colors.transparent, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9), child: Row(children: [
        Icon(widget.icon, color: _D.textSecondary, size: 16),
        const SizedBox(width: 10),
        Expanded(child: Text(widget.label, style: const TextStyle(color: _D.textPrimary, fontSize: 13))),
        _KbdHint(keys: widget.kbd.split('+')),
      ]))),
    );
  }
}

// ─── Keyboard hint badge ───────────────────────────────────────────────────
class _KbdHint extends StatelessWidget {
  final List<String> keys;
  const _KbdHint({required this.keys});
  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: keys.map((k) => Container(margin: const EdgeInsets.only(left: 3), padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2), decoration: BoxDecoration(color: _D.bg3, borderRadius: BorderRadius.circular(4), border: Border.all(color: _D.border)), child: Text(k, style: const TextStyle(color: _D.textSecondary, fontSize: 10, fontFamily: _D.mono)))).toList());
  }
}

// ─── Toast notification ────────────────────────────────────────────────────
class _ToastWidget extends StatefulWidget {
  final String msg;
  const _ToastWidget({required this.msg});
  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}
class _ToastWidgetState extends State<_ToastWidget> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 250));
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _ctrl.forward();
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: _anim, child: SlideTransition(position: Tween(begin: const Offset(0, -0.3), end: Offset.zero).animate(_anim), child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: _D.bg2, borderRadius: BorderRadius.circular(8), border: Border.all(color: _D.border)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.info_outline, color: _D.textSecondary, size: 15), const SizedBox(width: 8), Text(widget.msg, style: const TextStyle(color: _D.textPrimary, fontSize: 13, fontWeight: FontWeight.w500, fontFamily: 'Inter'))]),
    )));
  }
}

// ─── Rail logo ─────────────────────────────────────────────────────────────
class _RailLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.asset('web/icons/logo-512.png', width: 30, height: 30, fit: BoxFit.cover,
          errorBuilder: (c, e, s) => Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: _D.bg3,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _D.border, width: 0.5),
            ),
            child: const Icon(Icons.image, color: _D.textSecondary, size: 16),
          )),
    );
  }
}

// ─── Bottom nav item ───────────────────────────────────────────────────────
class _BottomNavItem extends StatelessWidget {
  final int index, currentIndex, badge;
  final String label;
  final IconData icon, activeIcon;
  final ValueChanged<int> onTap;
  const _BottomNavItem({required this.index, required this.currentIndex, required this.badge, required this.label, required this.icon, required this.activeIcon, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final isActive = currentIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => onTap(index),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(color: isActive ? _D.bg3 : Colors.transparent, borderRadius: BorderRadius.circular(8)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Badge(isLabelVisible: badge > 0, backgroundColor: _D.textPrimary, textColor: _D.bg0, label: Text('$badge', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 9)),
              child: Icon(isActive ? activeIcon : icon, color: isActive ? _D.textPrimary : _D.textSecondary, size: 22)),
            const SizedBox(height: 3),
            Text(label, style: TextStyle(color: isActive ? _D.textPrimary : _D.textSecondary, fontSize: 10, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}

// ─── Desktop rail item ─────────────────────────────────────────────────────
class _RightTooltip extends StatefulWidget {
  final Widget child; final String message;
  const _RightTooltip({required this.child, required this.message});
  @override
  State<_RightTooltip> createState() => _RightTooltipState();
}
class _RightTooltipState extends State<_RightTooltip> {
  OverlayEntry? _entry; final _link = LayerLink();
  void _show() {
    _entry = OverlayEntry(builder: (context) => Positioned(child: CompositedTransformFollower(link: _link, targetAnchor: Alignment.centerRight, followerAnchor: Alignment.centerLeft, offset: const Offset(10, 0),
      child: Material(color: Colors.transparent, child: Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5), decoration: BoxDecoration(color: _D.bg3, borderRadius: BorderRadius.circular(6), border: Border.all(color: _D.border)), child: Text(widget.message, style: const TextStyle(color: _D.textPrimary, fontSize: 12, fontFamily: 'Inter', decoration: TextDecoration.none)))))));
    Overlay.of(context).insert(_entry!);
  }
  void _hide() { _entry?.remove(); _entry = null; }
  @override
  void dispose() { _hide(); super.dispose(); }
  @override
  Widget build(BuildContext context) => CompositedTransformTarget(link: _link, child: MouseRegion(onEnter: (_) => _show(), onExit: (_) => _hide(), child: widget.child));
}

class _DesktopRailItem extends StatefulWidget {
  final int index, currentIndex, badgeCount;
  final String label;
  final IconData offIcon, onIcon;
  final bool isChatIcon;
  final ValueChanged<int> onTap;
  const _DesktopRailItem({required this.index, required this.currentIndex, required this.badgeCount, required this.label, required this.offIcon, required this.onIcon, this.isChatIcon = false, required this.onTap});
  @override
  State<_DesktopRailItem> createState() => _DesktopRailItemState();
}
class _DesktopRailItemState extends State<_DesktopRailItem> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    final isActive = widget.currentIndex == widget.index;
    final iconColor = isActive ? _D.textPrimary : (_hovered ? _D.textPrimary : _D.textSecondary);
    final bgColor = isActive ? _D.bg3 : (_hovered ? _D.bg2 : Colors.transparent);
    return _RightTooltip(
      message: widget.label,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => widget.onTap(widget.index),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: 40, height: 40,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(8),
              border: (_hovered && !isActive) ? Border.all(color: _D.border, width: 0.5) : null,
            ),
            child: Stack(alignment: Alignment.center, children: [
              widget.isChatIcon
                  ? CustomPaint(size: const Size(18, 18), painter: VercelChatIconPainter(color: iconColor))
                  : Icon(isActive ? widget.onIcon : widget.offIcon, color: iconColor, size: 18),
              if (widget.badgeCount > 0) Positioned(top: 2, right: 2, child: Container(width: 14, height: 14, decoration: BoxDecoration(color: _D.textPrimary, borderRadius: BorderRadius.circular(7)), child: Center(child: Text('${widget.badgeCount}', style: const TextStyle(color: _D.bg0, fontSize: 8, fontWeight: FontWeight.bold))))),
            ]),
          ),
        ),
      ),
    );
  }
}

// ─── Existing widgets (unchanged) ─────────────────────────────────────────
class VercelChatIconPainter extends CustomPainter {
  final Color color;
  VercelChatIconPainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 1.8..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round;
    final path = Path();
    path.moveTo(21, 11.5); path.arcToPoint(const Offset(20.1, 15.3), radius: const Radius.circular(8.38), clockwise: true); path.arcToPoint(const Offset(12.5, 20.0), radius: const Radius.circular(8.5), clockwise: true); path.arcToPoint(const Offset(8.7, 19.1), radius: const Radius.circular(8.38), clockwise: true); path.lineTo(3, 21); path.lineTo(4.9, 15.3); path.arcToPoint(const Offset(4.0, 11.5), radius: const Radius.circular(8.38), clockwise: true); path.arcToPoint(const Offset(8.7, 3.9), radius: const Radius.circular(8.5), clockwise: true); path.arcToPoint(const Offset(12.5, 3.0), radius: const Radius.circular(8.38), clockwise: true); path.lineTo(13.0, 3.0); path.arcToPoint(const Offset(21.0, 11.0), radius: const Radius.circular(8.48), clockwise: true); path.lineTo(21.0, 11.5); path.close();
    canvas.scale(size.width / 24.0, size.height / 24.0);
    canvas.drawPath(path, paint);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _AnimatedShapeLogo extends StatefulWidget {
  final double size;
  const _AnimatedShapeLogo({this.size = 36});
  @override
  State<_AnimatedShapeLogo> createState() => _AnimatedShapeLogoState();
}

class Particle { double x, y, z; Particle(this.x, this.y, this.z); }

class _AnimatedShapeLogoState extends State<_AnimatedShapeLogo> with TickerProviderStateMixin {
  late AnimationController _ctrl;
  late AnimationController _scaleCtrl;
  final List<Particle> _particles = [];
  final List<Particle> _originalParticles = [];
  Offset _mousePos = Offset.zero;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 15))..repeat();
    _scaleCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    const int n = 70;
    final double phi = pi * (3.0 - sqrt(5.0));
    for (int i = 0; i < n; i++) {
      double y = 1 - (i / (n - 1)) * 2;
      double radius = sqrt(1 - y * y);
      double theta = phi * i;
      final p = Particle(cos(theta) * radius, y, sin(theta) * radius);
      _particles.add(p); _originalParticles.add(Particle(p.x, p.y, p.z));
    }
  }
  @override
  void dispose() { _ctrl.dispose(); _scaleCtrl.dispose(); super.dispose(); }

  void _onPressed() { _scaleCtrl.forward().then((_) { if (mounted) Future.delayed(const Duration(milliseconds: 500), () { if (mounted) _scaleCtrl.reverse(); }); }); }

  void _updateParticlePositions() {
    double cx = widget.size / 2, cy = widget.size / 2;
    double attractionRadius = widget.size * 0.4;
    for (int i = 0; i < _particles.length; i++) {
      double dx = _mousePos.dx - cx, dy = _mousePos.dy - cy;
      double dist = sqrt(dx * dx + dy * dy);
      if (dist < attractionRadius) {
        double influence = 1.0 - (dist / attractionRadius); influence = influence * influence;
        double pullStrength = 0.15 * influence;
        _particles[i].x = _originalParticles[i].x * (1 - pullStrength) + (dx / widget.size) * 0.5 * pullStrength;
        _particles[i].y = _originalParticles[i].y * (1 - pullStrength) + (dy / widget.size) * 0.5 * pullStrength;
        _particles[i].z = _originalParticles[i].z * (1 - pullStrength * 0.5);
      } else {
        _particles[i].x = _originalParticles[i].x; _particles[i].y = _originalParticles[i].y; _particles[i].z = _originalParticles[i].z;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _onPressed,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onHover: (e) => setState(() { _mousePos = e.localPosition; _updateParticlePositions(); }),
        onExit: (e) => setState(() { _mousePos = Offset(widget.size / 2, widget.size / 2); _updateParticlePositions(); }),
        child: AnimatedBuilder(
          animation: Listenable.merge([_ctrl, _scaleCtrl]),
          builder: (context, child) {
            double scale = 1.0 + (_scaleCtrl.value * 2.0);
            return Transform.scale(scale: scale, child: SizedBox(width: widget.size, height: widget.size, child: CustomPaint(painter: _ParticlePainter(particles: _particles, progress: _ctrl.value, mousePos: _mousePos, sizeVal: widget.size, scale: scale))));
          },
        ),
      ),
    );
  }
}

class _ParticlePainter extends CustomPainter {
  final List<Particle> particles;
  final double progress, sizeVal, scale;
  final Offset mousePos;
  _ParticlePainter({required this.particles, required this.progress, required this.mousePos, required this.sizeVal, this.scale = 1.0});
  @override
  void paint(Canvas canvas, Size size) {
    double cx = size.width / 2, cy = size.height / 2;
    double r = size.width * 0.45 * scale;
    double angleY = progress * 2 * pi;
    double angleX = (mousePos.dy - cy) * 0.03;
    double angleZ = (mousePos.dx - cx) * 0.03;
    List<Map<String, dynamic>> projected = [];
    for (var p in particles) {
      double x1 = p.x * cos(angleY) - p.z * sin(angleY); double z1 = p.x * sin(angleY) + p.z * cos(angleY); double y1 = p.y;
      double y2 = y1 * cos(angleX) - z1 * sin(angleX); double z2 = y1 * sin(angleX) + z1 * cos(angleX); double x2 = x1;
      double x3 = x2 * cos(angleZ) - y2 * sin(angleZ); double y3 = x2 * sin(angleZ) + y2 * cos(angleZ); double z3 = z2;
      projected.add({'x': cx + x3 * r, 'y': cy + y3 * r, 'z': z3});
    }
    projected.sort((a, b) => a['z'].compareTo(b['z']));
    for (var p in projected) {
      double depth = ((p['z'] as double) + 1) / 2;
      double opacity = depth.clamp(0.15, 1.0);
      double radius = size.width * 0.015 + depth * (size.width * 0.035);
      final paint = Paint()..color = Colors.white.withValues(alpha: opacity * 0.8)..style = PaintingStyle.fill;
      if (depth > 0.8) paint.maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
      canvas.drawCircle(Offset(p['x'], p['y']), radius, paint);
    }
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}