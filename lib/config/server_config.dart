import 'package:socket_io_client/socket_io_client.dart' as io;

const String serverUrl = 'https://aether-backend-hrmq.onrender.com';

Map<String, dynamic> socketOptions() {
  return {
    'transports': ['websocket', 'polling'],
    'upgrade': true,
    'timeout': 60000, // Збільшено до 60с для Render.com cold start
    'reconnection': true,
    'reconnectionAttempts': 10,
    'reconnectionDelay': 2000,
    'forceNew': true,
  };
}