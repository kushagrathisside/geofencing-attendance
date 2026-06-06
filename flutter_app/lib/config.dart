// lib/config.dart
//
// kDefaultBaseUrl is the compile-time fallback.
// At runtime the user can override it from the login screen
// and it will be persisted via AuthService.setServerUrl().
//
// Find your server IP with:  hostname -I
// Example values:
//   http://192.168.1.42:8080   (classroom WiFi, plain HTTP — recommended)
//   http://10.0.0.5:8080

const String kDefaultBaseUrl = "http://172.17.24.26:8080";
const Duration kTimeout = Duration(seconds: 15);
