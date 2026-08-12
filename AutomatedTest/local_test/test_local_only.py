import sys
import os
import time
import argparse

# Add parent directory to sys.path to access shared page objects
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from adb_helper import run_adb, find_element, tap, wait_for_element, dismiss_permission_dialogs
from home_page import HomePage
from add_medicine_page import AddMedicinePage
from medicine_list_page import MedicineListPage
from history_page import HistoryPage
from onboarding_page import OnboardingPage


def clear_app_data(device_id: str):
    """Wipe all local SQLite + shared prefs to ensure a clean state."""
    print(f"[{device_id}] 🧹 Wiping app data...")
    run_adb(device_id, ["shell", "pm", "clear", "org.medimitra.family_medicine_tracker"])
    time.sleep(3)


def launch_app(device_id: str):
    print(f"[{device_id}] 🚀 Launching app...")
    run_adb(device_id, [
        "shell", "am", "start", "-n",
        "org.medimitra.family_medicine_tracker/org.medimitra.family_medicine_tracker.MainActivity"
    ])
    time.sleep(8)


def main():
    parser = argparse.ArgumentParser(description="Local-only emulator test — no Google login, no caretaker sync")
    parser.add_argument('--emulator', default='emulator-5554', help='Emulator device ID')
    args = parser.parse_args()
    device_id = args.emulator

    print("============================================================")
    print("🤖 LOCAL EMULATOR TEST SUITE")
    print(f"   Device: {device_id}")
    print("   Scope : local only — no Google login, no caretaker sync")
    print("============================================================")

    # ================================================================
    # STEP 1: Local onboarding
    # ================================================================
    print("\n--- STEP 1: Complete onboarding ---")
    
    # Dismiss any system permission dialogs that appear on launch
    dismiss_permission_dialogs(device_id)

    onboarding = OnboardingPage(device_id)
    onboarding.enter_profile_name("Test User")
    onboarding.submit()
    time.sleep(3)



    # ================================================================
    # STEP 2: Add a medicine with "2 times, Daily" frequency
    # ================================================================
    print("\n--- STEP 2: Add medicine 'Paracetamol' (2 times, Daily) ---")
    home = HomePage(device_id)
    add_med = AddMedicinePage(device_id)

    home.tap_add_medicine_fab()
    # NOTE: frequency must match app's exact string from AppConstants.frequencyOptions
    add_med.add_medicine("Paracetamol", "2 times, Daily")
    time.sleep(2)

    # ================================================================
    # STEP 3: Verify medicine appears in Medicine List screen
    # ================================================================
    print("\n--- STEP 3: Verify medicine in Medicine List screen ---")
    home.navigate_to_medicine_list()
    med_list = MedicineListPage(device_id)
    med_list.verify_medicine_exists("Paracetamol")

    print(f"[{device_id}] ✅ Paracetamol found in Medicine List.")
    # Longer sleep to let the screen transition fully settle before opening drawer
    home.go_back()
    time.sleep(4)

    # ================================================================
    # STEP 4: Mark all doses as taken on Home screen
    # ================================================================
    print("\n--- STEP 4: Mark all pending doses as Taken ---")
    # Scroll back to top of home list to ensure all dose cards are in view
    run_adb(device_id, ["shell", "input", "swipe", "540", "800", "540", "1500"])
    time.sleep(1.5)
    home.take_all_pending_doses()
    time.sleep(2)

    # ================================================================
    # STEP 5: Verify Adherence History — By Date
    # ================================================================
    print("\n--- STEP 5: Verify adherence history (By Date) ---")
    # Give the home screen extra time before navigating (avoids drawer timing issue)
    time.sleep(2)
    home.navigate_to_history()
    history = HistoryPage(device_id)
    history.verify_history_contains("Paracetamol", should_be_taken=True)
    print(f"[{device_id}] ✅ History (By Date): Paracetamol is marked Taken.")

    # ================================================================
    # STEP 6: Verify Adherence History — By Medicine
    # ================================================================
    print("\n--- STEP 6: Verify adherence history (By Medicine) ---")
    # Switch to "By Medicine" tab (second tab on History screen)
    by_med_tab = find_element(device_id, "By Medicine")
    if by_med_tab:
        tap(device_id, by_med_tab[0], by_med_tab[1])
    else:
        # Fallback: tap approximate coordinates of second tab
        tap(device_id, 750, 350)
    time.sleep(2)

    para_tile = wait_for_element(device_id, "Paracetamol", timeout=10)
    if para_tile:
        print(f"[{device_id}] ✅ Paracetamol found in By-Medicine tab.")
    else:
        print(f"[{device_id}] ❌ Paracetamol NOT found in By-Medicine tab!")
        sys.exit(1)

    home.go_back()

    print("")
    print("============================================================")
    print("🎉 LOCAL EMULATOR TEST SUITE PASSED SUCCESSFULLY!")
    print("============================================================")


if __name__ == "__main__":
    main()
