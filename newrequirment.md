# Data Sync System — Parent App to Caretaker App
## Requirements & Architecture for AI Coding Agent

> This is a greenfield implementation prompt. Build exactly what is described here.
> Do not implement anything not listed. Do not add features "for completeness".
> When anything is ambiguous, state your assumption explicitly in a code comment and flag it for review.

---

## 1. Overview

Build a one-way, event-driven data sync system between two Android apps:

- **Parent App** — holds the source of truth in its local database. Triggers sync when data changes.
- **Caretaker App** — receives synced data and ingests it into its own local database.

Many Parent App instances can push data to one Caretaker App. The Caretaker App is always the
single receiver. Data flows one way only — Parent → Caretaker, never the reverse.

There is no custom backend server. All server-side logic runs on Firebase Cloud Functions.
Data travels via HTTP POST to a Cloud Function, which delivers it to the Caretaker App via
Firebase Cloud Messaging (FCM).

---

## 2. Topology

```
Parent App (Device A) ──┐
Parent App (Device B) ──┼──► Cloud Function /syncData ──► FCM ──► Caretaker App
Parent App (Device C) ──┘
```

---

## 3. Tech Stack

| Layer | Technology | Notes |
|---|---|---|
| Language | Kotlin | Native Android, both apps |
| Min SDK | API 26 (Android 8.0) | Both apps |
| Auth | Firebase Auth — Google Sign-In | Both apps. UID identifies each device |
| Push delivery | Firebase Cloud Messaging (FCM) | High-priority data messages |
| Server logic | Firebase Cloud Functions (Node.js) | Two functions: /syncData and /ackSync |
| Presence / FCM token | Firebase Realtime Database | Minimal — fcmToken and presence only |
| Local DB — Parent App | Room (SQLite) | Source of truth, tracks sync status per record |
| Local DB — Caretaker App | Room (SQLite) | Destination DB + sync queue table |
| Serialization | kotlinx.serialization (JSON) | Payload serialization |
| Compression | gzip + Base64 | Reduces payload size before FCM delivery |
| DI | Hilt | Both apps |
| Async | Kotlin Coroutines + Flow | Both apps |
| Architecture | Clean Architecture (domain / data / presentation) | Both apps |

---

## 4. Payload Size Strategy

Every sync payload is compressed (gzip + Base64) before transmission.

Two delivery modes based on compressed payload size:

```
≤ 3.5 KB compressed   →   Single FCM message   (standard path)
> 3.5 KB compressed   →   Chunked FCM          (chunked path)
```

Both paths must be implemented. The standard path handles the majority of cases.
The chunked path is a fallback for larger payloads and must be equally robust.

### 4.1 Single Message Path

Entire compressed payload fits in one FCM data message.
Caretaker App receives it, decompresses, and ingests directly.

### 4.2 Chunked Path

Payload is split into chunks of ≤ 3.5 KB each after compression.
Each chunk is sent as a separate FCM message.
Caretaker App reassembles chunks in order before decompressing and ingesting.

Chunk FCM message fields:
```
syncId        — shared UUID across all chunks of this sync event
chunkIndex    — zero-based index of this chunk (0, 1, 2 ...)
totalChunks   — total number of chunks for this syncId
chunkData     — this chunk's Base64-encoded bytes
checksum      — MD5 of the FULL decompressed JSON (same in every chunk)
eventType     — repeated in every chunk
senderUid     — repeated in every chunk
senderAppId   — repeated in every chunk
timestamp     — repeated in every chunk
```

Caretaker App reassembly rules:
- Store each arriving chunk in a ChunkBuffer Room table keyed by (syncId, chunkIndex)
- Once all totalChunks chunks are present for a syncId, reassemble in chunkIndex order
- Concatenate chunk bytes → Base64 decode → gunzip → JSON string
- Verify checksum against reassembled JSON
- If any chunk is missing after 60 seconds from first chunk received → mark as
  chunk_timeout, discard buffer, ack failure
- If checksum fails after reassembly → mark as corrupted, discard, ack failure
- Chunks may arrive out of order — always sort by chunkIndex before concatenating

---

## 5. Firebase Data Structure

Firebase Realtime DB is used only for FCM token storage and presence tracking.
No sync payload data ever touches Firebase Realtime DB.

```json
{
  "users": {
    "": {
      "fcmToken":  "abc123...",
      "presence":  "online | offline | busy",
      "role":      "parent | caretaker",
      "lastSeen":  ""
    }
  }
}
```

### 5.1 Presence Tracking — Caretaker App Only

