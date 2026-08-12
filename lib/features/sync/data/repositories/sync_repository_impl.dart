import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:sqflite/sqflite.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../../core/utils/db_helper.dart';
import '../../../../core/constants/app_constants.dart';
import '../datasources/sync_remote_datasource.dart';
import '../../presentation/providers/rtdb_sync_listener.dart';

abstract class SyncRepository {
  Future<void> syncAll(String activeProfileId, {int? caretakerLastSyncTime});
  Future<void> requestPullSync(
    String caretakerUid,
    String syncId,
    int caretakerLastSyncTime,
  );
  Future<bool> hasDirtyRows(String? activeProfileId);
  Future<void> markAllRowsDirty(String profileId);
}

class SyncRepositoryImpl implements SyncRepository {
  final SyncRemoteDataSource remoteDataSource;

  SyncRepositoryImpl({required this.remoteDataSource});

  @override
  Future<void> markAllRowsDirty(String profileId) async {
    final db = await DbHelper.instance.database;
    await db.transaction((txn) async {
      await txn.update(
        AppConstants.tableProfiles,
        {'is_dirty': 1},
        where: 'id = ?',
        whereArgs: [profileId],
      );
      await txn.update(
        AppConstants.tableMedicines,
        {'is_dirty': 1},
        where: 'profile_id = ?',
        whereArgs: [profileId],
      );
      await txn.update(
        AppConstants.tableSchedules,
        {'is_dirty': 1},
        where: 'profile_id = ?',
        whereArgs: [profileId],
      );
      await txn.update(
        AppConstants.tableMedicineLog,
        {'is_dirty': 1},
        where: 'profile_id = ?',
        whereArgs: [profileId],
      );
    });
    DbHelper.log('SyncRepo: Marked all profile rows dirty for $profileId');
  }

