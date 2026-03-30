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
  String _chatFolder = 'all';
  List<Map<String, dynamic>> _customChatFolders = [];
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
  final _friendsSearchController = TextEditingController();
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
  bool _autoDownloadMedia = true;
  bool _saveMediaToDevice = false;
  bool _lowDataMode = false;
  bool _animatedEmojiEnabled = true;
  bool _quickReactionsEnabled = true;
  bool _emojiLargeRenderEnabled = true;
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
    _searchController.addListener(_onSearchChanged);
    _friendsSearchController.addListener(_onSearchChanged);
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();

    _bgSocket = io.io('https://aether-backend-hrmq.onrender.com', {
      'transports': ['websocket', 'polling'],
      'upgrade': true,
      'timeout': 20000,
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
    _searchController.removeListener(_onSearchChanged);
    _friendsSearchController.removeListener(_onSearchChanged);
    _addFriendController.dispose();
    _searchController.dispose();
    _friendsSearchController.dispose();
    _verifySearchController.dispose();
    _pageController.dispose();
    _desktopChatsScrollController.dispose();
    _tokenRefreshSub?.cancel();
    _bgSocket.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (!mounted) return;
    setState(() {});
  }

  String _normalizeSearch(String value) => value.trim().toLowerCase();

  Future<void> _saveCustomChatFolders() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('custom_chat_folders', jsonEncode(_customChatFolders));
  }

  Map<String, dynamic>? _customFolderByKey(String key) {
    if (!key.startsWith('custom:')) return null;
    final id = key.substring('custom:'.length);
    for (final folder in _customChatFolders) {
      if ((folder['id'] ?? '').toString() == id) return folder;
    }
    return null;
  }

  bool _matchesChatFolder(Map<String, dynamic> chat) {
    final custom = _customFolderByKey(_chatFolder);
    if (custom != null) {
      final onlyUnread = custom['onlyUnread'] == true;
      final includeDirect = custom['includeDirect'] != false;
      final includeGroups = custom['includeGroups'] != false;
      final pinnedOnly = custom['pinnedOnly'] == true;
      final isGroup = chat['isGroup'] == true;
      final unreadCount = (chat['unreadCount'] ?? 0) as int;

      if (onlyUnread && unreadCount <= 0) return false;
      if (pinnedOnly && chat['isPinned'] != true) return false;
      if (isGroup && !includeGroups) return false;
      if (!isGroup && !includeDirect) return false;
      return true;
    }

    switch (_chatFolder) {
      case 'unread':
        return (chat['unreadCount'] ?? 0) > 0;
      case 'direct':
        return chat['isGroup'] != true;
      case 'groups':
        return chat['isGroup'] == true;
      default:
        return true;
    }
  }

  int _chatFolderCount(String folder) {
    return _recentChats.where((chat) {
      final custom = _customFolderByKey(folder);
      if (custom != null) {
        final onlyUnread = custom['onlyUnread'] == true;
        final includeDirect = custom['includeDirect'] != false;
        final includeGroups = custom['includeGroups'] != false;
        final pinnedOnly = custom['pinnedOnly'] == true;
        final isGroup = chat['isGroup'] == true;
        final unreadCount = (chat['unreadCount'] ?? 0) as int;

        if (onlyUnread && unreadCount <= 0) return false;
        if (pinnedOnly && chat['isPinned'] != true) return false;
        if (isGroup && !includeGroups) return false;
        if (!isGroup && !includeDirect) return false;
        return true;
      }

      switch (folder) {
        case 'unread':
          return (chat['unreadCount'] ?? 0) > 0;
        case 'direct':
          return chat['isGroup'] != true;
        case 'groups':
          return chat['isGroup'] == true;
        default:
          return true;
      }
    }).length;
  }

  Widget _buildHighlightedText(
    String text,
    String query,
    TextStyle baseStyle, {
    TextOverflow overflow = TextOverflow.ellipsis,
    int maxLines = 1,
  }) {
    final normalizedQuery = _normalizeSearch(query);
    if (normalizedQuery.isEmpty) {
      return Text(text, style: baseStyle, overflow: overflow, maxLines: maxLines);
    }

    final lowerText = text.toLowerCase();
    final start = lowerText.indexOf(normalizedQuery);
    if (start == -1) {
      return Text(text, style: baseStyle, overflow: overflow, maxLines: maxLines);
    }

    final end = start + normalizedQuery.length;
    final highlightStyle = baseStyle.copyWith(
      color: Colors.white,
      backgroundColor: Colors.white.withValues(alpha: 0.16),
      fontWeight: FontWeight.w700,
    );

    return RichText(
      overflow: overflow,
      maxLines: maxLines,
      text: TextSpan(
        style: baseStyle,
        children: [
          if (start > 0) TextSpan(text: text.substring(0, start)),
          TextSpan(text: text.substring(start, end), style: highlightStyle),
          if (end < text.length) TextSpan(text: text.substring(end)),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _filteredRecentChats() {
    final query = _normalizeSearch(_searchController.text);
    final folderFiltered = _recentChats.where(_matchesChatFolder).toList();
    if (query.isEmpty) return folderFiltered;
    return folderFiltered.where((chat) {
      final userName = (chat['partnerName'] ?? '').toString().toLowerCase();
      final displayName = (chat['displayName'] ?? '').toString().toLowerCase();
      return userName.contains(query) || displayName.contains(query);
    }).toList();
  }

  List<Map<String, dynamic>> _filteredFriends() {
    final query = _normalizeSearch(_friendsSearchController.text);
    if (query.isEmpty) return _friends;
    return _friends.where((friend) {
      final userName = (friend['userName'] ?? '').toString().toLowerCase();
      final displayName = (friend['displayName'] ?? '').toString().toLowerCase();
      return userName.contains(query) || displayName.contains(query);
    }).toList();
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
      'autoDownloadMedia': _autoDownloadMedia,
      'saveMediaToDevice': _saveMediaToDevice,
      'lowDataMode': _lowDataMode,
      'animatedEmojiEnabled': _animatedEmojiEnabled,
      'quickReactionsEnabled': _quickReactionsEnabled,
      'emojiLargeRenderEnabled': _emojiLargeRenderEnabled,
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
    List<Map<String, dynamic>> loadedFolders = [];
    final rawFolders = p.getString('custom_chat_folders');
    if (rawFolders != null && rawFolders.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawFolders) as List<dynamic>;
        loadedFolders = decoded
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .where((f) => (f['id'] ?? '').toString().isNotEmpty && (f['name'] ?? '').toString().trim().isNotEmpty)
            .toList();
      } catch (_) {}
    }
    String selectedFolder = p.getString('chat_folder_selected') ?? 'all';
    final isCustomSelected = selectedFolder.startsWith('custom:');
    if (isCustomSelected) {
      final id = selectedFolder.substring('custom:'.length);
      final exists = loadedFolders.any((f) => (f['id'] ?? '').toString() == id);
      if (!exists) selectedFolder = 'all';
    }

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
      _autoDownloadMedia    = p.getBool('auto_download_media') ?? true;
      _saveMediaToDevice    = p.getBool('save_media_to_device') ?? false;
      _lowDataMode          = p.getBool('low_data_mode') ?? false;
      _animatedEmojiEnabled = p.getBool('animated_emoji_enabled') ?? true;
      _quickReactionsEnabled = p.getBool('quick_reactions_enabled') ?? true;
      _emojiLargeRenderEnabled = p.getBool('emoji_large_render_enabled') ?? true;
      _myDisplayName        = p.getString('my_display_name') ?? _myDisplayName;
      _myBio                = p.getString('my_bio') ?? _myBio;
      _customChatFolders    = loadedFolders;
      _chatFolder           = selectedFolder;
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
    if (_authInProgress) return;

    if (!_systemLockEnabled) {
      if (mounted) {
        setState(() => _isAppLocked = false);
      }
      return;
    }

    final ok = await _authenticateSystem();
    if (!mounted) return;
    if (ok) {
      setState(() {
        _isAppLocked = false;
        _lockOnResume = false;
      });
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
    if (!_systemLockEnabled || !mounted) return;

    // local_auth can temporarily background/resume the app while the OS prompt
    // is open; relocking in that window causes an unlock loop on desktop.
    if (_authInProgress) return;

    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      setState(() {
        _lockOnResume = true;
      });
    } else if (state == AppLifecycleState.resumed) {
      if (_lockOnResume) {
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
    final groupDescriptionController = TextEditingController();
    final selectedFriends = <String>{};
    bool isCreating = false;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setStateSB) {
          return Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.92),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.only(
                  left: 18,
                  right: 18,
                  top: 12,
                  bottom: 16 + MediaQuery.of(dialogContext).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.28),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: accent.withValues(alpha: 0.22),
                            border: Border.all(color: accent.withValues(alpha: 0.5)),
                          ),
                          child: Icon(Icons.groups_rounded, color: accent),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            t('Нова група', 'New Group'),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 19),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    GlassInput(controller: groupNameController, hintText: t('Назва групи', 'Group Name')),
                    const SizedBox(height: 10),
                    GlassInput(controller: groupDescriptionController, hintText: t('Опис (необов\'язково)', 'Description (optional)')),
                    const SizedBox(height: 14),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        t('Учасники', 'Members'),
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.78), fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 230),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: _friends.length,
                        separatorBuilder: (_, _) => Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
                        itemBuilder: (context, index) {
                          final friend = (_friends[index]['userName'] ?? '').toString();
                          final display = (_friends[index]['displayName'] ?? '').toString().trim();
                          if (friend.isEmpty) return const SizedBox.shrink();
                          final selected = selectedFriends.contains(friend);
                          return CheckboxListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                            dense: true,
                            value: selected,
                            onChanged: (value) {
                              setStateSB(() {
                                if (value == true) {
                                  selectedFriends.add(friend);
                                } else {
                                  selectedFriends.remove(friend);
                                }
                              });
                            },
                            fillColor: WidgetStateProperty.resolveWith((states) =>
                                states.contains(WidgetState.selected) ? accent : Colors.transparent),
                            checkColor: onAccent(accent),
                            side: BorderSide(color: accent.withValues(alpha: 0.55)),
                            checkboxShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                            title: Text(
                              display.isNotEmpty ? '$display @$friend' : friend,
                              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${selectedFriends.length} ${t('обрано', 'selected')}',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.64), fontSize: 12),
                          ),
                        ),
                        TextButton(
                          onPressed: isCreating ? null : () => Navigator.pop(dialogContext),
                          child: Text(t('Скасувати', 'Cancel'), style: const TextStyle(color: Colors.white70)),
                        ),
                        const SizedBox(width: 6),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: onAccent(accent),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: isCreating
                              ? null
                              : () {
                                  final groupName = groupNameController.text.trim();
                                  final groupDescription = groupDescriptionController.text.trim();
                                  final participants = selectedFriends
                                      .map((e) => e.trim())
                                      .where((e) => e.isNotEmpty && e != widget.userName)
                                      .toSet()
                                      .toList();

                                  if (groupName.isEmpty) {
                                    _showSnack(t('Вкажіть назву групи', 'Enter group name'));
                                    return;
                                  }
                                  if (participants.isEmpty) {
                                    _showSnack(t('Оберіть хоча б одного друга', 'Select at least one friend'));
                                    return;
                                  }

                                  setStateSB(() => isCreating = true);
                                  _bgSocket.emitWithAck('create_group', {
                                    'name': groupName,
                                    'description': groupDescription,
                                    'participants': participants,
                                    'creator': widget.userName,
                                  }, ack: (dynamic raw) {
                                    if (!mounted) return;
                                    final data = raw is Map<String, dynamic>
                                        ? raw
                                        : (raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{});
                                    final success = data['success'] == true;

                                    if (!success) {
                                      setStateSB(() => isCreating = false);
                                      _showSnack(
                                        (data['message'] ?? t('Не вдалося створити групу', 'Failed to create group')).toString(),
                                      );
                                      return;
                                    }

                                    final groupId = (data['groupId'] ?? '').toString();
                                    _searchController.clear();
                                    _loadData();
                                    if (Navigator.of(dialogContext).canPop()) {
                                      Navigator.of(dialogContext).pop();
                                    }
                                    _showSnack(t('Групу створено', 'Group created'));
                                    if (groupId.startsWith('GROUP_')) {
                                      _startChat(groupName, groupId);
                                    }
                                  });
                                },
                          child: Text(isCreating ? t('Створення...', 'Creating...') : t('Створити', 'Create')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Color onAccent(Color color) {
    return ThemeData.estimateBrightnessForColor(color) == Brightness.dark ? Colors.white : Colors.black;
  }

  Future<Map<String, dynamic>?> _fetchGroupInfo(String groupId) async {
    final completer = Completer<Map<String, dynamic>?>();
    _bgSocket.emitWithAck(
      'get_group_info',
      {'groupId': groupId, 'userName': widget.userName},
      ack: (dynamic raw) {
        try {
          if (raw is Map<String, dynamic>) {
            completer.complete(raw);
            return;
          }
          if (raw is Map) {
            completer.complete(Map<String, dynamic>.from(raw));
            return;
          }
          completer.complete(null);
        } catch (_) {
          completer.complete(null);
        }
      },
    );
    return completer.future.timeout(const Duration(seconds: 8), onTimeout: () => null);
  }

  Future<void> _showEditGroupSheet(Map<String, dynamic> chat) async {
    final groupId = (chat['publicKey'] ?? '').toString();
    if (!groupId.startsWith('GROUP_')) return;

    final info = await _fetchGroupInfo(groupId);
    if (!mounted) return;
    if (info == null || info['success'] != true) {
      _showSnack((info?['message'] ?? t('Не вдалося завантажити групу', 'Failed to load group')).toString());
      return;
    }

    final accent = _accentColors[_accentColor] ?? const Color(0xFFB026FF);
    final groupNameController = TextEditingController(text: (info['name'] ?? chat['partnerName'] ?? '').toString());
    final groupDescriptionController = TextEditingController(text: (info['description'] ?? '').toString());
    final members = List<Map<String, dynamic>>.from((info['members'] as List?) ?? const []);
    final selectedMembers = members
        .map((m) => (m['userName'] ?? '').toString())
        .where((u) => u.isNotEmpty)
        .toSet();
    selectedMembers.add(widget.userName);

    final memberDisplayMap = <String, String>{};
    for (final m in members) {
      final userName = (m['userName'] ?? '').toString();
      if (userName.isEmpty) continue;
      final display = (m['displayName'] ?? '').toString().trim();
      memberDisplayMap[userName] = display;
    }
    for (final f in _friends) {
      final userName = (f['userName'] ?? '').toString();
      if (userName.isEmpty) continue;
      final display = (f['displayName'] ?? '').toString().trim();
      if (!memberDisplayMap.containsKey(userName)) {
        memberDisplayMap[userName] = display;
      }
    }

    bool isSaving = false;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setStateSB) {
          final availableUsers = <String>{...selectedMembers, ..._friends.map((e) => (e['userName'] ?? '').toString())}
            ..removeWhere((u) => u.isEmpty);
          final sortedUsers = availableUsers.toList()..sort();
          return Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.92),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.only(
                  left: 18,
                  right: 18,
                  top: 12,
                  bottom: 16 + MediaQuery.of(dialogContext).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.28),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: accent.withValues(alpha: 0.22),
                            border: Border.all(color: accent.withValues(alpha: 0.5)),
                          ),
                          child: Icon(Icons.edit_note_rounded, color: accent),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            t('Редагувати групу', 'Edit Group'),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 19),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    GlassInput(controller: groupNameController, hintText: t('Назва групи', 'Group Name')),
                    const SizedBox(height: 10),
                    GlassInput(controller: groupDescriptionController, hintText: t('Опис', 'Description')),
                    const SizedBox(height: 14),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        t('Учасники', 'Members'),
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.78), fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 230),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: sortedUsers.length,
                        separatorBuilder: (_, _) => Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
                        itemBuilder: (context, index) {
                          final user = sortedUsers[index];
                          final display = (memberDisplayMap[user] ?? '').trim();
                          final isMe = user == widget.userName;
                          final selected = selectedMembers.contains(user);
                          return CheckboxListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                            dense: true,
                            value: selected,
                            onChanged: isMe
                                ? null
                                : (value) {
                                    setStateSB(() {
                                      if (value == true) {
                                        selectedMembers.add(user);
                                      } else {
                                        selectedMembers.remove(user);
                                      }
                                    });
                                  },
                            fillColor: WidgetStateProperty.resolveWith((states) =>
                                states.contains(WidgetState.selected) ? accent : Colors.transparent),
                            checkColor: onAccent(accent),
                            side: BorderSide(color: accent.withValues(alpha: 0.55)),
                            checkboxShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                            title: Text(
                              isMe
                                  ? '${display.isNotEmpty ? display : user} (${t('ви', 'you')})'
                                  : (display.isNotEmpty ? '$display @$user' : user),
                              style: TextStyle(
                                color: isMe ? Colors.white70 : Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton.icon(
                            onPressed: isSaving
                                ? null
                                : () {
                                    final localPartnerName = (chat['partnerName'] ?? '').toString();
                                    _applyLocalChatSettings(
                                      localPartnerName,
                                      isPinned: false,
                                      isHidden: false,
                                      isBlocked: chat['isBlocked'] == true,
                                      isDeleted: true,
                                    );
                                    _bgSocket.emit('update_chat_settings', {
                                      'userName': widget.userName,
                                      'partnerName': groupId,
                                      'isPinned': false,
                                      'isHidden': false,
                                      'isDeleted': true,
                                      'isBlocked': chat['isBlocked'] == true,
                                    });
                                    Navigator.pop(dialogContext);
                                    _loadData();
                                    _showSnack(t('Ви вийшли з групи', 'You left the group'));
                                  },
                            icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFFF5E57), size: 18),
                            label: Text(
                              t('Вийти з групи', 'Leave Group'),
                              style: const TextStyle(color: Color(0xFFFF5E57), fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        TextButton(
                          onPressed: isSaving ? null : () => Navigator.pop(dialogContext),
                          child: Text(t('Скасувати', 'Cancel'), style: const TextStyle(color: Colors.white70)),
                        ),
                        const SizedBox(width: 6),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: onAccent(accent),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: isSaving
                              ? null
                              : () {
                                  final nextName = groupNameController.text.trim();
                                  if (nextName.isEmpty) {
                                    _showSnack(t('Вкажіть назву групи', 'Enter group name'));
                                    return;
                                  }
                                  if (selectedMembers.length < 2) {
                                    _showSnack(t('У групі має бути щонайменше 2 учасники', 'Group must have at least 2 members'));
                                    return;
                                  }
                                  setStateSB(() => isSaving = true);
                                  _bgSocket.emitWithAck('update_group', {
                                    'groupId': groupId,
                                    'editor': widget.userName,
                                    'name': nextName,
                                    'description': groupDescriptionController.text.trim(),
                                    'participants': selectedMembers.toList(),
                                  }, ack: (dynamic raw) {
                                    final data = raw is Map<String, dynamic>
                                        ? raw
                                        : (raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{});
                                    if (!mounted) return;
                                    if (data['success'] != true) {
                                      setStateSB(() => isSaving = false);
                                      _showSnack((data['message'] ?? t('Не вдалося оновити групу', 'Failed to update group')).toString());
                                      return;
                                    }
                                    Navigator.pop(dialogContext);
                                    _loadData();
                                    _showSnack(t('Групу оновлено', 'Group updated'));
                                  });
                                },
                          child: Text(isSaving ? t('Збереження...', 'Saving...') : t('Зберегти', 'Save')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
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
    bool isPresenceLoading = true;
    bool isPartnerOnline = false;
    List<String> sharedMedia = [];
    bool sheetOpen = true;

    void safeSheetSetState(StateSetter setStateSB, VoidCallback fn) {
      if (!mounted || !sheetOpen) return;
      setStateSB(fn);
    }

    Future<List<String>> loadSharedMediaPreviews() async {
      if (publicKey == null || publicKey.isEmpty) return [];
      final rows = await _loadHistoryForGlobalSearch({
        'publicKey': publicKey,
        'partnerName': partnerName,
        'isGroup': false,
      }, limit: 64);
      if (rows.isEmpty) return [];

      final out = <String>[];
      for (final m in rows.reversed) {
        String msgType = (m['type'] ?? 'text').toString().replaceFirst('ephemeral_', '');
        if (msgType != 'image') continue;

        final rawText = (m['text'] ?? '').toString();
        if (rawText.length > 100 && !rawText.startsWith('{')) {
          out.add(rawText);
        } else if (m['ciphertext'] != null && m['nonce'] != null && m['mac'] != null) {
          final dec = await _decrypt(
            (m['ciphertext'] ?? '').toString(),
            (m['nonce'] ?? '').toString(),
            (m['mac'] ?? '').toString(),
            publicKey,
            false,
          );
          if (dec != 'Encrypted' && dec.startsWith('{') && dec.endsWith('}')) {
            try {
              final j = jsonDecode(dec);
              if (j is Map && j['imageBytes'] != null) {
                final b64 = j['imageBytes'].toString();
                if (b64.isNotEmpty) out.add(b64);
              }
            } catch (_) {
              // Ignore malformed payloads in preview loader.
            }
          }
        }

        if (out.length >= 8) break;
      }
      return out;
    }

    String lastSeenText() {
      if (isPresenceLoading) return t('оновлення...', 'updating...');
      if (isPartnerOnline) return t('в мережі', 'online');
      return t('був(ла) нещодавно', 'last seen recently');
    }

    final sheetFuture = showModalBottomSheet(
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
                  safeSheetSetState(setStateSB, () {
                    currentBio = data['bio'];
                    currentAvatar = data['avatar'] ?? currentAvatar;
                    currentDisplayName = data['displayName'] ?? currentDisplayName;
                    isVerifiedUser = data['isVerified'] == true;
                  });
                }
              });
              _bgSocket.emitWithAck('check_presence', partnerName, ack: (dynamic data) {
                safeSheetSetState(setStateSB, () {
                  isPartnerOnline = data is Map && data['isOnline'] == true;
                  isPresenceLoading = false;
                });
              });
              unawaited(() async {
                final previews = await loadSharedMediaPreviews();
                safeSheetSetState(setStateSB, () {
                  sharedMedia = previews;
                });
              }());
            }
            final displayName = (currentDisplayName != null && currentDisplayName!.trim().isNotEmpty)
                ? currentDisplayName!.trim()
                : partnerName;
            final bioText = (currentBio ?? '').trim();
            final keyPreview = (publicKey != null && publicKey.isNotEmpty)
                ? '${publicKey.substring(0, publicKey.length > 20 ? 20 : publicKey.length)}...'
                : t('Не вказано', 'Not available');
            return Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFF17212B),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: SafeArea(
                    top: false,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.92),
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(height: 10),
                            Container(
                              width: 40,
                              height: 4,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.35),
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Container(
                              width: double.infinity,
                              margin: const EdgeInsets.symmetric(horizontal: 12),
                              padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    accent.withValues(alpha: 0.38),
                                    const Color(0xFF253341),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                              ),
                              child: Column(
                                children: [
                                  SafeAvatar(avatarBase64: currentAvatar, fallbackName: partnerName, radius: 46),
                                  const SizedBox(height: 12),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          displayName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 23,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      if (isVerifiedUser) ...[
                                        const SizedBox(width: 8),
                                        VerifiedBadge(size: 20, color: accent),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '@$partnerName',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.72),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 220),
                                    child: Row(
                                      key: ValueKey('$isPresenceLoading$isPartnerOnline'),
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        AnimatedContainer(
                                          duration: const Duration(milliseconds: 240),
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            color: isPresenceLoading
                                                ? Colors.white38
                                                : (isPartnerOnline ? const Color(0xFF4CC85A) : Colors.white38),
                                            shape: BoxShape.circle,
                                            boxShadow: isPartnerOnline
                                                ? [
                                                    BoxShadow(
                                                      color: const Color(0xFF4CC85A).withValues(alpha: 0.45),
                                                      blurRadius: 8,
                                                      spreadRadius: 1,
                                                    ),
                                                  ]
                                                : const [],
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          lastSeenText(),
                                          style: TextStyle(
                                            color: Colors.white.withValues(alpha: 0.82),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (bioText.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    Text(
                                      bioText,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.86),
                                        fontSize: 14,
                                        height: 1.35,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              margin: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1F2B38),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                              ),
                              child: Column(
                                children: [
                                  ListTile(
                                    leading: Icon(Icons.alternate_email_rounded, color: accent),
                                    title: Text('@$partnerName', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                                    subtitle: Text(t('Імʼя користувача', 'Username'), style: TextStyle(color: Colors.white.withValues(alpha: 0.55))),
                                  ),
                                  Divider(height: 1, indent: 56, color: Colors.white.withValues(alpha: 0.08)),
                                  ListTile(
                                    leading: Icon(Icons.key_rounded, color: accent),
                                    title: Text(keyPreview, style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 13)),
                                    subtitle: Text(t('Публічний ключ', 'Public key'), style: TextStyle(color: Colors.white.withValues(alpha: 0.55))),
                                  ),
                                ],
                              ),
                            ),
                            if (sharedMedia.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Container(
                                margin: const EdgeInsets.symmetric(horizontal: 12),
                                padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1F2B38),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      t('Спільні медіа', 'Shared media'),
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.95),
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    SizedBox(
                                      height: 84,
                                      child: ListView.separated(
                                        scrollDirection: Axis.horizontal,
                                        itemCount: sharedMedia.length,
                                        separatorBuilder: (context, index) => const SizedBox(width: 8),
                                        itemBuilder: (context, i) {
                                          return ClipRRect(
                                            borderRadius: BorderRadius.circular(12),
                                            child: Image.memory(
                                              base64Decode(sharedMedia[i]),
                                              width: 84,
                                              height: 84,
                                              fit: BoxFit.cover,
                                              errorBuilder: (context, error, stackTrace) => Container(
                                                width: 84,
                                                height: 84,
                                                color: Colors.white10,
                                                child: const Icon(Icons.broken_image_outlined, color: Colors.white54),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            Container(
                              margin: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1F2B38),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                              ),
                              child: Column(children: [
                                ListTile(
                                  leading: const Icon(Icons.chat_bubble_outline, color: Colors.white),
                                  title: Text(t("Написати", "Message"), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                                  onTap: () {
                                    Navigator.pop(context);
                                    _startChat(
                                      partnerName,
                                      publicKey,
                                      targetAvatar: currentAvatar,
                                      targetDisplayName: currentDisplayName,
                                      isVerified: isVerifiedUser,
                                    );
                                  },
                                ),
                                Divider(height: 1, indent: 56, color: Colors.white.withValues(alpha: 0.08)),
                                ListTile(
                                  leading: Icon(isPinned ? Icons.push_pin : Icons.push_pin_outlined, color: Colors.white),
                                  title: Text(isPinned ? t("Відкріпити чат", "Unpin Chat") : t("Закріпити чат", "Pin Chat"), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
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
                                Divider(height: 1, indent: 56, color: Colors.white.withValues(alpha: 0.08)),
                                ListTile(
                                  leading: const Icon(Icons.visibility_off, color: Colors.white),
                                  title: Text(t("Приховати чат", "Hide Chat"), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
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
                            const SizedBox(height: 12),
                            Container(
                              margin: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1F2B38),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                              ),
                              child: Column(children: [
                                ListTile(
                                  leading: Icon(isBlocked ? Icons.lock_open : Icons.block, color: const Color(0xFFFF5E57)),
                                  title: Text(
                                    isBlocked ? t("Розблокувати", "Unblock") : t("Заблокувати", "Block"),
                                    style: const TextStyle(color: Color(0xFFFF5E57), fontWeight: FontWeight.w600),
                                  ),
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
                                Divider(height: 1, indent: 56, color: Colors.white.withValues(alpha: 0.08)),
                                ListTile(
                                  leading: const Icon(Icons.delete_outline, color: Color(0xFFFF5E57)),
                                  title: Text(t("Видалити історію", "Delete History"), style: const TextStyle(color: Color(0xFFFF5E57), fontWeight: FontWeight.w600)),
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
                            const SizedBox(height: 18),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    sheetFuture.whenComplete(() {
      sheetOpen = false;
    });
  }

  void _showChatOptions(Map<String, dynamic> chat) {
    final isGroup = chat['isGroup'] == true;
    final localPartnerName = (chat['partnerName'] ?? '').toString();
    final serverPartnerKey = isGroup
        ? ((chat['publicKey'] ?? '').toString().startsWith('GROUP_')
            ? (chat['publicKey'] ?? '').toString()
            : localPartnerName)
        : localPartnerName;

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
                  if (isGroup) ...[
                    ListTile(
                      leading: const Icon(Icons.edit_note_rounded, color: Colors.white),
                      title: Text(t('Редагувати групу', 'Edit Group'), style: const TextStyle(color: Colors.white)),
                      subtitle: Text(
                        t('Назва, опис, учасники', 'Name, description, members'),
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        _showEditGroupSheet(chat);
                      },
                    ),
                    Divider(height: 1, color: Colors.white.withValues(alpha: 0.1)),
                  ],
                  ListTile(
                    leading: Icon(
                        chat['isPinned'] == true ? Icons.push_pin : Icons.push_pin_outlined,
                        color: Colors.white),
                    title: Text(chat['isPinned'] == true ? t('Відкріпити', 'Unpin') : t('Закріпити', 'Pin'),
                        style: const TextStyle(color: Colors.white)),
                    onTap: () {
                      Navigator.pop(context);
                      _applyLocalChatSettings(
                        localPartnerName,
                        isPinned: !(chat['isPinned'] == true),
                        isHidden: chat['isHidden'] == true,
                        isBlocked: chat['isBlocked'] == true,
                      );
                      _bgSocket.emit('update_chat_settings', {
                        'userName': widget.userName, 'partnerName': serverPartnerKey,
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
                        localPartnerName,
                        isPinned: chat['isPinned'] == true,
                        isHidden: true,
                        isBlocked: chat['isBlocked'] == true,
                      );
                      _bgSocket.emit('update_chat_settings', {
                        'userName': widget.userName, 'partnerName': serverPartnerKey,
                        'isPinned': chat['isPinned'] == true, 'isHidden': true,
                        'isDeleted': false, 'isBlocked': chat['isBlocked'] == true,
                      });
                    },
                  ),
                  Divider(height: 1, color: Colors.white.withValues(alpha: 0.1)),
                  ListTile(
                    leading: const Icon(Icons.delete_outline, color: Color(0xFFFF3B30)),
                    title: Text(
                      isGroup ? t('Вийти з групи', 'Leave Group') : t('Видалити', 'Delete'),
                      style: const TextStyle(color: Color(0xFFFF3B30)),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _applyLocalChatSettings(
                        localPartnerName,
                        isPinned: false,
                        isHidden: false,
                        isBlocked: chat['isBlocked'] == true,
                        isDeleted: true,
                      );
                      _bgSocket.emit('update_chat_settings', {
                        'userName': widget.userName, 'partnerName': serverPartnerKey,
                        'isPinned': false, 'isHidden': false,
                        'isDeleted': true, 'isBlocked': chat['isBlocked'] == true,
                      });
                      _loadData();
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
    final visibleChats = _filteredRecentChats();
    if (visibleChats.isEmpty) return;
    final maxIndex = visibleChats.length - 1;
    final next = (_desktopSelectedChatIndex + delta).clamp(0, maxIndex);
    if (next == _desktopSelectedChatIndex) return;
    setState(() => _desktopSelectedChatIndex = next);
    _scrollDesktopChatsToSelected();
  }

  void _scrollDesktopChatsToSelected() {
    final visibleChats = _filteredRecentChats();
    if (!_desktopChatsScrollController.hasClients || visibleChats.isEmpty) return;
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
    final visibleChats = _filteredRecentChats();
    if (visibleChats.isEmpty) return;
    final maxIndex = visibleChats.length - 1;
    final selected = _desktopSelectedChatIndex.clamp(0, maxIndex);
    if (selected != _desktopSelectedChatIndex) {
      setState(() => _desktopSelectedChatIndex = selected);
    }
    final chat = visibleChats[selected];
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
    final visibleChats = _filteredRecentChats();
    if (visibleChats.isEmpty && _desktopSelectedChatIndex != 0) {
      _desktopSelectedChatIndex = 0;
    } else if (visibleChats.isNotEmpty && _desktopSelectedChatIndex >= visibleChats.length) {
      _desktopSelectedChatIndex = visibleChats.length - 1;
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
              if (_searchController.text.trim().isNotEmpty) ...[
                const SizedBox(width: 10),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                    tooltip: t('Очистити пошук', 'Clear search'),
                    onPressed: () {
                      _searchController.clear();
                      if (mounted) setState(() => _desktopSelectedChatIndex = 0);
                    },
                  ),
                ),
              ],
              const SizedBox(width: 10),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: IconButton(
                  icon: const Icon(Icons.manage_search_rounded, color: Colors.white, size: 22),
                  tooltip: t('Пошук повідомлень', 'Search messages'),
                  onPressed: _showGlobalMessageSearchSheet,
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
                  icon: const Icon(Icons.folder_copy_rounded, color: Colors.white, size: 21),
                  tooltip: t('Керувати папками', 'Manage folders'),
                  onPressed: () => _showManageChatFoldersSheet(accent),
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
        SizedBox(
          height: 42,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _buildChatFolderChip(
                key: 'all',
                label: t('Усі', 'All'),
                count: _chatFolderCount('all'),
                accent: accent,
              ),
              const SizedBox(width: 8),
              _buildChatFolderChip(
                key: 'unread',
                label: t('Непрочитані', 'Unread'),
                count: _chatFolderCount('unread'),
                accent: accent,
              ),
              const SizedBox(width: 8),
              _buildChatFolderChip(
                key: 'direct',
                label: t('Особисті', 'Direct'),
                count: _chatFolderCount('direct'),
                accent: accent,
              ),
              const SizedBox(width: 8),
              _buildChatFolderChip(
                key: 'groups',
                label: t('Групи', 'Groups'),
                count: _chatFolderCount('groups'),
                accent: accent,
              ),
              if (_customChatFolders.isNotEmpty)
                ..._customChatFolders.map((folder) {
                  final id = (folder['id'] ?? '').toString();
                  final name = (folder['name'] ?? '').toString();
                  if (id.isEmpty || name.trim().isEmpty) return const SizedBox.shrink();
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(width: 8),
                      _buildChatFolderChip(
                        key: 'custom:$id',
                        label: name,
                        count: _chatFolderCount('custom:$id'),
                        accent: accent,
                      ),
                    ],
                  );
                }),
            ],
          ),
        ),
        const SizedBox(height: 6),
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
          child: visibleChats.isEmpty
              ? Center(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(_searchController.text.trim().isNotEmpty
                            ? t("Нічого не знайдено.", "No results found.")
                            : t("Чатів поки що немає.", "No chats yet."),
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 16)),
                    const SizedBox(height: 4),
                    Text(_searchController.text.trim().isNotEmpty
                            ? t("Спробуйте інший запит.", "Try a different query.")
                            : t("Напишіть щось друзям.", "Write something to friends."),
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 16)),
                  ]),
                )
              : Focus(
                  autofocus: (!kIsWeb && (Platform.isLinux || Platform.isMacOS)) && _currentIndex == 0,
                  onKeyEvent: (node, event) {
                    if (!(!kIsWeb && (Platform.isLinux || Platform.isMacOS)) || event is! KeyDownEvent) {
                      return KeyEventResult.ignored;
                    }
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
                    itemCount: visibleChats.length,
                    separatorBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.only(left: 76.0),
                      child: Divider(height: 1, color: Colors.white.withValues(alpha: 0.05)),
                    ),
                    itemBuilder: (context, index) {
                    final chat = visibleChats[index];
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
                          : MouseRegion(
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
                                            child: _buildHighlightedText(
                                              chatDisplayName.isNotEmpty ? chatDisplayName : chat['partnerName'],
                                              _searchController.text,
                                              const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 16,
                                                letterSpacing: -0.2,
                                              ),
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
                    return tile;
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildChatFolderChip({
    required String key,
    required String label,
    required int count,
    required Color accent,
  }) {
    final selected = _chatFolder == key;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () {
        setState(() {
          _chatFolder = key;
          _desktopSelectedChatIndex = 0;
        });
        unawaited(_saveSetting('chat_folder_selected', key));
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? accent.withValues(alpha: 0.65) : Colors.white.withValues(alpha: 0.12),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: selected ? accent : Colors.white.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showManageChatFoldersSheet(Color accent) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111216),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateSB) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text(
                          t('Папки чатів', 'Chat folders'),
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () async {
                            await _showCreateCustomFolderDialog(accent);
                            if (mounted) setStateSB(() {});
                          },
                          icon: const Icon(Icons.add_rounded, color: Colors.white),
                          label: Text(t('Нова', 'New'), style: const TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_customChatFolders.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        child: Text(
                          t('Ще немає власних папок', 'No custom folders yet'),
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.65)),
                        ),
                      )
                    else
                      ..._customChatFolders.map((folder) {
                        final id = (folder['id'] ?? '').toString();
                        final name = (folder['name'] ?? '').toString();
                        final onlyUnread = folder['onlyUnread'] == true;
                        final includeDirect = folder['includeDirect'] != false;
                        final includeGroups = folder['includeGroups'] != false;
                        final pinnedOnly = folder['pinnedOnly'] == true;
                        final rules = <String>[
                          if (includeDirect) t('direct', 'direct'),
                          if (includeGroups) t('groups', 'groups'),
                          if (onlyUnread) t('unread', 'unread'),
                          if (pinnedOnly) t('pinned', 'pinned'),
                        ].join(' • ');
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            rules.isEmpty ? t('no rules', 'no rules') : rules,
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                            onPressed: () async {
                              setState(() {
                                _customChatFolders.removeWhere((f) => (f['id'] ?? '').toString() == id);
                                if (_chatFolder == 'custom:$id') _chatFolder = 'all';
                              });
                              await _saveCustomChatFolders();
                              await _saveSetting('chat_folder_selected', _chatFolder);
                              if (mounted) setStateSB(() {});
                            },
                          ),
                        );
                      }),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showCreateCustomFolderDialog(Color accent) async {
    final nameController = TextEditingController();
    bool includeDirect = true;
    bool includeGroups = true;
    bool onlyUnread = false;
    bool pinnedOnly = false;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateSB) {
            return AlertDialog(
              backgroundColor: const Color(0xFF17181C),
              title: Text(t('Нова папка', 'New folder'), style: const TextStyle(color: Colors.white)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GlassInput(controller: nameController, hintText: t('Назва папки', 'Folder name')),
                    const SizedBox(height: 14),
                    SwitchListTile(
                      title: Text(t('Особисті чати', 'Direct chats'), style: const TextStyle(color: Colors.white)),
                      value: includeDirect,
                      activeThumbColor: accent,
                      onChanged: (v) => setStateSB(() => includeDirect = v),
                    ),
                    SwitchListTile(
                      title: Text(t('Групи', 'Groups'), style: const TextStyle(color: Colors.white)),
                      value: includeGroups,
                      activeThumbColor: accent,
                      onChanged: (v) => setStateSB(() => includeGroups = v),
                    ),
                    SwitchListTile(
                      title: Text(t('Тільки непрочитані', 'Unread only'), style: const TextStyle(color: Colors.white)),
                      value: onlyUnread,
                      activeThumbColor: accent,
                      onChanged: (v) => setStateSB(() => onlyUnread = v),
                    ),
                    SwitchListTile(
                      title: Text(t('Тільки закріплені', 'Pinned only'), style: const TextStyle(color: Colors.white)),
                      value: pinnedOnly,
                      activeThumbColor: accent,
                      onChanged: (v) => setStateSB(() => pinnedOnly = v),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(t('Скасувати', 'Cancel'), style: const TextStyle(color: Colors.white70)),
                ),
                TextButton(
                  onPressed: () async {
                    final name = nameController.text.trim();
                    if (name.isEmpty) {
                      _showSnack(t('Вкажіть назву папки', 'Enter folder name'));
                      return;
                    }
                    if (!includeDirect && !includeGroups) {
                      _showSnack(t('Оберіть хоч один тип чату', 'Select at least one chat type'));
                      return;
                    }
                    final folder = {
                      'id': DateTime.now().millisecondsSinceEpoch.toString(),
                      'name': name,
                      'includeDirect': includeDirect,
                      'includeGroups': includeGroups,
                      'onlyUnread': onlyUnread,
                      'pinnedOnly': pinnedOnly,
                    };
                    setState(() {
                      _customChatFolders.add(folder);
                      _chatFolder = 'custom:${folder['id']}';
                      _desktopSelectedChatIndex = 0;
                    });
                    await _saveCustomChatFolders();
                    await _saveSetting('chat_folder_selected', _chatFolder);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: Text(t('Створити', 'Create'), style: const TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _loadHistoryForGlobalSearch(Map<String, dynamic> chat, {int limit = 80}) async {
    final c = Completer<List<Map<String, dynamic>>>();
    final pub = (chat['publicKey'] ?? '').toString();
    final partner = pub.startsWith('GROUP_') ? pub : (chat['partnerName'] ?? '').toString();
    if (partner.isEmpty) return [];

    _bgSocket.emitWithAck(
      'get_direct_history',
      {'me': widget.userName, 'partner': partner, 'limit': limit},
      ack: (dynamic data) {
        try {
          final rows = List<Map<String, dynamic>>.from(data as List);
          if (!c.isCompleted) c.complete(rows);
        } catch (_) {
          if (!c.isCompleted) c.complete([]);
        }
      },
    );
    return c.future.timeout(const Duration(seconds: 8), onTimeout: () => []);
  }

  Future<String> _searchableMessageText(Map<String, dynamic> m, Map<String, dynamic> chat) async {
    String msgType = (m['type'] ?? 'text').toString();
    final isEph = m['isEphemeral'] == true || msgType.startsWith('ephemeral_');
    msgType = msgType.replaceFirst('ephemeral_', '');
    if (isEph) return t('Ефірне повідомлення', 'Lumyn message');
    if (msgType == 'audio') return t('Голосове повідомлення', 'Voice message');
    if (msgType == 'image') return t('Фотографія', 'Image');

    if (m['ciphertext'] != null && m['nonce'] != null && m['mac'] != null && chat['publicKey'] != null) {
      final dec = await _decrypt(
        (m['ciphertext'] ?? '').toString(),
        (m['nonce'] ?? '').toString(),
        (m['mac'] ?? '').toString(),
        (chat['publicKey'] ?? '').toString(),
        chat['isGroup'] == true,
      );
      if (dec == 'Encrypted') return t('🔒 Повідомлення зашифровано', '🔒 Message encrypted');
      try {
        if (dec.startsWith('{') && dec.endsWith('}')) {
          final j = jsonDecode(dec);
          if (j is Map && j['text'] != null) return (j['text']).toString();
        }
      } catch (_) {}
      return dec;
    }

    return (m['text'] ?? '').toString();
  }

  Future<List<Map<String, dynamic>>> _runGlobalMessageSearch(String query) async {
    final q = _normalizeSearch(query);
    if (q.length < 2) return [];
    final chats = _recentChats.take(20).toList();
    final batches = await Future.wait(chats.map((c) => _loadHistoryForGlobalSearch(c)));

    final out = <Map<String, dynamic>>[];
    for (int i = 0; i < chats.length; i++) {
      final chat = chats[i];
      final history = batches[i];
      for (final raw in history) {
        final m = Map<String, dynamic>.from(raw);
        final text = (await _searchableMessageText(m, chat)).trim();
        if (text.isEmpty) continue;
        if (!_normalizeSearch(text).contains(q)) continue;

        out.add({
          'targetName': (chat['partnerName'] ?? '').toString(),
          'targetKey': (chat['publicKey'] ?? '').toString(),
          'chatAvatar': chat['avatar'],
          'chatDisplayName': chat['displayName'],
          'chatVerified': chat['isVerified'] == true,
          'isGroup': chat['isGroup'] == true,
          'senderName': (m['senderName'] ?? '').toString(),
          'text': text,
          'timestamp': (m['timestamp'] ?? '').toString(),
        });
      }
    }

    out.sort((a, b) {
      final ad = DateTime.tryParse((a['timestamp'] ?? '').toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bd = DateTime.tryParse((b['timestamp'] ?? '').toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bd.compareTo(ad);
    });
    return out.take(120).toList();
  }

  void _showGlobalMessageSearchSheet() {
    final controller = TextEditingController();
    Timer? debounce;
    bool loading = false;
    List<Map<String, dynamic>> results = [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111216),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateSB) {
            Future<void> doSearch(String value) async {
              setStateSB(() => loading = true);
              final found = await _runGlobalMessageSearch(value);
              if (!ctx.mounted) return;
              setStateSB(() {
                results = found;
                loading = false;
              });
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 10, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
                child: SizedBox(
                  height: MediaQuery.of(ctx).size.height * 0.72,
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Text(t('Пошук повідомлень', 'Search messages'), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                          const Spacer(),
                          IconButton(
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(Icons.close_rounded, color: Colors.white70),
                          ),
                        ],
                      ),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                            ),
                            child: TextField(
                              controller: controller,
                              onChanged: (value) {
                                debounce?.cancel();
                                debounce = Timer(const Duration(milliseconds: 350), () {
                                  if (value.trim().length < 2) {
                                    setStateSB(() {
                                      loading = false;
                                      results = [];
                                    });
                                    return;
                                  }
                                  unawaited(doSearch(value));
                                });
                              },
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                hintText: t('Введіть текст (мінімум 2 символи)', 'Type text (min 2 chars)'),
                                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.45)),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                prefixIcon: const Icon(Icons.search_rounded, color: Colors.white70),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: loading
                            ? const Center(child: CircularProgressIndicator(color: Colors.white))
                            : controller.text.trim().length < 2
                                ? Center(
                                    child: Text(
                                      t('Введіть мінімум 2 символи', 'Enter at least 2 characters'),
                                      style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                                    ),
                                  )
                                : results.isEmpty
                                    ? Center(
                                        child: Text(
                                          t('Нічого не знайдено', 'Nothing found'),
                                          style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                                        ),
                                      )
                                    : ListView.separated(
                                        itemCount: results.length,
                                        separatorBuilder: (_, sepIndex) => Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
                                        itemBuilder: (context, i) {
                                          final r = results[i];
                                          final targetName = (r['targetName'] ?? '').toString();
                                          final targetKey = (r['targetKey'] ?? '').toString();
                                          final sender = (r['senderName'] ?? '').toString();
                                          final text = (r['text'] ?? '').toString();
                                          final isGroup = r['isGroup'] == true;
                                          final title = ((r['chatDisplayName'] ?? '').toString().trim().isNotEmpty)
                                              ? (r['chatDisplayName']).toString()
                                              : targetName;

                                          return ListTile(
                                            leading: SafeAvatar(
                                              avatarBase64: r['chatAvatar']?.toString(),
                                              fallbackName: targetName.isEmpty ? '?' : targetName,
                                              radius: 21,
                                              isGroup: isGroup,
                                            ),
                                            title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                                            subtitle: Text(
                                              isGroup && sender.isNotEmpty ? '$sender: $text' : text,
                                              style: TextStyle(color: Colors.white.withValues(alpha: 0.72), fontSize: 13),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            onTap: () {
                                              Navigator.pop(ctx);
                                              _startChat(
                                                targetName,
                                                targetKey.isEmpty ? null : targetKey,
                                                targetAvatar: r['chatAvatar']?.toString(),
                                                targetDisplayName: r['chatDisplayName']?.toString(),
                                                isVerified: r['chatVerified'] == true,
                                              );
                                            },
                                          );
                                        },
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
    ).whenComplete(() => debounce?.cancel());
  }

  Widget _buildFriendsTab() {
    final accent = _accentColors[_accentColor] ?? const Color(0xFFB026FF);
    final visibleFriends = _filteredFriends();
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
        const SizedBox(height: 12),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: GlassInput(
                  controller: _friendsSearchController,
                  hintText: t('Пошук друзів', 'Search friends'),
                ),
              ),
              if (_friendsSearchController.text.trim().isNotEmpty) ...[
                const SizedBox(width: 10),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                    tooltip: t('Очистити пошук', 'Clear search'),
                    onPressed: _friendsSearchController.clear,
                  ),
                ),
              ],
            ],
          ),
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
        visibleFriends.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(_friendsSearchController.text.trim().isNotEmpty
                        ? t("Нічого не знайдено.", "No results found.")
                        : t("У вас ще немає друзів.", "No friends yet."),
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 14)),
              )
            : GlassContainer(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: visibleFriends.asMap().entries.map((entry) {
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
                            child: _buildHighlightedText(
                              (f['displayName'] ?? '').toString().trim().isNotEmpty ? f['displayName'] : f['userName'],
                              _friendsSearchController.text,
                              const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 16),
                            ),
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
                      if (idx != visibleFriends.length - 1)
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

        // ── ДАНІ Й СХОВИЩЕ ──────────────────────────────────
        _sectionHeader(t("ДАНІ Й СХОВИЩЕ", "DATA & STORAGE")),
        GlassContainer(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(children: [
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              leading: _settingIcon(Icons.bar_chart_rounded, accent),
              title: Text(
                t("Використання даних", "Data usage"),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 15),
              ),
              subtitle: Text(
                t("Статистика чатів і орієнтовний трафік", "Chat stats and estimated traffic"),
                style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
              ),
              trailing: Icon(Icons.chevron_right_rounded, color: Colors.white24, size: 20),
              onTap: () => _showDataUsageSheet(accent),
            ),
            _divider(),
            _settingToggle(
              icon: Icons.download_rounded,
              iconColor: accent,
              title: t("Автозавантаження медіа", "Auto-download media"),
              subtitle: t("Фото й файли завантажуються автоматично", "Photos and files download automatically"),
              value: _autoDownloadMedia,
              onChanged: (v) {
                setState(() => _autoDownloadMedia = v);
                _saveSetting('auto_download_media', v);
                _syncSettingsToBackend();
              },
              accent: accent,
            ),
            _divider(),
            _settingToggle(
              icon: Icons.save_alt_rounded,
              iconColor: accent,
              title: t("Зберігати медіа на пристрій", "Save media to device"),
              subtitle: t("Завантажені фото й відео доступні офлайн", "Downloaded photos and videos are available offline"),
              value: _saveMediaToDevice,
              onChanged: (v) {
                setState(() => _saveMediaToDevice = v);
                _saveSetting('save_media_to_device', v);
                _syncSettingsToBackend();
              },
              accent: accent,
            ),
            _divider(),
            _settingToggle(
              icon: Icons.network_check_rounded,
              iconColor: accent,
              title: t("Економія трафіку", "Low data mode"),
              subtitle: t("Менше фонових завантажень", "Fewer background downloads"),
              value: _lowDataMode,
              onChanged: (v) {
                setState(() => _lowDataMode = v);
                _saveSetting('low_data_mode', v);
                _syncSettingsToBackend();
              },
              accent: accent,
            ),
            _divider(),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              leading: _settingIcon(Icons.cleaning_services_rounded, accent),
              title: Text(
                t("Очистити кеш зображень", "Clear image cache"),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 15),
              ),
              subtitle: Text(
                '${t("Зараз", "Now")}: ${_imageCacheSizeLabel()}',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
              ),
              trailing: Icon(Icons.chevron_right_rounded, color: Colors.white24, size: 20),
              onTap: _clearImageCache,
            ),
          ]),
        ),

        // ── ІНСТРУМЕНТИ ЧАТІВ ───────────────────────────────
        _sectionHeader(t("ІНСТРУМЕНТИ ЧАТІВ", "CHAT TOOLS")),
        GlassContainer(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(children: [
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              leading: _settingIcon(Icons.folder_copy_rounded, accent),
              title: Text(t("Папки чатів", "Chat folders"),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 15)),
              subtitle: Text(
                _customChatFolders.isEmpty
                    ? t("Налаштуйте власні фільтри чатів", "Create custom chat filters")
                    : '${_customChatFolders.length} ${t('папок', 'folders')}',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
              ),
              trailing: Icon(Icons.chevron_right_rounded, color: Colors.white24, size: 20),
              onTap: () => _showManageChatFoldersSheet(accent),
            ),
            _divider(),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              leading: _settingIcon(Icons.manage_search_rounded, accent),
              title: Text(t("Глобальний пошук", "Global search"),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 15)),
              subtitle: Text(
                t("Пошук повідомлень у всіх чатах", "Search messages across all chats"),
                style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
              ),
              trailing: Icon(Icons.chevron_right_rounded, color: Colors.white24, size: 20),
              onTap: _showGlobalMessageSearchSheet,
            ),
            _divider(),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              leading: _settingIcon(Icons.group_add_rounded, accent),
              title: Text(t("Створити групу", "Create group"),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 15)),
              subtitle: Text(
                t("Швидкий перехід до створення групового чату", "Quick access to create a group chat"),
                style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
              ),
              trailing: Icon(Icons.chevron_right_rounded, color: Colors.white24, size: 20),
              onTap: _showCreateGroupDialog,
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

        // ── STICKERS & EMOJI ───────────────────────────────
        _sectionHeader(t("СТІКЕРИ ТА ЕМОДЗІ", "STICKERS & EMOJI")),
        GlassContainer(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(children: [
            _settingToggle(
              icon: Icons.auto_awesome_rounded,
              iconColor: accent,
              title: t("Анімовані емодзі", "Animated emoji"),
              subtitle: t("Легка анімація для emoji-повідомлень", "Subtle animation for emoji-only messages"),
              value: _animatedEmojiEnabled,
              onChanged: (v) {
                setState(() => _animatedEmojiEnabled = v);
                _saveSetting('animated_emoji_enabled', v);
                _syncSettingsToBackend();
              },
              accent: accent,
            ),
            _divider(),
            _settingToggle(
              icon: Icons.emoji_emotions_rounded,
              iconColor: accent,
              title: t("Великі емодзі", "Large emoji"),
              subtitle: t("Окремі emoji відображаються більшими", "Single emoji messages are rendered larger"),
              value: _emojiLargeRenderEnabled,
              onChanged: (v) {
                setState(() => _emojiLargeRenderEnabled = v);
                _saveSetting('emoji_large_render_enabled', v);
                _syncSettingsToBackend();
              },
              accent: accent,
            ),
            _divider(),
            _settingToggle(
              icon: Icons.emoji_flags_rounded,
              iconColor: accent,
              title: t("Швидкі реакції", "Quick reactions"),
              subtitle: t("Панель реакцій у меню повідомлення", "Reaction strip in message menu"),
              value: _quickReactionsEnabled,
              onChanged: (v) {
                setState(() => _quickReactionsEnabled = v);
                _saveSetting('quick_reactions_enabled', v);
                _syncSettingsToBackend();
              },
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
    final sampleNames = [
      t('Alex', 'Alex'),
      t('Mila', 'Mila'),
      t('Den', 'Den'),
      t('Noah', 'Noah'),
      t('Sara', 'Sara'),
      t('Kai', 'Kai'),
    ];
    final sampleTexts = [
      t('Готово, зустрінемось о 19:00', 'Done, let\'s meet at 7:00 PM'),
      t('Голосове повідомлення', 'Voice message'),
      t('Дякую, все працює', 'Thanks, everything works'),
      t('Надішли фото, будь ласка', 'Send the photo please'),
      t('Захищений чат активний', 'Secure chat is active'),
      t('Побачимось пізніше', 'See you later'),
    ];

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

  String _imageCacheSizeLabel() {
    final bytes = PaintingBinding.instance.imageCache.currentSizeBytes;
    final mb = bytes / (1024 * 1024);
    if (mb < 1) return '< 1 MB';
    return '${mb.toStringAsFixed(1)} MB';
  }

  void _clearImageCache() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    if (mounted) setState(() {});
    _showSnack(t('Кеш зображень очищено', 'Image cache cleared'));
  }

  int _estimateChatUsageBytes(Map<String, dynamic> chat) {
    final preview = (chat['decryptedText'] ?? '').toString();
    final previewBytes = utf8.encode(preview).length;
    final unread = (chat['unreadCount'] ?? 0) is int ? (chat['unreadCount'] as int) : 0;
    final lastMsg = chat['lastMessage'];
    String msgType = 'text';
    if (lastMsg is Map) {
      msgType = (lastMsg['type'] ?? 'text').toString().replaceFirst('ephemeral_', '');
    }

    int mediaWeight = 0;
    if (msgType == 'image') mediaWeight += 180 * 1024;
    if (msgType == 'audio') mediaWeight += 95 * 1024;

    final avatarLen = (chat['avatar'] ?? '').toString().length;
    final avatarBytes = avatarLen > 0 ? (avatarLen * 0.75).round() : 0;
    final unreadWeight = unread * 140;

    return previewBytes + mediaWeight + avatarBytes + unreadWeight;
  }

  String _humanBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
  }

  void _showDataUsageSheet(Color accent) {
    final chats = List<Map<String, dynamic>>.from(_recentChats);
    final mapped = chats.map((c) {
      final bytes = _estimateChatUsageBytes(c);
      return {
        'chat': c,
        'bytes': bytes,
      };
    }).toList()
      ..sort((a, b) => (b['bytes'] as int).compareTo(a['bytes'] as int));

    final totalBytes = mapped.fold<int>(0, (sum, e) => sum + (e['bytes'] as int));
    final totalUnread = chats.fold<int>(0, (sum, c) => sum + (((c['unreadCount'] ?? 0) as int)));
    final groupsCount = chats.where((c) => c['isGroup'] == true).length;
    final directCount = chats.length - groupsCount;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111216),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: SizedBox(
              height: MediaQuery.of(ctx).size.height * 0.76,
              child: Column(
                children: [
                  Row(
                    children: [
                      Text(t('Використання даних', 'Data usage'), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded, color: Colors.white70),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  GlassContainer(
                    child: Column(
                      children: [
                        ListTile(
                          leading: _settingIcon(Icons.storage_rounded, accent),
                          title: Text(t('Орієнтовний обсяг', 'Estimated usage'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                          subtitle: Text(_humanBytes(totalBytes), style: TextStyle(color: Colors.white.withValues(alpha: 0.6))),
                        ),
                        _divider(),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(t('Чати', 'Chats'), style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12)),
                                    const SizedBox(height: 2),
                                    Text('${chats.length}', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(t('Непрочитані', 'Unread'), style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12)),
                                    const SizedBox(height: 2),
                                    Text('$totalUnread', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(t('Direct / Group', 'Direct / Group'), style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12)),
                                    const SizedBox(height: 2),
                                    Text('$directCount / $groupsCount', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text(t('Топ чатів за обсягом', 'Top chats by usage'), style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13, fontWeight: FontWeight.w600)),
                      const Spacer(),
                      Text(t('Оцінка', 'Estimate'), style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: mapped.isEmpty
                        ? Center(
                            child: Text(
                              t('Поки що немає даних', 'No usage data yet'),
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.55)),
                            ),
                          )
                        : ListView.separated(
                            itemCount: mapped.length > 12 ? 12 : mapped.length,
                            separatorBuilder: (_, sepIndex) => Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
                            itemBuilder: (context, i) {
                              final row = mapped[i];
                              final chat = Map<String, dynamic>.from(row['chat'] as Map);
                              final name = ((chat['displayName'] ?? '').toString().trim().isNotEmpty)
                                  ? (chat['displayName']).toString()
                                  : (chat['partnerName'] ?? t('Чат', 'Chat')).toString();
                              final bytes = row['bytes'] as int;
                              final ratio = totalBytes > 0 ? (bytes / totalBytes).clamp(0.0, 1.0) : 0.0;

                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 2),
                                leading: SafeAvatar(
                                  avatarBase64: chat['avatar']?.toString(),
                                  fallbackName: name,
                                  radius: 20,
                                  isGroup: chat['isGroup'] == true,
                                ),
                                title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(99),
                                    child: LinearProgressIndicator(
                                      minHeight: 5,
                                      value: ratio,
                                      backgroundColor: Colors.white.withValues(alpha: 0.1),
                                      color: accent,
                                    ),
                                  ),
                                ),
                                trailing: Text(_humanBytes(bytes), style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 12)),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        _clearImageCache();
                        Navigator.pop(ctx);
                      },
                      icon: const Icon(Icons.cleaning_services_rounded, color: Colors.white70, size: 18),
                      label: Text(t('Очистити кеш зображень', 'Clear image cache'), style: const TextStyle(color: Colors.white)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.16)),
                        backgroundColor: Colors.white.withValues(alpha: 0.04),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
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
    final isDesktopShortcutPlatform = !kIsWeb && (Platform.isLinux || Platform.isMacOS);

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
        shortcuts: isDesktopShortcutPlatform
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