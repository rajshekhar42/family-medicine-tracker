import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'compression_helper.dart';
import '../../../../core/utils/db_helper.dart';
import '../../../../core/constants/app_constants.dart';

abstract class SyncRemoteDataSource {
  Future<void> registerAppCode({
    required String uid,
    required String appCode,
    required String profileName,
    String? fcmToken,
  });

  Future<void> updatePresence(String appCode, String presence);

  Future<Map<String, dynamic>?> lookupProfileByAppCode(String appCode);

  Future<void> requestConnection({
    required String parentAppCode,
    required String parentName,
    required String caretakerAppCode,
    required String caretakerUid,
    required String caretakerDisplayName,
  });

  Future<void> acceptConnection({
    required String parentAppCode,
    required String caretakerAppCode,
    required String caretakerUid,
    required String parentName,
  });

  Future<void> rejectConnection({
    required String parentAppCode,
    required String caretakerAppCode,
    required String caretakerUid,
  });

  Stream<DatabaseEvent> getPendingConnectionsStream(String appCode);

  Stream<DatabaseEvent> getActiveConnectionsStream(String appCode);

  Stream<DatabaseEvent> getCaretakerConnectionsStream(String caretakerUid);

  Future<List<Map<String, dynamic>>> getCaretakerConnectedParents(String caretakerUid);

  Future<bool> hasUnconsumedPayload({
    required String recipientUid,
    required String senderUid,
  });

  Future<void> uploadSyncPayload({
    required String recipientUid,
    required String senderUid,
    required String senderAppCode,
    required String syncId,
    required String payloadJson,
    String? caretakerFcmToken,
    String? recipientAppCode,
  });

  Future<void> writeAckToSenderInbox({
    required String senderUid,
    required String syncId,
    required String status,
    String? failureReason,
  });
}

class SyncRemoteDataSourceImpl implements SyncRemoteDataSource {
  final FirebaseDatabase _db = FirebaseDatabase.instance;

  SyncRemoteDataSourceImpl() {
    // Disable offline persistence for Realtime Database
    _db.setPersistenceEnabled(false);
  }

  @override
  Future<void> registerAppCode({
    required String uid,
    required String appCode,
    required String profileName,
    String? fcmToken,
  }) async {
    final ref = _db.ref('profiles/$appCode');
    await ref.set({
      'uid': uid,
      'profile_name': profileName,
      'presence': 'online',
    });
  }

  @override
  Future<void> updatePresence(String appCode, String presence) async {
    final ref = _db.ref('profiles/$appCode/presence');
    await ref.set(presence);
    if (presence == 'offline') {
      await ref.onDisconnect().set('offline');
    }
  }

  @override
  Future<Map<String, dynamic>?> lookupProfileByAppCode(String appCode) async {
    final snapshot = await _db.ref('profiles/$appCode').get();
    if (snapshot.exists && snapshot.value is Map) {
      final data = Map<String, dynamic>.from(snapshot.value as Map);
      return data;
    }
    return null;
  }

  @override
  Future<void> requestConnection({
    required String parentAppCode,
    required String parentName,
    required String caretakerAppCode,
    required String caretakerUid,
    required String caretakerDisplayName,
  }) async {
    final parentProfile = await lookupProfileByAppCode(parentAppCode);
    final profileType = parentProfile?['profile_type'] as String? ?? 'Parent';
    if (profileType == 'Caretaker') {
      throw Exception('Target profile is a Caretaker and cannot be added as a Parent.');
    }

    // 1. Under Parent profiles -> connections
    await _db.ref('profiles/$parentAppCode/connections/$caretakerAppCode').set({
      'uid': caretakerUid,
      'display_name': caretakerDisplayName,
      'status': 'pending',
    });

    // 2. Under User index (for Caretakers)
    await _db.ref('users/$caretakerUid/connected_parents/$parentAppCode').set({
      'display_name': parentName,
      'status': 'pending',
    });
  }

  @override
  Future<void> acceptConnection({
    required String parentAppCode,
    required String caretakerAppCode,
    required String caretakerUid,
    required String parentName,
  }) async {
    // Approve parent connection and ensure caretaker UID is explicitly saved
    await _db.ref('profiles/$parentAppCode/connections/$caretakerAppCode').update({
      'status': 'active',
      'uid': caretakerUid,
    });
    
    // Approve caretaker connected parents index under users node
    await _db.ref('users/$caretakerUid/connected_parents/$parentAppCode').update({
      'status': 'active',
    });
  }

  @override
  Future<void> rejectConnection({
    required String parentAppCode,
    required String caretakerAppCode,
    required String caretakerUid,
  }) async {
    // Delete from parent connection node
    await _db.ref('profiles/$parentAppCode/connections/$caretakerAppCode').remove();
    
    // Delete from caretaker connected parents index under users node
    await _db.ref('users/$caretakerUid/connected_parents/$parentAppCode').remove();
  }