```kotlin
// On app foreground
presenceRef.setValue("online")

// On app background
presenceRef.setValue("offline")

// On app killed — Firebase sets this automatically
presenceRef.onDisconnect().setValue("offline")

// While SyncIngestionService is processing an item
presenceRef.setValue("busy")

// After SyncIngestionService finishes item
presenceRef.setValue("online")
```

Where presenceRef = db.child("users").child(myUid).child("presence")

The Parent App does not track presence. FCM handles delivery to the Caretaker App
regardless of its running state.

---

## 6. Delivery Behaviour

FCM delivers to the Caretaker App regardless of whether the app is running:

```
Caretaker App in foreground      →  onMessageReceived() fires directly
Caretaker App in background      →  onMessageReceived() fires directly
Caretaker App killed             →  Android OS wakes app, onMessageReceived() fires
Caretaker device has no internet →  FCM queues message (TTL: 4 weeks),
                                    delivers automatically on connectivity resume
```

There is no presence check before sending from the Parent App.
FCM's own delivery guarantee handles offline devices.

---

## 7. Cloud Functions (Node.js)

Two HTTP callable Cloud Functions. Both require Firebase Auth (context.auth).
Deploy on Blaze plan.

### 7.1 /syncData — Called by Parent App

```javascript
exports.syncData = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Login required")
    }
    const {
        caretakerUid, senderAppId, eventType, syncId, checksum, timestamp,
        isChunked, compressedData, chunkIndex, totalChunks, chunkData
    } = data

    if (!caretakerUid || !eventType || !syncId || !checksum) {
        throw new functions.https.HttpsError("invalid-argument", "Missing required fields")
    }

    const snap = await admin.database()
        .ref(`/users/${caretakerUid}/fcmToken`).once("value")
    const fcmToken = snap.val()
    if (!fcmToken) {
        throw new functions.https.HttpsError("not-found", "Caretaker FCM token not found")
    }

    const fcmData = isChunked ? {
        type: "data_sync_chunk", syncId,
        senderUid: context.auth.uid, senderAppId, eventType,
        timestamp: String(timestamp), checksum,
        chunkIndex: String(chunkIndex), totalChunks: String(totalChunks), chunkData
    } : {
        type: "data_sync", syncId,
        senderUid: context.auth.uid, senderAppId, eventType,
        timestamp: String(timestamp), checksum, compressedData
    }

    await admin.messaging().send({
        token: fcmToken, android: { priority: "high" }, data: fcmData
    })
    return { status: "delivered", syncId }
})
```

### 7.2 /ackSync — Called by Caretaker App after ingestion

```javascript
exports.ackSync = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Login required")
    }
    const { syncId, status, failureReason } = data
    await admin.firestore().collection("syncAudit").doc(syncId).set({
        syncId, status, failureReason: failureReason ?? null,
        ackedBy: context.auth.uid,
        ackedAt: admin.firestore.FieldValue.serverTimestamp()
    })
    return { status: "acknowledged" }
})
```

---

## 8. Compression & Checksum Utility

Implement in both apps (or a shared module if monorepo):

```kotlin
object PayloadCompressor {

    private const val MAX_CHUNK_BYTES = 3584   // 3.5 KB hard limit per FCM message

    fun compress(json: String): ByteArray {
        val output = ByteArrayOutputStream()
        GZIPOutputStream(output).use { it.write(json.toByteArray(Charsets.UTF_8)) }
        return output.toByteArray()
    }

    fun decompress(bytes: ByteArray): String =
        GZIPInputStream(bytes.inputStream()).bufferedReader(Charsets.UTF_8).readText()

    fun toBase64(bytes: ByteArray): String =
        Base64.encodeToString(bytes, Base64.NO_WRAP)

    fun fromBase64(encoded: String): ByteArray =
        Base64.decode(encoded, Base64.NO_WRAP)

    fun checksum(json: String): String {
        val md = MessageDigest.getInstance("MD5")
        return md.digest(json.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }
    }

    fun isSingleMessage(compressedBytes: ByteArray): Boolean =
        compressedBytes.size <= MAX_CHUNK_BYTES

    fun splitIntoChunks(compressedBytes: ByteArray): List =
        compressedBytes.asList().chunked(MAX_CHUNK_BYTES).map { it.toByteArray() }
}
```

---

## 9. Parent App — Implementation

### 9.1 Sync Status Fields

Add to every Room entity that participates in sync:

```kotlin
val syncStatus:      String  = "unsynced",   // unsynced | syncing | synced | sync_failed
val lastSyncAttempt: Long?   = null,
val syncId:          String? = null
```

