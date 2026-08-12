import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../../../../core/utils/db_helper.dart';
import '../../data/datasources/history_local_datasource.dart';
import '../../data/repositories/history_repository_impl.dart';
import '../../domain/entities/adherence_report.dart';
import '../../domain/repositories/history_repository.dart';
import '../../../medications/presentation/providers/medications_provider.dart';
import '../../../home/presentation/providers/home_provider.dart';
import '../../../home/domain/entities/scheduled_dose.dart';
import '../../../profiles/presentation/providers/active_profile_provider.dart';

// 1. Dependency Injection Providers
final historyLocalDataSourceProvider = Provider<HistoryLocalDataSource>((ref) {
  if (kIsWeb) {
    return HistoryLocalDataSourceInMemory();
  }
  return HistoryLocalDataSourceImpl(DbHelper.instance);
});

final historyRepositoryProvider = Provider<HistoryRepository>((ref) {
  return HistoryRepositoryImpl(
    historyLocalDataSource: ref.watch(historyLocalDataSourceProvider),
    medicationLocalDataSource: ref.watch(medicationLocalDataSourceProvider),
  );
});

// 2. Adherence Reports Provider (By Medicine Tab)
final adherenceReportsProvider = AsyncNotifierProvider<AdherenceReportsNotifier, List<MedicineAdherence>>(() {
  return AdherenceReportsNotifier();
});

class AdherenceReportsNotifier extends AsyncNotifier<List<MedicineAdherence>> {
  @override
  Future<List<MedicineAdherence>> build() async {
    final activeProfile = ref.watch(activeProfileProvider);
    if (activeProfile == null) return [];

    final repository = ref.watch(historyRepositoryProvider);
    final result = await repository.getAdherenceReports(profileId: activeProfile.id);

    return result.fold(
      (failure) => throw Exception(failure.message),
      (reports) => reports,
    );
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
  }
}

// 3. Selected Date Provider (By Date Tab)
final historySelectedDateProvider = StateProvider<DateTime>((ref) => DateTime.now());

// 4. Selected Date Doses Provider (By Date Tab list)
final historySelectedDateDosesProvider = FutureProvider<List<ScheduledDose>>((ref) async {
  final activeProfile = ref.watch(activeProfileProvider);
  if (activeProfile == null) return [];

  final selectedDate = ref.watch(historySelectedDateProvider);
  final dateStr = DateFormat('yyyy-MM-dd').format(selectedDate);

  final homeLocalDataSource = ref.watch(homeLocalDataSourceProvider);
  final result = await homeLocalDataSource.getScheduledDoses(
    profileId: activeProfile.id,
    date: dateStr,
  );
  return result;
});
