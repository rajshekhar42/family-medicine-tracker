import subprocess
import time
import re
import xml.etree.ElementTree as ET

def run_adb(device_id, args):
    cmd = ["adb", "-s", device_id] + args
    try:
        res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20)
        return res.stdout, res.stderr
    except subprocess.TimeoutExpired:
        print(f"[{device_id}] ⚠️ ADB command timed out: {' '.join(cmd)}")
        return "", "Timeout"

def get_dump(device_id):
    # Unique file name per device to avoid conflict during concurrent execution
    dump_remote = f"/sdcard/window_dump_{device_id}.xml"
    dump_local = f"window_dump_{device_id}.xml"
    run_adb(device_id, ["shell", "uiautomator", "dump", dump_remote])
    run_adb(device_id, ["pull", dump_remote, dump_local])
    return dump_local

def find_element_in_tree(root, text_pattern, match_desc=True):
    pattern = re.compile(text_pattern, re.IGNORECASE)
    matches = []
    
    for node in root.iter('node'):
        text = node.attrib.get('text', '')
        desc = node.attrib.get('content-desc', '')
        hint = node.attrib.get('hint', '')
        
        match = False
        if pattern.search(text):
            match = True
        elif match_desc and pattern.search(desc):
            match = True
        elif pattern.search(hint):
            match = True
            
        if match:
            bounds = node.attrib.get('bounds', '')
            m = re.match(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', bounds)
            if m:
                left, top, right, bottom = map(int, m.groups())
                if left == 0 and top == 0 and right == 0 and bottom == 0:
                    continue
                x = (left + right) // 2
                y = (top + bottom) // 2
                matches.append((x, y, text, desc, hint))


                
    if matches:
        # Sort matches by y-coordinate descending (prefer elements lower on screen, e.g., buttons)
        matches.sort(key=lambda item: item[1], reverse=True)
        best = matches[0]
        return best[0], best[1], len(matches), best[2], best[3]
        
    return None

def find_element(device_id, text_pattern, match_desc=True):
    try:
        dump_file = get_dump(device_id)
        tree = ET.parse(dump_file)
        root = tree.getroot()
        res = find_element_in_tree(root, text_pattern, match_desc)
        if res:
            x, y, count, text, desc = res
            print(f"[{device_id}] Found {count} matches for '{text_pattern}'. Selecting lowest: text='{text}', desc='{desc}' at ({x}, {y})")
            return x, y
    except Exception as e:
        print(f"[{device_id}] Error parsing dump: {e}")
    return None

def find_element_near(device_id, text_pattern, near_y, max_delta=180, match_desc=True):
    res = find_element_near_full(device_id, text_pattern, near_y, max_delta, match_desc)
    if res:
        return res[0], res[1]
    return None

def find_element_near_full(device_id, text_pattern, near_y, max_delta=180, match_desc=True):
    try:
        dump_file = get_dump(device_id)
        tree = ET.parse(dump_file)
        root = tree.getroot()
        pattern = re.compile(text_pattern, re.IGNORECASE)
        matches = []
        for node in root.iter('node'):
            text = node.attrib.get('text', '')
            desc = node.attrib.get('content-desc', '')
            hint = node.attrib.get('hint', '')
            match = False
            if pattern.search(text):
                match = True
            elif match_desc and pattern.search(desc):
                match = True
            elif pattern.search(hint):
                match = True
            if match:
                bounds = node.attrib.get('bounds', '')
                m = re.match(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', bounds)
                if m:
                    left, top, right, bottom = map(int, m.groups())
                    if left == 0 and top == 0 and right == 0 and bottom == 0:
                        continue
                    x = (left + right) // 2
                    y = (top + bottom) // 2
                    delta = abs(y - near_y)
                    if delta <= max_delta:
                        matches.append((delta, x, y, left, top, right, bottom, text, desc))

        if matches:
            matches.sort(key=lambda item: item[0])
            best = matches[0]
            print(f"[{device_id}] Found match for '{text_pattern}' near y={near_y}: text='{best[7]}', desc='{best[8]}' bounds=[{best[3]},{best[4]}][{best[5]},{best[6]}] (delta={best[0]}px)")
            return best[1], best[2], best[3], best[4], best[5], best[6]
    except Exception as e:
        print(f"[{device_id}] Error in find_element_near_full: {e}")
    return None

def tap(device_id, x, y):
    print(f"[{device_id}] Tapping coordinates ({x}, {y})")
    run_adb(device_id, ["shell", "input", "tap", str(x), str(y)])

def type_text(device_id, text):
    print(f"[{device_id}] Typing text: '{text}'")
    for char in text:
        if char == " ":
            escaped = "%s"
        elif char == "_":
            escaped = "\\_"
        else:
            escaped = char
        run_adb(device_id, ["shell", "input", "text", escaped])
        time.sleep(0.2)


def is_keyboard_visible(device_id):
    out, _ = run_adb(device_id, ["shell", "dumpsys input_method | grep mInputShown"])
    return "mInputShown=true" in out

def is_app_in_foreground(device_id, package="org.medimitra.family_medicine_tracker"):
    out, _ = run_adb(device_id, ["shell", "dumpsys window | grep mCurrentFocus"])
    return package in out

def ensure_app_in_foreground(device_id, package="org.medimitra.family_medicine_tracker", activity=".MainActivity"):
    if not is_app_in_foreground(device_id, package):
        print(f"[{device_id}] ⚠️ App was backgrounded. Bringing to foreground...")
        run_adb(device_id, ["shell", "am", "start", "-n", f"{package}/{activity}"])
        time.sleep(1.5)

def hide_keyboard(device_id):
    if is_keyboard_visible(device_id):
        print(f"[{device_id}] Keyboard is visible. Dismissing keyboard via KEYCODE_BACK...")
        run_adb(device_id, ["shell", "input", "keyevent", "4"])
        time.sleep(1.0)
        ensure_app_in_foreground(device_id)
    else:
        print(f"[{device_id}] Keyboard is not visible. Skipping dismissal.")


def wait_for_element(device_id, text_pattern, timeout=15):
    print(f"[{device_id}] Waiting for element '{text_pattern}' to appear (timeout={timeout}s)...")
    start = time.time()
    while time.time() - start < timeout:
        pos = find_element(device_id, text_pattern)
        if pos:
            return pos
        time.sleep(1)
    print(f"[{device_id}] ❌ Timeout waiting for element '{text_pattern}'.")
    return None


DISMISS_PATTERNS = [
    r"^Allow$",
    r"^ALLOW$",
    r"While using the app",
    r"Only this time",
    r"^OK$",
    r"^Allow all the time$",
    r"^Continue$",
    r"^Accept$",
]


def dismiss_permission_dialogs(device_id, max_rounds=2):
    """
    Taps any visible Android system permission dialog buttons (Allow / OK / While using the app).
    Runs up to `max_rounds` times so back-to-back dialogs are all cleared.
    """
    print(f"[{device_id}] 🔐 Checking for permission dialogs...")
    dismissed = 0
    for round_num in range(max_rounds):
        try:
            dump_file = get_dump(device_id)
            tree = ET.parse(dump_file)
            root = tree.getroot()
        except Exception as e:
            print(f"[{device_id}] Error getting dump in dismiss_permission_dialogs: {e}")
            break
            
        found = False
        for pattern in DISMISS_PATTERNS:
            res = find_element_in_tree(root, pattern, match_desc=True)
            if res:
                x, y, count, text, desc = res
                print(f"[{device_id}]   Tapping permission button matching '{pattern}' at ({x}, {y})")
                tap(device_id, x, y)
                time.sleep(1.2)
                dismissed += 1
                found = True
                break   # break patterns loop to fetch a new dump in next round
        if not found:
            break   # no permission dialogs found in this round
            
    if dismissed:
        print(f"[{device_id}] ✅ Dismissed {dismissed} permission dialog(s).")


def find_edit_texts(device_id):
    """
    Finds coordinates of all elements with class 'android.widget.EditText' on screen.
    """
    try:
        dump_file = get_dump(device_id)
        tree = ET.parse(dump_file)
        root = tree.getroot()
        matches = []
        for node in root.iter('node'):
            clazz = node.attrib.get('class', '')
            if clazz == 'android.widget.EditText':
                bounds = node.attrib.get('bounds', '')
                m = re.match(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', bounds)
                if m:
                    left, top, right, bottom = map(int, m.groups())
                    x = (left + right) // 2
                    y = (top + bottom) // 2
                    matches.append((x, y))
        # Sort by y-coordinate descending (but normally we want top-to-bottom for fields)
        # So let's sort top-to-bottom (y-coordinate ascending)
        matches.sort(key=lambda item: item[1])
        return matches
    except Exception as e:
        print(f"[{device_id}] Error in find_edit_texts: {e}")
        return []


def wait_for_edit_texts(device_id, count=2, timeout=10):
    """
    Waits for at least `count` elements with class 'android.widget.EditText' to appear.
    """
    print(f"[{device_id}] Waiting for {count} EditText fields to appear (timeout={timeout}s)...")
    start = time.time()
    while time.time() - start < timeout:
        fields = find_edit_texts(device_id)
        if len(fields) >= count:
            return fields
        time.sleep(1)
    print(f"[{device_id}] ❌ Timeout waiting for {count} EditText fields.")
    return []