### 9.2 SyncDataUseCase

```kotlin
class SyncDataUseCase @Inject constructor(
    private val repository: SyncRepository
) {
    suspend operator fun invoke(
        record: YourDomainModel, caretakerUid: String
    ): SyncResult {
        val json            = Json.encodeToString(record)
        val checksum        = PayloadCompressor.checksum(json)
        val compressedBytes = PayloadCompressor.compress(json)
        val syncId          = UUID.randomUUID().toString()

        return if (PayloadCompressor.isSingleMessage(compressedBytes)) {
            repository.sendSingle(
                syncId = syncId, caretakerUid = caretakerUid,
                compressedData = PayloadCompressor.toBase64(compressedBytes),
                checksum = checksum
            )
        } else {
            repository.sendChunked(
                syncId = syncId, caretakerUid = caretakerUid,
                chunks = PayloadCompressor.splitIntoChunks(compressedBytes),
                checksum = checksum
            )
        }
    }
}
```

### 9.3 SyncRepository Interface

```kotlin
interface SyncRepository {
    suspend fun sendSingle(
        syncId: String, caretakerUid: String,
        compressedData: String, checksum: String
    ): SyncResult

    suspend fun sendChunked(
        syncId: String, caretakerUid: String,
        chunks: List, checksum: String
    ): SyncResult
}
```

Implementation notes:
- sendChunked sends each chunk sequentially — one HTTP call per chunk
- If any chunk HTTP call fails → mark entire syncId as sync_failed, stop sending
- Mark syncStatus = "synced" only after HTTP 200 for all chunks
- Do not auto-retry — surface failure to user via UI

---

## 10. Caretaker App — Implementation

### 10.1 Room Entities

```kotlin
@Entity(tableName = "sync_queue")
data class SyncQueueItem(
    @PrimaryKey val syncId: String,
    val senderUid:          String,
    val senderAppId:        String,
    val eventType:          String,
    val compressedData:     String,    // Base64 of full gzipped payload
    val checksum:           String,
    val timestamp:          Long,
    val isChunked:          Boolean,
    val status:             String,    // pending | processing | done | failed
    val receivedAt:         Long = System.currentTimeMillis(),
    val processedAt:        Long?   = null,
    val failureReason:      String? = null
)

@Entity(tableName = "chunk_buffer", primaryKeys = ["syncId", "chunkIndex"])
data class ChunkBufferItem(
    val syncId:      String,
    val chunkIndex:  Int,
    val totalChunks: Int,
    val chunkData:   String,   // Base64 of this chunk's raw bytes
    val checksum:    String,   // checksum of FULL payload — same in every chunk
    val senderUid:   String,
    val senderAppId: String,
    val eventType:   String,
    val timestamp:   Long,
    val receivedAt:  Long
)
```

### 10.2 FirebaseMessagingService

```kotlin
class CaretakerMessagingService : FirebaseMessagingService() {

    override fun onMessageReceived(message: RemoteMessage) {
        when (message.data["type"]) {
            "data_sync"       -> handleSingleMessage(message.data)
            "data_sync_chunk" -> handleChunk(message.data)
        }
    }

    private fun handleSingleMessage(data: Map) {
        scope.launch {
            syncQueueDao.insert(SyncQueueItem(
                syncId = data["syncId"]!!, senderUid = data["senderUid"]!!,
                senderAppId = data["senderAppId"]!!, eventType = data["eventType"]!!,
                compressedData = data["compressedData"]!!, checksum = data["checksum"]!!,
                timestamp = data["timestamp"]!!.toLong(), isChunked = false, status = "pending"
            ))
            startSyncIngestionService()
        }
    }

    private fun handleChunk(data: Map) {
        scope.launch {
            chunkBufferDao.insert(ChunkBufferItem(
                syncId = data["syncId"]!!, chunkIndex = data["chunkIndex"]!!.toInt(),
                totalChunks = data["totalChunks"]!!.toInt(), chunkData = data["chunkData"]!!,
                checksum = data["checksum"]!!, senderUid = data["senderUid"]!!,
                senderAppId = data["senderAppId"]!!, eventType = data["eventType"]!!,
                timestamp = data["timestamp"]!!.toLong(), receivedAt = System.currentTimeMillis()
            ))
            tryReassemble(data["syncId"]!!, data["totalChunks"]!!.toInt())
        }
    }

    private suspend fun tryReassemble(syncId: String, totalChunks: Int) {
        val received = chunkBufferDao.getChunksForSync(syncId)
        if (received.size < totalChunks) return

        val ordered          = received.sortedBy { it.chunkIndex }
        val first            = ordered.first()
        val reassembledBytes = ordered
            .map { PayloadCompressor.fromBase64(it.chunkData) }
            .reduce { acc, bytes -> acc + bytes }

        syncQueueDao.insert(SyncQueueItem(
            syncId = syncId, senderUid = first.senderUid, senderAppId = first.senderAppId,
            eventType = first.eventType,
            compressedData = PayloadCompressor.toBase64(reassembledBytes),
            checksum = first.checksum, timestamp = first.timestamp,
            isChunked = true, status = "pending"
        ))
        chunkBufferDao.deleteForSync(syncId)
        startSyncIngestionService()
    }

    override fun onNewToken(token: String) {
        scope.launch {
            db.child("users").child(myUid).child("fcmToken").setValue(token)
        }
    }
}
```

