import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../constants/app_constants.dart';
import 'db_migrations.dart';

class DbHelper {
  static final DbHelper instance = DbHelper._init();
  static Database? _database;

  DbHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB(AppConstants.dbName);
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: AppConstants.dbVersion,
      onCreate: _createDB,
      onConfigure: _onConfigure,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onConfigure(Database db) async {
    // Enable Foreign Key support in SQLite
    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    await DbMigrationRunner.run(db, oldVersion, newVersion);
  }

  Future<void> _createDB(Database db, int version) async {
    const textType = 'TEXT NOT NULL';
    const textNullableType = 'TEXT';
    const integerType = 'INTEGER NOT NULL';
    const integerNullableType = 'INTEGER';
    const realNullableType = 'REAL';

    // 1. Profiles Table
    await db.execute('''
      CREATE TABLE ${AppConstants.tableProfiles} (
        id $textType PRIMARY KEY,
        profile_name TEXT UNIQUE NOT NULL,
        time_zone $textType,
        avatar_url $textNullableType,
        created_at $integerType,
        last_sync $integerNullableType,
        is_owner $integerType,
        app_code $textNullableType,
        profile_type $textNullableType DEFAULT 'Parent',
        updated_at $integerType,
        is_dirty $integerType
      )
    ''');

    // 2. Medicines Table
    await db.execute('''
      CREATE TABLE ${AppConstants.tableMedicines} (
        id $textType PRIMARY KEY,
        profile_id $textType,
        name $textType,
        type $textType,
        dosage_value $realNullableType,
        dosage_unit $textNullableType,
        quantity_value $realNullableType,
        quantity_unit $textNullableType,
        frequency $textType,
        start_date $integerType,
        end_date $integerNullableType,
        notes $textNullableType,
        active $integerType,
        updated_at $integerType,
        is_dirty $integerType,
        FOREIGN KEY (profile_id) REFERENCES ${AppConstants.tableProfiles} (id) ON DELETE CASCADE
      )
    ''');

    // 3. Schedules Table
    await db.execute('''
      CREATE TABLE ${AppConstants.tableSchedules} (
        id $textType PRIMARY KEY,
        profile_id $textType,
        medicine_id $textType,
        time $textType,
        updated_at $integerType,
        is_dirty $integerType,
        FOREIGN KEY (profile_id) REFERENCES ${AppConstants.tableProfiles} (id) ON DELETE CASCADE,
        FOREIGN KEY (medicine_id) REFERENCES ${AppConstants.tableMedicines} (id) ON DELETE CASCADE
      )
    ''');

    // 4. MedicineLog Table
    await db.execute('''
      CREATE TABLE ${AppConstants.tableMedicineLog} (
        id $textType PRIMARY KEY,
        profile_id $textType,
        schedule_id $textType,
        date $textType,
        status $textType,
        taken_at $integerNullableType,
        updated_at $integerType,
        is_dirty $integerType,
        FOREIGN KEY (profile_id) REFERENCES ${AppConstants.tableProfiles} (id) ON DELETE CASCADE,
        FOREIGN KEY (schedule_id) REFERENCES ${AppConstants.tableSchedules} (id) ON DELETE CASCADE
      )
    ''');

    // 5. Settings Table
    await db.execute('''
      CREATE TABLE ${AppConstants.tableSettings} (
        profile_id $textType PRIMARY KEY,
        reminders_enabled $integerType,
        sound_enabled $integerType,
        grace_period_minutes $integerType,
        updated_at $integerType,
        is_dirty $integerType,
        FOREIGN KEY (profile_id) REFERENCES ${AppConstants.tableProfiles} (id) ON DELETE CASCADE
      )
    ''');

    await _createSyncTables(db);
  }

  Future<void> _createSyncTables(Database db) async {
    const textType = 'TEXT NOT NULL';
    const textNullableType = 'TEXT';
    const integerType = 'INTEGER NOT NULL';
    const integerNullableType = 'INTEGER';

    await db.execute('''
      CREATE TABLE ${AppConstants.tableSyncQueue} (
        sync_id $textType PRIMARY KEY,
        sender_uid $textNullableType,
        sender_app_id $textNullableType,
        event_type $textNullableType,
        compressed_data $textNullableType,
        checksum $textNullableType,
        timestamp $integerNullableType,
        is_chunked $integerNullableType,
        status $textNullableType,
        received_at $integerNullableType,
        failure_reason $textNullableType
      )
    ''');

    await db.execute('''
      CREATE TABLE ${AppConstants.tableChunkBuffer} (
        sync_id $textType,
        chunk_index $integerType,
        total_chunks $integerType,
        chunk_data $textType,
        checksum $textType,
        sender_uid $textNullableType,
        sender_app_id $textNullableType,
        event_type $textNullableType,
        timestamp $integerNullableType,
        received_at $integerNullableType,
        PRIMARY KEY (sync_id, chunk_index)
      )
    ''');

    await db.execute('''
      CREATE TABLE app_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp INTEGER NOT NULL,
        message TEXT NOT NULL
      )
    ''');
  }

  static Future<void> log(String message) async {
    try {
      final db = await instance.database;
      await db.insert('app_logs', {
        'timestamp': DateTime.now().toUtc().millisecondsSinceEpoch,
        'message': message,
      });
      debugPrint('SQL Log: $message');
    } catch (e) {
      debugPrint('Failed to write SQL Log: $e');
    }
  }

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
    }
  }
}
