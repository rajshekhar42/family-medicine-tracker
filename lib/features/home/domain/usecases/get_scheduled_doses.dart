import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../entities/scheduled_dose.dart';
import '../repositories/home_repository.dart';

class GetScheduledDoses {
  final HomeRepository repository;

  GetScheduledDoses(this.repository);

  Future<Either<Failure, List<ScheduledDose>>> call({
    required String profileId,
    required String date,
  }) {
    return repository.getScheduledDoses(profileId: profileId, date: date);
  }
}
