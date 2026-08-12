import 'package:sqflite/sqflite.dart';
import '../../../../core/utils/db_helper.dart';
import '../../../../core/utils/in_memory_db.dart' as import_in_memory_db;
import '../../../../core/constants/app_constants.dart';

abstract class HistoryLocalDataSource {
  Future<List<Map<String, dynamic>>> getHistoryLogs(String profileId);
}

class HistoryLocalDataSourceImpl implements HistoryLocalDataSource {
  final DbHelper dbHelper;

  HistoryLocalDataSourceImpl(this.dbHelper);

  @override
  Future<List<Map<String, dynamic>>> getHistoryLogs(String profileId) async {
    final db = await dbHelper.database;
    return await db.rawQuery('''
      SELECT
        l.date,
        s.time,
        l.status,
        l.taken_at,
        m.id as medicine_id,
        m.name as medicine_name,
        m.type as medicine_type
      FROM ${AppConstants.tableMedicineLog} l
      JOIN ${AppConstants.tableSchedules} s ON l.schedule_id = s.id
      JOIN ${AppConstants.tableMedicines} m ON s.medicine_id = m.id
      WHERE l.profile_id = ?
      ORDER BY l.date DESC, s.time DESC
    ''', [profileId]);
  }
}

class HistoryLocalDataSourceInMemory implements HistoryLocalDataSource {
  HistoryLocalDataSourceInMemory();

  @override
  Future<List<Map<String, dynamic>>> getHistoryLogs(String profileId) async {
    final List<Map<String, dynamic>> results = [];

    // Simulate join logic in-memory
    final logs = import_in_memory_db.InMemoryDb.medicineLogs
        .where((l) => l['profile_id'] == profileId)
        .toList();

    for (final log in logs) {
      final schedule = import_in_memory_db.InMemoryDb.schedules.firstWhere(
        (s) => s['id'] == log['schedule_id'],
        orElse: () => {},
      );
      if (schedule.isEmpty) continue;

      final medicine = import_in_memory_db.InMemoryDb.medicines.firstWhere(
        (m) => m['id'] == schedule['medicine_id'],
        orElse: () => {},
      );
      if (medicine.isEmpty) continue;

      results.add({
        'date': log['date'],
        'time': schedule['time'],
        'status': log['status'],
        'taken_at': log['taken_at'],
        'medicine_id': medicine['id'],
        'medicine_name': medicine['name'],
        'medicine_type': medicine['type'],
      });
    }

    // Sort by date DESC, then time DESC
    results.sort((a, b) {
      final compDate = (b['date'] as String).compareTo(a['date'] as String);
      if (compDate != 0) return compDate;
      return (b['time'] as String).compareTo(a['time'] as String);
    });

    return results;
  }
}
