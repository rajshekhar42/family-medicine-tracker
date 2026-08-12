import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../entities/scheduled_dose.dart';
import '../repositories/home_repository.dart';

class MarkDoseSkipped {
  final HomeRepository repository;

  MarkDoseSkipped(this.repository);

  Future<Either<Failure, ScheduledDose>> call({
    required String profileId,
    required String scheduleId,
    required String date,
  }) {
    return repository.markDoseSkipped(
      profileId: profileId,
      scheduleId: scheduleId,
      date: date,
    );
  }
}
