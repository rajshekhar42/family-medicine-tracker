import sys
import os
import time

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
sys.path.append(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

from adb_helper import run_adb, get_dump, find_element, tap, type_text, hide_keyboard, wait_for_element
from onboarding_page import OnboardingPage
from home_page import HomePage
from add_medicine_page import AddMedicinePage
from medicine_list_page import MedicineListPage

def launch_app(device_id):
    run_adb(device_id, ["shell", "am", "start", "-n", "org.medimitra.family_medicine_tracker/.MainActivity"])

def complete_onboarding_if_needed(device_id, profile_name, is_caretaker=False):
    onboarding = OnboardingPage(device_id)
    if find_element(device_id, "Enter name") or find_element(device_id, "Create Profile"):
        print(f"[{device_id}] Onboarding active. Completing for '{profile_name}'...")
        onboarding.enter_profile_name(profile_name)
        onboarding.select_profile_type(is_caretaker=is_caretaker)
        onboarding.submit()

def test_login_logout_relogin_sync():
    parent_id = "emulator-5554"
    caretaker_id = "emulator-5556"
    t0 = time.time()

    def lap(msg):
        elapsed = time.time() - t0
        print(f"⏱️ [{elapsed:5.1f}s] {msg}")

    print("=" * 60)
    print("⚡ FAST DIAGNOSTIC TEST: Parent Logout & Relogin Sync")
    print(f"   Parent: {parent_id} | Caretaker: {caretaker_id}")
    print("=" * 60)

    launch_app(parent_id)
    launch_app(caretaker_id)
    lap("Apps launched on both devices")

    complete_onboarding_if_needed(parent_id, "Parent User", is_caretaker=False)
    complete_onboarding_if_needed(caretaker_id, "Caretaker User", is_caretaker=True)
    lap("Onboarding verified")

    parent_home = HomePage(parent_id)
    caretaker_home = HomePage(caretaker_id)
    parent_add_med = AddMedicinePage(parent_id)
    caretaker_med_list = MedicineListPage(caretaker_id)

    # 1. Initial Google Login
    parent_home.open_drawer()
    parent_home.trigger_google_login(email_pattern="rajshekhardev@gmail.com")
    parent_code = parent_home.get_app_code()
    parent_home.close_drawer()
    lap(f"Parent logged in (App Code: {parent_code})")

    caretaker_home.open_drawer()
    caretaker_home.trigger_google_login(email_pattern="rajshekhar42@gmail.com")
    caretaker_code = caretaker_home.get_app_code()
    caretaker_home.close_drawer()
    lap(f"Caretaker logged in (App Code: {caretaker_code})")

    if not parent_code or not caretaker_code:
        print("❌ ERROR: App code generation failed.")
        sys.exit(1)

    # 2. Pair Caretaker -> Parent
    caretaker_home.open_drawer()
    caretaker_home.enter_parent_app_code(parent_code, "Parent User")
    # STEP 3: Parent Accepts Pairing
    print(f"\n--- STEP 3: Parent Accepts Pairing ---")
    time.sleep(2)
    parent_home.accept_connection_request()
    lap("Parent accepted pairing request")

    # 3. Add Pre-Logout Med & Sync
    pre_med = f"PreMed{int(time.time())}"
    parent_home.tap_add_medicine_fab()
    parent_add_med.add_medicine(pre_med, "Once a Day")

    print(f"[{parent_id}] Pushing sync pre-logout...")
    parent_home.open_drawer()
    parent_home.trigger_sync_now()
    parent_home.close_drawer()

    print("Waiting 6s for Parent upload to reach Firebase RTDB...")
    time.sleep(6)

    print(f"[{caretaker_id}] Pulling sync pre-logout...")
    caretaker_home.open_drawer()
    caretaker_home.trigger_sync_now()
    caretaker_home.close_drawer()
    lap(f"Pre-logout medicine '{pre_med}' synced")

    # 4. Parent Logout & Relogin
    parent_home.open_drawer()
    sign_out_btn = find_element(parent_id, "Sign Out")
    if sign_out_btn:
        tap(parent_id, sign_out_btn[0], sign_out_btn[1])
    else:
        tap(parent_id, 660, 2210)
    time.sleep(2)
    parent_home.close_drawer()
    lap("Parent signed out")

    parent_home.open_drawer()
    parent_home.trigger_google_login(email_pattern="rajshekhardev@gmail.com")
    restored_code = parent_home.get_app_code()
    parent_home.close_drawer()
    lap(f"Parent logged back in (Restored Code: {restored_code})")

    if restored_code != parent_code:
        print(f"❌ FAIL: App code changed! Expected {parent_code}, got {restored_code}")
        sys.exit(1)

    # 5. Add Post-Relogin Med & Sync
    post_med = f"PostMed{int(time.time())}"
    parent_home.tap_add_medicine_fab()
    parent_add_med.add_medicine(post_med, "Once a Day")

    print(f"[{parent_id}] Pushing sync post-relogin...")
    parent_home.open_drawer()
    parent_home.trigger_sync_now()
    parent_home.close_drawer()

    print("Waiting 6s for Parent upload to reach Firebase RTDB...")
    time.sleep(6)

    print(f"[{caretaker_id}] Pulling sync post-relogin...")
    caretaker_home.open_drawer()
    caretaker_home.trigger_sync_now()
    caretaker_home.close_drawer()
    lap(f"Post-relogin medicine '{post_med}' synced")

    # 6. Verify Caretaker App Ingestion
    caretaker_home.switch_profile("Parent User")
    caretaker_home.navigate_to_medicine_list()
    has_post_med = caretaker_med_list.verify_medicine_exists(post_med)
    lap(f"Ingestion check finished for '{post_med}'")

    total_time = time.time() - t0
    print("=" * 60)
    if has_post_med:
        print(f"🎉 SUCCESS in {total_time:.1f}s! Parent Logout & Relogin sync test PASSED!")
    else:
        print(f"❌ FAIL in {total_time:.1f}s! Post-relogin medicine '{post_med}' NOT ingested by Caretaker!")
    print("=" * 60)

if __name__ == "__main__":
    test_login_logout_relogin_sync()
