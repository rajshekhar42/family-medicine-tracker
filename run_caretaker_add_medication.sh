#!/bin/bash
# ============================================================
# run_caretaker_add_medication.sh
# CARETAKER ADD MEDICATION test suite — tests caretaker adding parent medication.
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

echo "============================================================"
echo "🧪 CARETAKER ADD MEDICATION TEST SUITE"
echo "   Parent  (Emulator): $EMULATOR_ID"
echo "   Caretaker (Physical): $PHYSICAL_ID"
echo "   NOTE: Pre-logged sessions required. Database wiped for a fresh sync."
echo "============================================================"

# ---------- Wake up and unlock both devices ----------
echo "🔓 Waking up and unlocking emulator ($EMULATOR_ID)..."
adb -s "$EMULATOR_ID" shell input keyevent 224 || true
adb -s "$EMULATOR_ID" shell input keyevent 82 || true

echo "🔓 Waking up and unlocking physical device ($PHYSICAL_ID)..."
adb -s "$PHYSICAL_ID" shell input keyevent 224 || true
adb -s "$PHYSICAL_ID" shell input keyevent 82 || true

# ---------- Stop app on both devices ----------
echo ""
echo "🧹 Stopping apps on both devices..."
adb -s "$EMULATOR_ID" shell am force-stop "$APP_PACKAGE" || true
adb -s "$PHYSICAL_ID" shell am force-stop "$APP_PACKAGE" || true
adb -s "$PHYSICAL_ID" shell am force-stop "com.truecaller" || true
adb -s "$EMULATOR_ID" shell am force-stop "com.google.android.googlequicksearchbox" || true
adb -s "$PHYSICAL_ID" shell am force-stop "com.google.android.googlequicksearchbox" || true
sleep 2

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
echo "🤖 Running caretaker add medication test..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
python3 -u test_caretaker_add_medication.py --emulator "$EMULATOR_ID" --physical "$PHYSICAL_ID"

echo ""
echo "✅ CARETAKER ADD MEDICATION TEST COMPLETED SUCCESSFULLY!"
