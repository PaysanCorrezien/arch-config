#!/usr/bin/env python3
"""Reserve Meta+Shift+F12 as the one-key Linux <-> Windows desktop handoff."""

import argparse
import os
import subprocess
import time
from glob import glob as find_glob

from evdev import InputDevice, ecodes


def freerdp_is_active(uid: int) -> bool:
    result = subprocess.run(
        ["pgrep", "-u", str(uid), "-f", r"xfreerdp3|xfreerdp|sdl-freerdp3|sdl-freerdp"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    return result.returncode == 0


def stop_winbox(uid: int) -> None:
    """Return to Linux by ending only the local RDP client.

    Windows continues running and keeps the user session, while the winbox
    wrapper performs its normal USB-release cleanup.  This is more reliable
    than trying to synthesize compositor-dependent fullscreen/minimize keys.
    """
    subprocess.run(
        ["pkill", "-TERM", "-u", str(uid), "-f", r"xfreerdp3|xfreerdp|sdl-freerdp3|sdl-freerdp"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )


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
    last_toggle = 0.0
    launch_pending_until = 0.0
    held_keys: set[int] = set()

    for event in device.read_loop():
        if event.type == ecodes.EV_KEY:
            if event.value == 1:
                held_keys.add(event.code)
            elif event.value == 0:
                held_keys.discard(event.code)

            meta_held = bool({ecodes.KEY_LEFTMETA, ecodes.KEY_RIGHTMETA} & held_keys)
            shift_held = bool({ecodes.KEY_LEFTSHIFT, ecodes.KEY_RIGHTSHIFT} & held_keys)
            if event.code == ecodes.KEY_F12:
                if event.value == 1 and meta_held and shift_held:
                    if time.monotonic() - last_toggle < 1.0:
                        continue
                    last_toggle = time.monotonic()
                    if freerdp_is_active(uid):
                        print("Meta+Shift+F12: returning to Linux desktop", flush=True)
                        stop_winbox(uid)
                    elif time.monotonic() < launch_pending_until:
                        print("Meta+Shift+F12: Windows desktop is still opening; ignored", flush=True)
                    else:
                        print("Meta+Shift+F12: opening Windows desktop", flush=True)
                        # RDP authentication and fullscreen setup take a few
                        # seconds.  Do not start a second client if the key is
                        # pressed again before xfreerdp appears in the process
                        # list.
                        launch_pending_until = time.monotonic() + 30.0
                        start_winbox(args.user, args.home, runtime_dir)

        # This is deliberately a passive observer.  Never grab and recreate
        # the user's keyboard: injecting a virtual keyboard exposed both the
        # Ctrl+Alt+Delete reboot path and Ctrl+Alt+F12's virtual-console path.
        # Meta+Shift+F12 is not a kernel console chord and works even when the
        # fullscreen RDP window suppresses Plasma global shortcuts.


if __name__ == "__main__":
    main()
