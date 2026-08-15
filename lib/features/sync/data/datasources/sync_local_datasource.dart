import 'package:sqflite/sqflite.dart';
import '../../../../core/utils/db_helper.dart';
import '../../../../core/constants/app_constants.dart';

/// Abstract interface for all SQLite operations performed by the sync engine.
///
/// Decouples [SyncRepositoryImpl] from [DbHelper] so that the repository
/// becomes a pure orchestrator (no raw SQL), and so that sync local logic
/// can be independently tested with an in-memory SQLite instance.
abstract class SyncLocalDataSource {
  /// Returns the profile row for [profileId], or null if not found.
  Future<Map<String, dynamic>?> getProfileById(String profileId);

  /// Returns the single owner profile (is_owner = 1), or null if not found.
  Future<Map<String, dynamic>?> getOwnerProfile();

  /// Returns dirty profiles for [profileId].
  ///
  /// - If [allDirty] is true, returns all profiles with is_dirty = 1 (no
  ///   profile scoping). Used for owner push sync.
  /// - If [sinceTimestamp] is provided, returns rows where updated_at >
  ///   [sinceTimestamp] OR is_dirty = 1. Used for caretaker pull responses.
  /// - Otherwise returns the single profile row where id = [profileId] AND
  ///   is_dirty = 1. Used for caretaker push sync.
  Future<List<Map<String, dynamic>>> getDirtyProfiles(
    String profileId, {
    bool allDirty = false,
    int? sinceTimestamp,
  });

  /// Returns dirty medicine rows for [profileId]. See [getDirtyProfiles] for
  /// [allDirty] and [sinceTimestamp] semantics.
  Future<List<Map<String, dynamic>>> getDirtyMedicines(
    String profileId, {
    bool allDirty = false,
    int? sinceTimestamp,
  });

  /// Returns dirty schedule rows for [profileId]. See [getDirtyProfiles] for
  /// [allDirty] and [sinceTimestamp] semantics.
  Future<List<Map<String, dynamic>>> getDirtySchedules(
    String profileId, {
    bool allDirty = false,
    int? sinceTimestamp,
  });

  /// Returns dirty medicine log rows for [profileId]. See [getDirtyProfiles]
  /// for [allDirty] and [sinceTimestamp] semantics.
  Future<List<Map<String, dynamic>>> getDirtyLogs(
    String profileId, {
    bool allDirty = false,
    int? sinceTimestamp,
  });

  /// Returns all rows from all four syncable tables (full restore dump).
  Future<Map<String, List<Map<String, dynamic>>>> getAllSyncableRows();

  /// Marks all syncable rows for [profileId] as is_dirty = 1 in a single
  /// transaction.
  Future<void> markAllRowsDirty(String profileId);

  /// Returns true if there are any is_dirty = 1 rows.
  ///
  /// When [profileId] is non-null, checks only rows belonging to that profile
  /// first; falls back to a global dirty count scan.
  Future<bool> hasDirtyRows(String? profileId);

  /// Inserts an outgoing sync tracking record into [tableSyncQueue].
  Future<void> insertSyncQueueEntry(Map<String, dynamic> entry);

  /// Checks [targetUid]'s inbox in RTDB and invokes [handler] for each
  /// pending sync_ack or pull-request node.
  ///
  /// NOTE: This method queries the LOCAL SQLite inbox snapshot table, not
  /// RTDB. The RTDB check remains in [SyncRepositoryImpl] which holds the
  /// remote datasource reference.
  /// (This interface intentionally does NOT expose RTDB operations.)
}

/// SQLite implementation of [SyncLocalDataSource].
class SyncLocalDataSourceImpl implements SyncLocalDataSource {
  final DbHelper _dbHelper;

  SyncLocalDataSourceImpl({DbHelper? dbHelper})
      : _dbHelper = dbHelper ?? DbHelper.instance;

  Future<Database> get _db async => _dbHelper.database;

