import time
from adb_helper import find_element, tap, type_text, hide_keyboard, wait_for_element, dismiss_permission_dialogs, run_adb

class OnboardingPage:
    def __init__(self, device_id):
        self.device_id = device_id

    def enter_profile_name(self, name):
        print(f"[{self.device_id}] Entering profile name: {name}")
        # Wait up to 45 seconds for the onboarding screen text field to appear
        field = wait_for_element(self.device_id, "Enter name", timeout=45)
        if field:
            tap(self.device_id, field[0], field[1])
            time.sleep(1)
            type_text(self.device_id, name)
        else:
            print(f"[{self.device_id}] ❌ Onboarding field not found. Trying fallback.")
            tap(self.device_id, 540, 1420)
            time.sleep(1)
            type_text(self.device_id, name)
        time.sleep(1)
        
        # Dismiss keyboard safely
        hide_keyboard(self.device_id)

    def select_profile_type(self, is_caretaker=False):
        if is_caretaker:
            print(f"[{self.device_id}] Selecting Caretaker Profile option...")
            elem = wait_for_element(self.device_id, "Caretaker Profile", timeout=10)
            if not elem:
                elem = wait_for_element(self.device_id, "track medicine for my family", timeout=5)
            if elem:
                tap(self.device_id, elem[0], elem[1])
            else:
                print(f"[{self.device_id}] ⚠️ Caretaker option not found by text, using fallback tap")
                tap(self.device_id, 540, 1540)
            time.sleep(1)
        else:
            print(f"[{self.device_id}] Keeping default Parent Profile option selected...")

    def submit(self):
        print(f"[{self.device_id}] Submitting onboarding form...")
        # Clear any permission dialogs before looking for the button
        dismiss_permission_dialogs(self.device_id)
        # Swipe up to scroll button into view (in case keyboard is covering it)
        run_adb(self.device_id, ["shell", "input", "swipe", "500", "1000", "500", "300", "800"])
        time.sleep(1.5)
        btn = wait_for_element(self.device_id, "Create Profile", timeout=15)
        if btn:
            tap(self.device_id, btn[0], btn[1])
        else:
            print(f"[{self.device_id}] ❌ Onboarding submit button not found. Trying fallback.")
            tap(self.device_id, 540, 2180)
        time.sleep(4)
