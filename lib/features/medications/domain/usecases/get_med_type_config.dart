import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../entities/med_type_config.dart';
import '../repositories/medication_repository.dart';

class GetMedTypeConfig {
  final MedicationRepository repository;

  GetMedTypeConfig(this.repository);

  Future<Either<Failure, MedTypeConfig>> call() {
    return repository.getMedTypeConfig();
  }
}
