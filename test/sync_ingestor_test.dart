import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:family_medicine_tracker/core/constants/app_constants.dart';
import 'package:family_medicine_tracker/features/sync/data/datasources/compression_helper.dart';
import 'package:family_medicine_tracker/features/sync/data/datasources/sync_ingestor.dart';

void main() {
  // Setup sqflite_ffi for testing
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;

  setUp(() async {
    db = await openDatabase(
      inMemoryDatabasePath,
      version: 2,
      onCreate: (db, version) async {
        const textType = 'TEXT NOT NULL';
        const textNullableType = 'TEXT';
        const integerType = 'INTEGER NOT NULL';
        const integerNullableType = 'INTEGER';
        const realNullableType = 'REAL';

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
            updated_at $integerType,
            is_dirty $integerType
          )
        ''');

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
            is_dirty $integerType
          )
        ''');

        await db.execute('''
          CREATE TABLE ${AppConstants.tableSchedules} (
            id $textType PRIMARY KEY,
            profile_id $textType,
            medicine_id $textType,
            time $textType,
            updated_at $integerType,
            is_dirty $integerType
          )
        ''');

        await db.execute('''
          CREATE TABLE ${AppConstants.tableMedicineLog} (
            id $textType PRIMARY KEY,
            profile_id $textType,
            schedule_id $textType,
            date $textType,
            status $textType,
            taken_at $integerNullableType,
            updated_at $integerType,
            is_dirty $integerType
          )
        ''');

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
      },
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('SyncIngestor Database Integration Tests', () {
    test('Successful payload ingestion maps correctly into SQLite database', () async {
      // 1. Create a dummy profile, medicine, schedule, and log payload
      final payload = {
        'medicines': [
          {
            'id': 'med_123',
            'profile_id': 'profile_parent',
            'name': 'Aspirin',
            'type': 'Tablet',
            'dosage_value': 1.0,
            'dosage_unit': 'tab',
            'quantity_value': 10.0,
            'quantity_unit': 'tabs',
            'frequency': 'Once a Day',
            'start_date': 1718010000000,
            'end_date': null,
            'notes': 'Take with food',
            'active': 1,
            'updated_at': 1718010000000,
            'is_dirty': 0
          }
        ],
        'schedules': [
          {
            'id': 'sched_123',
            'profile_id': 'profile_parent',
            'medicine_id': 'med_123',
            'time': '08:00',
            'updated_at': 1718010000000,
            'is_dirty': 0
          }
        ],
        'logs': [
          {
            'id': 'log_123',
            'profile_id': 'profile_parent',
            'schedule_id': 'sched_123',
            'date': '2026-07-15',
            'status': 'Taken',
            'taken_at': 1718012400000,
            'updated_at': 1718012400000,
            'is_dirty': 0
          }
        ]
      };

      final jsonPayload = json.encode(payload);
      final checksum = CompressionHelper.computeChecksum(jsonPayload);
      final compressedBytes = CompressionHelper.compress(jsonPayload);
      final base64String = CompressionHelper.toBase64(compressedBytes);

      // 2. Insert into sync_queue
      await db.insert(AppConstants.tableSyncQueue, {
        'sync_id': 'sync_uuid_test',
        'sender_uid': 'caretaker_uid',
        'sender_app_id': 'P893021',
        'event_type': 'sync_update',
        'compressed_data': base64String,
        'checksum': checksum,
        'timestamp': 1718010000000,
        'is_chunked': 0,
        'status': 'pending',
        'received_at': DateTime.now().millisecondsSinceEpoch,
      });

      // 3. Process ingestion
      await SyncIngestor.processQueue(db);

      // 4. Assert queue status is done
      final queueResults = await db.query(
        AppConstants.tableSyncQueue,
        where: 'sync_id = ?',
        whereArgs: ['sync_uuid_test'],
      );
      expect(queueResults.first['status'], equals('done'));

      // 5. Assert database contains medicines, schedules, and logs
      final medResults = await db.query(AppConstants.tableMedicines);
      expect(medResults.length, equals(1));
      expect(medResults.first['name'], equals('Aspirin'));

      final schedResults = await db.query(AppConstants.tableSchedules);
      expect(schedResults.length, equals(1));
      expect(schedResults.first['time'], equals('08:00'));

      final logResults = await db.query(AppConstants.tableMedicineLog);
      expect(logResults.length, equals(1));
      expect(logResults.first['status'], equals('Taken'));
    });

    test('Mismatched checksum payload results in failed queue status', () async {
      // 1. Create bad compressed data
      const badJson = '{"medicines": []}';
      final compressedBytes = CompressionHelper.compress(badJson);
      final base64String = CompressionHelper.toBase64(compressedBytes);

      // 2. Insert into queue with mismatched checksum
      await db.insert(AppConstants.tableSyncQueue, {
        'sync_id': 'sync_bad_checksum',
        'sender_uid': 'caretaker_uid',
        'sender_app_id': 'P893021',
        'event_type': 'sync_update',
        'compressed_data': base64String,
        'checksum': 'incorrect_checksum_value',
        'timestamp': 1718010000000,
        'is_chunked': 0,
        'status': 'pending',
        'received_at': DateTime.now().millisecondsSinceEpoch,
      });

      // 3. Ingest
      await SyncIngestor.processQueue(db);

      // 4. Assert failed state
      final queueResults = await db.query(
        AppConstants.tableSyncQueue,
        where: 'sync_id = ?',
        whereArgs: ['sync_bad_checksum'],
      );
      expect(queueResults.first['status'], equals('failed'));
      expect(queueResults.first['failure_reason'], contains('MD5 checksum validation failed'));
    });
  });
}
