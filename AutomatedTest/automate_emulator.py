import sys
import time
import argparse
from adb_helper import run_adb
from onboarding_page import OnboardingPage
from home_page import HomePage
from add_medicine_page import AddMedicinePage
from medicine_list_page import MedicineListPage
from history_page import HistoryPage

def main():
    parser = argparse.ArgumentParser(description="Dual device UI automation sync test")
    parser.add_argument('--emulator', default='emulator-5554', help='Emulator device ID')
    parser.add_argument('--physical', default='51071JEBF16934', help='Physical device ID')
    args = parser.parse_args()

    parent_id = args.emulator
    caretaker_id = args.physical

    print(f"🤖 Starting Dual-Device Sync Verification...")
    print(f"   Parent Device (Emulator): {parent_id}")
    print(f"   Caretaker Device (Physical): {caretaker_id}")
    time.sleep(2)
    
    # Instantiate page objects for each device
    parent_onboarding = OnboardingPage(parent_id)
    caretaker_onboarding = OnboardingPage(caretaker_id)
    
    parent_home = HomePage(parent_id)
    caretaker_home = HomePage(caretaker_id)
    
    parent_add_med = AddMedicinePage(parent_id)
    
    # ==========================================
    # STEP 1: ONBOARDING ON BOTH DEVICES
    # ==========================================
    print("\n--- STEP 1: Onboarding on both devices ---")
    parent_onboarding.enter_profile_name("Parent Shekhar")
    parent_onboarding.submit()
    
    caretaker_onboarding.enter_profile_name("Caretaker Shekhar")
    caretaker_onboarding.submit()
    
    # ==========================================
    # STEP 2: GOOGLE LOGIN ON BOTH DEVICES
    # ==========================================
    print("\n--- STEP 2: Google Login ---")
    parent_home.open_drawer()
    already_logged_in_parent = parent_home.trigger_google_login()
    if not already_logged_in_parent:
        parent_home.select_google_account()
    
    caretaker_home.open_drawer()
    already_logged_in_caretaker = caretaker_home.trigger_google_login()
    if not already_logged_in_caretaker:
        caretaker_home.select_google_account()
    
    # ==========================================
    # STEP 3: RETRIEVE PARENT APP CODE
    # ==========================================
    print("\n--- STEP 3: Retrieve Parent App Code ---")
    # Parent's drawer is already open from Step 2 login
    parent_app_code = parent_home.get_app_code()
    if not parent_app_code:
        print("❌ CRITICAL: Failed to get Parent's App Code. Aborting.")
        sys.exit(1)
    parent_home.close_drawer()
    
    # ==========================================
    # STEP 4: CARETAKER REQUESTS PAIRING
    # ==========================================
    print("\n--- STEP 4: Caretaker Requests Pairing ---")
    # Caretaker's drawer is already open from Step 2 login
    caretaker_home.enter_parent_app_code(parent_app_code, "Parent Shekhar")
    caretaker_home.close_drawer()
    
    # ==========================================
    # STEP 5: PARENT ACCEPTS PAIRING REQUEST
    # ==========================================
    print("\n--- STEP 5: Parent Accepts Connection ---")
    parent_home.open_drawer()
    parent_home.accept_connection_request()
    parent_home.close_drawer()
    
    # ==========================================
    # STEP 6: VERIFY INITIAL EMPTY SYNC ON CARETAKER
    # ==========================================
    print("\n--- STEP 6: Verify Initial Sync on Caretaker ---")
    time.sleep(5) # Wait for sync ack and profile delivery
    caretaker_home.open_drawer()
    
    # Tap the synced Parent profile to select it
    print(f"[{caretaker_id}] Switching to Parent Shekhar profile...")
    from adb_helper import find_element, tap
    parent_tile = find_element(caretaker_id, "Parent Shekhar")
    if parent_tile:
        tap(caretaker_id, parent_tile[0], parent_tile[1])
    else:
        # Fallback list tile switch
        tap(caretaker_id, 300, 350)
    time.sleep(2)
    
    caretaker_home.navigate_to_medicine_list()
    caretaker_med_list = MedicineListPage(caretaker_id)
    # Check that it is currently empty
    empty_msg = find_element(caretaker_id, "No medications")
    if empty_msg:
        print("✅ Verified: Caretaker synced Parent view and shows no medicines initially.")
    else:
        print("⚠️ Warning: Medicine list not empty initially, proceeding anyway.")
        
    print(f"[{caretaker_id}] Returning to Home...")
    run_adb(caretaker_id, ["shell", "input", "keyevent", "4"])
    time.sleep(2)
    
    # ==========================================
    # STEP 7: ADD & TAKE MEDICINES ON PARENT
    # ==========================================
    print("\n--- STEP 7: Add & Take Medicines on Parent (Emulator) ---")
    parent_home.tap_add_medicine_fab()
    parent_add_med.add_medicine("Aspirin", "Once a Day")
    
    parent_home.tap_add_medicine_fab()
    parent_add_med.add_medicine("Metformin", "2 times, Daily")
    
    # Mark them taken on Parent
    parent_home.take_all_pending_doses()

    # Trigger Sync on Parent to push to caretaker
    print(f"[{parent_id}] Triggering Sync Now to push payload to Caretaker...")
    parent_home.open_drawer()
    parent_sync_btn = find_element(parent_id, "Sync Now")
    if parent_sync_btn:
        tap(parent_id, parent_sync_btn[0], parent_sync_btn[1])
    else:
        print(f"[{parent_id}] ❌ Sync Now button not found in drawer. Tapping fallback.")
        tap(parent_id, 300, 2210)
    time.sleep(6)
    parent_home.close_drawer()
    
    # ==========================================
    # STEP 8: VERIFY LIVE REAL-TIME SYNC ON CARETAKER
    # ==========================================
    print("\n--- STEP 8: Verify Live Sync on Caretaker (Physical Device) ---")
    print("Waiting 10 seconds for real-time background sync payload delivery...")
    time.sleep(10)
    
    # Go to Medicine List on Caretaker (we are already under Parent profile)
    caretaker_home.navigate_to_medicine_list()
    caretaker_med_list.verify_medicine_exists("Aspirin")
    caretaker_med_list.verify_medicine_exists("Metformin")
    
    print(f"[{caretaker_id}] Returning to Home...")
    run_adb(caretaker_id, ["shell", "input", "keyevent", "4"])
    time.sleep(2)
    
    # Go to History on Caretaker
    caretaker_home.navigate_to_history()
    caretaker_history = HistoryPage(caretaker_id)
    caretaker_history.verify_history_contains("Aspirin", should_be_taken=True)
    caretaker_history.verify_history_contains("Metformin", should_be_taken=True)
    
    print(f"[{caretaker_id}] Returning to Home...")
    run_adb(caretaker_id, ["shell", "input", "keyevent", "4"])
    time.sleep(2)
    
    print("\n🎉 DUAL-DEVICE CLOUD SYNC AUTOMATION PASSED SUCCESSFULLY!")

if __name__ == "__main__":
    main()
