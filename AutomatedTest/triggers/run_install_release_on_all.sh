#!/bin/bash
# ==============================================================================
# Compile latest debug APK and install on all connected devices (without clearing data/cache)
# ==============================================================================
set -e

APP_PACKAGE="org.medimitra.family_medicine_tracker"
APK_PATH="../../build/app/outputs/flutter-apk/app-debug.apk"

echo "============================================================"
echo "🛠️  1. Compiling latest debug APK..."
echo "============================================================"
flutter build apk --debug

# Get all connected device IDs
DEVICES=$(adb devices | grep -v "List of devices" | grep "device" | awk '{print $1}')

if [ -z "$DEVICES" ]; then
  echo "❌ Error: No connected devices found!"
  exit 1
fi

echo ""
echo "📱 Found connected devices:"
echo "$DEVICES"
echo ""

for DEVICE in $DEVICES; do
  echo "============================================================"
  echo "📲 Deploying to device: $DEVICE"
  echo "============================================================"
  
  echo "📥 Installing APK..."
  adb -s "$DEVICE" install -r "$APK_PATH"
  
  echo "🔔 Granting notification permission..."
  adb -s "$DEVICE" shell appops set "$APP_PACKAGE" POST_NOTIFICATION allow || true
  
  # Grant exact alarm permission (SCHEDULE_EXACT_ALARM is the valid appops op name)
  adb -s "$DEVICE" shell appops set "$APP_PACKAGE" SCHEDULE_EXACT_ALARM allow || true
  
  echo "♿ Enabling accessibility semantics..."
  adb -s "$DEVICE" shell settings put secure accessibility_enabled 1 || true
  
  echo "✅ Done for $DEVICE"
  echo ""
done

echo "🎉 Success! Updated application on all connected devices without clearing database/cache."
