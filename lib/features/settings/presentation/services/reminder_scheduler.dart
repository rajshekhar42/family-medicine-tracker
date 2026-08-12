import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/utils/db_helper.dart';
import '../../../profiles/presentation/providers/active_profile_provider.dart';
import '../providers/settings_provider.dart';
import 'notification_service.dart';

final reminderSchedulerProvider = Provider<ReminderScheduler>((ref) {
  return ReminderScheduler(ref);
});

class ReminderScheduler {
  final Ref _ref;
  ReminderScheduler(this._ref);

  Future<void> rescheduleAll() async {
    if (kIsWeb) {
      debugPrint('ReminderScheduler: Skip scheduling on Web');
      return;
    }

    try {
      // 1. Cancel all existing reminders
      await NotificationService.instance.cancelAll();

      // 2. Read active profile
      final activeProfile = _ref.read(activeProfileProvider);
      if (activeProfile == null) {
        debugPrint('ReminderScheduler: No active profile found.');
        return;
      }

      // 3. Read AppSettings
      final settingsState = _ref.read(settingsStateProvider);
      final settings = settingsState.valueOrNull;
      if (settings == null) {
        debugPrint('ReminderScheduler: App settings not loaded.');
        return;
      }

      if (!settings.remindersEnabled) {
        debugPrint('ReminderScheduler: Reminders disabled in settings.');
        return;
      }

      // 4. Query active medicines and schedules
      final db = await DbHelper.instance.database;
      final List<Map<String, dynamic>> medicines = await db.query(
        AppConstants.tableMedicines,
        where: 'profile_id = ? AND active = 1',
        whereArgs: [activeProfile.id],
      );

      final now = DateTime.now();
      final todayStr = DateFormat('yyyy-MM-dd').format(now);

      for (final medMap in medicines) {
        final medId = medMap['id'] as String;
        final medName = medMap['name'] as String;

        final List<Map<String, dynamic>> schedules = await db.query(
          AppConstants.tableSchedules,
          where: 'medicine_id = ?',
          whereArgs: [medId],
        );

        for (final schedMap in schedules) {
          final schedId = schedMap['id'] as String;
          final timeHHmm = schedMap['time'] as String;

          // Check if already taken or skipped today
          final List<Map<String, dynamic>> logs = await db.query(
            AppConstants.tableMedicineLog,
            where: 'schedule_id = ? AND date = ?',
            whereArgs: [schedId, todayStr],
          );

          final timeParts = timeHHmm.split(':');
          if (timeParts.length < 2) continue;
          final hour = int.parse(timeParts[0]);
          final minute = int.parse(timeParts[1]);

          var targetDate = DateTime(now.year, now.month, now.day, hour, minute);

          // If the scheduled time has already passed today, or if it was already logged today, schedule starting tomorrow
          if (targetDate.isBefore(now) || logs.isNotEmpty) {
            targetDate = targetDate.add(const Duration(days: 1));
          }

          // Generate a unique integer notification ID for this medicine+schedule combination
          final int notificationId = (medId.hashCode ^ schedId.hashCode).abs() % 100000;

          await NotificationService.instance.scheduleReminder(
            id: notificationId,
            title: 'Time for $medName',
            body: 'Scheduled dose at $timeHHmm',
            scheduledDateTime: targetDate,
            playSound: settings.soundEnabled,
          );
        }
      }
      debugPrint('ReminderScheduler: Successfully rescheduled all active reminders.');
    } catch (e, stack) {
      debugPrint('ReminderScheduler: Error rescheduling: $e\n$stack');
    }
  }
}
