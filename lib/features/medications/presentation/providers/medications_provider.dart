import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/foundation.dart';
import '../../../../core/utils/db_helper.dart';
import '../../data/datasources/medication_local_datasource.dart';
import '../../data/datasources/medication_remote_config_datasource.dart';
import '../../data/repositories/medication_repository_impl.dart';
import '../../domain/entities/medicine.dart';
import '../../domain/entities/schedule.dart';
import '../../domain/entities/med_type_config.dart';
import '../../domain/repositories/medication_repository.dart';
import '../../domain/usecases/add_medication.dart';
import '../../domain/usecases/update_medication.dart';
import '../../domain/usecases/get_all_medications.dart';
import '../../domain/usecases/get_med_type_config.dart';
import '../../../profiles/presentation/providers/active_profile_provider.dart';

// 1. Dependency Injection Providers
final medicationLocalDataSourceProvider = Provider<MedicationLocalDataSource>((ref) {
  if (kIsWeb) {
    return MedicationLocalDataSourceInMemory();
  }
  return MedicationLocalDataSourceImpl(DbHelper.instance);
});

final medicationRemoteConfigDataSourceProvider = Provider<MedicationRemoteConfigDataSource>((ref) {
  return MedicationRemoteConfigDataSourceImpl(); // Uses local fallback config
});

final medicationRepositoryProvider = Provider<MedicationRepository>((ref) {
  return MedicationRepositoryImpl(
    localDataSource: ref.watch(medicationLocalDataSourceProvider),
    remoteConfigDataSource: ref.watch(medicationRemoteConfigDataSourceProvider),
  );
});

final addMedicationUseCaseProvider = Provider<AddMedication>((ref) {
  return AddMedication(ref.watch(medicationRepositoryProvider));
});

final updateMedicationUseCaseProvider = Provider<UpdateMedication>((ref) {
  return UpdateMedication(ref.watch(medicationRepositoryProvider));
});

final getAllMedicationsUseCaseProvider = Provider<GetAllMedications>((ref) {
  return GetAllMedications(ref.watch(medicationRepositoryProvider));
});

final getMedTypeConfigUseCaseProvider = Provider<GetMedTypeConfig>((ref) {
  return GetMedTypeConfig(ref.watch(medicationRepositoryProvider));
});

// 2. Future Configuration Provider
final medTypeConfigProvider = FutureProvider<MedTypeConfig>((ref) async {
  final getMedTypeConfig = ref.watch(getMedTypeConfigUseCaseProvider);
  final result = await getMedTypeConfig();
  return result.fold(
    (failure) => throw Exception(failure.message),
    (config) => config,
  );
});

// 3. Medicines List Providers
final medicinesListProvider = AsyncNotifierProvider<MedicinesListNotifier, List<Medicine>>(() {
  return MedicinesListNotifier();
});

class MedicinesListNotifier extends AsyncNotifier<List<Medicine>> {
  @override
  Future<List<Medicine>> build() async {
    final activeProfile = ref.watch(activeProfileProvider);
    if (activeProfile == null) return [];

    final getAll = ref.watch(getAllMedicationsUseCaseProvider);
    final result = await getAll(profileId: activeProfile.id);

    return result.fold(
      (failure) => throw Exception(failure.message),
      (list) => list,
    );
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
  }
}

// 4. Form Submission Provider
final medicationFormStateProvider = StateProvider<AsyncValue<void>>((ref) {
  return const AsyncValue.data(null);
});
