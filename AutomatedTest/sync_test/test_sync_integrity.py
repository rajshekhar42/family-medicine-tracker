import sys
import os
import time
import argparse

# Add parent directory to sys.path to access shared page objects
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from adb_helper import run_adb, find_element, tap, dismiss_permission_dialogs, wait_for_element
from home_page import HomePage
from add_medicine_page import AddMedicinePage
from medicine_list_page import MedicineListPage
from history_page import HistoryPage
from onboarding_page import OnboardingPage


def main():
    parser = argparse.ArgumentParser(description="Sync Integrity Test — verifies caretaker additions don't reset parent completed actions")
    parser.add_argument('--emulator', default='emulator-5554', help='Parent device (emulator) ID')
    parser.add_argument('--physical', default='51071JEBF16934', help='Caretaker device (physical) ID')
    args = parser.parse_args()

    parent_id = args.emulator
    caretaker_id = args.physical

    print("============================================================")
    print("🤖 SYNC INTEGRITY TEST SUITE")
    print(f"   Parent     (Emulator): {parent_id}")
    print(f"   Caretaker  (Physical): {caretaker_id}")
    print("   Pre-requisite: Both devices must be Google signed-in")
    print("============================================================")
    time.sleep(2)

    parent_home = HomePage(parent_id)
    caretaker_home = HomePage(caretaker_id)

    # ================================================================
    # STEP 0: Onboarding
    # ================================================================
    print("\n--- STEP 0: Complete onboarding on both devices ---")
    dismiss_permission_dialogs(parent_id)
    dismiss_permission_dialogs(caretaker_id)

    parent_onboarding = OnboardingPage(parent_id)
    parent_onboarding.enter_profile_name("Parent User")
    parent_onboarding.submit()

    caretaker_onboarding = OnboardingPage(caretaker_id)
    caretaker_onboarding.enter_profile_name("Caretaker User")
    caretaker_onboarding.submit()

    # ================================================================
    # STEP 0.5: Verify Google Sign-In
    # ================================================================
    print("\n--- STEP 0.5: Verify Google Sign-In ---")
    
    # 1. Parent (Emulator)
    parent_home.open_drawer()
    already_signed_in = parent_home.trigger_google_login()
    if not already_signed_in:
        print(f"[{parent_id}] Google login triggered. Selecting account...")
        parent_home.select_google_account("rajshekhardev@gmail.com")
        app_code_label = wait_for_element(parent_id, "MY APP CODE", timeout=15)
        parent_app_code = parent_home.get_app_code()
        if parent_app_code:
            print(f"[{parent_id}] ✅ Google login confirmed.")
        else:
            print(f"[{parent_id}] ❌ Failed to log in to Google.")
            sys.exit(1)
    else:
        print(f"[{parent_id}] ✅ Already signed in.")
    parent_home.close_drawer()

    # 2. Caretaker (Physical Device)
    caretaker_home.open_drawer()
    already_signed_in = caretaker_home.trigger_google_login()
    if not already_signed_in:
        print(f"[{caretaker_id}] Google login triggered. Selecting account...")
        caretaker_home.select_google_account("rajshekhar53@gmail.com")
        app_code_label = wait_for_element(caretaker_id, "MY APP CODE", timeout=15)
        caretaker_app_code = caretaker_home.get_app_code()
        if caretaker_app_code:
            print(f"[{caretaker_id}] ✅ Google login confirmed.")
        else:
            print(f"[{caretaker_id}] ❌ Failed to log in to Google.")
            sys.exit(1)
    else:
        print(f"[{caretaker_id}] ✅ Already signed in.")
    caretaker_home.close_drawer()

    # ================================================================
    # STEP 1: Retrieve Parent App Code
    # ================================================================
    print("\n--- STEP 1: Retrieve Parent App Code ---")
    parent_home.open_drawer()
    parent_app_code = parent_home.get_app_code()
    if not parent_app_code:
        print("❌ CRITICAL: Failed to get Parent's App Code. Aborting.")
        sys.exit(1)
    print(f"[{parent_id}] ✅ Parent App Code: {parent_app_code}")
    parent_home.close_drawer()

    # ================================================================
    # STEP 2: Caretaker Requests Pairing
    # ================================================================
    print("\n--- STEP 2: Caretaker Requests Pairing ---")
    caretaker_home.open_drawer()
    caretaker_home.enter_parent_app_code(parent_app_code, "Parent Shekhar")
    caretaker_home.close_drawer()

    # ================================================================
    # STEP 3: Parent Accepts Connection Banner
    # ================================================================
    print("\n--- STEP 3: Parent Accepts Connection Banner ---")
    accepted = parent_home.accept_connection_request()
    if not accepted:
        print(f"[{parent_id}] ❌ No pairing request banner found. Trying via drawer...")
        parent_home.open_drawer()
        accepted = parent_home.accept_connection_request()
        parent_home.close_drawer()
    if accepted:
        print(f"[{parent_id}] ✅ Pairing request accepted.")
    else:
        print(f"[{parent_id}] ❌ Could not accept pairing request.")
        sys.exit(1)

    # ================================================================
    # STEP 4: Switch to Parent Profile on Caretaker
    # ================================================================
    print("\n--- STEP 4: Switch to Parent Profile on Caretaker ---")
    time.sleep(6)
    caretaker_home.open_drawer()
    parent_tile = find_element(caretaker_id, "Parent Shekhar")
    if parent_tile:
        tap(caretaker_id, parent_tile[0], parent_tile[1])
    else:
        print(f"[{caretaker_id}] ⚠️  'Parent Shekhar' tile not found. Tapping fallback.")
        tap(caretaker_id, 300, 350)
    time.sleep(2.5)
    caretaker_home.close_drawer()

    # ================================================================
    # STEP 5: Caretaker adds Medicine A for Parent
    # ================================================================
    timestamp = int(time.time())
    med_name_a = f"IntegMedA{timestamp}"
    med_name_b = f"IntegMedB{timestamp}"

    print(f"\n--- STEP 5: Caretaker adds Medicine A ({med_name_a}) and saves ---")
    caretaker_home.navigate_to_medicine_list()
    time.sleep(2)
    add_btn = find_element(caretaker_id, "Add Medicine")
    if add_btn:
        tap(caretaker_id, add_btn[0], add_btn[1])
    else:
        tap(caretaker_id, 960, 2240)
    time.sleep(2.5)

    caretaker_add_med = AddMedicinePage(caretaker_id)
    caretaker_add_med.add_medicine(med_name_a, "Once a Day")
    
    print("⏳ Waiting 15s for automatic sync of Medicine A to complete...")
    time.sleep(15)
    caretaker_home.go_back()
    time.sleep(2)

    # ================================================================
    # STEP 6: Verify Medicine A exists on Parent & Mark Taken
    # ================================================================
    print(f"\n--- STEP 6: Verify Medicine A ({med_name_a}) on Parent and mark as Taken ---")
    parent_home.navigate_to_medicine_list()
    parent_med_list = MedicineListPage(parent_id)
    parent_med_list.verify_medicine_exists(med_name_a)
    print(f"[{parent_id}] ✅ Verified: Medicine A successfully visible on Parent.")
    parent_home.go_back()
    time.sleep(2)

    # Parent marks Medicine A as taken on Home screen
    parent_home.take_all_pending_doses()
    time.sleep(3)

    # ================================================================
    # STEP 7: Caretaker adds Medicine B for Parent
    # ================================================================
    print(f"\n--- STEP 7: Caretaker adds Medicine B ({med_name_b}) and saves ---")
    caretaker_home.navigate_to_medicine_list()
    time.sleep(2)
    add_btn = find_element(caretaker_id, "Add Medicine")
    if add_btn:
        tap(caretaker_id, add_btn[0], add_btn[1])
    else:
        tap(caretaker_id, 960, 2240)
    time.sleep(2.5)

    caretaker_add_med.add_medicine(med_name_b, "Once a Day")
    
    print("⏳ Waiting 15s for automatic sync of Medicine B to complete...")
    time.sleep(15)
    caretaker_home.go_back()
    time.sleep(2)

    # ================================================================
    # STEP 8: Verify Medicine B exists on Parent & Medicine A is still Taken
    # ================================================================
    print(f"\n--- STEP 8: Verify Medicine B ({med_name_b}) exists and Medicine A ({med_name_a}) remains Taken ---")
    parent_home.navigate_to_medicine_list()
    parent_med_list.verify_medicine_exists(med_name_b)
    print(f"[{parent_id}] ✅ Verified: Medicine B successfully visible on Parent.")
    parent_home.go_back()
    time.sleep(2)

    # Navigate to Adherence History to verify Medicine A remains "Taken"
    parent_home.navigate_to_history()
    parent_history = HistoryPage(parent_id)
    parent_history.verify_history_contains(med_name_a, should_be_taken=True)
    print(f"[{parent_id}] ✅ VERIFIED: Medicine A '{med_name_a}' is still marked as Taken in History (no sync undo!).")
    parent_home.go_back()

    # Ensure drawers are closed on both devices at the end of the test
    parent_home.close_drawer()
    caretaker_home.close_drawer()

    print("")
    print("============================================================")
    print("🎉 SYNC INTEGRITY CHECK PASSED SUCCESSFULLY!")
    print("============================================================")


if __name__ == "__main__":
    main()
