import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../entities/profile.dart';

abstract class OnboardingRepository {
  Future<Either<Failure, Profile>> createProfile({
    required String name,
    required String timeZone,
    String profileType = 'Parent',
  });

  Future<Either<Failure, Profile?>> getOwnerProfile();
  Future<Either<Failure, Profile>> createFamilyProfile({
    required String name,
    required String timeZone,
  });
  Future<Either<Failure, Profile>> createSyncedFamilyProfile({
    required String id,
    required String name,
    required String timeZone,
    required String appCode,
  });
  Future<Either<Failure, List<Profile>>> getAllProfiles();
  Future<Either<Failure, void>> updateProfileName({
    required String profileId,
    required String newName,
  });
  Future<Either<Failure, void>> deleteParentProfile({
    required String profileId,
  });
}
