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
import 'main_gate.dart';

class ContactsScreen extends StatefulWidget {
  final String deviceId, userName, publicKey;
  const ContactsScreen({super.key, required this.deviceId, required this.userName, required this.publicKey});
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

  // --- ЗМІННІ ДЛЯ PIN-LOCK ---
  bool _isAppLocked = false;
  String? _savedPin;
  String _enteredPin = '';
  bool _isSettingPin = false;
  String _tempNewPin = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initLockState();
    
    _bgSocket = io.io('https://aether-backend-hrmq.onrender.com', {'transports': ['websocket'], 'forceNew': true});
    _bgSocket.connect();
    _bgSocket.onConnect((_) { 
      _bgSocket.emit('set_active', widget.userName); 
      _loadData(); 
    });
    
    _bgSocket.on('message', (data) {
      var msg = Map<String, dynamic>.from(data);
      if (msg['receiverName'] == widget.userName || (msg['receiverName'].toString().startsWith('GROUP_') && msg['senderName'] != widget.userName)) {
        if (currentActiveChat != msg['senderName'] && currentActiveChat != msg['receiverName']) { 
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

  // --- ЛОГІКА БЛОКУВАННЯ ---
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
        // ← ФІКС: скидаємо незавершене встановлення PIN
        _isSettingPin = false;
        _tempNewPin = '';
      });
    }
  }
}

  void _onPinTap(String val) {
    if (val == 'back') {
      if (_enteredPin.isNotEmpty) setState(() { _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1); });
      return;
    }
    if (_enteredPin.length < 4) {
      setState(() { _enteredPin += val; });
      if (_enteredPin.length == 4) {
        _verifyPin();
      }
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
          setState(() { _savedPin = _enteredPin; _isSettingPin = false; _tempNewPin = ''; _enteredPin = ''; });
          _showSnack(t("PIN-код встановлено", "PIN code set successfully"));
        } else {
          setState(() { _tempNewPin = ''; _enteredPin = ''; });
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
    } catch (e) { return "Encrypted"; }
  }

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
              if (dec.startsWith('{') && dec.endsWith('}')) { chat['decryptedText'] = jsonDecode(dec)['text']; }
              else { chat['decryptedText'] = dec; }
            } catch (e) { chat['decryptedText'] = t("🔒 Повідомлення зашифровано", "🔒 Message encrypted"); }
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
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 50, maxWidth: 500, maxHeight: 500);
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
    _bgSocket.emitWithAck('send_friend_request', {'requester': widget.userName, 'receiver': target}, ack: (dynamic data) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(data['message'], style: const TextStyle(color: Colors.white)), backgroundColor: data['success'] ? const Color(0xFF333333) : Colors.red.shade900, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50))));
        _addFriendController.clear();
      }
    });
  }

  void _respondToRequest(String requester, String action) {
    _bgSocket.emit('respond_friend_request', {'requester': requester, 'receiver': widget.userName, 'action': action});
    _loadData();
  }

  void _showCreateGroupDialog() {
    if (_friends.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('Спочатку додайте друзів!', 'Add friends first!'), style: const TextStyle(color: Colors.white)), backgroundColor: const Color(0xFF333333), behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50))));
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
                Text(t('Створити групу', 'Create Group'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 20),
                GlassInput(controller: groupNameController, hintText: t('Назва групи', 'Group Name')),
                const SizedBox(height: 16),
                Align(alignment: Alignment.centerLeft, child: Text(t("Учасники", "Members"), style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.white70, fontSize: 13))),
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
                        fillColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? Colors.white : Colors.transparent),
                        checkColor: Colors.black,
                        side: const BorderSide(color: Colors.white54),
                        checkboxShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                        onChanged: (bool? value) { setStateSB(() { if (value == true) { selectedFriends.add(friend); } else { selectedFriends.remove(friend); } }); },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: () => Navigator.pop(context), child: Text(t('Скасувати', 'Cancel'), style: const TextStyle(color: Colors.white70, fontSize: 14))),
                    TextButton(
                      onPressed: () {
                        if (groupNameController.text.trim().isNotEmpty && selectedFriends.isNotEmpty) {
                          _bgSocket.emitWithAck('create_group', {'name': groupNameController.text.trim(), 'participants': selectedFriends, 'creator': widget.userName}, ack: (dynamic data) { if (data['success'] == true) _loadData(); });
                          Navigator.pop(context);
                        }
                      },
                      child: Text(t('Створити', 'Create'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
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
    final TextEditingController bioController = TextEditingController(text: _myBio);
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
              Text(t("Про себе", "About"), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              TextField(
                controller: bioController,
                maxLength: 100,
                maxLines: null,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: t("Напишіть щось...", "Write something..."),
                  hintStyle: const TextStyle(color: Colors.white54),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.4))),
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
                  TextButton(onPressed: () => Navigator.pop(context), child: Text(t("Скасувати", "Cancel"), style: const TextStyle(color: Colors.white70))),
                  TextButton(
                    onPressed: () {
                      _bgSocket.emit('update_bio', {'userName': widget.userName, 'bio': bioController.text.trim()});
                      setState(() => _myBio = bioController.text.trim());
                      Navigator.pop(context);
                    },
                    child: Text(t("Зберегти", "Save"), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
                Text(t("Експорт акаунта", "Export Account"), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Text(
                  t("Увага! Створіть пароль. Якщо ви його забудете, відновити акаунт буде неможливо.", "Warning! Create a password. If you lose it, recovery is impossible."),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.red.withValues(alpha: 0.8), fontSize: 12),
                ),
                const SizedBox(height: 20),
                if (backupToken == null) ...[
                  GlassInput(controller: passwordController, hintText: t("Придумайте пароль", "Create password"), obscureText: true),
                  const SizedBox(height: 20),
                  ShineButton(
                    text: t("Згенерувати ключ", "Generate Backup"),
                    onPressed: () async {
                      if (passwordController.text.trim().isEmpty) return;
                      try {
                        final storage = const FlutterSecureStorage();
                        final priv = await storage.read(key: 'private_key');
                        final payloadStr = jsonEncode({'priv': priv, 'pub': widget.publicKey, 'dev': widget.deviceId, 'name': widget.userName});
                        final passHash = await Sha256().hash(utf8.encode(passwordController.text.trim()));
                        final key = await _aes.newSecretKeyFromBytes(passHash.bytes);
                        final box = await _aes.encrypt(utf8.encode(payloadStr), secretKey: key);
                        setStateSB(() { backupToken = '${base64Encode(box.nonce)}.${base64Encode(box.cipherText)}.${base64Encode(box.mac.bytes)}'; });
                      } catch (e) { _showSnack("Encryption error"); }
                    },
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFB026FF).withValues(alpha: 0.5))),
                    child: SelectableText(backupToken!, style: const TextStyle(color: Colors.white, fontSize: 10, fontFamily: 'monospace')),
                  ),
                  const SizedBox(height: 16),
                  ElegantButton(
                    text: t("Скопіювати ключ", "Copy Backup Key"),
                    onPressed: () { Clipboard.setData(ClipboardData(text: backupToken!)); _showSnack(t("Скопійовано в буфер", "Copied to clipboard")); Navigator.pop(context); },
                  ),
                ],
                if (backupToken == null) TextButton(onPressed: () => Navigator.pop(context), child: Text(t('Скасувати', 'Cancel'), style: const TextStyle(color: Colors.white70))),
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
        try { chatSettings = _recentChats.firstWhere((c) => c['partnerName'] == partnerName); } catch (e) { /* ignore */ }
        bool isBlocked = chatSettings?['isBlocked'] == true;
        bool isPinned = chatSettings?['isPinned'] == true;
        return StatefulBuilder(
          builder: (context, setStateSB) {
            if (!fetched) {
              fetched = true;
              _bgSocket.emitWithAck('get_user_profile', partnerName, ack: (dynamic data) {
                if (data['success'] == true) setStateSB(() { currentBio = data['bio']; currentAvatar = data['avatar'] ?? currentAvatar; isVerifiedUser = data['isVerified'] == true; });
              });
            }
            return Container(
              width: double.infinity,
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
                        SafeAvatar(avatarBase64: currentAvatar, fallbackName: partnerName, radius: 46),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(partnerName, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: -0.5)),
                            if (isVerifiedUser) ...[const SizedBox(width: 8), const VerifiedBadge(size: 22)],
                          ],
                        ),
                        if (currentBio != null && currentBio!.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(currentBio!, textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 15)),
                        ],
                        const SizedBox(height: 32),
                        GlassContainer(
                          child: Column(children: [
                            ListTile(leading: const Icon(Icons.chat_bubble_outline, color: Colors.white), title: Text(t("Написати", "Message"), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)), onTap: () { Navigator.pop(context); _startChat(partnerName, publicKey, targetAvatar: currentAvatar, isVerified: isVerifiedUser); }),
                            Divider(height: 1, indent: 50, color: Colors.white.withValues(alpha: 0.1)),
                            ListTile(leading: Icon(isPinned ? Icons.push_pin : Icons.push_pin_outlined, color: Colors.white), title: Text(isPinned ? t("Відкріпити чат", "Unpin Chat") : t("Закріпити чат", "Pin Chat"), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)), onTap: () { _bgSocket.emit('update_chat_settings', {'userName': widget.userName, 'partnerName': partnerName, 'isPinned': !isPinned, 'isHidden': chatSettings?['isHidden'] == true, 'isDeleted': false, 'isBlocked': isBlocked}); Navigator.pop(context); }),
                            Divider(height: 1, indent: 50, color: Colors.white.withValues(alpha: 0.1)),
                            ListTile(leading: const Icon(Icons.visibility_off, color: Colors.white), title: Text(t("Приховати чат", "Hide Chat"), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)), onTap: () { _bgSocket.emit('update_chat_settings', {'userName': widget.userName, 'partnerName': partnerName, 'isPinned': isPinned, 'isHidden': true, 'isDeleted': false, 'isBlocked': isBlocked}); Navigator.pop(context); }),
                          ]),
                        ),
                        const SizedBox(height: 16),
                        GlassContainer(
                          child: Column(children: [
                            ListTile(leading: Icon(isBlocked ? Icons.lock_open : Icons.block, color: const Color(0xFFFF3B30)), title: Text(isBlocked ? t("Розблокувати", "Unblock") : t("Заблокувати", "Block"), style: const TextStyle(color: Color(0xFFFF3B30), fontWeight: FontWeight.w500)), onTap: () { _bgSocket.emit('update_chat_settings', {'userName': widget.userName, 'partnerName': partnerName, 'isPinned': isPinned, 'isHidden': chatSettings?['isHidden'] == true, 'isDeleted': false, 'isBlocked': !isBlocked}); setStateSB(() { isBlocked = !isBlocked; }); _loadData(); }),
                            Divider(height: 1, indent: 50, color: Colors.white.withValues(alpha: 0.1)),
                            ListTile(leading: const Icon(Icons.delete_outline, color: Color(0xFFFF3B30)), title: Text(t("Видалити історію", "Delete History"), style: const TextStyle(color: Color(0xFFFF3B30), fontWeight: FontWeight.w500)), onTap: () { _bgSocket.emit('update_chat_settings', {'userName': widget.userName, 'partnerName': partnerName, 'isPinned': false, 'isHidden': false, 'isDeleted': true, 'isBlocked': isBlocked}); Navigator.pop(context); }),
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
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: const BorderRadius.vertical(top: Radius.circular(30))),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(leading: Icon(chat['isPinned'] == true ? Icons.push_pin : Icons.push_pin_outlined, color: Colors.white), title: Text(chat['isPinned'] == true ? t('Відкріпити', 'Unpin') : t('Закріпити', 'Pin'), style: const TextStyle(color: Colors.white)), onTap: () { Navigator.pop(context); _bgSocket.emit('update_chat_settings', {'userName': widget.userName, 'partnerName': chat['partnerName'], 'isPinned': !(chat['isPinned'] == true), 'isHidden': chat['isHidden'] == true, 'isDeleted': false, 'isBlocked': chat['isBlocked'] == true}); }),
                  Divider(height: 1, color: Colors.white.withValues(alpha: 0.1)),
                  ListTile(leading: const Icon(Icons.visibility_off, color: Colors.white), title: Text(t('Приховати чат', 'Hide Chat'), style: const TextStyle(color: Colors.white)), subtitle: Text(t('Можна знайти через пошук', 'Can be found via search'), style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12)), onTap: () { Navigator.pop(context); _bgSocket.emit('update_chat_settings', {'userName': widget.userName, 'partnerName': chat['partnerName'], 'isPinned': chat['isPinned'] == true, 'isHidden': true, 'isDeleted': false, 'isBlocked': chat['isBlocked'] == true}); }),
                  Divider(height: 1, color: Colors.white.withValues(alpha: 0.1)),
                  ListTile(leading: const Icon(Icons.delete_outline, color: Color(0xFFFF3B30)), title: Text(t('Видалити', 'Delete'), style: const TextStyle(color: Color(0xFFFF3B30))), onTap: () { Navigator.pop(context); _bgSocket.emit('update_chat_settings', {'userName': widget.userName, 'partnerName': chat['partnerName'], 'isPinned': false, 'isHidden': false, 'isDeleted': true, 'isBlocked': chat['isBlocked'] == true}); }),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _startChat(String targetName, String? targetKey, {String? targetAvatar, bool isVerified = false}) {
    if (targetName.isEmpty) return;
    if (targetKey != null) { _openChatScreen(targetName, targetKey, avatar: targetAvatar, isVerified: isVerified); return; }
    setState(() => _isSearching = true);
    _bgSocket.emitWithAck('get_key', targetName, ack: (dynamic response) {
      if (mounted) setState(() { _isSearching = false; });
      if (response['success'] == true) {
        _bgSocket.emit('update_chat_settings', {'userName': widget.userName, 'partnerName': targetName, 'isPinned': false, 'isHidden': false, 'isDeleted': false, 'isBlocked': false});
        _openChatScreen(targetName, response['publicKey'], avatar: response['avatar'], isVerified: response['isVerified'] == true);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(response['message'] ?? t('Не знайдено', 'Not found'), style: const TextStyle(color: Colors.white)), backgroundColor: Colors.red.shade900, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50))));
      }
    });
  }

  void _openChatScreen(String targetName, String targetKey, {String? avatar, bool isVerified = false}) {
    Navigator.push(context, MaterialPageRoute(builder: (context) => ChatScreen(
      deviceId: widget.deviceId, userName: widget.userName, myPublicKey: widget.publicKey,
      partnerName: targetName, partnerPublicKey: targetKey, partnerAvatar: avatar,
      partnerIsVerified: isVerified,
      friends: _friends,
    ))).then((_) => _loadData());
  }

  void _logout() async {
    await (await SharedPreferences.getInstance()).remove('user_name');
    if (mounted) Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (context) => const MainGate()), (r) => false);
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
    _bgSocket.emitWithAck('search_users_for_verify', {'adminName': widget.userName, 'query': q}, ack: (dynamic data) {
      if (mounted) setState(() { _verifyResults = List<Map<String, dynamic>>.from(data); });
    });
  }

  void _toggleVerification(String targetName, bool currentlyVerified) {
    final event = currentlyVerified ? 'revoke_verification' : 'grant_verification';
    _bgSocket.emitWithAck(event, {'adminName': widget.userName, 'targetName': targetName}, ack: (dynamic data) {
      if (context.mounted) {
        _showSnack(data['success'] ? (currentlyVerified ? t('Верифікацію знято', 'Verification revoked') : t('Верифіковано!', 'Verified!')) : (data['message'] ?? 'Error'));
        _searchUsersForVerify();
      }
    });
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg, style: const TextStyle(color: Colors.white)), backgroundColor: const Color(0xFF333333), behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50))));
  }

  // --- ЕКРАН БЛОКУВАННЯ ---
  Widget _buildLockScreen() {
  final isPinConfirmStep = _isSettingPin && _tempNewPin.isNotEmpty;

  return Scaffold(
    backgroundColor: Colors.black,
    body: Stack(
      children: [
        // Фонові кружки
        Positioned(top: -80, left: -60, child: Container(width: 280, height: 280, decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFFB026FF).withValues(alpha: 0.08)))),
        Positioned(bottom: -100, right: -80, child: Container(width: 320, height: 320, decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFFB026FF).withValues(alpha: 0.05)))),

        SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 2),

              // Іконка замку
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.05),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1.5),
                ),
                child: const Icon(Icons.lock_outline_rounded, size: 32, color: Colors.white),
              ),
              const SizedBox(height: 24),

              // Заголовок
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Text(
                  key: ValueKey(_isSettingPin ? (_tempNewPin.isEmpty ? 'create' : 'confirm') : 'enter'),
                  _isSettingPin
                      ? (_tempNewPin.isEmpty
                          ? t("Створіть PIN-код", "Create PIN code")
                          : t("Підтвердіть PIN-код", "Confirm PIN code"))
                      : t("Введіть PIN-код", "Enter PIN code"),
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.5),
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

              // Крапки-індикатори
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
                          ? [BoxShadow(color: const Color(0xFFB026FF).withValues(alpha: 0.5), blurRadius: 8, spreadRadius: 1)]
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
                    for (final row in [['1','2','3'], ['4','5','6'], ['7','8','9'], ['','0','back']])
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

