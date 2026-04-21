import 'package:flutter/foundation.dart'; // ДОДАНО ІМПОРТ
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../config/server_config.dart';

class SocketService {
  static io.Socket? socket;

  static void connect() {
    socket = io.io(serverUrl, <String, dynamic>{
      ...socketOptions(),
      'autoConnect': true,
    });

    socket!.onConnect((_) {
      debugPrint('Connected to Aether ($serverUrl)');
    });

    socket!.onConnectError((err) => debugPrint('Connection error: $err'));
    socket!.onDisconnect((_) => debugPrint('Disconnected from server'));
  }
}