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
import 'package:path_drawing/path_drawing.dart';
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
  bool _isLoadingData = false; // Prevent race condition in _loadData

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

  // ─────────────────────────────────────────────────────────
  // INIT / DISPOSE
  // ─────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentIndex);
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();

    _bgSocket = io.io('https://aether-backend-hrmq.onrender.com', {
      'transports': ['websocket'],
      'forceNew': true,
    });
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

  IconData _getDeviceIcon(Map<String, dynamic> device) {
    final deviceName = (device['deviceName'] ?? '').toString().toLowerCase();
    final deviceType = (device['deviceType'] ?? '').toString().toLowerCase();
    
    // Перевірити за deviceType спочатку
    if (deviceType.contains('iphone') || deviceType.contains('ios')) return Icons.phone_iphone_rounded;
    if (deviceType.contains('ipad')) return Icons.tablet_mac_rounded;
    if (deviceType.contains('mac') || deviceType.contains('macos')) return Icons.laptop_mac_rounded;
    if (deviceType.contains('windows')) return Icons.computer_rounded;
    if (deviceType.contains('android')) return Icons.android_rounded;
    if (deviceType.contains('linux')) return Icons.memory_rounded;
    
    // Потім перевірити за deviceName
    if (deviceName.contains('iphone')) return Icons.phone_iphone_rounded;
    if (deviceName.contains('ipad')) return Icons.tablet_mac_rounded;
    if (deviceName.contains('mac') || deviceName.contains('macbook')) return Icons.laptop_mac_rounded;
    if (deviceName.contains('windows') || deviceName.contains('pc')) return Icons.computer_rounded;
    if (deviceName.contains('android')) return Icons.android_rounded;
    if (deviceName.contains('linux')) return Icons.memory_rounded;
    if (deviceName.contains('web')) return Icons.language_rounded;
    
    return Icons.devices_other_rounded; // За замовчуванням
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
                          child: Icon(_getDeviceIcon(d), color: Colors.white70),
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

  void _syncSettingsToBackend() {
    if (!_bgSocket.connected) return;
    _bgSocket.emit('update_settings', {
      'userName': widget.userName,
      'accentColor': _accentColor,
      'chatFontSize': _chatFontSize,
      'chatBubbleStyle': _chatBubbleStyle,
      'compactMode': _compactMode,
      'soundEnabled': _soundEnabled,
      'vibrationEnabled': _vibrationEnabled,
      'myDisplayName': _myDisplayName,
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
    await _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 340),
      curve: Curves.easeInOutCubicEmphasized,
    );
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
    // Prevent multiple concurrent _loadData() calls (race condition)
    if (_isLoadingData) return;
    _isLoadingData = true;
    
    _bgSocket.emitWithAck('get_recent_chats', widget.userName, ack: (dynamic data) async {
      // Cancel if widget was disposed or another load finished
      if (!mounted) {
        _isLoadingData = false;
        return;
      }
      
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
      _isLoadingData = false;
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

  // ignore: unused_element
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
                          _syncSettingsToBackend();
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
                      border: Border.all(color: accent.withValues(alpha: 0.5)),
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
                        GlassContainer(
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
                        GlassContainer(
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

  // ─────────────────────────────────────────────────────────
  // LOCK SCREEN
  // ─────────────────────────────────────────────────────────
  Widget _buildLockScreen() {
    const accent = Color(0xFF5DA8FF);
    const deepBg = Color(0xFF0D1117);

    return Scaffold(
      backgroundColor: deepBg,
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF111827),
                    const Color(0xFF0B1020),
                    deepBg,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: -120,
            left: -100,
            child: Container(
              width: 340,
              height: 340,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withValues(alpha: 0.18),
              ),
            ),
          ),
          Positioned(
            bottom: -130,
            right: -80,
            child: Container(
              width: 380,
              height: 380,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.07),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                const Spacer(),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 30,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      const _AppleLockIcon(accent: accent),
                      const SizedBox(height: 14),
                      Text(
                        t("Захист Lumyn", "Lumyn Protection"),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        t("Використайте Face ID, відбиток або пароль пристрою", "Use Face ID, fingerprint, or your device passcode"),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.62), fontSize: 14, height: 1.4),
                      ),
                      const SizedBox(height: 18),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: Container(
                          key: ValueKey(_authInProgress),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: _authInProgress
                                ? accent.withValues(alpha: 0.2)
                                : Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: _authInProgress
                                  ? accent.withValues(alpha: 0.55)
                                  : Colors.white.withValues(alpha: 0.14),
                            ),
                          ),
                          child: Text(
                            _authInProgress
                                ? t("Перевірка системою...", "Checking system authentication...")
                                : t("Захищений вхід увімкнено", "Secure sign-in is enabled"),
                            style: TextStyle(
                              color: _authInProgress ? accent : Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _authInProgress ? null : _unlockWithSystemAuth,
                          icon: _authInProgress
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.black),
                                )
                              : const Icon(Icons.lock_open_rounded),
                          label: Text(_authInProgress
                              ? t("Перевірка...", "Authenticating...")
                              : t("Розблокувати", "Unlock")),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                            disabledBackgroundColor: Colors.white70,
                            disabledForegroundColor: Colors.black87,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        t("Якщо автентифікація скасована, натисніть кнопку ще раз", "If authentication is canceled, press the button again"),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const Spacer(flex: 2),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // TABS
  // ─────────────────────────────────────────────────────────
  void _moveDesktopChatSelection(int delta) {
    if (_recentChats.isEmpty) return;
    final maxIndex = _recentChats.length - 1;
    final next = (_desktopSelectedChatIndex + delta).clamp(0, maxIndex);
    if (next == _desktopSelectedChatIndex) return;
    setState(() => _desktopSelectedChatIndex = next);
    _scrollDesktopChatsToSelected();
  }

  void _scrollDesktopChatsToSelected() {
    if (!_desktopChatsScrollController.hasClients || _recentChats.isEmpty) return;
    final approxItemExtent = 84.0;
    final target = _desktopSelectedChatIndex * approxItemExtent;
    final max = _desktopChatsScrollController.position.maxScrollExtent;
    _desktopChatsScrollController.animateTo(
      target.clamp(0.0, max),
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
    );
  }

  void _openSelectedDesktopChat() {
    if (_recentChats.isEmpty) return;
    final maxIndex = _recentChats.length - 1;
    final selected = _desktopSelectedChatIndex.clamp(0, maxIndex);
    if (selected != _desktopSelectedChatIndex) {
      setState(() => _desktopSelectedChatIndex = selected);
    }
    final chat = _recentChats[selected];
    final chatVerified = chat['isVerified'] == true;
    _startChat(
      chat['partnerName'],
      chat['publicKey'],
      targetAvatar: chat['avatar'],
      targetDisplayName: chat['displayName'],
      isVerified: chatVerified,
    );
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
          child: Row(
            children: [
              Expanded(
                child: AnimatedSearchInput(
                  controller: _searchController,
                  onSubmitted: (_) =>
                      _isSearching ? null : _startChat(_searchController.text.trim(), null),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: IconButton(
                  icon: const Icon(Icons.group_add, color: Colors.white, size: 22),
                  tooltip: t('Створити групу', 'Create group'),
                  onPressed: _showCreateGroupDialog,
                ),
              ),
            ],
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
                      hoverColor: Colors.white.withValues(alpha: 0.04),
                      selected: isDesktopPlatform && index == _desktopSelectedChatIndex,
                      selectedColor: Colors.white,
                      selectedTileColor: Colors.white.withValues(alpha: 0.08),
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
                    if (!isDesktopPlatform) return tile;
                    return Tooltip(
                      message: t('Відкрити чат', 'Open chat'),
                      waitDuration: const Duration(milliseconds: 260),
                      child: tile,
                    );
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
            : GlassContainer(
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
          child: GestureDetector(
            onTap: _showEditProfileSheet,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1),
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

        // ── СПОВІЩЕННЯ ────────────────────────────────────────
        _sectionHeader(t("СПОВІЩЕННЯ", "NOTIFICATIONS")),
        GlassContainer(
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
              onChanged: (v) { setState(() => _soundEnabled = v); _saveSetting('sound_enabled', v); _syncSettingsToBackend(); },
              accent: accent,
            ),
            _divider(),
            _settingToggle(
              icon: Icons.vibration_rounded, iconColor: accent,
              title: t("Вібрація", "Vibration"),
              value: _vibrationEnabled, enabled: _notificationsEnabled,
              onChanged: (v) { setState(() => _vibrationEnabled = v); _saveSetting('vibration_enabled', v); _syncSettingsToBackend(); },
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

        // ── КОНФІДЕНЦІЙНІСТЬ ──────────────────────────────────
        _sectionHeader(t("КОНФІДЕНЦІЙНІСТЬ", "PRIVACY")),
        GlassContainer(
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

        // ── БЕЗПЕКА ───────────────────────────────────────────
        _sectionHeader(t("БЕЗПЕКА", "SECURITY")),
        GlassContainer(
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
                        onTap: () { setState(() => _accentColor = e.key); _saveSetting('accent_color', e.key); _syncSettingsToBackend(); },
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
            // Розмір шрифту
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
            // Стиль бульок
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
              onChanged: (v) { setState(() => _compactMode = v); _saveSetting('compact_mode', v); _syncSettingsToBackend(); },
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

        // ── АДМІН ─────────────────────────────────────────────
        if (_isAdmin) ...[
          _sectionHeader(t("АДМІН-ПАНЕЛЬ", "ADMIN PANEL"), icon: VerifiedBadge(size: 13, color: accent)),
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
              decoration: BoxDecoration(
                color: const Color(0xFF16171B),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
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
                                  final preview = textOrFallback(i, t("Тестове повідомлення", "Sample message"));
                                  final time = ['1:02 PM', '2:01 PM', '1:53 PM', '1:50 PM', '1:16 PM', '12:54 PM'][i];
                                  return ListTile(
                                    dense: true,
                                    leading: CircleAvatar(
                                      radius: 22,
                                      backgroundColor: [
                                        const Color(0xFFF6B85C),
                                        const Color(0xFF6B8CFF),
                                        const Color(0xFF6EDB7A),
                                        const Color(0xFF37D2E5),
                                        const Color(0xFF4CB4FF),
                                        const Color(0xFF63C2FF)
                                      ][i],
                                      child: Text(
                                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                                        style: TextStyle(color: Colors.white, fontSize: appliedFont + 2, fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                    title: Text(
                                      name,
                                      style: TextStyle(color: Colors.white, fontSize: appliedFont + 2, fontWeight: FontWeight.w600),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(
                                      preview,
                                      style: TextStyle(color: Colors.white.withValues(alpha: 0.52), fontSize: appliedFont),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: Text(time, style: TextStyle(color: Colors.white38, fontSize: appliedFont - 1)),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      ValueListenableBuilder<int>(
                        valueListenable: pageIdx,
                        builder: (_, idx, _) {
                          return Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _dot(idx == 0),
                              const SizedBox(width: 6),
                              _dot(idx == 1),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Text(t("Системний розмір тексту", "System text size"), style: const TextStyle(color: Colors.white, fontSize: 14)),
                          const Spacer(),
                          Switch(
                            value: useSystemSize,
                            activeTrackColor: accent.withValues(alpha: 0.45),
                            inactiveTrackColor: Colors.white24,
                            thumbColor: WidgetStateProperty.all(Colors.white),
                            onChanged: (v) => setStateSB(() => useSystemSize = v),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Text('A', style: TextStyle(color: Colors.white70, fontSize: 14)),
                          Expanded(
                            child: SliderTheme(
                              data: SliderThemeData(
                                activeTrackColor: const Color(0xFFD5AF73),
                                inactiveTrackColor: Colors.white12,
                                thumbColor: Colors.white,
                                overlayColor: accent.withValues(alpha: 0.2),
                                trackHeight: 3,
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                              ),
                              child: Slider(
                                value: tempSize,
                                min: 12,
                                max: 18,
                                divisions: 6,
                                onChanged: (v) => setStateSB(() => tempSize = v),
                              ),
                            ),
                          ),
                          Text('A', style: TextStyle(color: Colors.white70, fontSize: 28)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () {
                                pageController.dispose();
                                pageIdx.dispose();
                                Navigator.pop(ctx);
                              },
                              child: Container(
                                height: 48,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
                                ),
                                child: Text(t("Скасувати", "Cancel"), style: const TextStyle(color: Colors.white, fontSize: 16)),
                              ),
                            ),
                          ),
                          Container(width: 1, height: 48, color: Colors.white.withValues(alpha: 0.08)),
                          Expanded(
                            child: InkWell(
                              onTap: () {
                                setState(() => _chatFontSize = tempSize);
                                _saveSetting('chat_font_size', tempSize);
                                _syncSettingsToBackend();
                                pageController.dispose();
                                pageIdx.dispose();
                                Navigator.pop(ctx);
                              },
                              child: Container(
                                height: 48,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
                                ),
                                child: Text(t("Встановити", "Apply"), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                              ),
                            ),
                          ),
                        ],
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

  Widget _dot(bool active) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: active ? 16 : 6,
      height: 6,
      decoration: BoxDecoration(
        color: active ? Colors.white : Colors.white38,
        borderRadius: BorderRadius.circular(20),
      ),
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
      leading: _settingIcon(icon, enabled ? iconColor : iconColor.withValues(alpha: 0.35)),
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
          activeTrackColor: accent.withValues(alpha: 0.42),
          inactiveTrackColor: Colors.white12,
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
      onTap: () { setState(() => _chatBubbleStyle = style); _saveSetting('bubble_style', style); _syncSettingsToBackend(); },
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
            child: Text(t("Привіт", "Hi"),
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
  // МЕНЮ 1-В-1 ЯК НА ДРУГОМУ СКРІНШОТІ
  // ─────────────────────────────────────────────────────────
  Widget _buildDarkGlassMenu(int totalUnread, int totalPending) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.only(
          left: 10, right: 10,
          bottom: MediaQuery.of(context).padding.bottom + 12,
        ),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 520),
          child: Stack(
            children: [
              // Uiverse-like glass shell
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.88),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 30,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _menuItem(0, "Home", totalUnread),
                        _menuItem(1, "Friends", totalPending),
                        _menuItem(2, "Settings", 0),
                      ],
                    ),
                  ),
                ),
              ),

              // ::after-like inset highlights from the original CSS
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.white.withValues(alpha: 0.07),
                          blurRadius: 5,
                          offset: const Offset(2, 2),
                          spreadRadius: -2,
                        ),
                        BoxShadow(
                          color: Colors.white.withValues(alpha: 0.03),
                          blurRadius: 5,
                          offset: const Offset(-2, -2),
                          spreadRadius: 2,
                        ),
                        BoxShadow(
                          color: Colors.white.withValues(alpha: 0.02),
                          blurRadius: 0,
                          offset: const Offset(0, -2),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menuItem(int index, String label, int badgeCount) {
    final isActive = _currentIndex == index;
    final accent = _accentColors[_accentColor]!;

    final textColor = isActive ? accent : Colors.white.withValues(alpha: 0.65);

    final bgColor = isActive ? Colors.white.withValues(alpha: 0.12) : Colors.transparent;

    return Expanded(
      child: GestureDetector(
        onTap: () => _onTabSelected(index),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(999),
            border: isActive ? Border.all(color: Colors.white.withValues(alpha: 0.05)) : Border.all(color: Colors.transparent),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.20),
                      blurRadius: 5,
                      offset: const Offset(2, 2),
                      spreadRadius: -2,
                    ),
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.08),
                      blurRadius: 5,
                      offset: const Offset(-2, -2),
                      spreadRadius: 2,
                    ),
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.05),
                      blurRadius: 0,
                      offset: const Offset(0, -2),
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Badge(
                isLabelVisible: badgeCount > 0,
                backgroundColor: Colors.white,
                textColor: Colors.black,
                label: Text('$badgeCount', style: const TextStyle(fontWeight: FontWeight.bold)),
                // Використовуємо наші кастомні іконки з правильними шляхами
                child: CustomUiverseIcon(index: index, color: textColor),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: textColor,
                  fontSize: 12.0,
                  fontWeight: FontWeight.w600,
                  height: 1,
                ),
              ),
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
    final isDesktopLayout = MediaQuery.of(context).size.width >= 980;
    final isDesktopPlatform = !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      resizeToAvoidBottomInset: false, // фікс кліку в PWA
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        centerTitle: true,
        title: SizedBox(
          width: 40,
          height: 40,
          child: Image.asset('web/icons/favicon.png', width: 40, height: 40),
        ),
      ),
      body: Shortcuts(
        shortcuts: isDesktopPlatform
            ? const <ShortcutActivator, Intent>{
                SingleActivator(LogicalKeyboardKey.digit1, control: true): _SwitchTabIntent(0),
                SingleActivator(LogicalKeyboardKey.digit2, control: true): _SwitchTabIntent(1),
                SingleActivator(LogicalKeyboardKey.digit3, control: true): _SwitchTabIntent(2),
                SingleActivator(LogicalKeyboardKey.digit4, control: true): _SwitchTabIntent(2),
              }
            : const <ShortcutActivator, Intent>{},
        child: Actions(
          actions: <Type, Action<Intent>>{
            _SwitchTabIntent: CallbackAction<_SwitchTabIntent>(
              onInvoke: (intent) {
                final target = intent.index.clamp(0, 2);
                unawaited(_onTabSelected(target));
                return null;
              },
            ),
          },
          child: Focus(
            autofocus: true,
            child: LiquidBackground(
              child: isDesktopLayout
                  ? Row(
                      children: [
                        NavigationRail(
                          backgroundColor: Colors.black.withValues(alpha: 0.32),
                          selectedIndex: _currentIndex,
                          onDestinationSelected: (index) => _onTabSelected(index),
                          labelType: NavigationRailLabelType.all,
                          selectedIconTheme: const IconThemeData(color: Colors.white),
                          unselectedIconTheme: IconThemeData(color: Colors.white.withValues(alpha: 0.45)),
                          selectedLabelTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                          unselectedLabelTextStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                          destinations: [
                            NavigationRailDestination(
                              icon: const Icon(Icons.chat_bubble_outline_rounded),
                              selectedIcon: const Icon(Icons.chat_bubble_rounded),
                              label: Text(t('Чати', 'Chats')),
                            ),
                            NavigationRailDestination(
                              icon: const Icon(Icons.people_outline_rounded),
                              selectedIcon: const Icon(Icons.people_rounded),
                              label: Text(t('Друзі', 'Friends')),
                            ),
                            NavigationRailDestination(
                              icon: const Icon(Icons.person_outline_rounded),
                              selectedIcon: const Icon(Icons.person_rounded),
                              label: Text(t('Профіль', 'Profile')),
                            ),
                          ],
                          trailing: Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (totalUnread > 0) _desktopBadge('$totalUnread'),
                                if (totalPending > 0) ...[
                                  const SizedBox(height: 8),
                                  _desktopBadge('$totalPending', color: const Color(0xFF2FA8FF)),
                                ],
                              ],
                            ),
                          ),
                        ),
                        VerticalDivider(width: 1, color: Colors.white.withValues(alpha: 0.08)),
                        Expanded(
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 1120),
                              child: _buildAnimatedTabPage(_currentIndex),
                            ),
                          ),
                        ),
                      ],
                    )
                  : Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: PageView.builder(
                            controller: _pageController,
                            physics: const BouncingScrollPhysics(),
                            itemCount: 3,
                            onPageChanged: (index) {
                              if (_currentIndex != index && mounted) {
                                setState(() => _currentIndex = index);
                              }
                            },
                            itemBuilder: (context, index) => _buildAnimatedTabPage(index),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: _buildDarkGlassMenu(totalUnread, totalPending),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _desktopBadge(String value, {Color color = Colors.white}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(value, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}
// ─────────────────────────────────────────────────────────
// КАСТОМНІ SVG ІКОНКИ (UIVERSE)
// ─────────────────────────────────────────────────────────
// ─────────────────────────────────────────────────────────
// КАСТОМНІ SVG ІКОНКИ (ТОЧНО З UIVERSE)
// ─────────────────────────────────────────────────────────
class CustomUiverseIcon extends StatelessWidget {
  final int index;
  final Color color;
  const CustomUiverseIcon({super.key, required this.index, required this.color});

  double get _offsetY {
    switch (index) {
      case 0:
        return -0.4;
      case 1:
        return 0.2;
      case 2:
        return -0.6;
      default:
        return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: Offset(0, _offsetY),
      child: SizedBox(
        width: 24, // Розмір як у CSS (1.4rem)
        height: 24,
        child: CustomPaint(
          painter: _UiverseIconPainter(index: index, color: color),
        ),
      ),
    );
  }
}

class _UiverseIconPainter extends CustomPainter {
  final int index;
  final Color color;
  _UiverseIconPainter({required this.index, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final solidPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final fadedPaint = Paint()
      ..color = color.withValues(alpha: 0.4)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final scale = size.width / 24.0;
    canvas.scale(scale, scale);

    if (index == 0) {
      canvas.drawPath(
        parseSvgPathData('M11.47 3.841a.75.75 0 0 1 1.06 0l8.69 8.69a.75.75 0 1 0 1.06-1.061l-8.689-8.69a2.25 2.25 0 0 0-3.182 0l-8.69 8.69a.75.75 0 1 0 1.061 1.06l8.69-8.689Z'),
        solidPaint,
      );
      canvas.drawPath(
        parseSvgPathData('m12 5.432 8.159 8.159c.03.03.06.058.091.086v6.198c0 1.035-.84 1.875-1.875 1.875H15a.75.75 0 0 1-.75-.75v-4.5a.75.75 0 0 0-.75-.75h-3a.75.75 0 0 0-.75.75V21a.75.75 0 0 1-.75.75H5.625a1.875 1.875 0 0 1-1.875-1.875v-6.198a2.29 2.29 0 0 0 .091-.086L12 5.432Z'),
        solidPaint,
      );
      return;
    }

    if (index == 1) {
      canvas.drawPath(
        parseSvgPathData('M16.5 7.5a4.5 4.5 0 1 1-9 0 4.5 4.5 0 0 1 9 0ZM3.75 20.1a8.25 8.25 0 0 1 16.5 0 .75.75 0 0 1-.437.695A18.683 18.683 0 0 1 12 22.5c-2.786 0-5.433-.608-7.813-1.705A.75.75 0 0 1 3.75 20.1Z'),
        solidPaint,
      );
      canvas.drawPath(
        parseSvgPathData('M16 4a4 4 0 1 1 0 8 4 4 0 0 1 0-8Z'),
        fadedPaint,
      );
      canvas.drawPath(
        parseSvgPathData('M16 13.5a9 9 0 0 1 6.25 2.45.75.75 0 0 1 .25.55v.6a.75.75 0 0 1-.437.695A18 18 0 0 1 18 18.3v-.2a9.26 9.26 0 0 0-3.2-7 9.1 9.1 0 0 1 1.2-.1Z'),
        fadedPaint,
      );
      return;
    }

    canvas.drawPath(
      parseSvgPathData('M17.004 10.407c.138.435-.216.842-.672.842h-3.465a.75.75 0 0 1-.65-.375l-1.732-3c-.229-.396-.053-.907.393-1.004a5.252 5.252 0 0 1 6.126 3.537ZM8.12 8.464c.307-.338.838-.235 1.066.16l1.732 3a.75.75 0 0 1 0 .75l-1.732 3c-.229.397-.76.5-1.067.161A5.23 5.23 0 0 1 6.75 12a5.23 5.23 0 0 1 1.37-3.536ZM10.878 17.13c-.447-.098-.623-.608-.394-1.004l1.733-3.002a.75.75 0 0 1 .65-.375h3.465c.457 0 .81.407.672.842a5.252 5.252 0 0 1-6.126 3.539Z'),
      solidPaint,
    );
    final settingsPath = parseSvgPathData('M21 12.75a.75.75 0 1 0 0-1.5h-.783a8.22 8.22 0 0 0-.237-1.357l.734-.267a.75.75 0 1 0-.513-1.41l-.735.268a8.24 8.24 0 0 0-.689-1.192l.6-.503a.75.75 0 1 0-.964-1.149l-.6.504a8.3 8.3 0 0 0-1.054-.885l.391-.678a.75.75 0 1 0-1.299-.75l-.39.676a8.188 8.188 0 0 0-1.295-.47l.136-.77a.75.75 0 0 0-1.477-.26l-.136.77a8.36 8.36 0 0 0-1.377 0l-.136-.77a.75.75 0 1 0-1.477.26l.136.77c-.448.121-.88.28-1.294.47l-.39-.676a.75.75 0 0 0-1.3.75l.392.678a8.29 8.29 0 0 0-1.054.885l-.6-.504a.75.75 0 1 0-.965 1.149l.6.503a8.243 8.243 0 0 0-.689 1.192L3.8 8.216a.75.75 0 1 0-.513 1.41l.735.267a8.222 8.222 0 0 0-.238 1.356h-.783a.75.75 0 0 0 0 1.5h.783c.042.464.122.917.238 1.356l-.735.268a.75.75 0 0 0 .513 1.41l.735-.268c.197.417.428.816.69 1.191l-.6.504a.75.75 0 0 0 .963 1.15l.601-.505c.326.323.679.62 1.054.885l-.392.68a.75.75 0 0 0 1.3.75l.39-.679c.414.192.847.35 1.294.471l-.136.77a.75.75 0 0 0 1.477.261l.137-.772a8.332 8.332 0 0 0 1.376 0l.136.772a.75.75 0 1 0 1.477-.26l-.136-.771a8.19 8.19 0 0 0 1.294-.47l.391.677a.75.75 0 0 0 1.3-.75l-.393-.679a8.29 8.29 0 0 0 1.054-.885l.601.504a.75.75 0 0 0 .964-1.15l-.6-.503c.261-.375.492-.774.69-1.191l.735.267a.75.75 0 1 0 .512-1.41l-.734-.267c.115-.439.195-.892.237-1.356h.784Zm-2.657-3.06a6.744 6.744 0 0 0-1.19-2.053 6.784 6.784 0 0 0-1.82-1.51A6.705 6.705 0 0 0 12 5.25a6.8 6.8 0 0 0-1.225.11 6.7 6.7 0 0 0-2.15.793 6.784 6.784 0 0 0-2.952 3.489.76.76 0 0 1-.036.098A6.74 6.74 0 0 0 5.251 12a6.74 6.74 0 0 0 3.366 5.842l.009.005a6.704 6.704 0 0 0 2.18.798l.022.003a6.792 6.792 0 0 0 2.368-.004 6.704 6.704 0 0 0 2.205-.811 6.785 6.785 0 0 0 1.762-1.484l.009-.01.009-.01a6.743 6.743 0 0 0 1.18-2.066c.253-.707.39-1.469.39-2.263a6.74 6.74 0 0 0-.408-2.309Z');
    settingsPath.fillType = PathFillType.evenOdd;
    canvas.drawPath(settingsPath, solidPaint);
  }

  @override
  bool shouldRepaint(covariant _UiverseIconPainter oldDelegate) {
    return oldDelegate.index != index || oldDelegate.color != color;
  }
}