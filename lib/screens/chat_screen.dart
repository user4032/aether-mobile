import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cryptography/cryptography.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import '../utils/globals.dart';
import '../widgets/ui_core.dart';

class _ToggleSearchIntent extends Intent {
  const _ToggleSearchIntent();
}

class ChatScreen extends StatefulWidget {
  final String deviceId, userName, myPublicKey, partnerName, partnerPublicKey;
  final String? partnerAvatar;
  final String? partnerDisplayName;
  final bool partnerIsVerified;
  final List<Map<String, dynamic>> friends;

  const ChatScreen({
    super.key, required this.deviceId, required this.userName,
    required this.myPublicKey, required this.partnerName,
    required this.partnerPublicKey, this.partnerAvatar,
    this.partnerDisplayName,
    this.partnerIsVerified = false,
    this.friends = const [],
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const int _historyPageSize = 80;
  static const _accentColors = {
    'purple': Color(0xFFB026FF),
    'blue': Color(0xFF007AFF),
    'green': Color(0xFF34C759),
    'orange': Color(0xFFFF9500),
    'white': Color(0xFFEDEDED),
  };

  late io.Socket socket;
  final List<Map<String, dynamic>> _messages = [];
  final TextEditingController _c = TextEditingController();
  final TextEditingController _searchBarController = TextEditingController();
  final AesGcm _aes = AesGcm.with256bits();
  final _storage = const FlutterSecureStorage();
  final ImagePicker _picker = ImagePicker();
  final AudioRecorder _audioRecorder = AudioRecorder();
  final FocusNode _chatFocusNode = FocusNode();

  bool _isRecordingAudio = false;
  bool _isPartnerTyping = false;
  bool _isPartnerOnline = false;
  bool _isCheckingPresence = true;
  bool _isLoadingHistory = true;
  bool _isLoadingMoreHistory = false;
  bool _hasMoreHistory = true;
  bool _isAetherMode = false;
  bool _isSearchMode = false;
  
  final int _ephemeralDuration = 5;

  String _searchQuery = '';
  List<int> _searchMatchIndices = [];
  int _currentSearchIdx = -1;

  final Map<String, SecretKey> _keyCache = {};
  final Map<String, Map<String, List<String>>> _reactions = {};
  final ScrollController _scrollController = ScrollController();

  Timer? _typingTimer;
  late String _currentPartnerKey;
  Map<String, dynamic>? _replyingTo;
  Map<String, dynamic>? _editingMessage;
  bool _hasText = false;
  bool _isTearingDown = false;
  bool _socketInitialized = false;
  double _chatFontSize = 15.0;
  String _accentColor = 'purple';
  String _chatBubbleStyle = 'rounded';
  bool _compactMode = false;
  bool _readReceiptsEnabled = true;
  bool _onlineStatusEnabled = true;
  bool _typingIndicatorEnabled = true;
  bool _animatedEmojiEnabled = true;
  bool _quickReactionsEnabled = true;
  bool _emojiLargeRenderEnabled = true;
  bool _autoDownloadMedia = true;
  int? _oldestMessageId;
  String? _groupNameOverride;

  StreamSubscription<Amplitude>? _amplitudeSub;
  List<double> _recordAmplitudes = [];
  int _recordDuration = 0;
  Timer? _recordTimer;

  @override
  void initState() {
    super.initState();
    _currentPartnerKey = widget.partnerPublicKey;
    currentActiveChat = widget.partnerPublicKey.startsWith('GROUP_') ? widget.partnerPublicKey : widget.partnerName;
    _scrollController.addListener(_maybeLoadOlderHistory);
    _loadUiPreferences();
    _connect();
  }

  Future<void> _loadUiPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted || _isTearingDown) return;
    final size = (prefs.getDouble('chat_font_size') ?? 14.0).clamp(12.0, 18.0).toDouble();
    setState(() {
      _chatFontSize = size;
      _accentColor = prefs.getString('accent_color') ?? 'purple';
      _chatBubbleStyle = prefs.getString('bubble_style') ?? 'rounded';
      _compactMode = prefs.getBool('compact_mode') ?? false;
      _readReceiptsEnabled = prefs.getBool('read_receipts') ?? true;
      _onlineStatusEnabled = prefs.getBool('online_status') ?? true;
      _typingIndicatorEnabled = prefs.getBool('typing_indicator') ?? true;
      _animatedEmojiEnabled = prefs.getBool('animated_emoji_enabled') ?? true;
      _quickReactionsEnabled = prefs.getBool('quick_reactions_enabled') ?? true;
      _emojiLargeRenderEnabled = prefs.getBool('emoji_large_render_enabled') ?? true;
      _autoDownloadMedia = prefs.getBool('auto_download_media') ?? true;
    });
    if (_socketInitialized && socket.connected) {
      _emitSetActive();
    }
  }

  Color _onAccent(Color color) {
    return ThemeData.estimateBrightnessForColor(color) == Brightness.dark ? Colors.white : Colors.black;
  }

  void _emitSetActive() {
    socket.emit('set_active', {
      'userName': widget.userName,
      'deviceId': widget.deviceId,
      'onlineStatus': _onlineStatusEnabled,
    });
  }

  void _emitTyping(bool isTyping) {
    if (!widget.partnerPublicKey.startsWith('GROUP_') && !_typingIndicatorEnabled) {
      if (isTyping) return;
    }
    socket.emit('typing', {
      'senderName': widget.userName,
      'receiverName': widget.partnerName,
      'isTyping': isTyping,
    });
  }

