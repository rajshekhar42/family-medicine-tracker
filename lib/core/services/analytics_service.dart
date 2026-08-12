import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final analyticsServiceProvider = Provider<AnalyticsService>((ref) {
  return AnalyticsService();
});

class AnalyticsService {
  final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  Future<void> logEvent({
    required String name,
    Map<String, Object>? parameters,
  }) async {
    try {
      await _analytics.logEvent(name: name, parameters: parameters);
      debugPrint('Analytics: Event "$name" logged with parameters: $parameters');
    } catch (e, stack) {
      debugPrint('Analytics: Failed to log event "$name": $e\n$stack');
    }
  }

  Future<void> setUserId(String? userId) async {
    try {
      await _analytics.setUserId(id: userId);
      debugPrint('Analytics: User ID set to "$userId"');
    } catch (e) {
      debugPrint('Analytics: Failed to set User ID: $e');
    }
  }

  Future<void> setUserProperty({
    required String name,
    required String value,
  }) async {
    try {
      await _analytics.setUserProperty(name: name, value: value);
      debugPrint('Analytics: User property "$name" set to "$value"');
    } catch (e) {
      debugPrint('Analytics: Failed to set user property "$name": $e');
    }
  }

  Future<void> logOnboardingCompleted(String profileId, String timeZone) async {
    await logEvent(
      name: 'onboarding_completed',
      parameters: {
        'profile_id': profileId,
        'timezone': timeZone,
      },
    );
  }

  Future<void> logFamilyMemberAdded(String profileId, String timeZone, bool isSynced) async {
    await logEvent(
      name: 'family_member_added',
      parameters: {
        'profile_id': profileId,
        'timezone': timeZone,
        'is_synced': isSynced ? 1 : 0,
      },
    );
  }

  Future<void> logMedicationAdded(String medicineId, String type, int frequencyCount) async {
    await logEvent(
      name: 'medication_added',
      parameters: {
        'medicine_id': medicineId,
        'medicine_type': type,
        'frequency_count': frequencyCount,
      },
    );
  }

  Future<void> logMedicationUpdated(String medicineId, String type, int frequencyCount) async {
    await logEvent(
      name: 'medication_updated',
      parameters: {
        'medicine_id': medicineId,
        'medicine_type': type,
        'frequency_count': frequencyCount,
      },
    );
  }

  Future<void> logDoseStatusChanged(
    String medicineId,
    String scheduleId,
    String status,
    String scheduledTime,
  ) async {
    await logEvent(
      name: 'dose_status_changed',
      parameters: {
        'medicine_id': medicineId,
        'schedule_id': scheduleId,
        'status': status,
        'scheduled_time': scheduledTime,
      },
    );
  }

  Future<void> logSyncStarted(String role, String type) async {
    await logEvent(
      name: 'sync_started',
      parameters: {
        'role': role,
        'type': type,
      },
    );
  }

  Future<void> logSyncFinished(
    String role,
    String type,
    bool isSuccess, {
    int? durationMs,
    int? recordsCount,
    String? error,
  }) async {
    final params = <String, Object>{
      'role': role,
      'type': type,
      'is_success': isSuccess ? 1 : 0,
    };
    if (durationMs != null) params['duration_ms'] = durationMs;
    if (recordsCount != null) params['records_count'] = recordsCount;
    if (error != null) params['error'] = error.length > 100 ? error.substring(0, 100) : error;

    await logEvent(name: 'sync_finished', parameters: params);
  }

  Future<void> logAuthEvent(String eventName, {String? error}) async {
    final params = <String, Object>{};
    if (error != null) params['error'] = error.length > 100 ? error.substring(0, 100) : error;
    await logEvent(name: eventName, parameters: params);
  }
}
