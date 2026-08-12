import 'package:sqflite/sqflite.dart';
import '../../../../core/utils/db_helper.dart';
import '../../../../core/utils/in_memory_db.dart' as import_in_memory_db;
import '../../../../core/constants/app_constants.dart';
import '../models/profile_model.dart';

abstract class OnboardingLocalDataSource {
  Future<void> saveProfile(ProfileModel profile);
  Future<ProfileModel?> getOwnerProfile();
  Future<List<ProfileModel>> getAllProfiles();
  Future<void> deleteProfile(String profileId);
}

class OnboardingLocalDataSourceImpl implements OnboardingLocalDataSource {
  final DbHelper dbHelper;

  OnboardingLocalDataSourceImpl(this.dbHelper);

  @override
  Future<void> saveProfile(ProfileModel profile) async {
    final db = await dbHelper.database;
    
    // 1. Check if a profile with the same ID already exists
    final existingById = await db.query(
      AppConstants.tableProfiles,
      where: 'id = ?',
      whereArgs: [profile.id],
      limit: 1,
    );

    if (existingById.isNotEmpty) {
      // Update existing profile in-place to avoid triggering ON DELETE CASCADE
      await db.update(
        AppConstants.tableProfiles,
        profile.toMap(),
        where: 'id = ?',
        whereArgs: [profile.id],
      );
      return;
    }

    // 2. If saving an owner profile, check if an owner profile already exists
    if (profile.isOwner) {
      final existingOwner = await db.query(
        AppConstants.tableProfiles,
        where: 'is_owner = ?',
        whereArgs: [1],
        limit: 1,
      );

      if (existingOwner.isNotEmpty) {
        final existingOwnerId = existingOwner.first['id'] as String;
        // Retain existing owner ID to preserve foreign key relations in medicines, schedules, and logs
        final map = profile.toMap();
        map['id'] = existingOwnerId;
        await db.update(
          AppConstants.tableProfiles,
          map,
          where: 'id = ?',
          whereArgs: [existingOwnerId],
        );
        return;
      }
    }

    // 3. Otherwise insert new profile using IGNORE to prevent cascade deletion
    await db.insert(
      AppConstants.tableProfiles,
      profile.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  @override
  Future<ProfileModel?> getOwnerProfile() async {
    final db = await dbHelper.database;
    final maps = await db.query(
      AppConstants.tableProfiles,
      where: 'is_owner = ?',
      whereArgs: [1],
      limit: 1,
    );

    if (maps.isNotEmpty) {
      return ProfileModel.fromMap(maps.first);
    }
    return null;
  }

  @override
  Future<List<ProfileModel>> getAllProfiles() async {
    final db = await dbHelper.database;
    final results = await db.query(AppConstants.tableProfiles, orderBy: 'created_at ASC');
    final profiles = results.map((m) => ProfileModel.fromMap(m)).toList();

    // Deduplicate: Ensure only 1 owner profile exists locally
    final ownerProfiles = profiles.where((p) => p.isOwner).toList();
    if (ownerProfiles.length > 1) {
      for (int i = 1; i < ownerProfiles.length; i++) {
        final dup = ownerProfiles[i];
        await db.delete(AppConstants.tableProfiles, where: 'id = ?', whereArgs: [dup.id]);
        profiles.removeWhere((p) => p.id == dup.id);
      }
    }

    return profiles;
  }

  @override
  Future<void> deleteProfile(String profileId) async {
    final db = await dbHelper.database;
    await db.transaction((txn) async {
      await txn.delete(AppConstants.tableMedicines, where: 'profile_id = ?', whereArgs: [profileId]);
      await txn.delete(AppConstants.tableSchedules, where: 'profile_id = ?', whereArgs: [profileId]);
      await txn.delete(AppConstants.tableMedicineLog, where: 'profile_id = ?', whereArgs: [profileId]);
      await txn.delete(AppConstants.tableSettings, where: 'profile_id = ?', whereArgs: [profileId]);
      await txn.delete(AppConstants.tableProfiles, where: 'id = ? AND is_owner = 0', whereArgs: [profileId]);
    });
  }
}

class OnboardingLocalDataSourceInMemory implements OnboardingLocalDataSource {
  OnboardingLocalDataSourceInMemory();

  @override
  Future<void> saveProfile(ProfileModel profile) async {
    final Map<String, dynamic> map = profile.toMap();
    import_in_memory_db.InMemoryDb.profiles.removeWhere((p) => p['id'] == profile.id);
    import_in_memory_db.InMemoryDb.profiles.add(map);

    if (profile.isOwner) {
      import_in_memory_db.InMemoryDb.ownerProfile = map;
    }
  }

  @override
  Future<ProfileModel?> getOwnerProfile() async {
    final list = import_in_memory_db.InMemoryDb.profiles;
    try {
      final owner = list.firstWhere((p) => p['is_owner'] == 1);
      return ProfileModel.fromMap(owner);
    } catch (_) {
      final map = import_in_memory_db.InMemoryDb.ownerProfile;
      if (map != null) {
        return ProfileModel.fromMap(map);
      }
    }
    return null;
  }

  @override
  Future<List<ProfileModel>> getAllProfiles() async {
    return import_in_memory_db.InMemoryDb.profiles.map((p) => ProfileModel.fromMap(p)).toList();
  }

  @override
  Future<void> deleteProfile(String profileId) async {
    import_in_memory_db.InMemoryDb.profiles.removeWhere((p) => p['id'] == profileId);
    import_in_memory_db.InMemoryDb.medicines.removeWhere((m) => m['profile_id'] == profileId);
    import_in_memory_db.InMemoryDb.schedules.removeWhere((s) => s['profile_id'] == profileId);
    import_in_memory_db.InMemoryDb.medicineLogs.removeWhere((l) => l['profile_id'] == profileId);
  }
}
