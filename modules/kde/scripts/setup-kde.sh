#!/usr/bin/env bash
# Post-install for KDE Plasma 6 module.
# - Installs/enables SDDM with the stock Breeze theme and a Wayland session.
# - Removes the niri-flavored Noctalia SDDM drop-in if present, so the KDE
#   host doesn't end up with the wrong theme / DisplayServer=x11.
# - Does NOT touch user dotfiles; Plasma writes its own config on first login.

set -euo pipefail

echo "[kde] Ensuring SDDM is enabled"
sudo systemctl enable sddm.service >/dev/null

echo "[kde] Removing niri Noctalia SDDM drop-in (if present)"
sudo rm -f /etc/sddm.conf.d/10-noctalia-theme.conf
# Old name from earlier iterations of this script
sudo rm -f /etc/sddm.conf.d/10-plasma-wayland.conf

echo "[kde] Writing SDDM config → Breeze theme + Plasma (Wayland)"
sudo install -d /etc/sddm.conf.d
SDDM_CONF="/etc/sddm.conf.d/20-plasma-wayland.conf"
sudo tee "$SDDM_CONF" >/dev/null <<'EOF'
[Theme]
Current=breeze

[General]
DisplayServer=wayland
InputMethod=

[Wayland]
EnableHiDPI=true
EOF

echo "[kde] Disabling niri-only user services that fight Plasma"
# mako owns org.freedesktop.Notifications via D-Bus activation
# (/usr/share/dbus-1/services/fr.emersion.mako.service), which prevents Plasma
# from delivering notifications. Stop+disable the user service AND mask the
# D-Bus activation file so notifications route to plasma_waitforname.
systemctl --user disable --now mako.service 2>/dev/null || true
# The mako package owns fr.emersion.mako.service. We can't delete it without
# removing mako, but pointing /etc/dbus-1/services/fr.emersion.mako.service to
# /dev/null on the system bus overrides the user-bus copy on most setups. The
# bulletproof fix is removing the mako package via the host `exclude:` list,
# which the gpu.yaml host already does.
if pacman -Qq mako &>/dev/null; then
  echo "[kde] WARNING: mako is still installed. Run \`sudo paru -Rns mako\` (or"
  echo "[kde]          rely on the gpu.yaml exclude + auto_prune to remove it)."
fi

echo "[kde] Disabling automatic sleep and auto-lock (manual suspend/lock still work)"
# systemd-logind: ignore idle, lid, power/suspend keys — nothing triggers sleep
# implicitly. Manual `systemctl suspend` / `loginctl lock-session` still work.
sudo install -d /etc/systemd/logind.conf.d
sudo tee /etc/systemd/logind.conf.d/50-no-idle-sleep.conf >/dev/null <<'EOF'
[Login]
IdleAction=ignore
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
EOF

# KDE Powerdevil: AC profile — never dim, never turn off screen, never suspend.
# Written as an xdg default so it applies system-wide for any user without
# clobbering per-user overrides they explicitly set later.
sudo install -d /etc/xdg
sudo tee /etc/xdg/powermanagementprofilesrc >/dev/null <<'EOF'
[AC][DimDisplay]
idleTime=-1

[AC][DPMSControl]
idleTime=-1

[AC][SuspendSession]
suspendType=0
idleTime=-1

[Battery][SuspendSession]
suspendType=0
idleTime=-1

[LowBattery][SuspendSession]
suspendType=0
idleTime=-1
EOF

# KDE screen locker: headless remote box — never auto-lock, and don't relock
# after an RDP resume either. Manual lock (Meta+L) still works.
sudo tee /etc/xdg/kscreenlockerrc >/dev/null <<'EOF'
[Daemon]
Autolock=false
LockOnResume=false
EOF

echo "[kde] Reloading user systemd to pick up portal changes (if logged in)"
systemctl --user daemon-reload 2>/dev/null || true
sudo systemctl restart systemd-logind 2>/dev/null || true

echo "[kde] Done. Reboot — SDDM will show Breeze + Plasma (Wayland) session."
