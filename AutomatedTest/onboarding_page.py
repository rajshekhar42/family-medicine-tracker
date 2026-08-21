import time
from adb_helper import (
    find_element,
    tap,
    type_text,
    wait_for_element,
    dismiss_permission_dialogs,
    run_adb,
    find_edit_texts,
)

class OnboardingPage:
    def __init__(self, device_id):
        self.device_id = device_id

    def enter_profile_name(self, name):
        print(f"[{self.device_id}] Entering profile name: {name}")
        # Find the name text field using multiple locator strategies
        field = None
        for _ in range(15):
            field = (
                find_element(self.device_id, "e.g. Ram")
                or find_element(self.device_id, "NAME")
                or find_element(self.device_id, "Enter name")
                or find_element(self.device_id, "What should we call you")
            )
            if not field:
                edit_texts = find_edit_texts(self.device_id)
                if edit_texts:
                    field = edit_texts[0]
            if field:
                break
            time.sleep(1)

        if field:
            tap(self.device_id, field[0], field[1])
            time.sleep(0.8)
            type_text(self.device_id, name)
            time.sleep(0.8)
        else:
            print(f"[{self.device_id}] ❌ Onboarding field not found. Trying fallback.")
            tap(self.device_id, 540, 1670)
            time.sleep(1)
            type_text(self.device_id, name)

        time.sleep(1)

    def select_profile_type(self, is_caretaker=False):
        if is_caretaker:
            print(f"[{self.device_id}] Selecting Caretaker Profile option...")
            elem = (
                find_element(self.device_id, "My family")
                or find_element(self.device_id, "Caretaker Profile")
                or find_element(self.device_id, "Caretaker profile")
                or find_element(self.device_id, "track medicine for my family")
            )
            if not elem:
                elem = (
                    wait_for_element(self.device_id, "My family", timeout=8)
                    or wait_for_element(self.device_id, "Caretaker", timeout=5)
                )
            if elem:
                tap(self.device_id, elem[0], elem[1])
            else:
                print(f"[{self.device_id}] ⚠️ Caretaker option not found by text, using fallback tap")
                tap(self.device_id, 540, 1284)
            time.sleep(1)
        else:
            print(f"[{self.device_id}] Keeping default Parent Profile option selected...")
            elem = find_element(self.device_id, "Myself")
            if elem:
                tap(self.device_id, elem[0], elem[1])
            time.sleep(0.5)

    def submit(self):
        print(f"[{self.device_id}] Submitting onboarding form...")
        # Clear any permission dialogs before looking for the button
        dismiss_permission_dialogs(self.device_id)
        btn = (
            find_element(self.device_id, "Create profile & start")
            or find_element(self.device_id, "Create profile")
            or find_element(self.device_id, "Create Profile")
        )
        if not btn:
            # Swipe up to scroll button into view if needed
            run_adb(self.device_id, ["shell", "input", "swipe", "500", "1500", "500", "500", "500"])
            time.sleep(1.5)
            btn = (
                wait_for_element(self.device_id, "Create profile & start", timeout=10)
                or wait_for_element(self.device_id, "Create profile", timeout=5)
                or wait_for_element(self.device_id, "Create Profile", timeout=5)
            )
        if btn:
            tap(self.device_id, btn[0], btn[1])
        else:
            print(f"[{self.device_id}] ❌ Onboarding submit button not found. Trying fallback.")
            tap(self.device_id, 540, 2135)
        
        # Verify transition away from onboarding
        time.sleep(3)
        if find_element(self.device_id, "Create profile & start"):
            print(f"[{self.device_id}] Re-tapping submit button to ensure onboarding completion...")
            re_btn = find_element(self.device_id, "Create profile & start")
            if re_btn:
                tap(self.device_id, re_btn[0], re_btn[1])
            time.sleep(3)
