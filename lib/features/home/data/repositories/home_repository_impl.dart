import 'package:dartz/dartz.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/scheduled_dose.dart';
import '../../domain/repositories/home_repository.dart';
import '../datasources/home_local_datasource.dart';
import '../models/scheduled_dose_model.dart';

class HomeRepositoryImpl implements HomeRepository {
  final HomeLocalDataSource localDataSource;
  final Uuid uuid;

  HomeRepositoryImpl({
    required this.localDataSource,
    required this.uuid,
  });

  @override
  Future<Either<Failure, List<ScheduledDose>>> getScheduledDoses({
    required String profileId,
    required String date,
  }) async {
    try {
      final models = await localDataSource.getScheduledDoses(
        profileId: profileId,
        date: date,
      );
      final entities = models.map((model) => model.toEntity()).toList();
      return Right(entities);
    } catch (e) {
      return Left(LocalDatabaseFailure('Failed to query scheduled doses: $e'));
    }
  }

  @override
  Future<Either<Failure, ScheduledDose>> markDoseTaken({
    required String profileId,
    required String scheduleId,
    required String date,
    required int takenAt,
  }) async {
    try {
      final logId = uuid.v4();
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      
      await localDataSource.logDose(
        id: logId,
        profileId: profileId,
        scheduleId: scheduleId,
        date: date,
        status: 'Taken',
        takenAt: takenAt,
        updatedAt: now,
        isDirty: 1,
      );

      final row = await localDataSource.getScheduledDoseRow(
        scheduleId: scheduleId,
        date: date,
      );

      if (row != null) {
        return Right(ScheduledDoseModel.fromMap(row, date).toEntity());
      }
      return Left(LocalDatabaseFailure('Dose logged, but failed to retrieve updated data.'));
    } catch (e) {
      return Left(LocalDatabaseFailure('Failed to log dose: $e'));
    }
  }

  @override
  Future<Either<Failure, ScheduledDose>> markDoseSkipped({
    required String profileId,
    required String scheduleId,
    required String date,
  }) async {
    try {
      final logId = uuid.v4();
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;

      await localDataSource.logDose(
        id: logId,
        profileId: profileId,
        scheduleId: scheduleId,
        date: date,
        status: 'Skipped',
        takenAt: null,
        updatedAt: now,
        isDirty: 1,
      );

      final row = await localDataSource.getScheduledDoseRow(
        scheduleId: scheduleId,
        date: date,
      );

      if (row != null) {
        return Right(ScheduledDoseModel.fromMap(row, date).toEntity());
      }
      return Left(LocalDatabaseFailure('Dose logged, but failed to retrieve updated data.'));
    } catch (e) {
      return Left(LocalDatabaseFailure('Failed to log dose: $e'));
    }
  }
}
