import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../entities/medicine.dart';
import '../entities/schedule.dart';
import '../entities/med_type_config.dart';

abstract class MedicationRepository {
  Future<Either<Failure, void>> addMedication({
    required Medicine medicine,
    required List<Schedule> schedules,
  });

  Future<Either<Failure, void>> updateMedication({
    required Medicine medicine,
    required List<Schedule> schedules,
  });

  Future<Either<Failure, List<Medicine>>> getAllMedications({
    required String profileId,
  });

  Future<Either<Failure, MedTypeConfig>> getMedTypeConfig();

  Future<Either<Failure, List<Schedule>>> getSchedulesForMedicine({
    required String medicineId,
  });
}
