import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../../core/utils/db_helper.dart';
import '../datasources/sync_remote_datasource.dart';
import '../datasources/sync_local_datasource.dart';
import '../../presentation/providers/rtdb_sync_listener.dart';
import '../../domain/repositories/sync_repository.dart';

// SyncRepository interface lives in domain/repositories/sync_repository.dart
// Imported above — do not re-declare here.

class SyncRepositoryImpl implements SyncRepository {
  final SyncRemoteDataSource remoteDataSource;
  final SyncLocalDataSource localDataSource;

  SyncRepositoryImpl({
    required this.remoteDataSource,
    required this.localDataSource,
  });

  @override
  Future<void> markAllRowsDirty(String profileId) async {
    await localDataSource.markAllRowsDirty(profileId);
    DbHelper.log('SyncRepo: Marked all profile rows dirty for $profileId');
  }

  @override
  Future<void> syncAll(
    String activeProfileId, {
    int? caretakerLastSyncTime,
  }) async {
    // 1. Fetch active profile to check if it's caretaker or owner
    final activeProfile = await localDataSource.getProfileById(activeProfileId);
    if (activeProfile == null) return;
    final isOwner = activeProfile['is_owner'] as int == 1;

    // 2. Fetch owner profile details (needs app code)
    final ownerMap = await localDataSource.getOwnerProfile();
    if (ownerMap == null) return;
    final ownerFirebaseUid = ownerMap['id'] as String;
    final ownerAppCode = ownerMap['app_code'] as String?;
    if (ownerAppCode == null) return;

    final String currentAuthUid =
        FirebaseAuth.instance.currentUser?.uid ?? '';
    final List<String> inboxUidsToCheck = {
      if (currentAuthUid.isNotEmpty) currentAuthUid,
      ownerFirebaseUid,
    }.toList();

    if (isOwner && caretakerLastSyncTime == null) {
      // Pre-Sync Priority Check: Check if pending sync_acks or pull requests
      // exist in Parent's inbox
      for (final targetUid in inboxUidsToCheck) {
        try {
          final inboxRef =
              FirebaseDatabase.instance.ref('sync_payloads/$targetUid');
          final inboxSnap = await inboxRef.get();
          if (inboxSnap.exists && inboxSnap.value is Map) {
            final rawMap = inboxSnap.value as Map;
            for (final entry in rawMap.entries) {
              final nodeKey = entry.key.toString();
              final data =
                  Map<String, dynamic>.from(entry.value as Map);
              final eventType = data['event_type'] as String?;

              if (eventType == 'sync_ack' || nodeKey.endsWith('_ack')) {
                final db = await DbHelper.instance.database;
                final processed = await processSyncAck(db, data);
                if (processed) {
                  DbHelper.log(
                    'SyncRepo: Pre-sync pipeline - processed and removed sync_ack $nodeKey from $targetUid inbox',
                  );
                  await inboxRef.child(nodeKey).remove();
                } else {
                  DbHelper.log(
                    'SyncRepo: Pre-sync pipeline - sync_ack $nodeKey not recognized in queue; keeping node',
                  );
                }
              } else if (eventType == 'request_sync' ||
                  nodeKey.endsWith('_pull')) {
                final pendingTime =
                    data['caretakerLastSyncTime'] as int? ?? 0;
                DbHelper.log(
                  'SyncRepo: Pre-sync pipeline - consuming pending pull request $nodeKey (lastSync=$pendingTime) prior to push.',
                );
                caretakerLastSyncTime = pendingTime;
                await inboxRef.child(nodeKey).remove();
                break;
              }
            }
          }
        } catch (e) {
          DbHelper.log(
            'SyncRepo: Warning checking inbox $targetUid in pre-sync pipeline: $e',
          );
        }
      }
    }

    // 3. Fetch dirty rows based on role and sync mode
    List<Map<String, dynamic>> profiles;
    List<Map<String, dynamic>> medicines;
    List<Map<String, dynamic>> schedules;
    List<Map<String, dynamic>> logs;

    if (isOwner) {
      if (caretakerLastSyncTime != null) {
        // Parent is responding to a Caretaker pull request
        if (caretakerLastSyncTime > 0) {
          final ts = caretakerLastSyncTime;
          profiles = await localDataSource.getDirtyProfiles(
            activeProfileId,
            sinceTimestamp: ts,
          );
          medicines = await localDataSource.getDirtyMedicines(
            activeProfileId,
            sinceTimestamp: ts,
          );
          schedules = await localDataSource.getDirtySchedules(
            activeProfileId,
            sinceTimestamp: ts,
          );
          logs = await localDataSource.getDirtyLogs(
            activeProfileId,
            sinceTimestamp: ts,
          );
        } else {
          // Full restore pull response for Caretaker (caretakerLastSyncTime == 0)
          final all = await localDataSource.getAllSyncableRows();
          profiles = all['profiles']!;
          medicines = all['medicines']!;
          schedules = all['schedules']!;
          logs = all['logs']!;
        }
      } else {
        // Parent initiating push sync: query ONLY local dirty modifications
        profiles = await localDataSource.getDirtyProfiles(
          activeProfileId,
          allDirty: true,
        );
        medicines = await localDataSource.getDirtyMedicines(
          activeProfileId,
          allDirty: true,
        );
        schedules = await localDataSource.getDirtySchedules(
          activeProfileId,
          allDirty: true,
        );
        logs = await localDataSource.getDirtyLogs(
          activeProfileId,
          allDirty: true,
        );
      }
    } else {
      // Caretaker pushing modifications for the parent profile back to the parent
      profiles = await localDataSource.getDirtyProfiles(activeProfileId);
      medicines = await localDataSource.getDirtyMedicines(activeProfileId);
      schedules = await localDataSource.getDirtySchedules(activeProfileId);
      logs = await localDataSource.getDirtyLogs(activeProfileId);
    }

    if (caretakerLastSyncTime == null &&
        profiles.isEmpty &&
        medicines.isEmpty &&
        schedules.isEmpty &&
        logs.isEmpty) {
      // No local modifications to push
      return;
    }

    // 4. Build payload map (only include keys that have non-empty records)
    final Map<String, dynamic> payload = {};
    if (profiles.isNotEmpty) payload['profiles'] = profiles;
    if (medicines.isNotEmpty) payload['medicines'] = medicines;
    if (schedules.isNotEmpty) payload['schedules'] = schedules;
    if (logs.isNotEmpty) payload['logs'] = logs;

    final payloadJson = json.encode(payload);

    final recipients = <Map<String, String>>[];

    if (isOwner) {
      // Fetch all active connected caretakers from Cloud/RTDB
      final profileData =
          await remoteDataSource.lookupProfileByAppCode(ownerAppCode);
      if (profileData == null || !profileData.containsKey('connections')) {
        return;
      }

      final connections = Map<String, dynamic>.from(
        profileData['connections'] as Map,
      );
      connections.forEach((caretakerCode, caretakerData) {
        if (caretakerData is Map) {
          final targetUid = caretakerData['uid']?.toString();
          if (targetUid != null &&
              targetUid.isNotEmpty &&
              targetUid != 'null') {
            recipients.add({
              'uid': targetUid,
              'code': caretakerCode.toString(),
            });
          }
        }
      });
    } else {
      // Caretaker pushing back to the parent:
      // The parent's Firebase UID is exactly activeProfileId
      // The parent's App Code is activeProfile['app_code']
      final parentAppCode = activeProfile['app_code'] as String?;
      if (parentAppCode != null) {
        recipients.add({'uid': activeProfileId, 'code': parentAppCode});
      }
    }

    if (recipients.isEmpty) return;

    // 5. Resolve sender UID
    final String senderUid;
    if (currentAuthUid.isNotEmpty) {
      senderUid = currentAuthUid;
    } else if (isOwner) {
      senderUid = ownerFirebaseUid;
    } else {
      senderUid = activeProfileId;
    }

    // 6. Package and push to each recipient
    for (final recipient in recipients) {
      final recipientUid = recipient['uid']!;
      final recipientCode = recipient['code']!;

      // Resolve recipient FCM token
      final recipientProfile =
          await remoteDataSource.lookupProfileByAppCode(recipientCode);
      final recipientFcmToken =
          recipientProfile?['fcm_token'] as String? ?? '';

      final syncId = const Uuid().v4();

      try {
        await localDataSource.insertSyncQueueEntry({
          'sync_id': syncId,
          'sender_uid': senderUid,
          'sender_app_id': ownerAppCode,
          'event_type': 'outgoing_sync',
          'compressed_data': payloadJson,
          'status': 'pending_ack',
          'timestamp': DateTime.now().toUtc().millisecondsSinceEpoch,
          'received_at': DateTime.now().toUtc().millisecondsSinceEpoch,
        });

        await remoteDataSource.uploadSyncPayload(
          recipientUid: recipientUid,
          senderUid: senderUid,
          caretakerFcmToken: recipientFcmToken,
          senderAppCode: ownerAppCode,
          syncId: syncId,
          payloadJson: payloadJson,
          recipientAppCode: recipientCode,
        );

        DbHelper.log(
          'SyncRepo: Payload $syncId recorded in tableSyncQueue and uploaded to slot $recipientUid/$senderUid; awaiting sync_ack',
        );
      } catch (e) {
        debugPrint('Sync failed for recipient $recipientUid: $e');
        // Dirty flags remain set so user can retry later
      }
    }
  }

  @override
  Future<void> requestPullSync(
    String caretakerUid,
    String syncId,
    int caretakerLastSyncTime,
  ) async {
    // Caretakers no longer write pull requests to RTDB.
    // Sync data is pushed directly by the Parent upon modifications or pairing acceptance.
    DbHelper.log(
      'SyncRepo: requestPullSync invoked. Skipping pull request node creation.',
    );
  }

  @override
  Future<bool> hasDirtyRows(String? activeProfileId) async {
    return localDataSource.hasDirtyRows(activeProfileId);
  }
}
