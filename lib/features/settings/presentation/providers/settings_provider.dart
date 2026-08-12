import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import '../../../../core/utils/db_helper.dart';
import '../../data/datasources/settings_local_datasource.dart';
import '../../data/repositories/settings_repository_impl.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/repositories/settings_repository.dart';
import '../../domain/usecases/get_settings.dart';
import '../../domain/usecases/save_settings.dart';
import '../../../profiles/presentation/providers/active_profile_provider.dart';

import 'package:uuid/uuid.dart';
import '../../../home/presentation/providers/home_provider.dart';
import '../services/auto_skip_service.dart';
import '../services/reminder_scheduler.dart';

// 1. Dependency Injection Providers
final settingsLocalDataSourceProvider = Provider<SettingsLocalDataSource>((ref) {
  if (kIsWeb) {
    return SettingsLocalDataSourceInMemory();
  }
  return SettingsLocalDataSourceImpl(DbHelper.instance);
});

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepositoryImpl(
    localDataSource: ref.watch(settingsLocalDataSourceProvider),
  );
});

final autoSkipServiceProvider = Provider<AutoSkipService>((ref) {
  return AutoSkipService(
    homeLocalDataSource: ref.watch(homeLocalDataSourceProvider),
    settingsLocalDataSource: ref.watch(settingsLocalDataSourceProvider),
    uuid: const Uuid(),
  );
});

final getSettingsUseCaseProvider = Provider<GetSettings>((ref) {
  return GetSettings(ref.watch(settingsRepositoryProvider));
});

final saveSettingsUseCaseProvider = Provider<SaveSettings>((ref) {
  return SaveSettings(ref.watch(settingsRepositoryProvider));
});

// 2. Settings State Manager
final settingsStateProvider = AsyncNotifierProvider<SettingsNotifier, AppSettings>(() {
  return SettingsNotifier();
});

class SettingsNotifier extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() async {
    final activeProfile = ref.watch(activeProfileProvider);
    if (activeProfile == null) {
      return const AppSettings(profileId: '');
    }

    final getSettings = ref.watch(getSettingsUseCaseProvider);
    final result = await getSettings(profileId: activeProfile.id);

    return result.fold(
      (failure) => throw Exception(failure.message),
      (settings) => settings,
    );
  }

  Future<void> updateReminders(bool enabled) async {
    final current = state.valueOrNull;
    if (current == null) return;

    final updated = current.copyWith(remindersEnabled: enabled);
    state = AsyncValue.data(updated);

    final saveSettings = ref.read(saveSettingsUseCaseProvider);
    await saveSettings(settings: updated);
    await ref.read(reminderSchedulerProvider).rescheduleAll();
  }

  Future<void> updateSound(bool enabled) async {
    final current = state.valueOrNull;
    if (current == null) return;

    final updated = current.copyWith(soundEnabled: enabled);
    state = AsyncValue.data(updated);

    final saveSettings = ref.read(saveSettingsUseCaseProvider);
    await saveSettings(settings: updated);
    await ref.read(reminderSchedulerProvider).rescheduleAll();
  }

  Future<void> updateGracePeriod(int minutes) async {
    final current = state.valueOrNull;
    if (current == null) return;

    final updated = current.copyWith(gracePeriodMinutes: minutes);
    state = AsyncValue.data(updated);

    final saveSettings = ref.read(saveSettingsUseCaseProvider);
    await saveSettings(settings: updated);
    await ref.read(reminderSchedulerProvider).rescheduleAll();
  }
}
