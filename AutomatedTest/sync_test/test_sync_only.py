import sys
import os
import time
import argparse
import threading

# Add parent directory to sys.path to access shared page objects
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from adb_helper import run_adb, find_element, tap, dismiss_permission_dialogs, wait_for_element
from home_page import HomePage
from add_medicine_page import AddMedicinePage
from medicine_list_page import MedicineListPage
from history_page import HistoryPage
from onboarding_page import OnboardingPage


def run_parallel(fns):
    """Run a list of zero-arg callables in parallel daemon threads.
    Blocks until all threads finish. Re-raises the first BaseException
    (including SystemExit) that any thread raised."""
    errors = []
    lock = threading.Lock()

    def wrapped(fn):
        try:
            fn()
        except BaseException as exc:
            with lock:
                if not errors:
                    errors.append(exc)

    threads = [threading.Thread(target=wrapped, args=(fn,), daemon=True) for fn in fns]
    for t in threads:
        t.start()
    for t in threads:
        t.join()

    if errors:
        raise errors[0]


def main():
    parser = argparse.ArgumentParser(description="Sync-only test — pre-logged session required on both devices")
    parser.add_argument('--emulator', default='emulator-5554', help='Parent device (emulator) ID')
    parser.add_argument('--physical', default='51071JEBF16934', help='Caretaker device (physical) ID')
    args = parser.parse_args()

    parent_id = args.emulator
    caretaker_id = args.physical

    print("============================================================")
    print("🤖 SYNC ONLY TEST SUITE")
    print(f"   Parent     (Emulator): {parent_id}")
    print(f"   Caretaker  (Physical): {caretaker_id}")
    print("   Pre-requisite: Fresh install of app with database wiped out")
    print("============================================================")
    time.sleep(2)

    parent_home = HomePage(parent_id)
    caretaker_home = HomePage(caretaker_id)
    parent_add_med = AddMedicinePage(parent_id)
    caretaker_add_med = AddMedicinePage(caretaker_id)
    parent_med_list = MedicineListPage(parent_id)
    caretaker_med_list = MedicineListPage(caretaker_id)
    parent_history = HistoryPage(parent_id)
    caretaker_history = HistoryPage(caretaker_id)

    # ================================================================
    # STEP 0: Onboarding (PARALLEL — both devices simultaneously)
    # ================================================================
    print("\n--- STEP 0: Complete onboarding on both devices (parallel) ---")

    def onboard_parent():
        dismiss_permission_dialogs(parent_id)
        p_onboarding = OnboardingPage(parent_id)
        p_onboarding.enter_profile_name("Parent Userrrrr")
        p_onboarding.select_profile_type(is_caretaker=False)
        p_onboarding.submit()

    def onboard_caretaker():
        dismiss_permission_dialogs(caretaker_id)
        c_onboarding = OnboardingPage(caretaker_id)
        c_onboarding.enter_profile_name("Cccccaretaker User")
        c_onboarding.select_profile_type(is_caretaker=True)
        c_onboarding.submit()

    run_parallel([onboard_parent, onboard_caretaker])
    time.sleep(3)  # Allow UI to transition to Home screen on both devices

    # ================================================================
    # STEP 0.1 + 0.2: Add & Log Doses on BOTH devices (PARALLEL)
    # ================================================================
    print("\n--- STEP 0.1 + 0.2 (PARALLEL): Add & Log Doses on Both Devices ---")
    ts_pre = int(time.time())
    p_med1 = f"ParentPreMed1{ts_pre}"
    p_med2 = f"ParentPreMed2{ts_pre}"
    c_med1 = f"CaretakerPreMed1{ts_pre}"
    c_med2 = f"CaretakerPreMed2{ts_pre}"

    def add_parent_pre_meds():
        print(f"\n--- STEP 0.1: Add & Log Doses in Parent App ---")
        print(f"[{parent_id}] Adding medicine 1: '{p_med1}'...")
        parent_home.tap_add_medicine_fab()
        parent_add_med.add_medicine(p_med1, "Once a Day")
        time.sleep(1.5)

        print(f"[{parent_id}] Adding medicine 2: '{p_med2}'...")
        parent_home.tap_add_medicine_fab()
        parent_add_med.add_medicine(p_med2, "Once a Day")
        time.sleep(1.5)

        print(f"[{parent_id}] Marking '{p_med1}' as Taken...")
        parent_home.take_dose(p_med1)
        time.sleep(1.5)

        print(f"[{parent_id}] Marking '{p_med2}' as Skipped...")
        parent_home.skip_dose(p_med2)
        time.sleep(1.5)

    def add_caretaker_pre_meds():
        print(f"\n--- STEP 0.2: Add & Log Doses in Caretaker App ---")
        print(f"[{caretaker_id}] Adding medicine 1: '{c_med1}'...")
        caretaker_home.tap_add_medicine_fab()
        caretaker_add_med.add_medicine(c_med1, "Once a Day")
        time.sleep(1.5)

        print(f"[{caretaker_id}] Adding medicine 2: '{c_med2}'...")
        caretaker_home.tap_add_medicine_fab()
        caretaker_add_med.add_medicine(c_med2, "Once a Day")
        time.sleep(1.5)

        print(f"[{caretaker_id}] Marking '{c_med1}' as Taken...")
        caretaker_home.take_dose(c_med1)
        time.sleep(1.5)

        print(f"[{caretaker_id}] Marking '{c_med2}' as Skipped...")
        caretaker_home.skip_dose(c_med2)
        time.sleep(1.5)

    run_parallel([add_parent_pre_meds, add_caretaker_pre_meds])

    # ================================================================
    # STEP 0.5: Verify Google Sign-In (PARALLEL — both devices simultaneously)
    # ================================================================
    print("\n--- STEP 0.5: Verify Google Sign-In (parallel) ---")

    def sign_in_parent_device():
        parent_home.open_drawer()
        already_signed_in = parent_home.trigger_google_login()
        if not already_signed_in:
            print(f"[{parent_id}] Google login triggered. Selecting account...")
            parent_home.select_google_account("rajshekhardev@gmail.com")
            # Verify signed in — drawer should show "MY APP CODE"
            app_code_label = wait_for_element(parent_id, "MY APP CODE", timeout=25)
            if not app_code_label:
                print(f"[{parent_id}] ⚠️ First Google Sign-In attempt pending. Retrying sign-in trigger...")
                parent_home.trigger_google_login()
                parent_home.select_google_account("rajshekhardev@gmail.com")
                app_code_label = wait_for_element(parent_id, "MY APP CODE", timeout=25)

            if app_code_label:
                print(f"[{parent_id}] ✅ Google login confirmed and App code generated.")
            else:
                print(f"[{parent_id}] ❌ Failed to log in to Google.")
                sys.exit(1)
        else:
            print(f"[{parent_id}] ✅ Google login confirmed and App code generated.")
        parent_home.close_drawer()

    def sign_in_caretaker_device():
        caretaker_home.open_drawer()
        already_signed_in = caretaker_home.trigger_google_login()
        if not already_signed_in:
            print(f"[{caretaker_id}] Google login triggered. Selecting account...")
            caretaker_home.select_google_account("rajshekhar53@gmail.com")
            # Verify signed in
            app_code_label = wait_for_element(caretaker_id, "MY APP CODE", timeout=25)
            if not app_code_label:
                print(f"[{caretaker_id}] ⚠️ First Google Sign-In attempt pending. Retrying sign-in trigger...")
                caretaker_home.trigger_google_login()
                caretaker_home.select_google_account("rajshekhar53@gmail.com")
                app_code_label = wait_for_element(caretaker_id, "MY APP CODE", timeout=25)

            if app_code_label:
                print(f"[{caretaker_id}] ✅ Google login confirmed and App code generated.")
            else:
                print(f"[{caretaker_id}] ❌ Failed to log in to Google.")
                sys.exit(1)
        else:
            print(f"[{caretaker_id}] ✅ Google login confirmed and App code generated.")
        caretaker_home.close_drawer()

    run_parallel([sign_in_parent_device, sign_in_caretaker_device])

    # STEP 0.51: Verify App Codes are Different on Both Devices
    print("\n--- STEP 0.51: Verify App Codes are Different on Both Devices ---")
    # Retrieve app codes from both devices (sequential — needed for comparison)
    parent_home.open_drawer()
    parent_app_code = parent_home.get_app_code()
    parent_home.close_drawer()
    caretaker_home.open_drawer()
    caretaker_app_code = caretaker_home.get_app_code()
    caretaker_home.close_drawer()
    if not parent_app_code or not caretaker_app_code:
        print("❌ Failed to retrieve app codes on one or both devices.")
        sys.exit(1)
    print(f"[{parent_id}] Parent App Code: {parent_app_code}")
    print(f"[{caretaker_id}] Caretaker App Code: {caretaker_app_code}")
    if parent_app_code == caretaker_app_code:
        print("❌ App codes are identical; expected different codes.")
        sys.exit(1)
    else:
        print("✅ App codes are different as expected.")

    # ================================================================
    # STEP 0.6: Verify Local Medicines Persisted After Google Sign-In (PARALLEL)
    # ================================================================
    print("\n--- STEP 0.6: Verify Local Medicines Persisted After Google Sign-In (parallel) ---")

    def verify_parent_pre_login_meds():
        print(f"[{parent_id}] Verifying pre-login medicines in Parent App...")
        parent_home.navigate_to_medicine_list()
        parent_med_list.verify_medicine_exists(p_med1)
        parent_med_list.verify_medicine_exists(p_med2)
        parent_home.go_back()

        parent_home.navigate_to_history()
        parent_history.verify_history_contains(p_med1, should_be_taken=True)
        parent_history.verify_history_contains(p_med2, should_be_skipped=True)
        parent_home.go_back()
        print(f"[{parent_id}] ✅ Verified: Pre-login medicines '{p_med1}' (Taken) & '{p_med2}' (Skipped) persisted after Google Sign-In.")

    def verify_caretaker_pre_login_meds():
        print(f"[{caretaker_id}] Verifying pre-login medicines in Caretaker App...")
        # Ensure caretaker is on their own profile since Google Sign-In could auto-select a parent profile
        print(f"[{caretaker_id}] Switching to Caretaker Owner Profile to verify local medicines...")
        caretaker_home.open_drawer()
        caretaker_tile = find_element(caretaker_id, "Caretaker User")
        if caretaker_tile:
            tap(caretaker_id, caretaker_tile[0], caretaker_tile[1])
        else:
            tap(caretaker_id, 300, 250)
        time.sleep(2)

        caretaker_home.navigate_to_medicine_list()
        caretaker_med_list.verify_medicine_exists(c_med1)
        caretaker_med_list.verify_medicine_exists(c_med2)
        caretaker_home.go_back()

        caretaker_home.navigate_to_history()
        caretaker_history.verify_history_contains(c_med1, should_be_taken=True)
        caretaker_history.verify_history_contains(c_med2, should_be_skipped=True)
        caretaker_home.go_back()
        print(f"[{caretaker_id}] ✅ Verified: Pre-login medicines '{c_med1}' (Taken) & '{c_med2}' (Skipped) persisted after Google Sign-In.")

    run_parallel([verify_parent_pre_login_meds, verify_caretaker_pre_login_meds])

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
    # STEP 2.5: Verify Caretaker does NOT receive the approval banner
    # ================================================================
    print("\n--- STEP 2.5: Verify Approval Banner is NOT Displayed on Caretaker ---")
    time.sleep(3)  # Wait for RTDB sync stream to update
    caretaker_banner = find_element(caretaker_id, "Accept")
    if caretaker_banner:
        print(f"[{caretaker_id}] ❌ FAIL: Pairing approval banner was incorrectly displayed on Caretaker's screen!")
        sys.exit(1)
    else:
        print(f"[{caretaker_id}] ✅ VERIFIED: Pairing approval banner is NOT displayed on Caretaker's screen.")

    # ================================================================
    # STEP 2.6: Verify Caretaker App shows "Pending Approval" status
    # ================================================================
    print("\n--- STEP 2.6: Verify Caretaker shows 'Pending Approval' for Parent profile ---")
    caretaker_home.open_drawer()
    time.sleep(2)
    parent_tile = find_element(caretaker_id, "Parent Shekhar")
    pending_badge = find_element(caretaker_id, "Pending Approval")
    if parent_tile and pending_badge:
        print(f"[{caretaker_id}] ✅ VERIFIED: Parent profile shows 'Pending Approval' status in the Caretaker's profile drawer.")
    else:
        print(f"[{caretaker_id}] ❌ FAIL: Caretaker app did not show 'Pending Approval' status (parent_tile: {parent_tile}, pending_badge: {pending_badge})")
        caretaker_home.close_drawer()
        sys.exit(1)
    caretaker_home.close_drawer()

    # ================================================================
    # STEP 2.7: Verify Pairing Banner Persistence on App Reopen
    # ================================================================
    print("\n--- STEP 2.7: Verify Pairing Banner Persistence on App Reopen ---")
    # Verify banner is visible before reopen
    accept_btn_before = find_element(parent_id, "Accept")
    if not accept_btn_before:
        print(f"[{parent_id}] ❌ FAIL: Pairing banner not visible on Parent's screen before closing app!")
        sys.exit(1)

    print(f"[{parent_id}] Force-closing Parent app...")
    run_adb(parent_id, ["shell", "am", "force-stop", "org.medimitra.family_medicine_tracker"])
    time.sleep(2)

    print(f"[{parent_id}] Reopening Parent app...")
    run_adb(parent_id, ["shell", "monkey", "-p", "org.medimitra.family_medicine_tracker", "-c", "android.intent.category.LAUNCHER", "1"])
    time.sleep(8)  # Wait for startup RTDB linking and sync to run

    accept_btn_after = find_element(parent_id, "Accept")
    if accept_btn_after:
        print(f"[{parent_id}] ✅ VERIFIED: Pairing banner persists and is visible after reopening the app.")
    else:
        print(f"[{parent_id}] ❌ FAIL: Pairing banner disappeared after reopening the app!")
        sys.exit(1)

    # ================================================================
    # STEP 3: Parent Accepts Pairing Request
    # ================================================================
    print("\n--- STEP 3: Parent Accepts Connection Banner ---")
    # The pairing confirmation appears as a banner on the parent's Home screen
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
    # STEP 3.5: Verify Parent Profile is Visible in Caretaker Profile Menu
    # ================================================================
    print("\n--- STEP 3.5: Verify Parent Profile Visible in Caretaker Profile Menu ---")
    time.sleep(4)  # Allow RTDB stream and state to update
    caretaker_home.open_drawer()
    time.sleep(1.5)
    parent_tile = find_element(caretaker_id, "Parent User") or find_element(caretaker_id, "Parent Shekhar") or find_element(caretaker_id, "Shekhar")
    pending_badge = find_element(caretaker_id, "Pending Approval")
    if parent_tile and not pending_badge:
        print(f"[{caretaker_id}] ✅ VERIFIED: Connected Parent profile is visible and active (no 'Pending Approval' badge) in Caretaker profile menu.")
    elif parent_tile:
        print(f"[{caretaker_id}] ✅ VERIFIED: Connected Parent profile is visible in Caretaker profile menu.")
    else:
        print(f"[{caretaker_id}] ❌ FAIL: Connected Parent profile was NOT found in Caretaker profile menu after acceptance.")
        caretaker_home.close_drawer()
        sys.exit(1)

    # ================================================================
    # STEP 4: Switch to Parent Profile on Caretaker
    # ================================================================
    print("\n--- STEP 4: Switch to Parent Profile on Caretaker ---")
    if parent_tile:
        print(f"[{caretaker_id}] Tapping Parent profile tile at {parent_tile}...")
        tap(caretaker_id, parent_tile[0], parent_tile[1])
    else:
        print(f"[{caretaker_id}] ⚠️ Parent tile text not matched, tapping fallback (399, 847)...")
        tap(caretaker_id, 399, 847)
    time.sleep(2)

    # ================================================================
    # STEP 4.1: Verify Local Medicines Persisted After Pairing
    # ================================================================
    print("\n--- STEP 4.1: Verify Local Medicines Persisted After Pairing ---")

    # Restart both apps in PARALLEL to align calendar / home screen dates with current system date
    print("\n🔄 Restarting both apps in parallel to align calendar dates with current day...")

    def restart_app(device_id):
        run_adb(device_id, ["shell", "am", "force-stop", "org.medimitra.family_medicine_tracker"])
        time.sleep(0.5)
        run_adb(device_id, ["shell", "am", "start", "-S", "-n",
                 "org.medimitra.family_medicine_tracker/org.medimitra.family_medicine_tracker.MainActivity"])

    run_parallel([lambda: restart_app(parent_id), lambda: restart_app(caretaker_id)])
    print("⏳ Waiting 10s for both apps to fully render after restart...")
    time.sleep(10)

    # Verify BOTH devices in PARALLEL
    def verify_parent_post_pairing():
        print(f"[{parent_id}] Verifying pre-pairing medicines in Parent App...")
        parent_home.navigate_to_medicine_list()
        parent_med_list.verify_medicine_exists(p_med1)
        parent_med_list.verify_medicine_exists(p_med2)
        parent_home.go_back()

        parent_home.navigate_to_history()
        parent_history.verify_history_contains(p_med1, should_be_taken=True)
        parent_history.verify_history_contains(p_med2, should_be_skipped=True)
        parent_home.go_back()
        print(f"[{parent_id}] ✅ Verified: Pre-pairing medicines '{p_med1}' (Taken) & '{p_med2}' (Skipped) persisted after Pairing.")

    def verify_caretaker_post_pairing():
        # Switch Caretaker active profile to Caretaker Owner Profile to check local owner data
        print(f"[{caretaker_id}] Switching to Caretaker Owner Profile to verify local medicines...")
        caretaker_home.open_drawer()
        caretaker_tile = find_element(caretaker_id, "Caretaker User")
        if caretaker_tile:
            tap(caretaker_id, caretaker_tile[0], caretaker_tile[1])
        else:
            tap(caretaker_id, 300, 250)
        time.sleep(2)
        caretaker_home.close_drawer()

        caretaker_home.navigate_to_medicine_list()
        caretaker_med_list.verify_medicine_exists(c_med1)
        caretaker_med_list.verify_medicine_exists(c_med2)
        caretaker_home.go_back()

        caretaker_home.navigate_to_history()
        caretaker_history.verify_history_contains(c_med1, should_be_taken=True)
        caretaker_history.verify_history_contains(c_med2, should_be_skipped=True)
        caretaker_home.go_back()
        print(f"[{caretaker_id}] ✅ Verified: Pre-pairing medicines '{c_med1}' (Taken) & '{c_med2}' (Skipped) persisted after Pairing.")

    run_parallel([verify_parent_post_pairing, verify_caretaker_post_pairing])

    # Switch Caretaker active profile back to Parent Profile for STEP 5
    print(f"[{caretaker_id}] Switching active profile back to Parent Profile for sync tests...")
    caretaker_home.open_drawer()
    time.sleep(1.5)  # Wait for drawer animation to complete
    parent_tile = find_element(caretaker_id, "Parent User") or find_element(caretaker_id, "Parent Shekhar") or find_element(caretaker_id, "Shekhar")
    if parent_tile:
        print(f"[{caretaker_id}] Found Parent tile at {parent_tile}")
        tap(caretaker_id, parent_tile[0], parent_tile[1])
    else:
        print(f"[{caretaker_id}] Parent tile text not matched, tapping fallback (399, 847)...")
        tap(caretaker_id, 399, 847)
    time.sleep(2)

    # ================================================================
    # STEP 5: Add Medicine on Parent & Sync to Caretaker
    # ================================================================
    print("\n--- STEP 5: Add unique medicine on Parent and verify sync to Caretaker ---")
    timestamp = int(time.time())
    med_name = f"SyncMed{timestamp}"

    parent_home.tap_add_medicine_fab()
    parent_add_med.add_medicine(med_name, "Once a Day")
    time.sleep(1.5)

    # Mark dose as taken on Parent
    print(f"[{parent_id}] Marking dose as taken on Parent...")
    parent_home.take_dose(med_name)
    time.sleep(1.5)

    # Trigger push sync on Parent
    print(f"[{parent_id}] Triggering Parent 'Sync Now'...")
    parent_home.open_drawer()
    parent_sync_btn = find_element(parent_id, "Sync Now")
    if parent_sync_btn:
        tap(parent_id, parent_sync_btn[0], parent_sync_btn[1])
    else:
        print(f"[{parent_id}] ❌ 'Sync Now' button not found. Tapping fallback.")
        tap(parent_id, 300, 2210)
    print("⏳ Waiting 12s for parent push sync to complete...")
    time.sleep(12)
    parent_home.close_drawer()

    # Trigger pull sync on Caretaker
    print(f"[{caretaker_id}] Triggering Caretaker 'Sync Now'...")
    caretaker_home.open_drawer()
    caretaker_sync_btn = find_element(caretaker_id, "Sync Now")
    if caretaker_sync_btn:
        tap(caretaker_id, caretaker_sync_btn[0], caretaker_sync_btn[1])
    else:
        print(f"[{caretaker_id}] ❌ 'Sync Now' button not found. Tapping fallback.")
        tap(caretaker_id, 336, 2151)

    print("⏳ Waiting 12s for caretaker pull sync to complete...")
    time.sleep(12)
    caretaker_home.close_drawer()

    # ================================================================
    # STEP 6: Verify Medicine exists on Caretaker — Medicine List
    # ================================================================
    print(f"\n--- STEP 6: Verify '{med_name}' in Caretaker Medicine List ---")
    caretaker_home.navigate_to_medicine_list()
    caretaker_med_list = MedicineListPage(caretaker_id)
    caretaker_med_list.verify_medicine_exists(med_name)
    print(f"[{caretaker_id}] ✅ '{med_name}' verified in Medicine List.")
    caretaker_home.go_back()
    time.sleep(1.5)

    # ================================================================
    # STEP 7: Verify taken dose in Caretaker History
    # ================================================================
    print(f"\n--- STEP 7: Verify '{med_name}' taken in Caretaker History ---")
    caretaker_home.navigate_to_history()
    caretaker_history = HistoryPage(caretaker_id)
    caretaker_history.verify_history_contains(med_name, should_be_taken=True)
    print(f"[{caretaker_id}] ✅ '{med_name}' dose shows as Taken in Caretaker History.")
    caretaker_home.go_back()

    # ================================================================
    # STEP 8: Sync Integrity Verification (Caretaker additions vs Parent status)
    # ================================================================
    print("\n--- STEP 8: Sync Integrity Verification (Caretaker additions vs Parent status) ---")

    # 1. Caretaker adds Medicine A
    integrity_timestamp = int(time.time())
    med_name_a = f"IntegMedA{integrity_timestamp}"
    med_name_b = f"IntegMedB{integrity_timestamp}"

    print(f"[{caretaker_id}] Caretaker adding Medicine A: {med_name_a}")
    caretaker_home.navigate_to_medicine_list()
    time.sleep(1.5)
    add_btn = find_element(caretaker_id, "Add Medicine")
    if add_btn:
        tap(caretaker_id, add_btn[0], add_btn[1])
    else:
        tap(caretaker_id, 960, 2240)
    time.sleep(2)

    caretaker_add_med = AddMedicinePage(caretaker_id)
    caretaker_add_med.add_medicine(med_name_a, "Once a Day")

    print("⏳ Waiting 10s for automatic push sync of Medicine A...")
    time.sleep(10)
    caretaker_home.go_back()  # return to Home screen
    time.sleep(1.5)

    # 2. Verify Medicine A exists on Parent and Parent marks it as taken
    print(f"[{parent_id}] Verifying Medicine A exists on Parent...")
    parent_home.navigate_to_medicine_list()
    parent_med_list = MedicineListPage(parent_id)
    parent_med_list.verify_medicine_exists(med_name_a)
    print(f"[{parent_id}] ✅ Medicine A verified on Parent. Returning to Home...")
    parent_home.go_back()
    time.sleep(1.5)

    print(f"[{parent_id}] Parent marking Medicine A as Taken...")
    parent_home.take_dose(med_name_a)
    time.sleep(3)

    # 3. Caretaker adds Medicine B
    print(f"[{caretaker_id}] Caretaker adding Medicine B: {med_name_b}")
    caretaker_home.navigate_to_medicine_list()
    time.sleep(1.5)
    add_btn = find_element(caretaker_id, "Add Medicine")
    if add_btn:
        tap(caretaker_id, add_btn[0], add_btn[1])
    else:
        tap(caretaker_id, 960, 2240)
    time.sleep(2)

    caretaker_add_med.add_medicine(med_name_b, "Once a Day")

    print("⏳ Waiting 10s for automatic push sync of Medicine B...")
    time.sleep(10)
    caretaker_home.go_back()  # return to Home screen
    time.sleep(1.5)

    # 4. Verify Medicine B exists on Parent, and Medicine A's status remains Taken
    print(f"[{parent_id}] Verifying Medicine B exists on Parent...")
    parent_home.navigate_to_medicine_list()
    parent_med_list.verify_medicine_exists(med_name_b)
    print(f"[{parent_id}] ✅ Medicine B verified on Parent. Returning to Home...")
    parent_home.go_back()
    time.sleep(1.5)

    print(f"[{parent_id}] Verifying Medicine A '{med_name_a}' is still Taken on Parent...")
    parent_home.navigate_to_history()
    parent_history = HistoryPage(parent_id)
    parent_history.verify_history_contains(med_name_a, should_be_taken=True)
    print(f"[{parent_id}] ✅ VERIFIED: Medicine A '{med_name_a}' remains Taken in History (no sync undo!).")
    parent_home.go_back()

    # ================================================================
    # STEP 9: Parent Logout & Relogin Sync Verification
    # ================================================================
    print("\n--- STEP 9: Parent Logout & Relogin Sync Verification ---")
    print(f"[{parent_id}] Parent logging out...")
    parent_home.open_drawer()
    time.sleep(1.5)
    parent_app_code_before = parent_home.get_app_code()
    print(f"[{parent_id}] Parent App Code before logout: {parent_app_code_before}")
    sign_out_btn = find_element(parent_id, "Sign Out")
    if sign_out_btn:
        tap(parent_id, sign_out_btn[0], sign_out_btn[1])
        print(f"[{parent_id}] Tapped Sign Out button.")
    else:
        print(f"[{parent_id}] ⚠️ Sign Out button not found, tapping fallback (450, 2069)...")
        tap(parent_id, 450, 2069)
    time.sleep(3)
    parent_home.close_drawer()
    time.sleep(1.5)

    print(f"[{parent_id}] Parent logging back in with Google...")
    parent_home.open_drawer()
    time.sleep(1.5)
    logged_in = parent_home.trigger_google_login()
    parent_app_code_after = parent_home.get_app_code()
    print(f"[{parent_id}] Parent App Code after re-login: {parent_app_code_after}")
    parent_home.close_drawer()
    if not logged_in:
        print(f"[{parent_id}] ❌ Failed to log back in to Google on Parent.")
        sys.exit(1)

    if parent_app_code_before and parent_app_code_after:
        if parent_app_code_before == parent_app_code_after:
            print(f"[{parent_id}] ✅ VERIFIED: Parent App Code remained identical ({parent_app_code_before}) before & after logout/re-login.")
        else:
            raise Exception(f"[{parent_id}] ❌ Parent App Code CHANGED after logout/re-login! Before: '{parent_app_code_before}', After: '{parent_app_code_after}'")
    print(f"[{parent_id}] ✅ Parent logged back in successfully.")

    print(f"[{parent_id}] Parent adding post-relogin medicine...")
    timestamp_rel = int(time.time())
    relogin_med = f"ReloginMed{timestamp_rel}"
    parent_home.tap_add_medicine_fab()
    parent_add_med.add_medicine(relogin_med, "Once a Day")
    time.sleep(1.5)

    print(f"[{parent_id}] Parent triggering 'Sync Now' post-relogin...")
    parent_home.open_drawer()
    time.sleep(1.5)
    parent_home.trigger_sync_now()
    print("⏳ Waiting 12s for parent push sync to complete...")
    time.sleep(12)
    parent_home.close_drawer()

    print(f"[{caretaker_id}] Caretaker triggering 'Sync Now' post-relogin...")
    caretaker_home.open_drawer()
    time.sleep(1.5)
    caretaker_home.trigger_sync_now()
    print("⏳ Waiting 12s for caretaker pull sync to complete...")
    time.sleep(12)
    caretaker_home.close_drawer()

    print(f"[{caretaker_id}] Verifying post-relogin medicine '{relogin_med}' in Caretaker Medicine List...")
    caretaker_home.navigate_to_medicine_list()
    caretaker_med_list.verify_medicine_exists(relogin_med)
    print(f"[{caretaker_id}] ✅ VERIFIED: Post-relogin medicine '{relogin_med}' synced successfully to Caretaker!")
    caretaker_home.go_back()

    # ================================================================
    # STEP 10: Run Async & Offline Sync Test Suite
    # ================================================================
    print("\n--- STEP 10: Running async & offline sync test suite ---")
    import subprocess
    async_script = os.path.join(os.path.dirname(__file__), "test_sync_in_async_manner.py")
    cmd = [sys.executable, async_script, "--emulator", parent_id, "--physical", caretaker_id]
    print(f"Executing: {' '.join(cmd)}")
    res = subprocess.run(cmd)
    if res.returncode != 0:
        print(f"❌ test_sync_in_async_manner.py failed with exit code {res.returncode}")
        sys.exit(res.returncode)

    print("")
    print("============================================================")
    print(f"🎉 SYNC ONLY TEST SUITE PASSED SUCCESSFULLY for '{med_name}', '{med_name_a}'/'{med_name_b}', & '{relogin_med}'!")
    print("============================================================")


if __name__ == "__main__":
    main()
