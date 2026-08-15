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
PHYSICAL_ID="${2:-emulator-5556}"
APP_PACKAGE="org.medimitra.family_medicine_tracker"
APP_ACTIVITY="$APP_PACKAGE.MainActivity"
DEBUG_APK="../../build/app/outputs/flutter-apk/app-debug.apk"

# ---------- Build Debug APK ----------
echo ""
echo "🛠️  Compiling Debug APK..."
flutter build apk --debug

if [ ! -f "$DEBUG_APK" ]; then
  echo "❌ Error: Debug APK not found at $DEBUG_APK"
  exit 1
fi

# ---------- Force-stop & clear all app data (parallel) ----------
echo ""
echo "🛑 Force-stopping app on both devices (parallel)..."
adb -s "$EMULATOR_ID" shell am force-stop "$APP_PACKAGE" &
adb -s "$PHYSICAL_ID" shell am force-stop "$APP_PACKAGE" &
wait

echo "🧹 Clearing app data on both devices (parallel)..."
adb -s "$EMULATOR_ID" shell pm clear "$APP_PACKAGE" &
adb -s "$PHYSICAL_ID" shell pm clear "$APP_PACKAGE" &
wait

# ---------- Install Debug APK on connected devices (parallel) ----------
echo ""
echo "📲 Installing Debug APK on devices (parallel)..."

INSTALL_PIDS=()

if adb devices | grep -q "$EMULATOR_ID"; then
  echo "📥 Installing debug APK on emulator ($EMULATOR_ID)..."
  adb -s "$EMULATOR_ID" install -r "$DEBUG_APK" &
  INSTALL_PIDS+=($!)
else
  echo "⚠️ Warning: Emulator device ($EMULATOR_ID) not detected by ADB."
fi

if adb devices | grep -q "$PHYSICAL_ID"; then
  echo "📥 Installing debug APK on physical device ($PHYSICAL_ID)..."
  adb -s "$PHYSICAL_ID" install -r "$DEBUG_APK" &
  INSTALL_PIDS+=($!)
else
  echo "⚠️ Warning: Physical device ($PHYSICAL_ID) not detected by ADB."
fi

# Wait for all installs to complete
for pid in "${INSTALL_PIDS[@]}"; do
  wait "$pid"
done
echo "✅ APK installation complete on all detected devices."

# NOTE: No second force-stop or DB wipe needed here.
# 'pm clear' above already wiped all app data (including SQLite DB) and
# stopped the app. The DB directory doesn't exist again until the app
# runs for the first time after install, so 'run-as rm' would be a no-op.

# ---------- Enable accessibility & grant permissions (parallel) ----------
echo ""
echo "♿ Enabling accessibility semantics (parallel)..."
adb -s "$EMULATOR_ID" shell settings put secure accessibility_enabled 1 &
adb -s "$PHYSICAL_ID" shell settings put secure accessibility_enabled 1 &
wait

echo "🔔 Granting notification permission (parallel)..."
adb -s "$EMULATOR_ID" shell pm grant "$APP_PACKAGE" android.permission.POST_NOTIFICATIONS &
adb -s "$PHYSICAL_ID" shell pm grant "$APP_PACKAGE" android.permission.POST_NOTIFICATIONS &
wait

echo "⏰ Granting exact alarm permission (parallel)..."
adb -s "$EMULATOR_ID" shell appops set "$APP_PACKAGE" SCHEDULE_EXACT_ALARM allow &
adb -s "$PHYSICAL_ID" shell appops set "$APP_PACKAGE" SCHEDULE_EXACT_ALARM allow &
wait

# ---------- Launch app on both devices (parallel) ----------
echo ""
echo "🚀 Launching app on both devices (parallel)..."
adb -s "$EMULATOR_ID" shell am start -S -n "$APP_PACKAGE/$APP_ACTIVITY" &
adb -s "$PHYSICAL_ID" shell am start -S -n "$APP_PACKAGE/$APP_ACTIVITY" &
wait

echo "⏳ Waiting 8s for both apps to fully render..."
sleep 8

# ---------- Run sync test ----------
echo ""
echo "🤖 Running sync-only test suite..."
cd ../../AutomatedTest/sync_test
python3 -u test_sync_only.py --emulator "$EMULATOR_ID" --physical "$PHYSICAL_ID"
cd ../..

echo ""
echo "✅ ALL SYNC TEST SUITES COMPLETED SUCCESSFULLY!"
