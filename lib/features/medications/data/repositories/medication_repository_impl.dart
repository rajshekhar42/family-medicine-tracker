import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/medicine.dart';
import '../../domain/entities/schedule.dart';
import '../../domain/entities/med_type_config.dart';
import '../../domain/repositories/medication_repository.dart';
import '../datasources/medication_local_datasource.dart';
import '../datasources/medication_remote_config_datasource.dart';
import '../models/medicine_model.dart';
import '../models/schedule_model.dart';

class MedicationRepositoryImpl implements MedicationRepository {
  final MedicationLocalDataSource localDataSource;
  final MedicationRemoteConfigDataSource remoteConfigDataSource;

  MedicationRepositoryImpl({
    required this.localDataSource,
    required this.remoteConfigDataSource,
  });

  @override
  Future<Either<Failure, void>> addMedication({
    required Medicine medicine,
    required List<Schedule> schedules,
  }) async {
    try {
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      final medicineModel = MedicineModel.fromMedicine(medicine, isDirty: 1, updatedAt: now);
      final scheduleModels = schedules.map((s) => ScheduleModel.fromSchedule(s, isDirty: 1, updatedAt: now)).toList();

      await localDataSource.saveMedication(
        medicine: medicineModel,
        schedules: scheduleModels,
      );
      return const Right(null);
    } catch (e) {
      return Left(LocalDatabaseFailure('Failed to insert medication: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> updateMedication({
    required Medicine medicine,
    required List<Schedule> schedules,
  }) async {
    try {
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      final medicineModel = MedicineModel.fromMedicine(medicine, isDirty: 1, updatedAt: now);
      final scheduleModels = schedules.map((s) => ScheduleModel.fromSchedule(s, isDirty: 1, updatedAt: now)).toList();

      await localDataSource.updateMedication(
        medicine: medicineModel,
        schedules: scheduleModels,
      );
      return const Right(null);
    } catch (e) {
      return Left(LocalDatabaseFailure('Failed to update medication: $e'));
    }
  }

  @override
  Future<Either<Failure, List<Medicine>>> getAllMedications({
    required String profileId,
  }) async {
    try {
      final models = await localDataSource.getAllMedications(profileId);
      final entities = models.map((m) => m.toEntity()).toList();
      return Right(entities);
    } catch (e) {
      return Left(LocalDatabaseFailure('Failed to query medications: $e'));
    }
  }

  @override
  Future<Either<Failure, MedTypeConfig>> getMedTypeConfig() async {
    try {
      final config = await remoteConfigDataSource.getMedTypeConfig();
      return Right(config);
    } catch (e) {
      return Left(UnknownFailure('Failed to load med type configuration: $e'));
    }
  }

  @override
  Future<Either<Failure, List<Schedule>>> getSchedulesForMedicine({
    required String medicineId,
  }) async {
    try {
      final models = await localDataSource.getSchedulesForMedicine(medicineId);
      final entities = models.map((s) => s.toEntity()).toList();
      return Right(entities);
    } catch (e) {
      return Left(LocalDatabaseFailure('Failed to query schedules: $e'));
    }
  }
}
