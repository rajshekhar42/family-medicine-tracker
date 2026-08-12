import sys
import os
import time
import argparse
import re
import threading
import xml.etree.ElementTree as ET

# Add parent directory to sys.path to access shared page objects
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from adb_helper import run_adb, find_element, tap, type_text, wait_for_element, hide_keyboard, dismiss_permission_dialogs, get_dump
from home_page import HomePage
from add_medicine_page import AddMedicinePage
from medicine_list_page import MedicineListPage
from history_page import HistoryPage
from onboarding_page import OnboardingPage

APP_PACKAGE = "org.medimitra.family_medicine_tracker"
APP_ACTIVITY = f"{APP_PACKAGE}.MainActivity"


def set_internet(device_id: str, enable: bool):
    """Turns Wi-Fi and Cellular Data ON or OFF on the device via ADB."""
    state = "enable" if enable else "disable"
    print(f"[{device_id}] 🌐 Turning internet {state.upper()}...")
    run_adb(device_id, ["shell", "svc", "wifi", state])
    run_adb(device_id, ["shell", "svc", "data", state])
    if enable:
        print(f"[{device_id}] ⏳ Waiting 4s for Android network stack to re-establish...")
        time.sleep(4)
    else:
        time.sleep(2)


def clear_logcat(device_id: str):
    """Clears the ADB logcat buffer for clean monitoring."""
    print(f"[{device_id}] 🧹 Clearing logcat buffer...")
    run_adb(device_id, ["shell", "logcat", "-c"])


def verify_logcat_sync_payload(device_id: str, timeout: int = 15) -> bool:
    """
    Monitors logcat for confirmation that a sync payload was uploaded to Firebase.
    Looks for 'Uploaded sync payload', 'uploaded to slot', 'SyncRepo:', 'sync_payloads', or 'tableSyncQueue' logs.
    """
    print(f"[{device_id}] 🔍 Watching logcat for Firebase sync payload upload confirmation (up to {timeout}s)...")
    start = time.time()
    patterns = ["Uploaded sync payload", "uploaded to slot", "SyncRepo:", "sync_payloads", "tableSyncQueue"]
    while time.time() - start < timeout:
        out, _ = run_adb(device_id, ["shell", "logcat", "-d"])
        for pattern in patterns:
            if pattern in out:
                print(f"[{device_id}] ✅ CONFIRMED: Found logcat entry matching '{pattern}'!")
                return True
        time.sleep(2)
    print(f"[{device_id}] ⚠️ Logcat search did not find payload upload pattern within {timeout}s.")
    return False


def force_close_app(device_id: str):
    """Force-stops the app."""
    print(f"[{device_id}] 🛑 Force-stopping app...")
    run_adb(device_id, ["shell", "am", "force-stop", APP_PACKAGE])
    time.sleep(2)


def launch_app(device_id: str):
    """Launches the app on device and waits for startup rendering."""
    print(f"[{device_id}] 🚀 Launching app...")
    run_adb(device_id, ["shell", "am", "start", "-S", "-n", f"{APP_PACKAGE}/{APP_ACTIVITY}"])
    time.sleep(7)


def trigger_sync(device_id: str, home: HomePage, wait_time: int = 12):
    """
    Helper to trigger sync via profile drawer, waiting for Firebase auth state to settle.
    """
    print(f"[{device_id}] Triggering sync via drawer...")
    time.sleep(2)  # Ensure previous drawer animation is fully settled
    home.open_drawer()
    time.sleep(2)
    wait_for_element(device_id, "MY APP CODE", timeout=15)
    home.trigger_sync_now()
    time.sleep(wait_time)
    home.close_drawer()
    time.sleep(2)


