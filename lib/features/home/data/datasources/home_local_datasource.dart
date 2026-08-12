import 'package:sqflite/sqflite.dart';
import 'package:intl/intl.dart';
import '../../../../core/utils/db_helper.dart';
import '../../../../core/utils/in_memory_db.dart' as import_in_memory_db;
import '../../../../core/constants/app_constants.dart';
import '../models/scheduled_dose_model.dart';

abstract class HomeLocalDataSource {
  Future<List<ScheduledDoseModel>> getScheduledDoses({
    required String profileId,
    required String date,
  });

  Future<void> logDose({
    required String id,
    required String profileId,
    required String scheduleId,
    required String date,
    required String status,
    int? takenAt,
    required int updatedAt,
    required int isDirty,
  });

  Future<Map<String, dynamic>?> getScheduledDoseRow({
    required String scheduleId,
    required String date,
  });
}

class HomeLocalDataSourceImpl implements HomeLocalDataSource {
  final DbHelper dbHelper;

  HomeLocalDataSourceImpl(this.dbHelper);

  @override
  Future<List<ScheduledDoseModel>> getScheduledDoses({
    required String profileId,
    required String date,
  }) async {
    final db = await dbHelper.database;
    
    // Select all active schedules for the profile
    final List<Map<String, dynamic>> results = await db.rawQuery('''
      SELECT
        s.id as schedule_id,
        s.medicine_id,
        s.time,
        m.name,
        m.type,
        m.dosage_value,
        m.dosage_unit,
        m.quantity_value,
        m.quantity_unit,
        m.frequency,
        m.start_date,
        m.end_date,
        l.id as log_id,
        l.status,
        l.taken_at
      FROM ${AppConstants.tableSchedules} s
      JOIN ${AppConstants.tableMedicines} m ON s.medicine_id = m.id
      LEFT JOIN ${AppConstants.tableMedicineLog} l ON s.id = l.schedule_id AND l.date = ?
      WHERE s.profile_id = ? AND m.active = 1
    ''', [date, profileId]);

    final List<ScheduledDoseModel> list = [];
    final targetLocal = DateFormat('yyyy-MM-dd').parse(date);
    final targetDate = DateTime.utc(targetLocal.year, targetLocal.month, targetLocal.day);

    for (final row in results) {
      // Filter by start and end dates
      final startDateMillis = row['start_date'] as int;
      final startRaw = DateTime.fromMillisecondsSinceEpoch(startDateMillis, isUtc: true);
      final startDate = DateTime.utc(startRaw.year, startRaw.month, startRaw.day);
      
      final endDateMillis = row['end_date'] as int?;
      DateTime? endDate;
      if (endDateMillis != null) {
        final endRaw = DateTime.fromMillisecondsSinceEpoch(endDateMillis, isUtc: true);
        endDate = DateTime.utc(endRaw.year, endRaw.month, endRaw.day);
      }

      // Check if targetDate is out of medicine schedule range
      if (targetDate.isBefore(startDate)) {
        continue;
      }
      if (endDate != null && targetDate.isAfter(endDate)) {
        continue;
      }

      // Filter by frequency rules
      final frequency = row['frequency'] as String;
      if (_matchesFrequency(targetDate, startDate, frequency)) {
        list.add(ScheduledDoseModel.fromMap(row, date));
      }
    }

    return list;
  }

