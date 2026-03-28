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

class ChatScreen extends StatefulWidget {
  final String deviceId, userName, myPublicKey, partnerName, partnerPublicKey;
  final String? partnerAvatar;
  final bool partnerIsVerified;
  final List<Map<String, dynamic>> friends;

  const ChatScreen({
    super.key, required this.deviceId, required this.userName,
    required this.myPublicKey, required this.partnerName,
    required this.partnerPublicKey, this.partnerAvatar,
    this.partnerIsVerified = false,
    this.friends = const [],
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
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
  bool _isAetherMode = false;
  bool _isSearchMode = false;
  
  int _ephemeralDuration = 5;

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

  StreamSubscription<Amplitude>? _amplitudeSub;
  List<double> _recordAmplitudes = [];
  int _recordDuration = 0;
  Timer? _recordTimer;

  @override
  void initState() {
    super.initState();
    _currentPartnerKey = widget.partnerPublicKey;
    currentActiveChat = widget.partnerPublicKey.startsWith('GROUP_') ? widget.partnerPublicKey : widget.partnerName;
    _connect();
  }

  void _cycleEphemeralDuration() {
    setState(() {
      if (_ephemeralDuration == 5) {
        _ephemeralDuration = 10;
      } else if (_ephemeralDuration == 10) {
        _ephemeralDuration = 30;
      } else if (_ephemeralDuration == 30) {
        _ephemeralDuration = 60;
      } else {
        _ephemeralDuration = 5;
      }
    });
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
      if (await _audioRecorder.hasPermission()) {
        final dir = await getApplicationDocumentsDirectory();
        final path = '${dir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _audioRecorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000, sampleRate: 44100), 
          path: path
        );
        setState(() { 
          _isRecordingAudio = true; 
          _recordDuration = 0; 
          _recordAmplitudes = List.generate(30, (_) => 2.0); 
        });
        _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) { if (mounted) setState(() => _recordDuration++); });
        _amplitudeSub = _audioRecorder.onAmplitudeChanged(const Duration(milliseconds: 50)).listen((amp) {
          if (mounted) {
            setState(() {
              double height = (amp.current + 50).clamp(0.0, 50.0) / 50.0 * 28.0;
              List<double> newAmps = List.from(_recordAmplitudes);
              newAmps.add(max(2.0, height));
              if (newAmps.length > 30) {
                newAmps.removeAt(0);
              }
              _recordAmplitudes = newAmps;
            });
          }
        });
      }
    } catch (e) { debugPrint("Recording error: $e"); }
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

  void _connect() {
    socket = io.io('https://aether-backend-hrmq.onrender.com', {'transports': ['websocket'], 'forceNew': true});
    socket.connect();
    socket.onConnect((_) {
      socket.emit('set_active', widget.userName);
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
      
      String historyPartner = widget.partnerPublicKey.startsWith('GROUP_') ? widget.partnerPublicKey : widget.partnerName;
      socket.emitWithAck('get_direct_history', {'me': widget.userName, 'partner': historyPartner}, ack: (dynamic data) async {
        List<Map<String, dynamic>> temp = [];
        bool hasEncryptedOldMessages = false;

        for (var m in (data as List)) {
          var msgMap = Map<String, dynamic>.from(m);
          await _processMessage(msgMap);
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
          setState(() { _messages.clear(); _messages.addAll(temp); _isLoadingHistory = false; });
          socket.emit('mark_read', {'chatId': historyPartner, 'readerName': widget.userName});
          Future.delayed(const Duration(milliseconds: 100), () {
            if (_scrollController.hasClients && mounted) {
              _scrollController.animateTo(_scrollController.position.maxScrollExtent + 100, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
            }
          });
        }
      });
    });

    socket.onDisconnect((_) { if (mounted) setState(() => _isPartnerOnline = false); });
    socket.onReconnect((_) {
      socket.emit('set_active', widget.userName);
      if (!widget.partnerPublicKey.startsWith('GROUP_')) {
        socket.emitWithAck('check_presence', widget.partnerName, ack: (dynamic data) { 
          if (mounted) {
            setState(() => _isPartnerOnline = data['isOnline']); 
          }
        });
      }
      String historyPartner = widget.partnerPublicKey.startsWith('GROUP_') ? widget.partnerPublicKey : widget.partnerName;
      socket.emit('get_direct_history', {'me': widget.userName, 'partner': historyPartner});
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
          Future.delayed(const Duration(milliseconds: 100), () {
            if (_scrollController.hasClients && mounted) {
              _scrollController.animateTo(_scrollController.position.maxScrollExtent + 100, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
            }
          });
          if (msg['senderName'] != widget.userName && msg['isEphemeral'] != true) {
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
    socket.emit('typing', {'senderName': widget.userName, 'receiverName': widget.partnerName, 'isTyping': true});
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(milliseconds: 1500), () { 
      socket.emit('typing', {'senderName': widget.userName, 'receiverName': widget.partnerName, 'isTyping': false}); 
    });
  }

  void _send({String? textOverride, String type = 'text'}) async {
    final text = textOverride ?? _c.text.trim();
    if (text.isEmpty && type == 'text') return;
    final isEditingMode = _editingMessage != null;
    if (type == 'text' && !isEditingMode) { _c.clear(); setState(() { _hasText = false; }); }
    final replyData = _replyingTo != null ? {'senderName': _replyingTo!['senderName'] ?? 'Unknown', 'text': _replyingTo!['type'] == 'image' ? t('Фото', 'Image') : (_replyingTo!['type'] == 'audio' ? t('Голосове повідомлення', 'Voice message') : (_replyingTo!['text']?.toString() ?? t('Повідомлення', 'Message')))} : null;
    setState(() { _replyingTo = null; });
    socket.emit('typing', {'senderName': widget.userName, 'receiverName': widget.partnerName, 'isTyping': false});
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
    final date = await showDatePicker(context: context, initialDate: now.add(const Duration(hours: 1)), firstDate: now, lastDate: now.add(const Duration(days: 365)), builder: (ctx, child) => Theme(data: ThemeData.dark().copyWith(colorScheme: const ColorScheme.dark(primary: Color(0xFFB026FF), surface: Color(0xFF1E1E2C))), child: child!));
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))), builder: (ctx, child) => Theme(data: ThemeData.dark().copyWith(colorScheme: const ColorScheme.dark(primary: Color(0xFFB026FF), surface: Color(0xFF1E1E2C))), child: child!));
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
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.9), borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
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
                      _attachmentIcon(Icons.photo_library, t("Галерея", "Gallery"), () { Navigator.pop(ctx); _pickAndSendImage(ImageSource.gallery); }),
                      _attachmentIcon(Icons.camera_alt, t("Камера", "Camera"), () { Navigator.pop(ctx); _pickAndSendImage(ImageSource.camera); }),
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
        ),
      ),
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

  Future<void> _pickAndSendImage(ImageSource source) async {
    final XFile? image = await _picker.pickImage(source: source, maxWidth: 800, maxHeight: 800, imageQuality: 50);
    if (image == null || !mounted) return;

    final bytes = await image.readAsBytes();
    final base64Image = base64Encode(bytes);
    final captionController = TextEditingController();
    
    if (!mounted) return;
    
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: GlassContainer(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.memory(bytes, height: 250, fit: BoxFit.contain)),
                const SizedBox(height: 16),
                GlassInput(controller: captionController, hintText: t("Додати підпис...", "Add a caption...")),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t("Скасувати", "Cancel"), style: const TextStyle(color: Colors.white54))),
                    const SizedBox(width: 8),
                    ShineButton(
                      text: t("Відправити", "Send"),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _sendWithImage(captionController.text.trim(), base64Image);
                      },
                    ),
                  ],
                )
              ],
            ),
          ),
        ),
      )
    );
  }

  void _sendWithImage(String caption, String base64Image) async {
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
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        width: double.infinity,
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.7), borderRadius: const BorderRadius.vertical(top: Radius.circular(30))),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withValues(alpha: 0.12))),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: ['❤️', '😂', '🔥', '👍', '😮', '🎉', '🤯', '😢'].map((emoji) {
                        final msgKey = '${m['timestamp']}_${m['senderName']}';
                        final isMine = _reactions[msgKey]?[emoji]?.contains(widget.userName) ?? false;
                        return GestureDetector(
                          onTap: () { Navigator.pop(context); _toggleReaction(m, emoji); },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(color: isMine ? const Color(0xFFB026FF).withValues(alpha: 0.3) : Colors.transparent, borderRadius: BorderRadius.circular(12)),
                            child: Text(emoji, style: const TextStyle(fontSize: 26)),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),
                ListTile(leading: const Icon(Icons.reply, color: Colors.white), title: Text(t('Відповісти', 'Reply'), style: const TextStyle(color: Colors.white)), onTap: () { Navigator.pop(context); setState(() => _replyingTo = m); _chatFocusNode.requestFocus(); }),
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
        ),
      ),
    );
  }

