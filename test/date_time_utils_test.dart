import 'package:flutter_test/flutter_test.dart';
import 'package:family_medicine_tracker/core/utils/date_time_utils.dart';

void main() {
  group('DateTimeUtils Unit Tests', () {
    test('formatTime parses epoch milliseconds to h:mm a format', () {
      final millis = DateTime(2024, 6, 10, 9, 0).millisecondsSinceEpoch;
      final formatted = DateTimeUtils.formatTime(millis);
      expect(formatted, contains(RegExp(r'AM|PM')));
    });

    test('formatDate parses milliseconds to dd-MMM-yy format', () {
      final millis = DateTime(2024, 6, 10).millisecondsSinceEpoch;
      final formatted = DateTimeUtils.formatDate(millis);
      expect(formatted, equals('10-Jun-24'));
    });

    test('formatTimeString converts 24h string to 12h format', () {
      expect(DateTimeUtils.formatTimeString('09:00'), equals('9:00 AM'));
      expect(DateTimeUtils.formatTimeString('14:30'), equals('2:30 PM'));
      expect(DateTimeUtils.formatTimeString('00:15'), equals('12:15 AM'));
    });

    test('parseDateToMillis converts dd-MMM-yy string to UTC milliseconds', () {
      final dateStr = '10-Jun-24';
      final millis = DateTimeUtils.parseDateToMillis(dateStr);
      final expected = DateTime.utc(2024, 6, 10).millisecondsSinceEpoch;
      expect(millis, equals(expected));
    });
  });
}
