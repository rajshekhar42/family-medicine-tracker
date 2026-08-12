import time
from adb_helper import find_element

class MedicineListPage:
    def __init__(self, device_id):
        self.device_id = device_id

    def verify_medicine_exists(self, name):
        print(f"[{self.device_id}] Checking if medicine '{name}' exists in the medicines list...")
        time.sleep(3)
        pos = find_element(self.device_id, name)
        if pos:
            print(f"[{self.device_id}] ✅ Verified: Medicine '{name}' is in the list.")
            return True

        # Scroll down to find medicine if list is long
        for attempt in range(12):
            print(f"[{self.device_id}] Scrolling down to find '{name}' (attempt {attempt + 1}/12)...")
            from adb_helper import run_adb
            run_adb(self.device_id, ["shell", "input", "swipe", "540", "1500", "540", "600"])
            time.sleep(1.5)
            pos = find_element(self.device_id, name)
            if pos:
                print(f"[{self.device_id}] ✅ Verified: Medicine '{name}' is in the list.")
                return True



        raise Exception(f"Failed: Medicine '{name}' was not found in the list.")
