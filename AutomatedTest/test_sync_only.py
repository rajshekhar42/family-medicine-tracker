import sys
import time
import argparse
from adb_helper import run_adb, find_element, tap
from home_page import HomePage
from add_medicine_page import AddMedicinePage
from medicine_list_page import MedicineListPage
from history_page import HistoryPage

def main():
    parser = argparse.ArgumentParser(description="Persisted session sync test")
    parser.add_argument('--emulator', default='emulator-5554', help='Emulator device ID')
    parser.add_argument('--physical', default='51071JEBF16934', help='Physical device ID')
    args = parser.parse_args()

    parent_id = args.emulator
    caretaker_id = args.physical

    print(f"🤖 Starting Persisted Session Sync Verification...")
    print(f"   Parent Device (Emulator): {parent_id}")
    print(f"   Caretaker Device (Physical): {caretaker_id}")
    time.sleep(2)
    
    parent_home = HomePage(parent_id)
    caretaker_home = HomePage(caretaker_id)
    parent_add_med = AddMedicinePage(parent_id)

    # ==========================================
    # STEP 1: RETRIEVE PARENT APP CODE
    # ==========================================
    print("\n--- STEP 1: Retrieve Parent App Code ---")
    parent_home.open_drawer()
    parent_app_code = parent_home.get_app_code()
    if not parent_app_code:
        print("❌ CRITICAL: Failed to get Parent's App Code. Aborting.")
        sys.exit(1)
    parent_home.close_drawer()

    # ==========================================
    # STEP 2: CARETAKER REQUESTS PAIRING
    # ==========================================
    print("\n--- STEP 2: Caretaker Requests Pairing ---")
    caretaker_home.open_drawer()
    caretaker_home.enter_parent_app_code(parent_app_code, "Parent Shekhar")
    caretaker_home.close_drawer()

    # ==========================================
    # STEP 3: PARENT ACCEPTS PAIRING REQUEST
    # ==========================================
    print("\n--- STEP 3: Parent Accepts Connection ---")
    parent_home.open_drawer()
    parent_home.accept_connection_request()
    parent_home.close_drawer()

    # ==========================================
    # STEP 4: SWITCH TO PARENT PROFILE ON CARETAKER
    # ==========================================
    print("\n--- STEP 4: Switch to Parent Profile on Caretaker ---")
    caretaker_home.open_drawer()
    print(f"[{caretaker_id}] Switching to Parent Shekhar profile...")
    parent_tile = find_element(caretaker_id, "Parent Shekhar")
    if parent_tile:
        tap(caretaker_id, parent_tile[0], parent_tile[1])
    else:
        # Fallback list tile switch
        tap(caretaker_id, 300, 350)
    time.sleep(2.5)
    caretaker_home.close_drawer()

    # ==========================================
    # STEP 5: ADD UNIQUE MEDICINE & SYNC ON PARENT
    # ==========================================
    print("\n--- STEP 5: Add Medicine & Sync on Parent ---")
    timestamp = int(time.time())
    med_name = f"Aspirin_{timestamp}"
    
    parent_home.tap_add_medicine_fab()
    parent_add_med.add_medicine(med_name, "Once a Day")
    
    # Mark taken on Parent
    parent_home.take_dose(med_name)

    # Trigger pull sync on Caretaker to request payload from Parent
    print(f"[{caretaker_id}] Triggering Caretaker pull sync request from drawer...")
    caretaker_home.open_drawer()
    caretaker_sync_btn = find_element(caretaker_id, "Sync Now")
    if caretaker_sync_btn:
        tap(caretaker_id, caretaker_sync_btn[0], caretaker_sync_btn[1])
    else:
        print(f"[{caretaker_id}] ❌ Sync Now button not found in drawer. Tapping fallback.")
        tap(caretaker_id, 300, 2210)
    
    # Wait for the pull sync handshake and data delivery to complete
    print("Waiting 12 seconds for caretaker pull sync request handshake and data delivery...")
    time.sleep(12)
    caretaker_home.close_drawer()
    
    # Go to Medicine List on Caretaker and verify exists
    caretaker_home.navigate_to_medicine_list()
    caretaker_med_list = MedicineListPage(caretaker_id)
    caretaker_med_list.verify_medicine_exists(med_name)
    
    print(f"[{caretaker_id}] Returning to Home...")
    caretaker_home.go_back()
    
    # Go to History on Caretaker
    caretaker_home.navigate_to_history()
    caretaker_history = HistoryPage(caretaker_id)
    caretaker_history.verify_history_contains(med_name, should_be_taken=True)
    
    print(f"[{caretaker_id}] Returning to Home...")
    caretaker_home.go_back()
    
    print(f"\n🎉 PERSISTED SESSION SYNC AUTOMATION PASSED SUCCESSFULLY FOR '{med_name}'!")

if __name__ == "__main__":
    main()
