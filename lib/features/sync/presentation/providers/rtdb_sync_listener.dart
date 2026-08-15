import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../../core/utils/db_helper.dart';
import '../../data/datasources/sync_payload_processor.dart';
import '../../data/datasources/sync_ack_handler.dart';
import 'auth_provider.dart';
import '../../../onboarding/presentation/providers/onboarding_provider.dart';
import '../../../home/presentation/providers/home_provider.dart';
import '../../../medications/presentation/providers/medications_provider.dart';
import '../../../history/presentation/providers/history_provider.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../../settings/presentation/services/reminder_scheduler.dart';

// ---------------------------------------------------------------------------
// Re-exported helpers for backward compat (used by SyncRepositoryImpl)
// ---------------------------------------------------------------------------

/// Processes a sync_ack data map against the local SQLite tableSyncQueue.
///
/// Delegates to [SyncAckHandler.processSyncAck].
Future<bool> processSyncAck(dynamic db, Map<String, dynamic> data) async {
  final handler = SyncAckHandler(db: db);
  return handler.processSyncAck(data);
}

// ---------------------------------------------------------------------------
// Manual inbox poll
// ---------------------------------------------------------------------------

/// Manually checks and consumes any pending inbox payloads at
/// `sync_payloads/$uid` in RTDB.
///
/// Called by [SyncNotifier] on startup and on app resume to drain any payloads
/// that arrived while the real-time listener was not active.
Future<void> consumePendingInboxPayloads(Ref ref) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;
  if (firebaseUser == null) return;

  final uid = firebaseUser.uid;
  final refDb = FirebaseDatabase.instance.ref('sync_payloads/$uid');
  try {
    final snapshot = await refDb.get();
    if (snapshot.exists && snapshot.value != null) {
      DbHelper.log('RTDB Sync: Manual inbox check found pending payloads for UID $uid');
      final rawValue = snapshot.value;
      if (rawValue is Map) {
        final payloadsMap = <String, Map<String, dynamic>>{};
        rawValue.forEach((key, val) {
          if (val is Map) {
            final data = <String, dynamic>{};
            val.forEach((k, v) => data[k.toString()] = v);
            payloadsMap[key.toString()] = data;
          }
        });

        final db = await DbHelper.instance.database;
        final processor = SyncPayloadProcessor(db: db);

        for (final entry in payloadsMap.entries) {
          final nodeKey = entry.key;
          final data = entry.value;
          if (data['sync_id'] == null) data['sync_id'] = nodeKey;
          final eventType = data['event_type'] as String?;
          try {
            if (eventType != 'sync_ack' && !nodeKey.endsWith('_ack')) {
              await processor.process(data, ref);
            }
          } catch (e) {
            DbHelper.log('RTDB Sync: Error processing manual payload $nodeKey: $e');
          } finally {
            try {
              await refDb.child(nodeKey).remove();
              DbHelper.log('RTDB Sync: Consumed and deleted node: $nodeKey');
            } catch (e) {
              DbHelper.log('RTDB Sync: Error removing node $nodeKey: $e');
            }
          }
        }

        ref.invalidate(profilesListProvider);
        ref.invalidate(homeDosesProvider);
        ref.invalidate(medicinesListProvider);
        ref.invalidate(adherenceReportsProvider);
        ref.invalidate(historySelectedDateDosesProvider);
        ref.invalidate(settingsStateProvider);
      }
    }
  } catch (e) {
    DbHelper.log('RTDB Sync: Error checking pending inbox payloads: $e');
  }
}

// ---------------------------------------------------------------------------
// Real-time RTDB listener provider
// ---------------------------------------------------------------------------