  @override
  Future<void> logDose({
    required String id,
    required String profileId,
    required String scheduleId,
    required String date,
    required String status,
    int? takenAt,
    required int updatedAt,
    required int isDirty,
  }) async {
    final db = await dbHelper.database;
    
    // Check if an existing log exists for this schedule_id and date
    final List<Map<String, dynamic>> existing = await db.query(
      AppConstants.tableMedicineLog,
      where: 'schedule_id = ? AND date = ?',
      whereArgs: [scheduleId, date],
    );

    if (existing.isNotEmpty) {
      final existingId = existing.first['id'] as String;
      
      // Update the first existing log, preserving its ID
      await db.update(
        AppConstants.tableMedicineLog,
        {
          'status': status,
          'taken_at': takenAt,
          'updated_at': updatedAt,
          'is_dirty': isDirty,
        },
        where: 'id = ?',
        whereArgs: [existingId],
      );

      // Clean up any extra duplicates that might have been created previously
      if (existing.length > 1) {
        await db.delete(
          AppConstants.tableMedicineLog,
          where: 'schedule_id = ? AND date = ? AND id != ?',
          whereArgs: [scheduleId, date, existingId],
        );
      }
    } else {
      // Insert new log using the generated ID
      await db.insert(
        AppConstants.tableMedicineLog,
        {
          'id': id,
          'profile_id': profileId,
          'schedule_id': scheduleId,
          'date': date,
          'status': status,
          'taken_at': takenAt,
          'updated_at': updatedAt,
          'is_dirty': isDirty,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  @override
  Future<Map<String, dynamic>?> getScheduledDoseRow({
    required String scheduleId,
    required String date,
  }) async {
    final db = await dbHelper.database;
    final List<Map<String, dynamic>> results = await db.rawQuery('''
      SELECT
        s.id as schedule_id,
        s.medicine_id,
        s.time,
        m.name,
        m.type,
        m.dosage_value,
        m.dosage_unit,
        m.quantity_value,
        m.quantity_unit,
        m.frequency,
        l.id as log_id,
        l.status,
        l.taken_at
      FROM ${AppConstants.tableSchedules} s
      JOIN ${AppConstants.tableMedicines} m ON s.medicine_id = m.id
      LEFT JOIN ${AppConstants.tableMedicineLog} l ON s.id = l.schedule_id AND l.date = ?
      WHERE s.id = ?
      LIMIT 1
    ''', [date, scheduleId]);

    if (results.isNotEmpty) {
      return results.first;
    }
    return null;
  }

  bool _matchesFrequency(DateTime targetDate, DateTime startDate, String frequency) {
    final cleanFreq = frequency.toLowerCase();
    
    // 1. Daily variations ("once a day", "2 times, daily", etc.)
    if (cleanFreq.contains('day') || cleanFreq.contains('daily')) {
      return true;
    }

    // 2. Weekly variations ("once a week", "x times a week", etc.)
    if (cleanFreq.contains('week')) {
      // Repeat on the same weekday as the start_date (difference in days is multiple of 7)
      final diff = targetDate.difference(startDate);
      final differenceInDays = (diff.inHours / 24.0).round();
      return differenceInDays % 7 == 0;
    }

    // 3. Monthly variations ("once a month", "x times a month", etc.)
    if (cleanFreq.contains('month')) {
      // Repeat on the same day number of the month
      return targetDate.day == startDate.day;
    }

    return true; // Default fallback to daily
  }
}

class HomeLocalDataSourceInMemory implements HomeLocalDataSource {
  HomeLocalDataSourceInMemory();

  @override
  Future<List<ScheduledDoseModel>> getScheduledDoses({
    required String profileId,
    required String date,
  }) async {
    final targetLocal = DateFormat('yyyy-MM-dd').parse(date);
    final targetDate = DateTime.utc(targetLocal.year, targetLocal.month, targetLocal.day);
    final List<ScheduledDoseModel> list = [];

    // Filter schedules
    final profileSchedules = import_in_memory_db.InMemoryDb.schedules.where((s) => s['profile_id'] == profileId).toList();

    for (final s in profileSchedules) {
      final medId = s['medicine_id'] as String;
      // Find active medicine matching medId
      final medList = import_in_memory_db.InMemoryDb.medicines.where((m) => m['id'] == medId && m['active'] == 1).toList();
      if (medList.isEmpty) continue;
      
      final m = medList.first;
      final startDateMillis = m['start_date'] as int;
      final startRaw = DateTime.fromMillisecondsSinceEpoch(startDateMillis, isUtc: true);
      final startDate = DateTime.utc(startRaw.year, startRaw.month, startRaw.day);
      
      final endDateMillis = m['end_date'] as int?;
      DateTime? endDate;
      if (endDateMillis != null) {
        final endRaw = DateTime.fromMillisecondsSinceEpoch(endDateMillis, isUtc: true);
        endDate = DateTime.utc(endRaw.year, endRaw.month, endRaw.day);
      }

      // Check date bounds
      if (targetDate.isBefore(startDate)) continue;
      if (endDate != null && targetDate.isAfter(endDate)) continue;

      // Check frequency
      final frequency = m['frequency'] as String;
      if (_matchesFrequency(targetDate, startDate, frequency)) {
        // Find log
        final logs = import_in_memory_db.InMemoryDb.medicineLogs.where((l) => l['schedule_id'] == s['id'] && l['date'] == date).toList();
        final Map<String, dynamic> row = {
          'schedule_id': s['id'],
          'medicine_id': medId,
          'time': s['time'],
          'name': m['name'],
          'type': m['type'],
          'dosage_value': m['dosage_value'],
          'dosage_unit': m['dosage_unit'],
          'quantity_value': m['quantity_value'],
          'quantity_unit': m['quantity_unit'],
          'frequency': frequency,
          'start_date': m['start_date'],
          'end_date': m['end_date'],
          'log_id': logs.isNotEmpty ? logs.first['id'] : null,
          'status': logs.isNotEmpty ? logs.first['status'] : null,
          'taken_at': logs.isNotEmpty ? logs.first['taken_at'] : null,
        };
        list.add(ScheduledDoseModel.fromMap(row, date));
      }
    }
    return list;
  }

  @override
  Future<void> logDose({
    required String id,
    required String profileId,
    required String scheduleId,
    required String date,
    required String status,
    int? takenAt,
    required int updatedAt,
    required int isDirty,
  }) async {
    // Remove existing log if any
    import_in_memory_db.InMemoryDb.medicineLogs.removeWhere((l) => l['schedule_id'] == scheduleId && l['date'] == date);

    // Insert new
    import_in_memory_db.InMemoryDb.medicineLogs.add({
      'id': id,
      'profile_id': profileId,
      'schedule_id': scheduleId,
      'date': date,
      'status': status,
      'taken_at': takenAt,
      'updated_at': updatedAt,
      'is_dirty': isDirty,
    });
  }

  @override
  Future<Map<String, dynamic>?> getScheduledDoseRow({
    required String scheduleId,
    required String date,
  }) async {
    final schedules = import_in_memory_db.InMemoryDb.schedules.where((s) => s['id'] == scheduleId).toList();
    if (schedules.isEmpty) return null;
    
    final s = schedules.first;
    final medId = s['medicine_id'] as String;
    
    final medicines = import_in_memory_db.InMemoryDb.medicines.where((m) => m['id'] == medId).toList();
    if (medicines.isEmpty) return null;
    
    final m = medicines.first;
    final logs = import_in_memory_db.InMemoryDb.medicineLogs.where((l) => l['schedule_id'] == scheduleId && l['date'] == date).toList();

    return {
      'schedule_id': s['id'],
      'medicine_id': medId,
      'time': s['time'],
      'name': m['name'],
      'type': m['type'],
      'dosage_value': m['dosage_value'],
      'dosage_unit': m['dosage_unit'],
      'quantity_value': m['quantity_value'],
      'quantity_unit': m['quantity_unit'],
      'frequency': m['frequency'],
      'log_id': logs.isNotEmpty ? logs.first['id'] : null,
      'status': logs.isNotEmpty ? logs.first['status'] : null,
      'taken_at': logs.isNotEmpty ? logs.first['taken_at'] : null,
    };
  }

  bool _matchesFrequency(DateTime targetDate, DateTime startDate, String frequency) {
    final cleanFreq = frequency.toLowerCase();
    if (cleanFreq.contains('day') || cleanFreq.contains('daily')) return true;
    
    if (cleanFreq.contains('week')) {
      final diff = targetDate.difference(startDate);
      final differenceInDays = (diff.inHours / 24.0).round();
      return differenceInDays % 7 == 0;
    }
    
    if (cleanFreq.contains('month')) {
      return targetDate.day == startDate.day;
    }
    return true;
  }
}
