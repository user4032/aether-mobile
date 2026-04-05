import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cryptography/cryptography.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:audioplayers/audioplayers.dart';
import '../config/server_config.dart';
import '../utils/globals.dart';
import '../firebase_web_config.dart';
import '../widgets/ui_core.dart';
import 'chat_screen.dart';
import 'dart:math' show pi;
import 'main_gate.dart';

class _SwitchTabIntent extends Intent {
  final int index;
  const _SwitchTabIntent(this.index);
}

// ─────────────────────────────────────────────────────────
// КАСТОМНА ІКОНКА ЗАМКА (APPLE STYLE)
// ─────────────────────────────────────────────────────────
class _AppleLockIcon extends StatelessWidget {
  final Color accent;
  const _AppleLockIcon({this.accent = Colors.white});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      height: 72,
      child: CustomPaint(painter: _LockPainter(accent: accent)),
    );
  }
}

class _LockPainter extends CustomPainter {
  final Color accent;
  const _LockPainter({required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Glow
    canvas.drawCircle(
      Offset(cx, cy), 32,
      Paint()
        ..color = accent.withValues(alpha: 0.16)
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
  int _desktopSelectedChatIndex = 0;
  late final PageController _pageController;
  final ScrollController _desktopChatsScrollController = ScrollController();
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
  String _myDisplayName = "";
  String? _pendingMyAvatar;
  String? _pendingMyBio;
  String? _pendingMyDisplayName;
  bool _myVerified = false;
  bool get _isAdmin => widget.userName == kAdminUsername;

  final _addFriendController = TextEditingController();
  final _searchController = TextEditingController();
  final _verifySearchController = TextEditingController();
  List<Map<String, dynamic>> _verifyResults = [];

  // --- PIN-LOCK ---
  bool _isAppLocked = false;
  bool _lockOnResume = false;
  bool _systemLockEnabled = false;
  bool _useFaceIdOnIOS = false;
  bool _authInProgress = false;
  final LocalAuthentication _localAuth = LocalAuthentication();

  // --- НАЛАШТУВАННЯ ---
  bool _notificationsEnabled = true;
  bool _soundEnabled = true;
  bool _vibrationEnabled = true;
  bool _messagePreview = true;
  bool _readReceipts = true;
  bool _onlineStatus = true;
  bool _typingIndicator = true;
  String _dmPermission = 'everyone';
  String _accentColor = 'purple';
  double _chatFontSize = 14.0;
  String _chatBubbleStyle = 'rounded';
  bool _compactMode = false;
  StreamSubscription<String>? _tokenRefreshSub;

  static const _accentColors = {
    'purple': Color(0xFFB026FF),
    'blue':   Color(0xFF007AFF),
    'green':  Color(0xFF34C759),
    'orange': Color(0xFFFF9500),
    'white':  Color(0xFFEDEDED),
  };

  bool get isDesktopView => MediaQuery.of(context).size.width >= 720;

  // ─────────────────────────────────────────────────────────
  // INIT / DISPOSE
  // ─────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentIndex);
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();

    _bgSocket = io.io(serverUrl, socketOptions());
    _bgSocket.connect();
    _bgSocket.onConnect((_) {
      _emitSetActive();
      _syncPrivacyToBackend();
      _loadData();
      unawaited(_syncWebPushToken());
    });

    _bgSocket.on('message', (data) {
      var msg = Map<String, dynamic>.from(data);
      if (msg['receiverName'] == widget.userName ||
          (msg['receiverName'].toString().startsWith('GROUP_') &&
              msg['senderName'] != widget.userName)) {
        if (currentActiveChat != msg['senderName'] &&
            currentActiveChat != msg['receiverName']) {
          if (_notificationsEnabled && _soundEnabled) {
            unawaited(_audioPlayer.play(AssetSource('ding.mp3')));
          }
          if (_notificationsEnabled && _vibrationEnabled && !kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
            HapticFeedback.mediumImpact();
          }
        }
        _loadData();
      }
    });

    _bgSocket.on('refresh_chats', (data) {
      if (data['userName'] == widget.userName || data['userName'] == 'all') _loadData();
    });

    _bgSocket.on('messages_read', (data) { _loadData(); });

    _bgSocket.on('friends_data', (data) {
      final payload = Map<String, dynamic>.from(data);
      if (mounted) {
        setState(() {
          final incomingAvatar = payload['myAvatar'] as String?;
          final incomingBio = (payload['myBio'] ?? "").toString();
          final incomingDisplayName = (payload['myDisplayName'] ?? "").toString();

          if (_pendingMyAvatar == null) {
            _myAvatar = incomingAvatar;
          } else if (incomingAvatar == _pendingMyAvatar) {
            _myAvatar = incomingAvatar;
            _pendingMyAvatar = null;
          }

          if (_pendingMyBio == null) {
            _myBio = incomingBio;
          } else if (incomingBio == _pendingMyBio) {
            _myBio = incomingBio;
            _pendingMyBio = null;
          }

          if (_pendingMyDisplayName == null) {
            if (payload.containsKey('myDisplayName') && payload['myDisplayName'] != null) {
              _myDisplayName = incomingDisplayName;
            }
          } else if (incomingDisplayName == _pendingMyDisplayName) {
            _myDisplayName = incomingDisplayName;
            _pendingMyDisplayName = null;
          }

          _myVerified = payload['myVerified'] == true;
          _friends = List<Map<String, dynamic>>.from(payload['friends'] ?? const []);
          _pendingRequests = List<Map<String, dynamic>>.from(payload['pending'] ?? const []);
        });
        unawaited(_persistProfileCache());
      }
    });

    _bgSocket.on('device_link_requested', (raw) {
      if (!mounted) return;
      final data = Map<String, dynamic>.from(raw as Map);
      _showApproveDeviceDialog(data);
    });

    _bgSocket.on('device_revoked', (raw) async {
      if (!mounted) return;
      final data = Map<String, dynamic>.from(raw as Map);
      _showSnack(t('Цей пристрій видалено з акаунта', 'This device was removed from account'));
      await (await SharedPreferences.getInstance()).remove('user_name');
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const MainGate()),
        (r) => false,
      );
      debugPrint('Device revoked: ${data['deviceId']}');
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    currentActiveChat = null;
    _pageController.dispose();
    _desktopChatsScrollController.dispose();
    _tokenRefreshSub?.cancel();
    _bgSocket.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _initWebPushIfNeeded() async {
    if (!kIsWeb || !WebFirebaseConfig.isConfigured || !_notificationsEnabled) return;

    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return;
      }

      await _syncWebPushToken();
      _tokenRefreshSub ??= FirebaseMessaging.instance.onTokenRefresh.listen(_sendFcmToken);
    } catch (_) {
      // Ignore push init errors so chat remains usable even without push setup.
    }
  }

  Future<void> _syncWebPushToken() async {
    if (!kIsWeb || !WebFirebaseConfig.isConfigured || !_notificationsEnabled) return;

    final token = await FirebaseMessaging.instance.getToken(
      vapidKey: WebFirebaseConfig.vapidKey.isEmpty ? null : WebFirebaseConfig.vapidKey,
    );

    if (token != null && token.isNotEmpty) {
      _sendFcmToken(token);
    }
  }

  void _sendFcmToken(String token) {
    if (!_bgSocket.connected || token.isEmpty) return;
    _bgSocket.emit('update_fcm_token', {
      'userName': widget.userName,
      'token': token,
    });
  }

  void _emitSetActive() {
    if (!_bgSocket.connected) return;
    _bgSocket.emit('set_active', {
      'userName': widget.userName,
      'deviceId': widget.deviceId,
      'onlineStatus': _onlineStatus,
    });
  }

  Future<void> _showApproveDeviceDialog(Map<String, dynamic> data) async {
    final requestId = (data['requestId'] ?? '').toString();
    if (requestId.isEmpty) return;
    final deviceName = (data['deviceName'] ?? t('Новий пристрій', 'New device')).toString();
    final code = (data['code'] ?? '').toString();

    if (!mounted) return;
    final approve = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161616),
        title: Text(t('Підключення пристрою', 'Device linking'), style: const TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t('Пристрій просить доступ до акаунта:', 'A device is requesting account access:'),
              style: TextStyle(color: Colors.white.withValues(alpha: 0.82)),
            ),
            const SizedBox(height: 8),
            Text(deviceName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            if (code.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('${t('Код', 'Code')}: $code', style: TextStyle(color: Colors.white.withValues(alpha: 0.65))),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t('Відхилити', 'Reject')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t('Підтвердити', 'Approve')),
          ),
        ],
      ),
    );

    if (approve == true) {
      final prefs = await SharedPreferences.getInstance();
      final storage = const FlutterSecureStorage();
      final privateKey = await storage.read(key: 'private_key');
      final publicKey = prefs.getString('public_key') ?? widget.publicKey;
      if (privateKey == null || privateKey.isEmpty || publicKey.isEmpty) {
        _showSnack(t('Не вдалося підтвердити: ключі відсутні', 'Failed to approve: keys missing'));
        return;
      }
      _bgSocket.emitWithAck('approve_device_link', {
        'requestId': requestId,
        'privateKey': privateKey,
        'publicKey': publicKey,
      }, ack: (dynamic resp) {
        final r = Map<String, dynamic>.from(resp as Map);
        _showSnack(r['success'] == true
            ? t('Пристрій підключено', 'Device linked')
            : (r['message'] ?? t('Не вдалося підтвердити', 'Approval failed')).toString());
      });
    } else {
      _bgSocket.emitWithAck('reject_device_link', {'requestId': requestId}, ack: (_) {});
    }
  }

  String _formatDeviceTime(String? iso) {
    if (iso == null || iso.isEmpty) return t('щойно', 'just now');
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return iso;
    return DateFormat('dd.MM HH:mm').format(dt);
  }

  void _showMyDevicesSheet() {
    _bgSocket.emitWithAck('get_my_devices', {
      'userName': widget.userName,
      'currentDeviceId': widget.deviceId,
    }, ack: (dynamic data) {
      final devices = List<Map<String, dynamic>>.from((data as List).map((e) => Map<String, dynamic>.from(e as Map)));
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (ctx) => Container(
          height: MediaQuery.of(ctx).size.height * 0.6,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.92),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(3))),
                const SizedBox(height: 14),
                Text(t('Мої пристрої', 'My devices'), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.separated(
                    itemCount: devices.length,
                    separatorBuilder: (_, _) => Divider(height: 1, indent: 70, color: Colors.white.withValues(alpha: 0.08)),
                    itemBuilder: (context, i) {
                      final d = devices[i];
                      final isCurrent = d['isCurrent'] == true;
                      return ListTile(
                        leading: CircleAvatar(
                          radius: 20,
                          backgroundColor: Colors.white.withValues(alpha: 0.08),
                          child: Icon(isCurrent ? Icons.smartphone_rounded : Icons.devices_other_rounded, color: Colors.white70),
                        ),
                        title: Text((d['deviceName'] ?? t('Пристрій', 'Device')).toString(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          isCurrent
                              ? t('Поточний пристрій', 'Current device')
                              : '${t('Остання активність', 'Last active')}: ${_formatDeviceTime((d['lastSeen'] ?? '').toString())}',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
                        ),
                        trailing: isCurrent
                            ? Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)),
                                child: Text(t('Онлайн', 'Online'), style: const TextStyle(color: Colors.greenAccent, fontSize: 11)),
                              )
                            : IconButton(
                                onPressed: () {
                                  _bgSocket.emitWithAck('revoke_my_device', {
                                    'userName': widget.userName,
                                    'deviceId': d['deviceId'],
                                    'currentDeviceId': widget.deviceId,
                                  }, ack: (dynamic resp) {
                                    final r = Map<String, dynamic>.from(resp as Map);
                                    if (r['success'] == true) {
                                      Navigator.pop(ctx);
                                      _showSnack(t('Пристрій видалено', 'Device removed'));
                                    } else {
                                      _showSnack((r['message'] ?? t('Помилка', 'Error')).toString());
                                    }
                                  });
                                },
                                icon: const Icon(Icons.logout_rounded, color: Color(0xFFFF6B6B)),
                              ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }

  void _syncPrivacyToBackend() {
    if (!_bgSocket.connected) return;
    _bgSocket.emit('update_privacy', {
      'userName': widget.userName,
      'readReceipts': _readReceipts,
      'onlineStatus': _onlineStatus,
      'typingIndicator': _typingIndicator,
      'notificationsEnabled': _notificationsEnabled,
      'messagePreview': _messagePreview,
      'dmPermission': _dmPermission,
    });
  }

  Future<void> _persistProfileCache() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('my_display_name', _myDisplayName);
    await p.setString('my_bio', _myBio);
    if (_myAvatar != null && _myAvatar!.isNotEmpty) {
      await p.setString('my_avatar', _myAvatar!);
    } else {
      await p.remove('my_avatar');
    }
  }

  String _dmPermissionLabel(String value) {
    switch (value) {
      case 'friends_only':
        return t('Тільки друзі', 'Friends only');
      case 'friends_or_groups':
        return t('Друзі або спільні групи', 'Friends or shared groups');
      case 'everyone':
      default:
        return t('Всі', 'Everyone');
    }
  }

  Widget _buildTabByIndex(int index) {
    switch (index) {
      case 0:
        return _buildChatsTab();
      case 1:
        return _buildFriendsTab();
      default:
        return _buildSettingsTab();
    }
  }

  Widget _buildAnimatedTabPage(int index) {
    return AnimatedBuilder(
      animation: _pageController,
      child: _buildTabByIndex(index),
      builder: (context, child) {
        double page = _currentIndex.toDouble();
        if (_pageController.hasClients) {
          page = _pageController.page ?? _currentIndex.toDouble();
        }
        final delta = (page - index).abs().clamp(0.0, 1.0);
        final scale = 1.0 - (delta * 0.035);
        final opacity = 1.0 - (delta * 0.22);

        return Opacity(
          opacity: opacity,
          child: Transform.scale(scale: scale, child: child),
        );
      },
    );
  }

  Future<void> _onTabSelected(int index) async {
    if (_currentIndex == index) return;

    setState(() => _currentIndex = index);
    
    // Перевіряємо, чи існує PageView на екрані перед анімацією
    if (_pageController.hasClients) {
      await _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 340),
        curve: Curves.easeInOutCubicEmphasized,
      );
    }
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
      _dmPermission         = p.getString('dm_permission') ?? 'everyone';
      _accentColor          = p.getString('accent_color') ?? 'purple';
      _chatFontSize         = p.getDouble('chat_font_size') ?? 14.0;
      _chatBubbleStyle      = p.getString('bubble_style') ?? 'rounded';
      _compactMode          = p.getBool('compact_mode') ?? false;
      _myDisplayName        = p.getString('my_display_name') ?? _myDisplayName;
      _myBio                = p.getString('my_bio') ?? _myBio;
      _myAvatar             = p.getString('my_avatar') ?? _myAvatar;
      _systemLockEnabled    = p.getBool('system_lock_enabled') ?? false;
      _useFaceIdOnIOS       = p.getBool('use_face_id_ios') ?? false;
    });
    if (_systemLockEnabled) {
      _initLockState();
    }
    if (kIsWeb && _notificationsEnabled) {
      unawaited(_initWebPushIfNeeded());
    }
    _syncPrivacyToBackend();
  }

  Future<void> _saveSetting(String key, dynamic value) async {
    final p = await SharedPreferences.getInstance();
    if (value is bool)   await p.setBool(key, value);
    if (value is double) await p.setDouble(key, value);
    if (value is String) await p.setString(key, value);
  }

  // ─────────────────────────────────────────────────────────
  // SYSTEM LOCK
  // ─────────────────────────────────────────────────────────
  Future<void> _initLockState() async {
    if (!_systemLockEnabled || !mounted || _authInProgress) return;
    setState(() {
      _isAppLocked = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isAppLocked || _authInProgress) return;
      _unlockWithSystemAuth();
    });
  }

  Future<void> _persistSystemLockSettings() async {
    await _saveSetting('system_lock_enabled', _systemLockEnabled);
    await _saveSetting('use_face_id_ios', _useFaceIdOnIOS);
  }

  Future<bool> _authenticateSystem() async {
    if (_authInProgress) return false;

    if (mounted) {
      setState(() => _authInProgress = true);
    } else {
      _authInProgress = true;
    }
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();
      if (!canCheck && !isSupported) {
        _showSnack(t("На пристрої недоступна системна автентифікація", "System authentication is unavailable on this device"));
        return false;
      }

      return await _localAuth.authenticate(
        localizedReason: t("Підтвердіть вхід у Lumyn", "Authenticate to unlock Lumyn"),
        options: AuthenticationOptions(
          biometricOnly: Platform.isIOS && _useFaceIdOnIOS,
          stickyAuth: true,
          useErrorDialogs: true,
          sensitiveTransaction: true,
        ),
      );
    } on PlatformException {
      return false;
    } finally {
      if (mounted) {
        setState(() => _authInProgress = false);
      } else {
        _authInProgress = false;
      }
    }
  }

  Future<void> _unlockWithSystemAuth() async {
    if (!_systemLockEnabled) {
      if (mounted) {
        setState(() => _isAppLocked = false);
      }
      return;
    }

    final ok = await _authenticateSystem();
    if (!mounted) return;
    if (ok) {
      setState(() => _isAppLocked = false);
    } else {
      setState(() => _isAppLocked = true);
    }
  }

  Future<void> _toggleSystemLock(bool enabled) async {
    if (!enabled) {
      setState(() {
        _systemLockEnabled = false;
        _useFaceIdOnIOS = false;
        _isAppLocked = false;
        _lockOnResume = false;
      });
      await _persistSystemLockSettings();
      _showSnack(t("Системний захист вимкнено", "System lock disabled"));
      return;
    }

    bool askFaceId = _useFaceIdOnIOS;
    if (Platform.isIOS) {
      final available = await _localAuth.getAvailableBiometrics();
      final hasFaceId = available.contains(BiometricType.face);
      if (hasFaceId && mounted) {
        final choice = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF161616),
            title: Text(t("Face ID", "Face ID"), style: const TextStyle(color: Colors.white)),
            content: Text(
              t("Увімкнути розблокування через Face ID? Якщо ні, буде системний пароль пристрою.", "Enable Face ID unlock? If not, device passcode will be used."),
              style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t("Ні", "No"))),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t("Так", "Yes"))),
            ],
          ),
        );
        askFaceId = choice == true;
      }
    }

    final wasFaceId = _useFaceIdOnIOS;
    _useFaceIdOnIOS = askFaceId;
    final ok = await _authenticateSystem();
    if (!mounted) return;

    if (ok) {
      setState(() {
        _systemLockEnabled = true;
        _isAppLocked = false;
        _lockOnResume = false;
      });
      await _persistSystemLockSettings();
      _showSnack(t("Системний захист увімкнено", "System lock enabled"));
    } else {
      _useFaceIdOnIOS = wasFaceId;
      _showSnack(t("Не вдалося увімкнути захист", "Could not enable lock"));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      if (_systemLockEnabled) {
        setState(() {
          _lockOnResume = true;
        });
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_lockOnResume && _systemLockEnabled) {
        setState(() {
          _isAppLocked = true;
          _lockOnResume = false;
        });
        _unlockWithSystemAuth();
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
            chat['decryptedText'] = "✨ ${t('Ефірне повідомлення', 'Lumyn message')}";
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

  void _applyLocalChatSettings(
    String partnerName, {
    bool? isPinned,
    bool? isHidden,
    bool? isBlocked,
    bool isDeleted = false,
  }) {
    if (!mounted) return;
    setState(() {
      bool updated = false;
      _recentChats = _recentChats.map((chat) {
        if (chat['partnerName'] != partnerName) return chat;
        updated = true;
        final next = Map<String, dynamic>.from(chat);
        if (isDeleted) {
          next['isHidden'] = true;
          return next;
        }
        if (isPinned != null) next['isPinned'] = isPinned;
        if (isHidden != null) next['isHidden'] = isHidden;
        if (isBlocked != null) next['isBlocked'] = isBlocked;
        return next;
      }).toList();

      if (!updated && !isDeleted) {
        _recentChats.add({
          'partnerName': partnerName,
          'isPinned': isPinned ?? false,
          'isHidden': isHidden ?? false,
          'isBlocked': isBlocked ?? false,
          'isGroup': false,
          'unreadCount': 0,
          'timestamp': DateTime.now().toIso8601String(),
        });
      }

      _recentChats.removeWhere((c) => c['isHidden'] == true);
      _recentChats.sort((a, b) {
        final ap = a['isPinned'] == true ? 1 : 0;
        final bp = b['isPinned'] == true ? 1 : 0;
        if (ap != bp) return bp.compareTo(ap);
        final at = DateTime.tryParse((a['timestamp'] ?? '').toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bt = DateTime.tryParse((b['timestamp'] ?? '').toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bt.compareTo(at);
      });
    });
  }

  Future<void> _updateAvatar() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery, imageQuality: 50, maxWidth: 500, maxHeight: 500);
    if (image == null || !mounted) return;
    final bytes = await image.readAsBytes();
    final base64String = base64Encode(bytes);
    _pendingMyAvatar = base64String;
    setState(() { _myAvatar = base64String; });
    unawaited(_persistProfileCache());
    _bgSocket.emit('update_avatar', {'userName': widget.userName, 'avatar': base64String});
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
  // UI HELPERS (RESPONSIVE)
  // ─────────────────────────────────────────────────────────

  Widget _buildBackground({required Widget child}) {
    if (isDesktopView) {
      return Container(color: Colors.black, child: child);
    }
    return LiquidBackground(child: child);
  }

  Widget _surface({required Widget child, EdgeInsetsGeometry? padding, EdgeInsetsGeometry? margin}) {
    if (isDesktopView) {
      return Container(
        margin: margin,
        padding: padding,
        decoration: BoxDecoration(
          color: const Color(0xFF0A0A0A),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF1A1A1A), width: 1),
        ),
        child: child,
      );
    }
    return GlassContainer(padding: padding, margin: margin, child: child);
  }

  Widget _vercelInput({required TextEditingController controller, required String hintText, List<TextInputFormatter>? inputFormatters, bool obscureText = false}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0A),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF222222)),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        inputFormatters: inputFormatters,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: const TextStyle(color: Color(0xFF666666)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
      ),
    );
  }

  Widget _vercelButton({required String text, required VoidCallback onPressed}) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        elevation: 0,
      ),
      onPressed: onPressed,
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
    );
  }

  // ─────────────────────────────────────────────────────────
  // DIALOGS
  // ─────────────────────────────────────────────────────────
  void _showCreateGroupDialog() {
    if (_friends.isEmpty) {
      _showSnack(t('Спочатку додайте друзів!', 'Add friends first!'));
      return;
    }
    final accent = _accentColors[_accentColor]!;
    final groupNameController = TextEditingController();
    List<String> selectedFriends = [];
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateSB) => AlertDialog(
          backgroundColor: Colors.transparent,
          contentPadding: EdgeInsets.zero,
          content: _surface(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(t('Створити групу', 'Create Group'),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 20),
                isDesktopView 
                  ? _vercelInput(controller: groupNameController, hintText: t('Назва групи', 'Group Name'))
                  : GlassInput(controller: groupNameController, hintText: t('Назва групи', 'Group Name')),
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
                          states.contains(WidgetState.selected) ? accent : Colors.transparent),
                        checkColor: Colors.black,
                        side: BorderSide(color: accent.withValues(alpha: 0.55)),
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

  void _showEditProfileSheet() {
    final accent = _accentColors[_accentColor] ?? const Color(0xFFB026FF);
    final displayController = TextEditingController(
      text: _myDisplayName.isNotEmpty ? _myDisplayName : widget.userName,
    );
    final bioController = TextEditingController(text: _myBio);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.92),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Text(
                          t('Інформація', 'Profile Info'),
                          style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: Icon(Icons.close, color: Colors.white.withValues(alpha: 0.85)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Center(
                      child: GestureDetector(
                        onTap: _updateAvatar,
                        child: SafeAvatar(avatarBase64: _myAvatar, fallbackName: widget.userName, radius: 46),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: Text(
                        displayController.text.trim().isEmpty ? widget.userName : displayController.text.trim(),
                        style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w700),
                      ),
                    ),
                    Center(
                      child: Text(
                        '@${widget.userName}',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 15),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      t('Про себе', 'About'),
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: bioController,
                      maxLength: 100,
                      maxLines: null,
                      style: const TextStyle(color: Colors.white, fontSize: 15),
                      decoration: InputDecoration(
                        hintText: t('Будь-які деталі про вас...', 'Any details about you...'),
                        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.03),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: accent.withValues(alpha: 0.7)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: displayController,
                      maxLength: 32,
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                      decoration: InputDecoration(
                        labelText: t('Display Name', 'Display Name'),
                        labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.03),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: accent.withValues(alpha: 0.7)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.alternate_email_rounded, color: Colors.white70, size: 18),
                          const SizedBox(width: 10),
                          Text(
                            t('Імʼя користувача', 'Username'),
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 14),
                          ),
                          const Spacer(),
                          Text(
                            '@${widget.userName}',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          final nextDisplay = displayController.text.trim();
                          final nextBio = bioController.text.trim();
                          _pendingMyDisplayName = nextDisplay;
                          _pendingMyBio = nextBio;
                          _bgSocket.emit('update_display_name', {
                            'userName': widget.userName,
                            'displayName': nextDisplay,
                          });
                          _bgSocket.emit('update_bio', {
                            'userName': widget.userName,
                            'bio': nextBio,
                          });
                          setState(() {
                            _myDisplayName = nextDisplay;
                            _myBio = nextBio;
                          });
                          unawaited(_persistProfileCache());
                          Navigator.pop(ctx);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: ThemeData.estimateBrightnessForColor(accent) == Brightness.dark ? Colors.white : Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(t('Зберегти', 'Save'), style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showExportDialog() {
    final accent = _accentColors[_accentColor]!;
    final passwordController = TextEditingController();
    String? backupToken;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateSB) => AlertDialog(
          backgroundColor: Colors.transparent,
          contentPadding: EdgeInsets.zero,
          content: _surface(
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
                  isDesktopView
                    ? _vercelInput(controller: passwordController, hintText: t("Придумайте пароль", "Create password"), obscureText: true)
                    : GlassInput(
                        controller: passwordController,
                        hintText: t("Придумайте пароль", "Create password"),
                        obscureText: true,
                      ),
                  const SizedBox(height: 20),
                  isDesktopView
                    ? SizedBox(
                        width: double.infinity, 
                        child: _vercelButton(text: t("Згенерувати ключ", "Generate Backup"), onPressed: () async {
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
                        })
                      )
                    : ShineButton(
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
                      border: Border.all(color: accent.withValues(alpha: 0.5)),
                    ),
                    child: SelectableText(backupToken!,
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontFamily: 'monospace')),
                  ),
                  const SizedBox(height: 16),
                  isDesktopView 
                    ? SizedBox(width: double.infinity, child: _vercelButton(text: t("Скопіювати ключ", "Copy Backup Key"), onPressed: () {
                        Clipboard.setData(ClipboardData(text: backupToken!));
                        _showSnack(t("Скопійовано в буфер", "Copied to clipboard"));
                        Navigator.pop(context);
                      }))
                    : ElegantButton(
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

  void _showUserProfile(String partnerName, String? initialAvatar, String? publicKey, bool isGroup, {String? initialDisplayName}) {
    if (isGroup || partnerName == widget.userName) return;
    final accent = _accentColors[_accentColor] ?? const Color(0xFFB026FF);
    String? currentBio;
    String? currentAvatar = initialAvatar;
    String? currentDisplayName = initialDisplayName;
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
                    currentDisplayName = data['displayName'] ?? currentDisplayName;
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
                            Text((currentDisplayName != null && currentDisplayName!.trim().isNotEmpty) ? currentDisplayName!.trim() : partnerName,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 24,
                                    fontWeight: FontWeight.bold, letterSpacing: -0.5)),
                            if (isVerifiedUser) ...[const SizedBox(width: 8), VerifiedBadge(size: 22, color: accent)],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text('@$partnerName', style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 13)),
                        if (currentBio != null && currentBio!.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(currentBio!, textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 15)),
                        ],
                        const SizedBox(height: 32),
                        _surface(
                          child: Column(children: [
                            ListTile(
                              leading: const Icon(Icons.chat_bubble_outline, color: Colors.white),
                              title: Text(t("Написати", "Message"),
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                              onTap: () {
                                Navigator.pop(context);
                                _startChat(partnerName, publicKey,
                                    targetAvatar: currentAvatar,
                                    targetDisplayName: currentDisplayName,
                                    isVerified: isVerifiedUser);
                              },
                            ),
                            Divider(height: 1, indent: 50, color: Colors.white.withValues(alpha: 0.1)),
                            ListTile(
                              leading: Icon(isPinned ? Icons.push_pin : Icons.push_pin_outlined, color: Colors.white),
                              title: Text(isPinned ? t("Відкріпити чат", "Unpin Chat") : t("Закріпити чат", "Pin Chat"),
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                              onTap: () {
                                _applyLocalChatSettings(
                                  partnerName,
                                  isPinned: !isPinned,
                                  isHidden: chatSettings?['isHidden'] == true,
                                  isBlocked: isBlocked,
                                );
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
                                _applyLocalChatSettings(
                                  partnerName,
                                  isPinned: isPinned,
                                  isHidden: true,
                                  isBlocked: isBlocked,
                                );
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
                        _surface(
                          child: Column(children: [
                            ListTile(
                              leading: Icon(isBlocked ? Icons.lock_open : Icons.block,
                                  color: const Color(0xFFFF3B30)),
                              title: Text(isBlocked ? t("Розблокувати", "Unblock") : t("Заблокувати", "Block"),
                                  style: const TextStyle(color: Color(0xFFFF3B30), fontWeight: FontWeight.w500)),
                              onTap: () {
                                _applyLocalChatSettings(
                                  partnerName,
                                  isPinned: isPinned,
                                  isHidden: chatSettings?['isHidden'] == true,
                                  isBlocked: !isBlocked,
                                );
                                _bgSocket.emit('update_chat_settings', {
                                  'userName': widget.userName, 'partnerName': partnerName,
                                  'isPinned': isPinned, 'isHidden': chatSettings?['isHidden'] == true,
                                  'isDeleted': false, 'isBlocked': !isBlocked,
                                });
                                setStateSB(() { isBlocked = !isBlocked; });
                              },
                            ),
                            Divider(height: 1, indent: 50, color: Colors.white.withValues(alpha: 0.1)),
                            ListTile(
                              leading: const Icon(Icons.delete_outline, color: Color(0xFFFF3B30)),
                              title: Text(t("Видалити історію", "Delete History"),
                                  style: const TextStyle(color: Color(0xFFFF3B30), fontWeight: FontWeight.w500)),
                              onTap: () {
                                _applyLocalChatSettings(
                                  partnerName,
                                  isPinned: false,
                                  isHidden: false,
                                  isBlocked: isBlocked,
                                  isDeleted: true,
                                );
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
                      _applyLocalChatSettings(
                        chat['partnerName'],
                        isPinned: !(chat['isPinned'] == true),
                        isHidden: chat['isHidden'] == true,
                        isBlocked: chat['isBlocked'] == true,
                      );
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
                      _applyLocalChatSettings(
                        chat['partnerName'],
                        isPinned: chat['isPinned'] == true,
                        isHidden: true,
                        isBlocked: chat['isBlocked'] == true,
                      );
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
                      _applyLocalChatSettings(
                        chat['partnerName'],
                        isPinned: false,
                        isHidden: false,
                        isBlocked: chat['isBlocked'] == true,
                        isDeleted: true,
                      );
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
                        separatorBuilder: (_, _) => _divider(),
                        itemBuilder: (context, i) {
                          final u = blocked[i];
                          return ListTile(
                            leading: SafeAvatar(
                                avatarBase64: u['avatar'], fallbackName: u['partnerName'], radius: 20),
                            title: Text(u['partnerName'],
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                            trailing: GestureDetector(
                              onTap: () {
                                _applyLocalChatSettings(
                                  u['partnerName'],
                                  isPinned: u['isPinned'] == true,
                                  isHidden: u['isHidden'] == true,
                                  isBlocked: false,
                                );
                                _bgSocket.emit('update_chat_settings', {
                                  'userName': widget.userName, 'partnerName': u['partnerName'],
                                  'isPinned': u['isPinned'] == true, 'isHidden': u['isHidden'] == true,
                                  'isDeleted': false, 'isBlocked': false,
                                });
                                Navigator.pop(context);
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

  void _startChat(
    String targetName,
    String? targetKey, {
    String? targetAvatar,
    String? targetDisplayName,
    bool isVerified = false,
  }) {
    if (targetName.isEmpty) return;
    if (targetKey != null) {
      _openChatScreen(
        targetName,
        targetKey,
        avatar: targetAvatar,
        displayName: targetDisplayName,
        isVerified: isVerified,
      );
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
          avatar: response['avatar'],
          displayName: response['displayName'],
          isVerified: response['isVerified'] == true);
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

  void _openChatScreen(
    String targetName,
    String targetKey, {
    String? avatar,
    String? displayName,
    bool isVerified = false,
  }) {
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
          partnerDisplayName: displayName,
          partnerIsVerified: isVerified,
          friends: _friends,
        ),
      ),
    ).then((_) => _loadData());
  }

  Widget _buildChatsTab() {
    final accent = _accentColors[_accentColor] ?? const Color(0xFFB026FF);
    final isDesktopPlatform = !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
    if (_recentChats.isEmpty && _desktopSelectedChatIndex != 0) {
      _desktopSelectedChatIndex = 0;
    } else if (_recentChats.isNotEmpty && _desktopSelectedChatIndex >= _recentChats.length) {
      _desktopSelectedChatIndex = _recentChats.length - 1;
    }
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
              : Focus(
                  autofocus: isDesktopPlatform && _currentIndex == 0,
                  onKeyEvent: (node, event) {
                    if (!isDesktopPlatform || event is! KeyDownEvent) return KeyEventResult.ignored;
                    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                      _moveDesktopChatSelection(1);
                      return KeyEventResult.handled;
                    }
                    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                      _moveDesktopChatSelection(-1);
                      return KeyEventResult.handled;
                    }
                    if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter) {
                      _openSelectedDesktopChat();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: ListView.separated(
                    controller: isDesktopPlatform ? _desktopChatsScrollController : null,
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
                    final chatDisplayName = (chat['displayName'] ?? '').toString().trim();
                    final chatVerified = chat['isVerified'] == true;
                    final tile = ListTile(
                      mouseCursor: SystemMouseCursors.click,
                      hoverColor: isDesktopView ? const Color(0xFF111111) : Colors.white.withValues(alpha: 0.04),
                      selected: isDesktopPlatform && index == _desktopSelectedChatIndex,
                      selectedColor: Colors.white,
                      selectedTileColor: isDesktopView ? const Color(0xFF1A1A1A) : Colors.white.withValues(alpha: 0.08),
                      shape: isDesktopView ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)) : null,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      leading: isSelf
                          ? CircleAvatar(
                              radius: 24,
                              backgroundColor: Colors.white.withValues(alpha: 0.1),
                              child: const Icon(Icons.bookmark, color: Colors.white70),
                            )
                          : Tooltip(
                              message: t('Профіль', 'Profile'),
                              waitDuration: const Duration(milliseconds: 280),
                              child: MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: GestureDetector(
                                  onTap: () => _showUserProfile(
                                    chat['partnerName'],
                                    chat['avatar'],
                                    chat['publicKey'],
                                    isGroup,
                                    initialDisplayName: chat['displayName'],
                                  ),
                                  child: StoryRingAvatar(
                                    avatarBase64: chat['avatar'],
                                    fallbackName: chat['partnerName'],
                                    radius: 24,
                                    isGroup: isGroup,
                                    hasUnread: unreadCount > 0,
                                  ),
                                ),
                              ),
                            ),
                      title: Row(
                        children: [
                          Expanded(
                            child: isSelf
                                ? Text(
                                    t("Нотатник", "Saved Messages"),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16,
                                      letterSpacing: -0.2,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  )
                                : Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              chatDisplayName.isNotEmpty ? chatDisplayName : chat['partnerName'],
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 16,
                                                letterSpacing: -0.2,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (!isGroup && chatVerified) ...[
                                            const SizedBox(width: 4),
                                            VerifiedBadge(size: 14, color: accent),
                                          ],
                                        ],
                                      ),
                                      Text(
                                        '@${chat['partnerName']}',
                                        style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                          ),
                          if (chat['isPinned'] == true) ...[
                            const SizedBox(width: 4),
                            Icon(Icons.push_pin, color: Colors.white.withValues(alpha: 0.5), size: 14),
                          ],
                        ],
                      ),
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
                        onTap: () {
                          if (isDesktopPlatform && _desktopSelectedChatIndex != index) {
                            setState(() => _desktopSelectedChatIndex = index);
                          }
                          _startChat(chat['partnerName'], chat['publicKey'],
                            targetAvatar: chat['avatar'],
                            targetDisplayName: chat['displayName'],
                            isVerified: chatVerified);
                        },
                    );
                    if (kIsWeb || Platform.isAndroid || Platform.isIOS) {
                      return tile;
                    } else {
                      return Tooltip(
                        message: t('Відкрити чат', 'Open chat'),
                        waitDuration: const Duration(milliseconds: 260),
                        child: tile,
                      );
                    }
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildFriendsTab() {
    final accent = _accentColors[_accentColor] ?? const Color(0xFFB026FF);
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
              child: isDesktopView
                ? _vercelInput(
                    controller: _addFriendController,
                    hintText: t("Нікнейм", "Username"),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_.\-]'))],
                  )
                : GlassInput(
                    controller: _addFriendController,
                    hintText: t("Нікнейм", "Username"),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_.\-]'))],
                  ),
            ),
            const SizedBox(width: 10),
            isDesktopView 
              ? _vercelButton(text: t("ДОДАТИ", "ADD"), onPressed: _sendFriendRequest)
              : ElegantButton(text: t("ДОДАТИ", "ADD"), onPressed: _sendFriendRequest),
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
          _surface(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: _pendingRequests.asMap().entries.map((entry) {
                int idx = entry.key;
                var req = entry.value;
                return Column(children: [
                  ListTile(
                    leading: GestureDetector(
                      onTap: () => _showUserProfile(req['userName'], req['avatar'], null, false, initialDisplayName: req['displayName']),
                      child: SafeAvatar(avatarBase64: req['avatar'], fallbackName: req['userName'], radius: 20),
                    ),
                    title: Row(children: [
                      Flexible(
                        child: Text(
                            (req['displayName'] ?? '').toString().trim().isNotEmpty ? req['displayName'] : req['userName'],
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 16),
                            overflow: TextOverflow.ellipsis),
                      ),
                      if (req['isVerified'] == 1) ...[const SizedBox(width: 5), VerifiedBadge(size: 13, color: accent)],
                    ]),
                    subtitle: Text('@${req['userName']}', style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12)),
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
            : _surface(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: _friends.asMap().entries.map((entry) {
                    int idx = entry.key;
                    var f = entry.value;
                    return Column(children: [
                      ListTile(
                        leading: GestureDetector(
                          onTap: () => _showUserProfile(f['userName'], f['avatar'], f['publicKey'], false, initialDisplayName: f['displayName']),
                          child: SafeAvatar(avatarBase64: f['avatar'], fallbackName: f['userName'], radius: 20),
                        ),
                        title: Row(children: [
                          Flexible(
                            child: Text(
                                (f['displayName'] ?? '').toString().trim().isNotEmpty ? f['displayName'] : f['userName'],
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 16),
                                overflow: TextOverflow.ellipsis),
                          ),
                          if (f['isVerified'] == true || f['isVerified'] == 1) ...[
                            const SizedBox(width: 5), VerifiedBadge(size: 13, color: accent),
                          ],
                        ]),
                        subtitle: Text('@${f['userName']}', style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12)),
                        onTap: () => _startChat(f['userName'], f['publicKey'],
                          targetAvatar: f['avatar'],
                          targetDisplayName: f['displayName'],
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

  Widget _buildSettingsTab() {
    final accent = _accentColors[_accentColor]!;

    return ListView(
      padding: const EdgeInsets.only(top: 0, bottom: 120),
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 20, 16, 0),
          child: GestureDetector(
            onTap: _showEditProfileSheet,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDesktopView ? const Color(0xFF0A0A0A) : Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(isDesktopView ? 8 : 20),
                border: Border.all(color: isDesktopView ? const Color(0xFF1A1A1A) : Colors.white.withValues(alpha: 0.1), width: 1),
              ),
              child: Row(
              children: [
                GestureDetector(
                  onTap: _updateAvatar,
                  child: SafeAvatar(avatarBase64: _myAvatar, fallbackName: widget.userName, radius: 34),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Flexible(
                          child: Text(_myDisplayName.isNotEmpty ? _myDisplayName : widget.userName,
                              style: const TextStyle(
                                color: Colors.white, fontSize: 18,
                                fontWeight: FontWeight.w700, letterSpacing: -0.4,
                              ),
                              overflow: TextOverflow.ellipsis),
                        ),
                        if (_myVerified) ...[const SizedBox(width: 6), VerifiedBadge(size: 16, color: accent)],
                      ]),
                      const SizedBox(height: 2),
                      Text('@${widget.userName}', style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12)),
                      const SizedBox(height: 4),
                      GestureDetector(
                        onTap: _showEditProfileSheet,
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
        ),

        _sectionHeader(t("СПОВІЩЕННЯ", "NOTIFICATIONS")),
        _surface(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(children: [
            _settingToggle(
              icon: Icons.notifications_rounded, iconColor: accent,
              title: t("Сповіщення", "Notifications"),
              value: _notificationsEnabled,
              onChanged: (v) {
                setState(() => _notificationsEnabled = v);
                _saveSetting('notif_enabled', v);
                _syncPrivacyToBackend();
                if (!v) {
                  _bgSocket.emit('update_fcm_token', {'userName': widget.userName, 'token': ''});
                } else {
                  unawaited(_initWebPushIfNeeded());
                }
              },
              accent: accent,
            ),
            _divider(),
            _settingToggle(
              icon: Icons.volume_up_rounded, iconColor: accent,
              title: t("Звук", "Sound"),
              value: _soundEnabled, enabled: _notificationsEnabled,
              onChanged: (v) { setState(() => _soundEnabled = v); _saveSetting('sound_enabled', v); },
              accent: accent,
            ),
            _divider(),
            _settingToggle(
              icon: Icons.vibration_rounded, iconColor: accent,
              title: t("Вібрація", "Vibration"),
              value: _vibrationEnabled, enabled: _notificationsEnabled,
              onChanged: (v) { setState(() => _vibrationEnabled = v); _saveSetting('vibration_enabled', v); },
              accent: accent,
            ),
            _divider(),
            _settingToggle(
              icon: Icons.chat_bubble_outline_rounded, iconColor: accent,
              title: t("Попередній перегляд", "Message Preview"),
              subtitle: t("Показувати текст у сповіщенні", "Show text in notification"),
              value: _messagePreview, enabled: _notificationsEnabled,
              onChanged: (v) {
                setState(() => _messagePreview = v);
                _saveSetting('message_preview', v);
                _syncPrivacyToBackend();
              },
              accent: accent,
            ),
          ]),
        ),

        _sectionHeader(t("КОНФІДЕНЦІЙНІСТЬ", "PRIVACY")),
        _surface(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(children: [
            _settingToggle(
              icon: Icons.done_all_rounded, iconColor: accent,
              title: t("Прочитано", "Read Receipts"),
              subtitle: t("Показувати коли прочитали", "Show when you've read messages"),
              value: _readReceipts,
              onChanged: (v) {
                setState(() => _readReceipts = v);
                _saveSetting('read_receipts', v);
                _syncPrivacyToBackend();
              },
              accent: accent,
            ),
            _divider(),
            _settingToggle(
              icon: Icons.circle_rounded, iconColor: accent,
              title: t("Статус онлайн", "Online Status"),
              subtitle: t("Показувати коли ви в мережі", "Show when you're online"),
              value: _onlineStatus,
              onChanged: (v) {
                setState(() => _onlineStatus = v);
                _saveSetting('online_status', v);
                _emitSetActive();
                _syncPrivacyToBackend();
              },
              accent: accent,
            ),
            _divider(),
            _settingToggle(
              icon: Icons.keyboard_rounded, iconColor: accent,
              title: t("Введення...", "Typing Indicator"),
              subtitle: t("Показувати коли пишете", "Show when you're typing"),
              value: _typingIndicator,
              onChanged: (v) {
                setState(() => _typingIndicator = v);
                _saveSetting('typing_indicator', v);
                _syncPrivacyToBackend();
              },
              accent: accent,
            ),
            _divider(),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              leading: _settingIcon(Icons.alternate_email_rounded, accent),
              title: Text(
                t("Хто може писати", "Who can message"),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 15),
              ),
              subtitle: Text(
                _dmPermissionLabel(_dmPermission),
                style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12),
              ),
              trailing: Icon(Icons.chevron_right_rounded, color: Colors.white24, size: 20),
              onTap: () async {
                final selected = await showModalBottomSheet<String>(
                  context: context,
                  backgroundColor: const Color(0xFF121212),
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  builder: (ctx) => SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          leading: const Icon(Icons.public_rounded, color: Colors.white),
                          title: Text(t('Всі', 'Everyone'), style: const TextStyle(color: Colors.white)),
                          subtitle: Text(
                            t('Писати може будь-хто', 'Anyone can message you'),
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12),
                          ),
                          trailing: _dmPermission == 'everyone' ? Icon(Icons.check_rounded, color: accent) : null,
                          onTap: () => Navigator.pop(ctx, 'everyone'),
                        ),
                        ListTile(
                          leading: const Icon(Icons.groups_rounded, color: Colors.white),
                          title: Text(t('Друзі або спільні групи', 'Friends or shared groups'), style: const TextStyle(color: Colors.white)),
                          subtitle: Text(
                            t('Писати можуть друзі та користувачі зі спільних груп', 'Friends and users from shared groups can message you'),
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12),
                          ),
                          trailing: _dmPermission == 'friends_or_groups' ? Icon(Icons.check_rounded, color: accent) : null,
                          onTap: () => Navigator.pop(ctx, 'friends_or_groups'),
                        ),
                        ListTile(
                          leading: const Icon(Icons.people_alt_rounded, color: Colors.white),
                          title: Text(t('Тільки друзі', 'Friends only'), style: const TextStyle(color: Colors.white)),
                          subtitle: Text(
                            t('Писати можуть лише користувачі зі списку друзів', 'Only users in your friends list can message you'),
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12),
                          ),
                          trailing: _dmPermission == 'friends_only' ? Icon(Icons.check_rounded, color: accent) : null,
                          onTap: () => Navigator.pop(ctx, 'friends_only'),
                        ),
                        const SizedBox(height: 6),
                      ],
                    ),
                  ),
                );

                if (selected != null && selected != _dmPermission) {
                  setState(() => _dmPermission = selected);
                  await _saveSetting('dm_permission', selected);
                  _syncPrivacyToBackend();
                }
              },
            ),
          ]),
        ),

        _sectionHeader(t("БЕЗПЕКА", "SECURITY")),
        _surface(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(children: [
            _settingToggle(
              icon: Icons.lock_rounded, iconColor: accent,
              title: t("Системний захист", "System Lock"),
              subtitle: _systemLockEnabled
                  ? (Platform.isIOS && _useFaceIdOnIOS
                      ? t("Увімкнено (Face ID)", "Enabled (Face ID)")
                      : t("Увімкнено (пароль пристрою)", "Enabled (device passcode)"))
                  : t("Вимкнено", "Disabled"),
              value: _systemLockEnabled,
              onChanged: (val) => _toggleSystemLock(val),
              accent: accent,
            ),
            _divider(),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              leading: _settingIcon(Icons.vpn_key_rounded, accent),
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
              leading: _settingIcon(Icons.devices_rounded, accent),
              title: Text(t("Пристрої", "Devices"),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 15)),
              subtitle: Text(t("Керування активними пристроями", "Manage active devices"),
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12)),
              trailing: Icon(Icons.chevron_right_rounded, color: Colors.white24, size: 20),
              onTap: _showMyDevicesSheet,
            ),
            _divider(),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              leading: _settingIcon(Icons.block_rounded, accent),
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

        _sectionHeader(t("ЗОВНІШНІЙ ВИГЛЯД", "APPEARANCE")),
        _surface(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(children: [
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
                              ? Icon(
                                  Icons.check_rounded,
                                  color: ThemeData.estimateBrightnessForColor(e.value) == Brightness.dark
                                      ? Colors.white
                                      : Colors.black,
                                  size: 16,
                                )
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            _divider(),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              leading: _settingIcon(Icons.format_size_rounded, accent),
              title: Text(
                t("Розмір тексту", "Text Size"),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 15),
              ),
              subtitle: Text(
                '${_chatFontSize.round()} px',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
              ),
              trailing: Icon(Icons.chevron_right_rounded, color: Colors.white24, size: 20),
              onTap: () => _showTextSizeSheet(accent),
            ),
            _divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    _settingIcon(Icons.chat_bubble_rounded, accent),
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
              icon: Icons.view_compact_rounded, iconColor: accent,
              title: t("Компактний режим", "Compact Mode"),
              subtitle: t("Менші відступи у чатах", "Smaller padding in chats"),
              value: _compactMode,
              onChanged: (v) { setState(() => _compactMode = v); _saveSetting('compact_mode', v); },
              accent: accent,
            ),
          ]),
        ),

        _sectionHeader(t("МОВА", "LANGUAGE")),
        _surface(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(children: [
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              leading: const Text("🇺🇦", style: TextStyle(fontSize: 22)),
              title: Text(t("Українська", "Ukrainian"),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 15)),
              trailing: lang == 'uk' ? Icon(Icons.check_rounded, color: accent) : null,
              onTap: () => _changeLanguage('uk'),
            ),
            _divider(),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              leading: const Text("🇬🇧", style: TextStyle(fontSize: 22)),
              title: Text(t("Англійська", "English"),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 15)),
              trailing: lang == 'en' ? Icon(Icons.check_rounded, color: accent) : null,
              onTap: () => _changeLanguage('en'),
            ),
          ]),
        ),

        if (_isAdmin) ...[
          _sectionHeader(t("АДМІН-ПАНЕЛЬ", "ADMIN PANEL"), icon: VerifiedBadge(size: 13, color: accent)),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Expanded(
                child: isDesktopView
                  ? _vercelInput(controller: _verifySearchController, hintText: t("Пошук користувача...", "Search user..."), inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_.\-]'))])
                  : GlassInput(
                      controller: _verifySearchController,
                      hintText: t("Пошук користувача...", "Search user..."),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_.\-]'))],
                    ),
              ),
              const SizedBox(width: 10),
              isDesktopView
                ? _vercelButton(text: t("ЗНАЙТИ", "FIND"), onPressed: _searchUsersForVerify)
                : ElegantButton(text: t("ЗНАЙТИ", "FIND"), onPressed: _searchUsersForVerify),
            ]),
          ),
          if (_verifyResults.isNotEmpty) ...[
            const SizedBox(height: 12),
            _surface(
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
                        if (isVerified) ...[const SizedBox(width: 6), VerifiedBadge(size: 13, color: accent)],
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

        const SizedBox(height: 32),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GestureDetector(
            onTap: _logout,
            child: Container(
              height: 50,
              decoration: BoxDecoration(
                color: isDesktopView ? Colors.black : Colors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(isDesktopView ? 8 : 50),
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
          child: Text(t("Lumyn • версія 1.0.0", "Lumyn • v1.0.0"),
              style: TextStyle(color: Colors.white.withValues(alpha: 0.15), fontSize: 11)),
        ),
      ],
    );
  }

  void _showTextSizeSheet(Color accent) {
    final previewChats = _recentChats.take(6).toList();
    final sampleNames = previewChats
        .map((c) => ((c['displayName'] ?? c['partnerName']) ?? '').toString().trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final sampleTexts = previewChats
        .map((c) => (c['decryptedText'] ?? '').toString().trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final PageController pageController = PageController(viewportFraction: 0.98);
    final ValueNotifier<int> pageIdx = ValueNotifier<int>(0);
    double tempSize = _chatFontSize;
    bool useSystemSize = false;

    String nameOrFallback(int idx, String fallback) {
      if (sampleNames.isEmpty) return fallback;
      return sampleNames[idx % sampleNames.length];
    }

    String textOrFallback(int idx, String fallback) {
      if (sampleTexts.isEmpty) return fallback;
      return sampleTexts[idx % sampleTexts.length];
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateSB) {
            final mediaScale = MediaQuery.of(ctx).textScaler.scale(1.0);
            final appliedFont = useSystemSize ? tempSize * mediaScale : tempSize;

            return Container(
              decoration: const BoxDecoration(
                color: Color(0xFF16171B),
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 38,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                      Text(
                        t("Розмір тексту", "Text Size"),
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 360,
                        child: PageView(
                          controller: pageController,
                          onPageChanged: (i) => pageIdx.value = i,
                          children: [
                            Container(
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF111216),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
                                child: Column(
                                  children: [
                                    Expanded(
                                      child: ListView(
                                        physics: const NeverScrollableScrollPhysics(),
                                        children: [
                                          Align(
                                            alignment: Alignment.centerRight,
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFD5AF73),
                                                borderRadius: BorderRadius.circular(14),
                                              ),
                                              child: Text(
                                                textOrFallback(0, t("Він щось довго пояснював 🙂", "He was explaining for a while 🙂")),
                                                style: TextStyle(color: Colors.white, fontSize: appliedFont),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF1D2128),
                                              borderRadius: BorderRadius.circular(14),
                                            ),
                                            child: Text(
                                              textOrFallback(1, t("Голову праворуч і виразно.", "Turn your head right and clearly.")),
                                              style: TextStyle(color: Colors.white, fontSize: appliedFont),
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Align(
                                            alignment: Alignment.centerRight,
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFD5AF73),
                                                borderRadius: BorderRadius.circular(14),
                                              ),
                                              child: Text(
                                                textOrFallback(2, t("І все? Звучало довше 🤔", "And that's all? It sounded longer 🤔")),
                                                style: TextStyle(color: Colors.white, fontSize: appliedFont),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Container(
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF111216),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                              ),
                              child: ListView.separated(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: 6,
                                separatorBuilder: (_, _) => Divider(height: 1, indent: 72, color: Colors.white.withValues(alpha: 0.05)),
                                itemBuilder: (context, i) {
                                  final name = nameOrFallback(i, t("Контакт", "Contact"));
                                  final preview = textOrFallback(i, t("Тестове повідомлення", "Test message"));
                                  return ListTile(
                                        leading: CircleAvatar(
                                          radius: 20,
                                          backgroundColor: Colors.white.withValues(alpha: 0.08),
                                          child: const Icon(Icons.person, color: Colors.white70),
                                        ),
                                        title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                                        subtitle: Text(
                                          preview,
                                          style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: appliedFont),
                                          maxLines: 1, overflow: TextOverflow.ellipsis,
                                        ),
                                      );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      ValueListenableBuilder<int>(
                        valueListenable: pageIdx,
                        builder: (ctx, idx, _) => Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [0, 1].map((i) => Container(
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: 8, height: 8,
                            decoration: BoxDecoration(
                              color: i == idx ? accent : Colors.white24,
                              shape: BoxShape.circle,
                            ),
                          )).toList(),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          const Text("A", style: TextStyle(color: Colors.white70, fontSize: 14)),
                          Expanded(
                            child: SliderTheme(
                              data: SliderThemeData(
                                activeTrackColor: accent,
                                inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
                                thumbColor: accent,
                                overlayColor: accent.withValues(alpha: 0.2),
                                trackHeight: 4,
                              ),
                              child: Slider(
                                value: tempSize,
                                min: 12.0, max: 24.0, divisions: 12,
                                onChanged: useSystemSize ? null : (val) => setStateSB(() => tempSize = val),
                              ),
                            ),
                          ),
                          const Text("A", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w500)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: ThemeData.estimateBrightnessForColor(accent) == Brightness.dark ? Colors.white : Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () {
                            setState(() { _chatFontSize = tempSize; });
                            _saveSetting('chat_font_size', tempSize);
                            Navigator.pop(ctx);
                          },
                          child: Text(t("Застосувати", "Apply"), style: const TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _divider() => Divider(height: 1, indent: 16, endIndent: 16, color: Colors.white.withValues(alpha: 0.05));

  Widget _sectionHeader(String title, {Widget? icon}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 24, 8),
      child: Row(
        children: [
          Text(title, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
          if (icon != null) ...[const SizedBox(width: 6), icon],
        ],
      ),
    );
  }

  Widget _settingIcon(IconData icon, Color accent) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: accent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
      child: Icon(icon, color: accent, size: 20),
    );
  }

  Widget _settingToggle({
    required IconData icon, required Color iconColor, required String title, String? subtitle,
    required bool value, required ValueChanged<bool> onChanged, required Color accent, bool enabled = true,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      enabled: enabled,
      leading: _settingIcon(icon, iconColor),
      title: Text(title, style: TextStyle(color: enabled ? Colors.white : Colors.white54, fontWeight: FontWeight.w500, fontSize: 15)),
      subtitle: subtitle != null ? Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12)) : null,
      trailing: Switch(
        value: value, onChanged: enabled ? onChanged : null,
        activeThumbColor: Colors.white, activeTrackColor: accent,
        inactiveThumbColor: Colors.white54, inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
      ),
      onTap: enabled ? () => onChanged(!value) : null,
    );
  }

  Widget _bubbleOption(String value, String label, Color accent) {
    final isSelected = _chatBubbleStyle == value;
    BorderRadius radius;
    if (value == 'sharp') {
      radius = const BorderRadius.only(topLeft: Radius.circular(8), topRight: Radius.circular(8), bottomLeft: Radius.circular(8), bottomRight: Radius.circular(2));
    } else if (value == 'minimal') {
      radius = BorderRadius.circular(6);
    } else {
      radius = const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16), bottomLeft: Radius.circular(16), bottomRight: Radius.circular(4));
    }
    return GestureDetector(
      onTap: () { setState(() => _chatBubbleStyle = value); _saveSetting('bubble_style', value); },
      child: Column(
        children: [
          Container(
            width: 60, height: 40,
            decoration: BoxDecoration(
              color: isSelected ? accent : Colors.white.withValues(alpha: 0.05),
              borderRadius: radius,
              border: Border.all(color: isSelected ? accent : Colors.white.withValues(alpha: 0.1), width: 2),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.abc, color: isSelected ? (ThemeData.estimateBrightnessForColor(accent) == Brightness.dark ? Colors.white : Colors.black) : Colors.white54),
          ),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.white54, fontSize: 12, fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal)),
        ],
      ),
    );
  }

  void _moveDesktopChatSelection(int delta) {
    if (_recentChats.isEmpty) return;
    setState(() {
      _desktopSelectedChatIndex = (_desktopSelectedChatIndex + delta).clamp(0, _recentChats.length - 1);
    });
    if (_desktopChatsScrollController.hasClients) {
      final targetOffset = _desktopSelectedChatIndex * 64.0;
      final maxExtent = _desktopChatsScrollController.position.maxScrollExtent;
      final currentOffset = _desktopChatsScrollController.offset;
      final viewport = _desktopChatsScrollController.position.viewportDimension;
      if (targetOffset < currentOffset) {
        _desktopChatsScrollController.jumpTo(targetOffset);
      } else if (targetOffset > currentOffset + viewport - 64) {
        _desktopChatsScrollController.jumpTo((targetOffset - viewport + 64).clamp(0.0, maxExtent));
      }
    }
  }

  void _openSelectedDesktopChat() {
    if (_recentChats.isEmpty || _desktopSelectedChatIndex < 0 || _desktopSelectedChatIndex >= _recentChats.length) return;
    final chat = _recentChats[_desktopSelectedChatIndex];
    _startChat(chat['partnerName'], chat['publicKey'], targetAvatar: chat['avatar'], targetDisplayName: chat['displayName'], isVerified: chat['isVerified'] == true);
  }

  @override
  Widget build(BuildContext context) {
    if (_isAppLocked) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Positioned.fill(child: LiquidBackground(child: Container())),
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child: Container(color: Colors.black.withValues(alpha: 0.5)),
            ),
            SafeArea(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _AppleLockIcon(accent: _accentColors[_accentColor] ?? Colors.white),
                    const SizedBox(height: 24),
                    Text(t("Додаток заблоковано", "App Locked"), style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: -0.5)),
                    const SizedBox(height: 8),
                    Text(t("Для доступу підтвердіть особу", "Authenticate to gain access"), style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 15)),
                    const SizedBox(height: 48),
                    if (_authInProgress)
                      const CircularProgressIndicator(color: Colors.white)
                    else
                      ElevatedButton.icon(
                        onPressed: _unlockWithSystemAuth,
                        icon: const Icon(Icons.fingerprint, color: Colors.black),
                        label: Text(t("Розблокувати", "Unlock"), style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    final isDesktopPlatform = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    final accent = _accentColors[_accentColor] ?? const Color(0xFFB026FF);

    Widget body = SafeArea(
      child: Column(
        children: [
          if (!isDesktopView)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _currentIndex == 0 ? t("Чати", "Chats") : (_currentIndex == 1 ? t("Друзі", "Friends") : t("Налаштування", "Settings")),
                    style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.5),
                  ),
                  if (_currentIndex == 0)
                    Row(
                      children: [
                        GestureDetector(
                          onTap: _showCreateGroupDialog,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), shape: BoxShape.circle),
                            child: const Icon(Icons.group_add, color: Colors.white, size: 22),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          Expanded(
            child: isDesktopPlatform
              ? _buildAnimatedTabPage(_currentIndex)
              : PageView(
                  controller: _pageController,
                  onPageChanged: (i) => setState(() => _currentIndex = i),
                  children: [ _buildChatsTab(), _buildFriendsTab(), _buildSettingsTab() ],
                ),
          ),
        ],
      ),
    );

    if (isDesktopView) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Row(
          children: [
            Container(
              width: 260,
              decoration: const BoxDecoration(
                color: Color(0xFF000000),
                border: Border(right: BorderSide(color: Color(0xFF1A1A1A), width: 1)),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("LUMYN", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 2)),
                        if (_currentIndex == 0)
                          Tooltip(
                            message: t("Створити групу", "Create Group"),
                            child: MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: GestureDetector(
                                onTap: _showCreateGroupDialog,
                                child: const Icon(Icons.group_add, color: Colors.white70, size: 20),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      children: [
                        _DesktopNavItem(
                          icon: Icons.chat_bubble_outline,
                          activeIcon: Icons.chat_bubble,
                          label: t("Чати", "Chats"),
                          isSelected: _currentIndex == 0,
                          onTap: () => _onTabSelected(0),
                        ),
                        const SizedBox(height: 4),
                        _DesktopNavItem(
                          icon: Icons.people_outline,
                          activeIcon: Icons.people,
                          label: t("Друзі", "Friends"),
                          isSelected: _currentIndex == 1,
                          onTap: () => _onTabSelected(1),
                          badgeCount: _pendingRequests.length,
                        ),
                        const SizedBox(height: 4),
                        _DesktopNavItem(
                          icon: Icons.settings_outlined,
                          activeIcon: Icons.settings,
                          label: t("Налаштування", "Settings"),
                          isSelected: _currentIndex == 2,
                          onTap: () => _onTabSelected(2),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Row(
                      children: [
                        SafeAvatar(avatarBase64: _myAvatar, fallbackName: widget.userName, radius: 16),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _myDisplayName.isNotEmpty ? _myDisplayName : widget.userName,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 14),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Shortcuts(
                shortcuts: const <ShortcutActivator, Intent>{
                  SingleActivator(LogicalKeyboardKey.digit1, control: true): _SwitchTabIntent(0),
                  SingleActivator(LogicalKeyboardKey.digit2, control: true): _SwitchTabIntent(1),
                  SingleActivator(LogicalKeyboardKey.digit3, control: true): _SwitchTabIntent(2),
                },
                child: Actions(
                  actions: <Type, Action<Intent>>{
                    _SwitchTabIntent: CallbackAction<_SwitchTabIntent>(onInvoke: (intent) {
                      _onTabSelected(intent.index);
                      return null;
                    }),
                  },
                  child: Focus(autofocus: true, child: body),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: _buildBackground(child: body),
      bottomNavigationBar: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.1), width: 0.5)),
            ),
            child: BottomNavigationBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              currentIndex: _currentIndex,
              onTap: (i) {
                setState(() {
                  _currentIndex = i;
                });
                // Перевірка для мобільного/веб формату
                if (_pageController.hasClients) {
                  _pageController.animateToPage(i, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
                }
              },
              selectedItemColor: accent,
              unselectedItemColor: Colors.white54,
              selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
              unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 11),
              items: [
                BottomNavigationBarItem(icon: const Icon(Icons.chat_bubble_outline), activeIcon: const Icon(Icons.chat_bubble), label: t("Чати", "Chats")),
                BottomNavigationBarItem(
                  icon: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Icon(Icons.people_outline),
                      if (_pendingRequests.isNotEmpty)
                        Positioned(
                          right: -4, top: -4,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(color: Color(0xFFFF3B30), shape: BoxShape.circle),
                            child: Text('${_pendingRequests.length}', style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                          ),
                        ),
                    ],
                  ),
                  activeIcon: const Icon(Icons.people),
                  label: t("Друзі", "Friends"),
                ),
                BottomNavigationBarItem(icon: const Icon(Icons.settings_outlined), activeIcon: const Icon(Icons.settings), label: t("Налаштування", "Settings")),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopNavItem extends StatefulWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final int badgeCount;

  const _DesktopNavItem({
    required this.icon, required this.activeIcon, required this.label, required this.isSelected, required this.onTap, this.badgeCount = 0,
  });

  @override
  State<_DesktopNavItem> createState() => _DesktopNavItemState();
}

class _DesktopNavItemState extends State<_DesktopNavItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: widget.isSelected ? const Color(0xFF1A1A1A) : (_isHovered ? const Color(0xFF111111) : Colors.transparent),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              Icon(widget.isSelected ? widget.activeIcon : widget.icon, color: widget.isSelected ? Colors.white : Colors.white70, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(color: widget.isSelected ? Colors.white : Colors.white70, fontWeight: widget.isSelected ? FontWeight.w600 : FontWeight.w500, fontSize: 14),
                ),
              ),
              if (widget.badgeCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                  child: Text('${widget.badgeCount}', style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
