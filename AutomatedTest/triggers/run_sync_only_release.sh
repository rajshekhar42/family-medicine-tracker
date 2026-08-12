#!/bin/bash
# ============================================================
# run_sync_only_release.sh
# FRESH RELEASE BUILD SYNC TEST SUITE — complete fresh start.
#
# Steps:
#   1. Build Release APK (`flutter build apk --release`)
#   2. Install Release APK on emulator & physical device
#   3. Complete wipe of app data (clears DB, Google login, & preferences)
#   4. Re-grant accessibility and permissions
#   5. Run full end-to-end sync integrity test (onboarding -> Google login -> sync)
# ============================================================
set -e

EMULATOR_ID="${1:-emulator-5554}"
PHYSICAL_ID="${2:-51071JEBF16934}"
APP_PACKAGE="org.medimitra.family_medicine_tracker"
APP_ACTIVITY="$APP_PACKAGE.MainActivity"
RELEASE_APK="build/app/outputs/flutter-apk/app-release.apk"

echo "============================================================"
echo "🧪 FRESH RELEASE BUILD SYNC TEST SUITE"
echo "   Parent   (Emulator): $EMULATOR_ID"
echo "   Caretaker (Physical): $PHYSICAL_ID"
echo "   Mode: Complete Fresh Start (Wiping App Data & Google Auth)"
echo "============================================================"

# ---------- Step 1: Build Release APK ----------
echo ""
echo "🛠️  1. Compiling Release APK..."
flutter build apk --release

if [ ! -f "$RELEASE_APK" ]; then
  echo "❌ Error: Release APK not found at $RELEASE_APK"
  exit 1
fi

# ---------- Step 2: Install Release APK on connected devices ----------
echo ""
echo "📲 2. Installing Release APK on devices..."

if adb devices | grep -q "$EMULATOR_ID"; then
  echo "📥 Installing release APK on emulator ($EMULATOR_ID)..."
  adb -s "$EMULATOR_ID" install -r "$RELEASE_APK"
else
  echo "⚠️ Warning: Emulator device ($EMULATOR_ID) not detected by ADB."
fi

if adb devices | grep -q "$PHYSICAL_ID"; then
  echo "📥 Installing release APK on physical device ($PHYSICAL_ID)..."
  adb -s "$PHYSICAL_ID" install -r "$RELEASE_APK"
else
  echo "⚠️ Warning: Physical device ($PHYSICAL_ID) not detected by ADB."
fi

# ---------- Step 3: Wake up and unlock devices ----------
echo ""
echo "🔓 3. Waking up and unlocking devices..."
if adb devices | grep -q "$EMULATOR_ID"; then
  adb -s "$EMULATOR_ID" shell input keyevent 224 || true
  adb -s "$EMULATOR_ID" shell input keyevent 82 || true
fi

if adb devices | grep -q "$PHYSICAL_ID"; then
  adb -s "$PHYSICAL_ID" shell input keyevent 224 || true
  adb -s "$PHYSICAL_ID" shell input keyevent 82 || true
fi

# ---------- Step 4: Complete Fresh Start (pm clear) ----------
echo ""
echo "🧹 4. Complete fresh wipe of app data & Google sessions..."
if adb devices | grep -q "$EMULATOR_ID"; then
  adb -s "$EMULATOR_ID" shell am force-stop "$APP_PACKAGE" || true
  adb -s "$EMULATOR_ID" shell pm clear "$APP_PACKAGE" || true
fi

if adb devices | grep -q "$PHYSICAL_ID"; then
  adb -s "$PHYSICAL_ID" shell am force-stop "$APP_PACKAGE" || true
  adb -s "$PHYSICAL_ID" shell pm clear "$APP_PACKAGE" || true
fi

sleep 2

# ---------- Step 5: Enable accessibility & permissions ----------
echo ""
echo "♿ 5. Enabling permissions and accessibility..."
for DEV in "$EMULATOR_ID" "$PHYSICAL_ID"; do
  if adb devices | grep -q "$DEV"; then
    adb -s "$DEV" shell settings put secure accessibility_enabled 1 || true
    adb -s "$DEV" shell pm grant "$APP_PACKAGE" android.permission.POST_NOTIFICATIONS 2>/dev/null || true
    adb -s "$DEV" shell appops set "$APP_PACKAGE" POST_NOTIFICATION allow 2>/dev/null || true
    adb -s "$DEV" shell appops set "$APP_PACKAGE" SCHEDULE_EXACT_ALARM allow 2>/dev/null || true
  fi
done

# ---------- Step 6: Launch Release App ----------
echo ""
echo "🚀 6. Launching Release App on devices..."
if adb devices | grep -q "$EMULATOR_ID"; then
  echo "🚀 Launching on emulator ($EMULATOR_ID)..."
  adb -s "$EMULATOR_ID" shell am start -S -n "$APP_PACKAGE/$APP_ACTIVITY"
fi

if adb devices | grep -q "$PHYSICAL_ID"; then
  echo "🚀 Launching on physical device ($PHYSICAL_ID)..."
  adb -s "$PHYSICAL_ID" shell am start -S -n "$APP_PACKAGE/$APP_ACTIVITY"
fi

echo "⏳ Waiting 10s for release apps to render..."
sleep 10

# ---------- Step 7: Run Full Sync Test ----------
echo ""
echo "🤖 7. Running full sync test suite (onboarding -> Google login -> sync)..."
cd AutomatedTest/sync_test
python3 -u test_sync_integrity.py --emulator "$EMULATOR_ID" --physical "$PHYSICAL_ID"
cd ../..

echo ""
echo "🎉 FRESH RELEASE BUILD SYNC TEST COMPLETED SUCCESSFULLY!"