Widget _numButton(String val, {IconData? icon}) {
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
            : Text(val, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w400, letterSpacing: -0.5)),
      ),
    ),
  );
}

  // --- ТАБИ ---
  Widget _buildChatsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10),
          child: Center(child: AnimatedSearchInput(controller: _searchController, onSubmitted: (_) => _isSearching ? null : _startChat(_searchController.text.trim(), null))),
        ),
        if (_isSearching) const Center(child: Padding(padding: EdgeInsets.all(10), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)))),
        Expanded(
          child: _recentChats.isEmpty
            ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(t("Чатів поки що немає.", "No chats yet."), style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 16)),
                const SizedBox(height: 4),
                Text(t("Напишіть щось друзям.", "Write something to friends."), style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 16)),
              ]))
            : ListView.separated(
                padding: const EdgeInsets.only(bottom: 120), // Відступ для нижнього меню
                itemCount: _recentChats.length,
                separatorBuilder: (context, index) => Padding(padding: const EdgeInsets.only(left: 76.0), child: Divider(height: 1, color: Colors.white.withValues(alpha: 0.05))),
                itemBuilder: (context, index) {
                  final chat = _recentChats[index];
                  final isGroup = chat['isGroup'] == true;
                  final unreadCount = chat['unreadCount'] ?? 0;
                  final isSelf = chat['partnerName'] == widget.userName;
                  final chatVerified = chat['isVerified'] == true;
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    leading: GestureDetector(
                      onTap: () => isSelf ? null : _showUserProfile(chat['partnerName'], chat['avatar'], chat['publicKey'], isGroup),
                      child: isSelf
                        ? CircleAvatar(radius: 24, backgroundColor: Colors.white.withValues(alpha: 0.1), child: const Icon(Icons.bookmark, color: Colors.white70))
                        : StoryRingAvatar(avatarBase64: chat['avatar'], fallbackName: chat['partnerName'], radius: 24, isGroup: isGroup, hasUnread: unreadCount > 0),
                    ),
                    title: Row(children: [
                      Expanded(child: Text(isSelf ? t("Нотатник", "Saved Messages") : chat['partnerName'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16, letterSpacing: -0.2), overflow: TextOverflow.ellipsis)),
                      if (!isGroup && chatVerified) ...[const SizedBox(width: 4), const VerifiedBadge(size: 14)],
                      if (chat['isPinned'] == true) ...[const SizedBox(width: 4), Icon(Icons.push_pin, color: Colors.white.withValues(alpha: 0.5), size: 14)],
                    ]),
                    subtitle: Text(
                      chat['decryptedText'] ?? (isGroup ? t("Груповий чат", "Group Chat") : t("Почніть чат", "Start chatting")),
                      style: TextStyle(color: unreadCount > 0 ? Colors.white : Colors.white.withValues(alpha: 0.6), fontWeight: unreadCount > 0 ? FontWeight.w500 : FontWeight.normal, fontSize: 14),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (chat['lastMessage'] != null) Text(DateFormat('HH:mm').format(DateTime.parse(chat['timestamp']).toLocal()), style: TextStyle(fontSize: 12, color: unreadCount > 0 ? Colors.white : Colors.white.withValues(alpha: 0.5))),
                        const SizedBox(height: 4),
                        if (unreadCount > 0) Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(50)), child: Text('$unreadCount', style: const TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.bold))),
                      ],
                    ),
                    onLongPress: () => _showChatOptions(chat),
                    onTap: () => _startChat(chat['partnerName'], chat['publicKey'], targetAvatar: chat['avatar'], isVerified: chatVerified),
                  );
                },
              ),
        ),
      ],
    );
  }

  Widget _buildFriendsTab() {
    return ListView(
      padding: const EdgeInsets.only(top: 20, bottom: 120), // Відступ для нижнього меню
      children: [
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Text(t("ДОДАТИ ДРУГА", "ADD FRIEND"), style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.5), fontWeight: FontWeight.bold, letterSpacing: 1))),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Expanded(child: GlassInput(controller: _addFriendController, hintText: t("Нікнейм", "Username"), inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_.\-]'))])),
            const SizedBox(width: 10),
            ElegantButton(text: t("ДОДАТИ", "ADD"), onPressed: _sendFriendRequest),
          ]),
        ),
        const SizedBox(height: 32),
        if (_pendingRequests.isNotEmpty) ...[
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Text(t("ЗАПИТИ В ДРУЗІ", "REQUESTS"), style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.5), fontWeight: FontWeight.bold, letterSpacing: 1))),
          GlassContainer(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(children: _pendingRequests.asMap().entries.map((entry) {
              int idx = entry.key; var req = entry.value;
              return Column(children: [
                ListTile(
                  leading: GestureDetector(onTap: () => _showUserProfile(req['userName'], req['avatar'], null, false), child: SafeAvatar(avatarBase64: req['avatar'], fallbackName: req['userName'], radius: 20)),
                  title: Row(children: [
                    Text(req['userName'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 16)),
                    if (req['isVerified'] == 1) ...[const SizedBox(width: 5), const VerifiedBadge(size: 13)],
                  ]),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    GestureDetector(onTap: () => _respondToRequest(req['userName'], 'accept'), child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(50)), child: Text(t("Прийняти", "Accept"), style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold)))),
                    const SizedBox(width: 8),
                    GestureDetector(onTap: () => _respondToRequest(req['userName'], 'reject'), child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), border: Border.all(color: Colors.white.withValues(alpha: 0.2)), borderRadius: BorderRadius.circular(50)), child: Text(t("Сховати", "Deny"), style: const TextStyle(color: Colors.white, fontSize: 12)))),
                  ]),
                ),
                if (idx != _pendingRequests.length - 1) Divider(height: 1, indent: 60, color: Colors.white.withValues(alpha: 0.05)),
              ]);
            }).toList()),
          ),
          const SizedBox(height: 24),
        ],
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Text(t("ДРУЗІ", "FRIENDS"), style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.5), fontWeight: FontWeight.bold, letterSpacing: 1))),
        _friends.isEmpty
          ? Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Text(t("У вас ще немає друзів.", "No friends yet."), style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 14)))
          : GlassContainer(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(children: _friends.asMap().entries.map((entry) {
                int idx = entry.key; var f = entry.value;
                return Column(children: [
                  ListTile(
                    leading: GestureDetector(onTap: () => _showUserProfile(f['userName'], f['avatar'], f['publicKey'], false), child: SafeAvatar(avatarBase64: f['avatar'], fallbackName: f['userName'], radius: 20)),
                    title: Row(children: [
                      Text(f['userName'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 16)),
                      if (f['isVerified'] == true || f['isVerified'] == 1) ...[const SizedBox(width: 5), const VerifiedBadge(size: 13)],
                    ]),
                    onTap: () => _startChat(f['userName'], f['publicKey'], targetAvatar: f['avatar'], isVerified: (f['isVerified'] == true || f['isVerified'] == 1)),
                  ),
                  if (idx != _friends.length - 1) Divider(height: 1, indent: 60, color: Colors.white.withValues(alpha: 0.05)),
                ]);
              }).toList()),
            ),
      ],
    );
  }

  Widget _buildSettingsTab() {
    return ListView(
      padding: const EdgeInsets.only(top: 20, bottom: 120),
      children: [
        Center(
          child: Stack(children: [
            SafeAvatar(avatarBase64: _myAvatar, fallbackName: widget.userName, radius: 46),
            Positioned(bottom: 0, right: 0, child: GestureDetector(onTap: _updateAvatar, child: Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: const Color(0xFF1E1E2C), border: Border.all(color: Colors.black, width: 2), shape: BoxShape.circle), child: const Icon(Icons.camera_alt, color: Colors.white, size: 14)))),
          ]),
        ),
        const SizedBox(height: 12),
        Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.userName, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: -0.5)),
              if (_myVerified) ...[const SizedBox(width: 8), const VerifiedBadge(size: 18)],
            ],
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _showEditBioDialog,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(child: Text(_myBio.isEmpty ? t("Додати інформацію про себе", "Add a bio") : _myBio, textAlign: TextAlign.center, style: TextStyle(color: _myBio.isEmpty ? Colors.white.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.7), fontSize: 14, fontStyle: _myBio.isEmpty ? FontStyle.italic : FontStyle.normal))),
                const SizedBox(width: 6),
                Icon(Icons.edit, size: 14, color: Colors.white.withValues(alpha: 0.5)),
              ],
            ),
          ),
        ),
        
        const SizedBox(height: 32),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Text(t("БЕЗПЕКА (ZERO-KNOWLEDGE)", "SECURITY (ZERO-KNOWLEDGE)"), style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.5), fontWeight: FontWeight.bold, letterSpacing: 1))),
        GlassContainer(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(children: [
            // НОВА КНОПКА PIN-LOCK
            ListTile(
              leading: const Icon(Icons.lock_outline, color: Colors.white), 
              title: Text(t("PIN-код для входу", "App Lock (PIN)"), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)), 
              trailing: Switch(
  value: _savedPin != null && _savedPin!.isNotEmpty,
  activeColor: const Color(0xFFB026FF),
  onChanged: (val) async {
    if (val) {
      // Вмикаємо — показуємо екран встановлення PIN
      setState(() {
        _isAppLocked = true;
        _isSettingPin = true;
        _enteredPin = '';
        _tempNewPin = '';
      });
    } else {
      // ← ФІКС: НЕ блокуємо апп, просто видаляємо PIN
      await const FlutterSecureStorage().delete(key: 'app_pin');
      setState(() { _savedPin = null; });
      _showSnack(t("PIN-код вимкнено", "PIN disabled"));
    }
  },
),
            ),
            Divider(height: 1, indent: 50, color: Colors.white.withValues(alpha: 0.05)),
            ListTile(leading: const Icon(Icons.vpn_key, color: Colors.white), title: Text(t("Експорт акаунта", "Export Account"), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)), subtitle: Text(t("Створити резервну копію ключів", "Create a backup of your keys"), style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12)), onTap: _showExportDialog),
          ]),
        ),

        const SizedBox(height: 32),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Text(t("МОВА", "LANGUAGE"), style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.5), fontWeight: FontWeight.bold, letterSpacing: 1))),
        GlassContainer(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(children: [
            ListTile(title: const Text("Українська", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)), trailing: lang == 'uk' ? const Icon(Icons.check, color: Colors.white) : null, onTap: () => _changeLanguage('uk')),
            Divider(height: 1, indent: 16, color: Colors.white.withValues(alpha: 0.05)),
            ListTile(title: const Text("English", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)), trailing: lang == 'en' ? const Icon(Icons.check, color: Colors.white) : null, onTap: () => _changeLanguage('en')),
          ]),
        ),

        if (_isAdmin) ...[
          const SizedBox(height: 32),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [
              const VerifiedBadge(size: 14),
              const SizedBox(width: 8),
              Text(t("ВЕРИФІКАЦІЯ АКАУНТІВ", "ACCOUNT VERIFICATION"), style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.5), fontWeight: FontWeight.bold, letterSpacing: 1)),
            ]),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Expanded(child: GlassInput(controller: _verifySearchController, hintText: t("Знайти користувача...", "Find user..."), inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_.\-]'))])),
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
                      leading: SafeAvatar(avatarBase64: user['avatar'], fallbackName: user['userName'], radius: 18),
                      title: Row(children: [
                        Text(user['userName'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                        if (isVerified) ...[const SizedBox(width: 6), const VerifiedBadge(size: 13)],
                      ]),
                      trailing: GestureDetector(
                        onTap: () => _toggleVerification(user['userName'], isVerified),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(
                            color: isVerified ? Colors.red.withValues(alpha: 0.12) : const Color(0xFF1DA1F2).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(50),
                            border: Border.all(color: isVerified ? Colors.red.withValues(alpha: 0.4) : const Color(0xFF1DA1F2).withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            isVerified ? t('Зняти', 'Revoke') : t('Верифікувати', 'Verify'),
                            style: TextStyle(color: isVerified ? Colors.red : const Color(0xFF1DA1F2), fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                    if (idx != _verifyResults.length - 1) Divider(height: 1, indent: 56, color: Colors.white.withValues(alpha: 0.05)),
                  ]);
                }).toList(),
              ),
            ),
          ],
        ],

        const SizedBox(height: 40),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GestureDetector(
            onTap: _logout,
            child: Container(height: 48, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(50), border: Border.all(color: Colors.red.withValues(alpha: 0.3))), alignment: Alignment.center, child: Text(t("Вийти з акаунту", "Log Out"), style: const TextStyle(color: Color(0xFFFF3B30), fontSize: 14, fontWeight: FontWeight.w600))),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────
  // НОВЕ ПОВНІСТЮ ЧОРНЕ МЕНЮ З UIVERSE (З НАШИМИ 3 КНОПКАМИ)
  // ─────────────────────────────────────────────────────────
  // ─────────────────────────────────────────────────────────
  // ПРЕМІАЛЬНЕ ЧОРНЕ МЕНЮ (АДАПТОВАНО З UIVERSE)
  // ─────────────────────────────────────────────────────────
  Widget _buildDarkGlassMenu(int totalUnread, int totalPending) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.only(
          left: 10, 
          right: 10, 
          // Відступ знизу для iPhone
          bottom: MediaQuery.of(context).padding.bottom + 12
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: BackdropFilter(
            // backdrop-filter: blur(12px)
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 520),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                // background: rgba(20, 20, 20, 0.75);
                color: const Color(0xFF141414).withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(999),
                // border: 1px solid rgba(255, 255, 255, 0.08);
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                boxShadow: [
                  // box-shadow: 0 10px 30px rgba(0, 0, 0, 0.35);
                  BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 30, offset: const Offset(0, 10))
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _menuItem(0, Icons.home_rounded, t("Чати", "Home"), totalUnread),
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
    // color: rgba(255, 255, 255, 0.95) для активного, 0.65 для неактивного
    final color = isActive ? Colors.white.withValues(alpha: 0.95) : Colors.white.withValues(alpha: 0.65);
    // background: rgba(255, 255, 255, 0.12) для активного
    final bgColor = isActive ? Colors.white.withValues(alpha: 0.12) : Colors.transparent;

    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _currentIndex = index),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          // transition: background 0.18s
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Badge(
                isLabelVisible: badgeCount > 0,
                backgroundColor: Colors.white,
                textColor: Colors.black,
                label: Text('$badgeCount', style: const TextStyle(fontWeight: FontWeight.bold)),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 11, // font-size: 0.8rem
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

  @override
  Widget build(BuildContext context) {
    // ЯКЩО ДОДАТОК ЗАБЛОКОВАНИЙ — ПОКАЗУЄМО PIN-LOCK ЕКРАН
    if (_isAppLocked) {
      return _buildLockScreen();
    }

    int totalUnread = _recentChats.fold(0, (sum, chat) => sum + ((chat['unreadCount'] ?? 0) as int));
    int totalPending = _pendingRequests.length;
    String appBarTitle = _currentIndex == 0 ? t("Чати", "Chats") : (_currentIndex == 1 ? t("Друзі", "Friends") : t("Профіль", "Profile"));
    
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true, 
      appBar: AppBar(
        title: Text(appBarTitle),
        flexibleSpace: ClipRect(child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20), child: Container(color: Colors.black.withValues(alpha: 0.5)))),
        actions: _currentIndex == 0 ? [Container(margin: const EdgeInsets.only(right: 16), child: IconButton(icon: const Icon(Icons.group_add, color: Colors.white, size: 24), onPressed: _showCreateGroupDialog))] : null,
      ),
      body: LiquidBackground(
        child: Stack(
          children: [
            _currentIndex == 0 ? _buildChatsTab() : (_currentIndex == 1 ? _buildFriendsTab() : _buildSettingsTab()),
            // Вставляємо нове круте меню поверх усього
            _buildDarkGlassMenu(totalUnread, totalPending),
          ],
        ),
      ),
    );
  }
}