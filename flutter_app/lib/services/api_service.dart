// lib/services/api_service.dart
//
// Single class that wraps every Flask endpoint.
// Throws ApiException on non-2xx responses so callers can show friendly errors.

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import '../config.dart';
import '../models/session.dart';
import '../models/attendance_record.dart';

// ---------------------------------------------------------------------------
// Custom exception
// ---------------------------------------------------------------------------

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  const ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

class ApiService {
  // Accepts self-signed SSL certificates (needed for local HTTPS with pyopenssl)
  static final _client = IOClient(
    HttpClient()..badCertificateCallback = (cert, host, port) => true,
  );

  static Map<String, String> get _adminHeaders => {
        'Content-Type': 'application/json',
        'X-Admin-Key': kAdminKey,
      };

  static Map<String, String> get _publicHeaders => {
        'Content-Type': 'application/json',
      };

  // ---- helpers ----

  static Map<String, dynamic> _parse(http.Response res) {
    final body = jsonDecode(res.body);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return body as Map<String, dynamic>;
    }
    final msg = (body as Map)['message'] ?? body['error'] ?? 'Unknown error';
    throw ApiException(msg.toString(), statusCode: res.statusCode);
  }

  static Uri _uri(String path) => Uri.parse('$kBaseUrl$path');

  // -------------------------------------------------------------------------
  // Instructor — session management
  // -------------------------------------------------------------------------

  /// Create a new session. Returns { session_id, link, course_name }.
  static Future<Map<String, dynamic>> createSession({
    required String courseName,
    double? geoLat,
    double? geoLon,
    double geoRadius = 100,
  }) async {
    final res = await _client
        .post(
          _uri('/session/new'),
          headers: _adminHeaders,
          body: jsonEncode({
            'course_name': courseName,
            if (geoLat != null) 'geo_lat': geoLat,
            if (geoLon != null) 'geo_lon': geoLon,
            'geo_radius': geoRadius,
          }),
        )
        .timeout(kTimeout);
    return _parse(res);
  }

  /// List all sessions (instructor dashboard).
  static Future<List<Session>> listSessions() async {
    final res = await _client
        .get(_uri('/sessions'), headers: _adminHeaders)
        .timeout(kTimeout);
    final list = jsonDecode(res.body) as List;
    return list
        .map((j) => Session.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  /// Close a session (stop accepting submissions).
  static Future<void> closeSession(String sessionId) async {
    final res = await _client
        .post(_uri('/session/$sessionId/close'), headers: _adminHeaders)
        .timeout(kTimeout);
    _parse(res);
  }

  /// Re-open a closed session.
  static Future<void> openSession(String sessionId) async {
    final res = await _client
        .post(_uri('/session/$sessionId/open'), headers: _adminHeaders)
        .timeout(kTimeout);
    _parse(res);
  }

  /// Delete all records for a session (keep session itself).
  static Future<void> resetSession(String sessionId) async {
    final res = await _client
        .post(_uri('/session/$sessionId/reset'), headers: _adminHeaders)
        .timeout(kTimeout);
    _parse(res);
  }

  /// Get records + session info for a session.
  static Future<Map<String, dynamic>> getRecords(String sessionId) async {
    final res = await _client
        .get(_uri('/session/$sessionId/records'), headers: _adminHeaders)
        .timeout(kTimeout);
    return _parse(res);
  }

  /// Returns the export URL (open in browser / share).
  static String exportUrl(String sessionId) =>
      '$kBaseUrl/session/$sessionId/export';

  // -------------------------------------------------------------------------
  // Public — student
  // -------------------------------------------------------------------------

  /// Fetch session metadata (check if active, get geofence).
  static Future<Session> getSession(String sessionId) async {
    final res = await _client
        .get(_uri('/session/$sessionId'), headers: _publicHeaders)
        .timeout(kTimeout);
    return Session.fromJson(_parse(res));
  }

  /// Submit attendance. Throws ApiException with error key for
  /// 'duplicate' and 'outside_geofence' so UI can show specific messages.
  static Future<void> submitAttendance({
    required String sessionId,
    required String name,
    required String rollNo,
    required String fingerprint,
    required double latitude,
    required double longitude,
    String comments = '',
  }) async {
    final res = await _client
        .post(
          _uri('/session/$sessionId/submit'),
          headers: _publicHeaders,
          body: jsonEncode({
            'name': name,
            'roll_no': rollNo,
            'fingerprint': fingerprint,
            'latitude': latitude,
            'longitude': longitude,
            'comments': comments,
          }),
        )
        .timeout(kTimeout);
    _parse(res);
  }
}