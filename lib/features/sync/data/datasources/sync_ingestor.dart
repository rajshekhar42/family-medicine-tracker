import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:sqflite/sqflite.dart';
import '../../../../core/utils/db_helper.dart';
import '../../../../core/constants/app_constants.dart';
import 'compression_helper.dart';

class SyncIngestor {
  SyncIngestor._();

  static Future<void> processQueue(Database db) async {
    // Expire stale chunks older than 60 seconds
    final cutoff = DateTime.now().millisecondsSinceEpoch - 60000;
    await db.delete(
      AppConstants.tableChunkBuffer,
      where: 'received_at < ?',
      whereArgs: [cutoff],
    );

    // Reset any stuck 'processing' items back to 'pending' (recovery)
    await db.update(
      AppConstants.tableSyncQueue,
      {'status': 'pending'},
      where: 'status = ?',
      whereArgs: ['processing'],
    );

    while (true) {
      final List<Map<String, dynamic>> pending = await db.query(
        AppConstants.tableSyncQueue,
        where: 'status = ? AND (event_type IS NULL OR event_type != ?)',
        whereArgs: ['pending', 'outgoing_sync'],
        orderBy: 'received_at ASC',
        limit: 1,
      );

      if (pending.isEmpty) break;

      final item = pending.first;
      final syncId = item['sync_id'] as String;

      await db.update(
        AppConstants.tableSyncQueue,
        {'status': 'processing'},
        where: 'sync_id = ?',
        whereArgs: [syncId],
      );
      final senderUid = item['sender_uid'] as String?;
      final senderAppId = item['sender_app_id'] as String?;

      try {
        final compressedData = item['compressed_data'] as String;
        final checksum = item['checksum'] as String;

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

        final firebaseUser = Firebase.apps.isNotEmpty ? FirebaseAuth.instance.currentUser : null;
        final allLocalProfiles = await db.query(AppConstants.tableProfiles);
        final localProfileIds = allLocalProfiles.map((p) => p['id'] as String).toSet();
        final ownerResults = allLocalProfiles.where((p) => p['is_owner'] == 1).toList();
        final ownerProfileId = ownerResults.isNotEmpty ? ownerResults.first['id'] as String : null;

        await db.transaction((txn) async {
          // Find matching local non-owner parent profile by senderAppId or senderUid
          final matchingParentProfiles = await txn.query(
            AppConstants.tableProfiles,
            where: '(app_code = ? OR id = ?) AND is_owner = 0',
            whereArgs: [senderAppId ?? '', senderUid ?? ''],
          );

          final String? localParentProfileId;
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
            // On Caretaker device (where local non-owner parent profile exists), map all incoming parent records to the local parent profile ID
            if (localParentProfileId != null && localParentProfileId.isNotEmpty) {
              return localParentProfileId;
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

          // 1. Ingest Profiles first (if payload includes profiles)
          if (payload.containsKey('profiles')) {
            final list = payload['profiles'] as List;
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
                  map['profile_name'] = map['profile_name'] ?? map['name'] ?? 'Parent Profile';
                }
              } else {
                map['profile_name'] = map['profile_name'] ?? map['name'] ?? 'Synced Profile';
              }

              map.remove('name');

              await txn.insert(
                AppConstants.tableProfiles,
                map,
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
            }
          }

          // 2. Ingest Medicines
          if (payload.containsKey('medicines')) {
            final list = payload['medicines'] as List;
            for (final medMap in list) {
              final map = Map<String, dynamic>.from(medMap as Map);
              final rowProfileId = map['profile_id'] as String?;
              map['profile_id'] = await resolveAndEnsureProfileId(rowProfileId);
              map['is_dirty'] = 0;
              await txn.insert(
                AppConstants.tableMedicines,
                map,
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
            }
          }

          // 3. Ingest Schedules
          if (payload.containsKey('schedules')) {
            final list = payload['schedules'] as List;
            for (final schedMap in list) {
              final map = Map<String, dynamic>.from(schedMap as Map);
              final rowProfileId = map['profile_id'] as String?;
              map['profile_id'] = await resolveAndEnsureProfileId(rowProfileId);
              map['is_dirty'] = 0;
              await txn.insert(
                AppConstants.tableSchedules,
                map,
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
            }
          }

          // 4. Ingest Medicine Logs
          if (payload.containsKey('logs')) {
            final list = payload['logs'] as List;
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

        // Ingestion success: Update status
        await db.update(
          AppConstants.tableSyncQueue,
          {
            'status': 'done',
            'failure_reason': null,
          },
          where: 'sync_id = ?',
          whereArgs: [syncId],
        );

        // Send confirmation ack to sender's inbox
        await _sendSyncAck(syncId, senderUid ?? '', 'success');

      } catch (e) {
        debugPrint('Sync ingestion failed for syncId=$syncId: $e');
        await db.update(
          AppConstants.tableSyncQueue,
          {
            'status': 'failed',
            'failure_reason': e.toString(),
          },
          where: 'sync_id = ?',
          whereArgs: [syncId],
        );

        await _sendSyncAck(syncId, senderUid ?? '', 'failed', reason: e.toString());
      }
    }
  }

  static Future<void> _sendSyncAck(String syncId, String senderUid, String status, {String? reason}) async {
    if (Firebase.apps.isEmpty || FirebaseAuth.instance.currentUser == null) {
      debugPrint('Firebase not initialized or user not authenticated, skipping remote sync ack for syncId=$syncId');
      return;
    }
    if (senderUid.isEmpty) {
      debugPrint('Cannot send sync ack: senderUid is empty for syncId=$syncId');
      return;
    }
    try {
      final db = await DbHelper.instance.database;
      final ownerResults = await db.query(
        AppConstants.tableProfiles,
        where: 'is_owner = ?',
        whereArgs: [1],
        limit: 1,
      );
      final myAppCode = ownerResults.isNotEmpty ? ownerResults.first['app_code'] as String? ?? '' : '';

      final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
      // Write ack to sender's inbox (bidirectional inbox model)
      await FirebaseDatabase.instance.ref('sync_payloads/$senderUid/${syncId}_ack').set({
        'event_type': 'sync_ack',
        'status': status,
        'original_sync_id': syncId,
        'sender_uid': myUid,
        'sender_app_id': myAppCode,
        'timestamp': ServerValue.timestamp,
        if (reason != null) 'failure_reason': reason,
      });
    } catch (e) {
      debugPrint('Failed to send sync ack to sender inbox: $e');
    }
  }
}