  BorderRadius _bubbleRadius(bool isMe) {
    switch (_chatBubbleStyle) {
      case 'sharp':
        return BorderRadius.only(
          topLeft: const Radius.circular(8),
          topRight: const Radius.circular(8),
          bottomLeft: Radius.circular(isMe ? 8 : 2),
          bottomRight: Radius.circular(isMe ? 2 : 8),
        );
      case 'minimal':
        return BorderRadius.circular(10);
      case 'rounded':
      default:
        return BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(isMe ? 18 : 4),
          bottomRight: Radius.circular(isMe ? 4 : 18),
        );
    }
  }

  BorderRadius _scaledBubbleRadius(bool isMe, double scale) {
    final base = _bubbleRadius(isMe);
    return BorderRadius.only(
      topLeft: Radius.circular(base.topLeft.x * scale),
      topRight: Radius.circular(base.topRight.x * scale),
      bottomLeft: Radius.circular(base.bottomLeft.x * scale),
      bottomRight: Radius.circular(base.bottomRight.x * scale),
    );
  }

  void _safeSetState(VoidCallback fn) {
    if (!mounted || _isTearingDown) return;
    setState(fn);
  }

  Future<SecretKey> _getSecretKey(String remotePub) async {
    if (_keyCache.containsKey(remotePub)) {
      return _keyCache[remotePub]!;
    }
    SecretKey finalKey;
    if (remotePub.startsWith('GROUP_')) {
      final hash = await Sha256().hash(utf8.encode(remotePub));
      finalKey = await _aes.newSecretKeyFromBytes(hash.bytes);
    } else {
      final priv = await _storage.read(key: 'private_key');
      final secret = await X25519().sharedSecretKey(
        keyPair: SimpleKeyPairData(base64Decode(priv!), publicKey: SimplePublicKey(base64Decode(widget.myPublicKey), type: KeyPairType.x25519), type: KeyPairType.x25519),
        remotePublicKey: SimplePublicKey(base64Decode(remotePub), type: KeyPairType.x25519),
      );
      finalKey = await _aes.newSecretKeyFromBytes(await secret.extractBytes());
    }
    _keyCache[remotePub] = finalKey;
    return finalKey;
  }

  Future<void> _startRecording() async {
  try {
    final hasPermission = await _audioRecorder.hasPermission();
    if (!hasPermission) {
      debugPrint("Microphone permission denied");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t('Дозвольте доступ до мікрофону в налаштуваннях', 'Allow microphone access in Settings')),
          backgroundColor: Colors.red.shade900,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
        ));
      }
      return;
    }
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _audioRecorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
        noiseSuppress: true, 
        echoCancel: true,    
      ),
      path: path,
    );
    setState(() {
      _isRecordingAudio = true;
      _recordDuration = 0;
      _recordAmplitudes = List.generate(30, (_) => 2.0);
    });
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _recordDuration++);
    });
    _amplitudeSub = _audioRecorder.onAmplitudeChanged(const Duration(milliseconds: 50)).listen((amp) {
      if (mounted) {
        setState(() {
          double height = (amp.current + 50).clamp(0.0, 50.0) / 50.0 * 28.0;
          List<double> newAmps = List.from(_recordAmplitudes);
          newAmps.add(max(2.0, height));
          if (newAmps.length > 30) newAmps.removeAt(0);
          _recordAmplitudes = newAmps;
        });
      }
    });
  } catch (e) {
    debugPrint("Recording error: $e");
    setState(() => _isRecordingAudio = false);
  }
}

  Future<void> _stopRecording() async {
    try {
      _recordTimer?.cancel();
      _amplitudeSub?.cancel();
      final path = await _audioRecorder.stop();
      setState(() => _isRecordingAudio = false);
      if (path != null) { 
        final bytes = await File(path).readAsBytes(); 
        _send(textOverride: base64Encode(bytes), type: 'audio'); 
      }
    } catch (e) { debugPrint(e.toString()); }
  }

  void _cancelRecording() {
    _recordTimer?.cancel();
    _amplitudeSub?.cancel();
    _audioRecorder.stop();
    setState(() => _isRecordingAudio = false);
  }

  Future<void> _processMessage(Map<String, dynamic> msg) async {
    String msgType = msg['type'] ?? 'text';
    if (msgType.startsWith('ephemeral_')) { 
      msg['isEphemeral'] = true; 
      msg['type'] = msgType.replaceFirst('ephemeral_', ''); 
    }
    if (msg['type'] == 'audio') {
      final prefs = await SharedPreferences.getInstance();
      msg['isListened'] = prefs.getBool('listened_${msg['timestamp']}') ?? false;
    }
    if (msg['reactions'] != null) {
      final msgKey = '${msg['timestamp']}_${msg['senderName']}';
      final rawReactions = Map<String, dynamic>.from(msg['reactions']);
      _reactions[msgKey] = rawReactions.map((emoji, users) => MapEntry(emoji, List<String>.from(users)));
    }
    if (msg['ciphertext'] != null) {
      String remotePub = _currentPartnerKey;
      if (!_currentPartnerKey.startsWith('GROUP_')) {
        remotePub = (msg['senderName'] == widget.partnerName) ? (msg['publicKey'] ?? _currentPartnerKey) : _currentPartnerKey;
      }
      try {
        final key = await _getSecretKey(remotePub);
        final box = SecretBox(base64Decode(msg['ciphertext']), nonce: base64Decode(msg['nonce']), mac: Mac(base64Decode(msg['mac'])));
        String dec = utf8.decode(await _aes.decrypt(box, secretKey: key));
        if (dec.startsWith('{') && dec.endsWith('}')) {
          final parsed = jsonDecode(dec);
          msg['text'] = parsed['text'];
          msg['replyTo'] = parsed['replyTo'];
          if (parsed['imageBytes'] != null) {
            msg['imageBytes'] = base64Decode(parsed['imageBytes']);
          }
        } else { msg['text'] = dec; }
      } catch (e) { 
        msg['text'] = "Encrypted"; 
        msg['isDecryptionFailed'] = true; 
      }
    }
    if (msg['senderName'] == widget.partnerName && msg['publicKey'] != null && !msg['publicKey'].toString().startsWith('GROUP_')) {
      _currentPartnerKey = msg['publicKey'];
    }
    if (msg['type'] == 'image' && msg['text'] != null && msg['text'].toString().length > 100) {
      try { 
        msg['imageBytes'] = base64Decode(msg['text']); 
        msg['text'] = ""; 
      } catch (_) {}
    }
  }

  String _historyPartnerId() {
    return widget.partnerPublicKey.startsWith('GROUP_') ? widget.partnerPublicKey : widget.partnerName;
  }

  int? _extractOldestId(List<Map<String, dynamic>> batch) {
    int? oldest;
    for (final item in batch) {
      final raw = item['id'];
      final id = raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '');
      if (id == null) continue;
      if (oldest == null || id < oldest) oldest = id;
    }
    return oldest;
  }

  void _loadInitialHistory() {
    final historyPartner = _historyPartnerId();
    if (mounted) {
      setState(() {
        _isLoadingHistory = true;
        _isLoadingMoreHistory = false;
      });
    }
    socket.emitWithAck(
      'get_direct_history',
      {'me': widget.userName, 'partner': historyPartner, 'limit': _historyPageSize},
      ack: (dynamic data) async {
        final incoming = List<Map<String, dynamic>>.from(data as List);
        final oldestId = _extractOldestId(incoming);
        List<Map<String, dynamic>> temp = [];
        bool hasEncryptedOldMessages = false;

        for (var m in incoming) {
          var msgMap = Map<String, dynamic>.from(m);
          await _processMessage(msgMap);
          
          if (msgMap['isEphemeral'] == true) {
            try {
              final createdAt = DateTime.parse(msgMap['timestamp'].toString());
              final duration = (msgMap['ephemeralDuration'] as int?) ?? _ephemeralDuration;
              final expiresAt = createdAt.add(Duration(seconds: duration));
              if (DateTime.now().isAfter(expiresAt)) {
                continue; 
              }
            } catch (_) {}
          }
          
          if (msgMap['isDecryptionFailed'] == true) {
            hasEncryptedOldMessages = true;
          } else {
            temp.add(msgMap);
          }
        }

        if (hasEncryptedOldMessages) {
          temp.insert(0, {
            'isSystem': true,
            'text': t("🔒 Попередні повідомлення були надійно зашифровані та недоступні для цієї сесії.", "🔒 Previous messages were encrypted and are unavailable in this session."),
            'timestamp': temp.isNotEmpty ? temp.first['timestamp'] : DateTime.now().toIso8601String(),
            'senderName': 'system',
          });
        }

        if (mounted) {
          setState(() {
            _messages
              ..clear()
              ..addAll(temp);
            _isLoadingHistory = false;
            _hasMoreHistory = incoming.length >= _historyPageSize;
            _oldestMessageId = oldestId;
          });
          if (_readReceiptsEnabled) {
            socket.emit('mark_read', {'chatId': historyPartner, 'readerName': widget.userName});
          }
          Future.delayed(const Duration(milliseconds: 100), () {
            if (_scrollController.hasClients && mounted) {
              _scrollController.animateTo(_scrollController.position.maxScrollExtent + 100, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
            }
          });
        }
      },
    );
  }

  void _maybeLoadOlderHistory() {
    if (!_scrollController.hasClients || _isLoadingHistory || _isLoadingMoreHistory || !_hasMoreHistory) return;
    if (_scrollController.offset <= 140) {
      _loadOlderHistory();
    }
  }

  void _loadOlderHistory() {
    if (_oldestMessageId == null || _isLoadingMoreHistory || !_hasMoreHistory) return;
    final historyPartner = _historyPartnerId();
    final prevOffset = _scrollController.hasClients ? _scrollController.offset : 0.0;
    final prevMax = _scrollController.hasClients ? _scrollController.position.maxScrollExtent : 0.0;

    setState(() => _isLoadingMoreHistory = true);
    socket.emitWithAck(
      'get_direct_history',
      {
        'me': widget.userName,
        'partner': historyPartner,
        'beforeId': _oldestMessageId,
        'limit': _historyPageSize,
      },
      ack: (dynamic data) async {
        final incoming = List<Map<String, dynamic>>.from(data as List);
        final oldestId = _extractOldestId(incoming);
        if (incoming.isEmpty) {
          if (mounted) {
            setState(() {
              _isLoadingMoreHistory = false;
              _hasMoreHistory = false;
            });
          }
          return;
        }

        final existingKeys = _messages.map((m) => '${m['timestamp']}_${m['senderName']}').toSet();
        final older = <Map<String, dynamic>>[];
        for (final m in incoming) {
          final msgMap = Map<String, dynamic>.from(m);
          await _processMessage(msgMap);
          if (msgMap['isDecryptionFailed'] == true) continue;
          final key = '${msgMap['timestamp']}_${msgMap['senderName']}';
          if (!existingKeys.contains(key)) {
            older.add(msgMap);
          }
        }

        if (!mounted) return;
        setState(() {
          if (older.isNotEmpty) {
            _messages.insertAll(0, older);
          }
          _isLoadingMoreHistory = false;
          _hasMoreHistory = incoming.length >= _historyPageSize;
          _oldestMessageId = oldestId ?? _oldestMessageId;
        });

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_scrollController.hasClients) return;
          final nextMax = _scrollController.position.maxScrollExtent;
          final delta = nextMax - prevMax;
          final target = (prevOffset + delta).clamp(0.0, nextMax);
          _scrollController.jumpTo(target);
        });
      },
    );
  }

  void _connect() {
    socket = io.io('https://aether-backend-hrmq.onrender.com', {
      'transports': ['websocket', 'polling'],
      'upgrade': true,
      'timeout': 20000,
      'forceNew': true,
    });
    _socketInitialized = true;
    socket.connect();
    socket.onConnect((_) {
      _emitSetActive();
      if (!widget.partnerPublicKey.startsWith('GROUP_')) {
        socket.emitWithAck('check_presence', widget.partnerName, ack: (dynamic data) { 
          if (mounted) {
            setState(() { _isPartnerOnline = data['isOnline']; _isCheckingPresence = false; }); 
          }
        });
      } else {
        if (mounted) {
          setState(() { _isCheckingPresence = false; });
        }
      }

      _loadInitialHistory();
    });

    socket.onDisconnect((_) {
      _safeSetState(() => _isPartnerOnline = false);
    });
    socket.onReconnect((_) {
      _emitSetActive();
      if (!widget.partnerPublicKey.startsWith('GROUP_')) {
        socket.emitWithAck('check_presence', widget.partnerName, ack: (dynamic data) {
          _safeSetState(() => _isPartnerOnline = data['isOnline']);
        });
      }
      _loadInitialHistory();
    });

    socket.on('message', (data) async {
      var msg = Map<String, dynamic>.from(data);
      bool isRelevant = _currentPartnerKey.startsWith('GROUP_')
          ? msg['receiverName'] == _currentPartnerKey
          : ((msg['senderName'] == widget.userName && msg['receiverName'] == widget.partnerName) || (msg['senderName'] == widget.partnerName && msg['receiverName'] == widget.userName));
      if (isRelevant) {
        await _processMessage(msg);
        if (mounted && !_messages.any((m) => m['timestamp'] == msg['timestamp'] && m['senderName'] == msg['senderName'])) {
          setState(() {
            _messages.add(msg);
            if (_isSearchMode && _searchQuery.isNotEmpty) {
              _updateSearchResults();
            }
          });
          if (msg['isEphemeral'] == true) {
            final duration = (msg['ephemeralDuration'] as int?) ?? _ephemeralDuration;
            Timer(Duration(seconds: duration), () {
              if (mounted) {
                setState(() {
                  _messages.removeWhere((m) => m['timestamp'] == msg['timestamp'] && m['senderName'] == msg['senderName']);
                });
              }
            });
          }
          Future.delayed(const Duration(milliseconds: 100), () {
            if (_scrollController.hasClients && mounted) {
              _scrollController.animateTo(_scrollController.position.maxScrollExtent + 100, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
            }
          });
          if (msg['senderName'] != widget.userName && msg['isEphemeral'] != true && _readReceiptsEnabled) {
            String chatId = _currentPartnerKey.startsWith('GROUP_') ? _currentPartnerKey : msg['senderName'];
            socket.emit('mark_read', {'chatId': chatId, 'readerName': widget.userName});
          }
        }
      }
    });

    socket.on('messages_read', (data) {
      if (mounted) {
        bool changed = false;
        String chatId = data['chatId'] ?? '';
        String reader = data['readerName'] ?? '';
        if ((chatId == _currentPartnerKey || chatId == widget.userName) && reader != widget.userName) {
          for (var m in _messages) { 
            if (m['senderName'] == widget.userName && m['status'] != 'read') { 
              m['status'] = 'read'; changed = true; 
            } 
          }
        }
        if (changed) {
          setState(() {});
        }
      }
    });

    socket.on('message_deleted', (data) { if (mounted) setState(() => _messages.removeWhere((m) => m['timestamp'] == data['timestamp'] && m['senderName'] == data['senderName'])); });

    socket.on('message_blocked', (data) {
      if (!mounted) return;
      final reason = data is Map<String, dynamic> ? data['message'] : null;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text((reason ?? t('Користувач обмежив коло, хто може писати', 'This user restricts who can message them')).toString()),
        backgroundColor: Colors.red.shade900,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
      ));
    });

    socket.on('message_edited', (data) async {
      var editedMsgData = Map<String, dynamic>.from(data);
      if (mounted) {
        int idx = _messages.indexWhere((m) => m['timestamp'] == editedMsgData['timestamp'] && m['senderName'] == editedMsgData['senderName']);
        if (idx != -1) {
          _messages[idx]['ciphertext'] = editedMsgData['ciphertext'];
          _messages[idx]['nonce'] = editedMsgData['nonce'];
          _messages[idx]['mac'] = editedMsgData['mac'];
          _messages[idx]['isEdited'] = 1;
          await _processMessage(_messages[idx]);
          setState(() {});
        }
      }
    });

    socket.on('typing', (data) { if (data['senderName'] == widget.partnerName && data['receiverName'] == widget.userName && mounted) setState(() => _isPartnerTyping = data['isTyping']); });

    socket.on('user_presence', (data) {
      if (!mounted || widget.partnerPublicKey.startsWith('GROUP_')) return;
      final map = Map<String, dynamic>.from(data as Map);
      if (map['userName'] == widget.partnerName) {
        _safeSetState(() {
          _isPartnerOnline = map['isOnline'] == true;
          _isCheckingPresence = false;
        });
      }
    });
    
    socket.on('reaction_update', (data) {
      if (!mounted) return;
      final msgKey = '${data['msgTimestamp']}_${data['msgSender']}';
      setState(() {
        _reactions[msgKey] ??= {};
        final emoji = data['emoji'] as String?;
        final reactor = data['reactorName'] as String;
        if (emoji == null) {
          _reactions[msgKey]!.forEach((e, list) => list.remove(reactor));
          _reactions[msgKey]!.removeWhere((_, list) => list.isEmpty);
        } else {
          _reactions[msgKey]!.forEach((e, list) { list.remove(reactor); });
          _reactions[msgKey]!.removeWhere((_, list) => list.isEmpty);
          _reactions[msgKey]![emoji] ??= [];
          if (!_reactions[msgKey]![emoji]!.contains(reactor)) {
            _reactions[msgKey]![emoji]!.add(reactor);
          }
        }
      });
    });
  }

  void _toggleReaction(Map<String, dynamic> msg, String emoji) {
    final msgKey = '${msg['timestamp']}_${msg['senderName']}';
    final myList = _reactions[msgKey]?[emoji] ?? [];
    if (myList.contains(widget.userName)) {
      socket.emit('remove_reaction', {'msgTimestamp': msg['timestamp'], 'msgSender': msg['senderName'], 'reactorName': widget.userName});
    } else {
      socket.emit('add_reaction', {'msgTimestamp': msg['timestamp'], 'msgSender': msg['senderName'], 'reactorName': widget.userName, 'emoji': emoji});
    }
  }

  void _updateSearchResults() {
    _searchMatchIndices = [];
    if (_searchQuery.isEmpty) { _currentSearchIdx = -1; return; }
    for (int i = 0; i < _messages.length; i++) {
      final text = _messages[i]['text']?.toString().toLowerCase() ?? '';
      if (text.contains(_searchQuery.toLowerCase())) {
        _searchMatchIndices.add(i);
      }
    }
    if (_searchMatchIndices.isNotEmpty) {
      _currentSearchIdx = _searchMatchIndices.length - 1;
      _scrollToSearchMatch();
    } else {
      _currentSearchIdx = -1;
    }
  }

  void _scrollToSearchMatch() {
    if (_currentSearchIdx < 0 || _currentSearchIdx >= _searchMatchIndices.length) return;
    if (!_scrollController.hasClients) return;
    final msgIdx = _searchMatchIndices[_currentSearchIdx];
    final total = _messages.length;
    if (total == 0) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final targetScroll = (msgIdx / total) * maxScroll;
    _scrollController.animateTo(targetScroll.clamp(0.0, maxScroll), duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  void _prevMatch() { if (_searchMatchIndices.isEmpty) return; setState(() { _currentSearchIdx = (_currentSearchIdx - 1 + _searchMatchIndices.length) % _searchMatchIndices.length; }); _scrollToSearchMatch(); }
  void _nextMatch() { if (_searchMatchIndices.isEmpty) return; setState(() { _currentSearchIdx = (_currentSearchIdx + 1) % _searchMatchIndices.length; }); _scrollToSearchMatch(); }

  void _closeSearch() { setState(() { _isSearchMode = false; _searchQuery = ''; _searchMatchIndices = []; _currentSearchIdx = -1; _searchBarController.clear(); }); }

  void _onTextChanged(String text) {
    bool currentHasText = text.trim().isNotEmpty;
    if (_hasText != currentHasText) {
      setState(() { _hasText = currentHasText; });
    }
    _emitTyping(true);
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(milliseconds: 1500), () { 
      _emitTyping(false);
    });
  }

  void _send({String? textOverride, String type = 'text'}) async {
    final text = textOverride ?? _c.text.trim();
    if (text.isEmpty && type == 'text') return;
    final isEditingMode = _editingMessage != null;
    if (type == 'text' && !isEditingMode) { _c.clear(); setState(() { _hasText = false; }); }
    final replyData = _replyingTo != null ? {'senderName': _replyingTo!['senderName'] ?? 'Unknown', 'text': _replyingTo!['type'] == 'image' ? t('Фото', 'Image') : (_replyingTo!['type'] == 'audio' ? t('Голосове повідомлення', 'Voice message') : (_replyingTo!['text']?.toString() ?? t('Повідомлення', 'Message')))} : null;
    setState(() { _replyingTo = null; });
    _emitTyping(false);
    final key = await _getSecretKey(_currentPartnerKey);
    String payloadStr = replyData != null ? jsonEncode({'text': text, 'replyTo': replyData}) : text;
    final box = await _aes.encrypt(utf8.encode(payloadStr), secretKey: key);
    String actualType = type;
    if (_isAetherMode) {
      actualType = 'ephemeral_$type';
    }
    if (isEditingMode) {
      socket.emit('edit_message', {'text': text, 'ciphertext': base64Encode(box.cipherText), 'nonce': base64Encode(box.nonce), 'mac': base64Encode(box.mac.bytes), 'timestamp': _editingMessage!['timestamp'], 'senderName': widget.userName});
      setState(() { _editingMessage = null; });
      _c.clear();
      setState(() { _hasText = false; });
    } else {
      socket.emit('message', {
        'type': actualType, 'text': text, 'ciphertext': base64Encode(box.cipherText), 'nonce': base64Encode(box.nonce), 'mac': base64Encode(box.mac.bytes), 'senderName': widget.userName, 'receiverName': _currentPartnerKey.startsWith('GROUP_') ? _currentPartnerKey : widget.partnerName,
        if (_isAetherMode) 'ephemeralDuration': _ephemeralDuration,
      });
    }
  }

  Future<void> _sendScheduled(DateTime scheduledAt) async {
    final text = _c.text.trim();
    if (text.isEmpty) return;
    _c.clear();
    setState(() { _hasText = false; });
    final key = await _getSecretKey(_currentPartnerKey);
    final box = await _aes.encrypt(utf8.encode(text), secretKey: key);
    socket.emitWithAck('schedule_message', {
      'type': 'text', 'senderName': widget.userName, 'receiverName': _currentPartnerKey.startsWith('GROUP_') ? _currentPartnerKey : widget.partnerName,
      'text': text, 'ciphertext': base64Encode(box.cipherText), 'nonce': base64Encode(box.nonce), 'mac': base64Encode(box.mac.bytes), 'publicKey': widget.myPublicKey, 'scheduledAt': scheduledAt.toUtc().toIso8601String(),
    }, ack: (dynamic response) {
      if (mounted && response['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${t("Заплановано на", "Scheduled for")} ${DateFormat('dd.MM HH:mm').format(scheduledAt)}', style: const TextStyle(color: Colors.white)), backgroundColor: const Color(0xFF333333), behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50))));
      }
    });
  }

  Future<void> _showScheduleDialog() async {
    final now = DateTime.now();
    final accent = _accentColors[_accentColor] ?? const Color(0xFFB026FF);
    final date = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(hours: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      builder: (ctx, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: ColorScheme.dark(primary: accent, surface: const Color(0xFF1E1E2C)),
          ),
          child: child!,
        );
      },
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
      builder: (ctx, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: ColorScheme.dark(primary: accent, surface: const Color(0xFF1E1E2C)),
          ),
          child: child!,
        );
      },
    );
    if (time == null || !mounted) return;
    final scheduledAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (scheduledAt.isBefore(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('Час вже минув!', 'Time is in the past!'), style: const TextStyle(color: Colors.white)), backgroundColor: Colors.red.shade900, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50))));
      return;
    }
    await _sendScheduled(scheduledAt);
  }

  void _showAttachmentMenu() {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(10))),
                  const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _attachmentIcon(Icons.photo_library, t("Галерея", "Gallery"), () { Navigator.pop(ctx); _pickAndSendImagesFromGallery(); }),
                        if (!Platform.isWindows && !Platform.isLinux) _attachmentIcon(Icons.camera_alt, t("Камера", "Camera"), () { Navigator.pop(ctx); _pickAndSendImage(ImageSource.camera); }),
                        _attachmentIcon(Icons.insert_drive_file, t("Файл", "File"), () { 
                          Navigator.pop(ctx); 
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('Надсилання файлів з\'явиться в наступному оновленні!', 'File sending coming in next update!'), style: const TextStyle(color: Colors.white)), backgroundColor: const Color(0xFF333333), behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50))));
                        }),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          );
      },
    );
  }

  Widget _attachmentIcon(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), shape: BoxShape.circle, border: Border.all(color: Colors.white.withValues(alpha: 0.15))),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Future<void> _pickAndSendImagesFromGallery() async {
    try {
      final images = await _picker.pickMultiImage(
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 70,
      );
      if (!mounted) return;

      if (images.isEmpty) {
        final single = await _picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 1280,
          maxHeight: 1280,
          imageQuality: 70,
        );
        if (single == null || !mounted) return;
        await _showPhotoComposerSheet([single]);
        return;
      }

      await _showPhotoComposerSheet(images);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t('Не вдалося відкрити галерею', 'Failed to open gallery')),
        backgroundColor: Colors.red.shade900,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
      ));
    }
  }

  Future<void> _showPhotoComposerSheet(List<XFile> images) async {
    if (!mounted || images.isEmpty) return;

    final captionController = TextEditingController();
    final pageController = PageController();
    int active = 0;
    bool sending = false;

    final previewBytes = <Uint8List>[];
    for (final image in images) {
      previewBytes.add(await image.readAsBytes());
    }

    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateSB) {
            final h = MediaQuery.of(ctx).size.height;
            final w = MediaQuery.of(ctx).size.width;
            final canSend = !sending && previewBytes.isNotEmpty;

            return Container(
              height: h * 0.9,
              decoration: BoxDecoration(
                color: const Color(0xFF0C0D12),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: sending ? null : () => Navigator.pop(ctx),
                            icon: const Icon(Icons.close_rounded, color: Colors.white),
                          ),
                          Text(
                            t('Надіслати фото', 'Send photo'),
                            style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700),
                          ),
                          const Spacer(),
                          Text(
                            '${active + 1}/${previewBytes.length}',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: PageView.builder(
                        controller: pageController,
                        itemCount: previewBytes.length,
                        onPageChanged: (i) => setStateSB(() => active = i),
                        itemBuilder: (context, i) {
                          return Center(
                            child: Container(
                              width: w,
                              margin: const EdgeInsets.symmetric(horizontal: 10),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(18),
                                child: Image.memory(
                                  previewBytes[i],
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    if (previewBytes.length > 1)
                      SizedBox(
                        height: 74,
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          scrollDirection: Axis.horizontal,
                          itemCount: previewBytes.length,
                          separatorBuilder: (context, index) => const SizedBox(width: 8),
                          itemBuilder: (context, i) {
                            final selected = i == active;
                            return GestureDetector(
                              onTap: () {
                                pageController.animateToPage(
                                  i,
                                  duration: const Duration(milliseconds: 220),
                                  curve: Curves.easeOut,
                                );
                              },
                              child: Container(
                                width: 58,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: selected ? Colors.white : Colors.white.withValues(alpha: 0.12),
                                    width: selected ? 2 : 1,
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.memory(previewBytes[i], fit: BoxFit.cover),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(12, 4, 12, 12 + MediaQuery.of(ctx).viewInsets.bottom),
                      child: Row(
                        children: [
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                              ),
                              child: TextField(
                                controller: captionController,
                                minLines: 1,
                                maxLines: 4,
                                enabled: !sending,
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  hintText: t('Додати підпис...', 'Add a caption...'),
                                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.45)),
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: !canSend
                                ? null
                                : () async {
                                    setStateSB(() => sending = true);
                                    final caption = captionController.text.trim();
                                    for (int i = 0; i < previewBytes.length; i++) {
                                      final currentCaption = i == 0 ? caption : '';
                                      await _sendWithImage(currentCaption, base64Encode(previewBytes[i]));
                                    }
                                    if (!ctx.mounted) return;
                                    Navigator.pop(ctx);
                                  },
                            child: Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                color: canSend ? Colors.white : Colors.white24,
                                shape: BoxShape.circle,
                              ),
                              child: sending
                                  ? const Padding(
                                      padding: EdgeInsets.all(12),
                                      child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.black),
                                    )
                                  : const Icon(Icons.arrow_upward_rounded, color: Colors.black, size: 22),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _pickAndSendImage(ImageSource source) async {
    final XFile? image = await _picker.pickImage(source: source, maxWidth: 1280, maxHeight: 1280, imageQuality: 70);
    if (image == null || !mounted) return;
    await _showPhotoComposerSheet([image]);
  }

  Future<void> _sendWithImage(String caption, String base64Image) async {
    final key = await _getSecretKey(_currentPartnerKey);
    String payloadStr = jsonEncode({
      'text': caption,
      'imageBytes': base64Image,
      if (_replyingTo != null) 'replyTo': {
        'senderName': _replyingTo!['senderName'] ?? 'Unknown', 
        'text': _replyingTo!['type'] == 'image' ? 'Фото' : _replyingTo!['text']
      }
    });

    final box = await _aes.encrypt(utf8.encode(payloadStr), secretKey: key);
    String actualType = _isAetherMode ? 'ephemeral_image' : 'image';

    socket.emit('message', {
      'type': actualType, 'text': 'encrypted_payload', 'ciphertext': base64Encode(box.cipherText), 'nonce': base64Encode(box.nonce), 'mac': base64Encode(box.mac.bytes), 'senderName': widget.userName, 'receiverName': _currentPartnerKey.startsWith('GROUP_') ? _currentPartnerKey : widget.partnerName,
      if (_isAetherMode) 'ephemeralDuration': _ephemeralDuration,
    });
    
    setState(() { _replyingTo = null; });
  }

  void _showMessageOptions(Map<String, dynamic> m, bool isMe) {
    if (m['isEphemeral'] == true) return;
    final accent = _accentColors[_accentColor] ?? const Color(0xFFB026FF);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          width: double.infinity,
          decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: const BorderRadius.vertical(top: Radius.circular(30))),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    decoration: BoxDecoration(color: const Color(0xFF2A2A2A), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withValues(alpha: 0.15))),
                      child: _quickReactionsEnabled
                          ? Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: ['❤️', '😂', '🔥', '👍', '😮', '🎉', '🤯', '😢'].map((emoji) {
                                final msgKey = '${m['timestamp']}_${m['senderName']}';
                                final isMine = _reactions[msgKey]?[emoji]?.contains(widget.userName) ?? false;
                                return GestureDetector(
                                  onTap: () { Navigator.pop(context); _toggleReaction(m, emoji); },
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(color: isMine ? accent.withValues(alpha: 0.3) : Colors.transparent, borderRadius: BorderRadius.circular(12)),
                                    child: Text(emoji, style: const TextStyle(fontSize: 26)),
                                  ),
                                );
                              }).toList(),
                            )
                          : Row(
                              children: [
                                const Icon(Icons.emoji_emotions_outlined, color: Colors.white54, size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  t('Швидкі реакції вимкнено', 'Quick reactions are disabled'),
                                  style: TextStyle(color: Colors.white.withValues(alpha: 0.62), fontSize: 13),
                                ),
                              ],
                            ),
                    ),
                  ),
                  Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),
                  ListTile(leading: const Icon(Icons.reply, color: Colors.white), title: Text(t('Відповісти', 'Reply'), style: const TextStyle(color: Colors.white)), onTap: () { 
                    Navigator.pop(context); 
                    setState(() => _replyingTo = m); 
                    Future.delayed(const Duration(milliseconds: 100), () {
                     if (mounted) _chatFocusNode.requestFocus(); 
                   });
                  }),
                  if (isMe && m['type'] == 'text') ...[
                    Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),
                    ListTile(leading: const Icon(Icons.edit_outlined, color: Colors.white), title: Text(t('Редагувати', 'Edit'), style: const TextStyle(color: Colors.white)), onTap: () { Navigator.pop(context); setState(() { _editingMessage = m; _replyingTo = null; _c.text = m['text'] ?? ''; _hasText = _c.text.trim().isNotEmpty; }); _chatFocusNode.requestFocus(); }),
                  ],
                  if (m['type'] == 'text') ...[
                    Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),
                    ListTile(leading: const Icon(Icons.forward, color: Colors.white), title: Text(t('Переслати', 'Forward'), style: const TextStyle(color: Colors.white)), onTap: () { Navigator.pop(context); _showForwardDialog(m); }),
                  ],
                  Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),
                  if (isMe) ListTile(leading: const Icon(Icons.delete_outline, color: Color(0xFFFF3B30)), title: Text(t('Видалити', 'Delete'), style: const TextStyle(color: Color(0xFFFF3B30))), onTap: () { Navigator.pop(context); socket.emit('delete_message', {'timestamp': m['timestamp'], 'senderName': m['senderName']}); }),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          );
      },
    );
  }

