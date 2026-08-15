import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../../../../core/utils/db_helper.dart';
import '../../../../core/constants/app_constants.dart';
import 'compression_helper.dart';
import '../../../profiles/presentation/providers/active_profile_provider.dart';
import '../../../onboarding/presentation/providers/onboarding_provider.dart';
import '../../../home/presentation/providers/home_provider.dart';
import '../../../medications/presentation/providers/medications_provider.dart';

/// Responsible for ingesting a single incoming RTDB sync payload into SQLite.
///
/// Extracted from [rtdb_sync_listener.dart] to satisfy SRP.
///
/// Responsibilities:
/// - Validate payload checksum
/// - Determine whether to skip self-echoed payloads
/// - Resolve profile ID mapping (owner vs caretaker)
/// - Run the multi-table SQLite ingest transaction
/// - Update `last_sync` timestamp
/// - Write success/failure ack back to sender's RTDB inbox
/// - Invalidate Riverpod providers so UI refreshes
class SyncPayloadProcessor {
  final Database db;

  SyncPayloadProcessor({required this.db});

  /// Processes a single incoming RTDB sync payload [data].
  ///
  /// Pass [ref] to allow Riverpod provider invalidation after ingestion.
  Future<void> process(Map<String, dynamic> data, [Ref? ref]) async {
    final syncId = data['sync_id'] as String?;
    if (syncId == null) return;

    final senderUid = data['sender_uid'] as String?;
    final compressedData = data['compressed_data'] as String?;
    final checksum = data['checksum'] as String?;

    if (compressedData == null || checksum == null) {
      DbHelper.log(
        'SyncPayloadProcessor: Ingestion error for $syncId — compressedData or checksum is null',
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
    final ownerAppCode =
        ownerResults.isNotEmpty ? ownerResults.first['app_code'] as String? : null;

    // Skip self-echoed payloads uploaded by the current device
    if (senderAppId != null && ownerAppCode != null && senderAppId == ownerAppCode) {
      DbHelper.log(
        'SyncPayloadProcessor: Skipping self-echoed payload syncId=$syncId (appCode=$ownerAppCode)',
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
        'SyncPayloadProcessor: Decoded payload for $syncId. Starting DB transaction.',
      );

      final allLocalProfiles = await db.query(AppConstants.tableProfiles);
      final localProfileIds = allLocalProfiles.map((p) => p['id'] as String).toSet();
      final ownerProfileId = ownerResults.isNotEmpty
          ? ownerResults.first['id'] as String
          : null;

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
          localParentProfileId =
              nonOwnerProfiles.isNotEmpty ? nonOwnerProfiles.first['id'] as String : null;
        }

        Future<String> resolveAndEnsureProfileId(String? rowProfileId) async {
          final targetId = localParentProfileId;
          if (targetId != null && targetId.isNotEmpty) return targetId;

          if (rowProfileId != null && rowProfileId.isNotEmpty) {
            final res = await txn.rawQuery('SELECT id FROM profiles WHERE id = ?', [rowProfileId]);
            if (res.isNotEmpty) return rowProfileId;
          }

          if (senderUid != null && senderUid.isNotEmpty) {
            final res = await txn.rawQuery('SELECT id FROM profiles WHERE id = ?', [senderUid]);
            if (res.isNotEmpty) return senderUid;
          }

          if (ownerProfileId != null && ownerProfileId.isNotEmpty) return ownerProfileId;

          final fallbackId = rowProfileId ?? senderUid ?? 'synced_profile';
          final uniqueName = 'Synced Profile ${DateTime.now().millisecondsSinceEpoch}';
          await txn.insert(
            AppConstants.tableProfiles,
            {
              'id': fallbackId,
              'app_code': 'SYNC',
              'profile_name': uniqueName,
              'is_owner': 0,
              'created_at': DateTime.now().millisecondsSinceEpoch,
              'updated_at': DateTime.now().millisecondsSinceEpoch,
              'is_dirty': 0,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
          return fallbackId;
        }

        // 1. Ingest Profiles
        if (payload.containsKey('profiles')) {
          final list = payload['profiles'] as List;
          DbHelper.log('SyncPayloadProcessor: Ingesting ${list.length} profiles.');
          for (final profMap in list) {
            final map = Map<String, dynamic>.from(profMap as Map);
            map['is_dirty'] = 0;

            if (localParentProfileId != null) {
              // Caretaker device: preserve local parent profile ID/name/ownership
              final existingProf = await txn.query(
                AppConstants.tableProfiles,
                where: 'id = ?',
                whereArgs: [localParentProfileId],
                limit: 1,
              );
              final existingName =
                  existingProf.isNotEmpty ? existingProf.first['profile_name'] as String? : null;
              map['id'] = localParentProfileId;
              map['is_owner'] = 0;
              if (existingName != null && existingName.isNotEmpty) {
                map['profile_name'] = existingName;
              } else {
                map['profile_name'] = map['profile_name'] ?? map['name'] ?? 'Parent Profile';
              }
            } else {
              // Owner device: check if incoming profile is the local owner
              final existingOwnerProf =
                  await txn.query(AppConstants.tableProfiles, where: 'is_owner = 1', limit: 1);
              if (existingOwnerProf.isNotEmpty) {
                final ownerProfileMap = existingOwnerProf.first;
                final ownerId = ownerProfileMap['id'] as String;
                final localOwnerAppCode = ownerProfileMap['app_code'] as String?;
                final incomingAppCode = map['app_code'] as String?;
                final incomingId = map['id'] as String?;

                if (incomingId == ownerId ||
                    (incomingAppCode != null && incomingAppCode == localOwnerAppCode) ||
                    map['is_owner'] == 1 ||
                    (map['profile_type'] == 'Parent' &&
                        ownerProfileMap['profile_type'] == 'Parent')) {
                  map['id'] = ownerId;
                  map['is_owner'] = 1;
                  if (ownerProfileMap['profile_name'] != null &&
                      (ownerProfileMap['profile_name'] as String).isNotEmpty) {
                    map['profile_name'] = ownerProfileMap['profile_name'];
                  }
                }
              } else {
                map['profile_name'] = map['profile_name'] ?? map['name'] ?? 'Synced Profile';
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
                await txn.update(AppConstants.tableProfiles, map, where: 'id = ?', whereArgs: [profId]);
              } else {
                await txn.insert(AppConstants.tableProfiles, map, conflictAlgorithm: ConflictAlgorithm.ignore);
              }
            } else {
              await txn.insert(AppConstants.tableProfiles, map, conflictAlgorithm: ConflictAlgorithm.ignore);
            }
          }
        }

        // 2. Ingest Medicines
        if (payload.containsKey('medicines')) {
          final list = payload['medicines'] as List;
          DbHelper.log('SyncPayloadProcessor: Ingesting ${list.length} medicines.');
          for (final medMap in list) {
            final map = Map<String, dynamic>.from(medMap as Map);
            map['profile_id'] = await resolveAndEnsureProfileId(map['profile_id'] as String?);
            map['is_dirty'] = 0;
            final medId = map['id'] as String?;
            if (medId != null && medId.isNotEmpty) {
              final existing = await txn.query(AppConstants.tableMedicines, where: 'id = ?', whereArgs: [medId], limit: 1);
              if (existing.isNotEmpty) {
                await txn.update(AppConstants.tableMedicines, map, where: 'id = ?', whereArgs: [medId]);
              } else {
                await txn.insert(AppConstants.tableMedicines, map, conflictAlgorithm: ConflictAlgorithm.ignore);
              }
            } else {
              await txn.insert(AppConstants.tableMedicines, map, conflictAlgorithm: ConflictAlgorithm.ignore);
            }
          }
        }

        // 3. Ingest Schedules
        if (payload.containsKey('schedules')) {
          final list = payload['schedules'] as List;
          DbHelper.log('SyncPayloadProcessor: Ingesting ${list.length} schedules.');
          for (final schMap in list) {
            final map = Map<String, dynamic>.from(schMap as Map);
            map['profile_id'] = await resolveAndEnsureProfileId(map['profile_id'] as String?);
            map['is_dirty'] = 0;
            final schId = map['id'] as String?;
            if (schId != null && schId.isNotEmpty) {
              final existing = await txn.query(AppConstants.tableSchedules, where: 'id = ?', whereArgs: [schId], limit: 1);
              if (existing.isNotEmpty) {
                await txn.update(AppConstants.tableSchedules, map, where: 'id = ?', whereArgs: [schId]);
              } else {
                await txn.insert(AppConstants.tableSchedules, map, conflictAlgorithm: ConflictAlgorithm.ignore);
              }
            } else {
              await txn.insert(AppConstants.tableSchedules, map, conflictAlgorithm: ConflictAlgorithm.ignore);
            }
          }
        }

        // 4. Ingest Medicine Logs
        if (payload.containsKey('logs')) {
          final list = payload['logs'] as List;
          DbHelper.log('SyncPayloadProcessor: Ingesting ${list.length} logs.');
          for (final logMap in list) {
            final map = Map<String, dynamic>.from(logMap as Map);
            map['profile_id'] = await resolveAndEnsureProfileId(map['profile_id'] as String?);
            map['is_dirty'] = 0;
            await txn.insert(AppConstants.tableMedicineLog, map, conflictAlgorithm: ConflictAlgorithm.replace);
          }
        }
      });

      final now = DateTime.now().millisecondsSinceEpoch;

      // Update last_sync for the relevant local profile
      final targetProfileId = localParentProfileId ??
          ((senderUid != null && senderUid.isNotEmpty && localProfileIds.contains(senderUid))
              ? senderUid
              : (ownerProfileId ?? ''));

      if (targetProfileId.isNotEmpty) {
        await db.update(
          AppConstants.tableProfiles,
          {'last_sync': now},
          where: 'id = ?',
          whereArgs: [targetProfileId],
        );
        DbHelper.log('SyncPayloadProcessor: Updated last_sync for profile $targetProfileId.');
      }

      if (ref != null) {
        ref.invalidate(profilesListProvider);
        ref.invalidate(homeDosesProvider);
        ref.invalidate(medicinesListProvider);
        final active = ref.read(activeProfileProvider);
        if (active != null && active.id == targetProfileId) {
          ref.read(activeProfileProvider.notifier).setActiveProfile(active.copyWith(lastSync: now));
        }
      }

      DbHelper.log('SyncPayloadProcessor: Ingested $syncId. Sending ack to $senderUid.');

      // Write ack to sender's inbox
      if (senderUid != null && senderUid.isNotEmpty) {
        try {
          await FirebaseDatabase.instance.ref('sync_payloads/$senderUid/${syncId}_ack').set({
            'event_type': 'sync_ack',
            'status': 'success',
            'original_sync_id': syncId,
            'sender_uid': FirebaseAuth.instance.currentUser?.uid ?? '',
            'sender_app_id': ownerAppCode ?? '',
            if (senderAppId != null) 'recipient_app_code': senderAppId,
            'timestamp': ServerValue.timestamp,
          });
        } catch (ackErr) {
          DbHelper.log('SyncPayloadProcessor: Warning — failed to write ack for $syncId: $ackErr');
        }
      }
    } catch (e, stack) {
      DbHelper.log('SyncPayloadProcessor: Transaction failed for $syncId: $e\n$stack');
      final senderUidForNack = data['sender_uid'] as String?;
      if (senderUidForNack != null && senderUidForNack.isNotEmpty) {
        try {
          await FirebaseDatabase.instance.ref('sync_payloads/$senderUidForNack/${syncId}_ack').set({
            'event_type': 'sync_ack',
            'status': 'failed',
            'original_sync_id': syncId,
            'failure_reason': e.toString(),
            'sender_uid': FirebaseAuth.instance.currentUser?.uid ?? '',
            'sender_app_id': ownerAppCode,
            if (senderAppId != null) 'recipient_app_code': senderAppId,
            'timestamp': ServerValue.timestamp,
          });
        } catch (_) {}
      }
    }
  }
}
