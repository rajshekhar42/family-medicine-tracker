# Sync Test Suite — Test Case Documentation

> **Source of Truth** for all test cases executed by `./run_sync_emulator_only.sh`
>
> Generated from:
> - [`run_sync_emulator_only.sh`](file:///Users/rajshekhar/code/projects/MedicineTrackerAppV2/run_sync_emulator_only.sh)
> - [`test_sync_only.py`](file:///Users/rajshekhar/code/projects/MedicineTrackerAppV2/AutomatedTest/sync_test/test_sync_only.py)
> - [`test_sync_in_async_manner.py`](file:///Users/rajshekhar/code/projects/MedicineTrackerAppV2/AutomatedTest/sync_test/test_sync_in_async_manner.py)

---

## Execution Overview

```
run_sync_emulator_only.sh
  ├── Build debug APK
  ├── Clear app data on both devices (pm clear)
  ├── Install APK on emulator (Parent) and physical device (Caretaker)
  ├── Wipe SQLite DB on both devices (preserves Google login session)
  ├── Grant permissions (notification, exact alarm, accessibility)
  ├── Launch app on both devices
  └── Execute test_sync_only.py
        └── (STEP 10) Chains into → test_sync_in_async_manner.py
```

**Devices:**

| Role | Default Device ID |
|------|------------------|
| Parent | `emulator-5554` |
| Caretaker | `emulator-5556` (or physical device) |

**Pre-requisites enforced by the script:**
- Fresh APK install with SQLite DB wiped (Google login session preserved)
- Both devices have internet access
- Notification, exact alarm, and accessibility permissions granted automatically

---

## Part 1 — `test_sync_only.py` (Steps 0–10)

---

### STEP 0 — Onboarding on Both Devices

| Field | Detail |
|-------|--------|
| **What is tested** | Onboarding screen completes successfully after a fresh DB wipe |
| **Parent profile name** | `"Parent Userrrrr"` |
| **Parent profile type** | Self (non-caretaker) |
| **Caretaker profile name** | `"Cccccaretaker User"` |
| **Caretaker profile type** | Caretaker |
| **Outcome** | Both devices land on the Home screen after onboarding |

---

### STEP 0.1 — Add & Log Doses on Parent (Pre–Google Sign-In)

| Field | Detail |
|-------|--------|
| **What is tested** | Local data created before Google Sign-In is preserved |
| **Actions** | Add `ParentPreMed1<ts>` → Mark **Taken**; Add `ParentPreMed2<ts>` → Mark **Skipped** |
| **Data scope** | Parent device only, local-only at this point |
| **Outcome** | Two medicines exist locally with correct taken/skipped statuses |

---

### STEP 0.2 — Add & Log Doses on Caretaker (Pre–Google Sign-In)

| Field | Detail |
|-------|--------|
| **What is tested** | Caretaker local data created before Google Sign-In is preserved |
| **Actions** | Add `CaretakerPreMed1<ts>` → Mark **Taken**; Add `CaretakerPreMed2<ts>` → Mark **Skipped** |
| **Data scope** | Caretaker device only, local-only at this point |
| **Outcome** | Two medicines exist locally with correct taken/skipped statuses |

---

### STEP 0.5 — Google Sign-In Verification (Both Devices)

| Field | Detail |
|-------|--------|
| **What is tested** | Google Sign-In succeeds and generates an App Code for each device |
| **Parent account** | `rajshekhardev@gmail.com` |
| **Caretaker account** | `rajshekhar53@gmail.com` |
| **Verification** | `MY APP CODE` label appears in the profile drawer after sign-in |
| **Retry logic** | One automatic retry if the first sign-in attempt returns without an App Code |
| **Failure behavior** | `sys.exit(1)` if either device fails to sign in |

---

### STEP 0.51 — App Codes Are Unique on Both Devices

| Field | Detail |
|-------|--------|
| **What is tested** | Each device generates a distinct App Code; codes are not shared or duplicated |
| **How verified** | App Code text extracted from the profile drawer on each device and string-compared |
| **Failure behavior** | `sys.exit(1)` if codes match or cannot be retrieved |

---

### STEP 0.6 — Local Medicines Persist After Google Sign-In

| Field | Detail |
|-------|--------|
| **What is tested** | Pre-login local medicines and dose logs survive Google Sign-In without data loss |
| **Parent checks** | `ParentPreMed1` in Medicine List; `ParentPreMed1` as **Taken** in History; `ParentPreMed2` as **Skipped** in History |
| **Caretaker checks** | Switches to caretaker owner profile; `CaretakerPreMed1` in Medicine List; `CaretakerPreMed1` as **Taken** in History; `CaretakerPreMed2` as **Skipped** in History |
| **Outcome** | All pre-login data persists unchanged post-sign-in |

---

### STEP 1 — Retrieve Parent App Code

| Field | Detail |
|-------|--------|
| **What is tested** | App Code is readable from the profile drawer (prerequisite for pairing) |
| **Failure behavior** | `sys.exit(1)` if code is not obtainable |

---

### STEP 2 — Caretaker Requests Pairing

| Field | Detail |
|-------|--------|
| **What is tested** | Caretaker can initiate a pairing request using the Parent's App Code |
| **Action** | Caretaker opens drawer → enters Parent App Code → labels connection as `"Parent Shekhar"` |
| **Outcome** | Pairing request sent to Parent via Firebase Realtime Database |

---

### STEP 2.5 — Pairing Approval Banner NOT Shown on Caretaker

| Field | Detail |
|-------|--------|
| **What is tested** | The "Accept" banner is shown only on the Parent device, never on the Caretaker |
| **How verified** | UI dump searched for the `"Accept"` element on Caretaker; must be absent |
| **Failure behavior** | `sys.exit(1)` if banner is found on Caretaker |

---

### STEP 2.6 — Caretaker Shows "Pending Approval" for Parent Profile

| Field | Detail |
|-------|--------|
| **What is tested** | After a pairing request is sent, the Parent profile tile in Caretaker's drawer shows a `"Pending Approval"` badge |
| **How verified** | Both `"Parent Shekhar"` tile and `"Pending Approval"` text must be present in the drawer |
| **Failure behavior** | `sys.exit(1)` if either element is missing |

---

### STEP 2.7 — Pairing Banner Persists After App Reopen

| Field | Detail |
|-------|--------|
| **What is tested** | The pending pairing approval banner on Parent's Home screen survives a force-close + reopen cycle |
| **Flow** | Verify banner visible → Force-stop Parent app → Relaunch → Verify banner still visible |
| **Wait time** | 8 seconds post-launch to allow RTDB linking and startup sync to complete |
| **Failure behavior** | `sys.exit(1)` if banner disappears after reopen |

---

### STEP 3 — Parent Accepts Connection Request

| Field | Detail |
|-------|--------|
| **What is tested** | Parent can accept the pending pairing request via the on-screen banner |
| **Fallback** | If banner not found on Home screen, tries again via the profile drawer |
| **Failure behavior** | `sys.exit(1)` if pairing cannot be accepted |

---

### STEP 3.5 — Parent Profile Visible in Caretaker Profile Menu After Acceptance

| Field | Detail |
|-------|--------|
| **What is tested** | Once Parent accepts the request, Caretaker's profile drawer shows the Parent profile as active (no `"Pending Approval"` badge) |
| **Wait time** | 5 seconds for RTDB stream and state to propagate |
| **Checks** | Parent tile present; `"Pending Approval"` badge absent |
| **Failure behavior** | `sys.exit(1)` if Parent tile not found |

---

### STEP 4 — Switch to Parent Profile on Caretaker

| Field | Detail |
|-------|--------|
| **What is tested** | Caretaker can switch their active profile to the paired Parent profile |
| **Action** | Tap the Parent profile tile in Caretaker's profile drawer |

---

### STEP 4.1 — Local Medicines Persist After Pairing

| Field | Detail |
|-------|--------|
| **What is tested** | Pre-pairing local medicines and dose history on both devices are not wiped or corrupted by the pairing process |
| **Setup note** | Both apps are force-stopped and relaunched (10s wait) to eliminate calendar-date drift across long test runs |
| **Parent checks** | `ParentPreMed1` in Medicine List; `ParentPreMed1` **Taken** & `ParentPreMed2` **Skipped** in History |
| **Caretaker checks** | Switches to caretaker owner profile; `CaretakerPreMed1` in Medicine List; `CaretakerPreMed1` **Taken** & `CaretakerPreMed2` **Skipped** in History |
| **After** | Caretaker active profile switched back to Parent for subsequent sync tests |

---

### STEP 5 — Add Medicine on Parent & Manual Sync to Caretaker

| Field | Detail |
|-------|--------|
| **What is tested** | End-to-end bidirectional manual sync: Parent adds medicine → marks dose Taken → pushes to Firebase → Caretaker pulls from Firebase |
| **Medicine name** | `SyncMed<timestamp>` (unique per run) |
| **Frequency** | Once a Day |
| **Dose action** | Marked **Taken** on Parent |
| **Sync trigger (Parent)** | "Sync Now" button in profile drawer; 12s wait |
| **Sync trigger (Caretaker)** | "Sync Now" button in profile drawer; 12s wait |

---

### STEP 6 — Verify Medicine in Caretaker Medicine List

| Field | Detail |
|-------|--------|
| **What is tested** | Medicine added on Parent appears in the Caretaker's Medicine List after pull sync |
| **Verified element** | `SyncMed<timestamp>` present in Medicine List |

---

### STEP 7 — Verify Taken Dose in Caretaker History

| Field | Detail |
|-------|--------|
| **What is tested** | Dose status (Taken) synced from Parent is reflected in Caretaker's History page |
| **Verified element** | `SyncMed<timestamp>` appears in History with **Taken** status |

---

### STEP 8 — Sync Integrity: Interleaved Caretaker Additions vs. Parent Dose Status

| Field | Detail |
|-------|--------|
| **What is tested** | A new medicine sync from Caretaker does not overwrite or undo dose statuses previously marked on Parent (no sync undo) |
| **Medicines** | `IntegMedA<ts>`, `IntegMedB<ts>` (both added by Caretaker) |
| **Sequence** | 1. Caretaker adds MedA → 15s auto-sync wait → 2. Parent verifies MedA → marks MedA **Taken** → 3. Caretaker adds MedB → 15s auto-sync wait → 4. Parent verifies MedB → 5. Parent checks History: MedA must still be **Taken** |
| **Key assertion** | After MedB sync, `IntegMedA` dose status must remain **Taken** in Parent's History |

---

### STEP 9 — Parent Logout & Re-Login Sync Verification

| Field | Detail |
|-------|--------|
| **What is tested** | Parent can sign out and re-login; App Code is preserved across logout/re-login; post-relogin medicine syncs to Caretaker |
| **App Code check** | Code before logout must equal code after re-login |
| **Post-relogin action** | Add `ReloginMed<ts>` → trigger "Sync Now" on Parent (12s) → trigger "Sync Now" on Caretaker (12s) |
| **Final verification** | `ReloginMed<ts>` present in Caretaker's Medicine List |
| **Failure behavior** | Exception raised if App Code changes; `sys.exit(1)` if re-login fails |

---

### STEP 10 — Async & Offline Sync Sub-Suite (Chains to `test_sync_in_async_manner.py`)

| Field | Detail |
|-------|--------|
| **What is tested** | Full offline-capable and asynchronous sync scenarios (see Part 2 below) |
| **How invoked** | `subprocess.run` — the parent test waits for full completion before proceeding |
| **Failure behavior** | `sys.exit(returncode)` if the sub-suite exits non-zero |

---

## Part 2 — `test_sync_in_async_manner.py` (Test Cases 1–7)

> Invoked by STEP 10. A setup phase runs first to guarantee both devices are paired and internet is on before any test case executes.

---

### Setup Phase — `ensure_paired()` Helper

| Field | Detail |
|-------|--------|
| **What it does** | Idempotently ensures both devices are onboarded, Google-signed-in, and paired with each other |
| **Includes** | Onboarding check on both, Google Sign-In check (both accounts), pairing check (initiates + Parent accepts if not yet paired), ensures Caretaker active profile is set to Parent, clears leftover RTDB inbox payloads via a Caretaker sync |

---

### TEST CASE 1 — Parent Offline Operations → App Close → Internet ON → App Open Auto-Sync

| Field | Detail |
|-------|--------|
| **Scenario** | Parent adds medicine and marks dose while offline; after reconnecting, startup auto-sync pushes data to Firebase |
| **Medicine** | `ParentOffMed1<ts>` |
| **Dose action** | Marked **Taken** while offline |
| **Flow** | Turn off Parent internet → Add medicine → Mark Taken → Force-close app → Turn on internet → Clear logcat → Launch app → Trigger push sync (12s) → Verify logcat Firebase payload upload |
| **Caretaker side** | Force-close + relaunch → ensure Parent profile active → trigger pull sync (12s) |
| **Verifications** | `ParentOffMed1` in Caretaker Medicine List; `ParentOffMed1` as **Taken** in Caretaker History |
| **Logcat check** | Searches for any of: `"Uploaded sync payload"`, `"uploaded to slot"`, `"SyncRepo:"`, `"sync_payloads"`, `"tableSyncQueue"` |

---

### TEST CASE 2 — Caretaker Offline → Parent Takes Doses → Firebase Upload → Caretaker Reconnects & Auto-Syncs

| Field | Detail |
|-------|--------|
| **Scenario** | Caretaker is offline while Parent adds a medicine, marks a dose Taken, and uploads payload to Firebase; Caretaker then reconnects and pulls the data |
| **Medicine** | `ParentAsyncMed3<ts>` |
| **Dose action** | Marked **Taken** on Parent while Caretaker is offline |
| **Flow** | Turn off Caretaker internet → Parent adds medicine → marks Taken → Parent sync (8s) → Verify logcat upload → Turn on Caretaker internet → Force-close + relaunch Caretaker → ensure Parent profile active → Caretaker pull sync (10s) |
| **Verifications** | `ParentAsyncMed3` in Caretaker Medicine List; `ParentAsyncMed3` as **Taken** in Caretaker History |
| **Key behavior tested** | Firebase RTDB inbox acts as a durable store so Caretaker receives data uploaded while it was offline |

---

### TEST CASE 3 — Parent Offline Manual Sync → Internet ON → Manual Sync Upload

| Field | Detail |
|-------|--------|
| **Scenario** | Parent attempts manual sync while offline (expects graceful no-op / no crash), then successfully syncs once back online |
| **Medicine** | `ManualMed5<ts>` |
| **Dose action** | Marked **Skipped** while offline |
| **Flow** | Turn off Parent internet → Add medicine → Mark Skipped → Tap "Sync Now" while offline (3s wait, no crash) → Turn on internet → Clear logcat → Trigger sync (8s) → Verify logcat upload → Caretaker pull sync (8s) |
| **Verifications** | `ManualMed5` appears in Caretaker History as **Skipped** |
| **Key behavior tested** | Offline "Sync Now" is a graceful no-op; data is uploaded correctly once internet is restored |

---

### TEST CASE 4 — Caretaker Offline Operations & Startup Auto-Push Sync

| Field | Detail |
|-------|--------|
| **Scenario** | Caretaker adds a medicine for the Parent profile while offline; after reconnecting, startup auto-push sync uploads to Firebase and Parent receives it |
| **Medicine** | `CaretakerOffMed6<ts>` |
| **Dose action** | None (medicine addition only) |
| **Flow** | Turn off Caretaker internet → Ensure on Parent profile → Navigate Medicine List → Add medicine → Force-close app → Turn on internet → Clear logcat → Launch app → Ensure Parent profile active → Trigger push sync (10s) → Verify logcat upload → Parent pull sync (8s) |
| **Verifications** | `CaretakerOffMed6` in Parent Medicine List |
| **Key behavior tested** | Caretaker-side offline writes (for the Parent profile) are queued locally and auto-pushed upon reconnection |

---

### TEST CASE 5 — Parent Logout → Offline Mark Taken → Re-Login → Online Mark Taken → Full Sync

| Field | Detail |
|-------|--------|
| **Scenario** | Data created while logged out is preserved and synced after re-login, alongside data created post-login |
| **Medicines** | `LogoutMed7<ts>` (added while logged out); `LoginMed8<ts>` (added after re-login) |
| **Dose actions** | `LogoutMed7` marked **Taken** while logged out; `LoginMed8` marked **Taken** after re-login |
| **App Code check** | App Code before logout must equal App Code after re-login |
| **Flow** | Parent sign out → Add + mark LogoutMed7 → Re-login Google → Add + mark LoginMed8 → Parent push sync (10s) → Caretaker pull sync (10s) |
| **Verifications** | `LogoutMed7` in Caretaker Medicine List; `LoginMed8` in Caretaker Medicine List |
| **Key behavior tested** | Logged-out additions queue correctly and sync post-login alongside new logged-in additions |

---

### TEST CASE 6 — Caretaker Logout → Connection Deletion → Login & Re-Pairing

| Field | Detail |
|-------|--------|
| **Scenario** | After Caretaker logs out, their paired connections are removed; they can re-pair after re-login and receive synced Parent data |
| **App Code check** | Caretaker App Code before logout must equal App Code after re-login |
| **Post-logout verification** | `"Parent Shekhar"` tile must NOT be present in Caretaker's profile drawer |
| **Re-pairing flow** | Caretaker enters Parent App Code → Parent accepts connection banner (up to 5 retries × 3s) → Caretaker ensures Parent profile active |
| **Post-repairing sync** | Parent push sync (8s) → Caretaker pull sync (8s) |
| **Verifications** | `LogoutMed7` (from TC-5) in Caretaker Medicine List |
| **Key behavior tested** | Logout cleanly removes the paired profile; re-pairing re-establishes full sync access to existing Parent data |

---

### TEST CASE 7 — Caretaker Storage Data Wipe (pm clear) → Setup → Re-Pairing → Data Sync

| Field | Detail |
|-------|--------|
| **Scenario** | Simulates a complete uninstall/reinstall by wiping all Caretaker app storage; Caretaker must re-onboard, re-login, re-pair, and receive Parent data fresh |
| **Wipe method** | `adb shell pm clear <package>` — removes all app data, SharedPreferences, SQLite, etc. |
| **Post-wipe verification** | `"Parent Shekhar"` tile must NOT appear in drawer after wipe + re-onboard + re-login |
| **Re-pairing flow** | Caretaker enters Parent App Code → Parent accepts banner → Caretaker switches to Parent profile |
| **Post-repairing sync** | Parent push sync (8s) → Caretaker pull sync (8s) |
| **Verifications** | `LogoutMed7` (from TC-5) in Caretaker Medicine List |
| **Key behavior tested** | A fresh reinstall scenario does not retain stale pairings; re-pairing restores full data access |

---

## Complete Test Case Index

| # | Test Case | File | Covered Scenario |
|---|-----------|------|-----------------|
| 0 | Onboarding on Both Devices | `test_sync_only.py` | Fresh DB wipe → Onboarding completion |
| 0.1 | Parent Pre-Login Medicines | `test_sync_only.py` | Add & log doses before Google Sign-In (Parent) |
| 0.2 | Caretaker Pre-Login Medicines | `test_sync_only.py` | Add & log doses before Google Sign-In (Caretaker) |
| 0.5 | Google Sign-In Verification | `test_sync_only.py` | Sign-in success + App Code generation on both devices |
| 0.51 | Unique App Codes | `test_sync_only.py` | App Codes are different per device |
| 0.6 | Data Persistence After Sign-In | `test_sync_only.py` | Pre-login data survives Google Sign-In |
| 1 | Retrieve Parent App Code | `test_sync_only.py` | App Code readable from drawer |
| 2 | Caretaker Requests Pairing | `test_sync_only.py` | Pairing request via App Code |
| 2.5 | No Approval Banner on Caretaker | `test_sync_only.py` | Accept banner only shown on Parent |
| 2.6 | "Pending Approval" on Caretaker | `test_sync_only.py` | Correct pending state in Caretaker drawer |
| 2.7 | Pairing Banner Persists on Reopen | `test_sync_only.py` | Banner survives force-close + reopen |
| 3 | Parent Accepts Pairing | `test_sync_only.py` | Pairing finalized via banner |
| 3.5 | Parent Profile Active in Caretaker | `test_sync_only.py` | Post-acceptance profile menu state |
| 4 | Profile Switch on Caretaker | `test_sync_only.py` | Caretaker switches to Parent profile |
| 4.1 | Data Persistence After Pairing | `test_sync_only.py` | Pre-pairing data intact after pairing |
| 5 | Manual Sync: Parent → Caretaker | `test_sync_only.py` | Add + take dose → Sync Now → pull on Caretaker |
| 6 | Medicine List Verification | `test_sync_only.py` | Synced medicine visible in Caretaker's Medicine List |
| 7 | History Verification | `test_sync_only.py` | Synced dose status (Taken) visible in Caretaker's History |
| 8 | Sync Integrity (Interleaved Adds) | `test_sync_only.py` | Caretaker additions don't undo Parent's dose status |
| 9 | Parent Logout & Re-Login Sync | `test_sync_only.py` | App Code stability + post-relogin sync |
| TC-1 | Parent Offline → Auto-Sync on Reconnect | `test_sync_in_async_manner.py` | Offline add + mark taken → startup push sync |
| TC-2 | Caretaker Offline → Firebase Inbox | `test_sync_in_async_manner.py` | Parent uploads while Caretaker offline; Caretaker pulls on reconnect |
| TC-3 | Offline Manual Sync Graceful Handling | `test_sync_in_async_manner.py` | Offline "Sync Now" no-op + successful online sync |
| TC-4 | Caretaker Offline Add → Auto-Push on Reconnect | `test_sync_in_async_manner.py` | Caretaker offline write queued and auto-pushed |
| TC-5 | Logout → Offline Take → Re-Login → Sync | `test_sync_in_async_manner.py` | Logged-out doses sync post-login alongside new ones |
| TC-6 | Caretaker Logout → Re-Pairing → Data Sync | `test_sync_in_async_manner.py` | Logout removes pairing; re-pairing restores access |
| TC-7 | Storage Wipe → Re-Pairing → Data Sync | `test_sync_in_async_manner.py` | Full reinstall simulation; re-pairing restores access |

---

## Notes for Future Test Case Additions

- Add each new test case to the **Complete Test Case Index** table above.
- IDs `0.x` / `1–9` belong to **`test_sync_only.py`**. IDs `TC-N` belong to **`test_sync_in_async_manner.py`**.
- When adding offline scenarios, always restore internet in a `finally` block to prevent device state contamination between runs.
- All medicine names must include a Unix timestamp suffix to guarantee uniqueness across consecutive test runs.
- Any new profile-switching logic on the Caretaker must use `ensure_caretaker_on_parent_profile()` to avoid position-based tap fragility.
