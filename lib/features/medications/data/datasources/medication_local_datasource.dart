import 'package:sqflite/sqflite.dart';
import '../../../../core/utils/db_helper.dart';
import '../../../../core/utils/in_memory_db.dart' as import_in_memory_db;
import '../../../../core/constants/app_constants.dart';
import '../models/medicine_model.dart';
import '../models/schedule_model.dart';

abstract class MedicationLocalDataSource {
  Future<void> saveMedication({
    required MedicineModel medicine,
    required List<ScheduleModel> schedules,
  });

  Future<void> updateMedication({
    required MedicineModel medicine,
    required List<ScheduleModel> schedules,
  });

  Future<List<MedicineModel>> getAllMedications(String profileId);

  Future<List<ScheduleModel>> getSchedulesForMedicine(String medicineId);
}

class MedicationLocalDataSourceImpl implements MedicationLocalDataSource {
  final DbHelper dbHelper;

  MedicationLocalDataSourceImpl(this.dbHelper);

  @override
  Future<void> saveMedication({
    required MedicineModel medicine,
    required List<ScheduleModel> schedules,
  }) async {
    final db = await dbHelper.database;
    
    // Execute inside a Transaction to ensure both write operations succeed
    await db.transaction((txn) async {
      await txn.insert(
        AppConstants.tableMedicines,
        medicine.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      for (final schedule in schedules) {
        await txn.insert(
          AppConstants.tableSchedules,
          schedule.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  @override
  Future<void> updateMedication({
    required MedicineModel medicine,
    required List<ScheduleModel> schedules,
  }) async {
    final db = await dbHelper.database;
    
    await db.transaction((txn) async {
      // 1. Update medicine details
      await txn.update(
        AppConstants.tableMedicines,
        medicine.toMap(),
        where: 'id = ?',
        whereArgs: [medicine.id],
      );

      // 2. Delete old schedules
      await txn.delete(
        AppConstants.tableSchedules,
        where: 'medicine_id = ?',
        whereArgs: [medicine.id],
      );

      // 3. Insert new schedules
      for (final schedule in schedules) {
        await txn.insert(
          AppConstants.tableSchedules,
          schedule.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  @override
  Future<List<MedicineModel>> getAllMedications(String profileId) async {
    final db = await dbHelper.database;
    final results = await db.query(
      AppConstants.tableMedicines,
      where: 'profile_id = ?',
      whereArgs: [profileId],
      orderBy: 'name ASC',
    );

    return results.map((map) => MedicineModel.fromMap(map)).toList();
  }

  @override
  Future<List<ScheduleModel>> getSchedulesForMedicine(String medicineId) async {
    final db = await dbHelper.database;
    final results = await db.query(
      AppConstants.tableSchedules,
      where: 'medicine_id = ?',
      whereArgs: [medicineId],
    );

    return results.map((map) => ScheduleModel.fromMap(map)).toList();
  }
}

class MedicationLocalDataSourceInMemory implements MedicationLocalDataSource {
  MedicationLocalDataSourceInMemory();

  @override
  Future<void> saveMedication({
    required MedicineModel medicine,
    required List<ScheduleModel> schedules,
  }) async {
    // Save medicine map representation
    import_in_memory_db.InMemoryDb.medicines.add(medicine.toMap());

    // Save schedules
    for (final s in schedules) {
      import_in_memory_db.InMemoryDb.schedules.add(s.toMap());
    }
  }

  @override
  Future<void> updateMedication({
    required MedicineModel medicine,
    required List<ScheduleModel> schedules,
  }) async {
    // 1. Remove old medicine
    import_in_memory_db.InMemoryDb.medicines.removeWhere((m) => m['id'] == medicine.id);
    import_in_memory_db.InMemoryDb.medicines.add(medicine.toMap());

    // 2. Remove old schedules
    import_in_memory_db.InMemoryDb.schedules.removeWhere((s) => s['medicine_id'] == medicine.id);

    // 3. Add new schedules
    for (final s in schedules) {
      import_in_memory_db.InMemoryDb.schedules.add(s.toMap());
    }
  }

  @override
  Future<List<MedicineModel>> getAllMedications(String profileId) async {
    final list = import_in_memory_db.InMemoryDb.medicines.where((m) => m['profile_id'] == profileId).toList();
    // Sort chronologically/alphabetically by name
    list.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
    return list.map((map) => MedicineModel.fromMap(map)).toList();
  }

  @override
  Future<List<ScheduleModel>> getSchedulesForMedicine(String medicineId) async {
    final list = import_in_memory_db.InMemoryDb.schedules.where((s) => s['medicine_id'] == medicineId).toList();
    return list.map((map) => ScheduleModel.fromMap(map)).toList();
  }
}