void _showForwardDialog(Map<String, dynamic> msg) {
    final targetController = TextEditingController();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.8), 
              borderRadius: const BorderRadius.vertical(top: Radius.circular(30))
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
              child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        const Icon(Icons.forward, color: Colors.white, size: 20),
                        const SizedBox(width: 10),
                        Text(t('Переслати повідомлення', 'Forward message'), style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
                      ]),
                      const SizedBox(height: 16),
                      if (widget.friends.isNotEmpty) ...[
                        Text(t('Друзі', 'Friends'), style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.5), fontWeight: FontWeight.bold, letterSpacing: 1)),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 80,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: widget.friends.length,
                            itemBuilder: (context, index) {
                              final f = widget.friends[index];
                              return GestureDetector(
                                onTap: () async {
                                  Navigator.pop(ctx);
                                  final friendKey = f['publicKey'];
                                  if (friendKey == null) return;
                                  final messenger = ScaffoldMessenger.of(context);
                                  final key = await _getSecretKey(friendKey);
                                  final originalText = msg['text'] ?? '';
                                  final box = await _aes.encrypt(utf8.encode(originalText), secretKey: key);
                                  socket.emit('message', {'type': 'text', 'text': originalText, 'ciphertext': base64Encode(box.cipherText), 'nonce': base64Encode(box.nonce), 'mac': base64Encode(box.mac.bytes), 'senderName': widget.userName, 'receiverName': f['userName']});
                                  if (mounted) {
                                    messenger.showSnackBar(SnackBar(
                                      content: Text('${t("Переслано до", "Forwarded to")} ${f['userName']}'),
                                      backgroundColor: const Color(0xFF333333),
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                                    ));
                                  }
                                },
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 16),
                                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                                    SafeAvatar(avatarBase64: f['avatar'], fallbackName: f['userName'], radius: 24),
                                    const SizedBox(height: 4),
                                    Text(f['userName'], style: const TextStyle(color: Colors.white, fontSize: 11)),
                                  ]),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      GlassInput(controller: targetController, hintText: t('Введіть нікнейм...', 'Enter username...')),
                      const SizedBox(height: 12),
                      ShineButton(
                        text: t('Переслати', 'Forward'),
                        onPressed: () async {
                          final target = targetController.text.trim();
                          if (target.isEmpty) return;
                          Navigator.pop(ctx);
                          socket.emitWithAck('get_key', target, ack: (dynamic response) async {
                            if (response['success'] == true) {
                              final targetKey = response['publicKey'];
                              final key = await _getSecretKey(targetKey);
                              final originalText = msg['text'] ?? '';
                              final box = await _aes.encrypt(utf8.encode(originalText), secretKey: key);
                              socket.emit('message', {'type': 'text', 'text': originalText, 'ciphertext': base64Encode(box.cipherText), 'nonce': base64Encode(box.nonce), 'mac': base64Encode(box.mac.bytes), 'senderName': widget.userName, 'receiverName': target});
                            }
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
      },
    );
  }
  
  void _showChatUserProfile() {
    if (widget.partnerPublicKey.startsWith('GROUP_')) {
      return;
    }
    final accent = _accentColors[_accentColor] ?? const Color(0xFFB026FF);
    String? currentBio;
    String? currentAvatar = widget.partnerAvatar;
    String? currentDisplayName = widget.partnerDisplayName;
    bool isVerifiedUser = widget.partnerIsVerified;
    bool fetched = false;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateSB) {
            if (!fetched) {
              fetched = true;
              socket.emitWithAck('get_user_profile', widget.partnerName, ack: (dynamic data) {
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
            final displayName = (currentDisplayName != null && currentDisplayName!.trim().isNotEmpty)
                ? currentDisplayName!.trim()
                : widget.partnerName;
            final bioText = (currentBio ?? '').trim();
            final keyPreview = '${widget.partnerPublicKey.substring(0, widget.partnerPublicKey.length > 24 ? 24 : widget.partnerPublicKey.length)}...';
            final sharedMedia = <String>[];
            for (final m in _messages.reversed) {
              String msgType = (m['type'] ?? 'text').toString().replaceFirst('ephemeral_', '');
              if (msgType != 'image') continue;
              if (m['imageBytes'] != null) {
                sharedMedia.add(base64Encode(m['imageBytes']));
              } else {
                final txt = (m['text'] ?? '').toString();
                if (txt.length > 100 && !txt.startsWith('{')) {
                  sharedMedia.add(txt);
                }
              }
              if (sharedMedia.length >= 8) break;
            }

            final statusText = _isCheckingPresence
                ? t('оновлення...', 'updating...')
                : (_isPartnerOnline ? t('в мережі', 'online') : t('був(ла) нещодавно', 'last seen recently'));
            return Container(
              width: MediaQuery.of(context).size.width,
              decoration: const BoxDecoration(color: Color(0xFF1A1A1A), borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                child: SafeArea(
                  top: false,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
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
                                  SafeAvatar(avatarBase64: currentAvatar, fallbackName: widget.partnerName, radius: 48),
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
                                          style: const TextStyle(color: Colors.white, fontSize: 23, fontWeight: FontWeight.w700),
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
                                    '@${widget.partnerName}',
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
                                      key: ValueKey('$_isCheckingPresence$_isPartnerOnline'),
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        AnimatedContainer(
                                          duration: const Duration(milliseconds: 240),
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            color: _isCheckingPresence
                                                ? Colors.white38
                                                : (_isPartnerOnline ? const Color(0xFF4CC85A) : Colors.white38),
                                            shape: BoxShape.circle,
                                            boxShadow: _isPartnerOnline
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
                                          statusText,
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
                                    title: Text('@${widget.partnerName}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
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
                            const SizedBox(height: 18),
                          ],
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
  }

  Future<Map<String, dynamic>?> _fetchGroupInfo(String groupId) async {
    final c = Completer<Map<String, dynamic>?>();
    socket.emitWithAck(
      'get_group_info',
      {'groupId': groupId, 'userName': widget.userName},
      ack: (dynamic raw) {
        try {
          if (raw is Map<String, dynamic>) {
            c.complete(raw);
            return;
          }
          if (raw is Map) {
            c.complete(Map<String, dynamic>.from(raw));
            return;
          }
          c.complete(null);
        } catch (_) {
          c.complete(null);
        }
      },
    );
    return c.future.timeout(const Duration(seconds: 8), onTimeout: () => null);
  }

  String? _resolveGroupId() {
    if (_currentPartnerKey.startsWith('GROUP_')) return _currentPartnerKey;
    if (widget.partnerPublicKey.startsWith('GROUP_')) return widget.partnerPublicKey;
    if (widget.partnerName.startsWith('GROUP_')) return widget.partnerName;
    return null;
  }

  List<String> _collectGroupMediaPreviews({int limit = 24}) {
    final out = <String>[];
    final seen = <String>{};
    for (final m in _messages.reversed) {
      final type = (m['type'] ?? '').toString();
      if (type != 'image') continue;
      final imageBytes = (m['imageBytes'] ?? '').toString();
      if (imageBytes.isNotEmpty && !seen.contains(imageBytes)) {
        seen.add(imageBytes);
        out.add(imageBytes);
      } else {
        final rawText = (m['text'] ?? '').toString();
        if (rawText.length > 100 && !rawText.startsWith('{') && !seen.contains(rawText)) {
          seen.add(rawText);
          out.add(rawText);
        }
      }
      if (out.length >= limit) break;
    }
    return out;
  }

  Future<bool> _showGroupSettingsSheet({
    String? groupIdOverride,
    Map<String, dynamic>? prefetchedInfo,
  }) async {
    final groupId = groupIdOverride ?? _resolveGroupId();
    if (groupId == null) return false;

    final info = prefetchedInfo ?? await _fetchGroupInfo(groupId);
    if (!mounted) return false;
    if (info == null || info['success'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text((info?['message'] ?? t('Не вдалося завантажити групу', 'Failed to load group')).toString()),
        backgroundColor: Colors.red.shade900,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
      ));
      return false;
    }

    final accent = _accentColors[_accentColor] ?? const Color(0xFFB026FF);
    final nameController = TextEditingController(text: (info['name'] ?? widget.partnerName).toString());
    final descriptionController = TextEditingController(text: (info['description'] ?? '').toString());
    final members = List<Map<String, dynamic>>.from((info['members'] as List?) ?? const []);
    final selectedMembers = members
        .map((m) => (m['userName'] ?? '').toString())
        .where((u) => u.isNotEmpty)
        .toSet();
    selectedMembers.add(widget.userName);

    final displayMap = <String, String>{};
    for (final m in members) {
      final user = (m['userName'] ?? '').toString();
      if (user.isEmpty) continue;
      displayMap[user] = (m['displayName'] ?? '').toString().trim();
    }
    for (final f in widget.friends) {
      final user = (f['userName'] ?? '').toString();
      if (user.isEmpty) continue;
      displayMap.putIfAbsent(user, () => (f['displayName'] ?? '').toString().trim());
    }

    bool isSaving = false;
    bool didUpdate = false;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (sheetCtx, setStateSB) {
            final users = <String>{...selectedMembers, ...widget.friends.map((f) => (f['userName'] ?? '').toString())}
              ..removeWhere((u) => u.isEmpty);
            final sortedUsers = users.toList()..sort();

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
                    bottom: 16 + MediaQuery.of(sheetCtx).viewInsets.bottom,
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
                            child: Icon(Icons.settings_rounded, color: accent),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              t('Налаштування групи', 'Group Settings'),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 19),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      GlassInput(controller: nameController, hintText: t('Назва групи', 'Group Name')),
                      const SizedBox(height: 10),
                      GlassInput(controller: descriptionController, hintText: t('Опис', 'Description')),
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
                            final display = (displayMap[user] ?? '').trim();
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
                              checkColor: _onAccent(accent),
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
                          TextButton(
                            onPressed: isSaving ? null : () => Navigator.pop(sheetCtx),
                            child: Text(t('Скасувати', 'Cancel'), style: const TextStyle(color: Colors.white70)),
                          ),
                          const Spacer(),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: accent,
                              foregroundColor: _onAccent(accent),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            onPressed: isSaving
                                ? null
                                : () {
                                    final nextName = nameController.text.trim();
                                    if (nextName.isEmpty) {
                                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                        content: Text(t('Вкажіть назву групи', 'Enter group name')),
                                        backgroundColor: Colors.red.shade900,
                                        behavior: SnackBarBehavior.floating,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                                      ));
                                      return;
                                    }
                                    if (selectedMembers.length < 2) {
                                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                        content: Text(t('У групі має бути щонайменше 2 учасники', 'Group must have at least 2 members')),
                                        backgroundColor: Colors.red.shade900,
                                        behavior: SnackBarBehavior.floating,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                                      ));
                                      return;
                                    }

                                    setStateSB(() => isSaving = true);
                                    socket.emitWithAck('update_group', {
                                      'groupId': groupId,
                                      'editor': widget.userName,
                                      'name': nextName,
                                      'description': descriptionController.text.trim(),
                                      'participants': selectedMembers.toList(),
                                    }, ack: (dynamic raw) {
                                      final data = raw is Map<String, dynamic>
                                          ? raw
                                          : (raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{});
                                      if (!mounted) return;
                                      if (data['success'] != true) {
                                        setStateSB(() => isSaving = false);
                                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                          content: Text((data['message'] ?? t('Не вдалося оновити групу', 'Failed to update group')).toString()),
                                          backgroundColor: Colors.red.shade900,
                                          behavior: SnackBarBehavior.floating,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                                        ));
                                        return;
                                      }
                                      _safeSetState(() {
                                        _groupNameOverride = nextName;
                                      });
                                      didUpdate = true;
                                      Navigator.pop(sheetCtx);
                                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                        content: Text(t('Групу оновлено', 'Group updated')),
                                        backgroundColor: const Color(0xFF333333),
                                        behavior: SnackBarBehavior.floating,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                                      ));
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
        );
      },
    );
    return didUpdate;
  }

  Future<void> _openGroupInfoPage() async {
    final groupId = _resolveGroupId();
    if (groupId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t('Не вдалося визначити групу', 'Failed to resolve group')),
        backgroundColor: Colors.red.shade900,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
      ));
      return;
    }

    final initialInfo = await _fetchGroupInfo(groupId);
    if (!mounted) return;
    if (initialInfo == null || initialInfo['success'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text((initialInfo?['message'] ?? t('Не вдалося завантажити групу', 'Failed to load group')).toString()),
        backgroundColor: Colors.red.shade900,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
      ));
      return;
    }

    final accent = _accentColors[_accentColor] ?? const Color(0xFFB026FF);
    final mediaPreviews = _collectGroupMediaPreviews();

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (pageCtx) {
          Map<String, dynamic> groupInfo = Map<String, dynamic>.from(initialInfo);

          Future<void> refreshInfo(StateSetter setPageState) async {
            final fresh = await _fetchGroupInfo(groupId);
            if (!mounted || !pageCtx.mounted) return;
            if (fresh != null && fresh['success'] == true) {
              setPageState(() {
                groupInfo = Map<String, dynamic>.from(fresh);
              });
            }
          }

          Widget sectionCard({required String title, required Widget child}) {
            return Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 14),
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
                    title,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.95),
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  child,
                ],
              ),
            );
          }

          return StatefulBuilder(
            builder: (pageCtx, setPageState) {
              final groupName = (groupInfo['name'] ?? widget.partnerName).toString();
              final groupDescription = (groupInfo['description'] ?? '').toString().trim();
              final members = List<Map<String, dynamic>>.from((groupInfo['members'] as List?) ?? const []);

              return Scaffold(
                backgroundColor: const Color(0xFF0F1720),
                appBar: AppBar(
                  backgroundColor: Colors.black.withValues(alpha: 0.35),
                  title: Text(t('Group Info', 'Group Info')),
                  actions: [
                    IconButton(
                      tooltip: t('Редагувати групу', 'Edit group'),
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () async {
                        final updated = await _showGroupSettingsSheet(
                          groupIdOverride: groupId,
                          prefetchedInfo: groupInfo,
                        );
                        if (!updated) return;
                        _safeSetState(() {
                          _groupNameOverride = null;
                        });
                        await refreshInfo(setPageState);
                      },
                    ),
                  ],
                ),
                body: SafeArea(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 14),
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.symmetric(horizontal: 14),
                          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                accent.withValues(alpha: 0.35),
                                const Color(0xFF253341),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                          ),
                          child: Column(
                            children: [
                              SafeAvatar(
                                avatarBase64: widget.partnerAvatar,
                                fallbackName: groupName,
                                radius: 46,
                                isGroup: true,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                groupName,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 23,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${members.length} ${t('учасників', 'members')}',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.76),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (groupDescription.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Text(
                                  groupDescription,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.88),
                                    fontSize: 14,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        sectionCard(
                          title: t('Спільні медіа', 'Shared media'),
                          child: mediaPreviews.isEmpty
                              ? Text(
                                  t('Поки немає медіа', 'No media yet'),
                                  style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                                )
                              : SizedBox(
                                  height: 86,
                                  child: ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: mediaPreviews.length,
                                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                                    itemBuilder: (_, i) {
                                      return ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: Image.memory(
                                          base64Decode(mediaPreviews[i]),
                                          width: 86,
                                          height: 86,
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) => Container(
                                            width: 86,
                                            height: 86,
                                            color: Colors.white10,
                                            child: const Icon(Icons.broken_image_outlined, color: Colors.white54),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                        ),
                        const SizedBox(height: 12),
                        sectionCard(
                          title: t('Учасники', 'Members'),
                          child: ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: members.length,
                            separatorBuilder: (_, _) => Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),
                            itemBuilder: (_, i) {
                              final m = members[i];
                              final user = (m['userName'] ?? '').toString();
                              final display = (m['displayName'] ?? '').toString().trim();
                              final isMe = user == widget.userName;
                              final label = display.isNotEmpty ? display : user;
                              final subtitle = user.isNotEmpty && display.isNotEmpty ? '@$user' : null;

                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                minLeadingWidth: 40,
                                leading: CircleAvatar(
                                  radius: 18,
                                  backgroundColor: accent.withValues(alpha: 0.22),
                                  child: Text(
                                    label.isEmpty ? '?' : label.substring(0, 1).toUpperCase(),
                                    style: TextStyle(color: _onAccent(accent), fontWeight: FontWeight.w700),
                                  ),
                                ),
                                title: Text(
                                  isMe ? '$label (${t('ви', 'you')})' : label,
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: subtitle == null
                                    ? null
                                    : Text(
                                        subtitle,
                                        style: TextStyle(color: Colors.white.withValues(alpha: 0.58), fontSize: 12),
                                      ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1F2B38),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                          ),
                          child: Column(
                            children: [
                              ListTile(
                                leading: Icon(Icons.edit_rounded, color: accent),
                                title: Text(t('Редагувати групу', 'Edit group'), style: const TextStyle(color: Colors.white)),
                                onTap: () async {
                                  final updated = await _showGroupSettingsSheet(
                                    groupIdOverride: groupId,
                                    prefetchedInfo: groupInfo,
                                  );
                                  if (!updated) return;
                                  _safeSetState(() {
                                    _groupNameOverride = null;
                                  });
                                  await refreshInfo(setPageState);
                                },
                              ),
                              Divider(height: 1, indent: 56, color: Colors.white.withValues(alpha: 0.08)),
                              ListTile(
                                leading: const Icon(Icons.logout_rounded, color: Color(0xFFFF5E57)),
                                title: Text(t('Вийти з групи', 'Leave Group'), style: const TextStyle(color: Color(0xFFFF5E57))),
                                onTap: () {
                                  Navigator.pop(pageCtx);
                                  _leaveCurrentGroup();
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _leaveCurrentGroup() {
    final groupId = _resolveGroupId();
    if (groupId == null) return;
    socket.emit('update_chat_settings', {
      'userName': widget.userName,
      'partnerName': groupId,
      'isPinned': false,
      'isHidden': false,
      'isDeleted': true,
      'isBlocked': false,
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(t('Ви вийшли з групи', 'You left the group')),
      backgroundColor: const Color(0xFF333333),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
    ));
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _isTearingDown = true;
    currentActiveChat = null;
    _typingTimer?.cancel();
    _emitTyping(false);
    socket.dispose();
    _scrollController.removeListener(_maybeLoadOlderHistory);
    _scrollController.dispose();
    _recordTimer?.cancel();
    _amplitudeSub?.cancel();
    _chatFocusNode.dispose();
    _searchBarController.dispose();
    super.dispose();
  }

  String _formatTime(String? isoTime) { if (isoTime == null) return ""; try { return DateFormat('HH:mm').format(DateTime.parse(isoTime).toLocal()); } catch (e) { return ""; } }

  Widget _buildImage(dynamic bytesOrString) {
    if (!_autoDownloadMedia) {
      return GestureDetector(
        onTap: () {
          if (mounted) setState(() => _autoDownloadMedia = true);
        },
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.24),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.image_not_supported_rounded, color: Colors.white70, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  t('Торкніться, щоб завантажити медіа', 'Tap to load media'),
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.82), fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final Widget errorWidget = Container(padding: const EdgeInsets.all(12), color: const Color(0xFF222222), child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.broken_image, color: Colors.white70), const SizedBox(width: 8), Text(t("Помилка", "Error"), style: const TextStyle(color: Colors.white70))]));
    if (bytesOrString == null) return errorWidget;
    Uint8List bytes = bytesOrString is Uint8List ? bytesOrString : base64Decode(bytesOrString);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.4,
      ),
      child: Image.memory(
        bytes, 
        fit: BoxFit.contain, 
        gaplessPlayback: true, 
        cacheWidth: 800, 
        errorBuilder: (ctx, err, stack) => errorWidget
      ),
    );
  }

  Widget _buildMessageText(String text, Color baseColor) {
    bool isEmojiOnly(String value) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return false;

      if (RegExp(r'[A-Za-z0-9А-Яа-яІіЇїЄєҐґ]').hasMatch(trimmed)) {
        return false;
      }

      bool isEmojiRune(int rune) {
        if (rune >= 0x1F300 && rune <= 0x1FAFF) return true;
        if (rune >= 0x2600 && rune <= 0x26FF) return true;
        if (rune >= 0x2700 && rune <= 0x27BF) return true;
        return false;
      }

      int emojiUnits = 0;
      for (final rune in trimmed.runes) {
        if (rune == 0x20 || rune == 0x0A || rune == 0x09) continue;
        if (rune == 0xFE0F || rune == 0x200D) continue;
        if (rune >= 0x1F3FB && rune <= 0x1F3FF) continue; 

        if (!isEmojiRune(rune)) return false;
        emojiUnits++;
      }

      return emojiUnits > 0 && emojiUnits <= 6;
    }

    final emojiOnly = _emojiLargeRenderEnabled && isEmojiOnly(text);
    final fontSize = emojiOnly ? (_chatFontSize + 18) : _chatFontSize;
    final textStyle = TextStyle(color: baseColor, fontSize: fontSize, height: emojiOnly ? 1.15 : null);

    Widget wrapAnimated(Widget child) {
      if (!emojiOnly || !_animatedEmojiEnabled) return child;
      return TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.97, end: 1.03),
        duration: const Duration(milliseconds: 1200),
        curve: Curves.easeInOut,
        builder: (context, scale, inner) {
          return Transform.scale(scale: scale, child: inner);
        },
        child: child,
      );
    }

    final urlRegExp = RegExp(r'(https?:\/\/[^\s]+)');
    final matches = urlRegExp.allMatches(text);

    if (matches.isEmpty) {
      final child = _isSearchMode && _searchQuery.isNotEmpty
          ? HighlightedText(text: "$text   ", query: _searchQuery, baseStyle: textStyle)
          : Text("$text   ", style: textStyle);
      return wrapAnimated(child);
    }

    List<TextSpan> spans = [];
    int lastMatchEnd = 0;
    for (var match in matches) {
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(text: text.substring(lastMatchEnd, match.start)));
      }
      final url = match.group(0)!;
      spans.add(TextSpan(text: url, style: const TextStyle(color: Color(0xFF00C7FF), decoration: TextDecoration.underline), recognizer: TapGestureRecognizer()..onTap = () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)));
      lastMatchEnd = match.end;
    }
    if (lastMatchEnd < text.length) {
      spans.add(TextSpan(text: "${text.substring(lastMatchEnd)}   "));
    } else {
      spans.add(const TextSpan(text: "   "));
    }

    return wrapAnimated(RichText(text: TextSpan(style: textStyle, children: spans)));
  }

  @override
  Widget build(BuildContext context) {
    final isGroupChat = _currentPartnerKey.startsWith('GROUP_');
    final isSelf = widget.partnerName == widget.userName;
    final isDesktopPlatform = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    final partnerNameLabel = (widget.partnerDisplayName != null && widget.partnerDisplayName!.trim().isNotEmpty)
        ? widget.partnerDisplayName!.trim()
        : widget.partnerName;
    final effectiveTitle = isGroupChat
      ? ((_groupNameOverride != null && _groupNameOverride!.trim().isNotEmpty) ? _groupNameOverride!.trim() : partnerNameLabel)
      : partnerNameLabel;
    final accent = _accentColors[_accentColor] ?? const Color(0xFFB026FF);
    final onAccent = ThemeData.estimateBrightnessForColor(accent) == Brightness.dark ? Colors.white : Colors.black;
    final messageListSidePadding = _compactMode ? 8.0 : 12.0;
    final messageListTopPadding = _compactMode ? 10.0 : 20.0;
    final messageListBottomPadding = _compactMode ? (_isPartnerTyping ? 48.0 : 12.0) : (_isPartnerTyping ? 60.0 : 20.0);
    final bubbleHorizontalPadding = _compactMode ? 10.0 : 14.0;
    final bubbleVerticalPadding = _compactMode ? 7.0 : 10.0;
    final bubbleBottomMargin = _compactMode ? 1.0 : 2.0;
    final bubbleRadiusScale = _compactMode ? 0.86 : 1.0;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        leading: _isSearchMode
          ? IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              tooltip: t('Закрити пошук', 'Close search'),
              onPressed: _closeSearch,
            )
          : IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
              tooltip: t('Назад', 'Back'),
              onPressed: () => Navigator.pop(context),
            ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1A1A1A),
            border: Border(bottom: BorderSide(color: Color(0xFF2A2A2A), width: 1)),
          ),
        ),
        title: _isSearchMode
          ? TextField(controller: _searchBarController, autofocus: true, style: const TextStyle(color: Colors.white, fontSize: 16), decoration: InputDecoration(hintText: t('Пошук у чаті...', 'Search in chat...'), hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)), border: InputBorder.none), onChanged: (q) { setState(() { _searchQuery = q; _updateSearchResults(); }); })
          : GestureDetector(
              onTap: () { if (!isSelf && !isGroupChat) { _showChatUserProfile(); } },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  isSelf ? CircleAvatar(radius: 16, backgroundColor: Colors.white.withValues(alpha: 0.1), child: const Icon(Icons.bookmark, color: Colors.white70, size: 16)) : SafeAvatar(avatarBase64: widget.partnerAvatar, fallbackName: widget.partnerName, radius: 16, isGroup: isGroupChat),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(mainAxisSize: MainAxisSize.min, children: [
                          Text(isSelf ? t("Нотатник", "Saved Messages") : effectiveTitle, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                          if (widget.partnerIsVerified && !isGroupChat && !isSelf) ...[const SizedBox(width: 5), VerifiedBadge(size: 15, color: accent)],
                      ]),
                      if (!isSelf) ...[
                        if (_isPartnerTyping) Row(mainAxisSize: MainAxisSize.min, children: [Text(t("друкує ", "typing "), style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11)), const TypingIndicator(color: Colors.white70, size: 3)])
                        else if (isGroupChat) Text(t("Груповий чат", "Group Chat"), style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11))
                        else if (_isCheckingPresence) Text(t("оновлення...", "updating..."), style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11))
                        else if (_isPartnerOnline) Text(t("в мережі", "online"), style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11))
                        else Text(t("не в мережі", "offline"), style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
        actions: _isSearchMode
          ? [
              if (_searchMatchIndices.isNotEmpty) Center(child: Text('${_currentSearchIdx + 1}/${_searchMatchIndices.length}', style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13))),
              IconButton(icon: const Icon(Icons.keyboard_arrow_up, color: Colors.white), tooltip: t('Попередній збіг', 'Previous match'), onPressed: _prevMatch),
              IconButton(icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white), tooltip: t('Наступний збіг', 'Next match'), onPressed: _nextMatch),
            ]
          : [
              if (!isSelf) IconButton(icon: const Icon(Icons.search, color: Colors.white), tooltip: t('Пошук', 'Search'), onPressed: () { setState(() { _isSearchMode = true; }); }),
              if (!isSelf) IconButton(icon: Icon(_isAetherMode ? Icons.local_fire_department : Icons.local_fire_department_outlined, color: _isAetherMode ? accent : Colors.white), tooltip: t('Режим Aether', 'Aether mode'), onPressed: () => setState(() { _isAetherMode = !_isAetherMode; _replyingTo = null; })),
              if (isGroupChat)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.white),
                  color: const Color(0xFF202A35),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  onSelected: (value) {
                    if (value == 'group_settings') {
                      _openGroupInfoPage();
                      return;
                    }
                    if (value == 'leave_group') {
                      _leaveCurrentGroup();
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem<String>(
                      value: 'group_settings',
                      child: Row(
                        children: [
                          const Icon(Icons.settings_rounded, color: Colors.white70, size: 18),
                          const SizedBox(width: 10),
                          Text(t('Group Info', 'Group Info'), style: const TextStyle(color: Colors.white)),
                        ],
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'leave_group',
                      child: Row(
                        children: [
                          const Icon(Icons.logout_rounded, color: Color(0xFFFF5E57), size: 18),
                          const SizedBox(width: 10),
                          Text(t('Вийти з групи', 'Leave Group'), style: const TextStyle(color: Color(0xFFFF5E57))),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
      ),
      body: Shortcuts(
        shortcuts: isDesktopPlatform
            ? const <ShortcutActivator, Intent>{
                SingleActivator(LogicalKeyboardKey.keyF, control: true): _ToggleSearchIntent(),
                SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
              }
            : const <ShortcutActivator, Intent>{},
        child: Actions(
          actions: <Type, Action<Intent>>{
            _ToggleSearchIntent: CallbackAction<_ToggleSearchIntent>(
              onInvoke: (intent) {
                if (isSelf) return null;
                if (_isSearchMode) {
                  _closeSearch();
                } else {
                  _safeSetState(() => _isSearchMode = true);
                }
                return null;
              },
            ),
            DismissIntent: CallbackAction<DismissIntent>(
              onInvoke: (intent) {
                if (_isSearchMode) _closeSearch();
                return null;
              },
            ),
          },
          child: Focus(
            autofocus: true,
            child: SafeArea(
              child: LiquidBackground(
                child: Column(
                  children: [
                    Expanded(
                      child: _isLoadingHistory
                        ? const Center(child: CircularProgressIndicator(color: Colors.white54))
                        : Stack(
                            children: [
                              ListView.builder(
                                controller: _scrollController,
                                padding: EdgeInsets.only(
                                  left: messageListSidePadding,
                                  right: messageListSidePadding,
                                  top: messageListTopPadding,
                                  bottom: messageListBottomPadding,
                                ),
                                itemCount: _messages.length,
                                itemBuilder: (context, i) {
                                  final m = _messages[i];

                                  if (m['isSystem'] == true) {
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
                                      child: Text(
                                        m['text'] ?? '',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: Colors.white.withValues(alpha: 0.4),
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          height: 1.5,
                                        ),
                                      ),
                                    );
                                  }
                                  final isMe = m['senderName'] == widget.userName;
                                  final timeStr = _formatTime(m['timestamp']);
                                  final isImage = m['type'] == 'image';
                                  final isAudio = m['type'] == 'audio';
                                  final hasReply = m['replyTo'] != null;
                                  final isEdited = m['isEdited'] == 1;
                                  final isMsgEphemeral = m['isEphemeral'] == true;
                                  final isListened = m['isListened'] == true;
                                  final ephemeralDuration = m['ephemeralDuration'] as int? ?? 5;
                                  final msgKey = '${m['timestamp']}_${m['senderName']}';
                                  final msgReactions = Map<String, List<String>>.from(_reactions[msgKey] ?? {});
                                  final isSearchMatch = _isSearchMode && _searchMatchIndices.isNotEmpty && _searchMatchIndices[_currentSearchIdx] == i;
                                  final bubbleColor = isSearchMatch
                                    ? const Color(0xFF6B5B00)
                                    : (isMsgEphemeral
                                      ? const Color(0xFF4A1073)
                                      : (isMe ? const Color(0xFF111111) : accent.withValues(alpha: 0.92)));
                                  final bubbleBorderColor = isSearchMatch
                                    ? const Color(0xFFFFD700).withValues(alpha: 0.55)
                                    : (isMsgEphemeral
                                      ? accent.withValues(alpha: 0.55)
                                      : (isMe
                                        ? Colors.white.withValues(alpha: 0.18)
                                        : onAccent.withValues(alpha: 0.26)));
                                  final messageTextColor = isMsgEphemeral
                                    ? const Color(0xFFE5B3FF)
                                    : (isMe ? Colors.white : onAccent);

                                  bool hasValidImage = m['imageBytes'] != null || (m['text'] != null && m['text'].toString().length > 100);
                                  bool hasCaption = m['text'] != null && m['text'].toString().isNotEmpty && m['text'].toString().length < 1000;

                                  Widget bubble = RepaintBoundary(
                                    child: Container(
                                      margin: EdgeInsets.only(bottom: bubbleBottomMargin),
                                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                                      padding: EdgeInsets.only(
                                        left: isImage || isAudio ? 4 : bubbleHorizontalPadding,
                                        right: isImage || isAudio ? 4 : bubbleHorizontalPadding,
                                        top: isImage ? 4 : bubbleVerticalPadding,
                                        bottom: isImage ? 4 : bubbleVerticalPadding,
                                      ),
                                      decoration: BoxDecoration(
                                        color: bubbleColor,
                                        border: Border.all(color: bubbleBorderColor, width: 0.9),
                                        borderRadius: _scaledBubbleRadius(isMe, bubbleRadiusScale),
                                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 2, offset: const Offset(0, 1))],
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start, 
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (isGroupChat && !isMe) ...[
                                            Padding(padding: const EdgeInsets.only(bottom: 2, left: 2), child: Text(m['senderName'] ?? 'Unknown', style: TextStyle(fontSize: 12, color: isMsgEphemeral ? const Color(0xFFE5B3FF) : messageTextColor, fontWeight: FontWeight.w600))),
                                          ],
                                          if (hasReply) ...[
                                            if (_isLoadingMoreHistory)
                                              Positioned(
                                                top: 8,
                                                left: 0,
                                                right: 0,
                                                child: Center(
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                    decoration: BoxDecoration(
                                                      color: Colors.black.withValues(alpha: 0.35),
                                                      borderRadius: BorderRadius.circular(999),
                                                      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                                                    ),
                                                    child: const SizedBox(
                                                      width: 18,
                                                      height: 18,
                                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            Container(
                                              margin: const EdgeInsets.only(bottom: 6), width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
                                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                                Text(m['replyTo']['senderName']?.toString() ?? 'Unknown', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
                                                const SizedBox(height: 2),
                                                Text(m['replyTo']['text']?.toString() ?? t('Повідомлення', 'Message'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.7))),
                                              ]),
                                            ),
                                          ],
                                          if (isAudio) ...[
                                            AudioMessagePlayer(
                                              key: ValueKey('audio_${m['timestamp']}_${m['senderName']}'),
                                              base64Audio: m['text'] ?? '', isMe: isMe, isEphemeral: isMsgEphemeral, showUnreadDot: !isMe && !isListened,
                                              themeColor: accent,
                                              onPlay: () async {
                                                if (!isMe && !isListened) { setState(() { m['isListened'] = true; }); final prefs = await SharedPreferences.getInstance(); await prefs.setBool('listened_${m['timestamp']}', true); }
                                              },
                                            ),
                                            const SizedBox(height: 2),
                                            _buildTimeAndStatus(isEdited, isMsgEphemeral, timeStr, isMe, m['status'], accent, messageTextColor),
                                          ] else if (isImage && hasValidImage) ...[
                                            ClipRRect(borderRadius: BorderRadius.circular(14), child: _buildImage(m['imageBytes'] ?? m['text'])),
                                            if (hasCaption) ...[
                                              const SizedBox(height: 6),
                                              _buildMessageText(m['text'].toString(), messageTextColor),
                                            ],
                                            const SizedBox(height: 4),
                                            _buildTimeAndStatus(isEdited, isMsgEphemeral, timeStr, isMe, m['status'], accent, messageTextColor),
                                          ] else ...[
                                            Wrap(alignment: WrapAlignment.end, crossAxisAlignment: WrapCrossAlignment.end, children: [
                                              _buildMessageText(m['text'] ?? '', messageTextColor),
                                              _buildTimeAndStatus(isEdited, isMsgEphemeral, timeStr, isMe, m['status'], accent, messageTextColor),
                                            ]),
                                          ]
                                        ],
                                      ),
                                    )
                                  );

                                  return SwipeToReplyWrapper(
                                    messageKey: ValueKey('${m['timestamp']}${m['senderName']}'),
                                    onSwipe: () { setState(() { _replyingTo = m; _editingMessage = null; _hasText = _c.text.trim().isNotEmpty; }); _chatFocusNode.requestFocus(); },
                                    child: Align(
                                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                                      child: Column(
                                        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                        children: [
                                          GestureDetector(
                                            onLongPress: () => _showMessageOptions(m, isMe),
                                            child: HoldToRevealWrapper(
                                              isEphemeral: isMsgEphemeral,
                                              durationSeconds: ephemeralDuration,
                                              onRevealStarted: () { 
                                                Timer(Duration(seconds: ephemeralDuration), () { 
                                                  if (mounted) {
                                                    socket.emit('delete_message', {'timestamp': m['timestamp'], 'senderName': m['senderName']}); 
                                                  }
                                                }); 
                                              },
                                              child: bubble,
                                            ),
                                          ),
                                          if (msgReactions.isNotEmpty) ...[
                                            Padding(padding: EdgeInsets.only(top: 3, bottom: 4, left: isMe ? 0 : 8, right: isMe ? 8 : 0), child: ReactionsBar(reactions: msgReactions, myName: widget.userName, onToggle: (emoji) => _toggleReaction(m, emoji)))
                                          ] else ...[
                                            const SizedBox(height: 4),
                                          ],
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                              Align(
                                alignment: Alignment.bottomLeft,
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  height: _isPartnerTyping ? 56.0 : 0.0,
                                  curve: Curves.easeOut,
                                  child: SingleChildScrollView(
                                    physics: const NeverScrollableScrollPhysics(),
                                    child: Padding(
                                      padding: const EdgeInsets.only(left: 12, bottom: 8, top: 4), 
                                      child: Container(
                                        decoration: BoxDecoration(color: const Color(0xFF2A2A2A), borderRadius: BorderRadius.circular(12)), 
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), 
                                        child: const TypingIndicator(color: Colors.white, size: 6)
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                    ),
                    if (_replyingTo != null && !_isAetherMode) _buildReplyBar(),
                    if (_editingMessage != null) _buildEditingBar(),
                    _buildInputBar(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTimeAndStatus(
    bool isEdited,
    bool isMsgEphemeral,
    String timeStr,
    bool isMe,
    String? status,
    Color accent,
    Color baseTextColor,
  ) {
    final metaColor = isMsgEphemeral
        ? accent.withValues(alpha: 0.95)
        : baseTextColor.withValues(alpha: 0.65);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isEdited) ...[
          Text(t("змінено ", "edited "), style: TextStyle(color: metaColor, fontSize: 10, fontStyle: FontStyle.italic)),
        ],
        Text(timeStr, style: TextStyle(color: metaColor, fontSize: 10)),
        if (isMe && !isMsgEphemeral) ...[
          const SizedBox(width: 4), 
          Icon(Icons.done_all, size: 14, color: status == 'read' ? accent : Colors.white.withValues(alpha: 0.95)),
        ],
        if (isMsgEphemeral) ...[
          Padding(padding: const EdgeInsets.only(left: 4), child: Icon(Icons.local_fire_department, color: accent, size: 12)),
          const SizedBox(width: 4),
          Text(t("видалиться", "self-destruct"), style: TextStyle(color: accent, fontSize: 9, fontStyle: FontStyle.italic)),
        ],
      ],
    );
  }

  Widget _buildReplyBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.1)))),
      child: Row(children: [
        const Icon(Icons.reply, color: Colors.white, size: 20), const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${t("Відповідь", "Reply to")} ${_replyingTo!['senderName'] ?? 'Unknown'}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Colors.white)),
          const SizedBox(height: 2),
          Text(_replyingTo!['type'] == 'image' ? t('Фото', 'Image') : (_replyingTo!['type'] == 'audio' ? t('Голосове повідомлення', 'Voice message') : (_replyingTo!['text']?.toString() ?? t('Повідомлення', 'Message'))), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.5))),
        ])),
        IconButton(icon: Icon(Icons.close_rounded, size: 20, color: Colors.white.withValues(alpha: 0.5)), onPressed: () => setState(() => _replyingTo = null)),
      ]),
    );
  }

  Widget _buildEditingBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.1)))),
      child: Row(children: [
        const Icon(Icons.edit, color: Colors.white, size: 18), const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t('Редагування повідомлення', 'Edit message'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Colors.white)),
          const SizedBox(height: 2),
          Text(_editingMessage!['text']?.toString() ?? t('Повідомлення', 'Message'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.5))),
        ])),
        IconButton(icon: Icon(Icons.close_rounded, size: 20, color: Colors.white.withValues(alpha: 0.5)), onPressed: () { _c.clear(); setState(() { _editingMessage = null; _hasText = false; }); }),
      ]),
    );
  }

  Widget _buildInputBar() {
    final isEditingMode = _editingMessage != null;
    final accent = _accentColors[_accentColor] ?? const Color(0xFFB026FF);
    final onAccent = ThemeData.estimateBrightnessForColor(accent) == Brightness.dark ? Colors.white : Colors.black;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
      decoration: BoxDecoration(color: const Color(0xFF1A1A1A), border: Border(top: BorderSide(color: _isAetherMode ? accent.withValues(alpha: 0.5) : const Color(0xFF2A2A2A), width: 1))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        if (!isEditingMode && !_isRecordingAudio) ...[
          Tooltip(
            message: t('Вкладення', 'Attachments'),
            waitDuration: const Duration(milliseconds: 250),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _showAttachmentMenu,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(50),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                  ),
                  child: Icon(Icons.add_rounded, color: _isAetherMode ? accent : Colors.white, size: 22),
                ),
              ),
            ),
          ),
        ],

        if (!_isRecordingAudio) const SizedBox(width: 8),
        Expanded(
          child: _isRecordingAudio
            ? Container(
                height: 40, padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(color: const Color(0xFFFF3B30).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFFF3B30).withValues(alpha: 0.3))),
                child: Row(children: [
                  const Icon(Icons.fiber_manual_record, color: Color(0xFFFF3B30), size: 16), const SizedBox(width: 8),
                  Text('${(_recordDuration ~/ 60).toString().padLeft(2, '0')}:${(_recordDuration % 60).toString().padLeft(2, '0')}', style: const TextStyle(color: Color(0xFFFF3B30), fontWeight: FontWeight.bold)),
                  const SizedBox(width: 12),
                  Expanded(child: CustomPaint(size: const Size(double.infinity, 20), painter: WaveformPainter(amplitudes: _recordAmplitudes, progress: 1.0, activeColor: const Color(0xFFFF3B30), inactiveColor: const Color(0xFFFF3B30)))),
                ]),
              )
            : Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: _isAetherMode ? null : const LinearGradient(
                    colors: [Color(0xFFB026FF), Color(0xFF00C7FF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  color: _isAetherMode ? accent.withValues(alpha: 0.15) : null,
                ),
                padding: _isAetherMode ? null : const EdgeInsets.all(1.5),
                child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(color: _isAetherMode ? Colors.transparent : const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(19), border: _isAetherMode ? Border.all(color: accent) : null),
                child: Focus(
                  onKeyEvent: (node, event) {
                    final isDesktopPlatform = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
                    if (!isDesktopPlatform) return KeyEventResult.ignored;
                    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.enter) {
                      if (HardwareKeyboard.instance.isShiftPressed) {
                        return KeyEventResult.ignored;
                      }
                      _send();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: TextField(
                    controller: _c, focusNode: _chatFocusNode, minLines: 1, maxLines: 4, onChanged: _onTextChanged, autocorrect: false, enableSuggestions: false, keyboardAppearance: Brightness.dark,
                    style: TextStyle(color: _isAetherMode ? accent : Colors.white, fontSize: _chatFontSize),
                    decoration: InputDecoration(
                      hintText: isEditingMode ? t("Змінити...", "Edit...") : (_isAetherMode ? t("Секретне повідомлення...", "Secret message...") : t("Повідомлення...", "Message...")),
                      hintStyle: TextStyle(color: _isAetherMode ? accent.withValues(alpha: 0.55) : Colors.white.withValues(alpha: 0.4), fontSize: _chatFontSize),
                      border: InputBorder.none, isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                    ),
                  ),
                ),
              ),
            ),
        ),
        const SizedBox(width: 8),
        (_hasText || isEditingMode)
          ? Tooltip(
              message: isEditingMode ? t('Зберегти зміни', 'Save changes') : t('Надіслати', 'Send'),
              waitDuration: const Duration(milliseconds: 250),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _send,
                  onLongPress: (!isEditingMode && !_isAetherMode) ? _showScheduleDialog : null,
                  child: Container(
                    height: 40, width: 40,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(50),
                      gradient: _isAetherMode ? null : const LinearGradient(
                        colors: [Color(0xFFB026FF), Color(0xFF00C7FF)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      color: _isAetherMode ? accent : null,
                    ),
                    child: Icon(isEditingMode ? Icons.check : Icons.arrow_upward, color: Colors.white, size: 20),
                  ),
                ),
              ),
            )
          : Tooltip(
              message: t('Голосове повідомлення', 'Voice message'),
              waitDuration: const Duration(milliseconds: 250),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onLongPressStart: (_) => _startRecording(),
                  onLongPressEnd: (_) => _stopRecording(),
                  onLongPressCancel: () => _cancelRecording(),
                  child: Container(
                    height: 40, width: 40,
                    decoration: BoxDecoration(color: _isRecordingAudio ? const Color(0xFFFF3B30) : Colors.white.withValues(alpha: 0.1), border: Border.all(color: _isRecordingAudio ? const Color(0xFFFF3B30) : Colors.transparent), borderRadius: BorderRadius.circular(50)),
                    child: Icon(_isRecordingAudio ? Icons.mic : Icons.mic_none, color: _isRecordingAudio ? Colors.white : (_isAetherMode ? accent : Colors.white), size: 20),
                  ),
                ),
              ),
            ),
      ]),
    );
  }
}