/// Riverpod provider that establishes real-time listeners on the current
/// user's RTDB inbox (`sync_payloads/$uid`).
///
/// Delegates payload ingestion to [SyncPayloadProcessor] and ack handling to
/// [SyncAckHandler]. This provider is intentionally side-effect-only (returns
/// void) so that state updates flow through dedicated Riverpod providers.
final rtdbSyncListenerProvider = Provider<void>((ref) {
  final authState = ref.watch(authProvider);
  final firebaseUser = authState.firebaseUser;

  if (firebaseUser == null) {
    DbHelper.log('RTDB Sync: firebaseUser is null. Skipping listener initialization.');
    return;
  }

  final ownerProfileAsync = ref.read(ownerProfileProvider);
  final ownerProfile = ownerProfileAsync.valueOrNull;

  final uid = firebaseUser.uid;
  final refDb = FirebaseDatabase.instance.ref('sync_payloads/$uid');

  DbHelper.log('Starting RTDB sync listener for UID: $uid (AppCode: ${ownerProfile?.appCode})');

  // Force database online and keep inbox synced
  try {
    FirebaseDatabase.instance.setPersistenceEnabled(false);
    FirebaseDatabase.instance.goOnline();
    refDb.keepSynced(true);
    DbHelper.log('RTDB Sync: persistence disabled, forced online, keepSynced=true for UID: $uid');
  } catch (e) {
    DbHelper.log('RTDB Sync: Failed to force online/keepSynced: $e');
  }

  // Inner handler: processes all nodes in a snapshot
  Future<void> handleSnapshot(DataSnapshot snapshot) async {
    if (!snapshot.exists || snapshot.value == null) return;

    final rawValue = snapshot.value;
    if (rawValue is! Map) {
      DbHelper.log('RTDB Sync: Snapshot value is not a Map: ${rawValue.runtimeType}');
      return;
    }

    final payloadsMap = <String, Map<String, dynamic>>{};
    rawValue.forEach((key, val) {
      if (val is Map) {
        final data = <String, dynamic>{};
        val.forEach((k, v) => data[k.toString()] = v);
        payloadsMap[key.toString()] = data;
      }
    });

    if (payloadsMap.isEmpty) return;
    DbHelper.log('RTDB Sync: Found ${payloadsMap.length} payloads to process.');

    final db = await DbHelper.instance.database;
    final processor = SyncPayloadProcessor(db: db);
    final ackHandler = SyncAckHandler(db: db);

    for (final entry in payloadsMap.entries) {
      final nodeKey = entry.key;
      final data = entry.value;
      if (data['sync_id'] == null) data['sync_id'] = nodeKey;

      final eventType = data['event_type'] as String?;

      try {
        if (eventType == 'sync_ack' || nodeKey.endsWith('_ack')) {
          DbHelper.log('RTDB Sync: Received sync_ack nodeKey=$nodeKey, status=${data['status']}');
          await ackHandler.handleIncomingAck(data, ref);
        } else {
          DbHelper.log('RTDB Sync: Processing payload nodeKey=$nodeKey (event_type=$eventType)');
          await processor.process(data, ref);

          // Invalidate providers to refresh UI in real-time
          ref.invalidate(profilesListProvider);
          ref.invalidate(homeDosesProvider);
          ref.invalidate(medicinesListProvider);
          ref.invalidate(adherenceReportsProvider);
          ref.invalidate(historySelectedDateDosesProvider);
          ref.invalidate(settingsStateProvider);

          // Reschedule all active reminders based on new sync data
          await ref.read(reminderSchedulerProvider).rescheduleAll();
        }
      } catch (e, stack) {
        DbHelper.log('RTDB Sync: Error processing node $nodeKey: $e\n$stack');
      } finally {
        // ALWAYS delete the node from RTDB to keep storage clean
        try {
          await refDb.child(nodeKey).remove();
          DbHelper.log('RTDB Sync: Consumed and deleted node: $nodeKey');
        } catch (e) {
          DbHelper.log('RTDB Sync: Error removing node $nodeKey: $e');
        }
      }
    }
  }

  // Subscribe to real-time onValue updates
  final subscription = refDb.onValue.listen(
    (event) async {
      try {
        DbHelper.log('RTDB Sync: onValue triggered, exists: ${event.snapshot.exists}');
        await handleSnapshot(event.snapshot);
      } catch (e, stack) {
        DbHelper.log('RTDB Sync: Error inside onValue listener: $e\n$stack');
      }
    },
    onError: (err) {
      DbHelper.log('RTDB Sync: onValue stream error: $err');
    },
  );

  // Immediate initial fetch to drain any pre-existing inbox nodes
  refDb.get().then((snapshot) {
    if (snapshot.exists) {
      DbHelper.log('RTDB Sync: Initial inbox fetch found nodes for UID $uid');
      handleSnapshot(snapshot);
    }
  }).catchError((e) {
    DbHelper.log('RTDB Sync: Initial inbox fetch error: $e');
  });

  // Also listen/fetch legacy profile inbox path if owner.id ≠ firebase uid
  StreamSubscription? legacySubscription;
  if (ownerProfile != null && ownerProfile.id.isNotEmpty && ownerProfile.id != uid) {
    final legacyRef = FirebaseDatabase.instance.ref('sync_payloads/${ownerProfile.id}');
    DbHelper.log('RTDB Sync: Subscribing to legacy path: sync_payloads/${ownerProfile.id}');
    legacySubscription = legacyRef.onValue.listen((event) async {
      try {
        if (event.snapshot.exists) await handleSnapshot(event.snapshot);
      } catch (e) {
        DbHelper.log('RTDB Sync: Error handling legacy snapshot: $e');
      }
    });
    legacyRef.get().then((snapshot) {
      if (snapshot.exists) {
        DbHelper.log('RTDB Sync: Initial legacy inbox fetch found nodes for ${ownerProfile.id}');
        handleSnapshot(snapshot);
      }
    }).catchError((e) {
      DbHelper.log('RTDB Sync: Initial legacy inbox fetch error: $e');
    });
  }

  ref.onDispose(() {
    DbHelper.log('Stopping RTDB sync listener for UID: $uid');
    subscription.cancel();
    legacySubscription?.cancel();
  });
});

// ---------------------------------------------------------------------------
// NOTE: processIncomingRtdbSyncPayload has been moved to SyncPayloadProcessor.
// NOTE: processSyncAck, handleIncomingAck, _clearItemizedDirtyFlags have been
//       moved to SyncAckHandler.
// The re-exported processSyncAck() shim at the top of this file maintains
// backward compatibility for SyncRepositoryImpl which imports it.
// ---------------------------------------------------------------------------
