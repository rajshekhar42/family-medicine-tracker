import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../entities/medicine.dart';
import '../repositories/medication_repository.dart';

class GetAllMedications {
  final MedicationRepository repository;

  GetAllMedications(this.repository);

  Future<Either<Failure, List<Medicine>>> call({
    required String profileId,
  }) {
    return repository.getAllMedications(profileId: profileId);
  }
}
