import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../entities/medicine.dart';
import '../entities/schedule.dart';
import '../repositories/medication_repository.dart';

class UpdateMedication {
  final MedicationRepository repository;

  UpdateMedication(this.repository);

  Future<Either<Failure, void>> call({
    required Medicine medicine,
    required List<Schedule> schedules,
  }) {
    return repository.updateMedication(medicine: medicine, schedules: schedules);
  }
}
