import 'package:flutter/foundation.dart'; // Додаємо для перевірки kIsWeb
import 'package:socket_io_client/socket_io_client.dart' as io;

class SocketService {
  static io.Socket? socket;

  static void connect() {
    // РОЗУМНИЙ ВИБІР URL:
    // Якщо це браузер (PWA) -> йдемо через локальний проксі, щоб уникнути CORS
    // Якщо це Windows/Android/iOS -> йдемо НАПРЯМУ на Render
    String url = kIsWeb 
        ? 'http://localhost:3000' 
        : 'https://aether-backend-hrmq.onrender.com';

    socket = io.io(url, <String, dynamic>{
      // Для нативних додатків краще працює чистий websocket, 
      // а для вебу залишаємо обидва варіанти
      'transports': kIsWeb ? ['websocket', 'polling'] : ['websocket'], 
      'autoConnect': true,
    });

    socket!.onConnect((_) {
      debugPrint('✅ Підключено до Aether ($url)');
    });

    socket!.onConnectError((err) => debugPrint('❌ Помилка підключення: $err'));
    
    socket!.onDisconnect((_) => debugPrint('⚠️ Відключено від сервера'));
  }
}