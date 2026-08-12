#!/bin/bash
# ============================================================
# run_on_emulator.sh
# LOCAL ONLY test suite — no Google login, no caretaker sync.
#
# Steps:
#   1. Build & install app on emulator
#   2. Wipe emulator app data (clean state)
#   3. Run test_local_only.py
# ============================================================
set -e

EMULATOR_ID="${1:-emulator-5554}"
APP_PACKAGE="org.medimitra.family_medicine_tracker"
APP_ACTIVITY="$APP_PACKAGE.MainActivity"

echo "============================================================"
echo "🧪 LOCAL EMULATOR TEST SUITE"
echo "   Emulator: $EMULATOR_ID"
echo "============================================================"

# ---------- 1. Build ----------
echo ""
echo "🛠️  Building debug APK..."
flutter build apk --debug

# ---------- 2. Install ----------
echo ""
echo "📥 Installing app on emulator ($EMULATOR_ID)..."
adb -s "$EMULATOR_ID" install -r build/app/outputs/flutter-apk/app-debug.apk

# ---------- 3. Wipe app data (clean state) ----------
echo ""
echo "🧹 Clearing emulator app data (fresh start)..."
adb -s "$EMULATOR_ID" shell am force-stop "$APP_PACKAGE" || true
adb -s "$EMULATOR_ID" shell am force-stop com.google.android.gms || true
adb -s "$EMULATOR_ID" shell pm clear "$APP_PACKAGE" || true

# ---------- 4. Enable accessibility for UI automation ----------
echo "♿ Enabling accessibility semantics..."
adb -s "$EMULATOR_ID" shell settings put secure accessibility_enabled 1 || true

# ---------- 5. Grant notification & exact alarm permissions ----------
echo "🔔 Granting notification permission..."
adb -s "$EMULATOR_ID" shell pm grant "$APP_PACKAGE" android.permission.POST_NOTIFICATIONS || true

echo "⏰ Granting exact alarm permission..."
adb -s "$EMULATOR_ID" shell appops set "$APP_PACKAGE" SCHEDULE_EXACT_ALARM allow || true

# ---------- 6. Launch app ----------
echo ""
echo "🚀 Launching app on emulator ($EMULATOR_ID)..."
adb -s "$EMULATOR_ID" shell am start -S -n "$APP_PACKAGE/$APP_ACTIVITY"

echo "⏳ Waiting 4s for app to fully render..."
sleep 4

# ---------- 7. Run local-only test ----------
echo ""
echo "🤖 Running local-only test suite..."
cd AutomatedTest/local_test
python3 -u test_local_only.py --emulator "$EMULATOR_ID"
cd ../..

echo ""
echo "✅ LOCAL EMULATOR TEST SUITE COMPLETED SUCCESSFULLY!"
