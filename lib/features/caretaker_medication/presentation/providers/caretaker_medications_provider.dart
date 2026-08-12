import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../medications/presentation/providers/medications_provider.dart';
import '../../../sync/presentation/providers/sync_provider.dart';
import '../../domain/usecases/caretaker_add_medication.dart';
import '../../domain/usecases/caretaker_update_medication.dart';

final caretakerAddMedicationUseCaseProvider = Provider<CaretakerAddMedication>((ref) {
  return CaretakerAddMedication(
    medicationRepository: ref.watch(medicationRepositoryProvider),
    syncRepository: ref.watch(syncRepositoryProvider),
  );
});

final caretakerUpdateMedicationUseCaseProvider = Provider<CaretakerUpdateMedication>((ref) {
  return CaretakerUpdateMedication(
    medicationRepository: ref.watch(medicationRepositoryProvider),
    syncRepository: ref.watch(syncRepositoryProvider),
  );
});
