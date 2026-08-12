import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../../medications/domain/entities/medicine.dart';
import '../../../medications/domain/entities/schedule.dart';
import '../../../medications/domain/repositories/medication_repository.dart';
import '../../../sync/data/repositories/sync_repository_impl.dart';

class CaretakerUpdateMedication {
  final MedicationRepository medicationRepository;
  final SyncRepository syncRepository;

  CaretakerUpdateMedication({
    required this.medicationRepository,
    required this.syncRepository,
  });

  Future<Either<Failure, void>> call({
    required Medicine medicine,
    required List<Schedule> schedules,
  }) async {
    // 1. Update medication locally with is_dirty = 1
    final result = await medicationRepository.updateMedication(
      medicine: medicine,
      schedules: schedules,
    );

    return result.fold(
      (failure) => Left(failure),
      (_) async {
        try {
          // 2. Immediately trigger sync to Parent's device
          await syncRepository.syncAll(medicine.profileId);
          return const Right(null);
        } catch (e) {
          return Left(RemoteSyncFailure('Updated locally, but failed to sync to parent device: $e'));
        }
      },
    );
  }
}