  @override
  Stream<DatabaseEvent> getPendingConnectionsStream(String appCode) {
    return _db.ref('profiles/$appCode/connections').onValue;
  }

  @override
  Stream<DatabaseEvent> getActiveConnectionsStream(String appCode) {
    return _db.ref('profiles/$appCode/connections').onValue;
  }

  @override
  Stream<DatabaseEvent> getCaretakerConnectionsStream(String caretakerUid) {
    return _db.ref('users/$caretakerUid/connected_parents').onValue;
  }

  @override
  Future<List<Map<String, dynamic>>> getCaretakerConnectedParents(String caretakerUid) async {
    final snapshot = await _db.ref('users/$caretakerUid/connected_parents').get();
    if (snapshot.exists && snapshot.value is Map) {
      final map = Map<String, dynamic>.from(snapshot.value as Map);
      final List<Map<String, dynamic>> results = [];
      map.forEach((key, value) {
        if (value is Map) {
          final entry = Map<String, dynamic>.from(value);
          entry['parent_app_code'] = key;
          results.add(entry);
        }
      });
      return results;
    }
    return [];
  }

  @override
  Future<bool> hasUnconsumedPayload({
    required String recipientUid,
    required String senderUid,
  }) async {
    if (recipientUid.isEmpty || senderUid.isEmpty) return false;
    try {
      final snapshot = await _db.ref('sync_payloads/$recipientUid/$senderUid').get();
      return snapshot.exists && snapshot.value != null;
    } catch (e) {
      DbHelper.log('SyncRemoteDataSource: error checking unconsumed payload: $e');
      return false;
    }
  }

  @override
  Future<void> uploadSyncPayload({
    required String recipientUid,
    required String senderUid,
    required String senderAppCode,
    required String syncId,
    required String payloadJson,
    String? caretakerFcmToken,
    String? recipientAppCode,
  }) async {
    if (recipientUid.isEmpty || senderUid.isEmpty) {
      DbHelper.log('SyncRemoteDataSource: Cannot upload payload - recipientUid or senderUid is empty.');
      return;
    }
    final String base64String;
    if (payloadJson == '{}') {
      base64String = '{}';
    } else {
      final compressedBytes = CompressionHelper.compress(payloadJson);
      base64String = CompressionHelper.toBase64(compressedBytes);
    }
    final checksum = CompressionHelper.computeChecksum(payloadJson);
    final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch;

    final ref = _db.ref('sync_payloads/$recipientUid/$senderUid');
    await ref.set({
      'sender_uid': senderUid,
      'sender_app_id': senderAppCode,
      if (recipientAppCode != null) 'recipient_app_code': recipientAppCode,
      'event_type': 'sync_update',
      'sync_id': syncId,
      'checksum': checksum,
      'timestamp': timestamp,
      'is_chunked': false,
      'compressed_data': base64String,
    });
  }

  @override
  Future<void> writeAckToSenderInbox({
    required String senderUid,
    required String syncId,
    required String status,
    String? failureReason,
  }) async {
    final senderAppCode = await _resolveSenderAppCode();
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    await _db.ref('sync_payloads/$senderUid/${syncId}_ack').set({
      'event_type': 'sync_ack',
      'status': status,
      'original_sync_id': syncId,
      'sender_uid': myUid,
      'sender_app_id': senderAppCode,
      'timestamp': ServerValue.timestamp,
      if (failureReason != null) 'failure_reason': failureReason,
    });
  }

  /// Resolves the current device's app code from the owner profile for ack sender_app_id.
  Future<String> _resolveSenderAppCode() async {
    try {
      final db = await DbHelper.instance.database;
      final ownerResults = await db.query(
        AppConstants.tableProfiles,
        where: 'is_owner = ?',
        whereArgs: [1],
        limit: 1,
      );
      if (ownerResults.isNotEmpty) {
        final code = ownerResults.first['app_code'] as String?;
        if (code != null && code.isNotEmpty) return code;
      }
    } catch (_) {}
    return FirebaseAuth.instance.currentUser?.uid ?? '';
  }
}

class SyncRemoteDataSourceInMemory implements SyncRemoteDataSource {
  static final Map<String, Map<String, dynamic>> _mockProfiles = {};
  static final Map<String, Map<String, dynamic>> _mockCaretakers = {};

  @override
  Future<void> registerAppCode({
    required String uid,
    required String appCode,
    required String profileName,
    String? fcmToken,
  }) async {
    _mockProfiles[appCode] = {
      'uid': uid,
      'profile_name': profileName,
      'presence': 'online',
      'connections': {},
    };
  }

  @override
  Future<void> updateFcmToken(String appCode, String token) async {
    if (_mockProfiles.containsKey(appCode)) {
      _mockProfiles[appCode]!['fcm_token'] = token;
    }
  }

