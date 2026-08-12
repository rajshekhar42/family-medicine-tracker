# Sync Logic Invocations

This document lists all sync logic invocations, entry points, listeners, and background processing handlers across the codebase.

---

## 1. Automatic / Lifecycle Sync Triggers

### [app.dart](file:///Users/rajshekhar/code/projects/MedicineTrackerAppV2/lib/app.dart)
- **Lifecycle state changes**: `didChangeAppLifecycleState` (lines 133-138) triggers `_triggerStartupSync()` on app resume/startup.
- **`_triggerStartupSync`** (lines 140-169):
  - Validates authentication state and active profile.
  - Checks if the time since the last sync exceeds the debounce period (`AppConstants.syncDebounceMinutes`).
  - **Owner/Parent Sync Trigger** (line 161): Calls `ref.read(syncStateProvider.notifier).sync()` to push local modifications.
  - **Caretaker Sync Trigger** (line 164): Calls `ref.read(syncStateProvider.notifier).requestPull()` to fetch updates from the parent.
- **Listener Initialization** (line 174): In the `build()` method, `ref.watch(rtdbSyncListenerProvider)` is watched to register the real-time RTDB listener/polling channel at app startup.

---

## 2. Authentication / Linking Triggers

### [auth_provider.dart](file:///Users/rajshekhar/code/projects/MedicineTrackerAppV2/lib/features/sync/presentation/providers/auth_provider.dart)
- **Caretaker Account Link Pull** (line 456): Once a caretaker links their device with a parent's `app_code` and restores the parent profiles locally, a pull sync is triggered:
  ```dart
  Future.microtask(() async {
    await ref!.read(syncStateProvider.notifier).requestPull();
  });
  ```

---

## 3. Manual / UI Sync Triggers

### [profile_drawer.dart](file:///Users/rajshekhar/code/projects/MedicineTrackerAppV2/lib/features/home/presentation/widgets/profile_drawer.dart)
- **Profile Card Tap Switching** (lines 461-469): Switching the active profile triggers a sync context switch:
  - If the profile is the owner: `ref.read(syncStateProvider.notifier).sync()` (pushes changes).
  - If the profile is a caretaker: `ref.read(syncStateProvider.notifier).requestPull()` (pulls changes).
- **"Sync Now" Button** (lines 630-639): Manual synchronization trigger:
  - If the active profile is the owner: `ref.read(syncStateProvider.notifier).sync()`.
  - If the active profile is a caretaker: `ref.read(syncStateProvider.notifier).requestPull()`.
- **Caretaker Validation** (lines 107-108): Tapping to link/add a new caretaker checks the app code against Firebase RTDB:
  - Calls `ref.read(syncRemoteDataSourceProvider).lookupProfileByAppCode(code)`.
- **Pending Connections Accept/Reject** (lines 757-762, 771-775):
  - Calls `ref.read(syncRemoteDataSourceProvider).acceptConnection(...)`.
  - Calls `ref.read(syncRemoteDataSourceProvider).rejectConnection(...)`.

### [home_screen.dart](file:///Users/rajshekhar/code/projects/MedicineTrackerAppV2/lib/features/home/presentation/screens/home_screen.dart)
- **Connection Approval Banner** (lines 161-165, 183-188): Allows parents to approve or reject caretakers from the home screen:
  - Calls `ref.read(syncRemoteDataSourceProvider).rejectConnection(...)`.
  - Calls `ref.read(syncRemoteDataSourceProvider).acceptConnection(...)`.

---

## 4. Business Logic Use Case Sync Triggers

### [caretaker_add_medication.dart](file:///Users/rajshekhar/code/projects/MedicineTrackerAppV2/lib/features/caretaker_medication/domain/usecases/caretaker_add_medication.dart)
- **Add Medication Sync Trigger** (line 32): When a caretaker successfully adds a medication locally (with `is_dirty = 1`), they immediately push the update to the parent's device:
  ```dart
  await syncRepository.syncAll(medicine.profileId);
  ```

### [caretaker_update_medication.dart](file:///Users/rajshekhar/code/projects/MedicineTrackerAppV2/lib/features/caretaker_medication/domain/usecases/caretaker_update_medication.dart)
- **Update Medication Sync Trigger** (line 32): When a caretaker successfully updates a medication locally (with `is_dirty = 1`), they immediately push the update to the parent's device:
  ```dart
  await syncRepository.syncAll(medicine.profileId);
  ```

---

## 5. Background Handlers, Receivers & Listeners

### [fcm_background_handler.dart](file:///Users/rajshekhar/code/projects/MedicineTrackerAppV2/lib/features/sync/data/datasources/fcm_background_handler.dart)
- **FCM Entry Point** (`firebaseMessagingBackgroundHandler`, line 15): Route background FCM payloads based on message `type`:
  - `data_sync`: Calls `handleSingleMessage` (inserts directly into SQLite `sync_queue` table and triggers queue ingestion).
  - `data_sync_chunk`: Calls `handleChunkMessage` (stores chunks in SQLite `chunk_buffer` table; when complete, joins them, writes to `sync_queue` table, and triggers queue ingestion).
  - `request_sync`: Calls `handleRequestSync` (triggered by caretakers; gathers modified SQLite tables and uploads a push sync payload to RTDB, then writes success/failure to `sync_acks/$syncId`).
- **Queue Processor** (`SyncIngestor.processQueue`, line 242): Ingests incoming sync updates (medicines, schedules, logs) inside database transactions, updates queue statuses to `done` or `failed`, and sends acknowledgment.

### [rtdb_sync_listener.dart](file:///Users/rajshekhar/code/projects/MedicineTrackerAppV2/lib/features/sync/presentation/providers/rtdb_sync_listener.dart)
- **RTDB Live Payload Listener** (lines 97-106): Listens to the `sync_payloads/$uid` RTDB path. Upon receiving a payload, it:
  - Calls `processIncomingRtdbSyncPayload(data)`.
  - Invalidates providers (`homeDosesProvider`, `medicinesListProvider`, `adherenceReportsProvider`, `settingsStateProvider`) to refresh the UI.
  - Reschedules medication reminders.
  - Deletes the processed payload from RTDB.
- **RTDB Live Pull Request Listener** (lines 116-152): Listens to `profiles/$appCode/pull_requests`. When a parent device receives a pull request signaller, it:
  - Calls `handleRequestSync(...)` to build and upload the payload.
  - Deletes the pull request signaller node.
- **Failsafe Poll Timer** (line 156-166): Runs a periodic timer (every 3 seconds) that calls `refDb.get()` and handles any missed payloads to ensure robust sync processing.
- **Database Transaction Processor** (`processIncomingRtdbSyncPayload`, line 176): Decompresses and verifies the payload checksum, resolves the profile ID mapping, runs a SQLite transaction to upsert data, and writes the status to `sync_acks/$syncId`.

---

## 6. Automated Testing Sync Triggers

### [test_sync_only.py](file:///Users/rajshekhar/code/projects/MedicineTrackerAppV2/AutomatedTest/sync_test/test_sync_only.py)
- **Manual Parent Push Trigger** (lines 398-406): Simulates tapping the "Sync Now" button in the parent drawer using ADB coordinates.
- **Manual Caretaker Pull Trigger** (lines 410-421): Simulates tapping the "Sync Now" button in the caretaker drawer using ADB coordinates.
- **Auto Push Sync Verifications** (lines 467-468, 498-500): Introduces sleeps (`time.sleep(15)`) to wait for automatic sync pushes after adding medications.
