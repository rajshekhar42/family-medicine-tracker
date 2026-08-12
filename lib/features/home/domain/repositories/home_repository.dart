import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../entities/scheduled_dose.dart';

abstract class HomeRepository {
  Future<Either<Failure, List<ScheduledDose>>> getScheduledDoses({
    required String profileId,
    required String date,
  });

  Future<Either<Failure, ScheduledDose>> markDoseTaken({
    required String profileId,
    required String scheduleId,
    required String date,
    required int takenAt,
  });

  Future<Either<Failure, ScheduledDose>> markDoseSkipped({
    required String profileId,
    required String scheduleId,
    required String date,
  });
}
