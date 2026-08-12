import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../entities/scheduled_dose.dart';
import '../repositories/home_repository.dart';

class MarkDoseTaken {
  final HomeRepository repository;

  MarkDoseTaken(this.repository);

  Future<Either<Failure, ScheduledDose>> call({
    required String profileId,
    required String scheduleId,
    required String date,
    required int takenAt,
  }) {
    return repository.markDoseTaken(
      profileId: profileId,
      scheduleId: scheduleId,
      date: date,
      takenAt: takenAt,
    );
  }
}
