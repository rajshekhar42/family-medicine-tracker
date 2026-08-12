import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../entities/medicine.dart';
import '../entities/schedule.dart';
import '../repositories/medication_repository.dart';

class AddMedication {
  final MedicationRepository repository;

  AddMedication(this.repository);

  Future<Either<Failure, void>> call({
    required Medicine medicine,
    required List<Schedule> schedules,
  }) {
    return repository.addMedication(medicine: medicine, schedules: schedules);
  }
}
