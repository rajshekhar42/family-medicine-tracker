import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:family_medicine_tracker/core/utils/db_helper.dart';
import 'package:family_medicine_tracker/core/constants/app_constants.dart';
import 'package:family_medicine_tracker/features/sync/data/repositories/sync_repository_impl.dart';
import 'package:family_medicine_tracker/features/sync/data/datasources/sync_remote_datasource.dart';
import 'package:family_medicine_tracker/features/sync/data/datasources/sync_local_datasource.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late SyncRemoteDataSourceInMemory mockRemote;
  late SyncRepositoryImpl repo;

  setUp(() async {
    final db = await DbHelper.instance.database;
    await db.delete(AppConstants.tableProfiles);
    mockRemote = SyncRemoteDataSourceInMemory();
    repo = SyncRepositoryImpl(
      remoteDataSource: mockRemote,
      localDataSource: SyncLocalDataSourceImpl(),
    );
  });

  test('hasUnconsumedPayload returns false when slot is empty', () async {
    final result = await mockRemote.hasUnconsumedPayload(
      recipientUid: 'caretaker_1',
      senderUid: 'parent_1',
    );
    expect(result, isFalse);
  });

  test('hasUnconsumedPayload returns true after uploadSyncPayload', () async {
    await mockRemote.uploadSyncPayload(
      recipientUid: 'caretaker_1',
      senderUid: 'senderUid',
      senderAppCode: 'PARENT123',
      syncId: 'sync_id_abc',
      payloadJson: '{"medicines":[]}',
    );

    final result = await mockRemote.hasUnconsumedPayload(
      recipientUid: 'caretaker_1',
      senderUid: 'senderUid',
    );
    expect(result, isTrue);
  });

  test('syncAll skips push upload when unconsumed payload exists', () async {
    await mockRemote.uploadSyncPayload(
      recipientUid: 'caretaker_1',
      senderUid: 'profile_1',
      senderAppCode: 'PARENT123',
      syncId: 'sync_id_abc',
      payloadJson: '{"medicines":[]}',
    );

    final db = await DbHelper.instance.database;
    await db.insert(AppConstants.tableProfiles, {
      'id': 'profile_1',
      'profile_name': 'Parent Profile',
      'time_zone': 'UTC',
      'created_at': 1000,
      'is_owner': 1,
      'updated_at': 1000,
      'is_dirty': 1,
      'app_code': 'PARENT123',
    });

    final hasUnconsumedBefore = await mockRemote.hasUnconsumedPayload(
      recipientUid: 'caretaker_1',
      senderUid: 'profile_1',
    );
    expect(hasUnconsumedBefore, isTrue);

    await repo.syncAll('profile_1');

    final hasUnconsumedAfter = await mockRemote.hasUnconsumedPayload(
      recipientUid: 'caretaker_1',
      senderUid: 'profile_1',
    );
    expect(hasUnconsumedAfter, isTrue);
  });
}
