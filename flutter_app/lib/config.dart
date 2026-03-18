// lib/config.dart
// Change BASE_URL to your deployed Flask server URL.

const String kBaseUrl = "https://172.29.1.239:8080";
const String kAdminKey = "supersecret"; // match ADMIN_KEY env var on server

// How long to wait on API calls before timing out
const Duration kTimeout = Duration(seconds: 15);