  @override
  Future<void> syncAll(
    String activeProfileId, {
    int? caretakerLastSyncTime,
  }) async {
    final db = await DbHelper.instance.database;

    // 1. Fetch active profile to check if it's caretaker or owner
    final activeProfileResults = await db.query(
      AppConstants.tableProfiles,
      where: 'id = ?',
      whereArgs: [activeProfileId],
      limit: 1,
    );
    if (activeProfileResults.isEmpty) return;
    final activeProfile = activeProfileResults.first;
    final isOwner = activeProfile['is_owner'] as int == 1;

    // 2. Fetch owner profile details (needs app code)
    final ownerResults = await db.query(
      AppConstants.tableProfiles,
      where: 'is_owner = ?',
      whereArgs: [1],
      limit: 1,
    );
    if (ownerResults.isEmpty) return;
    final ownerMap = ownerResults.first;
    final ownerFirebaseUid = ownerMap['id'] as String;
    final ownerAppCode = ownerMap['app_code'] as String?;
    if (ownerAppCode == null) return;

    final String currentAuthUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final List<String> inboxUidsToCheck = {
      if (currentAuthUid.isNotEmpty) currentAuthUid,
      ownerFirebaseUid,
    }.toList();

    if (isOwner && caretakerLastSyncTime == null) {
      // Pre-Sync Priority Check: Check if pending sync_acks or pull requests exist in Parent's inbox
      for (final targetUid in inboxUidsToCheck) {
        try {
          final inboxRef = FirebaseDatabase.instance.ref('sync_payloads/$targetUid');
          final inboxSnap = await inboxRef.get();
          if (inboxSnap.exists && inboxSnap.value is Map) {
            final rawMap = inboxSnap.value as Map;
            for (final entry in rawMap.entries) {
              final nodeKey = entry.key.toString();
              final data = Map<String, dynamic>.from(entry.value as Map);
              final eventType = data['event_type'] as String?;

              if (eventType == 'sync_ack' || nodeKey.endsWith('_ack')) {
                final processed = await processSyncAck(db, data);
                if (processed) {
                  DbHelper.log('SyncRepo: Pre-sync pipeline - processed and removed sync_ack $nodeKey from $targetUid inbox');
                  await inboxRef.child(nodeKey).remove();
                } else {
                  DbHelper.log('SyncRepo: Pre-sync pipeline - sync_ack $nodeKey not recognized in queue; keeping node');
                }
              } else if (eventType == 'request_sync' || nodeKey.endsWith('_pull')) {
                final pendingTime = data['caretakerLastSyncTime'] as int? ?? 0;
                DbHelper.log('SyncRepo: Pre-sync pipeline - consuming pending pull request $nodeKey (lastSync=$pendingTime) prior to push.');
                caretakerLastSyncTime = pendingTime;
                await inboxRef.child(nodeKey).remove();
                break;
              }
            }
          }
        } catch (e) {
          DbHelper.log('SyncRepo: Warning checking inbox $targetUid in pre-sync pipeline: $e');
        }
      }
    }

    List<Map<String, dynamic>> profiles;
    List<Map<String, dynamic>> medicines;
    List<Map<String, dynamic>> schedules;
    List<Map<String, dynamic>> logs;

    if (isOwner) {
      if (caretakerLastSyncTime != null) {
        // Parent is responding to a Caretaker pull request
        if (caretakerLastSyncTime > 0) {
          final queryTime = caretakerLastSyncTime;
          profiles = await db.query(
            AppConstants.tableProfiles,
            where: 'updated_at > ? OR is_dirty = ?',
            whereArgs: [queryTime, 1],
          );
          medicines = await db.query(
            AppConstants.tableMedicines,
            where: 'updated_at > ? OR is_dirty = ?',
            whereArgs: [queryTime, 1],
          );
          schedules = await db.query(
            AppConstants.tableSchedules,
            where: 'updated_at > ? OR is_dirty = ?',
            whereArgs: [queryTime, 1],
          );
          logs = await db.query(
            AppConstants.tableMedicineLog,
            where: 'updated_at > ? OR is_dirty = ?',
            whereArgs: [queryTime, 1],
          );
        } else {
          // Full restore pull response for Caretaker (caretakerLastSyncTime == 0)
          profiles = await db.query(AppConstants.tableProfiles);
          medicines = await db.query(AppConstants.tableMedicines);
          schedules = await db.query(AppConstants.tableSchedules);
          logs = await db.query(AppConstants.tableMedicineLog);
        }
      } else {
        // Parent initiating push sync from Parent app: query ONLY local dirty modifications
        profiles = await db.query(
          AppConstants.tableProfiles,
          where: 'is_dirty = ?',
          whereArgs: [1],
        );
        medicines = await db.query(
          AppConstants.tableMedicines,
          where: 'is_dirty = ?',
          whereArgs: [1],
        );
        schedules = await db.query(
          AppConstants.tableSchedules,
          where: 'is_dirty = ?',
          whereArgs: [1],
        );
        logs = await db.query(
          AppConstants.tableMedicineLog,
          where: 'is_dirty = ?',
          whereArgs: [1],
        );
      }
    } else {
      // Caretaker pushing modifications for the parent profile back to the parent
      profiles = await db.query(
        AppConstants.tableProfiles,
        where: 'id = ? AND is_dirty = ?',
        whereArgs: [activeProfileId, 1],
      );
      medicines = await db.query(
        AppConstants.tableMedicines,
        where: 'profile_id = ? AND is_dirty = ?',
        whereArgs: [activeProfileId, 1],
      );
      schedules = await db.query(
        AppConstants.tableSchedules,
        where: 'profile_id = ? AND is_dirty = ?',
        whereArgs: [activeProfileId, 1],
      );
      logs = await db.query(
        AppConstants.tableMedicineLog,
        where: 'profile_id = ? AND is_dirty = ?',
        whereArgs: [activeProfileId, 1],
      );
    }

    if (caretakerLastSyncTime == null &&
        profiles.isEmpty &&
        medicines.isEmpty &&
        schedules.isEmpty &&
        logs.isEmpty) {
      // No local modifications to push
      return;
    }

    // 3. Build payload map (only include keys that have non-empty records)
    final Map<String, dynamic> payload = {};
    if (profiles.isNotEmpty) payload['profiles'] = profiles;
    if (medicines.isNotEmpty) payload['medicines'] = medicines;
    if (schedules.isNotEmpty) payload['schedules'] = schedules;
    if (logs.isNotEmpty) payload['logs'] = logs;

    final payloadJson = json.encode(payload);

    final recipients = <Map<String, String>>[];

    if (isOwner) {
      // Fetch all active connected caretakers from Cloud/RTDB
      final profileData = await remoteDataSource.lookupProfileByAppCode(
        ownerAppCode,
      );
      if (profileData == null || !profileData.containsKey('connections'))
        return;

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

    // 5. Package and push to each recipient
    final String senderUid;
    if (currentAuthUid.isNotEmpty) {
      senderUid = currentAuthUid;
    } else if (isOwner) {
      senderUid = ownerFirebaseUid;
    } else {
      senderUid = activeProfileId;
    }

    for (final recipient in recipients) {
      final recipientUid = recipient['uid']!;
      final recipientCode = recipient['code']!;

      // Resolve recipient FCM token
      final recipientProfile = await remoteDataSource.lookupProfileByAppCode(
        recipientCode,
      );
      final recipientFcmToken = recipientProfile?['fcm_token'] as String? ?? '';

      final syncId = const Uuid().v4();

      try {
        await db.insert(
          AppConstants.tableSyncQueue,
          {
            'sync_id': syncId,
            'sender_uid': senderUid,
            'sender_app_id': ownerAppCode,
            'event_type': 'outgoing_sync',
            'compressed_data': payloadJson,
            'status': 'pending_ack',
            'timestamp': DateTime.now().toUtc().millisecondsSinceEpoch,
            'received_at': DateTime.now().toUtc().millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        // Upload sync payload to recipient's inbox (fire-and-forget to cloud)
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
    DbHelper.log('SyncRepo: requestPullSync invoked. Skipping pull request node creation.');
  }

  @override
  Future<bool> hasDirtyRows(String? activeProfileId) async {
    final db = await DbHelper.instance.database;
    if (activeProfileId != null) {
      final profilesCount = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) FROM ${AppConstants.tableProfiles} WHERE id = ? AND is_dirty = ?',
        [activeProfileId, 1],
      )) ?? 0;
      final medicinesCount = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) FROM ${AppConstants.tableMedicines} WHERE profile_id = ? AND is_dirty = ?',
        [activeProfileId, 1],
      )) ?? 0;
      final schedulesCount = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) FROM ${AppConstants.tableSchedules} WHERE profile_id = ? AND is_dirty = ?',
        [activeProfileId, 1],
      )) ?? 0;
      final logsCount = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) FROM ${AppConstants.tableMedicineLog} WHERE profile_id = ? AND is_dirty = ?',
        [activeProfileId, 1],
      )) ?? 0;
      if ((profilesCount + medicinesCount + schedulesCount + logsCount) > 0) {
        return true;
      }
    }
    final totalUnscoped = Sqflite.firstIntValue(await db.rawQuery('''
      SELECT 
        (SELECT COUNT(*) FROM ${AppConstants.tableProfiles} WHERE is_dirty = 1) +
        (SELECT COUNT(*) FROM ${AppConstants.tableMedicines} WHERE is_dirty = 1) +
        (SELECT COUNT(*) FROM ${AppConstants.tableSchedules} WHERE is_dirty = 1) +
        (SELECT COUNT(*) FROM ${AppConstants.tableMedicineLog} WHERE is_dirty = 1)
    ''')) ?? 0;
    return totalUnscoped > 0;
  }
}
