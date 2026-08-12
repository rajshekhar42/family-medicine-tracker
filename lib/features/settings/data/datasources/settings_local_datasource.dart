import 'package:sqflite/sqflite.dart';
import '../../../../core/utils/db_helper.dart';
import '../../../../core/utils/in_memory_db.dart' as import_in_memory_db;
import '../../../../core/constants/app_constants.dart';
import '../models/settings_model.dart';

abstract class SettingsLocalDataSource {
  Future<SettingsModel?> getSettings(String profileId);
  Future<void> saveSettings(SettingsModel settings);
}

class SettingsLocalDataSourceImpl implements SettingsLocalDataSource {
  final DbHelper dbHelper;

  SettingsLocalDataSourceImpl(this.dbHelper);

  @override
  Future<SettingsModel?> getSettings(String profileId) async {
    final db = await dbHelper.database;
    final results = await db.query(
      AppConstants.tableSettings,
      where: 'profile_id = ?',
      whereArgs: [profileId],
      limit: 1,
    );

    if (results.isNotEmpty) {
      return SettingsModel.fromMap(results.first);
    }
    return null;
  }

  @override
  Future<void> saveSettings(SettingsModel settings) async {
    final db = await dbHelper.database;
    await db.insert(
      AppConstants.tableSettings,
      settings.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}

class SettingsLocalDataSourceInMemory implements SettingsLocalDataSource {
  SettingsLocalDataSourceInMemory();

  @override
  Future<SettingsModel?> getSettings(String profileId) async {
    final map = import_in_memory_db.InMemoryDb.ownerSettings;
    if (map != null) {
      return SettingsModel.fromMap(map);
    }
    return null;
  }

  @override
  Future<void> saveSettings(SettingsModel settings) async {
    import_in_memory_db.InMemoryDb.ownerSettings = settings.toMap();
  }
}
