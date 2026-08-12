import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final crashlyticsServiceProvider = Provider<CrashlyticsService>((ref) {
  return CrashlyticsService();
});

class CrashlyticsService {
  final FirebaseCrashlytics _crashlytics = FirebaseCrashlytics.instance;

  Future<void> recordError(
    dynamic exception,
    StackTrace? stack, {
    dynamic reason,
    bool fatal = false,
  }) async {
    try {
      await _crashlytics.recordError(
        exception,
        stack,
        reason: reason,
        fatal: fatal,
      );
      debugPrint('Crashlytics: Recorded error. Fatal: $fatal. Reason: $reason');
    } catch (e) {
      debugPrint('Crashlytics: Failed to record error: $e');
    }
  }

  Future<void> recordFlutterError(FlutterErrorDetails details) async {
    try {
      await _crashlytics.recordFlutterError(details);
      debugPrint('Crashlytics: Recorded Flutter error: ${details.exceptionAsString()}');
    } catch (e) {
      debugPrint('Crashlytics: Failed to record Flutter error: $e');
    }
  }

  Future<void> setCustomKey(String key, Object value) async {
    try {
      if (value is String) {
        await _crashlytics.setCustomKey(key, value);
      } else if (value is int) {
        await _crashlytics.setCustomKey(key, value);
      } else if (value is double) {
        await _crashlytics.setCustomKey(key, value);
      } else if (value is bool) {
        await _crashlytics.setCustomKey(key, value);
      } else {
        await _crashlytics.setCustomKey(key, value.toString());
      }
      debugPrint('Crashlytics: Custom key "$key" set to "$value"');
    } catch (e) {
      debugPrint('Crashlytics: Failed to set custom key: $e');
    }
  }

  Future<void> setUserIdentifier(String userId) async {
    try {
      await _crashlytics.setUserIdentifier(userId);
      debugPrint('Crashlytics: User identifier set to "$userId"');
    } catch (e) {
      debugPrint('Crashlytics: Failed to set user identifier: $e');
    }
  }

  Future<void> logBreadcrumb(String message) async {
    try {
      await _crashlytics.log(message);
      debugPrint('Crashlytics: Breadcrumb: $message');
    } catch (e) {
      debugPrint('Crashlytics: Failed to log breadcrumb: $e');
    }
  }
}
