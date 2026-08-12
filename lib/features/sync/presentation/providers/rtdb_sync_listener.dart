import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sqflite/sqflite.dart';
import '../../../../core/utils/db_helper.dart';
import '../../../../core/constants/app_constants.dart';
import '../../data/datasources/compression_helper.dart';
import '../../data/datasources/sync_ingestor.dart';
import 'auth_provider.dart';
import 'sync_provider.dart';
import '../../../profiles/presentation/providers/active_profile_provider.dart';
import '../../../onboarding/presentation/providers/onboarding_provider.dart';
import '../../../home/presentation/providers/home_provider.dart';
import '../../../medications/presentation/providers/medications_provider.dart';
import '../../../history/presentation/providers/history_provider.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../../settings/presentation/services/reminder_scheduler.dart';

/// Manually checks and consumes any pending inbox payloads at sync_payloads/$uid in RTDB
Future<void> consumePendingInboxPayloads(Ref ref) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;
  if (firebaseUser == null) return;

  final uid = firebaseUser.uid;
  final refDb = FirebaseDatabase.instance.ref('sync_payloads/$uid');
  try {
    final snapshot = await refDb.get();
    if (snapshot.exists && snapshot.value != null) {
      DbHelper.log(
        'RTDB Sync: Manual inbox check found pending payloads for UID $uid',
      );
      final rawValue = snapshot.value;
      if (rawValue is Map) {
        final payloadsMap = <String, Map<String, dynamic>>{};
        rawValue.forEach((key, val) {
          if (val is Map) {
            final data = <String, dynamic>{};
            val.forEach((k, v) {
              data[k.toString()] = v;
            });
            payloadsMap[key.toString()] = data;
          }
        });

        for (final entry in payloadsMap.entries) {
          final nodeKey = entry.key;
          final data = entry.value;
          if (data['sync_id'] == null) {
            data['sync_id'] = nodeKey;
          }
          final eventType = data['event_type'] as String?;
          try {
            if (eventType != 'sync_ack' && !nodeKey.endsWith('_ack')) {
              await processIncomingRtdbSyncPayload(data, ref);
            }
          } catch (e) {
            DbHelper.log(
              'RTDB Sync: Error processing manual payload $nodeKey: $e',
            );
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

final rtdbSyncListenerProvider = Provider<void>((ref) {
  final authState = ref.watch(authProvider);
  final firebaseUser = authState.firebaseUser;

  if (firebaseUser == null) {
    DbHelper.log(
      'RTDB Sync: firebaseUser is null. Skipping listener initialization.',
    );
    return;
  }

  // Use ref.read instead of ref.watch so profile state updates do NOT tear down/re-subscribe RTDB listeners
  final ownerProfileAsync = ref.read(ownerProfileProvider);
  final ownerProfile = ownerProfileAsync.valueOrNull;
  var appCode = ownerProfile?.appCode;

  final uid = firebaseUser.uid;
  final refDb = FirebaseDatabase.instance.ref('sync_payloads/$uid');

  DbHelper.log(
    'Starting RTDB sync listener and poll for UID: $uid (AppCode: $appCode)',
  );

  // Force database connection online and keep this node synced
  try {
    FirebaseDatabase.instance.setPersistenceEnabled(false);
    FirebaseDatabase.instance.goOnline();
    refDb.keepSynced(true);
    DbHelper.log(
      'RTDB Sync: database persistence disabled, forced online, and keepSynced set to true for UID: $uid',
    );
  } catch (e) {
    DbHelper.log(
      'RTDB Sync: Failed to force online/keepSynced/disablePersistence: $e',
    );
  }

  Future<void> handleSnapshot(DataSnapshot snapshot) async {
    if (!snapshot.exists || snapshot.value == null) return;

    final rawValue = snapshot.value;
    if (rawValue is! Map) {
      DbHelper.log(
        'RTDB Sync: Snapshot value is not a Map: ${rawValue.runtimeType}',
      );
      return;
    }

    // Convert Map safely to Map<String, Map<String, dynamic>>
    final payloadsMap = <String, Map<String, dynamic>>{};
    rawValue.forEach((key, val) {
      if (val is Map) {
        final data = <String, dynamic>{};
        val.forEach((k, v) {
          data[k.toString()] = v;
        });
        payloadsMap[key.toString()] = data;
      }
    });

    if (payloadsMap.isEmpty) return;
    DbHelper.log('RTDB Sync: Found ${payloadsMap.length} payloads to process.');

    for (final entry in payloadsMap.entries) {
      final nodeKey = entry.key;
      final data = entry.value;
      if (data['sync_id'] == null) {
        data['sync_id'] = nodeKey;
      }

      final eventType = data['event_type'] as String?;

      try {
        if (eventType == 'sync_ack' || nodeKey.endsWith('_ack')) {
          // Handle incoming acknowledgment from the other device
          DbHelper.log(
            'RTDB Sync: Received sync_ack for nodeKey=$nodeKey, status=${data['status']}',
          );
          await handleIncomingAck(data, ref);
        } else {
          // Handle incoming sync payload (sync_update / sync_restore)
          DbHelper.log(
            'RTDB Sync: Processing payload nodeKey=$nodeKey (event_type=$eventType)',
          );
          await processIncomingRtdbSyncPayload(data, ref);

          // Invalidate providers to refresh the UI in real-time
          ref.invalidate(profilesListProvider);
          ref.invalidate(homeDosesProvider);
          ref.invalidate(medicinesListProvider);
          ref.invalidate(adherenceReportsProvider);
          ref.invalidate(historySelectedDateDosesProvider);
          ref.invalidate(settingsStateProvider);

          // Reschedule all active reminders based on the new sync data
          await ref.read(reminderSchedulerProvider).rescheduleAll();
        }
      } catch (e, stack) {
        DbHelper.log('RTDB Sync: Error processing node $nodeKey: $e\n$stack');
      } finally {
        // ALWAYS delete the node from RTDB to keep DB storage clean and unblock future uploads
        try {
          await refDb.child(nodeKey).remove();
          DbHelper.log('RTDB Sync: Consumed and deleted node: $nodeKey');
        } catch (e) {
          DbHelper.log('RTDB Sync: Error removing node $nodeKey from RTDB: $e');
        }
      }
    }
  }

  // 1. Listen to onValue updates for real-time push sync & pull requests
  final subscription = refDb.onValue.listen(
    (event) async {
      try {
        DbHelper.log(
          'RTDB Sync: onValue triggered, exists: ${event.snapshot.exists}',
        );
        await handleSnapshot(event.snapshot);
      } catch (e, stack) {
        DbHelper.log(
          'RTDB Sync: Error inside onValue listener callback: $e\n$stack',
        );
      }
    },
    onError: (err) {
      DbHelper.log(
        'RTDB Sync: onValue listener encountered stream error: $err',
      );
    },
  );

  // Perform immediate initial fetch to process any pre-existing inbox nodes
  refDb
      .get()
      .then((snapshot) {
        if (snapshot.exists) {
          DbHelper.log(
            'RTDB Sync: Initial inbox fetch found nodes for UID $uid',
          );
          handleSnapshot(snapshot);
        }
      })
      .catchError((e) {
        DbHelper.log('RTDB Sync: Initial inbox fetch error: $e');
      });

  // If ownerProfile.id is different from firebaseUser.uid, also listen/fetch legacy inbox node
  StreamSubscription? legacySubscription;
  if (ownerProfile != null &&
      ownerProfile.id.isNotEmpty &&
      ownerProfile.id != uid) {
    final legacyRef = FirebaseDatabase.instance.ref(
      'sync_payloads/${ownerProfile.id}',
    );
    DbHelper.log(
      'RTDB Sync: Subscribing to legacy profile inbox path: sync_payloads/${ownerProfile.id}',
    );
    legacySubscription = legacyRef.onValue.listen((event) async {
      try {
        if (event.snapshot.exists) {
          await handleSnapshot(event.snapshot);
        }
      } catch (e) {
        DbHelper.log('RTDB Sync: Error handling legacy snapshot: $e');
      }
    });
    legacyRef
        .get()
        .then((snapshot) {
          if (snapshot.exists) {
            DbHelper.log(
              'RTDB Sync: Initial legacy inbox fetch found nodes for ${ownerProfile.id}',
            );
            handleSnapshot(snapshot);
          }
        })
        .catchError((e) {
          DbHelper.log('RTDB Sync: Initial legacy inbox fetch error: $e');
        });
  }

  ref.onDispose(() {
    DbHelper.log('Stopping RTDB sync listener for UID: $uid');
    subscription.cancel();
    legacySubscription?.cancel();
  });
});

Future<void> processIncomingRtdbSyncPayload(
  Map<String, dynamic> data, [
  Ref? ref,
]) async {
  final db = await DbHelper.instance.database;
  final syncId = data['sync_id'] as String?;
  if (syncId == null) return;

  final senderUid = data['sender_uid'] as String?;
  final compressedData = data['compressed_data'] as String?;
  final checksum = data['checksum'] as String?;

  if (compressedData == null || checksum == null) {
    DbHelper.log(
      'RTDB Sync: Ingestion error for $syncId - compressedData or checksum is null',
    );
    return;
  }

  final senderAppId =
      data['sender_app_id'] as String? ?? data['sender_app_code'] as String?;
  final ownerResults = await db.query(
    AppConstants.tableProfiles,
    where: 'is_owner = ?',
    whereArgs: [1],
    limit: 1,
  );
  final ownerAppCode = ownerResults.isNotEmpty
      ? ownerResults.first['app_code'] as String?
      : null;

  // Ignore self-echoed sync payloads uploaded by the current device instance
  if (senderAppId != null &&
      ownerAppCode != null &&
      senderAppId == ownerAppCode) {
    DbHelper.log(
      'RTDB Sync: Skipping self-echoed sync payload for syncId=$syncId (appCode=$ownerAppCode)',
    );
    return;
  }

  try {
    final String jsonString;
    if (compressedData == '{}' || compressedData.trim().startsWith('{')) {
      jsonString = compressedData;
    } else {
      final decodedBytes = CompressionHelper.fromBase64(compressedData);
      jsonString = CompressionHelper.decompress(decodedBytes);
    }
    final computedChecksum = CompressionHelper.computeChecksum(jsonString);

    if (computedChecksum != checksum) {
      throw Exception('MD5 checksum validation failed');
    }

    final Map<String, dynamic> payload = json.decode(jsonString);

    DbHelper.log(
      'RTDB Sync: Decoded payload for $syncId successfully. Starting database transaction.',
    );

    final allLocalProfiles = await db.query(AppConstants.tableProfiles);
    final localProfileIds = allLocalProfiles
        .map((p) => p['id'] as String)
        .toSet();
    final ownerResults = allLocalProfiles
        .where((p) => p['is_owner'] == 1)
        .toList();
    final ownerProfileId = ownerResults.isNotEmpty
        ? ownerResults.first['id'] as String
        : null;
    final firebaseUser = FirebaseAuth.instance.currentUser;

    String resolveProfileId(String? rowProfileId) {
      if (rowProfileId != null && localProfileIds.contains(rowProfileId)) {
        return rowProfileId;
      }
      if (senderUid != null &&
          senderUid.isNotEmpty &&
          localProfileIds.contains(senderUid)) {
        return senderUid;
      }
      if (firebaseUser != null &&
          (rowProfileId == firebaseUser.uid ||
              rowProfileId == ownerProfileId)) {
        if (ownerProfileId != null) {
          return ownerProfileId;
        }
      }
      if (senderUid != null && senderUid.isNotEmpty) {
        return senderUid;
      }
      return rowProfileId ?? ownerProfileId ?? '';
    }

    String? localParentProfileId;

    await db.transaction((txn) async {
      // Find matching local non-owner parent profile by senderAppId or senderUid
      final matchingParentProfiles = await txn.query(
        AppConstants.tableProfiles,
        where: '(app_code = ? OR id = ?) AND is_owner = 0',
        whereArgs: [senderAppId ?? '', senderUid ?? ''],
      );

      if (matchingParentProfiles.isNotEmpty) {
        localParentProfileId = matchingParentProfiles.first['id'] as String;
      } else {
        final nonOwnerProfiles = await txn.query(
          AppConstants.tableProfiles,
          where: 'is_owner = ?',
          whereArgs: [0],
        );
        localParentProfileId = nonOwnerProfiles.isNotEmpty
            ? (nonOwnerProfiles.first['id'] as String)
            : null;
      }

      Future<String> resolveAndEnsureProfileId(String? rowProfileId) async {
        final targetId = localParentProfileId;
        if (targetId != null && targetId.isNotEmpty) {
          return targetId;
        }

        if (rowProfileId != null && rowProfileId.isNotEmpty) {
          final res = await txn.rawQuery(
            'SELECT id FROM profiles WHERE id = ?',
            [rowProfileId],
          );
          if (res.isNotEmpty) return rowProfileId;
        }

        if (senderUid != null && senderUid.isNotEmpty) {
          final res = await txn.rawQuery(
            'SELECT id FROM profiles WHERE id = ?',
            [senderUid],
          );
          if (res.isNotEmpty) return senderUid;
        }

        if (ownerProfileId != null && ownerProfileId.isNotEmpty) {
          return ownerProfileId;
        }

        final fallbackId = rowProfileId ?? senderUid ?? 'synced_profile';
        final uniqueName =
            'Synced Profile ${DateTime.now().millisecondsSinceEpoch}';
        await txn.insert(AppConstants.tableProfiles, {
          'id': fallbackId,
          'app_code': 'SYNC',
          'profile_name': uniqueName,
          'is_owner': 0,
          'created_at': DateTime.now().millisecondsSinceEpoch,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
          'is_dirty': 0,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        return fallbackId;
      }

      // 1. Ingest Profiles first (if payload includes profiles)
      if (payload.containsKey('profiles')) {
        final list = payload['profiles'] as List;
        DbHelper.log('RTDB Sync: Ingesting ${list.length} profiles in txn.');
        for (final profMap in list) {
          final map = Map<String, dynamic>.from(profMap as Map);
          map['is_dirty'] = 0;

          if (localParentProfileId != null) {
            // On Caretaker device: preserve local parent profile ID, local profile_name, and non-owner status
            final existingProf = await txn.query(
              AppConstants.tableProfiles,
              where: 'id = ?',
              whereArgs: [localParentProfileId],
              limit: 1,
            );
            final existingName = existingProf.isNotEmpty
                ? (existingProf.first['profile_name'] as String?)
                : null;

            map['id'] = localParentProfileId;
            map['is_owner'] = 0;
            if (existingName != null && existingName.isNotEmpty) {
              map['profile_name'] = existingName;
            } else {
              map['profile_name'] =
                  map['profile_name'] ?? map['name'] ?? 'Parent Profile';
            }
          } else {
            // On Owner device: check if incoming profile corresponds to local owner
            final existingOwnerProf = await txn.query(
              AppConstants.tableProfiles,
              where: 'is_owner = 1',
              limit: 1,
            );
            if (existingOwnerProf.isNotEmpty) {
              final ownerProfileMap = existingOwnerProf.first;
              final ownerId = ownerProfileMap['id'] as String;
              final ownerAppCode = ownerProfileMap['app_code'] as String?;
              final incomingAppCode = map['app_code'] as String?;
              final incomingId = map['id'] as String?;

              if (incomingId == ownerId ||
                  (incomingAppCode != null &&
                      incomingAppCode == ownerAppCode) ||
                  map['is_owner'] == 1 ||
                  (map['profile_type'] == 'Parent' &&
                      ownerProfileMap['profile_type'] == 'Parent')) {
                // Match! Map incoming profile data to local owner ID and preserve owner status
                map['id'] = ownerId;
                map['is_owner'] = 1;
                if (ownerProfileMap['profile_name'] != null &&
                    (ownerProfileMap['profile_name'] as String).isNotEmpty) {
                  map['profile_name'] = ownerProfileMap['profile_name'];
                }
              }
            } else {
              map['profile_name'] =
                  map['profile_name'] ?? map['name'] ?? 'Synced Profile';
            }
          }

          map.remove('name');

          final profId = map['id'] as String?;
          if (profId != null && profId.isNotEmpty) {
            final existing = await txn.query(
              AppConstants.tableProfiles,
              where: 'id = ?',
              whereArgs: [profId],
              limit: 1,
            );
            if (existing.isNotEmpty) {
              await txn.update(
                AppConstants.tableProfiles,
                map,
                where: 'id = ?',
                whereArgs: [profId],
              );
            } else {
              await txn.insert(
                AppConstants.tableProfiles,
                map,
                conflictAlgorithm: ConflictAlgorithm.ignore,
              );
            }
          } else {
            await txn.insert(
              AppConstants.tableProfiles,
              map,
              conflictAlgorithm: ConflictAlgorithm.ignore,
            );
          }
        }
      }

      // 2. Ingest Medicines
      if (payload.containsKey('medicines')) {
        final list = payload['medicines'] as List;
        DbHelper.log('RTDB Sync: Ingesting ${list.length} medicines in txn.');
        for (final medMap in list) {
          final map = Map<String, dynamic>.from(medMap as Map);
          final rowProfileId = map['profile_id'] as String?;
          map['profile_id'] = await resolveAndEnsureProfileId(rowProfileId);
          map['is_dirty'] = 0;

          final medId = map['id'] as String?;
          if (medId != null && medId.isNotEmpty) {
            final existing = await txn.query(
              AppConstants.tableMedicines,
              where: 'id = ?',
              whereArgs: [medId],
              limit: 1,
            );
            if (existing.isNotEmpty) {
              await txn.update(
                AppConstants.tableMedicines,
                map,
                where: 'id = ?',
                whereArgs: [medId],
              );
            } else {
              await txn.insert(
                AppConstants.tableMedicines,
                map,
                conflictAlgorithm: ConflictAlgorithm.ignore,
              );
            }
          } else {
            await txn.insert(
              AppConstants.tableMedicines,
              map,
              conflictAlgorithm: ConflictAlgorithm.ignore,
            );
          }
        }
      }

      // 3. Ingest Schedules
      if (payload.containsKey('schedules')) {
        final list = payload['schedules'] as List;
        DbHelper.log('RTDB Sync: Ingesting ${list.length} schedules in txn.');
        for (final schMap in list) {
          final map = Map<String, dynamic>.from(schMap as Map);
          final rowProfileId = map['profile_id'] as String?;
          map['profile_id'] = await resolveAndEnsureProfileId(rowProfileId);
          map['is_dirty'] = 0;

          final schId = map['id'] as String?;
          if (schId != null && schId.isNotEmpty) {
            final existing = await txn.query(
              AppConstants.tableSchedules,
              where: 'id = ?',
              whereArgs: [schId],
              limit: 1,
            );
            if (existing.isNotEmpty) {
              await txn.update(
                AppConstants.tableSchedules,
                map,
                where: 'id = ?',
                whereArgs: [schId],
              );
            } else {
              await txn.insert(
                AppConstants.tableSchedules,
                map,
                conflictAlgorithm: ConflictAlgorithm.ignore,
              );
            }
          } else {
            await txn.insert(
              AppConstants.tableSchedules,
              map,
              conflictAlgorithm: ConflictAlgorithm.ignore,
            );
          }
        }
      }

      // 4. Ingest Medicine Logs
      if (payload.containsKey('logs')) {
        final list = payload['logs'] as List;
        DbHelper.log('RTDB Sync: Ingesting ${list.length} logs in txn.');
        for (final logMap in list) {
          final map = Map<String, dynamic>.from(logMap as Map);
          final rowProfileId = map['profile_id'] as String?;
          map['profile_id'] = await resolveAndEnsureProfileId(rowProfileId);
          map['is_dirty'] = 0;
          await txn.insert(
            AppConstants.tableMedicineLog,
            map,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
    });

    final now = DateTime.now().millisecondsSinceEpoch;

    // Update local profile last_sync in SQLite DB for the specific profile associated with this payload
    final targetProfileId =
        localParentProfileId ??
        ((senderUid != null &&
                senderUid.isNotEmpty &&
                localProfileIds.contains(senderUid))
            ? senderUid
            : (ownerProfileId ?? ''));

    if (targetProfileId.isNotEmpty) {
      await db.update(
        AppConstants.tableProfiles,
        {'last_sync': now},
        where: 'id = ?',
        whereArgs: [targetProfileId],
      );
      DbHelper.log(
        'RTDB Sync: Updated last_sync for profile $targetProfileId to $now in SQLite.',
      );
    }

    if (ref != null) {
      ref.invalidate(profilesListProvider);
      ref.invalidate(homeDosesProvider);
      ref.invalidate(medicinesListProvider);

      final active = ref.read(activeProfileProvider);
      if (active != null && active.id == targetProfileId) {
        ref
            .read(activeProfileProvider.notifier)
            .setActiveProfile(active.copyWith(lastSync: now));
      }
    }

    DbHelper.log(
      'RTDB Sync: Ingested $syncId successfully. Sending ack to sender inbox.',
    );

    // Write ack to sender's inbox (bidirectional inbox model)
    if (senderUid != null && senderUid.isNotEmpty) {
      try {
        await FirebaseDatabase.instance
            .ref('sync_payloads/$senderUid/${syncId}_ack')
            .set({
              'event_type': 'sync_ack',
              'status': 'success',
              'original_sync_id': syncId,
              'sender_uid': FirebaseAuth.instance.currentUser?.uid ?? '',
              'sender_app_id': ownerAppCode ?? '',
              if (senderAppId != null) 'recipient_app_code': senderAppId,
              'timestamp': ServerValue.timestamp,
            });
        DbHelper.log(
          'RTDB Sync: Sent success ack to $senderUid for syncId=$syncId',
        );
      } catch (ackErr) {
        DbHelper.log(
          'RTDB Sync: Warning - failed to write remote ack for $syncId: $ackErr',
        );
      }
    }
  } catch (e, stack) {
    DbHelper.log(
      'RTDB Sync: Ingestion transaction failed for syncId=$syncId: $e\n$stack',
    );
    if (senderUid != null && senderUid.isNotEmpty) {
      try {
        await FirebaseDatabase.instance
            .ref('sync_payloads/$senderUid/${syncId}_ack')
            .set({
              'event_type': 'sync_ack',
              'status': 'failed',
              'original_sync_id': syncId,
              'failure_reason': e.toString(),
              'sender_uid': FirebaseAuth.instance.currentUser?.uid ?? '',
              'sender_app_id': ownerAppCode ?? '',
              if (senderAppId != null) 'recipient_app_code': senderAppId,
              'timestamp': ServerValue.timestamp,
            });
      } catch (_) {}
    }
  }
}

/// Clears dirty flags strictly for the row IDs included in the acknowledged payload batch,
/// provided the row has not been modified again (updated_at) since the payload was created.
Future<void> _clearItemizedDirtyFlags(
  Database db,
  Map<String, dynamic> payload,
) async {
  Future<void> clearTable(
    String tableName,
    String idCol,
    String keyName,
  ) async {
    if (payload.containsKey(keyName)) {
      final list = payload[keyName] as List?;
      if (list != null && list.isNotEmpty) {
        for (final item in list) {
          if (item is Map) {
            final id = item[idCol]?.toString();
            final itemUpdatedAt = item['updated_at'] as int?;
            if (id != null && id.isNotEmpty) {
              if (itemUpdatedAt != null) {
                // Only clear is_dirty if the row in SQLite has NOT been modified since this payload was built
                await db.update(
                  tableName,
                  {'is_dirty': 0},
                  where: '$idCol = ? AND updated_at = ? AND is_dirty = 1',
                  whereArgs: [id, itemUpdatedAt],
                );
              } else {
                await db.update(
                  tableName,
                  {'is_dirty': 0},
                  where: '$idCol = ? AND is_dirty = 1',
                  whereArgs: [id],
                );
              }
            }
          }
        }
      }
    }
  }

  await clearTable(AppConstants.tableProfiles, 'id', 'profiles');
  await clearTable(AppConstants.tableMedicines, 'id', 'medicines');
  await clearTable(AppConstants.tableSchedules, 'id', 'schedules');
  await clearTable(AppConstants.tableMedicineLog, 'id', 'logs');
}

/// Core helper to process a sync_ack data payload in SQLite.
/// Returns true if the ack was successfully matched and processed in tableSyncQueue.
Future<bool> processSyncAck(Database db, Map<String, dynamic> data) async {
  final status = data['status'] as String?;
  final originalSyncId = data['original_sync_id'] as String?;

  if (status != 'success') {
    DbHelper.log(
      'RTDB Sync Ack: Received non-success ack status=$status for originalSyncId=$originalSyncId. Reason: ${data['failure_reason']}',
    );
    return false;
  }

  if (originalSyncId == null || originalSyncId.isEmpty) {
    DbHelper.log('RTDB Sync Ack: originalSyncId is null or empty. Ignoring.');
    return false;
  }

  // Look up outgoing tracking record in tableSyncQueue
  final queueResults = await db.query(
    AppConstants.tableSyncQueue,
    where: 'sync_id = ? AND status = ?',
    whereArgs: [originalSyncId, 'pending_ack'],
    limit: 1,
  );

  if (queueResults.isEmpty) {
    DbHelper.log(
      'RTDB Sync Ack: Duplicate or unrecognized ack for sync_id=$originalSyncId. Ignoring without global clear.',
    );
    return false;
  }

  final item = queueResults.first;
  final compressedData = item['compressed_data'] as String?;

  if (compressedData != null && compressedData.isNotEmpty) {
    try {
      final String jsonString;
      if (compressedData == '{}' || compressedData.trim().startsWith('{')) {
        jsonString = compressedData;
      } else {
        final decodedBytes = CompressionHelper.fromBase64(compressedData);
        jsonString = CompressionHelper.decompress(decodedBytes);
      }
      final Map<String, dynamic> payload = json.decode(jsonString);
      await _clearItemizedDirtyFlags(db, payload);
    } catch (e) {
      DbHelper.log(
        'RTDB Sync Ack: Error parsing outgoing payload for $originalSyncId: $e',
      );
    }
  }

  // Delete acknowledged tracking record from tableSyncQueue to keep database storage clean
  await db.delete(
    AppConstants.tableSyncQueue,
    where: 'sync_id = ?',
    whereArgs: [originalSyncId],
  );

  final now = DateTime.now().millisecondsSinceEpoch;
  final ownerResults = await db.query(
    AppConstants.tableProfiles,
    where: 'is_owner = ?',
    whereArgs: [1],
    limit: 1,
  );
  if (ownerResults.isNotEmpty) {
    final ownerId = ownerResults.first['id'] as String;
    await db.update(
      AppConstants.tableProfiles,
      {'last_sync': now},
      where: 'id = ?',
      whereArgs: [ownerId],
    );
  }
  return true;
}

/// Handles an incoming sync_ack event from the other device.
/// Clears dirty flags for the acknowledged batch and updates last_sync in SQLite + Riverpod.
Future<void> handleIncomingAck(Map<String, dynamic> data, Ref ref) async {
  final db = await DbHelper.instance.database;
  final success = await processSyncAck(db, data);
  if (!success) return;

  final now = DateTime.now().millisecondsSinceEpoch;
  final activeProfile = ref.read(activeProfileProvider);
  if (activeProfile != null) {
    final updatedProfile = activeProfile.copyWith(lastSync: now);
    ref.read(activeProfileProvider.notifier).setActiveProfile(updatedProfile);
    DbHelper.log(
      'RTDB Sync Ack: Updated last_sync and processed batch ACK for profile ${activeProfile.id}',
    );
  }

  // Invalidate providers so UI instantly reflects (fully synced)
  ref.invalidate(homeDosesProvider);
  ref.invalidate(medicinesListProvider);
  ref.invalidate(settingsStateProvider);
}
