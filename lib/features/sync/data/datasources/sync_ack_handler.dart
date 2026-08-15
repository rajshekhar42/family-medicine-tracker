import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/utils/db_helper.dart';
import '../../../../core/constants/app_constants.dart';
import 'compression_helper.dart';
import '../../../profiles/presentation/providers/active_profile_provider.dart';
import '../../../home/presentation/providers/home_provider.dart';
import '../../../medications/presentation/providers/medications_provider.dart';
import '../../../settings/presentation/providers/settings_provider.dart';

/// Responsible for processing incoming RTDB sync_ack payloads.
///
/// Extracted from [rtdb_sync_listener.dart] to satisfy SRP.
///
/// Responsibilities:
/// - Validate ack status
/// - Look up the original sync record in [tableSyncQueue]
/// - Clear itemized dirty flags for acknowledged rows
/// - Update [last_sync] timestamp in SQLite
/// - Invalidate Riverpod providers so UI reflects the fully-synced state
class SyncAckHandler {
  final Database db;

  SyncAckHandler({required this.db});

  /// Processes a sync_ack [data] payload.
  ///
  /// Returns `true` if the ack was recognized and successfully processed,
  /// `false` if it should be silently ignored (duplicate, non-success, etc).
  Future<bool> processSyncAck(Map<String, dynamic> data) async {
    final status = data['status'] as String?;
    final originalSyncId = data['original_sync_id'] as String?;

    if (status != 'success') {
      DbHelper.log(
        'SyncAckHandler: Non-success ack status=$status for originalSyncId=$originalSyncId. Reason: ${data['failure_reason']}',
      );
      return false;
    }

    if (originalSyncId == null || originalSyncId.isEmpty) {
      DbHelper.log('SyncAckHandler: originalSyncId is null/empty. Ignoring.');
      return false;
    }

    final queueResults = await db.query(
      AppConstants.tableSyncQueue,
      where: 'sync_id = ? AND status = ?',
      whereArgs: [originalSyncId, 'pending_ack'],
      limit: 1,
    );

    if (queueResults.isEmpty) {
      DbHelper.log(
        'SyncAckHandler: Duplicate/unrecognized ack for sync_id=$originalSyncId. Ignoring.',
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
        await _clearItemizedDirtyFlags(payload);
      } catch (e) {
        DbHelper.log('SyncAckHandler: Error parsing outgoing payload for $originalSyncId: $e');
      }
    }

    // Delete the acknowledged tracking record from tableSyncQueue
    await db.delete(
      AppConstants.tableSyncQueue,
      where: 'sync_id = ?',
      whereArgs: [originalSyncId],
    );

    // Update last_sync for the owner profile
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
  ///
  /// Clears dirty flags for the acknowledged batch and updates last_sync
  /// in SQLite and Riverpod.
  Future<void> handleIncomingAck(Map<String, dynamic> data, Ref ref) async {
    final success = await processSyncAck(data);
    if (!success) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final activeProfile = ref.read(activeProfileProvider);
    if (activeProfile != null) {
      final updatedProfile = activeProfile.copyWith(lastSync: now);
      ref.read(activeProfileProvider.notifier).setActiveProfile(updatedProfile);
      DbHelper.log(
        'SyncAckHandler: Updated last_sync and processed batch ACK for profile ${activeProfile.id}',
      );
    }

    // Invalidate providers so UI instantly reflects fully-synced state
    ref.invalidate(homeDosesProvider);
    ref.invalidate(medicinesListProvider);
    ref.invalidate(settingsStateProvider);
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Clears is_dirty = 0 strictly for row IDs included in [payload],
  /// only if the row has not been modified since the payload was built
  /// (last-write-wins guard via updated_at).
  Future<void> _clearItemizedDirtyFlags(Map<String, dynamic> payload) async {
    Future<void> clearTable(String tableName, String idCol, String keyName) async {
      if (payload.containsKey(keyName)) {
        final list = payload[keyName] as List?;
        if (list != null && list.isNotEmpty) {
          for (final item in list) {
            if (item is Map) {
              final id = item[idCol]?.toString();
              final itemUpdatedAt = item['updated_at'] as int?;
              if (id != null && id.isNotEmpty) {
                if (itemUpdatedAt != null) {
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
}