  @override
  Future<void> updatePresence(String appCode, String presence) async {
    if (_mockProfiles.containsKey(appCode)) {
      _mockProfiles[appCode]!['presence'] = presence;
    }
  }

  @override
  Future<Map<String, dynamic>?> lookupProfileByAppCode(String appCode) async {
    return _mockProfiles[appCode];
  }

  @override
  Future<void> requestConnection({
    required String parentAppCode,
    required String parentName,
    required String caretakerAppCode,
    required String caretakerUid,
    required String caretakerDisplayName,
  }) async {
    if (_mockProfiles.containsKey(parentAppCode)) {
      final conns = _mockProfiles[parentAppCode]!['connections'] as Map;
      conns[caretakerAppCode] = {
        'uid': caretakerUid,
        'display_name': caretakerDisplayName,
        'status': 'pending',
      };
    }
    
    _mockCaretakers[caretakerUid] ??= {'connected_parents': {}};
    final parents = _mockCaretakers[caretakerUid]!['connected_parents'] as Map;
    parents[parentAppCode] = {
      'display_name': parentName,
      'status': 'pending',
    };
  }

  @override
  Future<void> acceptConnection({
    required String parentAppCode,
    required String caretakerAppCode,
    required String caretakerUid,
    required String parentName,
  }) async {
    if (_mockProfiles.containsKey(parentAppCode)) {
      final conns = _mockProfiles[parentAppCode]!['connections'] as Map;
      if (conns.containsKey(caretakerAppCode)) {
        conns[caretakerAppCode]['status'] = 'active';
      }
    }
    
    _mockCaretakers[caretakerUid] ??= {'connected_parents': {}};
    final parents = _mockCaretakers[caretakerUid]!['connected_parents'] as Map;
    parents[parentAppCode] = {
      'display_name': parentName,
      'status': 'active',
    };
  }

  @override
  Future<void> rejectConnection({
    required String parentAppCode,
    required String caretakerAppCode,
    required String caretakerUid,
  }) async {
    if (_mockProfiles.containsKey(parentAppCode)) {
      final conns = _mockProfiles[parentAppCode]!['connections'] as Map;
      conns.remove(caretakerAppCode);
    }
    if (_mockCaretakers.containsKey(caretakerUid)) {
      final parents = _mockCaretakers[caretakerUid]!['connected_parents'] as Map;
      parents.remove(parentAppCode);
    }
  }

  @override
  Stream<DatabaseEvent> getPendingConnectionsStream(String appCode) {
    // Return empty stream in-memory mock
    return const Stream.empty();
  }

  @override
  Stream<DatabaseEvent> getActiveConnectionsStream(String appCode) {
    return const Stream.empty();
  }

  @override
  Stream<DatabaseEvent> getCaretakerConnectionsStream(String caretakerUid) {
    return const Stream.empty();
  }

  @override
  Future<List<Map<String, dynamic>>> getCaretakerConnectedParents(String caretakerUid) async {
    if (_mockCaretakers.containsKey(caretakerUid)) {
      final map = _mockCaretakers[caretakerUid]!['connected_parents'] as Map;
      final List<Map<String, dynamic>> results = [];
      map.forEach((key, value) {
        if (value is Map) {
          final entry = Map<String, dynamic>.from(value);
          entry['parent_app_code'] = key;
          results.add(entry);
        }
      });
      return results;
    }
    return [];
  }

  final Map<String, Map<String, dynamic>> _mockSyncPayloads = {};

  @override
  Future<bool> hasUnconsumedPayload({
    required String recipientUid,
    required String senderUid,
  }) async {
    return _mockSyncPayloads.containsKey('$recipientUid/$senderUid');
  }

  @override
  Future<void> uploadSyncPayload({
    required String recipientUid,
    required String senderUid,
    required String senderAppCode,
    required String syncId,
    required String payloadJson,
    String? caretakerFcmToken,
    String? recipientAppCode,
  }) async {
    _mockSyncPayloads['$recipientUid/$senderUid'] = {
      'syncId': syncId,
      'payloadJson': payloadJson,
    };
    debugPrint('[Mock Sync] Uploaded sync payload slot: $recipientUid/$senderUid');
  }

  @override
  Future<void> writeAckToSenderInbox({
    required String senderUid,
    required String syncId,
    required String status,
    String? failureReason,
  }) async {
    String myUid = 'myUid';
    try {
      if (Firebase.apps.isNotEmpty) {
        myUid = FirebaseAuth.instance.currentUser?.uid ?? 'myUid';
      }
    } catch (_) {}
    _mockSyncPayloads['$senderUid/${myUid}_ack'] = {
      'syncId': syncId,
      'status': status,
    };
    debugPrint('[Mock Sync] Wrote ack to sender inbox slot: $senderUid/${myUid}_ack, status=$status');
  }
}
