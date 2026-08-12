import 'package:intl/intl.dart';

/// Abstract Clock interface to make time testable in use cases and repositories.
abstract class Clock {
  DateTime now();
}

class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now().toUtc();
}

class DateTimeUtils {
  DateTimeUtils._();

  static const String dateFormat = 'dd-MMM-yy'; // E.g. 01-Jul-26 matching requirements Section 7
  static const String timeFormat = 'h:mm a'; // E.g. 10:05 AM matching requirements Section 7

  /// Formats UTC timestamp in millis to date string: '01-Jul-26'
  static String formatDate(int timestampMillis) {
    final dateTime = DateTime.fromMillisecondsSinceEpoch(timestampMillis, isUtc: true).toLocal();
    return DateFormat(dateFormat).format(dateTime);
  }

  /// Formats UTC timestamp in millis to time string: '10:05 AM'
  static String formatTime(int timestampMillis) {
    final dateTime = DateTime.fromMillisecondsSinceEpoch(timestampMillis, isUtc: true).toLocal();
    return DateFormat(timeFormat).format(dateTime);
  }

  /// Formats a time string (HH:mm) into a user display format: '10:00 AM'
  static String formatTimeString(String time24h) {
    try {
      final parts = time24h.split(':');
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      final tempDate = DateTime(2026, 1, 1, hour, minute);
      return DateFormat(timeFormat).format(tempDate);
    } catch (_) {
      return time24h;
    }
  }

  /// Parses date string '01-Jul-26' to UTC timestamp in millis
  static int? parseDateToMillis(String dateStr) {
    try {
      final parsed = DateFormat(dateFormat).parseUtc(dateStr);
      return parsed.millisecondsSinceEpoch;
    } catch (_) {
      return null;
    }
  }

  /// Converts UTC DateTime to target timezone offset/location name
  /// Note: Real implementation would use package:timezone for full locations.
  /// For this base utility, we fallback to standard formatting.
  static String formatToLocalTimeZone(DateTime utcDateTime, String timeZoneName) {
    // Standard local fallback
    final localDateTime = utcDateTime.toLocal();
    return DateFormat('$dateFormat $timeFormat').format(localDateTime);
  }

  /// Returns midnight UTC for a given DateTime
  static DateTime getUtcStartOfDay(DateTime dateTime) {
    return DateTime.utc(dateTime.year, dateTime.month, dateTime.day);
  }

  /// Formats yyyy-MM-dd date string from millisecond timestamp
  static String formatDbDate(int timestampMillis) {
    final dateTime = DateTime.fromMillisecondsSinceEpoch(timestampMillis, isUtc: true);
    return DateFormat('yyyy-MM-dd').format(dateTime);
  }
}
