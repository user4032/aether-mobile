import 'package:flutter/foundation.dart';

const String _defaultServerUrl = 'https://aether-backend-hrmq.onrender.com';

String get serverUrl {
  const fromDefine = String.fromEnvironment('AETHER_SERVER_URL');
  if (fromDefine.isNotEmpty) return fromDefine;
  return _defaultServerUrl;
}

Map<String, dynamic> socketOptions({
  bool forceNew = true,
  bool reconnection = true,
}) {
  return <String, dynamic>{
    'transports': kIsWeb ? ['websocket', 'polling'] : ['websocket'],
    'forceNew': forceNew,
    'reconnection': reconnection,
  };
}