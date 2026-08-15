import 'package:dartz/dartz.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/profile.dart';
import '../../domain/repositories/onboarding_repository.dart';
import '../datasources/onboarding_local_datasource.dart';
import '../datasources/onboarding_remote_datasource.dart';
import '../models/profile_model.dart';
import '../../../../core/utils/app_code_generator.dart';
import 'package:firebase_auth/firebase_auth.dart';

class OnboardingRepositoryImpl implements OnboardingRepository {
  final OnboardingLocalDataSource localDataSource;
  final OnboardingRemoteDataSource remoteDataSource;
  final Uuid uuid;

  OnboardingRepositoryImpl({
    required this.localDataSource,
    required this.remoteDataSource,
    required this.uuid,
  });

  @override
  Future<Either<Failure, Profile>> createProfile({
    required String name,
    required String timeZone,
    String profileType = 'Parent',
  }) async {
    try {
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      final profile = Profile(
        id: uuid.v4(),
        profileName: name,
        timeZone: timeZone,
        createdAt: now,
        isOwner: true,
        appCode: null,
        profileType: profileType,
      );

      // Save to SQLite
      final model = ProfileModel.fromProfile(profile, isOwner: true, isDirty: 0, updatedAt: now);
      await localDataSource.saveProfile(model);

      return Right(profile);
    } catch (e) {
      return Left(LocalDatabaseFailure('Failed to save profile locally: $e'));
    }
  }

  @override
  Future<Either<Failure, Profile?>> getOwnerProfile() async {
    try {
      final model = await localDataSource.getOwnerProfile();
      if (model != null) {
        return Right(model.toEntity());
      }
      return const Right(null);
    } catch (e) {
      return Left(LocalDatabaseFailure('Failed to fetch profile locally: $e'));
    }
  }

  @override
  Future<Either<Failure, Profile>> createFamilyProfile({
    required String name,
    required String timeZone,
  }) async {
    try {
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      final profile = Profile(
        id: uuid.v4(),
        profileName: name,
        timeZone: timeZone,
        createdAt: now,
        isOwner: false,
      );

      final model = ProfileModel.fromProfile(profile, isOwner: false, isDirty: 1, updatedAt: now);
      await localDataSource.saveProfile(model);
      return Right(profile);
    } catch (e) {
      return Left(LocalDatabaseFailure('Failed to save family profile locally: $e'));
    }
  }

  @override
  Future<Either<Failure, Profile>> createSyncedFamilyProfile({
    required String id,
    required String name,
    required String timeZone,
    required String appCode,
  }) async {
    try {
      final existingProfiles = await localDataSource.getAllProfiles();
      final isDuplicate = existingProfiles.any(
        (p) => p.profileName.trim().toLowerCase() == name.trim().toLowerCase(),
      );
      if (isDuplicate) {
        return Left(
          LocalDatabaseFailure(
            'A profile with the name "$name" already exists. Please choose a unique name.',
          ),
        );
      }

      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      final profile = Profile(
        id: id,
        profileName: name,
        timeZone: timeZone,
        createdAt: now,
        isOwner: false,
        appCode: appCode,
      );

      final model = ProfileModel.fromProfile(profile, isOwner: false, isDirty: 1, updatedAt: now);
      await localDataSource.saveProfile(model);
      return Right(profile);
    } catch (e) {
      return Left(LocalDatabaseFailure('Failed to save synced family profile: $e'));
    }
  }

  @override
  Future<Either<Failure, List<Profile>>> getAllProfiles() async {
    try {
      final models = await localDataSource.getAllProfiles();
      final entities = models.map((m) => m.toEntity()).toList();
      
      // Always place Owner profile first, followed by family/parent profiles in order of addition (createdAt)
      entities.sort((a, b) {
        if (a.isOwner && !b.isOwner) return -1;
        if (!a.isOwner && b.isOwner) return 1;
        return a.createdAt.compareTo(b.createdAt);
      });

      return Right(entities);
    } catch (e) {
      return Left(LocalDatabaseFailure('Failed to fetch all profiles: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> updateProfileName({
    required String profileId,
    required String newName,
  }) async {
    try {
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      
      final allModels = await localDataSource.getAllProfiles();
      final targetIndex = allModels.indexWhere((m) => m.id == profileId);
      if (targetIndex == -1) {
        return Left(LocalDatabaseFailure('Profile not found locally with ID: $profileId'));
      }
      final targetModel = allModels[targetIndex];
      final updatedModel = ProfileModel(
        id: targetModel.id,
        profileName: newName,
        timeZone: targetModel.timeZone,
        avatarUrl: targetModel.avatarUrl,
        createdAt: targetModel.createdAt,
        lastSync: targetModel.lastSync,
        isOwner: targetModel.isOwner,
        appCode: targetModel.appCode,
        updatedAt: now,
        isDirty: 1,
      );

      await localDataSource.saveProfile(updatedModel);

      // Propagate name change to RTDB if authenticated
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final ownerModel = allModels.firstWhere((m) => m.isOwner, orElse: () => targetModel);
        final ownerAppCode = ownerModel.appCode;

        if (ownerAppCode != null && ownerAppCode.isNotEmpty && ownerAppCode != 'None') {
          if (targetModel.isOwner) {
            await remoteDataSource.updateOwnerProfileName(
              ownerAppCode: ownerAppCode,
              newName: newName,
            );
          } else {
            final parentAppCode = targetModel.appCode;
            if (parentAppCode != null && parentAppCode.isNotEmpty && parentAppCode != 'None') {
              await remoteDataSource.updateConnectedParentName(
                ownerAppCode: ownerAppCode,
                parentAppCode: parentAppCode,
                newName: newName,
                caretakerUid: user.uid,
              );
            }
          }
        }
      }

      return const Right(null);
    } catch (e) {
      return Left(LocalDatabaseFailure('Failed to update profile name: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> deleteParentProfile({
    required String profileId,
  }) async {
    try {
      final allModels = await localDataSource.getAllProfiles();
      final targetIndex = allModels.indexWhere((m) => m.id == profileId);
      if (targetIndex == -1) {
        return Left(LocalDatabaseFailure('Profile not found locally with ID: $profileId'));
      }
      final targetModel = allModels[targetIndex];
      if (targetModel.isOwner) {
        return Left(LocalDatabaseFailure('Owner profile cannot be deleted'));
      }

      // 1. Delete local data for this profile from SQLite
      await localDataSource.deleteProfile(profileId);

      // 2. Delete connection mapping from Firebase RTDB if user is logged in
      final user = FirebaseAuth.instance.currentUser;
      final parentAppCode = targetModel.appCode;
      if (user != null && parentAppCode != null && parentAppCode.isNotEmpty && parentAppCode != 'None') {
        final ownerModel = allModels.firstWhere((m) => m.isOwner, orElse: () => targetModel);
        final ownerAppCode = ownerModel.appCode;

        if (ownerAppCode != null && ownerAppCode.isNotEmpty) {
          await remoteDataSource.deleteParentConnection(
            ownerAppCode: ownerAppCode,
            parentAppCode: parentAppCode,
            caretakerUid: user.uid,
          );
        }
      }

      return const Right(null);
    } catch (e) {
      return Left(LocalDatabaseFailure('Failed to delete parent profile: $e'));
    }
  }
}
