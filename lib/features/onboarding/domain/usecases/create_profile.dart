import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../entities/profile.dart';
import '../repositories/onboarding_repository.dart';

class CreateProfile {
  final OnboardingRepository repository;

  CreateProfile(this.repository);

  Future<Either<Failure, Profile>> call({
    required String name,
    required String timeZone,
    String profileType = 'Parent',
  }) {
    return repository.createProfile(
      name: name,
      timeZone: timeZone,
      profileType: profileType,
    );
  }
}