### 10.3 SyncIngestionService

```kotlin
class SyncIngestionService : Service() {

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(NOTIFICATION_ID, buildNotification("Syncing data..."))
        scope.launch {
            syncQueueDao.resetStuck()
            expireStaleChunks()
            while (true) {
                val item = syncQueueDao.getNextPending() ?: break
                processItem(item)
            }
            stopSelf()
        }
        return START_NOT_STICKY
    }

    private suspend fun expireStaleChunks() {
        val cutoff   = System.currentTimeMillis() - 60_000L
        val staleIds = chunkBufferDao.getStaleIncompleteGroups(cutoff)
        staleIds.forEach { syncId ->
            chunkBufferDao.deleteForSync(syncId)
            ackSync(syncId, "chunk_timeout", "Chunks did not arrive within 60 seconds")
        }
    }

    private suspend fun processItem(item: SyncQueueItem) {
        syncQueueDao.markProcessing(item.syncId)
        presenceRef.setValue("busy")
        try {
            val bytes    = PayloadCompressor.fromBase64(item.compressedData)
            val json     = PayloadCompressor.decompress(bytes)
            val computed = PayloadCompressor.checksum(json)

            if (computed != item.checksum) {
                markFailed(item.syncId, "checksum_failed", "Checksum mismatch")
                return
            }

            val record = Json.decodeFromString(json)
            localRepository.upsert(record)
            syncQueueDao.markDone(item.syncId)
            ackSync(item.syncId, "success", null)

        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            markFailed(item.syncId, "parse_failed", e.message)
        } finally {
            presenceRef.setValue("online")
        }
    }

    private suspend fun markFailed(syncId: String, reason: String, detail: String?) {
        syncQueueDao.markFailed(syncId, reason)
        ackSync(syncId, reason, detail)
    }
}
```

---

## 11. Functional Requirements

### Parent App
- [ ] Google Sign-In via Firebase Auth
- [ ] Save FCM token to users/{uid}/fcmToken on login and in onNewToken()
- [ ] Detect local DB changes and trigger SyncDataUseCase
- [ ] Serialize record to JSON → compress → checksum
- [ ] Route to single message path if compressed size ≤ 3.5 KB
- [ ] Route to chunked path if compressed size > 3.5 KB
- [ ] Single path: one HTTP POST to /syncData with full payload
- [ ] Chunked path: one HTTP POST to /syncData per chunk, sent sequentially
- [ ] On any HTTP error during chunked send → stop, mark entire sync as sync_failed
- [ ] Mark syncStatus = "syncing" at start, "synced" on full success, "sync_failed" on error
- [ ] Surface sync_failed records in UI — do not silently swallow failures
- [ ] No auto-retry — retry is user-initiated only

### Caretaker App
- [ ] Google Sign-In via Firebase Auth
- [ ] Save FCM token to users/{uid}/fcmToken on login and in onNewToken()
- [ ] Maintain presence in Firebase with onDisconnect() fallback
- [ ] Handle data_sync FCM type → insert to sync_queue → start SyncIngestionService
- [ ] Handle data_sync_chunk FCM type → insert to chunk_buffer → attempt reassembly
- [ ] Reassemble chunks only when all totalChunks are present for a syncId
- [ ] Sort chunks by chunkIndex before concatenating
- [ ] Expire incomplete chunk sets after 60 seconds from first chunk received
- [ ] Process sync_queue sequentially — one item at a time, never concurrent
- [ ] Reset processing → pending on service start (crash recovery)
- [ ] Verify checksum after decompression — reject and ack failure if mismatch
- [ ] Write ingested record to local Room DB via upsert
- [ ] Call /ackSync after every item regardless of outcome
- [ ] Show foreground notification during SyncIngestionService run
- [ ] Delete done/failed queue items after 24 hours
- [ ] Delete chunk_buffer rows immediately after successful reassembly

