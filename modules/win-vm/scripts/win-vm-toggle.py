#!/usr/bin/env python3
"""Reserve Ctrl+Alt+F12 as the one-key Linux <-> Windows desktop handoff."""

import argparse
import os
import subprocess
import time
from glob import glob as find_glob

from evdev import InputDevice, UInput, ecodes


def freerdp_is_active(uid: int) -> bool:
    result = subprocess.run(
        ["pgrep", "-u", str(uid), "-f", r"xfreerdp3|xfreerdp|sdl-freerdp3|sdl-freerdp"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    return result.returncode == 0


def send_key(ui: UInput, key: int) -> None:
    ui.write(ecodes.EV_KEY, key, 1)
    ui.syn()
    ui.write(ecodes.EV_KEY, key, 0)
    ui.syn()


def start_winbox(user: str, home: str, runtime_dir: str) -> None:
    xauthority = max(find_glob(f"{runtime_dir}/xauth_*"), key=os.path.getmtime, default="")
    log_dir = os.path.join(home, ".local", "state", "win-vm")
    os.makedirs(log_dir, mode=0o700, exist_ok=True)
    log_path = os.path.join(log_dir, "winbox.log")
    environment = [
        f"HOME={home}",
        f"USER={user}",
        "DISPLAY=:0",
        f"XDG_RUNTIME_DIR={runtime_dir}",
        f"DBUS_SESSION_BUS_ADDRESS=unix:path={runtime_dir}/bus",
        "WAYLAND_DISPLAY=wayland-0",
        "XDG_SESSION_TYPE=wayland",
    ]
    if xauthority:
        environment.append(f"XAUTHORITY={xauthority}")
    with open(log_path, "ab", buffering=0) as log:
        subprocess.Popen(
            ["/usr/sbin/runuser", "-u", user, "--", "/usr/bin/env", *environment, f"{home}/.local/bin/winbox"],
            start_new_session=True,
            stdout=log,
            stderr=subprocess.STDOUT,
        )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--user", required=True)
    parser.add_argument("--home", required=True)
    parser.add_argument("--input", required=True)
    args = parser.parse_args()

    uid = os.stat(args.home).st_uid
    runtime_dir = f"/run/user/{uid}"
    device = InputDevice(args.input)
    ui = UInput.from_device(device, name="win-vm-toggle", phys="win-vm-toggle/input0")
    device.grab()
    last_toggle = 0.0
    held_keys: set[int] = set()
    suppress_f12 = False

    for event in device.read_loop():
        if event.type == ecodes.EV_KEY:
            if event.value == 1:
                held_keys.add(event.code)
            elif event.value == 0:
                held_keys.discard(event.code)

            ctrl_held = bool({ecodes.KEY_LEFTCTRL, ecodes.KEY_RIGHTCTRL} & held_keys)
            alt_held = bool({ecodes.KEY_LEFTALT, ecodes.KEY_RIGHTALT} & held_keys)
            if event.code == ecodes.KEY_F12:
                if event.value == 1 and ctrl_held and alt_held:
                    suppress_f12 = True
                    if time.monotonic() - last_toggle < 1.0:
                        continue
                    last_toggle = time.monotonic()
                    if freerdp_is_active(uid):
                        # Ctrl and Alt are already relayed as physically held.
                        # Feed FreeRDP only its two built-in actions: leave
                        # fullscreen, then minimize back to the Linux desktop.
                        send_key(ui, ecodes.KEY_ENTER)
                        time.sleep(0.25)
                        send_key(ui, ecodes.KEY_M)
                    else:
                        start_winbox(args.user, args.home, runtime_dir)
                    continue
                if suppress_f12:
                    if event.value == 0:
                        suppress_f12 = False
                    continue

        if event.type == ecodes.EV_SYN:
            ui.syn()
            continue
        ui.write_event(event)


if __name__ == "__main__":
    main()
