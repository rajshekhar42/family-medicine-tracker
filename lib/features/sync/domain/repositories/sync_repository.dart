/// Abstract interface for the sync engine.
///
/// Lives in the domain layer — no Firebase, SQLite, or platform imports allowed here.
/// Any use case or presentation provider that needs sync functionality
/// must depend on this interface, never on [SyncRepositoryImpl].
abstract class SyncRepository {
  /// Pushes all dirty local records for [activeProfileId] to the remote
  /// inbox of every connected device. When responding to a Caretaker pull
  /// request, [caretakerLastSyncTime] is set to the epoch-ms the Caretaker
  /// last received a full sync (0 means a full-restore push).
  Future<void> syncAll(String activeProfileId, {int? caretakerLastSyncTime});

  /// Sends a pull-sync request to the parent device's inbox.
  /// Currently a no-op (direct push model), preserved for interface stability.
  Future<void> requestPullSync(
    String caretakerUid,
    String syncId,
    int caretakerLastSyncTime,
  );

  /// Returns true if there are any un-synced (is_dirty = 1) rows
  /// for [activeProfileId], or globally if [activeProfileId] is null.
  Future<bool> hasDirtyRows(String? activeProfileId);

  /// Marks every syncable row for [profileId] as dirty so the next
  /// sync performs a full push (used after pairing acceptance).
  Future<void> markAllRowsDirty(String profileId);
}