### Cloud Functions
- [ ] /syncData — validate auth, fetch Caretaker FCM token, send FCM, return syncId
- [ ] /ackSync — validate auth, log result to Firestore syncAudit collection
- [ ] Both functions reject unauthenticated requests
- [ ] /syncData validates required fields before sending FCM

---

## 12. Non-Functional Requirements

- Data integrity: Checksum verified on every payload before any DB write.
  Corrupted or mismatched payloads are rejected and never written to local DB.
- Sequential ingestion: Caretaker App processes exactly one sync item at a time.
- Crash recovery: Items stuck in processing on service restart are reset to
  pending and reprocessed from scratch.
- No payload data in Firebase DB: Sync payloads never touch Firebase Realtime DB.
  Only fcmToken and presence are stored there.
- FCM payload hard limit: 3.5 KB per FCM message enforced in PayloadCompressor.
- Chunk ordering: Chunks may arrive in any order. Reassembly always sorts by
  chunkIndex before concatenating bytes.
- Audit trail: Every sync outcome logged to Firestore syncAudit via /ackSync.

---

## 13. Out of Scope — Do Not Implement

- Two-way sync (Caretaker → Parent): One-way only by design
- Auto-retry on sync failure: User-initiated retry only
- Firebase Storage for payloads: Chunked FCM handles all sizes
- Conflict resolution: Last write wins on Caretaker App
- Batch sync of multiple records per event: One record per sync event
- Real-time sync status pushed back to Parent: Async ack only
- Encryption beyond FCM/TLS transport security: Out of scope for V1
- iOS apps: Android only

---

## 14. Firebase Setup Checklist

- [ ] Create Firebase project(s) and register both Android apps
- [ ] Download google-services.json for each app → place in respective app/ directories
- [ ] Enable Google Sign-In → Authentication → Sign-in methods
- [ ] Enable Firebase Realtime Database in locked mode with these rules:
      {
        "rules": {
          "users": {
            "$uid": {
              ".read":  "$uid === auth.uid",
              ".write": "$uid === auth.uid"
            }
          }
        }
      }
- [ ] Enable Cloud Messaging (FCM) — on by default
- [ ] Upgrade to Blaze plan (required for Cloud Functions)
- [ ] Deploy /syncData and /ackSync Cloud Functions
- [ ] Enable Firestore for the syncAudit collection
- [ ] Enable Firebase App Check with Play Integrity (after end-to-end flow is working)

---

## 15. Key Dependencies (app/build.gradle — both apps)

implementation(platform("com.google.firebase:firebase-bom:32.7.0"))
implementation("com.google.firebase:firebase-auth-ktx")
implementation("com.google.firebase:firebase-database-ktx")
implementation("com.google.firebase:firebase-messaging-ktx")
implementation("com.google.firebase:firebase-functions-ktx")
implementation("com.google.android.gms:play-services-auth:20.7.0")
implementation("androidx.room:room-runtime:2.6.1")
implementation("androidx.room:room-ktx:2.6.1")
kapt("androidx.room:room-compiler:2.6.1")
implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.6.0")
implementation("com.google.dagger:hilt-android:2.48")
kapt("com.google.dagger:hilt-android-compiler:2.48")
implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")

---

## 16. Build Phases

Phase 1: Firebase Auth + Google Sign-In in both apps. FCM token saved on login and onNewToken().
Phase 2: Presence tracking in Caretaker App only. onDisconnect() fallback.
Phase 3: PayloadCompressor utility — compress, decompress, checksum, isSingleMessage,
          splitIntoChunks. Write unit tests for ALL methods before moving on.
Phase 4: Parent App sync trigger → single message path → /syncData Cloud Function →
          FCM delivery → Caretaker App onMessageReceived() → sync_queue insert.
          Validate end-to-end with a small payload before building ingestion.
Phase 5: Caretaker App SyncIngestionService — sequential queue processing,
          checksum verification, Room DB upsert, /ackSync call, foreground notification.
Phase 6: Chunked path — ChunkBufferItem entity + DAO, chunk reassembly in
          FirebaseMessagingService, 60-second expiry in SyncIngestionService.
          Test with a payload that exceeds 3.5 KB compressed.
Phase 7: Parent App sync status tracking in local DB + UI for sync_failed records.
Phase 8: Firebase Security Rules hardening, App Check, error handling polish,
          notification refinement, queue cleanup job (delete done/failed after 24h).
