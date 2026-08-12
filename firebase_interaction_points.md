# FCM & Firebase Realtime Database Interaction Points

This document provides a comprehensive catalog of all points in the codebase where **Firebase Cloud Messaging (FCM)** and **Firebase Realtime Database (RTDB)** are invoked. This serves as a reference for refactoring these integration boundaries.

---

## Table of Contents
1. [FCM Push Messaging Invocation Points](#1-fcm-push-messaging-invocation-points)
   - [A. Outgoing Messages (Sending)](#a-outgoing-messages-sending)
   - [B. Incoming Messages (Receiving & Ingestion)](#b-incoming-messages-receiving--ingestion)
   - [C. Configuration & Client Metadata (Tokens)](#c-configuration--client-metadata-tokens)
2. [Firebase Realtime Database (RTDB) Invocation Points](#2-firebase-realtime-database-rtdb-invocation-points)
   - [A. RTDB Operations by Reference Path](#a-rtdb-operations-by-reference-path)
   - [B. RTDB Operations by Source File (Detailed)](#b-rtdb-operations-by-source-file-detailed)
3. [Critical Architectural Findings & Discrepancies](#3-critical-architectural-findings--discrepancies)

---

## 1. FCM Push Messaging Invocation Points

FCM is used primarily to notify devices to initiate a synchronization cycle (either pushing pending local changes or pulling changes from their peer).

### A. Outgoing Messages (Sending)
There is only one point in the system that performs the actual **sending** of FCM push notifications:
*   **Firebase Cloud Functions Trigger:**
    *   **File:** [functions/index.js:L11-L46](file:///Users/rajshekhar/code/projects/MedicineTrackerAppV2/functions/index.js#L11-L46) (`exports.syncData`)
    *   **Action:** Calls `admin.messaging().send(...)` using the target profile's FCM token.
    *   **Trigger Condition:** Client invokes the `syncData` Cloud Function Callable.

*   **Callable Functions Requests from the Flutter App:**
    *   **File:** [sync_repository_impl.dart:L212-L232](file:///Users/rajshekhar/code/projects/MedicineTrackerAppV2/lib/features/sync/data/repositories/sync_repository_impl.dart#L212-L232)
    *   **Action:** Calls `syncData` Cloud Function with `eventType: 'request_sync'` to notify a parent device to trigger a pull sync request.

### B. Incoming Messages (Receiving & Ingestion)
The app listens for incoming FCM messages in both foreground and background states:
*   **Background Handler Registration:**
    *   **File:** [main.dart:L78](file:///Users/rajshekhar/code/projects/MedicineTrackerAppV2/lib/main.dart#L78)
    *   **Action:** Registers `firebaseMessagingBackgroundHandler` as the top-level background FCM message listener.
*   **Foreground Handler Registration:**
    *   **File:** [main.dart:L81-L99](file:///Users/rajshekhar/code/projects/MedicineTrackerAppV2/lib/main.dart#L81-L99)
    *   **Action:** Listens to `FirebaseMessaging.onMessage` stream.
*   **Message Processing Logic:**
    *   **File:** [fcm_background_handler.dart:L15-L37](file:///Users/rajshekhar/code/projects/MedicineTrackerAppV2/lib/features/sync/data/datasources/fcm_background_handler.dart#L15-L37) (`firebaseMessagingBackgroundHandler`)
    *   **Action:** Routes incoming payloads by `type`:
        *   `data_sync`: Ingests single sync payload ([fcm_background_handler.dart:L39-L61](file:///Users/rajshekhar/code/projects/MedicineTrackerAppV2/lib/features/sync/data/datasources/fcm_background_handler.dart#L39-L61)).
        *   `data_sync_chunk`: Re-assembles chunked payload ([fcm_background_handler.dart:L63-L130](file:///Users/rajshekhar/code/projects/MedicineTrackerAppV2/lib/features/sync/data/datasources/fcm_background_handler.dart#L63-L130)).
        *   `request_sync`: Handles pull request by gathering local updates and uploading them back to RTDB ([fcm_background_handler.dart:L132-L237](file:///Users/rajshekhar/code/projects/MedicineTrackerAppV2/lib/features/sync/data/datasources/fcm_background_handler.dart#L132-L237)).

### C. Configuration & Client Metadata (Tokens)
*   **Retrieving Client FCM Token:**
    *   **File:** [auth_provider.dart:L338](file:///Users/rajshekhar/code/projects/MedicineTrackerAppV2/lib/features/sync/presentation/providers/auth_provider.dart#L338)
    *   **Action:** Calls `FirebaseMessaging.instance.getToken()` during initialization or auth change.
*   **Storing Token in RTDB:**
    *   **File:** [auth_provider.dart:L350](file:///Users/rajshekhar/code/projects/MedicineTrackerAppV2/lib/features/sync/presentation/providers/auth_provider.dart#L350) & [sync_remote_datasource.dart:L93](file:///Users/rajshekhar/code/projects/MedicineTrackerAppV2/lib/features/sync/data/datasources/sync_remote_datasource.dart#L93)
    *   **Action:** Saves/updates the FCM token inside the profile record: `/profiles/$appCode/fcm_token`.

---

## 2. Firebase Realtime Database (RTDB) Invocation Points

RTDB is utilized as a real-time signaling channel (handling connection requests, pull signallers, and sync acknowledgments) and as a transport mechanism for compressed sync payloads.

### A. RTDB Operations by Reference Path

| Path | Operations | Used For |
|---|---|---|
| `/profiles/$appCode` | `SET`, `UPDATE`, `GET` | Registering profiles, checking presence, storing metadata (FCM token, name). |
| `/profiles/$appCode/fcm_token` | `SET` | Updating client FCM tokens. |
| `/profiles/$appCode/presence` | `SET`, `onDisconnect().set()` | Updating and maintaining real-time online/offline presence. |
| `/profiles/$parentAppCode/connections/$caretakerAppCode` | `SET`, `UPDATE`, `REMOVE`, `LISTEN` | Establishing, accepting, rejecting, and monitoring connections between parents and caretakers. |
| `/profiles/$parentAppCode/pull_requests/$syncId` | `SET`, `LISTEN`, `REMOVE` | Real-time signaling from caretakers requesting parents to push updates. |
| `/users/$userId/app_code` | `GET`, `SET` | Mapping a user's Firebase Auth UID to their profile App Code. |
| `/users/$userId/connected_parents` | `GET`, `SET`, `UPDATE`, `REMOVE`, `LISTEN` | Index of connected parent app codes for a caretaker. |
| `/sync_payloads/$caretakerUid/$syncId` | `SET`, `GET`, `LISTEN`, `REMOVE` | Uploading, polling, listening to, and cleaning up compressed sync payloads. |
| `/sync_acks/$syncId` | `SET`, `GET`, `LISTEN`, `REMOVE` | Acknowledging completion status (success/failed) of sync transactions. |
| `/users/$caretakerUid/fcmToken` | `GET` (Cloud Functions) | Looking up caretaker FCM tokens during sync events. *(See Critical Findings below)* |

---

### B. RTDB Operations by Source File (Detailed)

#### 1. [functions/index.js](file:///Users/rajshekhar/code/projects/MedicineTrackerAppV2/functions/index.js) (Cloud Functions)
*   **`syncData` (lines 24-26):**
    *   **Operation:** `READ` (`.once("value")`)
    *   **Path:** `/users/${caretakerUid}/fcmToken`
    *   **Purpose:** Fetches caretaker's FCM token.
*   **`cleanupStaleSyncAcks` (lines 74-75, 92):**
    *   **Operation:** `READ` (`.once("value")`) & `DELETE` (via `.update(updates)` setting nodes to `null`)
    *   **Path:** `/sync_acks`
    *   **Purpose:** Cron job running weekly to clear acks older than 7 days.

#### 2. [sync_repository_impl.dart](file:///Users/rajshekhar/code/projects/MedicineTrackerAppV2/lib/features/sync/data/repositories/sync_repository_impl.dart)
*   **`requestPullSync` (lines 199-207):**
    *   **Operation:** `WRITE` (`.set()`)
    *   **Path:** `profiles/$parentAppCode/pull_requests/$syncId`
    *   **Purpose:** Parent signaling mechanism triggering automatic sync retrieval on the parent's device.

#### 3. [sync_remote_datasource.dart](file:///Users/rajshekhar/code/projects/MedicineTrackerAppV2/lib/features/sync/data/datasources/sync_remote_datasource.dart) (`SyncRemoteDataSourceImpl`)
*   **`registerAppCode` (lines 89-95):**
    *   **Operation:** `WRITE` (`.set()`)
    *   **Path:** `profiles/$appCode`
*   **`updateFcmToken` (lines 99-101):**
    *   **Operation:** `WRITE` (`.set()`)
    *   **Path:** `profiles/$appCode/fcm_token`
*   **`updatePresence` (lines 104-110):**
    *   **Operation:** `WRITE` (`.set()`), `LIFECYCLE` (`.onDisconnect().set()`)
    *   **Path:** `profiles/$appCode/presence`
*   **`lookupProfileByAppCode` (lines 113-120):**
    *   **Operation:** `READ` (`.get()`)
    *   **Path:** `profiles/$appCode`
*   **`requestConnection` (lines 131-141):**
    *   **Operation:** `WRITE` (`.set()`)
    *   **Paths:**
        *   `profiles/$parentAppCode/connections/$caretakerAppCode`
        *   `users/$caretakerUid/connected_parents/$parentAppCode`
*   **`acceptConnection` (lines 152-160):**
    *   **Operation:** `WRITE` (`.update()`)
    *   **Paths:**
        *   `profiles/$parentAppCode/connections/$caretakerAppCode`
        *   `users/$caretakerUid/connected_parents/$parentAppCode`
*   **`rejectConnection` (lines 170-173):**
    *   **Operation:** `DELETE` (`.remove()`)
    *   **Paths:**
        *   `profiles/$parentAppCode/connections/$caretakerAppCode`
        *   `users/$caretakerUid/connected_parents/$parentAppCode`
*   **`getPendingConnectionsStream` / `getActiveConnectionsStream` (lines 177-184):**
    *   **Operation:** `LISTEN` (`.onValue`)
    *   **Path:** `profiles/$appCode/connections`
*   **`getCaretakerConnectionsStream` (lines 187-189):**
    *   **Operation:** `LISTEN` (`.onValue`)
    *   **Path:** `users/$caretakerUid/connected_parents`
*   **`getCaretakerConnectedParents` (lines 192-193):**
    *   **Operation:** `READ` (`.get()`)
    *   **Path:** `users/$caretakerUid/connected_parents`
*   **`uploadSyncPayload` (lines 224-235):**
    *   **Operation:** `WRITE` (`.set()`)
    *   **Path:** `sync_payloads/$caretakerUid/$syncId`
*   **`sendAck` (lines 252-255):**
    *   **Operation:** `WRITE` (`.set()`)
    *   **Path:** `sync_acks/$syncId`
*   **`listenForAck` (lines 259-261):**
    *   **Operation:** `LISTEN` (`.onValue`)
    *   **Path:** `sync_acks/$syncId`
*   **`deleteAck` (lines 264-266):**
    *   **Operation:** `DELETE` (`.remove()`)
    *   **Path:** `sync_acks/$syncId`

#### 4. [rtdb_sync_listener.dart](file:///Users/rajshekhar/code/projects/MedicineTrackerAppV2/lib/features/sync/presentation/providers/rtdb_sync_listener.dart)
*   **`rtdbSyncListenerProvider` initialization (lines 35-44):**
    *   **Operation:** `SETUP` (`setPersistenceEnabled(false)`, `goOnline()`, `keepSynced(true)`)
    *   **Path:** `sync_payloads/$uid`
*   **`handleSnapshot` processing (lines 91, 97-106):**
    *   **Operation:** `LISTEN` (`.onValue.listen()`) & `DELETE` (`.remove()`)
    *   **Path:** `sync_payloads/$uid/$syncId`
*   **Pull Requests listener (lines 111-152):**
    *   **Operation:** `LISTEN` (`.onValue.listen()`), `SETUP` (`keepSynced(true)`), & `DELETE` (`.remove()`)
    *   **Path:** `profiles/$appCode/pull_requests`
*   **Failsafe poll timer (lines 156-166):**
    *   **Operation:** `READ` (`.get()`)
    *   **Path:** `sync_payloads/$uid`
*   **`processIncomingRtdbSyncPayload` ack writes (lines 298, 305):**
    *   **Operation:** `WRITE` (`.set()`)
    *   **Path:** `sync_acks/$syncId`

#### 5. [auth_provider.dart](file:///Users/rajshekhar/code/projects/MedicineTrackerAppV2/lib/features/sync/presentation/providers/auth_provider.dart)
*   **Caretaker check & generation (lines 307-331):**
    *   **Operation:** `READ` (`.get()`)
    *   **Paths:**
        *   `caretakers/${user.uid}/app_code`
        *   `profiles/$appCode`
*   **Profile sync registration (lines 347-355):**
    *   **Operation:** `WRITE` (`.update()`, `.set()`)
    *   **Paths:**
        *   `profiles/$appCode`
        *   `caretakers/${user.uid}/app_code`
*   **Display connections (lines 395-406):**
    *   **Operation:** `READ` (`.get()`)
    *   **Paths:**
        *   `caretakers/${user.uid}/connected_parents`
        *   `profiles/$parentAppCode`

#### 6. [fcm_background_handler.dart](file:///Users/rajshekhar/code/projects/MedicineTrackerAppV2/lib/features/sync/data/datasources/fcm_background_handler.dart)
*   **`handleRequestSync` response (lines 199, 215, 227):**
    *   **Operation:** `WRITE` (`.set()`)
    *   **Paths:**
        *   `sync_payloads/$caretakerUid/$syncId`
        *   `sync_acks/$syncId`
*   **`_sendSyncAck` callback (line 414):**
    *   **Operation:** `WRITE` (`.set()`)
    *   **Path:** `sync_acks/$syncId`

#### 7. [sync_provider.dart](file:///Users/rajshekhar/code/projects/MedicineTrackerAppV2/lib/features/sync/presentation/providers/sync_provider.dart)
*   **`requestPull` stream (lines 196-211):**
    *   **Operation:** `LISTEN` (`.onValue.listen()`)
    *   **Path:** `sync_acks/$syncId`

#### 8. [onboarding_repository_impl.dart](file:///Users/rajshekhar/code/projects/MedicineTrackerAppV2/lib/features/onboarding/data/repositories/onboarding_repository_impl.dart)
*   **`updateProfileName` (lines 155-164):**
    *   **Operation:** `WRITE` (`.set()`)
    *   **Paths:**
        *   `profiles/$ownerAppCode/profile_name`
        *   `profiles/$ownerAppCode/connections/$parentAppCode/display_name`
        *   `caretakers/${user.uid}/connected_parents/$parentAppCode/display_name`

---

## 3. Critical Architectural Findings & Discrepancies

During this cataloging, a critical architectural mismatch was identified that should be prioritized during the refactoring:

> [!WARNING]
> **FCM Token Path Mismatch between Cloud Functions and Client App**
>
> 1. **Cloud Functions Lookup:** The `syncData` cloud function ([functions/index.js:L24-L26](file:///Users/rajshekhar/code/projects/MedicineTrackerAppV2/functions/index.js#L24-L26)) reads the caretaker's FCM token from:
>    `/users/${caretakerUid}/fcmToken`
>
> 2. **Client App Registration:** The Flutter client writes the FCM token under:
>    `/profiles/$appCode/fcm_token` ([auth_provider.dart:L347](file:///Users/rajshekhar/code/projects/MedicineTrackerAppV2/lib/features/sync/presentation/providers/auth_provider.dart#L347))
>
> **Implications:** Since the Flutter app never updates `/users/$caretakerUid/fcmToken`, the cloud function will consistently fail to retrieve the FCM token, throwing a `"Caretaker FCM token not found"` error ([functions/index.js:L27-L29](file:///Users/rajshekhar/code/projects/MedicineTrackerAppV2/functions/index.js#L27-L29)).
>
> **Recommended Fix:** 
> Update the Cloud Function's lookup logic to resolve the caretaker's App Code from `/caretakers/$caretakerUid/app_code` first, and then fetch the FCM token from `/profiles/$appCode/fcm_token`. Alternatively, update the client application to save the FCM token directly to both the user and profiles indices.
