# Medicine Tracker App V2 — Implementation Plan (Final)

## Overview

A cross-platform (iOS & Android) Flutter application that helps users track medication doses for themselves and family members. Offline-first with SQLite as local source of truth, Google Sheets (via Drive API) as the remote sync layer.

**Project:** `family_medicine_tracker` · **Org:** `org.medimitra`

### Home Screen Design Reference

📎 **Design reference:** [HomeScreen.png](file:///Users/rajshekhar/code/projects/MedicineTrackerAppV2/screenImages/HomeScreen.png) — click to view the home screen mockup

**Design language extracted from the reference — apply across all screens:**

| Element | Value |
|---|---|
| Primary color | Soft lavender/lilac `~#C9A0DC` |
| Background | Light pink/blush `~#FDF0F5` |
| Card / container fill | Pale lavender `~#E8D5F5` |
| Accent (FAB, selected date) | Medium purple `~#9B6DB0` |
| Text primary | Dark charcoal `~#2D2D2D` |
| Text secondary | Muted grey `~#8E8E93` |
| Corner radius | Large (16–20dp cards, fully rounded FAB & date circle) |
| Typography | Clean sans-serif (Inter or Poppins), generous line height |
| Spacing | Generous whitespace — relaxed, breathable layout |
| Shadows | Subtle, low-elevation shadows on cards |
| Icons | Thin-stroke, minimal style |

---

## All Decisions Resolved

| Item | Decision |
|---|---|
| Org / Project name | `org.medimitra` / `family_medicine_tracker` |
| Remote backend | Google Sheets via Google Drive API (not Firestore) |
| Authentication | Firebase Auth for login only |
| `medTypeUnits` config | Firebase Remote Config with hardcoded fallback |
| ID format | UUIDs — same UUID used in both SQLite and Google Sheets |
| Table strategy | Single set of tables with `profile_id` FK (not dynamic tables per profile) |
| Edit medication | Supported from Medicines List Screen |
| Dose statuses | "Taken" or "Skipped"; auto-skip after configurable grace period |
| Notifications | Remind at exact scheduled dose time; sound on/off toggle; no snooze |
| Family viewer | Can view log + view/update medicine list; **cannot** mark taken/skipped |
| View History | Weekly strip + calendar picker, two views: by date / by medicine |
| Profile schema | `ProfileId, ProfileName, TimeZone, LastSync, CreatedAt, AvatarUrl` |

---

## Sync Strategy — Two Directions

Per Section 6.2, there are exactly **two sync directions**, each with distinct triggers and scope:

### Sync Type 1: Local → Cloud (Own Profile) — Event-Driven

- **What syncs:** The logged-in user's own data — medicines, schedules, medicine log entries
- **Trigger model:** Every local write immediately triggers a sync attempt. No polling or periodic timers.

| Trigger Event | Flow |
|---|---|
| **Add medication** (save button) | Insert into SQLite with `is_dirty = 1` → immediately attempt sync push |
| **Edit medication** (save button) | Update SQLite rows, set `is_dirty = 1` → immediately attempt sync push |
| **Take dose** (tap/swipe) | Insert "taken" log with `is_dirty = 1` → immediately attempt sync push |
| **Skip dose** (tap/swipe) | Insert "skipped" log with `is_dirty = 1` → immediately attempt sync push |
| **Auto-skip** (in-app grace period timer) | While app is in foreground, a timer monitors scheduled doses. When `scheduled_time + grace_period` elapses with no action → insert "skipped" log with `is_dirty = 1` → immediately attempt sync push |

- **Offline behavior:** If the device is offline, the local write still succeeds (SQLite is source of truth). The `is_dirty` flag stays `1`. Dirty rows accumulate until the app resume flow (below) flushes them.

### Sync Type 2: Cloud → Local (Family Members)

- **What syncs:** Family members' data — their medicines, schedules, and medicine log
- **When it triggers:**
  - First login with Google account (full sync of all family profiles)
  - Subsequent app resumes (delta sync — only changed data based on timestamps)
- **How it works:** List all spreadsheets in the `MedicineTrackerApp` Drive folder. Each spreadsheet = one family profile. Read their sheets and upsert into local SQLite with the family member's `profile_id` (where `is_owner = 0`).
- **No bidirectional conflict risk:** Own profile only pushes up; family profiles only pull down. The viewer can update a family member's medicines/schedules, but those updates write directly to the family member's Google Sheet (not to local first) — this avoids the same field being written in both directions.

### App Resume Flow (3-step sequence)

When the app returns to the foreground (or comes back online), the following steps execute in order:

```
App Resume / Connectivity Restored
        │
        ▼
┌─────────────────────────────────────────────────┐
│ Step 1: RETROACTIVE AUTO-SKIP                    │
│                                                  │
│ Scan all scheduled doses where:                  │
│   scheduled_time + grace_period < now            │
│   AND no log entry exists for that dose/date     │
│                                                  │
│ → Auto-create "skipped" log entries              │
│ → Set is_dirty = 1 on each                       │
└─────────────────────┬───────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────┐
│ Step 2: FLUSH DIRTY ROWS (Sync Type 1)           │
│                                                  │
│ Read ALL is_dirty = 1 rows (including the        │
│ skips just created in Step 1, plus any that       │
│ accumulated while offline)                        │
│                                                  │
│ → Batch push to own Google Spreadsheet            │
│ → Clear is_dirty = 0 on success                  │
└─────────────────────┬───────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────┐
│ Step 3: PULL FAMILY DATA (Sync Type 2)           │
│                                                  │
│ Delta sync family profiles from Google Drive     │
│ → Upsert into local SQLite (is_owner = 0)        │
└─────────────────────────────────────────────────┘
```

> [!NOTE]
> **No background timer while app is inactive.** Auto-skip detection happens retroactively on app resume (Step 1), so there's no need for persistent background services. While the app is in the foreground, an in-app timer monitors upcoming grace periods in real time.

```
┌────────────────┐         ┌───────────────────────┐
│   Local SQLite  │         │   Google Drive         │
│                 │         │   MedicineTrackerApp/  │
│  Own profile    │──push──▶│     RajShekhar.gsheet  │
│  (is_owner=1)   │  event  │                        │
│                 │ driven  │     Nana.gsheet         │
│  Family profiles│◀──pull──│     Brother.gsheet      │
│  (is_owner=0)   │  on     │                        │
│                 │ resume  │                        │
└────────────────┘         └───────────────────────┘
```

> [!NOTE]
> **Why no `remote_row_ref` column?** You correctly pointed out that since we generate UUIDs locally and write the same UUID to the Google Sheet's ID column (MedicineID, ScheduleID, LogID), the local primary key **is** the remote key. No separate mapping column needed. The `is_dirty` flag is sufficient to track "has this row been pushed yet?"

---

## Architecture

Clean Architecture per AGENTS.md, with a **pluggable remote datasource** layer for future backend migration:

```
lib/
├── core/
│   ├── constants/          # App constants, route names, asset paths
│   ├── errors/             # Failure types (LocalFailure, RemoteFailure, AuthFailure)
│   ├── theme/              # Lavender/lilac theme, typography, color tokens
│   ├── utils/              # Date/time UTC helpers, formatters, validators, clock provider
│   ├── di/                 # Riverpod provider overrides, service locator
│   ├── sync/               # SyncService, remote datasource interface, sync providers
│   └── notifications/      # Local notification service
│
├── features/
│   ├── onboarding/         # First-time launch / profile creation
│   ├── home/               # Home screen (header, date strip, medication list)
│   ├── medications/        # Add/Edit medication, medicines list
│   ├── history/            # View history by date / by medicine
│   ├── profiles/           # Profile management, family profiles, profile menu
│   ├── auth/               # Google OAuth, Firebase Auth, Drive access
│   └── settings/           # Notifications, account, app info
│
├── app.dart                # MaterialApp, routing, top-level providers
└── main.dart               # Bootstrap: Firebase Auth init, DB open, runApp
```

### Pluggable Remote Datasource

Every feature's remote datasource is behind an abstract interface. Swapping Google Sheets for a custom backend requires only:
1. A new class implementing `RemoteDataSource`
2. Changing one Riverpod provider override

```dart
// Abstract contract — domain/data boundary
abstract class RemoteDataSource {
  Future<void> ensureRemoteStructure(String profileName);
  Future<List<Map<String, dynamic>>> readSheet(String profileName, String sheetTab);
  Future<void> writeRows(String profileName, String sheetTab, List<Map<String, dynamic>> rows);
  Future<List<String>> listRemoteProfiles();
}

// Current: Google Sheets
class GoogleSheetsRemoteDataSource implements RemoteDataSource { ... }

// Future: Custom API
// class ApiRemoteDataSource implements RemoteDataSource { ... }
```

---

## Data Model

### Local SQLite Tables

All tables scoped by `profile_id`. Sync metadata: `updated_at` (UTC millis), `is_dirty` (0/1).

#### `profiles`
| Column | Type | Notes |
|---|---|---|
| `id` | TEXT (PK) | UUID |
| `profile_name` | TEXT (UNIQUE) | |
| `time_zone` | TEXT | IANA timezone string (e.g., `Asia/Kolkata`) |
| `avatar_url` | TEXT | Nullable |
| `created_at` | INTEGER | UTC epoch millis |
| `last_sync` | INTEGER | Nullable — UTC epoch millis of last successful sync |
| `is_owner` | INTEGER | `1` = local user's profile, `0` = family member pulled from Drive |
| `updated_at` | INTEGER | UTC epoch millis |
| `is_dirty` | INTEGER | 0/1 — `1` = has local changes not yet pushed to Google Sheet |

#### `medicines`
| Column | Type | Notes |
|---|---|---|
| `id` | TEXT (PK) | UUID (same value used in Google Sheet `MedicineID` column) |
| `profile_id` | TEXT (FK → profiles) | Scopes all queries |
| `name` | TEXT | Medicine name |
| `type` | TEXT | `tablet`, `capsule`, `syrup`, `powder`, `cream`, `injection` |
| `dosage_value` | REAL | Nullable (e.g., `7.5`) |
| `dosage_unit` | TEXT | Nullable (`mg`, `mcg`, `g`, `ml`) |
| `quantity_value` | REAL | Nullable (e.g., `1`) |
| `quantity_unit` | TEXT | Nullable (`tab`, `cap`, etc.) |
| `frequency` | TEXT | Descriptive label: `"once_a_day"`, `"2_times_daily"`, `"once_a_week"`, `"3_times_monthly"`, etc. The actual number of doses is the count of rows in the `schedules` table for this medicine. |
| `start_date` | INTEGER | UTC epoch millis |
| `end_date` | INTEGER | Nullable — `null` means "Continuous" |
| `notes` | TEXT | Nullable |
| `active` | INTEGER | 0/1 |
| `updated_at` | INTEGER | UTC epoch millis |
| `is_dirty` | INTEGER | 0/1 |

> [!NOTE]
> **Single `frequency` column.** No separate `frequency_count` — the number of daily/weekly/monthly doses is already represented by the count of schedule rows for that medicine. The `frequency` string is for display ("Daily", "3 times, Daily") and for driving the Add/Edit form (how many time-slot pickers to show).

#### `schedules`
| Column | Type | Notes |
|---|---|---|
| `id` | TEXT (PK) | UUID (same as Google Sheet `ScheduleID`) |
| `profile_id` | TEXT (FK → profiles) | |
| `medicine_id` | TEXT (FK → medicines) | |
| `time` | TEXT | `HH:mm` 24-hour format (e.g., `"10:00"`, `"14:00"`) |
| `updated_at` | INTEGER | UTC epoch millis |
| `is_dirty` | INTEGER | 0/1 |

#### `medicine_log`
| Column | Type | Notes |
|---|---|---|
| `id` | TEXT (PK) | UUID (same as Google Sheet `LogID`) |
| `profile_id` | TEXT (FK → profiles) | |
| `schedule_id` | TEXT (FK → schedules) | |
| `date` | TEXT | `yyyy-MM-dd` (UTC date) |
| `status` | TEXT | `"taken"` or `"skipped"` |
| `taken_at` | INTEGER | Nullable — UTC epoch millis, set only when status = `"taken"` |
| `updated_at` | INTEGER | UTC epoch millis |
| `is_dirty` | INTEGER | 0/1 |

#### `settings` (local-only, not synced)
| Column | Type | Notes |
|---|---|---|
| `id` | TEXT (PK) | UUID |
| `profile_id` | TEXT (FK → profiles) | |
| `reminder_enabled` | INTEGER | 0/1 — whether to send notification at scheduled dose time |
| `reminder_sound_enabled` | INTEGER | 0/1 — on/off toggle for notification sound |
| `grace_period_minutes` | INTEGER | After this many minutes past dose time, auto-mark as "Skipped" (default: 60) |

### Remote: Google Sheets Schema

Each profile → one Google Spreadsheet in `MedicineTrackerApp/` folder on Google Drive.

| Sheet Tab | Maps to SQLite Table | Columns (per Section 7) |
|---|---|---|
| `Medicines` | `medicines` | MedicineID, Name, Type, Dosage, Quantity, Frequency, Start Date, End Date, Notes, Active |
| `Schedule` | `schedules` | ScheduleID, MedicineID, Time |
| `MedicineLog` | `medicine_log` | LogID, Date, ScheduleID, Status, Taken At |
| `Profile` | `profiles` | ProfileId, ProfileName, TimeZone, LastSync |

---

## Proposed Changes — Phased Implementation

### Phase 1: Project Scaffolding & Core

> Flutter project, theme, navigation, core utilities, SQLite setup.

#### [NEW] Flutter project
```bash
flutter create --org org.medimitra --project-name family_medicine_tracker ./
```

#### Key Dependencies
| Package | Purpose |
|---|---|
| `flutter_riverpod` | State management |
| `sqflite` | SQLite |
| `path_provider` | DB file paths |
| `go_router` | Routing |
| `freezed` + `freezed_annotation` | Immutable models |
| `json_annotation` + `json_serializable` | Serialization |
| `firebase_core` | Firebase init |
| `firebase_auth` | Google OAuth |
| `firebase_remote_config` | `medTypeUnits` config |
| `google_sign_in` | Google Sign-In |
| `googleapis` + `googleapis_auth` | Drive & Sheets API |
| `dartz` | `Either<Failure, T>` |
| `intl` | Date/time formatting |
| `uuid` | ID generation |
| `flutter_local_notifications` | Dose reminders |
| `timezone` | Timezone-aware scheduling |
| `mocktail` | Testing |

#### [NEW] `lib/core/theme/app_colors.dart`
- Lavender/lilac palette: primary `~#C9A0DC`, background `~#FDF0F5`, card `~#E8D5F5`, accent purple `~#7C4DFF`

#### [NEW] `lib/core/theme/app_text_styles.dart`
- Typography scale (Inter or Poppins via Google Fonts)

#### [NEW] `lib/core/theme/app_theme.dart`
- `ThemeData` composing colors + typography

#### [NEW] `lib/core/constants/app_constants.dart`
- Route names, table names, asset paths, frequency string values

#### [NEW] `lib/core/errors/failures.dart`
- Sealed `Failure`: `LocalFailure`, `RemoteFailure`, `AuthFailure`, `SyncFailure`

#### [NEW] `lib/core/utils/date_time_utils.dart`
- UTC ↔ timezone conversion; injected clock; no `DateTime.now()` in domain/data

#### [NEW] `lib/core/utils/db_helper.dart`
- SQLite init, CREATE TABLE DDL for all 5 tables, version migrations

#### [NEW] `lib/app.dart`
- `MaterialApp.router` + `GoRouter` routes + `ProviderScope`

#### [NEW] `lib/main.dart`
- `Firebase.initializeApp()`, open SQLite DB, `runApp()`

---

### Phase 2: Onboarding Feature

> First-launch: create profile → save to SQLite → navigate to Home.

#### Domain
- [NEW] `lib/features/onboarding/domain/entities/profile.dart` — immutable `Profile`
- [NEW] `lib/features/onboarding/domain/repositories/onboarding_repository.dart` — `createProfile()`
- [NEW] `lib/features/onboarding/domain/usecases/create_profile.dart`

#### Data
- [NEW] `lib/features/onboarding/data/models/profile_model.dart` — `fromMap`/`toMap`
- [NEW] `lib/features/onboarding/data/datasources/onboarding_local_datasource.dart` — SQLite INSERT
- [NEW] `lib/features/onboarding/data/repositories/onboarding_repository_impl.dart`

#### Presentation
- [NEW] `lib/features/onboarding/presentation/screens/onboarding_screen.dart` — logo, tagline, name input, timezone selector, Save
- [NEW] `lib/features/onboarding/presentation/providers/onboarding_provider.dart` — form state + save action

---

### Phase 3: Home Screen Feature

> Header, weekly date strip, time-grouped medication list, take/skip, FAB.

#### Domain
- [NEW] `lib/features/home/domain/entities/scheduled_dose.dart` — medicine + schedule + log status for a date
- [NEW] `lib/features/home/domain/repositories/home_repository.dart` — `getScheduledDosesForDate(profileId, date)`
- [NEW] `lib/features/home/domain/usecases/get_scheduled_doses.dart` — groups by time
- [NEW] `lib/features/home/domain/usecases/mark_dose_taken.dart` — status = "taken", taken_at = now
- [NEW] `lib/features/home/domain/usecases/mark_dose_skipped.dart` — status = "skipped"

#### Data
- [NEW] `lib/features/home/data/datasources/home_local_datasource.dart` — SQL JOIN medicines + schedules + LEFT JOIN medicine_log
- [NEW] `lib/features/home/data/models/scheduled_dose_model.dart`
- [NEW] `lib/features/home/data/repositories/home_repository_impl.dart`

#### Presentation
- [NEW] `lib/features/home/presentation/screens/home_screen.dart` — scaffold
- [NEW] `lib/features/home/presentation/widgets/home_header.dart` — profile icon, dynamic title, calendar icon
- [NEW] `lib/features/home/presentation/widgets/weekly_date_strip.dart` — Sun–Sat, purple circle selection
- [NEW] `lib/features/home/presentation/widgets/medication_time_group.dart` — time header + card list
- [NEW] `lib/features/home/presentation/widgets/medication_card.dart` — skip/take buttons, swipe gestures, type icon, name+dosage, frequency, quantity
- [NEW] `lib/features/home/presentation/widgets/empty_state.dart` — illustration + "No medications for today"
- [NEW] `lib/features/home/presentation/widgets/full_calendar_dialog.dart` — calendar picker → recenters weekly strip
- [NEW] `lib/features/home/presentation/providers/home_provider.dart` — selected date, scheduled doses, take/skip actions

---

### Phase 4: Add/Edit Medication + Medicines List

> Medication form with type→unit mapping, frequency→time slots, duration. Medicines list with edit.

#### Domain
- [NEW] `lib/features/medications/domain/entities/medicine.dart`
- [NEW] `lib/features/medications/domain/entities/schedule.dart`
- [NEW] `lib/features/medications/domain/entities/med_type_config.dart` — type→unit mapping
- [NEW] `lib/features/medications/domain/repositories/medication_repository.dart` — `addMedication`, `updateMedication`, `getAllMedications`, `getMedTypeConfig`
- [NEW] `lib/features/medications/domain/usecases/add_medication.dart`
- [NEW] `lib/features/medications/domain/usecases/update_medication.dart`
- [NEW] `lib/features/medications/domain/usecases/get_all_medications.dart`
- [NEW] `lib/features/medications/domain/usecases/get_med_type_config.dart` — Remote Config + fallback

#### Data
- [NEW] `lib/features/medications/data/datasources/medication_local_datasource.dart` — SQLite CRUD (transactional)
- [NEW] `lib/features/medications/data/datasources/medication_remote_datasource.dart` — abstract interface (pluggable)
- [NEW] `lib/features/medications/data/datasources/google_sheets_medication_remote_datasource.dart` — Sheets API impl
- [NEW] `lib/features/medications/data/datasources/medication_remote_config_datasource.dart` — Firebase Remote Config
- [NEW] `lib/features/medications/data/models/medicine_model.dart` — `fromMap`/`toMap` + `fromSheetRow`/`toSheetRow`
- [NEW] `lib/features/medications/data/models/schedule_model.dart`
- [NEW] `lib/features/medications/data/repositories/medication_repository_impl.dart`

#### Presentation
- [NEW] `lib/features/medications/presentation/screens/add_medication_screen.dart` — form (name, type picker, dosage, quantity, frequency, time slots, start/end date, save)
- [NEW] `lib/features/medications/presentation/screens/medicines_list_screen.dart` — active + inactive, tap to edit, profile-scoped
- [NEW] `lib/features/medications/presentation/widgets/type_selector.dart` — visual grid of type icons
- [NEW] `lib/features/medications/presentation/widgets/frequency_selector.dart` — all frequency options from Section 3.4; "X times" shows number input
- [NEW] `lib/features/medications/presentation/widgets/time_slot_picker.dart` — dynamic count driven by frequency
- [NEW] `lib/features/medications/presentation/providers/add_medication_provider.dart`
- [NEW] `lib/features/medications/presentation/providers/medicines_list_provider.dart`

---

### Phase 5: Settings Feature

> Notification prefs, account, app info.

#### Domain
- [NEW] `lib/features/settings/domain/entities/app_settings.dart` — reminder enabled, sound toggle, grace period
- [NEW] `lib/features/settings/domain/repositories/settings_repository.dart`
- [NEW] `lib/features/settings/domain/usecases/get_settings.dart`
- [NEW] `lib/features/settings/domain/usecases/update_settings.dart`

#### Data
- [NEW] `lib/features/settings/data/datasources/settings_local_datasource.dart` — SQLite CRUD (local-only, not synced)
- [NEW] `lib/features/settings/data/repositories/settings_repository_impl.dart`

#### Presentation
- [NEW] `lib/features/settings/presentation/screens/settings_screen.dart`
  - **Notifications**: Reminder on/off, sound on/off
  - **Account**: Sign Out
  - **Application**: App version, Privacy Policy
- [NEW] `lib/features/settings/presentation/providers/settings_provider.dart`

#### Notifications & Auto-Skip Service
- [NEW] `lib/core/notifications/notification_service.dart`
  - `flutter_local_notifications` setup
  - Schedule a notification at each dose's exact scheduled time
  - Sound on/off per settings
  - Reschedule on medication add/edit/delete
- [NEW] `lib/core/notifications/auto_skip_service.dart`
  - **In-app timer (foreground):** While app is active, monitors scheduled doses. When `scheduled_time + grace_period` passes with no action → auto-create "skipped" log with `is_dirty = 1` → trigger sync push
  - **Retroactive check (app resume):** On resume, scans all past doses with no log entry where grace period has elapsed → batch-creates "skipped" entries — this is Step 1 of the App Resume Flow

---

### Phase 6: Profile Menu, History & Family Profile UI

#### Profile Menu
- [NEW] `lib/features/profiles/presentation/widgets/profile_menu.dart`
  - Profile name (label)
  - MedicineList → Medicines List Screen
  - ViewHistory → History Screen
  - --- Track Family members --- (divider)
  - Login (pre-auth) / family profile entries (post-auth)
    - Each family profile expandable with sub-menus: Medicine log, Medicine schedule, List of medicines
  - Settings → Settings Screen

#### View History
- [NEW] `lib/features/history/domain/entities/history_entry.dart`
- [NEW] `lib/features/history/domain/repositories/history_repository.dart` — `getHistoryByDate`, `getHistoryByMedicine`
- [NEW] `lib/features/history/domain/usecases/get_history_by_date.dart`
- [NEW] `lib/features/history/domain/usecases/get_history_by_medicine.dart`
- [NEW] `lib/features/history/data/datasources/history_local_datasource.dart`
- [NEW] `lib/features/history/data/repositories/history_repository_impl.dart`
- [NEW] `lib/features/history/presentation/screens/history_screen.dart`
  - Weekly date strip + calendar picker (reusable from Home Screen)
  - Two views: "By Date" (select date → see all entries) / "By Medicine" (select medicine → see all entries)
- [NEW] `lib/features/history/presentation/providers/history_provider.dart`

#### Family Profile Screen
- [NEW] `lib/features/profiles/presentation/screens/family_profile_screen.dart`
  - Reuses Medicines List / History / Schedule screens with family `profileId`
  - Can view/edit medicines and schedules; **read-only** for medicine log (no take/skip)

---

### Phase 7: Authentication & Google Drive Sync

> Firebase Auth + Google Drive folder/spreadsheet management + both sync directions.

#### Auth
- [NEW] `lib/features/auth/domain/entities/auth_user.dart`
- [NEW] `lib/features/auth/domain/repositories/auth_repository.dart` — `signInWithGoogle`, `signOut`, `getCurrentUser`
- [NEW] `lib/features/auth/domain/usecases/sign_in_with_google.dart`
- [NEW] `lib/features/auth/domain/usecases/sign_out.dart`
- [NEW] `lib/features/auth/data/datasources/auth_remote_datasource.dart` — Firebase Auth + Google Sign-In with Drive scope
- [NEW] `lib/features/auth/data/repositories/auth_repository_impl.dart`

#### Remote Datasource (Pluggable)
- [NEW] `lib/core/sync/remote_datasource.dart` — abstract `RemoteDataSource` interface
- [NEW] `lib/core/sync/google_sheets_remote_datasource.dart` — concrete Google Sheets implementation
  - Creates `MedicineTrackerApp/` folder on Drive if not exists
  - Creates profile spreadsheet (named after profile) with 4 tabs if not exists
  - CRUD via Sheets API

#### Sync Service
- [NEW] `lib/core/sync/sync_service.dart`
  - **`pushDirtyRows()`** — Sync Type 1: reads all `is_dirty = 1` rows for own profile → batch writes to own spreadsheet → clears dirty flag on success
  - **`pullFamilyData()`** — Sync Type 2: lists family spreadsheets in Drive folder → reads their sheets → upserts into SQLite with `is_owner = 0`
  - **`onAppResume()`** — orchestrates the 3-step App Resume Flow:
    1. Call `AutoSkipService.retroactiveCheck()` → creates missing "skipped" entries
    2. Call `pushDirtyRows()` → flushes all accumulated dirty rows (including new skips)
    3. Call `pullFamilyData()` → delta sync family profiles
  - **Event-driven push:** called immediately after every local write (add/edit medicine, take/skip dose)
- [NEW] `lib/core/sync/sync_provider.dart` — sync status state (idle/syncing/error/last sync time), exposes `onAppResume()` to app lifecycle listener

#### Family Profile Discovery
- [NEW] `lib/features/profiles/domain/usecases/get_family_profiles.dart` — lists spreadsheets in Drive folder
- [NEW] `lib/features/profiles/domain/usecases/sync_family_profile.dart` — full sync on first login, delta sync after

---

## Assumptions

1. **Single set of tables with `profile_id` FK** — confirmed, no dynamic tables per profile.
2. **UUIDs** serve as PK in both SQLite and Google Sheets — no separate `remote_row_ref`.
3. **Single `frequency` column** — schedule row count determines actual dose count.
4. **Firebase Remote Config** for `medTypeUnits` with hardcoded fallback.
5. **Notifications at exact scheduled dose time** — not an offset before.
6. **No snooze** in initial scope.
7. **Auto-skip** after configurable grace period (creates a "skipped" log entry and marks `is_dirty`).
8. **No hard delete** — deactivate via `active = 0`. (Can revisit if needed.)
9. **All timestamps UTC** in SQLite and Sheets; presentation converts to profile timezone.
10. **Family viewer updates** to medicines/schedules write directly to that family member's Google Sheet.

---

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Google Sheets API rate limits | Batch operations, exponential backoff, dirty-row queue |
| Google Drive scope OAuth consent review | Apply early; restricted scopes; clear justification |
| Family profile sync conflicts | Own profile push-only, family profiles pull-only — no bidirectional conflict on same data |
| `medTypeUnits` unavailable | Hardcoded fallback config |
| Sheets scalability (~10M cells) | Acceptable for personal/family; archive old logs if needed |
| Future backend migration | Pluggable `RemoteDataSource` — one provider swap |

---

## Verification Plan

### Automated Tests
```bash
flutter test test/features/*/domain/    # Domain unit tests
flutter test test/features/*/data/      # Data layer (in-memory SQLite, mocked remote)
flutter test test/features/*/presentation/  # Widget tests
flutter test                            # All tests
```

### Manual Verification
1. **Onboarding** → create profile → home screen
2. **Add medication** → type auto-fills units → frequency drives time slot count → save → appears grouped by time
3. **Take/Skip** → log entry created → card state updates → `is_dirty` set
4. **Date navigation** → weekly strip + calendar → medications refresh
5. **Medicines List** → active + inactive → tap to edit → changes reflected
6. **History** → by date (strip + calendar) / by medicine (select + view entries)
7. **Settings** → notification toggle → reminders fire at dose time / sound on/off
8. **Auto-skip** → configured grace period expires → "skipped" log entry created
9. **Login** → Drive folder + spreadsheet created → own data syncs up
10. **Family sync** → family profiles pulled down → appear in menu → view their data
11. **Offline** → add/take/skip offline → come online → sync completes
12. **Pluggable backend** → mock `RemoteDataSource` works with same repository

---

## Implementation Order

| Phase | Scope | Size |
|---|---|---|
| **1** | Project scaffolding, core, theme, DB, routing | Foundation |
| **2** | Onboarding (profile creation) | Small |
| **3** | Home screen (date strip, medication list, take/skip) | Large |
| **4** | Add/Edit Medication + Medicines List | Medium–Large |
| **5** | Settings (notifications, account, app info) | Medium |
| **6** | Profile menu, View History, family profile UI | Medium |
| **7** | Auth, Google Drive/Sheets sync, family discovery | Large |

**Phases 1–5** = fully functional offline app with notifications.
**Phases 6–7** = cloud sync + family monitoring.
