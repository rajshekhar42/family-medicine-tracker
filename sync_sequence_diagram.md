# Sync Flow Initiation & Sequence Diagrams

This document details all initiation points for synchronization in the app and provides Mermaid sequence diagrams mapping out the complete flow, critical decision steps, and data exchange logic.

---

## 1. Summary of Sync Initiation Points

Sync in this application is initiated from **6 key entry points**:

| # | Initiation Point | Trigger / Condition | Code Location | Action Performed |
|---|---|---|---|---|
| **1** | **App Startup & Foreground Resume** | App launch (`addPostFrameCallback`) or app returning to foreground (`AppLifecycleState.resumed`). Requires authenticated user, not currently syncing, and last sync $\ge 5$ mins ago (or null). | [app.dart](file:///Users/rajshekhar/code/projects/MedicineTrackerAppV2/lib/app.dart#L112-L165) | Owner $\rightarrow$ `SyncNotifier.sync()` (Push)<br>Caretaker $\rightarrow$ `SyncNotifier.requestPull()` (Pull) |
| **2** | **Manual UI Refresh ("Sync Now")** | User manually taps the "Sync Now" button in the Profile Drawer. | [profile_drawer.dart](file:///Users/rajshekhar/code/projects/MedicineTrackerAppV2/lib/features/home/presentation/widgets/profile_drawer.dart#L773-L775) | Owner $\rightarrow$ `SyncNotifier.sync()` (Push)<br>Caretaker $\rightarrow$ `SyncNotifier.requestManualPull()` (with 60s cooldown check) |
| **3** | **Caretaker Medication Mutations** | Caretaker adds or updates a medication record for a linked parent profile. | [caretaker_add_medication.dart](file:///Users/rajshekhar/code/projects/MedicineTrackerAppV2/lib/features/caretaker_medication/domain/usecases/caretaker_add_medication.dart#L32)<br>[caretaker_update_medication.dart](file:///Users/rajshekhar/code/projects/MedicineTrackerAppV2/lib/features/caretaker_medication/domain/usecases/caretaker_update_medication.dart#L32) | Calls `syncRepository.syncAll(medicine.profileId)` immediately after SQLite write to push local modifications to Parent |
| **4** | **Auth Startup & Account Linking** | Google Sign-in or app boot links caretaker account with parent app code, restoring connected parent profiles to local SQLite. | [auth_provider.dart](file:///Users/rajshekhar/code/projects/MedicineTrackerAppV2/lib/features/sync/presentation/providers/auth_provider.dart#L444-L446) | Switches active profile to restored parent profile and executes `Future.microtask(() => syncNotifier.requestPull())` |
| **5** | **RTDB Incoming Pull Signal** | Persistent Realtime Database listener detects incoming pull request node (`event_type: 'request_sync'`) in Parent's inbox `/sync_payloads/$ownerUid`. | [rtdb_sync_listener.dart](file:///Users/rajshekhar/code/projects/MedicineTrackerAppV2/lib/features/sync/presentation/providers/rtdb_sync_listener.dart#L101-L115) | Parent app automatically invokes `syncRepository.syncAll(ownerProfile.id, caretakerLastSyncTime)` to prepare and upload response payload |
| **6** | **Pre-Sync Pipeline Inbox Interception** | Prior to executing a standard push sync, Parent checks `/sync_payloads/$ownerUid` for any unconsumed caretaker pull requests. | [sync_repository_impl.dart](file:///Users/rajshekhar/code/projects/MedicineTrackerAppV2/lib/features/sync/data/repositories/sync_repository_impl.dart#L58-L81) | Consumes pending pull request, extracts `caretakerLastSyncTime`, removes node from RTDB, and applies `caretakerLastSyncTime` to diff query |

---

## 2. Diagram 1: High-Level Sync Initiation & Routing Diagram

This diagram shows all 6 initiation points and how they route into `SyncNotifier` and `SyncRepository`.

```mermaid
sequenceDiagram
    autonumber
    actor User as User / App Lifecycle
    participant App as App Lifecycle / UI<br/>(app.dart / profile_drawer.dart)
    participant Auth as Auth / Onboarding<br/>(auth_provider.dart)
    participant CaretakerUC as Caretaker Use Cases<br/>(Add/Update Medication)
    participant RTDBListener as RTDB Signal Listener<br/>(rtdb_sync_listener.dart)
    participant Notifier as SyncNotifier<br/>(sync_provider.dart)
    participant Repo as SyncRepositoryImpl<br/>(sync_repository_impl.dart)

    rect rgb(235, 245, 255)
    note over User, Notifier: Initiation Point 1: App Launch / Foreground Resume
    User->>App: Launch / Foreground (AppLifecycleState.resumed)
    App->>App: Check Debounce (5 mins) & Auth State
    alt Is Owner Profile
        App->>Notifier: sync()
    else Is Caretaker Profile
        App->>Notifier: requestPull()
    end
    end

    rect rgb(240, 255, 240)
    note over User, Notifier: Initiation Point 2: Manual Profile Drawer Action
    User->>App: Tap "Sync Now" Button
    alt Is Owner Profile
        App->>Notifier: sync()
    else Is Caretaker Profile
        App->>Notifier: requestManualPull()
        Notifier->>Notifier: Check 60s Cooldown
        alt Cooldown Expired
            Notifier->>Notifier: requestPull()
        else Cooldown Active
            Notifier-->>App: Return remaining seconds (throttled)
        end
    end
    end

    rect rgb(255, 245, 235)
    note over CaretakerUC, Repo: Initiation Point 3: Caretaker Mutation
    User->>CaretakerUC: Add / Edit Medication
    CaretakerUC->>Repo: Write SQLite (is_dirty = 1)
    CaretakerUC->>Repo: syncAll(profileId)
    end

    rect rgb(250, 240, 255)
    note over Auth, Notifier: Initiation Point 4: Auth Account Linking
    Auth->>Auth: Restore Connected Parents from Cloud
    Auth->>Notifier: Future.microtask -> requestPull()
    end

    rect rgb(255, 250, 235)
    note over RTDBListener, Repo: Initiation Point 5: Incoming RTDB Pull Request Signal
    RTDBListener->>RTDBListener: RTDB onValue detects 'request_sync' in /sync_payloads/$ownerUid
    RTDBListener->>Repo: syncAll(ownerProfile.id, caretakerLastSyncTime)
    end

    rect rgb(240, 240, 240)
    note over Repo: Initiation Point 6: Pre-Sync Pipeline Inbox Interception
    Repo->>Repo: Check /sync_payloads/$ownerUid for pending pull request
    alt Pending Pull Request Found
        Repo->>Repo: Extract caretakerLastSyncTime & delete RTDB node
    end
    end
```

---

## 3. Diagram 2: Detailed Push Sync & Ingestion Flow (Owner / Mutation Push)

This diagram details the step-by-step execution of `syncAll()`, including dirty-flag filtering, payload generation, Firebase RTDB transport, target ingestion, provider invalidation, and acknowledgment.

```mermaid
sequenceDiagram
    autonumber
    participant AppUI as UI Layer / Providers
    participant Notifier as SyncNotifier
    participant Repo as SyncRepositoryImpl
    participant SQLite as SQLite Database (Local)
    participant RemoteDS as SyncRemoteDataSourceImpl
    participant RTDB as Firebase Realtime DB<br/>(/sync_payloads/$targetUid)
    participant ReceiverRTDB as Receiver RTDB Listener<br/>(rtdb_sync_listener.dart)
    participant ReceiverSQLite as Receiver SQLite DB
    participant ReceiverUI as Receiver UI / Reminders

    AppUI->>Notifier: sync()
    Notifier->>Notifier: Set isSyncing = true
    Notifier->>Repo: syncAll(activeProfileId)

    %% Pre-Sync check
    Repo->>RTDB: Check /sync_payloads/$ownerUid for pending pull
    opt Pending Pull Request Node Exists
        RTDB-->>Repo: Return pending pull (caretakerLastSyncTime)
        Repo->>RTDB: Delete pending pull request node
    end

    %% Query dirty / updated records
    alt Is Owner Push
        Repo->>SQLite: SELECT * FROM profiles, medicines, schedules, logs, settings WHERE is_dirty = 1 (or updated_at > queryTime)
    else Is Caretaker Push
        Repo->>SQLite: SELECT * FROM tables WHERE profile_id = parentId AND is_dirty = 1
    end
    SQLite-->>Repo: Return modified records

    alt No modified records to push
        Repo-->>Notifier: Early Return (Nothing to sync)
        Notifier->>Notifier: Set isSyncing = false
    else Records Exist
        Repo->>Repo: Construct Payload JSON (profiles, medicines, schedules, logs, settings)
        Repo->>RemoteDS: Get active connections for recipient UIDs

        loop For each active connected recipient
            Repo->>RemoteDS: hasUnconsumedPayload(recipientUid, senderUid)
            alt Unconsumed payload already in recipient inbox
                Repo->>Repo: Skip routine push to avoid overwrite
            else Inbox clear
                Repo->>SQLite: Record outgoing sync in tableSyncQueue (status: pending_ack)
                Repo->>RemoteDS: uploadSyncPayload(recipientUid, senderUid, syncId, payloadJson)
                RemoteDS->>RTDB: Write node under /sync_payloads/$recipientUid/$senderUid
            end
        end

        Repo-->>Notifier: Push Upload Complete
        Notifier->>AppUI: Invalidate UI providers (homeDosesProvider, medicinesListProvider, etc.)
        Notifier->>Notifier: Set isSyncing = false, update lastSyncedAt
    end

    %% Receiver Processing Step
    critical Critical Step: Receiver Ingestion & Ack Flow
        RTDB->>ReceiverRTDB: onValue trigger on /sync_payloads/$recipientUid
        ReceiverRTDB->>ReceiverRTDB: Decompress payload & verify checksum

        ReceiverRTDB->>ReceiverSQLite: BEGIN TRANSACTION
        ReceiverRTDB->>ReceiverSQLite: Upsert profiles, medicines, schedules, logs, settings (set is_dirty = 0)
        ReceiverSQLite-->>ReceiverRTDB: Transaction Commit Success

        ReceiverRTDB->>ReceiverUI: Invalidate Riverpod Providers & Reschedule Reminders
        ReceiverRTDB->>RTDB: REMOVE payload node from /sync_payloads/$recipientUid
        ReceiverRTDB->>RTDB: WRITE sync_ack to /sync_payloads/$senderUid (event_type: 'sync_ack')
    end

    %% Ack back to sender
    RTDB->>RTDBListener: onValue trigger on /sync_payloads/$senderUid receiving sync_ack
    RTDBListener->>SQLite: Update local profile last_sync timestamp & clear queue status
    RTDBListener->>RTDB: Delete sync_ack node
```

---

## 4. Diagram 3: Caretaker Pull Request & Response Flow

This diagram details the exact asynchronous signal-based pull process initiated by a Caretaker device to request data from the Owner device.

```mermaid
sequenceDiagram
    autonumber
    actor Caretaker as Caretaker User / App
    participant CaretakerNotifier as Caretaker SyncNotifier
    participant CaretakerRepo as Caretaker SyncRepositoryImpl
    participant CaretakerSQLite as Caretaker SQLite DB
    participant RTDB as Firebase Realtime DB
    participant OwnerListener as Owner rtdbSyncListenerProvider
    participant OwnerRepo as Owner SyncRepositoryImpl
    participant OwnerSQLite as Owner SQLite DB
    participant CaretakerListener as Caretaker rtdbSyncListenerProvider

    Caretaker->>CaretakerNotifier: requestPull() / requestManualPull()
    CaretakerNotifier->>CaretakerNotifier: Set isSyncing = true
    CaretakerNotifier->>CaretakerRepo: 1. syncAll(activeProfileId) [Push Caretaker Local Dirty Modifications First]
    CaretakerRepo->>CaretakerSQLite: Query local dirty changes for parent profile
    opt Caretaker has dirty changes
        CaretakerRepo->>RTDB: Push dirty payload to /sync_payloads/$parentUid
    end

    CaretakerNotifier->>CaretakerRepo: 2. requestPullSync(caretakerUid, syncId, caretakerLastSyncTime)
    CaretakerRepo->>RTDB: WRITE pull request signal to /sync_payloads/$parentUid/$caretakerUid<br/>{event_type: 'request_sync', caretakerLastSyncTime: X}
    CaretakerRepo-->>CaretakerNotifier: Pull request sent (Fire-and-Forget)
    CaretakerNotifier->>CaretakerNotifier: Set isSyncing = false

    %% Owner receives signal
    rect rgb(235, 245, 255)
    note over OwnerListener, OwnerSQLite: Asynchronous Signal Processing on Parent Device
    RTDB->>OwnerListener: onValue fires on /sync_payloads/$parentUid
    OwnerListener->>OwnerListener: Detect event_type == 'request_sync'
    OwnerListener->>OwnerRepo: syncAll(ownerProfile.id, caretakerLastSyncTime = X)

    alt caretakerLastSyncTime == 0 (Full Restore)
        OwnerRepo->>OwnerSQLite: SELECT * FROM all tables
    else caretakerLastSyncTime > 0 (Incremental Diff)
        OwnerRepo->>OwnerSQLite: SELECT * FROM tables WHERE updated_at > caretakerLastSyncTime OR is_dirty = 1
    end
    OwnerSQLite-->>OwnerRepo: Return requested data records

    OwnerRepo->>RTDB: WRITE response payload to /sync_payloads/$caretakerUid/$ownerUid<br/>{event_type: 'sync_update', compressed_data: ...}
    OwnerListener->>RTDB: DELETE pull request node from /sync_payloads/$parentUid
    end

    %% Caretaker receives data
    rect rgb(240, 255, 240)
    note over CaretakerListener, CaretakerSQLite: Payload Ingestion on Caretaker Device
    RTDB->>CaretakerListener: onValue fires on /sync_payloads/$caretakerUid
    CaretakerListener->>CaretakerListener: Process payload: decompress & verify checksum
    CaretakerListener->>CaretakerSQLite: BEGIN TRANSACTION: Upsert records (is_dirty = 0)
    CaretakerSQLite-->>CaretakerListener: Transaction Commit Success

    CaretakerListener->>CaretakerSQLite: UPDATE profiles SET last_sync = timestamp WHERE id = parentId
    CaretakerListener->>Caretaker: Invalidate UI Providers & Reschedule Reminders
    CaretakerListener->>RTDB: DELETE response payload node from /sync_payloads/$caretakerUid
    CaretakerListener->>RTDB: WRITE sync_ack node to /sync_payloads/$parentUid
    end
```

---

## 5. Critical Execution Highlights & Fail-Safes

1. **SQLite Source of Truth & Offline-First Principle**:
   - UI never blocks on cloud network calls; screens always read directly from local SQLite.
   - All mutations set `is_dirty = 1` and update `updated_at` with UTC epoch milliseconds.

2. **Incremental Diff Querying vs Full Restore**:
   - Caretakers with `last_sync == 0` receive full snapshots of all profiles, medicines, schedules, logs, and settings.
   - Caretakers with existing `last_sync > 0` receive only records where `updated_at > caretakerLastSyncTime` or `is_dirty = 1`.

3. **Atomic Transactions & Ingestion Safeguards**:
   - All incoming sync updates are applied inside a single SQLite database transaction to guarantee consistency.
   - On ingestion, `is_dirty` is cleared (`0`) for updated records.

4. **RTDB Signal Node Cleanup**:
   - Every processed node (`request_sync`, `sync_update`, `sync_ack`) is immediately deleted from Realtime Database upon ingestion to prevent stale processing loops and keep storage clean.

5. **UI Provider & Reminder Rescheduling Synchronization**:
   - Upon successful sync ingestion, Riverpod providers (`homeDosesProvider`, `medicinesListProvider`, `adherenceReportsProvider`, `historySelectedDateDosesProvider`, `settingsStateProvider`) are invalidated.
   - `ReminderScheduler.rescheduleAll()` is invoked immediately to align device alarm notifications with the updated schedule.