void _showForwardDialog(Map<String, dynamic> msg) {
    final targetController = TextEditingController();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.8), 
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30))
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
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
                                final key = await _getSecretKey(friendKey);
                                final originalText = msg['text'] ?? '';
                                final box = await _aes.encrypt(utf8.encode(originalText), secretKey: key);
                                socket.emit('message', {'type': 'text', 'text': originalText, 'ciphertext': base64Encode(box.cipherText), 'nonce': base64Encode(box.nonce), 'mac': base64Encode(box.mac.bytes), 'senderName': widget.userName, 'receiverName': f['userName']});
                                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${t("Переслано до", "Forwarded to")} ${f['userName']}'), backgroundColor: const Color(0xFF333333), behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50))));
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
        ),
      ),
    );
  }
  
  void _showChatUserProfile() {
    if (widget.partnerPublicKey.startsWith('GROUP_')) {
      return;
    }
    String? currentBio;
    String? currentAvatar = widget.partnerAvatar;
    bool isVerifiedUser = widget.partnerIsVerified;
    bool fetched = false;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      builder: (context) => StatefulBuilder(
        builder: (context, setStateSB) {
          if (!fetched) {
            fetched = true;
            socket.emitWithAck('get_user_profile', widget.partnerName, ack: (dynamic data) {
              if (data['success'] == true) {
                setStateSB(() { currentBio = data['bio']; currentAvatar = data['avatar'] ?? currentAvatar; isVerifiedUser = data['isVerified'] == true; });
              }
            });
          }
          return Container(
            width: MediaQuery.of(context).size.width,
            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: const BorderRadius.vertical(top: Radius.circular(30))),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SafeAvatar(avatarBase64: currentAvatar, fallbackName: widget.partnerName, radius: 56),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(widget.partnerName, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: -0.5)),
                          if (isVerifiedUser) ...[const SizedBox(width: 8), const VerifiedBadge(size: 22)],
                        ],
                      ),
                      if (currentBio != null && currentBio!.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(currentBio!, textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 15)),
                      ],
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    currentActiveChat = null;
    _typingTimer?.cancel();
    socket.dispose();
    _scrollController.dispose();
    _recordTimer?.cancel();
    _amplitudeSub?.cancel();
    _chatFocusNode.dispose();
    _searchBarController.dispose();
    super.dispose();
  }

  String _formatTime(String? isoTime) { if (isoTime == null) return ""; try { return DateFormat('HH:mm').format(DateTime.parse(isoTime).toLocal()); } catch (e) { return ""; } }

  Widget _buildImage(dynamic bytesOrString) {
    final Widget errorWidget = Container(padding: const EdgeInsets.all(12), color: const Color(0xFF222222), child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.broken_image, color: Colors.white70), const SizedBox(width: 8), Text(t("Помилка", "Error"), style: const TextStyle(color: Colors.white70))]));
    if (bytesOrString == null) return errorWidget;
    Uint8List bytes = bytesOrString is Uint8List ? bytesOrString : base64Decode(bytesOrString);
    return Image.memory(
      bytes, fit: BoxFit.cover, gaplessPlayback: true, cacheWidth: 400,
      errorBuilder: (ctx, err, stack) => errorWidget
    );
  }

  Widget _buildMessageText(String text, bool isEphemeral) {
    final urlRegExp = RegExp(r'(https?:\/\/[^\s]+)');
    final matches = urlRegExp.allMatches(text);
    final baseColor = isEphemeral ? const Color(0xFFE5B3FF) : Colors.white;

    if (matches.isEmpty) {
      return _isSearchMode && _searchQuery.isNotEmpty
          ? HighlightedText(text: "$text   ", query: _searchQuery, baseStyle: TextStyle(color: baseColor, fontSize: 15))
          : Text("$text   ", style: TextStyle(color: baseColor, fontSize: 15));
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

    return RichText(text: TextSpan(style: TextStyle(color: baseColor, fontSize: 15), children: spans));
  }

  @override
  Widget build(BuildContext context) {
    final isGroupChat = _currentPartnerKey.startsWith('GROUP_');
    final isSelf = widget.partnerName == widget.userName;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        leading: _isSearchMode
          ? IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: _closeSearch)
          : IconButton(icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20), onPressed: () => Navigator.pop(context)),
        flexibleSpace: ClipRect(child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20), child: Container(color: Colors.black.withValues(alpha: 0.5)))),
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
                          Text(isSelf ? t("Нотатник", "Saved Messages") : widget.partnerName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                          if (widget.partnerIsVerified && !isGroupChat && !isSelf) ...[const SizedBox(width: 5), const VerifiedBadge(size: 15)],
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
              IconButton(icon: const Icon(Icons.keyboard_arrow_up, color: Colors.white), onPressed: _prevMatch),
              IconButton(icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white), onPressed: _nextMatch),
            ]
          : [
              if (!isSelf) IconButton(icon: const Icon(Icons.search, color: Colors.white), onPressed: () { setState(() { _isSearchMode = true; }); }),
              if (!isSelf) IconButton(icon: Icon(_isAetherMode ? Icons.local_fire_department : Icons.local_fire_department_outlined, color: _isAetherMode ? const Color(0xFFB026FF) : Colors.white), onPressed: () => setState(() { _isAetherMode = !_isAetherMode; _replyingTo = null; })),
            ],
      ),
      body: SafeArea(
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
                          padding: EdgeInsets.only(left: 12, right: 12, top: 20, bottom: _isPartnerTyping ? 60 : 20),
                          itemCount: _messages.length,
                          itemBuilder: (context, i) {
                            final m = _messages[i];
                            
                            if (m['isSystem'] == true) {
                              return Padding(padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24), child: Text(m['text'] ?? '', textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 13, fontWeight: FontWeight.w500, height: 1.5)));
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

                            bool hasValidImage = m['imageBytes'] != null || (m['text'] != null && m['text'].toString().length > 100);
                            bool hasCaption = m['text'] != null && m['text'].toString().isNotEmpty && m['text'].toString().length < 1000;

                            Widget bubble = Container(
                                margin: const EdgeInsets.only(bottom: 2),
                                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                                padding: EdgeInsets.only(left: isImage || isAudio ? 4 : 14, right: isImage || isAudio ? 4 : 14, top: isImage ? 4 : 10, bottom: isImage ? 4 : 10),
                                decoration: BoxDecoration(
                                  color: isSearchMatch ? const Color(0xFF6B5B00) : (isMsgEphemeral ? const Color(0xFF4A1073) : (isMe ? const Color(0xFF2B5278) : const Color(0xFF212121))),
                                  border: Border.all(color: isSearchMatch ? const Color(0xFFFFD700).withValues(alpha: 0.5) : (isMsgEphemeral ? const Color(0xFFB026FF).withValues(alpha: 0.5) : Colors.transparent), width: 0.5),
                                  borderRadius: BorderRadius.only(topLeft: const Radius.circular(18), topRight: const Radius.circular(18), bottomLeft: Radius.circular(isMe ? 18 : 4), bottomRight: Radius.circular(isMe ? 4 : 18)),
                                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 2, offset: const Offset(0, 1))],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start, 
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (isGroupChat && !isMe) ...[
                                      Padding(padding: const EdgeInsets.only(bottom: 2, left: 2), child: Text(m['senderName'] ?? 'Unknown', style: TextStyle(fontSize: 12, color: isMsgEphemeral ? const Color(0xFFE5B3FF) : Colors.white, fontWeight: FontWeight.w600))),
                                    ],
                                    if (hasReply) ...[
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
                                        base64Audio: m['text'] ?? '', isMe: isMe, isEphemeral: isMsgEphemeral, showUnreadDot: !isMe && !isListened,
                                        onPlay: () async {
                                          if (!isMe && !isListened) { setState(() { m['isListened'] = true; }); final prefs = await SharedPreferences.getInstance(); await prefs.setBool('listened_${m['timestamp']}', true); }
                                        },
                                      ),
                                      const SizedBox(height: 2),
                                      _buildTimeAndStatus(isEdited, isMsgEphemeral, timeStr, isMe, m['status']),
                                    ] else if (isImage && hasValidImage) ...[
                                      ClipRRect(borderRadius: BorderRadius.circular(14), child: _buildImage(m['imageBytes'] ?? m['text'])),
                                      if (hasCaption) ...[
                                        const SizedBox(height: 6),
                                        _buildMessageText(m['text'].toString(), isMsgEphemeral),
                                      ],
                                      const SizedBox(height: 4),
                                      _buildTimeAndStatus(isEdited, isMsgEphemeral, timeStr, isMe, m['status']),
                                    ] else ...[
                                      Wrap(alignment: WrapAlignment.end, crossAxisAlignment: WrapCrossAlignment.end, children: [
                                        _buildMessageText(m['text'] ?? '', isMsgEphemeral),
                                        _buildTimeAndStatus(isEdited, isMsgEphemeral, timeStr, isMe, m['status']),
                                      ]),
                                    ]
                                  ],
                                ),
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
                              child: Padding(padding: const EdgeInsets.only(left: 12, bottom: 8, top: 4), child: GlassContainer(color: Colors.white.withValues(alpha: 0.05), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), borderRadius: 20, child: const TypingIndicator(color: Colors.white, size: 6))),
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
    );
  }

  Widget _buildTimeAndStatus(bool isEdited, bool isMsgEphemeral, String timeStr, bool isMe, String? status) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isEdited) ...[
          Text(t("змінено ", "edited "), style: TextStyle(color: isMsgEphemeral ? const Color(0xFFE5B3FF) : Colors.white.withValues(alpha: 0.5), fontSize: 10, fontStyle: FontStyle.italic)),
        ],
        Text(timeStr, style: TextStyle(color: isMsgEphemeral ? const Color(0xFFE5B3FF) : Colors.white.withValues(alpha: 0.5), fontSize: 10)),
        if (isMe && !isMsgEphemeral) ...[
          const SizedBox(width: 4), 
          Icon(status == 'read' ? Icons.done_all : Icons.check, size: 14, color: status == 'read' ? const Color(0xFF00C7FF) : Colors.white.withValues(alpha: 0.5)),
        ],
        if (isMsgEphemeral) ...[
          Padding(padding: const EdgeInsets.only(left: 4), child: Icon(Icons.local_fire_department, color: const Color(0xFFE5B3FF), size: 12)),
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
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), border: Border(top: BorderSide(color: _isAetherMode ? const Color(0xFFB026FF).withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.1), width: 1))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        if (!isEditingMode && !_isRecordingAudio) ...[
          GestureDetector(onTap: _showAttachmentMenu, child: const Icon(Icons.add, color: Colors.white, size: 28)),
        ],
        
        if (_isAetherMode && !_isRecordingAudio && !isEditingMode) ...[
          GestureDetector(
            onTap: _cycleEphemeralDuration,
            child: Container(
              margin: const EdgeInsets.only(left: 8), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: const Color(0xFFB026FF).withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFB026FF).withValues(alpha: 0.5))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.timer_outlined, color: Color(0xFFE5B3FF), size: 14),
                  const SizedBox(width: 4),
                  Text('${_ephemeralDuration}s', style: const TextStyle(color: Color(0xFFE5B3FF), fontSize: 12, fontWeight: FontWeight.bold)),
              ]),
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
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(color: _isAetherMode ? const Color(0xFF1A0B2E) : Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(20), border: Border.all(color: _isAetherMode ? const Color(0xFFB026FF) : Colors.white.withValues(alpha: 0.1))),
                child: TextField(
                  controller: _c, focusNode: _chatFocusNode, minLines: 1, maxLines: 4, onChanged: _onTextChanged,
                  style: TextStyle(color: _isAetherMode ? const Color(0xFFE5B3FF) : Colors.white, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: isEditingMode ? t("Змінити...", "Edit...") : (_isAetherMode ? t("Секретне повідомлення...", "Secret message...") : t("Повідомлення...", "Message...")),
                    hintStyle: TextStyle(color: _isAetherMode ? const Color(0xFFB026FF).withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.4), fontSize: 15),
                    border: InputBorder.none, isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                  ),
                ),
              ),
        ),
        const SizedBox(width: 8),
        (_hasText || isEditingMode)
          ? GestureDetector(
              behavior: HitTestBehavior.opaque, 
              onTap: _send, 
              onLongPress: (!isEditingMode && !_isAetherMode) ? _showScheduleDialog : null,
              child: Container(height: 40, width: 40, decoration: BoxDecoration(color: _isAetherMode ? const Color(0xFFB026FF) : Colors.white, borderRadius: BorderRadius.circular(50)), child: Icon(isEditingMode ? Icons.check : Icons.arrow_upward, color: _isAetherMode ? Colors.white : Colors.black, size: 20))
            )
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onLongPressStart: (_) => _startRecording(),
              onLongPressEnd: (_) => _stopRecording(),
              onLongPressCancel: () => _cancelRecording(),
              child: Container(
                height: 40, width: 40, 
                decoration: BoxDecoration(color: _isRecordingAudio ? const Color(0xFFFF3B30) : Colors.white.withValues(alpha: 0.1), border: Border.all(color: _isRecordingAudio ? const Color(0xFFFF3B30) : Colors.transparent), borderRadius: BorderRadius.circular(50)), 
                child: Icon(_isRecordingAudio ? Icons.mic : Icons.mic_none, color: _isRecordingAudio ? Colors.white : (_isAetherMode ? const Color(0xFFB026FF) : Colors.white), size: 20)
              ),
            ),
      ]),
    );
  }
}