import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../entities/profile.dart';
import '../repositories/onboarding_repository.dart';

class GetOwnerProfile {
  final OnboardingRepository repository;

  GetOwnerProfile(this.repository);

  Future<Either<Failure, Profile?>> call() {
    return repository.getOwnerProfile();
  }
}
