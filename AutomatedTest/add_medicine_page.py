import time
import re
import xml.etree.ElementTree as ET
from adb_helper import find_element, tap, type_text, run_adb, hide_keyboard, dismiss_permission_dialogs, get_dump

class AddMedicinePage:
    def __init__(self, device_id):
        self.device_id = device_id

    def add_medicine(self, name, frequency_option="Once a Day"):
        print(f"[{self.device_id}] Adding medicine: '{name}' with frequency '{frequency_option}'...")
        
        # 1. Enter Name
        name_field = None
        for attempt in range(5):
            name_field = find_element(self.device_id, "Enter name")
            if name_field:
                break
            time.sleep(1)
            
        if name_field:
            tap(self.device_id, name_field[0], name_field[1])
            time.sleep(0.5)
            type_text(self.device_id, name)
        else:
            print(f"[{self.device_id}] ❌ Name field not found. Tapping fallback.")
            tap(self.device_id, 300, 490)
            time.sleep(0.5)
            type_text(self.device_id, name)
        
        # Send KEYCODE_ENTER (66) to submit field and dismiss soft keyboard
        print(f"[{self.device_id}] Sending KEYCODE_ENTER (66) to submit field...")
        run_adb(self.device_id, ["shell", "input", "keyevent", "66"])
        time.sleep(2)

        # Check if Page 1 Next is still present, tap if needed
        next_btn = find_element(self.device_id, "Next")
        if next_btn:
            print(f"[{self.device_id}] Tapping Next button on Page 1...")
            btn_y = min(next_btn[1], 2240)
            tap(self.device_id, next_btn[0], btn_y)
            time.sleep(2.5)



        # 2. Select Frequency if not default
        if frequency_option != "Once a Day":
            print(f"[{self.device_id}] Selecting frequency: {frequency_option}...")
            freq_dropdown = None
            for attempt in range(5):
                freq_dropdown = find_element(self.device_id, "Once a Day")
                if freq_dropdown:
                    break
                time.sleep(1)
                
            if freq_dropdown:
                tap(self.device_id, freq_dropdown[0], freq_dropdown[1])
                time.sleep(1.5)
                
                target_option = find_element(self.device_id, frequency_option)
                if target_option:
                    tap(self.device_id, target_option[0], target_option[1])
                else:
                    print(f"[{self.device_id}] ❌ Target frequency option '{frequency_option}' not found in dropdown.")
            else:
                print(f"[{self.device_id}] ❌ Frequency dropdown not found.")
            time.sleep(1)

        # Tap Next to go to Page 3
        print(f"[{self.device_id}] Tapping Next button on Page 2...")
        next_btn = find_element(self.device_id, "Next")
        if next_btn and next_btn[0] > 550:
            btn_y = min(next_btn[1], 2240)
            tap(self.device_id, next_btn[0], btn_y)
        else:
            tap(self.device_id, 789, 2240)
        time.sleep(2.5)


        # 3. Tap Add Medication/Save button once and verify screen pop or offline SnackBar
        save_btn = None
        try:
            dump_file = get_dump(self.device_id)
            tree = ET.parse(dump_file)
            root = tree.getroot()
            pattern = re.compile(r"Add Medication|Save Changes|Save", re.IGNORECASE)
            matches = []
            for node in root.iter('node'):
                text = node.attrib.get('text', '')
                desc = node.attrib.get('content-desc', '')
                bounds = node.attrib.get('bounds', '')
                if pattern.search(text) or pattern.search(desc):
                    m = re.match(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', bounds)
                    if m:
                        left, top, right, bottom = map(int, m.groups())
                        x = (left + right) // 2
                        y = (top + bottom) // 2
                        if y > 2000:
                            matches.append((x, min(y, 2240)))
            if matches:
                matches.sort(key=lambda item: item[1], reverse=True)
                save_btn = matches[0]
        except Exception as e:
            print(f"[{self.device_id}] Error searching submit button: {e}")

        if save_btn:
            print(f"[{self.device_id}] Tapping submit button at ({save_btn[0]}, {save_btn[1]})...")
            tap(self.device_id, save_btn[0], save_btn[1])
        else:
            print(f"[{self.device_id}] Tapping fallback submit button (789, 2240)...")
            tap(self.device_id, 789, 2240)


        time.sleep(3.5)

        # Check if 'Add Medication' header title is still present at top < 300
        is_still_add_screen = False
        has_offline_snackbar = False
        try:
            dump_file = get_dump(self.device_id)
            tree = ET.parse(dump_file)
            root = tree.getroot()
            for node in root.iter('node'):
                desc = node.attrib.get('content-desc', '')
                text = node.attrib.get('text', '')
                val = desc or text
                bounds = node.attrib.get('bounds', '')
                m = re.match(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', bounds)
                if m:
                    top = int(m.group(2))
                    if top < 300:
                        if 'Add Medication' in val or 'Edit Medication' in val:
                            is_still_add_screen = True
                if 'Saved locally' in val or 'failed to sync' in val or 'sync to parent' in val:
                    has_offline_snackbar = True
        except Exception as e:
            print(f"[{self.device_id}] Error checking screen state: {e}")

        if not is_still_add_screen:
            print(f"[{self.device_id}] ✅ Successfully saved medication and returned from Add Medication screen.")
        elif has_offline_snackbar:
            print(f"[{self.device_id}] ℹ️ Saved locally offline (offline sync banner displayed). Exiting Add Medication screen via BACK...")
            run_adb(self.device_id, ["shell", "input", "keyevent", "KEYCODE_BACK"])
            time.sleep(2)
        else:
            print(f"[{self.device_id}] ⏳ Form submission pending, re-tapping submit button once...")
            tap(self.device_id, 789, 2227)
            time.sleep(3.5)
            # Re-check screen state
            dump_file = get_dump(self.device_id)
            tree = ET.parse(dump_file)
            root = tree.getroot()
            is_still_add = False
            for node in root.iter('node'):
                desc = node.attrib.get('content-desc', '')
                text = node.attrib.get('text', '')
                val = desc or text
                bounds = node.attrib.get('bounds', '')
                m = re.match(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', bounds)
                if m and int(m.group(2)) < 300:
                    if 'Add Medication' in val or 'Edit Medication' in val:
                        is_still_add = True
            if is_still_add:
                print(f"[{self.device_id}] ℹ️ Exiting Add Medication screen via BACK...")
                run_adb(self.device_id, ["shell", "input", "keyevent", "KEYCODE_BACK"])
                time.sleep(2)

        dismiss_permission_dialogs(self.device_id)








