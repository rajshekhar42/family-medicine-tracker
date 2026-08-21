import time
import re
import xml.etree.ElementTree as ET

from adb_helper import run_adb, find_element, tap, type_text, wait_for_element, hide_keyboard, get_dump

class HomePage:
    def __init__(self, device_id):
        self.device_id = device_id

    def open_drawer(self):
        print(f"[{self.device_id}] Opening drawer...")
        # Check if drawer is already open
        dump_file = get_dump(self.device_id)
        tree = ET.parse(dump_file)
        root = tree.getroot()
        if find_element(self.device_id, "PROFILES"):
            print(f"[{self.device_id}] Drawer is successfully opened.")
            return

        # Check if on sub-screen with Back button
        back_btn = find_element(self.device_id, "Back")
        if back_btn:
            print(f"[{self.device_id}] On sub-screen with Back button. Pressing back to return to Home...")
            self.go_back()
            time.sleep(1.5)

        for attempt in range(4):
            pill_coords = None
            try:
                dump_file = get_dump(self.device_id)
                tree = ET.parse(dump_file)
                root = tree.getroot()
                for node in root.iter('node'):
                    bounds = node.attrib.get('bounds', '')
                    m = re.match(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', bounds)
                    if m:
                        left, top, right, bottom = map(int, m.groups())
                        if 100 < top < 300 and 20 < left < 400 and 150 < bottom < 400:
                            pill_coords = ((left + right) // 2, (top + bottom) // 2)
                            break
            except Exception as e:
                print(f"[{self.device_id}] Error searching for header pill: {e}")

            if pill_coords:
                print(f"[{self.device_id}] Tapping header profile pill at {pill_coords}...")
                tap(self.device_id, pill_coords[0], pill_coords[1])
            else:
                print(f"[{self.device_id}] Tapping default menu button (195, 226)...")
                tap(self.device_id, 195, 226)

            time.sleep(2.5)
            if find_element(self.device_id, "PROFILES"):
                print(f"[{self.device_id}] Drawer is successfully opened.")
                return

        print(f"[{self.device_id}] ⚠️ Warning: Failed to confirm drawer is open.")





    def close_drawer(self):
        print(f"[{self.device_id}] Closing drawer...")
        # Tap on right side of screen outside drawer
        tap(self.device_id, 950, 1000)
        time.sleep(1.5)

    def trigger_google_login(self, email_pattern=None):
        print(f"[{self.device_id}] Triggering Google Login in drawer...")
        if find_element(self.device_id, "MY APP CODE") or find_element(self.device_id, "Sync Now"):
            print(f"[{self.device_id}] Already logged in.")
            return True

        for attempt in range(3):
            btn = find_element(self.device_id, "Sign in with Google")
            if not btn:
                # Scroll drawer down to ensure button is visible
                run_adb(self.device_id, ["shell", "input", "swipe", "400", "1800", "400", "1200"])
                time.sleep(1)
                btn = find_element(self.device_id, "Sign in with Google")

            if btn:
                print(f"[{self.device_id}] Tapping Sign in with Google at ({btn[0]}, {btn[1]})...")
                tap(self.device_id, btn[0], btn[1])
            else:
                print(f"[{self.device_id}] ❌ Sign in button not found. Tapping fallback.")
                tap(self.device_id, 399, 2214)

            time.sleep(3.5)
            print(f"[{self.device_id}] Google login triggered. Selecting account...")
            if self.select_google_account(email_pattern):
                return True

            if find_element(self.device_id, "MY APP CODE"):
                return True
            time.sleep(1)

        return False

    def select_google_account(self, email_pattern=None):
        print(f"[{self.device_id}] Selecting Google Account (pattern={email_pattern})...")
        device_account = None
        try:
            out, _ = run_adb(self.device_id, ["shell", "dumpsys", "account"])
            m = re.search(r"Account\s*\{name=([^,]+),\s*type=com\.google\}", out)
            if m:
                device_account = m.group(1).strip()
                print(f"[{self.device_id}] Discovered device Google account: {device_account}")
        except Exception as e:
            print(f"[{self.device_id}] Error querying dumpsys account: {e}")

        account_pos = None
        for attempt in range(6):
            if device_account:
                prefix = device_account.split('@')[0]
                account_pos = find_element(self.device_id, device_account) or find_element(self.device_id, prefix)
            if not account_pos and email_pattern:
                prefix = email_pattern.split('@')[0]
                account_pos = find_element(self.device_id, email_pattern) or find_element(self.device_id, prefix)
            if not account_pos:
                account_pos = find_element(self.device_id, r"[\w\.-]+@[\w\.-]+\.\w+") or find_element(self.device_id, "@gmail.com")
            if not account_pos:
                account_pos = find_element(self.device_id, "Continue as")
            if not account_pos:
                choose_elem = find_element(self.device_id, "Choose an account")
                if choose_elem:
                    account_pos = (choose_elem[0], choose_elem[1] + 120)

            if account_pos:
                print(f"[{self.device_id}] Tapping Google Account at ({account_pos[0]}, {account_pos[1]})...")
                tap(self.device_id, account_pos[0], account_pos[1])
                time.sleep(6)
                return True
            time.sleep(2)
        
        print(f"[{self.device_id}] ⚠️ Account selector not found dynamically, tapping fallback...")
        tap(self.device_id, 417, 1342)
        time.sleep(6)
        return False

    def get_app_code(self):
        print(f"[{self.device_id}] Retrieving App Code...")
        app_code_pattern = r"MY APP CODE\s+([A-Z0-9]{6,8})"
        
        # Poll up to 8 times (16 seconds total) waiting for code generation
        for attempt in range(8):
            try:
                dump_file = get_dump(self.device_id)
                tree = ET.parse(dump_file)
                root = tree.getroot()
                
                for node in root.iter('node'):
                    desc = node.attrib.get('content-desc', '')
                    text = node.attrib.get('text', '')
                    val = desc or text
                    m = re.search(app_code_pattern, val)
                    if m:
                        code = m.group(1)
                        print(f"[{self.device_id}] ✅ Extracted App Code: {code}")
                        return code
            except Exception as e:
                print(f"[{self.device_id}] Error parsing dump for App Code: {e}")
                
            print(f"[{self.device_id}] App Code still generating, waiting 2s (attempt {attempt + 1}/8)...")
            time.sleep(2)
            
        print(f"[{self.device_id}] ❌ Failed to retrieve App Code.")
        return None

    def enter_parent_app_code(self, parent_code, profile_name="Parent Shekhar"):
        print(f"[{self.device_id}] Pairing with Parent app code: {parent_code}")
        wait_for_element(self.device_id, "Add Family Member", timeout=10)
        
        btn = find_element(self.device_id, "Add Family Member")
        if btn:
            tap(self.device_id, btn[0], btn[1])
        else:
            tap(self.device_id, 683, 546)
        time.sleep(2)
        
        from adb_helper import wait_for_edit_texts, find_edit_texts
        fields = wait_for_edit_texts(self.device_id, count=2, timeout=10)
        if len(fields) >= 2:
            print(f"[{self.device_id}] Entering parent code '{parent_code}' into field 1 (App Code) at {fields[0]}...")
            tap(self.device_id, fields[0][0], fields[0][1])
            time.sleep(0.5)
            type_text(self.device_id, parent_code)
            time.sleep(0.5)

            # Re-locate EditText fields (which may have shifted up when keyboard opened)
            current_fields = find_edit_texts(self.device_id)
            field2_pos = None
            if len(current_fields) >= 2:
                field2_pos = current_fields[1]
            elif len(fields) >= 2:
                field2_pos = fields[1]

            if not field2_pos:
                field2_pos = find_element(self.device_id, "e.g. Father, Mother") or find_element(self.device_id, "Display Name")

            if field2_pos:
                print(f"[{self.device_id}] Entering profile name '{profile_name}' into field 2 (Display Name) at {field2_pos}...")
                tap(self.device_id, field2_pos[0], field2_pos[1])
                time.sleep(0.5)
                type_text(self.device_id, profile_name)
                time.sleep(0.5)
            else:
                print(f"[{self.device_id}] ⚠️ Display Name field could not be found.")
        else:
            print(f"[{self.device_id}] ⚠️ EditText fields not found dynamically, tapping fallback coordinates...")
            tap(self.device_id, 540, 936)
            time.sleep(0.5)
            type_text(self.device_id, parent_code)
            time.sleep(0.5)

            tap(self.device_id, 540, 1109)
            time.sleep(0.5)
            type_text(self.device_id, profile_name)
            time.sleep(0.5)

        time.sleep(1)
        submit_btn = (
            find_element(self.device_id, r"^Add$")
            or find_element(self.device_id, r"^\s*Add\s*$")
            or find_element(self.device_id, "Add & Connect")
        )
        if submit_btn:
            print(f"[{self.device_id}] Tapping submit 'Add' button at ({submit_btn[0]}, {submit_btn[1]})...")
            tap(self.device_id, submit_btn[0], submit_btn[1])
        else:
            print(f"[{self.device_id}] ⚠️ Submit button not found. Tapping fallback.")
            tap(self.device_id, 749, 1574)
        time.sleep(3)


    def accept_connection_request(self):
        print(f"[{self.device_id}] Checking for incoming connection requests...")
        btn = find_element(self.device_id, r"^Accept$") or find_element(self.device_id, "Approve Connection") or find_element(self.device_id, "Approve")
        if btn:
            print(f"[{self.device_id}] Accepting connection request at ({btn[0]}, {btn[1]})...")
            tap(self.device_id, btn[0], btn[1])
            time.sleep(3)
            return True
        return False


    def tap_add_medicine_fab(self):
        print(f"[{self.device_id}] Tapping Add Medicine FAB...")
        fab = find_element(self.device_id, "Add Medicine")
        if fab:
            tap(self.device_id, fab[0], fab[1])
        else:
            tap(self.device_id, 960, 2240)
        time.sleep(2)

    def take_dose(self, med_name=None):
        if med_name:
            print(f"[{self.device_id}] Marking '{med_name}' dose as taken...")
            time.sleep(2.5)
            pos = find_element(self.device_id, med_name)
            if not pos:
                print(f"[{self.device_id}] Card '{med_name}' not visible, scrolling to top of home screen...")
                run_adb(self.device_id, ["shell", "input", "swipe", "540", "600", "540", "1800"])
                time.sleep(1.5)
                pos = find_element(self.device_id, med_name)
                if not pos:
                    for scroll_idx in range(12):
                        print(f"[{self.device_id}] Card '{med_name}' not visible, scrolling down (attempt {scroll_idx + 1}/12)...")
                        run_adb(self.device_id, ["shell", "input", "swipe", "540", "1800", "540", "400"])
                        time.sleep(1.5)
                        pos = find_element(self.device_id, med_name)
                        if pos:
                            break
            if pos:
                if pos[1] > 1900:
                    print(f"[{self.device_id}] Card '{med_name}' near bottom at y={pos[1]}, scrolling up into center view...")
                    run_adb(self.device_id, ["shell", "input", "swipe", "540", "1800", "540", "900"])
                    time.sleep(2.0)
                    new_pos = find_element(self.device_id, med_name)
                    if new_pos:
                        pos = new_pos
                    else:
                        pos = (pos[0], max(300, pos[1] - 900))

                from adb_helper import find_element_near
                take_btn = find_element_near(self.device_id, r"\bTake\b", pos[1], max_delta=350)
                if not take_btn:
                    take_btn = find_element_near(self.device_id, r"Take", pos[1], max_delta=500)
                if take_btn:
                    tap(self.device_id, take_btn[0], take_btn[1])
                    time.sleep(2)
                    print(f"[{self.device_id}] ✅ Marked '{med_name}' dose as Taken.")
                    return True
                else:
                    print(f"[{self.device_id}] ⚠️ Take button not found near y={pos[1]}. Tapping right side of card at (919, {pos[1]})...")
                    tap(self.device_id, 919, pos[1])
                    time.sleep(2)
                    print(f"[{self.device_id}] ✅ Marked '{med_name}' dose as Taken via fallback.")
                    return True
            else:
                raise Exception(f"Failed: Medicine card '{med_name}' was not found on home screen to mark as taken.")

        print(f"[{self.device_id}] Marking dose as taken...")
        take_btn = find_element(self.device_id, r"\bTake\b")
        if take_btn:
            tap(self.device_id, take_btn[0], take_btn[1])
            time.sleep(2)
            print(f"[{self.device_id}] ✅ Marked dose as Taken.")
            return True
        return False

    def skip_dose(self, med_name=None):
        if med_name:
            print(f"[{self.device_id}] Marking '{med_name}' dose as skipped...")
            time.sleep(2.5)
            pos = find_element(self.device_id, med_name)
            if not pos:
                print(f"[{self.device_id}] Card '{med_name}' not visible, scrolling to top of home screen...")
                run_adb(self.device_id, ["shell", "input", "swipe", "540", "600", "540", "1800"])
                time.sleep(1.5)
                pos = find_element(self.device_id, med_name)
                if not pos:
                    for scroll_idx in range(12):
                        print(f"[{self.device_id}] Card '{med_name}' not visible, scrolling down (attempt {scroll_idx + 1}/12)...")
                        run_adb(self.device_id, ["shell", "input", "swipe", "540", "1800", "540", "400"])
                        time.sleep(1.5)
                        pos = find_element(self.device_id, med_name)
                        if pos:
                            break



            if pos:
                if pos[1] > 1900:
                    print(f"[{self.device_id}] Card '{med_name}' near bottom at y={pos[1]}, scrolling up into center view...")
                    run_adb(self.device_id, ["shell", "input", "swipe", "540", "1800", "540", "900"])
                    time.sleep(2.0)
                    new_pos = find_element(self.device_id, med_name)
                    if new_pos:
                        pos = new_pos
                    else:
                        pos = (pos[0], max(300, pos[1] - 900))

                from adb_helper import find_element_near_full
                res = find_element_near_full(self.device_id, "Skip dose", pos[1], max_delta=350)
                if not res:
                    res = find_element_near_full(self.device_id, "Skip", pos[1], max_delta=500)
                if res:
                    x, y, left, top, right, bottom = res
                    tap_x = left + 38 if right - left > 200 else x
                    tap_y = y
                    tap(self.device_id, tap_x, tap_y)
                    time.sleep(2)
                    print(f"[{self.device_id}] ✅ Marked '{med_name}' dose as Skipped.")
                    return True
                else:
                    print(f"[{self.device_id}] ⚠️ Skip button not found near y={pos[1]}. Tapping left side of card at (160, {pos[1]})...")
                    tap(self.device_id, 160, pos[1])
                    time.sleep(2)
                    print(f"[{self.device_id}] ✅ Marked '{med_name}' dose as Skipped via fallback.")
                    return True
            else:
                raise Exception(f"Failed: Medicine card '{med_name}' was not found on home screen to mark as skipped.")



        print(f"[{self.device_id}] Marking dose as skipped...")
        from adb_helper import find_element_near_full
        res = find_element_near_full(self.device_id, "Skip dose", 1000)
        if not res:
            res = find_element_near_full(self.device_id, "Skip", 1000)
        if res:
            x, y, left, top, right, bottom = res
            tap_x = left + 38 if right - left > 200 else x
            tap_y = y
            tap(self.device_id, tap_x, tap_y)
            time.sleep(2)
            print(f"[{self.device_id}] ✅ Marked dose as Skipped.")
            return True
        return False

    def trigger_sync_now(self):
        print(f"[{self.device_id}] Tapping Sync Now button in drawer...")
        btn = find_element(self.device_id, "Sync Now")
        if btn:
            tap(self.device_id, btn[0], btn[1])
            print(f"[{self.device_id}] ✅ Tapped Sync button at ({btn[0]}, {btn[1]}).")
            return True
        else:
            print(f"[{self.device_id}] ❌ Sync Now button not found in drawer.")
            return False

    def navigate_to_medicine_list(self):
        print(f"[{self.device_id}] Navigating to Medicines List...")
        self.open_drawer()
        btn = find_element(self.device_id, "Medicines List")
        if btn:
            tap(self.device_id, btn[0], btn[1])
        else:
            tap(self.device_id, 399, 1465)
        time.sleep(3)

    def navigate_to_history(self):
        print(f"[{self.device_id}] Navigating to Adherence History...")
        self.open_drawer()
        btn = find_element(self.device_id, "Adherence History")
        if btn:
            tap(self.device_id, btn[0], btn[1])
        else:
            tap(self.device_id, 399, 1570)
        time.sleep(3)

    def sign_out(self):
        print(f"[{self.device_id}] Signing out...")
        self.open_drawer()
        time.sleep(1.5)
        sign_out_btn = find_element(self.device_id, "Sign Out")
        if sign_out_btn:
            tap(self.device_id, sign_out_btn[0], sign_out_btn[1])
            print(f"[{self.device_id}] Tapped Sign Out button in drawer.")
        else:
            print(f"[{self.device_id}] ⚠️ Sign Out button not found, tapping fallback (450, 2069)...")
            tap(self.device_id, 450, 2069)
        time.sleep(1.5)
        # Handle confirmation dialog if present
        confirm_btn = wait_for_element(self.device_id, "Sign Out", timeout=4) or find_element(self.device_id, "Sign Out")
        if confirm_btn:
            print(f"[{self.device_id}] Confirming sign out dialog at {confirm_btn}...")
            tap(self.device_id, confirm_btn[0], confirm_btn[1])
            time.sleep(2)
        self.close_drawer()
        time.sleep(1.5)

    def go_back(self):
        print(f"[{self.device_id}] Pressing back (hardware KEYCODE_BACK)...")
        run_adb(self.device_id, ["shell", "input", "keyevent", "4"])
        time.sleep(2)
