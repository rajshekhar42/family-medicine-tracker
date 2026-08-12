import sys
import os
import time
import argparse
import re

# Add parent directory to sys.path to access shared page objects
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from adb_helper import run_adb, find_element, tap, type_text, wait_for_element, hide_keyboard, dismiss_permission_dialogs
from home_page import HomePage
from add_medicine_page import AddMedicinePage
from medicine_list_page import MedicineListPage
from history_page import HistoryPage
from onboarding_page import OnboardingPage


APP_PACKAGE = "org.medimitra.family_medicine_tracker"


def clear_app_data(device_id: str):
    """Wipe all local SQLite + shared prefs to ensure a clean state."""
    print(f"[{device_id}] 🧹 Wiping app data...")
    run_adb(device_id, ["shell", "pm", "clear", APP_PACKAGE])
    time.sleep(3)


def launch_app(device_id: str):
    print(f"[{device_id}] 🚀 Launching app...")
    run_adb(device_id, [
        "shell", "am", "start", "-n",
        f"{APP_PACKAGE}/{APP_PACKAGE}.MainActivity"
    ])
    time.sleep(8)


def add_medicine_due_in_minutes(device_id: str, med_name: str, minutes_from_now: int):
    """
    Adds a medicine with a single daily dose scheduled `minutes_from_now` minutes in the future.
    Taps the FAB, fills name, then manually edits the first time slot field.
    """
    # Fetch current time from the device itself via ADB to avoid host-emulator clock differences
    out, _ = run_adb(device_id, ["shell", "date", "+'%H:%M'"])
    out_clean = out.strip().replace("'", "").replace('"', "")
    print(f"[{device_id}] Current device time: {out_clean}")
    try:
        current_hour, current_minute = map(int, out_clean.split(':'))
    except Exception as e:
        print(f"[{device_id}] ⚠️ Failed to parse device time: {e}. Falling back to host time.")
        from datetime import datetime
        now = datetime.now()
        current_hour, current_minute = now.hour, now.minute

    # Calculate future time
    minute = (current_minute + minutes_from_now) % 60
    hour = (current_hour + (current_minute + minutes_from_now) // 60) % 24

    # Format for display
    display_hour = hour % 12 or 12
    am_pm = "PM" if hour >= 12 else "AM"
    time_str = f"{display_hour}:{minute:02d} {am_pm}"
    print(f"[{device_id}] ⏰ Scheduling '{med_name}' for ~{time_str} ({minutes_from_now} min from now)... with time as '{minute:02d}'")

    home = HomePage(device_id)
    home.tap_add_medicine_fab()
    time.sleep(2)

    # Enter name
    name_field = wait_for_element(device_id, "Enter name", timeout=10)
    if name_field:
        tap(device_id, name_field[0], name_field[1])
        time.sleep(1)
        type_text(device_id, med_name)
    hide_keyboard(device_id)
    time.sleep(1)

    # Tap the first time slot picker (it shows current default like "08:00 AM")
    # It's a time-picker chip/button in the form
    time_field = find_element(device_id, r"\d+:\d+ [AP]M")
    if time_field:
        tap(device_id, time_field[0], time_field[1])
        time.sleep(2)

        # Force TimePickerDialog into text input mode for reliable keyboard entry
        keyboard_mode_btn = find_element(device_id, "switch to text input mode", match_desc=True)
        if keyboard_mode_btn:
            tap(device_id, keyboard_mode_btn[0], keyboard_mode_btn[1])
            time.sleep(1.5)

        # On time picker in text mode, there should be separate hour / minute fields
        hour_input = find_element(device_id, "hour", match_desc=True)
        if hour_input:
            tap(device_id, hour_input[0], hour_input[1])
            time.sleep(1.2) # Wait for focus
            # Clear field using 4 backspaces
            for _ in range(4):
                run_adb(device_id, ["shell", "input", "keyevent", "67"])
                time.sleep(0.1)
            # Enter hour in 12h format
            display_hour = hour % 12 or 12
            type_text(device_id, str(display_hour))
            time.sleep(0.8)

        minute_input = find_element(device_id, "minute", match_desc=True)
        if minute_input:
            tap(device_id, minute_input[0], minute_input[1])
            time.sleep(1.2) # Wait for focus
            # Clear field using 4 backspaces
            for _ in range(4):
                run_adb(device_id, ["shell", "input", "keyevent", "67"])
                time.sleep(0.1)
            type_text(device_id, f"{minute:02d}")
            time.sleep(0.8)

        # Toggle AM/PM
        if hour >= 12:
            pm_btn = find_element(device_id, r"^PM$")
            if pm_btn:
                tap(device_id, pm_btn[0], pm_btn[1])
        else:
            am_btn = find_element(device_id, r"^AM$")
            if am_btn:
                tap(device_id, am_btn[0], am_btn[1])
        time.sleep(0.5)

        # Confirm time picker
        ok_btn = find_element(device_id, "OK")
        if ok_btn:
            tap(device_id, ok_btn[0], ok_btn[1])
        time.sleep(1.5)
    else:
        print(f"[{device_id}] ⚠️  Time field not found — using default time slot.")

    # Scroll down and save
    run_adb(device_id, ["shell", "input", "swipe", "500", "1500", "500", "500"])
    time.sleep(1.5)

    save_btn = find_element(device_id, "Add Medication")
    if save_btn:
        tap(device_id, save_btn[0], save_btn[1])
    else:
        tap(device_id, 540, 2200)
    time.sleep(3)

    return time_str


def check_notification_appeared(device_id: str, med_name: str, timeout_seconds: int = 150) -> bool:
    """
    Polls the notification shade every 10 seconds, looking for the medicine name.
    Returns True if notification is found within timeout, False otherwise.
    """
    print(f"[{device_id}] 🔔 Watching for '{med_name}' notification (up to {timeout_seconds}s)...")
    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        # Pull down the notification shade
        run_adb(device_id, ["shell", "input", "swipe", "540", "0", "540", "1000"])
        time.sleep(2)

        notif = find_element(device_id, med_name)
        if notif:
            print(f"[{device_id}] ✅ Notification for '{med_name}' appeared!")
            # Collapse notification shade
            run_adb(device_id, ["shell", "input", "keyevent", "4"])
            time.sleep(1)
            return True

        # Collapse shade and wait before next poll
        run_adb(device_id, ["shell", "input", "keyevent", "4"])
        time.sleep(8)

    print(f"[{device_id}] ❌ Notification for '{med_name}' did NOT appear within {timeout_seconds}s.")
    return False


def dismiss_notifications(device_id: str):
    """Clear all notifications from the shade."""
    run_adb(device_id, ["shell", "service", "call", "notification", "1"])
    time.sleep(1)


def navigate_to_settings(device_id: str, home: HomePage):
    """Open drawer and tap Settings."""
    print(f"[{device_id}] ⚙️  Navigating to Settings...")
    home.open_drawer()
    settings_btn = find_element(device_id, "Settings")
    if settings_btn:
        tap(device_id, settings_btn[0], settings_btn[1])
    else:
        tap(device_id, 300, 1400)
    time.sleep(2)


def toggle_reminders(device_id: str, enable: bool):
    """Toggle the 'Enable Reminders' switch in Settings to on/off."""
    state = "ON" if enable else "OFF"
    print(f"[{device_id}] 🔔 Setting reminders: {state}")

    # Find the switch element — look for content-desc "Reminders enabled" or similar
    switch = find_element(device_id, "Enable Reminders")
    if not switch:
        switch = find_element(device_id, "Reminders")
    if switch:
        # Read current state from UI dump to avoid double-toggling
        from adb_helper import get_dump
        import xml.etree.ElementTree as ET
        dump_file = get_dump(device_id)
        tree = ET.parse(dump_file)
        root = tree.getroot()
        is_checked = False
        for node in root.iter('node'):
            if "Reminders" in node.attrib.get('text', '') or "Reminders" in node.attrib.get('content-desc', ''):
                is_checked = node.attrib.get('checked', 'false') == 'true'
                break

        if enable != is_checked:
            tap(device_id, switch[0], switch[1])
            time.sleep(1)
        else:
            print(f"[{device_id}]   Reminders already set to {state}, skipping toggle.")
    else:
        print(f"[{device_id}] ⚠️  Reminders switch not found. Tapping fallback row.")
        tap(device_id, 900, 500)
        time.sleep(1)


def main():
    parser = argparse.ArgumentParser(description="Full features emulator test — Google login, App Code, reminders")
    parser.add_argument('--emulator', default='emulator-5554', help='Emulator device ID')
    args = parser.parse_args()
    device_id = args.emulator

    print("============================================================")
    print("🤖 FULL FEATURES EMULATOR TEST SUITE")
    print(f"   Device: {device_id}")
    print("   Scope : onboarding, Google login, App Code, reminders")
    print("============================================================")

    home = HomePage(device_id)
    add_med = AddMedicinePage(device_id)

    # ================================================================
    # STEP 0: Wipe app data + relaunch (clean state)
    # ================================================================
    print("\n--- STEP 0: Wipe app data and relaunch ---")
    clear_app_data(device_id)
    launch_app(device_id)

    # Dismiss any system permission dialogs that appear on first launch
    dismiss_permission_dialogs(device_id)

    # ================================================================
    # STEP 1: Onboarding
    # ================================================================
    print("\n--- STEP 1: Complete onboarding ---")
    onboarding = OnboardingPage(device_id)
    onboarding.enter_profile_name("Full Test User")
    dismiss_permission_dialogs(device_id)
    onboarding.submit()
    time.sleep(3)
    dismiss_permission_dialogs(device_id)

    # ================================================================
    # STEP 2: Google Login
    # ================================================================
    print("\n--- STEP 2: Google Login ---")
    home.open_drawer()
    already_signed_in = home.trigger_google_login()
    if not already_signed_in:
        home.select_google_account()
    time.sleep(3)

    # Verify signed in — drawer should show "MY APP CODE"
    app_code_label = wait_for_element(device_id, "MY APP CODE", timeout=15)
    if app_code_label:
        print(f"[{device_id}] ✅ Google login confirmed — 'MY APP CODE' section visible in drawer.")
    else:
        print(f"[{device_id}] ❌ Google login not confirmed. 'MY APP CODE' not visible.")
        sys.exit(1)

    # ================================================================
    # STEP 3: Verify 7-character App Code is generated
    # ================================================================
    print("\n--- STEP 3: Verify 7-character App Code ---")
    app_code = home.get_app_code()
    if not app_code:
        print(f"[{device_id}] ❌ App Code not found.")
        sys.exit(1)

    if len(app_code) == 7 and re.match(r'^[A-Z0-9]{7}$', app_code):
        print(f"[{device_id}] ✅ App Code is valid 7-character alphanumeric code: '{app_code}'")
    else:
        print(f"[{device_id}] ❌ App Code '{app_code}' does not match expected 7-char [A-Z0-9] format.")
        sys.exit(1)

    home.close_drawer()

    # ================================================================
    # STEP 4: Add a medicine due in 2 minutes
    # ================================================================
    print("\n--- STEP 4: Add medicine due in ~2 minutes ---")
    REMINDER_MED = "ReminderTest"
    add_medicine_due_in_minutes(device_id, REMINDER_MED, minutes_from_now=2)
    print(f"[{device_id}] ✅ Medicine '{REMINDER_MED}' added with 2-minute reminder.")

    # ================================================================
    # STEP 5: Verify notification appears WITH SOUND (reminders on by default)
    # ================================================================
    print("\n--- STEP 5: Verify reminder notification fires (reminders ON, sound ON) ---")
    # Note: automated tests cannot listen to system audio directly.
    # We verify that the notification appears in the shade within the deadline.
    if check_notification_appeared(device_id, REMINDER_MED, timeout_seconds=180):
        print(f"[{device_id}] ✅ PASS: Reminder notification appeared when reminders ON (sound assumed ON by default).")
    else:
        print(f"[{device_id}] ❌ FAIL: Reminder notification did NOT appear.")
        sys.exit(1)

    # ================================================================
    # STEP 6: Pre-taken dose should suppress next reminder
    # ================================================================
    print("\n--- STEP 6: Verify pre-taken dose suppresses notification ---")
    dismiss_notifications(device_id)

    # Add another medicine due in 2 minutes, but mark it taken immediately
    PRETAKEN_MED = "PreTakenTest"
    add_medicine_due_in_minutes(device_id, PRETAKEN_MED, minutes_from_now=2)
    time.sleep(2)

    # Mark it taken now (before the reminder fires)
    print(f"[{device_id}] ✍️  Marking '{PRETAKEN_MED}' as taken immediately...")
    home.take_all_pending_doses()
    time.sleep(2)

    # Wait past the scheduled time and confirm notification does NOT appear
    print(f"[{device_id}] ⏳ Waiting 3 minutes to verify notification is suppressed...")
    suppressed = not check_notification_appeared(device_id, PRETAKEN_MED, timeout_seconds=180)
    if suppressed:
        print(f"[{device_id}] ✅ PASS: No notification fired for pre-taken dose.")
    else:
        print(f"[{device_id}] ❌ FAIL: Notification fired for a dose that was already taken!")
        sys.exit(1)

    # ================================================================
    # STEP 7: Disable reminders in Settings — verify no notification fires
    # ================================================================
    print("\n--- STEP 7: Disable reminders → verify no notification ---")
    navigate_to_settings(device_id, home)
    toggle_reminders(device_id, enable=False)
    # Go back to home
    home.go_back()
    time.sleep(1)

    # Add another medicine due in 2 minutes
    DISABLED_MED = "DisabledReminderTest"
    add_medicine_due_in_minutes(device_id, DISABLED_MED, minutes_from_now=2)
    time.sleep(2)

    dismiss_notifications(device_id)
    no_notification = not check_notification_appeared(device_id, DISABLED_MED, timeout_seconds=180)
    if no_notification:
        print(f"[{device_id}] ✅ PASS: No notification fired when reminders are disabled.")
    else:
        print(f"[{device_id}] ❌ FAIL: Notification fired even though reminders are disabled!")
        sys.exit(1)

    # Re-enable reminders for good housekeeping
    navigate_to_settings(device_id, home)
    toggle_reminders(device_id, enable=True)
    home.go_back()

    print("")
    print("============================================================")
    print("🎉 FULL FEATURES EMULATOR TEST SUITE PASSED SUCCESSFULLY!")
    print("============================================================")


if __name__ == "__main__":
    main()
