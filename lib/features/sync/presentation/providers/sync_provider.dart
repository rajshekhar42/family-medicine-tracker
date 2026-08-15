import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import '../../../../core/utils/db_helper.dart';
import '../../data/datasources/sync_remote_datasource.dart';
import '../../data/datasources/sync_local_datasource.dart';
import '../../data/repositories/sync_repository_impl.dart';
import '../../domain/repositories/sync_repository.dart';
import 'auth_provider.dart';
import '../../../profiles/presentation/providers/active_profile_provider.dart';
import '../../../home/presentation/providers/home_provider.dart';
import '../../../medications/presentation/providers/medications_provider.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../../history/presentation/providers/history_provider.dart';
import '../../../../core/services/analytics_service.dart';
import '../../../../core/services/crashlytics_service.dart';
import '../../../../core/services/performance_service.dart';
import 'rtdb_sync_listener.dart';


class SyncState {
  final bool isSyncing;
  final int? lastSyncedAt;
  final String? errorMessage;

  const SyncState({
    this.isSyncing = false,
    this.lastSyncedAt,
    this.errorMessage,
  });

  SyncState copyWith({
    bool? isSyncing,
    int? lastSyncedAt,
    String? errorMessage,
    bool clearError = false,
  }) {
    return SyncState(
      isSyncing: isSyncing ?? this.isSyncing,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

// 1. Dependency Injection Providers
final syncRemoteDataSourceProvider = Provider<SyncRemoteDataSource>((ref) {
  if (kIsWeb) {
    return SyncRemoteDataSourceInMemory();
  }
  return SyncRemoteDataSourceImpl();
});

final syncLocalDataSourceProvider = Provider<SyncLocalDataSource>((ref) {
  return SyncLocalDataSourceImpl();
});

final syncRepositoryProvider = Provider<SyncRepository>((ref) {
  return SyncRepositoryImpl(
    remoteDataSource: ref.watch(syncRemoteDataSourceProvider),
    localDataSource: ref.watch(syncLocalDataSourceProvider),
  );
});

final syncHasDirtyRowsProvider = FutureProvider<bool>((ref) async {
  ref.watch(syncStateProvider);
  ref.watch(homeDosesProvider);
  ref.watch(medicinesListProvider);
  ref.watch(settingsStateProvider);
  final activeProfile = ref.watch(activeProfileProvider);

  final repository = ref.watch(syncRepositoryProvider);
  return repository.hasDirtyRows(activeProfile?.id);
});

// 2. Sync State Manager
final syncStateProvider = StateNotifierProvider<SyncNotifier, SyncState>((ref) {
  return SyncNotifier(ref);
});

class SyncNotifier extends StateNotifier<SyncState> {
  final Ref _ref;
  DateTime? _lastManualPullTime;

  SyncNotifier(this._ref) : super(const SyncState());

  int? getRemainingCooldownSeconds() {
    if (_lastManualPullTime == null) return null;
    final elapsed = DateTime.now().difference(_lastManualPullTime!).inSeconds;
    if (elapsed < 60) {
      return 60 - elapsed;
    }
    return null;
  }

  /// Triggers a manual sync. Returns remaining cooldown seconds if throttled.
  int? requestManualPull() {
    final remaining = getRemainingCooldownSeconds();
    if (remaining != null) {
      return remaining;
    }
    _lastManualPullTime = DateTime.now();
    sync();
    return null;
  }

  Future<void> sync() async {
    if (state.isSyncing) {
      DbHelper.log('SyncNotifier: Sync already in progress. Skipping duplicate push sync.');
      return;
    }

    final authState = _ref.read(authProvider);
    if (!authState.isAuthenticated || authState.firebaseUser == null) {
      DbHelper.log('SyncNotifier: User is not authenticated. Skipping sync.');
      return;
    }

    final activeProfile = _ref.read(activeProfileProvider);
    if (activeProfile == null) return;

    state = state.copyWith(isSyncing: true, clearError: true);
    final analytics = _ref.read(analyticsServiceProvider);
    final crashlytics = _ref.read(crashlyticsServiceProvider);
    final perf = _ref.read(performanceServiceProvider);

    final startTime = DateTime.now();
    await analytics.logSyncStarted(activeProfile.isOwner ? 'owner' : 'caretaker', 'push');
    await perf.startTrace('sync_push_trace');

    try {
      final repository = _ref.read(syncRepositoryProvider);
      await repository.syncAll(activeProfile.id);

      // Check for and consume any pending inbox payloads in RTDB
      await consumePendingInboxPayloads(_ref);

      // Invalidate all providers to pull fresh synchronized records into UI
      _ref.invalidate(homeDosesProvider);
      _ref.invalidate(medicinesListProvider);
      _ref.invalidate(settingsStateProvider);
      _ref.invalidate(adherenceReportsProvider);

      // Note: last_sync is NOT updated here anymore.
      // The persistent RTDB listener will update last_sync when the receiver's ack arrives.
      // Dirty flags are cleared immediately after successful upload in the repository.

      final durationMs = DateTime.now().difference(startTime).inMilliseconds;
      await analytics.logSyncFinished(
        activeProfile.isOwner ? 'owner' : 'caretaker',
        'push',
        true,
        durationMs: durationMs,
      );
      await perf.stopTrace('sync_push_trace', attributes: {'status': 'success'});

      state = SyncState(
        isSyncing: false,
        lastSyncedAt: DateTime.now().millisecondsSinceEpoch,
      );
    } catch (e, stack) {
      final durationMs = DateTime.now().difference(startTime).inMilliseconds;
      await analytics.logSyncFinished(
        activeProfile.isOwner ? 'owner' : 'caretaker',
        'push',
        false,
        durationMs: durationMs,
        error: e.toString(),
      );
      await perf.stopTrace('sync_push_trace', attributes: {'status': 'failure'});
      await crashlytics.recordError(
        e,
        stack,
        reason: 'Push sync failed',
      );

      state = state.copyWith(
        isSyncing: false,
        errorMessage: 'Synchronization failed: $e',
      );
    }
  }

  Future<void> requestPull() async {
    await sync();
  }
}

final pendingConnectionsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final authState = ref.watch(authProvider);
  if (!authState.isAuthenticated || authState.firebaseUser == null) {
    return Stream.value([]);
  }

  final activeProfile = ref.watch(activeProfileProvider);
  if (activeProfile == null || !activeProfile.isOwner || activeProfile.appCode == null) {
    return Stream.value([]);
  }
  final remoteDataSource = ref.watch(syncRemoteDataSourceProvider);
  return remoteDataSource.getPendingConnectionsStream(activeProfile.appCode!).map((event) {
    if (event.snapshot.exists && event.snapshot.value is Map) {
      final map = Map<String, dynamic>.from(event.snapshot.value as Map);
      final List<Map<String, dynamic>> list = [];
      map.forEach((key, value) {
        if (value is Map) {
          final entry = Map<String, dynamic>.from(value);
          if (entry['status'] == 'pending') {
            entry['caretaker_app_code'] = key;
            list.add(entry);
          }
        }
      });
      return list;
    }
    return [];
  });
});

final caretakerConnectionsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final authState = ref.watch(authProvider);
  if (!authState.isAuthenticated || authState.firebaseUser == null) {
    return Stream.value([]);
  }

  final remoteDataSource = ref.watch(syncRemoteDataSourceProvider);
  return remoteDataSource.getCaretakerConnectionsStream(authState.firebaseUser!.uid).map((event) {
    if (event.snapshot.exists && event.snapshot.value is Map) {
      final map = Map<String, dynamic>.from(event.snapshot.value as Map);
      final List<Map<String, dynamic>> list = [];
      map.forEach((key, value) {
        if (value is Map) {
          final entry = Map<String, dynamic>.from(value);
          entry['parent_app_code'] = key;
          list.add(entry);
        }
      });
      return list;
    }
    return [];
  });
});
