// lib/services/api_service.dart
//
// Single class that wraps every Flask endpoint.
// Throws ApiException on non-2xx responses so callers can show friendly errors.

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../models/session.dart';

// ---------------------------------------------------------------------------
// Custom exception
// ---------------------------------------------------------------------------

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? code;
  const ApiException(this.message, {this.statusCode, this.code});

  @override
  String toString() => message;
}

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

class ApiService {
  static final _client = http.Client();

  static Map<String, String> get _adminHeaders => {
        'Content-Type': 'application/json',
        'X-Admin-Key': kAdminKey,
      };

  static Map<String, String> get _publicHeaders => {
        'Content-Type': 'application/json',
      };

  // ---- helpers ----

  static dynamic _decode(http.Response res) {
    if (res.body.isEmpty) return <String, dynamic>{};
    try {
      return jsonDecode(res.body);
    } catch (_) {
      return res.body;
    }
  }

  static Never _throwForResponse(http.Response res, dynamic body) {
    if (body is Map) {
      final msg = body['message'] ?? body['error'] ?? 'Unknown error';
      throw ApiException(
        msg.toString(),
        statusCode: res.statusCode,
        code: body['code']?.toString(),
      );
    }
    throw ApiException(body.toString(), statusCode: res.statusCode);
  }

  static Map<String, dynamic> _parseMap(http.Response res) {
    final body = _decode(res);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return body as Map<String, dynamic>;
    }
    _throwForResponse(res, body);
  }

  static List<dynamic> _parseList(http.Response res) {
    final body = _decode(res);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return body as List<dynamic>;
    }
    _throwForResponse(res, body);
  }

  static Uri _uri(String path) => Uri.parse('$kApiBaseUrl$path');

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
    return _parseMap(res);
  }

  /// List all sessions (instructor dashboard).
  static Future<List<Session>> listSessions() async {
    final res = await _client
        .get(_uri('/sessions'), headers: _adminHeaders)
        .timeout(kTimeout);
    final list = _parseList(res);
    return list
        .map((j) => Session.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  /// Close a session (stop accepting submissions).
  static Future<void> closeSession(String sessionId) async {
    final res = await _client
        .post(_uri('/session/$sessionId/close'), headers: _adminHeaders)
        .timeout(kTimeout);
    _parseMap(res);
  }

  /// Re-open a closed session.
  static Future<void> openSession(String sessionId) async {
    final res = await _client
        .post(_uri('/session/$sessionId/open'), headers: _adminHeaders)
        .timeout(kTimeout);
    _parseMap(res);
  }

  /// Delete all records for a session (keep session itself).
  static Future<void> resetSession(String sessionId) async {
    final res = await _client
        .post(_uri('/session/$sessionId/reset'), headers: _adminHeaders)
        .timeout(kTimeout);
    _parseMap(res);
  }

  /// Get records + session info for a session.
  static Future<Map<String, dynamic>> getRecords(String sessionId) async {
    final res = await _client
        .get(_uri('/session/$sessionId/records'), headers: _adminHeaders)
        .timeout(kTimeout);
    return _parseMap(res);
  }

  /// Returns the export URL (open in browser / share).
  static String exportUrl(String sessionId) =>
      '$kApiBaseUrl/session/$sessionId/export';

  /// Download CSV contents using admin headers.
  static Future<String> exportCsv(String sessionId) async {
    final res = await _client
        .get(_uri('/session/$sessionId/export'), headers: _adminHeaders)
        .timeout(kTimeout);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return res.body;
    }
    _throwForResponse(res, _decode(res));
  }

  // -------------------------------------------------------------------------
  // Public — student
  // -------------------------------------------------------------------------

  /// Fetch session metadata (check if active, get geofence).
  static Future<Session> getSession(String sessionId) async {
    final res = await _client
        .get(_uri('/session/$sessionId'), headers: _publicHeaders)
        .timeout(kTimeout);
    return Session.fromJson(_parseMap(res));
  }

  /// Submit attendance. Throws ApiException on non-2xx responses. The backend
  /// may include structured ApiException.code values such as 'duplicate',
  /// 'outside_geofence', or 'session_closed'.
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
    _parseMap(res);
  }
}
