import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final NotificationService instance = NotificationService._();
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  NotificationService._();

  Future<void> init() async {
    // 1. Initialize timezone database for location-based schedules
    tz.initializeTimeZones();

    // 2. Platform initialization settings
    const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    
    final DarwinInitializationSettings darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      onDidReceiveLocalNotification: (id, title, body, payload) async {},
    );

    final InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    // 3. Initialize plugin
    try {
      await _notificationsPlugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (details) {
          debugPrint('Notification clicked: ${details.payload}');
        },
      );
      
      // Request permissions for Android 13+
      if (!kIsWeb) {
        final androidImplementation = _notificationsPlugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        if (androidImplementation != null) {
          await androidImplementation.requestNotificationsPermission();
          try {
            final bool? exactAlarmsGranted = await androidImplementation.requestExactAlarmsPermission();
            debugPrint('Notification Service: Exact alarms permission status: $exactAlarmsGranted');
          } catch (e) {
            debugPrint('Notification Service: Failed to request exact alarms permission: $e');
          }
        }
      }

      // Configure local timezone using flutter_timezone
      if (!kIsWeb) {
        final timezoneInfo = await FlutterTimezone.getLocalTimezone();
        final String timeZoneName = timezoneInfo.identifier;
        tz.setLocalLocation(tz.getLocation(timeZoneName));
        debugPrint('Notification Service: Timezone initialized as $timeZoneName');
      }

      debugPrint('Notification Service initialized successfully.');
    } catch (e) {
      debugPrint('Notification Service initialization warning: $e');
    }
  }

  Future<void> scheduleReminder({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDateTime,
    bool playSound = true,
  }) async {
    if (kIsWeb) return;

    try {
      final tz.TZDateTime tzScheduleDate = tz.TZDateTime.from(scheduledDateTime, tz.local);

      final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'med_reminders_channel_v3',
        'Medication Reminders',
        channelDescription: 'Alerts for scheduled medication times',
        importance: Importance.max,
        priority: Priority.high,
        playSound: playSound,
      );

      final DarwinNotificationDetails darwinDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: playSound,
      );

      final NotificationDetails notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
        macOS: darwinDetails,
      );

      await _notificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        tzScheduleDate,
        notificationDetails,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time, // Repeat daily at the same time
      );
      final formattedTime = '${scheduledDateTime.hour.toString().padLeft(2, '0')}:${scheduledDateTime.minute.toString().padLeft(2, '0')}';
      debugPrint('Scheduled notification ID $id for "$title" at $formattedTime (playSound: $playSound)');
    } catch (e) {
      debugPrint('Failed to schedule notification: $e');
    }
  }

  Future<void> cancelReminder(int id) async {
    if (kIsWeb) return;
    try {
      await _notificationsPlugin.cancel(id);
    } catch (e) {
      debugPrint('Failed to cancel notification: $e');
    }
  }

  Future<void> cancelAll() async {
    if (kIsWeb) return;
    try {
      await _notificationsPlugin.cancelAll();
      debugPrint('Cancelled all scheduled notifications.');
    } catch (e) {
      debugPrint('Failed to cancel all notifications: $e');
    }
  }

  Future<List<PendingNotificationRequest>> getPendingReminders() async {
    if (kIsWeb) return [];
    try {
      return await _notificationsPlugin.pendingNotificationRequests();
    } catch (e) {
      debugPrint('Failed to get pending notification requests: $e');
      return [];
    }
  }

  Future<void> scheduleTestNotification() async {
    if (kIsWeb) return;
    try {
      final scheduledDateTime = DateTime.now().add(const Duration(seconds: 5));
      final tz.TZDateTime tzScheduleDate = tz.TZDateTime.from(scheduledDateTime, tz.local);

      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'med_reminders_channel_v3',
        'Medication Reminders',
        channelDescription: 'Alerts for scheduled medication times',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
      );

      const DarwinNotificationDetails darwinDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const NotificationDetails notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
        macOS: darwinDetails,
      );

      await _notificationsPlugin.zonedSchedule(
        99999,
        'Test Notification (Scheduled)',
        'This is a test notification scheduled 5 seconds ago using AlarmManager.',
        tzScheduleDate,
        notificationDetails,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
      debugPrint('Scheduled test notification for $scheduledDateTime');
    } catch (e) {
      debugPrint('Failed to schedule test notification: $e');
    }
  }

  Future<bool> checkExactAlarmPermission() async {
    if (kIsWeb) return false;
    try {
      final androidImplementation = _notificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      return await androidImplementation?.canScheduleExactNotifications() ?? false;
    } catch (e) {
      debugPrint('Failed to check exact alarm permission: $e');
      return false;
    }
  }
}
