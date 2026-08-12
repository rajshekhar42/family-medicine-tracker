import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart';
import '../../../../core/utils/db_helper.dart';
import '../../../../core/utils/date_time_utils.dart';
import '../../data/datasources/home_local_datasource.dart';
import '../../data/repositories/home_repository_impl.dart';
import '../../domain/entities/scheduled_dose.dart';
import '../../domain/repositories/home_repository.dart';
import '../../domain/usecases/get_scheduled_doses.dart';
import '../../domain/usecases/mark_dose_taken.dart';
import '../../domain/usecases/mark_dose_skipped.dart';
import '../../../profiles/presentation/providers/active_profile_provider.dart';
import '../../../settings/presentation/services/reminder_scheduler.dart';
import '../../../sync/presentation/providers/sync_provider.dart';
import '../../../../core/services/analytics_service.dart';
import '../../../../core/services/crashlytics_service.dart';

// 1. Repository & Usecase Providers
final homeLocalDataSourceProvider = Provider<HomeLocalDataSource>((ref) {
  if (kIsWeb) {
    return HomeLocalDataSourceInMemory();
  }
  return HomeLocalDataSourceImpl(DbHelper.instance);
});

final homeRepositoryProvider = Provider<HomeRepository>((ref) {
  return HomeRepositoryImpl(
    localDataSource: ref.watch(homeLocalDataSourceProvider),
    uuid: const Uuid(),
  );
});

final getScheduledDosesUseCaseProvider = Provider<GetScheduledDoses>((ref) {
  return GetScheduledDoses(ref.watch(homeRepositoryProvider));
});

final markDoseTakenUseCaseProvider = Provider<MarkDoseTaken>((ref) {
  return MarkDoseTaken(ref.watch(homeRepositoryProvider));
});

final markDoseSkippedUseCaseProvider = Provider<MarkDoseSkipped>((ref) {
  return MarkDoseSkipped(ref.watch(homeRepositoryProvider));
});

// 2. State Providers
final selectedDateProvider = StateProvider<DateTime>((ref) {
  return DateTime.now();
});

// 3. Main Home Screen Doses AsyncNotifier
final homeDosesProvider = AsyncNotifierProvider<HomeDosesNotifier, List<ScheduledDose>>(() {
  return HomeDosesNotifier();
});

class HomeDosesNotifier extends AsyncNotifier<List<ScheduledDose>> {
  @override
  Future<List<ScheduledDose>> build() async {
    final activeProfile = ref.watch(activeProfileProvider);
    final selectedDate = ref.watch(selectedDateProvider);
    
    if (activeProfile == null) {
      return [];
    }

    final dateStr = DateFormat('yyyy-MM-dd').format(selectedDate);
    final getScheduledDoses = ref.watch(getScheduledDosesUseCaseProvider);
    
    final result = await getScheduledDoses(
      profileId: activeProfile.id,
      date: dateStr,
    );

    return result.fold(
      (failure) => throw Exception(failure.message),
      (doses) {
        // Sort doses chronologically by time
        doses.sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));
        return doses;
      },
    );
  }

  Future<void> takeDose(String scheduleId) async {
    final activeProfile = ref.read(activeProfileProvider);
    final selectedDate = ref.read(selectedDateProvider);
    if (activeProfile == null) return;

    final dateStr = DateFormat('yyyy-MM-dd').format(selectedDate);
    final nowMillis = DateTime.now().toUtc().millisecondsSinceEpoch;
    
    final markTaken = ref.read(markDoseTakenUseCaseProvider);
    
    // Update local state temporarily/optimistically if needed, or trigger reload after write
    final result = await markTaken(
      profileId: activeProfile.id,
      scheduleId: scheduleId,
      date: dateStr,
      takenAt: nowMillis,
    );

    result.fold(
      (failure) {
        ref.read(crashlyticsServiceProvider).recordError(
          failure,
          StackTrace.current,
          reason: 'Failed to mark dose taken',
        );
      },
      (updatedDose) async {
        ref.read(analyticsServiceProvider).logDoseStatusChanged(
          updatedDose.medicineId,
          updatedDose.scheduleId,
          'Taken',
          updatedDose.scheduledTime,
        );
        // Update state list
        final currentDoses = state.valueOrNull ?? [];
        state = AsyncValue.data(
          currentDoses.map((dose) => dose.scheduleId == scheduleId ? updatedDose : dose).toList(),
        );
        await ref.read(reminderSchedulerProvider).rescheduleAll();
        
        // Trigger background sync after local dose status change
        if (activeProfile.isOwner) {
          ref.read(syncStateProvider.notifier).sync();
        }
      },
    );
  }

  Future<void> skipDose(String scheduleId) async {
    final activeProfile = ref.read(activeProfileProvider);
    final selectedDate = ref.read(selectedDateProvider);
    if (activeProfile == null) return;

    final dateStr = DateFormat('yyyy-MM-dd').format(selectedDate);
    final markSkipped = ref.read(markDoseSkippedUseCaseProvider);

    final result = await markSkipped(
      profileId: activeProfile.id,
      scheduleId: scheduleId,
      date: dateStr,
    );

    result.fold(
      (failure) {
        ref.read(crashlyticsServiceProvider).recordError(
          failure,
          StackTrace.current,
          reason: 'Failed to mark dose skipped',
        );
      },
      (updatedDose) async {
        ref.read(analyticsServiceProvider).logDoseStatusChanged(
          updatedDose.medicineId,
          updatedDose.scheduleId,
          'Skipped',
          updatedDose.scheduledTime,
        );
        // Update state list
        final currentDoses = state.valueOrNull ?? [];
        state = AsyncValue.data(
          currentDoses.map((dose) => dose.scheduleId == scheduleId ? updatedDose : dose).toList(),
        );
        await ref.read(reminderSchedulerProvider).rescheduleAll();

        // Trigger background sync after local dose status change
        if (activeProfile.isOwner) {
          ref.read(syncStateProvider.notifier).sync();
        }
      },
    );
  }
}
