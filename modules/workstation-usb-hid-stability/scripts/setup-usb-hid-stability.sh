#!/bin/bash
# Keep Dell Universal Receiver and Realtek USB2 hub chain out of autosuspend.

set -euo pipefail

RULE_PATH="/etc/udev/rules.d/99-workstation-usb-hid-stability.rules"

sudo tee "$RULE_PATH" >/dev/null <<'RULES'
# Keep USB HID chain awake on plug/boot. ACTION is a single value (no regex/OR).

# Dell Universal Receiver (413c:301c)
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="413c", ATTR{idProduct}=="301c", TEST=="power/control", ATTR{power/control}="on"
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="413c", ATTR{idProduct}=="301c", TEST=="power/autosuspend", ATTR{power/autosuspend}="-1"
ACTION=="change", SUBSYSTEM=="usb", ATTR{idVendor}=="413c", ATTR{idProduct}=="301c", TEST=="power/control", ATTR{power/control}="on"
ACTION=="change", SUBSYSTEM=="usb", ATTR{idVendor}=="413c", ATTR{idProduct}=="301c", TEST=="power/autosuspend", ATTR{power/autosuspend}="-1"

# Realtek USB2 hub seen in dock/monitor chains (0bda:5409)
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="0bda", ATTR{idProduct}=="5409", TEST=="power/control", ATTR{power/control}="on"
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="0bda", ATTR{idProduct}=="5409", TEST=="power/autosuspend", ATTR{power/autosuspend}="-1"
ACTION=="change", SUBSYSTEM=="usb", ATTR{idVendor}=="0bda", ATTR{idProduct}=="5409", TEST=="power/control", ATTR{power/control}="on"
ACTION=="change", SUBSYSTEM=="usb", ATTR{idVendor}=="0bda", ATTR{idProduct}=="5409", TEST=="power/autosuspend", ATTR{power/autosuspend}="-1"

# Genesys USB2.1 hub seen live on workstation (05e3:0610)
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="05e3", ATTR{idProduct}=="0610", TEST=="power/control", ATTR{power/control}="on"
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="05e3", ATTR{idProduct}=="0610", TEST=="power/autosuspend", ATTR{power/autosuspend}="-1"
ACTION=="change", SUBSYSTEM=="usb", ATTR{idVendor}=="05e3", ATTR{idProduct}=="0610", TEST=="power/control", ATTR{power/control}="on"
ACTION=="change", SUBSYSTEM=="usb", ATTR{idVendor}=="05e3", ATTR{idProduct}=="0610", TEST=="power/autosuspend", ATTR{power/autosuspend}="-1"
RULES

sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=usb --action=add

echo "Installed $RULE_PATH and reloaded udev rules."
