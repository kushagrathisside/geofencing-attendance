// lib/config.dart
// Override these at build/run time with --dart-define.

const String kApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://127.0.0.1:5000',
);

const String kAppBaseUrl = String.fromEnvironment(
  'APP_BASE_URL',
  defaultValue: 'http://localhost:8080',
);

const String kAdminKey = String.fromEnvironment('ADMIN_KEY');

// How long to wait on API calls before timing out
const Duration kTimeout = Duration(seconds: 15);
