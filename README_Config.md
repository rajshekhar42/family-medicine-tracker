# Scheduled Cloud Function (Cron) - sync_acks Cleanup Configuration

This codebase now contains the fully integrated Firebase Cloud Functions codebase in the [functions/](file:///Users/rajshekhar/code/projects/MedicineTrackerAppV2/functions/) directory, configured inside [firebase.json](file:///Users/rajshekhar/code/projects/MedicineTrackerAppV2/firebase.json).

This includes the Scheduled Cloud Function (Cron) `cleanupStaleSyncAcks` which periodically deletes stale `sync_acks` from the Realtime Database (RTDB) as a safety net if client-side cleanup fails.

---

## 1. Directory Structure

The Firebase Functions configuration consists of:
* **[firebase.json](file:///Users/rajshekhar/code/projects/MedicineTrackerAppV2/firebase.json):** Configures Firebase to locate and compile the `functions/` folder.
* **[functions/package.json](file:///Users/rajshekhar/code/projects/MedicineTrackerAppV2/functions/package.json):** Defines the Node.js 18 engine, Firebase admin, and Firebase functions dependencies.
* **[functions/index.js](file:///Users/rajshekhar/code/projects/MedicineTrackerAppV2/functions/index.js):** Contains the production Cloud Functions code (including `syncData`, `ackSync`, and `cleanupStaleSyncAcks`).

---

## 2. Configured Functions in `functions/index.js`

### 1. `cleanupStaleSyncAcks` (Scheduled/Cron)
Deletes any `sync_acks` older than 7 days. By default, it is configured to run **weekly** on Sundays at 00:00 UTC.

```javascript
exports.cleanupStaleSyncAcks = functions.pubsub
  .schedule("0 0 * * 0") // Runs weekly (Sunday at 00:00 AM)
  .timeZone("UTC")
  .onRun(async (context) => {
    const db = admin.database();
    const cutoffTime = Date.now() - 7 * 24 * 60 * 60 * 1000; // 7 days in milliseconds

    const ref = db.ref("sync_acks");
    const snapshot = await ref.once("value");

    if (!snapshot.exists()) {
      console.log("No sync_acks found.");
      return null;
    }

    const updates = {};
    snapshot.forEach((childSnapshot) => {
      const ack = childSnapshot.val();
      if (ack && ack.timestamp && ack.timestamp < cutoffTime) {
        updates[childSnapshot.key] = null; // Mark node for deletion
      }
    });

    const deleteCount = Object.keys(updates).length;
    if (deleteCount > 0) {
      await ref.update(updates);
      console.log(`Successfully cleaned up ${deleteCount} stale sync_acks.`);
    } else {
      console.log("No stale sync_acks to clean up.");
    }
    return null;
  });
```

### 2. `syncData` (HTTPS Callable)
Responsible for routing payload sync alerts via FCM.

### 3. `ackSync` (HTTPS Callable)
Acknowledges sync events and logs details to Firestore `syncAudit` collection.

---

## 3. Changing the Cron Schedule Frequency

The cron schedule is defined by the string passed to `.schedule()`. It uses standard cron syntax:
```
* * * * *
│ │ │ │ │
│ │ │ │ └─── Day of week (0 - 6) (0 is Sunday)
│ │ │ └──────── Month (1 - 12)
│ │ └────────── Day of month (1 - 31)
│ └──────────── Hour (0 - 23)
└────────────── Minute (0 - 59)
```

To modify how often it runs, open [functions/index.js](file:///Users/rajshekhar/code/projects/MedicineTrackerAppV2/functions/index.js) and change `.schedule("0 0 * * 0")` to your desired frequency:

| Target Frequency | Cron Expression | Example Config Code |
| :--- | :--- | :--- |
| **Weekly** (Default) | `0 0 * * 0` | `.schedule("0 0 * * 0")` (Sunday at midnight) |
| **Daily** | `0 0 * * *` | `.schedule("0 0 * * *")` (Every night at midnight) |
| **Hourly** | `0 * * * *` | `.schedule("0 * * * *")` (Every hour at minute 0) |
| **Every 12 Hours** | `0 */12 * * *` | `.schedule("0 */12 * * *")` (At 12:00 AM and 12:00 PM) |

---

## 4. Changing the Cleanup Stale Cutoff Duration

To adjust the age at which an acknowledgment is considered "stale", modify the `cutoffTime` calculation in [functions/index.js](file:///Users/rajshekhar/code/projects/MedicineTrackerAppV2/functions/index.js):

* **Stale after 7 days (default):**
  ```javascript
  const cutoffTime = Date.now() - 7 * 24 * 60 * 60 * 1000;
  ```
* **Stale after 1 day (24 hours):**
  ```javascript
  const cutoffTime = Date.now() - 1 * 24 * 60 * 60 * 1000;
  ```
* **Stale after 12 hours:**
  ```javascript
  const cutoffTime = Date.now() - 12 * 60 * 60 * 1000;
  ```

---

## 5. Deployment Instructions

1. Ensure you have the Firebase CLI installed and are logged in:
   ```bash
   firebase login
   ```
2. Make sure you are using the correct Firebase project:
   ```bash
   firebase use <your-project-id>
   ```
3. Deploy the functions (this will deploy `syncData`, `ackSync`, and `cleanupStaleSyncAcks`):
   ```bash
   firebase deploy --only functions
   ```
   Or to deploy only the scheduler cron job:
   ```bash
   firebase deploy --only functions:cleanupStaleSyncAcks
   ```
