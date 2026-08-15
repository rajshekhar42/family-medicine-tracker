import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

/// Abstract interface for all Firebase RTDB operations performed during
/// onboarding profile management (profile name updates, connection deletions).
///
/// Allows [OnboardingRepositoryImpl] to remain free of Firebase imports,
/// making the repository fully unit-testable without a live Firebase instance.
abstract class OnboardingRemoteDataSource {
  /// Updates the owner's profile name in the RTDB profiles node.
  Future<void> updateOwnerProfileName({
    required String ownerAppCode,
    required String newName,
  });

  /// Updates a connected parent profile's display name in the RTDB connections
  /// and users index nodes.
  Future<void> updateConnectedParentName({
    required String ownerAppCode,
    required String parentAppCode,
    required String newName,
    required String caretakerUid,
  });

  /// Removes a parent connection from the RTDB connections node and the
  /// caretaker's connected_parents index.
  Future<void> deleteParentConnection({
    required String ownerAppCode,
    required String parentAppCode,
    required String caretakerUid,
  });
}

/// Firebase Realtime Database implementation of [OnboardingRemoteDataSource].
class OnboardingRemoteDataSourceImpl implements OnboardingRemoteDataSource {
  final FirebaseDatabase _db;
  final FirebaseAuth _auth;

  OnboardingRemoteDataSourceImpl({
    FirebaseDatabase? db,
    FirebaseAuth? auth,
  })  : _db = db ?? FirebaseDatabase.instance,
        _auth = auth ?? FirebaseAuth.instance;

  @override
  Future<void> updateOwnerProfileName({
    required String ownerAppCode,
    required String newName,
  }) async {
    await _db.ref('profiles/$ownerAppCode/profile_name').set(newName);
  }

  @override
  Future<void> updateConnectedParentName({
    required String ownerAppCode,
    required String parentAppCode,
    required String newName,
    required String caretakerUid,
  }) async {
    await _db
        .ref('profiles/$ownerAppCode/connections/$parentAppCode/display_name')
        .set(newName);
    await _db
        .ref('users/$caretakerUid/connected_parents/$parentAppCode/display_name')
        .set(newName);
  }

  @override
  Future<void> deleteParentConnection({
    required String ownerAppCode,
    required String parentAppCode,
    required String caretakerUid,
  }) async {
    await _db
        .ref('profiles/$parentAppCode/connections/$ownerAppCode')
        .remove();
    await _db
        .ref('users/$caretakerUid/connected_parents/$parentAppCode')
        .remove();
  }
}

/// No-op in-memory implementation for web and unit-test environments
/// where Firebase RTDB is not available.
class OnboardingRemoteDataSourceInMemory implements OnboardingRemoteDataSource {
  @override
  Future<void> updateOwnerProfileName({
    required String ownerAppCode,
    required String newName,
  }) async {
    // No-op in web/test
  }

  @override
  Future<void> updateConnectedParentName({
    required String ownerAppCode,
    required String parentAppCode,
    required String newName,
    required String caretakerUid,
  }) async {
    // No-op in web/test
  }

  @override
  Future<void> deleteParentConnection({
    required String ownerAppCode,
    required String parentAppCode,
    required String caretakerUid,
  }) async {
    // No-op in web/test
  }
}
