# Family Medicine Tracker (MediMitra)

A cross-platform Flutter application for tracking family medication schedules, built using a clean offline-first architecture with SQLite on-device storage and background Google Drive/Sheets synchronization.

---

## Getting Started

### 1. Prerequisites
Ensure you have the Flutter SDK installed and configured on your path.

### 2. Fetch Dependencies
Install all cached packages from pub.dev:
```bash
flutter pub get
```

### 3. Compilation & Execution Commands
You can compile and run the application on any active simulator, connected device, or desktop platform:

#### Debug Mode (Development)
* **List available devices:**
  ```bash
  flutter devices
  ```
* **Run on Web (Chrome):**
  ```bash
  flutter run -d chrome
  ```
* **Run on macOS Desktop:**
  ```bash
  flutter run -d macos
  ```
* **Run on iOS Simulator:**
  Ensure an iOS Simulator is open, then run:
  ```bash
  flutter run -d ios
  ```
* **Run on Android Emulator:**
  Ensure an Android Emulator is running, then run:
  ```bash
  flutter run -d android
  ```

#### Release Mode Compilation (Production)
* **Build Web application bundle:**
  ```bash
  flutter build web --release
  ```
* **Build macOS Desktop app bundle:**
  ```bash
  flutter build macos --release
  ```
* **Build iOS App Store bundle (IPA):**
  ```bash
  flutter build ipa --release
  ```
* **Build Android App Bundle (AAB) or APK:**
  ```bash
  flutter build appbundle --release
  flutter build apk --release
  ```

---

## Available Configuration Options

The application supports multiple run-time and compile-time configurations to fine-tune operations:

### 1. Dynamic Medication Types Configuration
Medicine types are loaded dynamically via **Firebase Remote Config** (with local fallback).
* Configurable categories (e.g. `Tablet`, `Capsule`, `Syrup`, `Cream`, `Injection`, etc.).
* Toggle input rows per type (`dosageEnabled: true/false`, `quantityEnabled: true/false`).
* Configure unit selection dropdown lists (e.g. `['mg', 'mcg', 'ml']` or `['tab', 'capsule']`).
* Layout automatically optimizes to place labels above fields, preventing cramped layout overflows.

### 2. Notifications & Alarm Preferences
Preferences are managed in the **Settings** panel per profile:
* **Dose Reminders Toggle:** Turn local push notifications on or off.
* **Notification Sounds:** Enable or disable custom alarm sounds for dose alerts.
* **Missed Dose Grace Period:** Configure a time window (`15`, `30`, `45`, or `60` minutes) after which any unlogged dose is marked `"skipped"` automatically.

### 3. Family Profile Access Controls
* **Owner Profile:** Possesses full read/write privileges (Add/Edit medications, log Taken/Skipped actions, link Google Drive).
* **Family Profiles:** Configured as read-only viewports (`isOwner: false`). Restricts all edit FABs, swipe logging controls, and data modifications.

### 4. Google Drive Spreadsheet Cloud Syncing
* **Google Sign-In Account Linkage:** Authenticate with Google Drive scopes (`drive.file`, `spreadsheets`).
* **Auto-generated Cloud Sheets:** Creates a spreadsheet named `FamilyMedicineTracker_V2` in the root of the user's Drive with dedicated tabs (`Profiles`, `Medicines`, `Schedules`, `MedicineLog`, `Settings`).
* **Last-Write-Wins Conflict Resolver:** Background checks determine sync status (`is_dirty`) and compare UTC timestamps during pulls to merge offline databases.

---

## Firebase & Google Sign-In Setup

To enable Firebase Authentication and Google Drive/Sheets Cloud Synchronization, follow these setup steps:

### 1. Register App in Firebase Console
1. Create a Firebase project in the [Firebase Console](https://console.firebase.google.com/).
2. Enable **Authentication** and activate the **Google** sign-in provider.
3. Configure the **OAuth Consent Screen** in the [Google Cloud Console](https://console.cloud.google.com/) for your project, ensuring the following scopes are enabled:
   * `email`
   * `https://www.googleapis.com/auth/spreadsheets`
   * `https://www.googleapis.com/auth/drive.file`

### 2. Platform Specific Configuration Files
* **Android:**
  * Download the `google-services.json` file from your Firebase project settings.
  * Place it in the `android/app/` folder.
* **iOS:**
  * Download the `GoogleService-Info.plist` file from your Firebase project settings.
  * Place it in the `ios/Runner/` folder (ensure it is added to your Xcode project resources).
  * Add the Google Sign-In URL scheme (reversed client ID found in `GoogleService-Info.plist`) to your `Info.plist` file under `<key>CFBundleURLTypes</key>` to register sign-in redirect callbacks.
* **Web:**
  * Run `flutterfire configure` using the FlutterFire CLI to automatically generate the platform credentials inside `lib/firebase_options.dart`.

*Note: If these files are not present, the app will gracefully run in **Offline/Sandbox Mode** using in-memory cloud simulations, preventing startup crashes.*

---

## Verifying Features (Phases 1-7 Checklist)

1. **Onboarding Screen:** Runs automatically on first startup to initialize the Owner Profile and timezone.
2. **Dashboard Calendar & Strip:** Weekly dates navigation strip + full calendar picker.
3. **Prescriptions CRUD Form:** Visual type grid selectors, custom frequencies (e.g. `3 times, Daily`), and staggered times pickers.
4. **Swipe Gestures:** Swipe cards right to record a dose as `"Taken"`, or swipe left to mark as `"Skipped"`.
5. **Adherence History Reports:** Two tabs: **By Date** checklists and **By Medicine** cumulative adherence percentage rates.
6. **Background Auto-Skip Checker:** Automatically updates missed schedules on app resume events.
7. **Cloud Backup Panel:** Google linking and manual cloud sync buttons inside the profile drawer.

---

## Testing

The project includes unit and widget tests to verify business logic and user flows:

* **Unit Tests:** Located in [date_time_utils_test.dart](file:///Users/rajshekhar/code/projects/MedicineTrackerAppV2/test/date_time_utils_test.dart) (verifies date conversions and 24-to-12 hour format strings conversion).
* **Widget Tests:** Located in [widget_test.dart](file:///Users/rajshekhar/code/projects/MedicineTrackerAppV2/test/widget_test.dart) (verifies initial app onboarding redirection and structure layout presence).

To execute the test suite, run:
```bash
flutter test
```
