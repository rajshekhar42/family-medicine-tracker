import time
from adb_helper import find_element, find_element_near

class HistoryPage:
    def __init__(self, device_id):
        self.device_id = device_id

    def verify_history_contains(self, name, should_be_taken=False, should_be_skipped=False):
        print(f"[{self.device_id}] Checking if history contains record for '{name}'...")
        time.sleep(3)
        pos = find_element(self.device_id, name)
        if not pos:
            # Scroll down to find entry if history list is long
            for attempt in range(12):
                print(f"[{self.device_id}] Scrolling down to find '{name}' in History (attempt {attempt + 1}/12)...")
                from adb_helper import run_adb
                run_adb(self.device_id, ["shell", "input", "swipe", "540", "1500", "540", "600"])
                time.sleep(1.5)
                pos = find_element(self.device_id, name)
                if pos:
                    break



        if pos:
            print(f"[{self.device_id}] ✅ Verified: History entry for '{name}' exists.")
            if should_be_taken:
                # Also verify that it says "Taken" in the same block/nearby
                taken_pos = find_element_near(self.device_id, r"\bTaken\b", pos[1], max_delta=180)
                if taken_pos:
                    print(f"[{self.device_id}] ✅ Verified: Dose is marked as 'Taken' in History for '{name}'.")
                    return True
                else:
                    raise Exception(f"Failed: Dose is NOT marked as 'Taken' in History for '{name}'.")
            if should_be_skipped:
                # Also verify that it says "Skipped" in the same block/nearby
                skipped_pos = find_element_near(self.device_id, r"\bSkipped\b", pos[1], max_delta=180)
                if skipped_pos:
                    print(f"[{self.device_id}] ✅ Verified: Dose is marked as 'Skipped' in History for '{name}'.")
                    return True
                else:
                    raise Exception(f"Failed: Dose is NOT marked as 'Skipped' in History for '{name}'.")
            return True
        else:
            raise Exception(f"Failed: History entry for '{name}' not found.")
