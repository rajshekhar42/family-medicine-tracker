import sys
import os
import time
import argparse

# Add parent directory to sys.path to access shared page objects
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from adb_helper import run_adb, find_element, tap, dismiss_permission_dialogs, wait_for_element
from home_page import HomePage
from onboarding_page import OnboardingPage

def main():
    parser = argparse.ArgumentParser(description="Test caretaker pairing request step only")
    parser.add_argument('--emulator', default='emulator-5554', help='Parent device (emulator) ID')
    parser.add_argument('--physical', default='51071JEBF16934', help='Caretaker device (physical) ID')
    parser.add_argument('--parent-code', default=None, help='Parent App Code (optional, will fetch from parent device if not provided)')
    args = parser.parse_args()

    parent_id = args.emulator
    caretaker_id = args.physical
    parent_app_code = args.parent_code

    print("============================================================")
    print("🤖 STANDALONE CARETAKER PAIRING REQUEST TEST")
    print(f"   Parent     (Emulator): {parent_id}")
    print(f"   Caretaker  (Physical): {caretaker_id}")
    print("============================================================")
    
    parent_home = HomePage(parent_id)
    caretaker_home = HomePage(caretaker_id)

    # If parent_app_code is not provided, fetch it from parent
    if not parent_app_code:
        print("\n--- STEP 1: Retrieve Parent App Code from Parent Device ---")
        parent_home.open_drawer()
        parent_app_code = parent_home.get_app_code()
        if not parent_app_code:
            print("❌ CRITICAL: Failed to get Parent's App Code. Aborting.")
            sys.exit(1)
        print(f"Parent App Code retrieved: {parent_app_code}")
        parent_home.close_drawer()
        time.sleep(2)

    # ================================================================
    # STEP 2: Caretaker Requests Pairing
    # ================================================================
    print("\n--- STEP 2: Caretaker Requests Pairing ---")
    caretaker_home.open_drawer()
    caretaker_home.enter_parent_app_code(parent_app_code, "Parent Shekhar")
    caretaker_home.close_drawer()
    print("\n🎉 STANDALONE CARETAKER PAIRING REQUEST INITIATED SUCCESSFULLY!")

if __name__ == "__main__":
    main()
