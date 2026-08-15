import 'package:sqflite/sqflite.dart';
import '../constants/app_constants.dart';

/// Encapsulates a single SQLite database migration.
///
/// Each migration is responsible for exactly one version transition.
/// To add a new schema version, create a new [DbMigration] and append it to
/// [DbMigrationRunner.migrations] — no modifications to existing migrations.
///
/// This satisfies the Open/Closed Principle: the migration mechanism is open
/// for extension (new versions) but closed for modification (past versions).
abstract class DbMigration {
  /// The database version this migration upgrades TO.
  int get targetVersion;

  /// Applies the migration to [db].
  Future<void> apply(Database db);
}

// ---------------------------------------------------------------------------
// Version-specific migrations
// ---------------------------------------------------------------------------

/// v1 → v2: Adds `app_code` column to profiles and creates sync tables.
class DbMigrationV2 implements DbMigration {
  @override
  int get targetVersion => 2;

  @override
  Future<void> apply(Database db) async {
    try {
      await db.execute(
        'ALTER TABLE ${AppConstants.tableProfiles} ADD COLUMN app_code TEXT',
      );
    } catch (_) {
      // Column already exists — safe to skip
    }
    try {
      await _createSyncTables(db);
    } catch (_) {
      // Tables already exist — safe to skip
    }
  }

  Future<void> _createSyncTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${AppConstants.tableSyncQueue} (
        sync_id TEXT NOT NULL PRIMARY KEY,
        sender_uid TEXT,
        sender_app_id TEXT,
        event_type TEXT,
        compressed_data TEXT,
        checksum TEXT,
        timestamp INTEGER,
        is_chunked INTEGER,
        status TEXT,
        received_at INTEGER,
        failure_reason TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${AppConstants.tableChunkBuffer} (
        sync_id TEXT NOT NULL,
        chunk_index INTEGER NOT NULL,
        total_chunks INTEGER NOT NULL,
        chunk_data TEXT NOT NULL,
        checksum TEXT NOT NULL,
        sender_uid TEXT,
        sender_app_id TEXT,
        event_type TEXT,
        timestamp INTEGER,
        received_at INTEGER,
        PRIMARY KEY (sync_id, chunk_index)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp INTEGER NOT NULL,
        message TEXT NOT NULL
      )
    ''');
  }
}

/// v2 → v3: Adds `profile_type` column to profiles.
class DbMigrationV3 implements DbMigration {
  @override
  int get targetVersion => 3;

  @override
  Future<void> apply(Database db) async {
    try {
      await db.execute(
        "ALTER TABLE ${AppConstants.tableProfiles} ADD COLUMN profile_type TEXT DEFAULT 'Parent'",
      );
    } catch (_) {
      // Column already exists — safe to skip
    }
  }
}

// ---------------------------------------------------------------------------
// Migration runner — the only place that needs to change when adding a new
// schema version: append a new DbMigration to the list below.
// ---------------------------------------------------------------------------

/// Applies all pending [DbMigration]s in order when [oldVersion] < [newVersion].
///
/// To add a new schema version:
/// 1. Create `class DbMigrationVN implements DbMigration { ... }` above.
/// 2. Append it to [migrations].
/// 3. Bump [AppConstants.dbVersion].
/// 4. Done — no other files need to change.
class DbMigrationRunner {
  /// Ordered list of all migrations. Add new versions at the end.
  static final List<DbMigration> migrations = [
    DbMigrationV2(),
    DbMigrationV3(),
  ];

  /// Runs all migrations whose [DbMigration.targetVersion] is in
  /// `(oldVersion, newVersion]`.
  static Future<void> run(Database db, int oldVersion, int newVersion) async {
    for (final migration in migrations) {
      if (migration.targetVersion > oldVersion &&
          migration.targetVersion <= newVersion) {
        await migration.apply(db);
      }
    }
  }
}
