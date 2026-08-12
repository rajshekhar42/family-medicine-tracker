import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../../home/data/datasources/home_local_datasource.dart';
import '../../data/datasources/settings_local_datasource.dart';
import '../../data/models/settings_model.dart';
import '../../../../core/utils/db_helper.dart';

class AutoSkipService {
  final HomeLocalDataSource homeLocalDataSource;
  final SettingsLocalDataSource settingsLocalDataSource;
  final Uuid uuid;

  AutoSkipService({
    required this.homeLocalDataSource,
    required this.settingsLocalDataSource,
    required this.uuid,
  });

  /// Check schedules for today and yesterday, marking missed doses past grace period as "skipped".
  Future<void> checkAndAutoSkipDoses({required String profileId}) async {
    try {
      // 1. Fetch settings to get the grace period minutes
      final settingsModel = await settingsLocalDataSource.getSettings(profileId);
      final graceMinutes = settingsModel?.gracePeriodMinutes ?? 30;

      final nowUtc = DateTime.now().toUtc();
      final todayStr = DateFormat('yyyy-MM-dd').format(nowUtc);
      final yesterdayStr = DateFormat('yyyy-MM-dd').format(nowUtc.subtract(const Duration(days: 1)));

      await _checkDate(profileId, todayStr, graceMinutes, nowUtc);
      await _checkDate(profileId, yesterdayStr, graceMinutes, nowUtc);
    } catch (e) {
      debugPrint('Auto-skip check failed: $e');
    }
  }

  Future<void> _checkDate(
    String profileId,
    String dateStr,
    int graceMinutes,
    DateTime nowUtc,
  ) async {
    final doses = await homeLocalDataSource.getScheduledDoses(
      profileId: profileId,
      date: dateStr,
    );

    for (final dose in doses) {
      // Skip if already logged (taken or skipped)
      if (dose.status != null) continue;

      // Construct absolute scheduled DateTime object in UTC
      final timeParts = dose.scheduledTime.split(':');
      final hour = int.parse(timeParts[0]);
      final minute = int.parse(timeParts[1]);
      
      final dateParts = dateStr.split('-');
      final year = int.parse(dateParts[0]);
      final month = int.parse(dateParts[1]);
      final day = int.parse(dateParts[2]);

      final scheduledDateTime = DateTime.utc(year, month, day, hour, minute);

      // Check if grace period has expired
      final difference = nowUtc.difference(scheduledDateTime);
      if (difference.inMinutes > graceMinutes) {
        debugPrint('Auto-skipping missed dose: ${dose.medicineName} scheduled at ${dose.scheduledTime} on $dateStr');
        
        await homeLocalDataSource.logDose(
          id: uuid.v4(),
          profileId: profileId,
          scheduleId: dose.scheduleId,
          date: dateStr,
          status: 'Skipped',
          takenAt: null,
          updatedAt: nowUtc.millisecondsSinceEpoch,
          isDirty: 1,
        );

        // TODO: Trigger background cloud sync immediately (implemented in Phase 7)
      }
    }
  }
}
