#!/bin/bash
# ============================================================
# run_sync_only.sh
# SYNC ONLY test suite — tests two-device pairing and sync.
#
# Pre-requisites:
#   - Both devices have the app installed & are already
#     Google signed-in (pre-logged sessions required).
#   - Internet access is available on both devices.
#   - Do NOT wipe app data — session data must persist.
# ============================================================
set -e

EMULATOR_ID="${1:-emulator-5554}"
PHYSICAL_ID="${2:-51071JEBF16934}"
APP_PACKAGE="org.medimitra.family_medicine_tracker"
APP_ACTIVITY="$APP_PACKAGE.MainActivity"
DEBUG_APK="build/app/outputs/flutter-apk/app-debug.apk"

# ---------- Build Debug APK ----------
echo ""
echo "🛠️  Compiling Debug APK..."
flutter build apk --debug

if [ ! -f "$DEBUG_APK" ]; then
  echo "❌ Error: Debug APK not found at $DEBUG_APK"
  exit 1
fi


 echo "🛑 Force-stopping app..."
  adb -s "$EMULATOR_ID" shell am force-stop "$APP_PACKAGE" || true
  adb -s "$PHYSICAL_ID" shell am force-stop "$APP_PACKAGE" || true
  
  echo "🧹 Clearing app database and cache..."
  adb -s "$EMULATOR_ID" shell pm clear "$APP_PACKAGE" || true
  adb -s "$PHYSICAL_ID" shell pm clear "$APP_PACKAGE" || true


# ---------- Install Debug APK on connected devices ----------
echo ""
echo "📲 Installing Debug APK on devices..."

if adb devices | grep -q "$EMULATOR_ID"; then
  echo "📥 Installing debug APK on emulator ($EMULATOR_ID)..."
  adb -s "$EMULATOR_ID" install -r "$DEBUG_APK"
else
  echo "⚠️ Warning: Emulator device ($EMULATOR_ID) not detected by ADB."
fi

if adb devices | grep -q "$PHYSICAL_ID"; then
  echo "📥 Installing debug APK on physical device ($PHYSICAL_ID)..."
  adb -s "$PHYSICAL_ID" install -r "$DEBUG_APK"
else
  echo "⚠️ Warning: Physical device ($PHYSICAL_ID) not detected by ADB."
fi











# ---------- Stop apps before wiping database ----------
echo "🛑 Stopping app on emulator ($EMULATOR_ID)..."
adb -s "$EMULATOR_ID" shell am force-stop "$APP_PACKAGE" || true

echo "🛑 Stopping app on physical device ($PHYSICAL_ID)..."
adb -s "$PHYSICAL_ID" shell am force-stop "$APP_PACKAGE" || true

# ---------- Wipe database files (preserves Google login sessions) ----------
echo "🧹 Wiping SQLite database on emulator ($EMULATOR_ID)..."
adb -s "$EMULATOR_ID" shell run-as "$APP_PACKAGE" rm -f databases/medicine_tracker.db databases/medicine_tracker.db-journal databases/medicine_tracker.db-wal databases/medicine_tracker.db-shm || true

echo "🧹 Wiping SQLite database on physical device ($PHYSICAL_ID)..."
adb -s "$PHYSICAL_ID" shell run-as "$APP_PACKAGE" rm -f databases/medicine_tracker.db databases/medicine_tracker.db-journal databases/medicine_tracker.db-wal databases/medicine_tracker.db-shm || true


# ---------- Enable accessibility & grant permissions ----------
echo "♿ Enabling accessibility semantics..."
adb -s "$EMULATOR_ID" shell settings put secure accessibility_enabled 1 || true
adb -s "$PHYSICAL_ID" shell settings put secure accessibility_enabled 1 || true

echo "🔔 Granting notification permission..."
adb -s "$EMULATOR_ID" shell pm grant "$APP_PACKAGE" android.permission.POST_NOTIFICATIONS || true
adb -s "$PHYSICAL_ID" shell pm grant "$APP_PACKAGE" android.permission.POST_NOTIFICATIONS || true

echo "⏰ Granting exact alarm permission..."
adb -s "$EMULATOR_ID" shell appops set "$APP_PACKAGE" SCHEDULE_EXACT_ALARM allow || true
adb -s "$PHYSICAL_ID" shell appops set "$APP_PACKAGE" SCHEDULE_EXACT_ALARM allow || true

# ---------- Launch app on both devices ----------
echo ""
echo "🚀 Launching app on emulator ($EMULATOR_ID)..."
adb -s "$EMULATOR_ID" shell am start -S -n "$APP_PACKAGE/$APP_ACTIVITY"

echo "🚀 Launching app on physical device ($PHYSICAL_ID)..."
adb -s "$PHYSICAL_ID" shell am start -S -n "$APP_PACKAGE/$APP_ACTIVITY"

echo "⏳ Waiting 10s for both apps to fully render..."
sleep 10

# ---------- Run sync test ----------
echo ""
echo "🤖 Running sync-only test suite..."
cd AutomatedTest/sync_test
python3 -u test_sync_only.py --emulator "$EMULATOR_ID" --physical "$PHYSICAL_ID"
cd ../..

echo ""
echo "✅ ALL SYNC TEST SUITES COMPLETED SUCCESSFULLY!"
