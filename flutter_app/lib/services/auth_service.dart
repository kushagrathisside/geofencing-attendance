// lib/services/auth_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config.dart';

class AuthService {
  static final AuthService instance = AuthService._();
  final _storage = const FlutterSecureStorage();
  AuthService._();

  String? _token;
  Map<String, dynamic>? _payload;
  String _serverUrl = kDefaultBaseUrl;

  // ---- public getters ----

  bool    get isLoggedIn => _token != null;
  String? get token      => _token;
  String  get username   => _payload?['username'] ?? '';
  String  get role       => _payload?['role']     ?? '';
  bool    get isAdmin    => role == 'admin';
  String  get serverUrl  => _serverUrl;

  // ---- shared HTTP client (standard, no SSL bypass) ----

  static final _client = http.Client();

  Uri _uri(String path) => Uri.parse('$_serverUrl$path');

  // ---- persistence ----

  Future<void> loadToken() async {
    _serverUrl = await _storage.read(key: 'server_url') ?? kDefaultBaseUrl;
    _token     = await _storage.read(key: 'auth_token');
    if (_token != null) {
      _payload = _decodePayload(_token!);
    }
  }

  Future<void> setServerUrl(String url) async {
    _serverUrl = url.trim();
    await _storage.write(key: 'server_url', value: _serverUrl);
  }

  // ---- login ----

  /// Returns null on success, error message string on failure.
  Future<String?> login(String username, String password) async {
    try {
      final res = await _client.post(
        _uri('/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username.trim().toLowerCase(),
          'password': password,
        }),
      ).timeout(kTimeout);

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 200) {
        _token = body['token'] as String;
        await _storage.write(key: 'auth_token', value: _token);
        _payload = _decodePayload(_token!);
        return null; // success
      }
      return body['error'] as String? ?? 'Login failed';
    } catch (e) {
      return 'Could not reach server. Is Flask running at $_serverUrl?';
    }
  }

  Future<void> logout() async {
    _token   = null;
    _payload = null;
    await _storage.delete(key: 'auth_token');
  }

  /// Change current user's password.
  Future<String?> changePassword(String current, String newPass) async {
    try {
      final res = await _client.post(
        _uri('/auth/change-password'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token',
        },
        body: jsonEncode({'current_password': current, 'new_password': newPass}),
      ).timeout(kTimeout);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 200) return null;
      return body['error'] as String? ?? 'Failed';
    } catch (e) {
      return e.toString();
    }
  }

  // ---- JWT payload decode (client-side only, no signature verification) ----

  Map<String, dynamic> _decodePayload(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return {};
    final normalized = base64Url.normalize(parts[1]);
    return jsonDecode(utf8.decode(base64Url.decode(normalized))) as Map<String, dynamic>;
  }
}
