
String? currentActiveChat;

String lang = 'uk';
String t(String uk, String en) => lang == 'uk' ? uk : en;

// ⚠️ IMPORTANT: Set ADMIN_USERNAME environment variable in build command
// Example: flutter build windows -- -DADMIN_USERNAME=admin_username
const String kAdminUsername = String.fromEnvironment(
  'ADMIN_USERNAME',
  defaultValue: '', // Empty default - must be set via environment
);