  @override
  Future<Map<String, dynamic>?> getProfileById(String profileId) async {
    final db = await _db;
    final results = await db.query(
      AppConstants.tableProfiles,
      where: 'id = ?',
      whereArgs: [profileId],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  @override
  Future<Map<String, dynamic>?> getOwnerProfile() async {
    final db = await _db;
    final results = await db.query(
      AppConstants.tableProfiles,
      where: 'is_owner = ?',
      whereArgs: [1],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  @override
  Future<List<Map<String, dynamic>>> getDirtyProfiles(
    String profileId, {
    bool allDirty = false,
    int? sinceTimestamp,
  }) async {
    final db = await _db;
    if (allDirty) {
      return db.query(
        AppConstants.tableProfiles,
        where: 'is_dirty = ?',
        whereArgs: [1],
      );
    }
    if (sinceTimestamp != null) {
      return db.query(
        AppConstants.tableProfiles,
        where: 'updated_at > ? OR is_dirty = ?',
        whereArgs: [sinceTimestamp, 1],
      );
    }
    return db.query(
      AppConstants.tableProfiles,
      where: 'id = ? AND is_dirty = ?',
      whereArgs: [profileId, 1],
    );
  }

  @override
  Future<List<Map<String, dynamic>>> getDirtyMedicines(
    String profileId, {
    bool allDirty = false,
    int? sinceTimestamp,
  }) async {
    final db = await _db;
    if (allDirty) {
      return db.query(
        AppConstants.tableMedicines,
        where: 'is_dirty = ?',
        whereArgs: [1],
      );
    }
    if (sinceTimestamp != null) {
      return db.query(
        AppConstants.tableMedicines,
        where: 'updated_at > ? OR is_dirty = ?',
        whereArgs: [sinceTimestamp, 1],
      );
    }
    return db.query(
      AppConstants.tableMedicines,
      where: 'profile_id = ? AND is_dirty = ?',
      whereArgs: [profileId, 1],
    );
  }

  @override
  Future<List<Map<String, dynamic>>> getDirtySchedules(
    String profileId, {
    bool allDirty = false,
    int? sinceTimestamp,
  }) async {
    final db = await _db;
    if (allDirty) {
      return db.query(
        AppConstants.tableSchedules,
        where: 'is_dirty = ?',
        whereArgs: [1],
      );
    }
    if (sinceTimestamp != null) {
      return db.query(
        AppConstants.tableSchedules,
        where: 'updated_at > ? OR is_dirty = ?',
        whereArgs: [sinceTimestamp, 1],
      );
    }
    return db.query(
      AppConstants.tableSchedules,
      where: 'profile_id = ? AND is_dirty = ?',
      whereArgs: [profileId, 1],
    );
  }

  @override
  Future<List<Map<String, dynamic>>> getDirtyLogs(
    String profileId, {
    bool allDirty = false,
    int? sinceTimestamp,
  }) async {
    final db = await _db;
    if (allDirty) {
      return db.query(
        AppConstants.tableMedicineLog,
        where: 'is_dirty = ?',
        whereArgs: [1],
      );
    }
    if (sinceTimestamp != null) {
      return db.query(
        AppConstants.tableMedicineLog,
        where: 'updated_at > ? OR is_dirty = ?',
        whereArgs: [sinceTimestamp, 1],
      );
    }
    return db.query(
      AppConstants.tableMedicineLog,
      where: 'profile_id = ? AND is_dirty = ?',
      whereArgs: [profileId, 1],
    );
  }

  @override
  Future<Map<String, List<Map<String, dynamic>>>> getAllSyncableRows() async {
    final db = await _db;
    return {
      'profiles': await db.query(AppConstants.tableProfiles),
      'medicines': await db.query(AppConstants.tableMedicines),
      'schedules': await db.query(AppConstants.tableSchedules),
      'logs': await db.query(AppConstants.tableMedicineLog),
    };
  }

  @override
  Future<void> markAllRowsDirty(String profileId) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.update(
        AppConstants.tableProfiles,
        {'is_dirty': 1},
        where: 'id = ?',
        whereArgs: [profileId],
      );
      await txn.update(
        AppConstants.tableMedicines,
        {'is_dirty': 1},
        where: 'profile_id = ?',
        whereArgs: [profileId],
      );
      await txn.update(
        AppConstants.tableSchedules,
        {'is_dirty': 1},
        where: 'profile_id = ?',
        whereArgs: [profileId],
      );
      await txn.update(
        AppConstants.tableMedicineLog,
        {'is_dirty': 1},
        where: 'profile_id = ?',
        whereArgs: [profileId],
      );
    });
  }

  @override
  Future<bool> hasDirtyRows(String? profileId) async {
    final db = await _db;
    if (profileId != null) {
      final profilesCount = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) FROM ${AppConstants.tableProfiles} WHERE id = ? AND is_dirty = ?',
        [profileId, 1],
      )) ?? 0;
      final medicinesCount = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) FROM ${AppConstants.tableMedicines} WHERE profile_id = ? AND is_dirty = ?',
        [profileId, 1],
      )) ?? 0;
      final schedulesCount = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) FROM ${AppConstants.tableSchedules} WHERE profile_id = ? AND is_dirty = ?',
        [profileId, 1],
      )) ?? 0;
      final logsCount = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) FROM ${AppConstants.tableMedicineLog} WHERE profile_id = ? AND is_dirty = ?',
        [profileId, 1],
      )) ?? 0;
      if ((profilesCount + medicinesCount + schedulesCount + logsCount) > 0) {
        return true;
      }
    }
    final totalUnscoped = Sqflite.firstIntValue(await db.rawQuery('''
      SELECT 
        (SELECT COUNT(*) FROM ${AppConstants.tableProfiles} WHERE is_dirty = 1) +
        (SELECT COUNT(*) FROM ${AppConstants.tableMedicines} WHERE is_dirty = 1) +
        (SELECT COUNT(*) FROM ${AppConstants.tableSchedules} WHERE is_dirty = 1) +
        (SELECT COUNT(*) FROM ${AppConstants.tableMedicineLog} WHERE is_dirty = 1)
    ''')) ?? 0;
    return totalUnscoped > 0;
  }

  @override
  Future<void> insertSyncQueueEntry(Map<String, dynamic> entry) async {
    final db = await _db;
    await db.insert(
      AppConstants.tableSyncQueue,
      entry,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
