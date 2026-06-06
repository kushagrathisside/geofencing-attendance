// lib/services/api_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../models/session.dart';
import '../models/instructor.dart';
import '../utils/file_saver.dart';
import 'auth_service.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  const ApiException(this.message, {this.statusCode});
  @override
  String toString() => message;
}

class ApiService {
  // Standard HTTP client — no SSL bypass. Use plain HTTP on the local network.
  // For HTTPS you need a certificate trusted by the device's OS cert store.
  static final _client = http.Client();

  static Uri _uri(String path) =>
      Uri.parse('${AuthService.instance.serverUrl}$path');

  // Auth headers — throws if not logged in
  static Map<String, String> get _authHeaders {
    final token = AuthService.instance.token;
    if (token == null) throw const ApiException('User not authenticated');
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  // Public headers — for endpoints that don't require auth
  static const Map<String, String> _publicHeaders = {
    'Content-Type': 'application/json',
  };

  static Map<String, dynamic> _parse(http.Response res) {
    final body = jsonDecode(res.body);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return body as Map<String, dynamic>;
    }
    if (res.statusCode == 401) {
      throw const ApiException('Session expired. Please log in again.', statusCode: 401);
    }
    final msg = (body as Map)['message'] ?? body['error'] ?? 'Unknown error';
    throw ApiException(msg.toString(), statusCode: res.statusCode);
  }

  // ---- Sessions ----

  static Future<Map<String, dynamic>> createSession({
    required String courseName,
    double? geoLat,
    double? geoLon,
    double geoRadius = 100,
  }) async {
    final res = await _client.post(
      _uri('/session/new'),
      headers: _authHeaders,
      body: jsonEncode({
        'course_name': courseName,
        if (geoLat != null) 'geo_lat': geoLat,
        if (geoLon != null) 'geo_lon': geoLon,
        'geo_radius': geoRadius,
      }),
    ).timeout(kTimeout);
    return _parse(res);
  }

  static Future<List<Session>> listSessions() async {
    final res = await _client
        .get(_uri('/sessions'), headers: _authHeaders)
        .timeout(kTimeout);
    if (res.statusCode == 401) {
      throw const ApiException('Session expired. Please log in again.', statusCode: 401);
    }
    final list = jsonDecode(res.body) as List;
    return list
        .map((j) => Session.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  static Future<void> closeSession(String id) async {
    final res = await _client
        .post(_uri('/session/$id/close'), headers: _authHeaders)
        .timeout(kTimeout);
    _parse(res);
  }

  static Future<void> openSession(String id) async {
    final res = await _client
        .post(_uri('/session/$id/open'), headers: _authHeaders)
        .timeout(kTimeout);
    _parse(res);
  }

  static Future<void> resetSession(String id) async {
    final res = await _client
        .post(_uri('/session/$id/reset'), headers: _authHeaders)
        .timeout(kTimeout);
    _parse(res);
  }

  static Future<Map<String, dynamic>> getRecords(String id) async {
    final res = await _client
        .get(_uri('/session/$id/records'), headers: _authHeaders)
        .timeout(kTimeout);
    return _parse(res);
  }

  /// Public endpoint — does NOT require the user to be logged in.
  static Future<Session> getSession(String id) async {
    final res = await _client
        .get(_uri('/session/$id'), headers: _publicHeaders)
        .timeout(kTimeout);
    if (res.statusCode == 404) {
      throw const ApiException('Session not found.', statusCode: 404);
    }
    return Session.fromJson(_parse(res));
  }

  static String exportUrl(String id) =>
      '${AuthService.instance.serverUrl}/session/$id/export';

  /// Downloads the CSV and saves it to disk (or triggers browser download on web).
  /// Returns a human-readable description of where the file was saved.
  static Future<String> downloadCsv(String sessionId) async {
    final res = await _client
        .get(_uri('/session/$sessionId/export'), headers: _authHeaders)
        .timeout(kTimeout);
    if (res.statusCode != 200) {
      throw ApiException('Export failed', statusCode: res.statusCode);
    }
    final filename = '$sessionId-attendance.csv';
    return saveFile(filename, res.body);
  }

  // ---- Student attendance submission (public endpoint) ----

  static Future<void> submitAttendance({
    required String sessionId,
    required String name,
    required String rollNo,
    required String fingerprint,
    required double latitude,
    required double longitude,
    String comments = '',
  }) async {
    final res = await _client.post(
      _uri('/session/$sessionId/submit'),
      headers: _publicHeaders,
      body: jsonEncode({
        'name':        name,
        'roll_no':     rollNo,
        'fingerprint': fingerprint,
        'latitude':    latitude,
        'longitude':   longitude,
        'comments':    comments,
      }),
    ).timeout(kTimeout);

    if (res.statusCode == 201) return;
    if (res.statusCode == 409) {
      throw const ApiException('Already submitted.', statusCode: 409);
    }
    if (res.statusCode == 403) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final msg = body['message'] as String? ?? 'Outside geofence.';
      throw ApiException(msg, statusCode: 403);
    }
    _parse(res);
  }

  // ---- Accounts (admin only) ----

  static Future<List<Instructor>> listAccounts() async {
    final res = await _client
        .get(_uri('/accounts'), headers: _authHeaders)
        .timeout(kTimeout);
    if (res.statusCode == 401) {
      throw const ApiException('Session expired. Please log in again.', statusCode: 401);
    }
    final list = jsonDecode(res.body) as List;
    return list
        .map((j) => Instructor.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  static Future<void> createAccount({
    required String username,
    required String password,
    required String fullName,
    required String role,
  }) async {
    final res = await _client.post(
      _uri('/accounts'),
      headers: _authHeaders,
      body: jsonEncode({
        'username':  username,
        'password':  password,
        'full_name': fullName,
        'role':      role,
      }),
    ).timeout(kTimeout);
    _parse(res);
  }

  static Future<void> deleteAccount(int id) async {
    final res = await _client
        .delete(_uri('/accounts/$id'), headers: _authHeaders)
        .timeout(kTimeout);
    _parse(res);
  }

  static Future<void> resetAccountPassword(int id, String newPassword) async {
    final res = await _client.post(
      _uri('/accounts/$id/reset-password'),
      headers: _authHeaders,
      body: jsonEncode({'new_password': newPassword}),
    ).timeout(kTimeout);
    _parse(res);
  }
}
