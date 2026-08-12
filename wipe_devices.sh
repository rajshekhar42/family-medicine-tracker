#!/bin/bash
# ============================================================
# wipe_devices.sh
# Clears the app data / database on all connected Android devices
# ============================================================

APP_PACKAGE="org.medimitra.family_medicine_tracker"

# Get list of all connected devices
DEVICES=$(adb devices | grep -v "List" | grep "device" | cut -f1)

if [ -z "$DEVICES" ]; then
  echo "❌ Error: No devices connected."
  exit 1
fi

echo "🧹 Wiping app data on all connected devices..."
echo ""

for DEVICE in $DEVICES; do
  echo "------------------------------------------------------------"
  echo "📱 Device: $DEVICE"
  echo "------------------------------------------------------------"
  
  echo "🛑 Force-stopping app..."
  adb -s "$DEVICE" shell am force-stop "$APP_PACKAGE" || true
  
  echo "🧹 Clearing app database and cache..."
  adb -s "$DEVICE" shell pm clear "$APP_PACKAGE" || true
  
  # Also re-grant notification and alarm permissions which might get reset by pm clear
  echo "🔔 Granting notification permission..."
  adb -s "$DEVICE" shell appops set "$APP_PACKAGE" POST_NOTIFICATION allow || true
  
  echo "⏰ Granting exact alarm permission..."
  adb -s "$DEVICE" shell appops set "$APP_PACKAGE" SCHEDULE_EXACT_ALARM allow || true
  
  echo "✅ Wiped successfully!"
  echo ""
done

echo "🎉 All devices cleared!"
