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

  late Database db;
  late SyncRepositoryImpl repo;

  setUp(() async {
    db = await DbHelper.instance.database;
    await db.delete(AppConstants.tableProfiles);
    await db.delete(AppConstants.tableMedicines);
    await db.delete(AppConstants.tableSchedules);
    await db.delete(AppConstants.tableMedicineLog);
    await db.delete(AppConstants.tableSettings);

    repo = SyncRepositoryImpl(
      remoteDataSource: SyncRemoteDataSourceInMemory(),
      localDataSource: SyncLocalDataSourceImpl(),
    );
  });

  test('hasDirtyRows returns false when all tables are clean', () async {
    final result = await repo.hasDirtyRows('profile_1');
    expect(result, isFalse);
  });

  test('hasDirtyRows returns true when a profile has is_dirty = 1', () async {
    await db.insert(AppConstants.tableProfiles, {
      'id': 'profile_1',
      'profile_name': 'Parent Profile',
      'time_zone': 'UTC',
      'created_at': 1000,
      'is_owner': 1,
      'updated_at': 1000,
      'is_dirty': 1,
    });

    final result = await repo.hasDirtyRows('profile_1');
    expect(result, isTrue);
  });
}
