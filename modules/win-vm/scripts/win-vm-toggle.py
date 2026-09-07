#!/usr/bin/env python3
"""Reserve Meta+Alt+W as the one-key Linux <-> Windows desktop handoff."""

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


def vm_is_active(vm_name: str) -> bool:
    """Return whether the guest is on, independently of the RDP client."""
    result = subprocess.run(
        ["virsh", "-c", "qemu:///system", "domstate", vm_name],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        env={**os.environ, "LC_ALL": "C"},
        check=False,
    )
    state = result.stdout.strip().lower()
    return result.returncode == 0 and state not in {"", "shut off", "shutoff", "crashed"}


def stop_winbox(uid: int, vm_name: str) -> None:
    """Return to Linux and request a graceful shutdown of the Windows guest.

    A second hotkey press ends the local RDP client, lets its normal USB-release
    cleanup run, then asks the guest agent to shut Windows down. It does not
    force-destroy the VM, so Windows can save work and refuse shutdown when
    appropriate. Libvirt starts it again automatically on the next host boot.
    """
    subprocess.run(
        ["pkill", "-TERM", "-u", str(uid), "-f", r"xfreerdp3|xfreerdp|sdl-freerdp3|sdl-freerdp"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    subprocess.run(
        ["virsh", "-c", "qemu:///system", "shutdown", vm_name],
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
    parser.add_argument(
        "--input-glob",
        default="/dev/input/by-id/*Dell*event-kbd",
        help="stable by-id keyboard path pattern; re-evaluated after hotplug",
    )
    parser.add_argument("--vm", required=True)
    args = parser.parse_args()

    uid = os.stat(args.home).st_uid
    runtime_dir = f"/run/user/{uid}"
    last_toggle = 0.0
    launch_pending_until = 0.0
    held_keys: set[int] = set()

    # This is deliberately a passive observer.  Never grab and recreate the
    # user's keyboard: injecting a virtual keyboard exposed both the
    # Ctrl+Alt+Delete and Ctrl+Alt+Fn are host control paths, so this binding
    # deliberately avoids both Ctrl and function keys. Meta+Alt+W also works
    # when the fullscreen RDP window suppresses Plasma global shortcuts.
    while True:
        paths = sorted(path for path in find_glob(args.input_glob) if os.path.exists(path))
        if not paths:
            # A receiver can disappear during USB reassignment.  Stay alive
            # and find it again rather than making systemd churn on a stale
            # /dev/input/eventN path.
            time.sleep(2)
            continue

        device = None
        try:
            device = InputDevice(paths[0])
            for event in device.read_loop():
                if event.type != ecodes.EV_KEY:
                    continue
                if event.value == 1:
                    held_keys.add(event.code)
                elif event.value == 0:
                    held_keys.discard(event.code)

                # Caps is remapped to Meta by the desktop, but this root evdev
                # observer sees physical KEY_CAPSLOCK before the XKB mapping.
                meta_held = bool(
                    {ecodes.KEY_LEFTMETA, ecodes.KEY_RIGHTMETA, ecodes.KEY_CAPSLOCK} & held_keys
                )
                alt_held = bool({ecodes.KEY_LEFTALT, ecodes.KEY_RIGHTALT} & held_keys)
                if event.code == ecodes.KEY_W and event.value == 1 and meta_held and alt_held:
                    if time.monotonic() - last_toggle < 1.0:
                        continue
                    last_toggle = time.monotonic()
                    if vm_is_active(args.vm) or freerdp_is_active(uid):
                        print("Meta+Alt+W: returning to Linux and shutting down Windows", flush=True)
                        stop_winbox(uid, args.vm)
                    elif time.monotonic() < launch_pending_until:
                        print("Meta+Alt+W: Windows desktop is still opening; ignored", flush=True)
                    else:
                        print("Meta+Alt+W: opening Windows desktop", flush=True)
                        # RDP authentication and fullscreen setup take a few
                        # seconds.  Do not start a second client if the key is
                        # pressed again before xfreerdp appears in the process
                        # list.
                        launch_pending_until = time.monotonic() + 30.0
                        start_winbox(args.user, args.home, runtime_dir)
        except (FileNotFoundError, OSError):
            # The selected device was unplugged or renumbered.  Rediscover it.
            held_keys.clear()
            time.sleep(1)
        finally:
            if device is not None:
                device.close()


if __name__ == "__main__":
    main()