def ensure_caretaker_on_parent_profile(caretaker_id: str, caretaker_home: HomePage, parent_name: str = "Parent"):
    """
    Ensures Caretaker active profile is set to the paired Parent profile (matching 'Parent').
    Differentiates between top header card (already active) vs list tile under PROFILES section.
    """
    print(f"[{caretaker_id}] Checking active profile contains '{parent_name}'...")
    time.sleep(2)
    caretaker_home.open_drawer()
    time.sleep(3)

    for attempt in range(4):
        try:
            dump_file = get_dump(caretaker_id)
            tree = ET.parse(dump_file)
            root = tree.getroot()

            is_already_active = False
            target_tile_coords = None

            for node in root.iter('node'):
                desc = node.attrib.get('content-desc', '')
                text = node.attrib.get('text', '')
                bounds = node.attrib.get('bounds', '')
                val = desc or text
                if parent_name.lower() in val.lower():
                    m = re.match(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', bounds)
                    if m:
                        top = int(m.group(2))
                        if top < 600:
                            # Top header card -> Parent profile is ALREADY active!
                            is_already_active = True
                            break
                        else:
                            # Tile in list below PROFILES section
                            target_tile_coords = (
                                (int(m.group(1)) + int(m.group(3))) // 2,
                                (int(m.group(2)) + int(m.group(4))) // 2
                            )

            if is_already_active:
                print(f"[{caretaker_id}] ✅ Profile matching '{parent_name}' is ALREADY active.")
                caretaker_home.close_drawer()
                time.sleep(2)
                return True
            elif target_tile_coords:
                print(f"[{caretaker_id}] Switching active profile to tile matching '{parent_name}' at {target_tile_coords}...")
                tap(caretaker_id, target_tile_coords[0], target_tile_coords[1])
                time.sleep(4)
                return True
            else:
                print(f"[{caretaker_id}] ⏳ Profile tile matching '{parent_name}' not ready yet, retrying (attempt {attempt + 1}/4)...")
                time.sleep(2)
        except Exception as e:
            print(f"[{caretaker_id}] Error in ensure_caretaker_on_parent_profile: {e}")
            time.sleep(2)

    print(f"[{caretaker_id}] ⚠️ Profile matching '{parent_name}' tile not found in drawer list after retries.")
    caretaker_home.close_drawer()
    time.sleep(2)
    return False




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


def clear_app_data(device_id: str):
    """Wipes app data to test clean reinstall / fresh setup state."""
    print(f"[{device_id}] 🧹 Wiping app data (pm clear)...")
    run_adb(device_id, ["shell", "am", "force-stop", APP_PACKAGE])
    run_adb(device_id, ["shell", "pm", "clear", APP_PACKAGE])
    time.sleep(3)


def ensure_internet_on_all(parent_id: str, caretaker_id: str):
    """Safety helper to restore internet on both devices."""
    print("🌐 Restoring internet connection on all devices...")
    set_internet(parent_id, True)
    set_internet(caretaker_id, True)


def ensure_paired(parent_id: str, caretaker_id: str, parent_home: HomePage, caretaker_home: HomePage):
    """
    Idempotent setup helper: ensures both devices are onboarded, Google logged in,
    and Caretaker is paired with Parent. Also clears any leftover inbox payloads.
    """
    print("\n--- SETUP: Ensuring Parent and Caretaker are logged in & paired ---")
    dismiss_permission_dialogs(parent_id)
    dismiss_permission_dialogs(caretaker_id)

    # 1. Onboarding check on Parent
    parent_dump = get_dump(parent_id)
    tree = ET.parse(parent_dump)
    if find_element(parent_id, "Welcome"):
        parent_onboarding = OnboardingPage(parent_id)
        parent_onboarding.enter_profile_name("Parent User")
        parent_onboarding.select_profile_type(is_caretaker=False)
        parent_onboarding.submit()
        time.sleep(3)

    # 2. Onboarding check on Caretaker
    caretaker_dump = get_dump(caretaker_id)
    if find_element(caretaker_id, "Welcome"):
        caretaker_onboarding = OnboardingPage(caretaker_id)
        caretaker_onboarding.enter_profile_name("Caretaker User")
        caretaker_onboarding.select_profile_type(is_caretaker=True)
        caretaker_onboarding.submit()
        time.sleep(3)

    # 3. Parent Google Sign-In
    parent_home.open_drawer()
    if not find_element(parent_id, "MY APP CODE"):
        already = parent_home.trigger_google_login("rajshekhardev@gmail.com")
        if not already:
            parent_home.select_google_account("rajshekhardev@gmail.com")
            wait_for_element(parent_id, "MY APP CODE", timeout=20)
    parent_app_code = parent_home.get_app_code()
    if not parent_app_code:
        print(f"[{parent_id}] Retrying Google Sign-In to obtain App Code...")
        parent_home.trigger_google_login("rajshekhardev@gmail.com")
        parent_app_code = parent_home.get_app_code()
    parent_home.close_drawer()

    if not parent_app_code:
        raise Exception(f"Failed to obtain Parent App Code on {parent_id}")

    # 4. Caretaker Google Sign-In
    caretaker_home.open_drawer()
    if not find_element(caretaker_id, "MY APP CODE"):
        already = caretaker_home.trigger_google_login("rajshekhar53@gmail.com")
        if not already:
            caretaker_home.select_google_account("rajshekhar53@gmail.com")
            wait_for_element(caretaker_id, "MY APP CODE", timeout=20)

    # Check if Caretaker already has Parent profile in profile drawer
    caretaker_home.open_drawer()
    parent_tile = find_element(caretaker_id, "Parent")
    if not parent_tile:
        print(f"[{caretaker_id}] Pairing Caretaker with Parent App Code: {parent_app_code}...")
        caretaker_home.enter_parent_app_code(parent_app_code, "Parent Shekhar")
        caretaker_home.close_drawer()

        # Parent accepts connection on Home screen
        print(f"[{parent_id}] Waiting for connection request banner on Home screen...")
        parent_home.close_drawer()
        accepted = False
        for attempt in range(5):
            time.sleep(3)
            accepted = parent_home.accept_connection_request()
            if accepted:
                print(f"[{parent_id}] ✅ Connection request accepted successfully!")
                break
    else:
        caretaker_home.close_drawer()



    # Always ensure Caretaker active profile is set to Parent Shekhar
    ensure_caretaker_on_parent_profile(caretaker_id, caretaker_home)


    # Clear any lingering unconsumed RTDB inbox payloads from prior test runs
    print(f"[{caretaker_id}] Clearing any leftover inbox payloads via Caretaker sync...")
    trigger_sync(caretaker_id, caretaker_home, wait_time=8)

def cleanup_sqlite_db(device_id: str):
    """Cleans up accumulated old test medicines from SQLite DB without logging out user."""
    try:
        tmp_path = f"tmp/{device_id}_clean.db"
        os.makedirs("tmp", exist_ok=True)
        res = subprocess.run(f'adb -s {device_id} shell "run-as {APP_PACKAGE} cat databases/medicine_tracker.db" > {tmp_path}', shell=True, capture_output=True)
        if res.returncode == 0 and os.path.exists(tmp_path) and os.path.getsize(tmp_path) > 0:
            conn = sqlite3.connect(tmp_path)
            c = conn.cursor()
            c.execute("DELETE FROM medicines WHERE name LIKE '%1786%' OR name LIKE 'TestMedDump' OR name LIKE 'ParentOffMed%' OR name LIKE 'ManualMed%' OR name LIKE 'CaretakerOffMed%' OR name LIKE 'ParentAsyncMed%' OR name LIKE 'LogoutMed%' OR name LIKE 'LoginMed%';")
            c.execute("DELETE FROM schedules WHERE medicine_id NOT IN (SELECT id FROM medicines);")
            c.execute("DELETE FROM medicine_log WHERE 1=1;")
            conn.commit()
            conn.close()
            subprocess.run(f'adb -s {device_id} push {tmp_path} /data/local/tmp/{device_id}.db', shell=True, capture_output=True)
            subprocess.run(f'adb -s {device_id} shell "run-as {APP_PACKAGE} cp /data/local/tmp/{device_id}.db databases/medicine_tracker.db"', shell=True, capture_output=True)
            subprocess.run(f'adb -s {device_id} shell am force-stop {APP_PACKAGE}', shell=True, capture_output=True)
            subprocess.run(f'adb -s {device_id} shell monkey -p {APP_PACKAGE} 1', shell=True, capture_output=True)
            time.sleep(2)
            print(f"[{device_id}] 🧹 Cleaned up old test medicines from SQLite DB.")
    except Exception as e:
        print(f"[{device_id}] Note: SQLite cleanup skipped: {e}")


def main():

    parser = argparse.ArgumentParser(description="Offline & Async Sync Test Suite")
    parser.add_argument('--emulator', default='emulator-5554', help='Parent device ID')
    parser.add_argument('--physical', default='emulator-5556', help='Caretaker device ID')
    args = parser.parse_args()

    parent_id = args.emulator
    caretaker_id = args.physical

    print("============================================================")
    print("🤖 OFFLINE & ASYNC SYNC TEST SUITE")
    print(f"   Parent   : {parent_id}")
    print(f"   Caretaker: {caretaker_id}")
    print("============================================================")

    parent_home = HomePage(parent_id)
    caretaker_home = HomePage(caretaker_id)
    parent_add_med = AddMedicinePage(parent_id)
    caretaker_add_med = AddMedicinePage(caretaker_id)
    parent_med_list = MedicineListPage(parent_id)
    caretaker_med_list = MedicineListPage(caretaker_id)
    parent_history = HistoryPage(parent_id)
    caretaker_history = HistoryPage(caretaker_id)

    try:
        # Guarantee internet ON at start
        ensure_internet_on_all(parent_id, caretaker_id)

        # Cleanup accumulated test medicines from SQLite in parallel for both devices
        run_parallel([lambda: cleanup_sqlite_db(parent_id), lambda: cleanup_sqlite_db(caretaker_id)])

        # Step 0: Ensure pairing state
        ensure_paired(parent_id, caretaker_id, parent_home, caretaker_home)

        # ================================================================
        # TEST CASE 1: Parent Offline Operations (Multiple Meds) -> App Close -> Internet ON -> App Open Auto-Sync
        # ================================================================
        print("\n--- TEST CASE 1: Parent Offline Operations (Multiple Meds) -> App Close -> Internet ON -> App Open Auto-Sync ---")
        ts1 = int(time.time())
        p_off_med1 = f"ParentOffMed1{ts1}"

        # 1. Turn OFF internet on Parent
        set_internet(parent_id, False)

        # 2. Add medicine on Parent while offline
        print(f"[{parent_id}] Adding offline medicine: {p_off_med1}...")
        parent_home.tap_add_medicine_fab()
        parent_add_med.add_medicine(p_off_med1, "Once a Day")
        time.sleep(2.5)

        # 3. Mark dose as taken on Parent while offline
        print(f"[{parent_id}] Marking '{p_off_med1}' as Taken while offline...")
        parent_home.take_dose(p_off_med1)
        time.sleep(1.5)

        # 4. Close Parent app
        force_close_app(parent_id)

        # 5. Turn ON internet on Parent
        set_internet(parent_id, True)

        # 6. Clear logcat & open Parent app
        clear_logcat(parent_id)
        launch_app(parent_id)

        # 7. Trigger push sync on Parent
        trigger_sync(parent_id, parent_home, wait_time=12)

        verify_logcat_sync_payload(parent_id, timeout=10)

        # 8. Open Caretaker app, ensure Parent Shekhar profile selected & trigger pull sync
        force_close_app(caretaker_id)
        launch_app(caretaker_id)
        ensure_caretaker_on_parent_profile(caretaker_id, caretaker_home)
        trigger_sync(caretaker_id, caretaker_home, wait_time=12)

        print(f"[{caretaker_id}] Verifying synced offline medicine '{p_off_med1}' on Caretaker...")
        caretaker_home.navigate_to_medicine_list()
        caretaker_med_list.verify_medicine_exists(p_off_med1)
        caretaker_home.go_back()

        caretaker_home.navigate_to_history()
        caretaker_history.verify_history_contains(p_off_med1, should_be_taken=True)
        caretaker_home.go_back()

        print("✅ TEST CASE 1 PASSED: Parent offline dose synced successfully after internet reconnection & sync!")

        # Clear inbox after Test Case 1
        trigger_sync(caretaker_id, caretaker_home, wait_time=6)

        # ================================================================
        # TEST CASE 2: Caretaker Offline -> Parent Takes Doses -> Firebase Upload -> Caretaker Reconnects & Auto-Syncs
        # ================================================================
        print("\n--- TEST CASE 2: Caretaker Offline -> Parent Takes Doses -> Firebase Upload -> Caretaker Reconnects & Auto-Syncs ---")
        ts2 = int(time.time())
        p_async_med3 = f"ParentAsyncMed3{ts2}"

        # 1. Turn OFF internet on Caretaker (Parent internet stays ON)
        set_internet(caretaker_id, False)

        # 2. Parent adds & takes medicine while Caretaker is offline
        print(f"[{parent_id}] Adding medicine: {p_async_med3}...")
        parent_home.tap_add_medicine_fab()
        parent_add_med.add_medicine(p_async_med3, "Once a Day")
        time.sleep(2.5)

        clear_logcat(parent_id)
        print(f"[{parent_id}] Marking '{p_async_med3}' as Taken...")
        parent_home.take_dose(p_async_med3)
        time.sleep(1.5)

        trigger_sync(parent_id, parent_home, wait_time=8)

        # 3. Verify Parent uploaded sync payload to Firebase (stored in recipient RTDB inbox)
        payload_uploaded = verify_logcat_sync_payload(parent_id, timeout=10)
        print(f"[{parent_id}] Firebase inbox upload status: {payload_uploaded}")

        # 4. Re-enable internet on Caretaker
        set_internet(caretaker_id, True)

        # 5. Launch Caretaker app, ensure Parent Shekhar profile selected & Pull Sync
        force_close_app(caretaker_id)
        launch_app(caretaker_id)
        ensure_caretaker_on_parent_profile(caretaker_id, caretaker_home)
        trigger_sync(caretaker_id, caretaker_home, wait_time=10)

        # 6. Verify Caretaker receives and displays the medicine & taken status
        print(f"[{caretaker_id}] Verifying receipt of async medicine '{p_async_med3}' on Caretaker...")
        caretaker_home.navigate_to_medicine_list()
        caretaker_med_list.verify_medicine_exists(p_async_med3)
        caretaker_home.go_back()

        caretaker_home.navigate_to_history()
        caretaker_history.verify_history_contains(p_async_med3, should_be_taken=True)
        caretaker_home.go_back()

        print("✅ TEST CASE 2 PASSED: Parent uploaded payload to Firebase while Caretaker was offline, Caretaker synced upon reconnecting!")

        # Clear inbox after Test Case 2
        trigger_sync(caretaker_id, caretaker_home, wait_time=6)

        # ================================================================
        # TEST CASE 3: Parent Offline Manual Sync -> Internet ON -> Manual Sync Upload
        # ================================================================
        print("\n--- TEST CASE 3: Parent Offline Manual Sync -> Internet ON -> Manual Sync Upload ---")
        ts3 = int(time.time())
        manual_med5 = f"ManualMed5{ts3}"

        # 1. Turn OFF internet on Parent
        set_internet(parent_id, False)

        # 2. Add & mark dose as Skipped on Parent
        parent_home.tap_add_medicine_fab()
        parent_add_med.add_medicine(manual_med5, "Once a Day")
        time.sleep(2.5)
        parent_home.skip_dose(manual_med5)
        time.sleep(1.5)

        # 3. Attempt manual sync while offline — verify graceful handling
        print(f"[{parent_id}] Attempting manual 'Sync Now' while offline...")
        parent_home.open_drawer()
        time.sleep(2)
        parent_home.trigger_sync_now()
        time.sleep(3)
        parent_home.close_drawer()

        # 4. Turn ON internet on Parent
        set_internet(parent_id, True)

        # 5. Manual Sync on Parent with internet ON
        clear_logcat(parent_id)
        trigger_sync(parent_id, parent_home, wait_time=8)

        # 6. Verify sync payload upload and receipt on Caretaker
        verify_logcat_sync_payload(parent_id, timeout=10)
        ensure_caretaker_on_parent_profile(caretaker_id, caretaker_home)
        trigger_sync(caretaker_id, caretaker_home, wait_time=8)

        caretaker_home.navigate_to_history()
        caretaker_history.verify_history_contains(manual_med5, should_be_skipped=True)
        caretaker_home.go_back()

        print("✅ TEST CASE 3 PASSED: Manual sync offline handled gracefully, manual sync online uploaded payload successfully!")

        # Clear inbox after Test Case 3
        trigger_sync(caretaker_id, caretaker_home, wait_time=6)

        # ================================================================
        # TEST CASE 4: Caretaker Offline Operations & Startup Auto-Push Sync
        # ================================================================
        print("\n--- TEST CASE 4: Caretaker Offline Operations & Startup Auto-Push Sync ---")
        ts4 = int(time.time())
        ct_med6 = f"CaretakerOffMed6{ts4}"

        # 1. Turn OFF internet on Caretaker
        set_internet(caretaker_id, False)

        # 2. Caretaker adds medicine for Parent profile while offline
        ensure_caretaker_on_parent_profile(caretaker_id, caretaker_home)
        print(f"[{caretaker_id}] Caretaker adding medicine for Parent while offline: {ct_med6}...")
        caretaker_home.navigate_to_medicine_list()
        time.sleep(2)
        add_btn = find_element(caretaker_id, "Add Medicine")
        if add_btn:
            tap(caretaker_id, add_btn[0], add_btn[1])
        else:
            tap(caretaker_id, 960, 2240)
        time.sleep(2)
        caretaker_add_med.add_medicine(ct_med6, "Once a Day")
        time.sleep(2)
        caretaker_home.go_back()

        # 3. Close Caretaker app & turn ON internet
        force_close_app(caretaker_id)
        set_internet(caretaker_id, True)

        # 4. Open Caretaker app & trigger push sync
        clear_logcat(caretaker_id)
        launch_app(caretaker_id)
        ensure_caretaker_on_parent_profile(caretaker_id, caretaker_home)
        trigger_sync(caretaker_id, caretaker_home, wait_time=10)

        # 5. Verify payload upload on Caretaker and receipt on Parent
        verify_logcat_sync_payload(caretaker_id, timeout=10)

        print(f"[{parent_id}] Verifying '{ct_med6}' synced to Parent Medicine List...")
        trigger_sync(parent_id, parent_home, wait_time=8)

        parent_home.navigate_to_medicine_list()
        parent_med_list.verify_medicine_exists(ct_med6)
        parent_home.go_back()

        print("✅ TEST CASE 4 PASSED: Caretaker offline additions push-synced to Parent on startup after reconnecting!")

        # Clear inbox after Test Case 4
        trigger_sync(parent_id, parent_home, wait_time=6)

        # ================================================================
        # TEST CASE 5: Parent Logout -> Offline Mark Taken -> Login -> Online Mark Taken -> Full Sync
        # ================================================================
        print("\n--- TEST CASE 5: Parent Logout -> Offline Mark Taken -> Login -> Online Mark Taken -> Full Sync ---")
        ts5 = int(time.time())
        logout_med7 = f"LogoutMed7{ts5}"
        login_med8 = f"LoginMed8{ts5}"

        # 1. Parent logs out via Profile Menu
        print(f"[{parent_id}] Parent logging out...")
        parent_home.open_drawer()
        parent_app_code_before = parent_home.get_app_code()
        print(f"[{parent_id}] Parent App Code before logout: {parent_app_code_before}")
        sign_out_btn = find_element(parent_id, "Sign Out")
        if sign_out_btn:
            tap(parent_id, sign_out_btn[0], sign_out_btn[1])
        else:
            tap(parent_id, 750, 750)
        time.sleep(3)
        parent_home.close_drawer()
        time.sleep(2)
        dismiss_permission_dialogs(parent_id)


        # 2. Add & mark dose taken while logged out
        print(f"[{parent_id}] Adding medicine 7 while logged out: {logout_med7}...")
        parent_home.tap_add_medicine_fab()
        parent_add_med.add_medicine(logout_med7, "Once a Day")
        time.sleep(2.5)
        parent_home.take_dose(logout_med7)
        time.sleep(1.5)

        # 3. Log in again via Google Sign-In
        print(f"[{parent_id}] Logging back in with Google...")
        parent_home.open_drawer()
        parent_home.trigger_google_login("rajshekhardev@gmail.com")
        wait_for_element(parent_id, "MY APP CODE", timeout=20)
        parent_app_code_after = parent_home.get_app_code()
        print(f"[{parent_id}] Parent App Code after re-login: {parent_app_code_after}")
        parent_home.close_drawer()

        if parent_app_code_before and parent_app_code_after:
            if parent_app_code_before == parent_app_code_after:
                print(f"[{parent_id}] ✅ VERIFIED: Parent App Code remained identical ({parent_app_code_before}) before & after logout/re-login.")
            else:
                raise Exception(f"[{parent_id}] ❌ Parent App Code CHANGED after logout/re-login! Before: '{parent_app_code_before}', After: '{parent_app_code_after}'")

        # 4. Add & mark dose taken while logged in
        print(f"[{parent_id}] Adding medicine 8 while logged in: {login_med8}...")
        parent_home.tap_add_medicine_fab()
        parent_add_med.add_medicine(login_med8, "Once a Day")
        time.sleep(2.5)
        parent_home.take_dose(login_med8)
        time.sleep(2)

        # 5. Trigger sync & verify both medicines are synced to Caretaker
        trigger_sync(parent_id, parent_home, wait_time=10)
        ensure_caretaker_on_parent_profile(caretaker_id, caretaker_home)
        trigger_sync(caretaker_id, caretaker_home, wait_time=10)

        caretaker_home.navigate_to_medicine_list()
        caretaker_med_list.verify_medicine_exists(logout_med7)
        caretaker_med_list.verify_medicine_exists(login_med8)
        caretaker_home.go_back()

        print("✅ TEST CASE 5 PASSED: Both logged-out and logged-in doses successfully synced after re-login!")

        # Clear inbox after Test Case 5
        trigger_sync(caretaker_id, caretaker_home, wait_time=6)

        # ================================================================
        # TEST CASE 6: Caretaker Logout -> Connection Deletion -> Login & Re-Pairing
        # ================================================================
        print("\n--- TEST CASE 6: Caretaker Logout -> Connection Deletion -> Login & Re-Pairing ---")

        # 1. Caretaker logs out
        print(f"[{caretaker_id}] Caretaker logging out...")
        caretaker_home.open_drawer()
        caretaker_app_code_before = caretaker_home.get_app_code()
        print(f"[{caretaker_id}] Caretaker App Code before logout: {caretaker_app_code_before}")
        sign_out_btn = find_element(caretaker_id, "Sign Out")
        if sign_out_btn:
            tap(caretaker_id, sign_out_btn[0], sign_out_btn[1])
        else:
            tap(caretaker_id, 750, 750)
        time.sleep(3)
        caretaker_home.close_drawer()
        time.sleep(2)


        # 2. Caretaker logs in again
        print(f"[{caretaker_id}] Caretaker logging back in...")
        caretaker_home.open_drawer()
        caretaker_home.trigger_google_login("rajshekhar53@gmail.com")
        wait_for_element(caretaker_id, "MY APP CODE", timeout=20)
        caretaker_app_code_after = caretaker_home.get_app_code()
        print(f"[{caretaker_id}] Caretaker App Code after re-login: {caretaker_app_code_after}")

        if caretaker_app_code_before and caretaker_app_code_after:
            if caretaker_app_code_before == caretaker_app_code_after:
                print(f"[{caretaker_id}] ✅ VERIFIED: Caretaker App Code remained identical ({caretaker_app_code_before}) before & after logout/re-login.")
            else:
                raise Exception(f"[{caretaker_id}] ❌ Caretaker App Code CHANGED after logout/re-login! Before: '{caretaker_app_code_before}', After: '{caretaker_app_code_after}'")

        # 3. Verify Parent profile is NOT in Caretaker profile menu
        parent_tile = find_element(caretaker_id, "Parent Shekhar")
        if parent_tile:
            print(f"[{caretaker_id}] ❌ FAIL: Parent profile was still present after logout & re-login!")
            sys.exit(1)
        else:
            print(f"[{caretaker_id}] ✅ VERIFIED: Parent profile is absent from profile menu after logout & re-login.")
        caretaker_home.close_drawer()

        # 4. Caretaker re-pairs with Parent
        parent_home.open_drawer()
        parent_app_code = parent_home.get_app_code()
        parent_home.close_drawer()

        print(f"[{caretaker_id}] Re-initiating pairing with Parent App Code '{parent_app_code}'...")
        caretaker_home.open_drawer()
        caretaker_home.enter_parent_app_code(parent_app_code, "Parent Shekhar")
        caretaker_home.close_drawer()

        # Parent accepts connection on Home screen
        print(f"[{parent_id}] Waiting for connection request banner on Home screen...")
        parent_home.close_drawer()
        accepted = False
        for attempt in range(5):
            time.sleep(3)
            accepted = parent_home.accept_connection_request()
            if accepted:
                print(f"[{parent_id}] ✅ Connection request accepted successfully!")
                break



        time.sleep(3)
        ensure_caretaker_on_parent_profile(caretaker_id, caretaker_home)
        trigger_sync(parent_id, parent_home, wait_time=8)
        ensure_caretaker_on_parent_profile(caretaker_id, caretaker_home)
        trigger_sync(caretaker_id, caretaker_home, wait_time=8)

        print(f"[{caretaker_id}] Verifying Parent medicines sync after re-pairing...")
        caretaker_home.navigate_to_medicine_list()
        caretaker_med_list.verify_medicine_exists(logout_med7)
        caretaker_home.go_back()

        print("✅ TEST CASE 6 PASSED: Caretaker logout deleted profile & connection, re-pairing successfully resynced parent data!")

        # Clear inbox after Test Case 6
        trigger_sync(caretaker_id, caretaker_home, wait_time=6)

        # ================================================================
        # TEST CASE 7: Caretaker Storage Data Wipe (pm clear) -> Setup -> Re-Pairing -> Data Sync
        # ================================================================
        print("\n--- TEST CASE 7: Caretaker Storage Data Wipe (pm clear) -> Setup -> Re-Pairing -> Data Sync ---")

        # 1. Wipe Caretaker app data
        clear_app_data(caretaker_id)

        # 2. Launch Caretaker & complete onboarding as Caretaker
        launch_app(caretaker_id)
        dismiss_permission_dialogs(caretaker_id)
        ct_onboarding = OnboardingPage(caretaker_id)
        ct_onboarding.enter_profile_name("Caretaker User")
        ct_onboarding.select_profile_type(is_caretaker=True)
        ct_onboarding.submit()
        time.sleep(3)
        dismiss_permission_dialogs(caretaker_id)

        # 3. Log in to Google
        caretaker_home.open_drawer()
        caretaker_home.trigger_google_login("rajshekhar53@gmail.com")
        wait_for_element(caretaker_id, "MY APP CODE", timeout=20)

        # 4. Verify Parent profile is NOT in drawer
        parent_tile = find_element(caretaker_id, "Parent Shekhar")
        if parent_tile:
            print(f"[{caretaker_id}] ❌ FAIL: Parent profile visible after app storage wipe!")
            sys.exit(1)
        else:
            print(f"[{caretaker_id}] ✅ VERIFIED: Parent profile absent after app storage wipe.")
        caretaker_home.close_drawer()

        # 5. Re-pair with Parent
        parent_home.open_drawer()
        parent_app_code = parent_home.get_app_code()
        parent_home.close_drawer()

        print(f"[{caretaker_id}] Re-pairing after app storage wipe with Parent App Code '{parent_app_code}'...")
        caretaker_home.open_drawer()
        caretaker_home.enter_parent_app_code(parent_app_code, "Parent Shekhar")
        caretaker_home.close_drawer()

        # Parent accepts connection on Home screen
        print(f"[{parent_id}] Waiting for connection request banner on Home screen...")
        parent_home.close_drawer()
        accepted = False
        for attempt in range(5):
            time.sleep(3)
            accepted = parent_home.accept_connection_request()
            if accepted:
                print(f"[{parent_id}] ✅ Connection request accepted successfully!")
                break



        time.sleep(3)
        ensure_caretaker_on_parent_profile(caretaker_id, caretaker_home)

        # 6. Trigger sync and verify data syncs after storage wipe re-pairing
        trigger_sync(parent_id, parent_home, wait_time=8)
        ensure_caretaker_on_parent_profile(caretaker_id, caretaker_home)
        trigger_sync(caretaker_id, caretaker_home, wait_time=8)

        caretaker_home.navigate_to_medicine_list()
        caretaker_med_list.verify_medicine_exists(logout_med7)
        caretaker_home.go_back()

        print("✅ TEST CASE 7 PASSED: App storage wipe clean setup & re-pairing successfully resynced parent data!")

        print("\n============================================================")
        print("🎉 ALL 7 OFFLINE & ASYNC SYNC TEST CASES PASSED SUCCESSFULLY!")
        print("============================================================")

    finally:
        # Guarantee internet is restored on both devices even if an exception occurred
        ensure_internet_on_all(parent_id, caretaker_id)


if __name__ == "__main__":
    main()
