#!/bin/bash
# ============================================================
# run_on_emulator_full.sh
# FULL FEATURES test suite — local + Google login + App Code
# verification + notification reminder tests.
#
# Pre-requisites:
#   - A Google account must already be configured on the emulator
#   - The emulator has internet access
#
# Steps:
#   1. Build & install app on emulator
#   2. Wipe emulator app data (clean state)
#   3. Run test_full_features.py
# ============================================================
set -e

EMULATOR_ID="${1:-emulator-5554}"
APP_PACKAGE="org.medimitra.family_medicine_tracker"
APP_ACTIVITY="$APP_PACKAGE.MainActivity"

echo "============================================================"
echo "🧪 FULL FEATURES EMULATOR TEST SUITE"
echo "   Emulator: $EMULATOR_ID"
echo "============================================================"

# ---------- 1. Build ----------
echo ""
echo "📦 Fetching packages..."
flutter pub get

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
adb -s "$EMULATOR_ID" shell am start -n "$APP_PACKAGE/$APP_ACTIVITY"

echo "⏳ Waiting 10s for app to fully render..."
sleep 10

# ---------- 7. Run full feature test ----------
echo ""
echo "🤖 Running full features test suite..."
cd AutomatedTest/full_test
python3 test_full_features.py --emulator "$EMULATOR_ID"
cd ../..

echo ""
echo "✅ FULL FEATURES EMULATOR TEST SUITE COMPLETED SUCCESSFULLY!"
