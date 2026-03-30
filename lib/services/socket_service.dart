import 'package:socket_io_client/socket_io_client.dart' as IO;

class SocketService {
  // Робимо змінну статичною, щоб мати доступ до сокета звідусіль
  static IO.Socket? socket;

  static void connect() {
    // Увага: для локального тесту на емуляторі Android часто треба 'http://10.0.2.2:3000'
    // Для вебу (PWA) або локального тесту в браузері залишай 'http://localhost:3000'
    // Коли будеш деплоїти, зміниш на свій Render URL: 'https://aether-backend-hrmq.onrender.com'
    String url = 'http://localhost:3000';

    socket = IO.io(url, <String, dynamic>{
      'transports': ['websocket', 'polling'], // Обов'язково для вебу
      'autoConnect': true,
    });

    socket!.onConnect((_) {
      print('✅ Підключено до Aether');
    });

    socket!.onConnectError((err) => print('❌ Помилка підключення: $err'));
    
    socket!.onDisconnect((_) => print('⚠️ Відключено від сервера'));
  }
}