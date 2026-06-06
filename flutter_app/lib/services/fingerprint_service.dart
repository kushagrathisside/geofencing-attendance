// lib/services/fingerprint_service.dart
//
// Generates a stable device fingerprint using device_info_plus.
// On web: uses browser user-agent + screen size hash.
// On mobile: uses Android ID or iOS identifierForVendor.

// add crypto: ^3.0.3 if using
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

class FingerprintService {
  static final _plugin = DeviceInfoPlugin();

  static Future<String> getFingerprint() async {
    try {
      if (kIsWeb) {
        final info = await _plugin.webBrowserInfo;
        final raw = '${info.userAgent}|${info.vendor}|${info.platform}';
        // Simple hash via utf8 bytes (no crypto package needed for basic use)
        return _simpleHash(raw);
      }

      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          final info = await _plugin.androidInfo;
          return _simpleHash(info.id + info.model + info.brand);

        case TargetPlatform.iOS:
          final info = await _plugin.iosInfo;
          return _simpleHash(info.identifierForVendor ?? info.name);

        default:
          final info = await _plugin.deviceInfo;
          return _simpleHash(info.data.values.join('|'));
      }
    } catch (_) {
      // Fallback: timestamp-based (not stable across sessions, but better than nothing)
      return 'fallback-${DateTime.now().millisecondsSinceEpoch}';
    }
  }

  /// Very simple non-crypto hash (good enough for anti-double-submit)
  static String _simpleHash(String input) {
    var hash = 0;
    for (final c in input.runes) {
      hash = (hash * 31 + c) & 0x7FFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}
