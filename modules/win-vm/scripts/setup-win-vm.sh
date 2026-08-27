#!/usr/bin/env bash
# Provision the Windows 11 KVM guest for the `devbox` host.
#
# Idempotent — safe to re-run. Re-running regenerates and redefines the domain
# XML from templates/windows.xml.in, so edit the template, never the live XML.
#
# It creates the answer media and defines the machine. Windows Setup and the
# guest integration bootstrap then run unattended after the installer starts.

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="${MODULE_DIR}/templates/windows.xml.in"
UNATTEND_TEMPLATE="${MODULE_DIR}/templates/autounattend.xml.in"
GUEST_SETUP_SCRIPT="${MODULE_DIR}/scripts/setup-vm-guest.ps1"
TOGGLE_SCRIPT="${MODULE_DIR}/scripts/win-vm-toggle.py"
TOGGLE_SERVICE_TEMPLATE="${MODULE_DIR}/templates/win-vm-toggle.service.in"

TARGET_USER="${SUDO_USER:-$USER}"
if [[ "$(id -u)" -eq 0 && "${TARGET_USER}" == "root" ]]; then
  TARGET_USER="${LOGNAME:-dylan}"
fi
USER_HOME="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"
USER_UID="$(id -u "${TARGET_USER}")"
USER_GID="$(id -g "${TARGET_USER}")"
WINDEV_BOX_DIR="${WINDEV_BOX_DIR:-${USER_HOME}/windev-box}"
WINDEV_BOOTSTRAP_SCRIPT="${WINDEV_BOX_DIR}/bootstrap.ps1"
WINDEV_VAULT_SCRIPT="${WINDEV_BOX_DIR}/setup-vault.ps1"

say() { printf '[win-vm] %s\n' "$*"; }
warn() { printf '[win-vm] WARNING: %s\n' "$*" >&2; }
die() { printf '[win-vm] ERROR: %s\n' "$*" >&2; exit 1; }

# --------------------------------------------------------------------------
# 0. Tunables. Everything host-specific lives in one env file the user owns.
# --------------------------------------------------------------------------
ENV_DIR="${USER_HOME}/.config/win-vm"
ENV_FILE="${ENV_DIR}/win-vm.env"
install -d -o "${TARGET_USER}" -g "${TARGET_USER}" "${ENV_DIR}"

if [[ ! -f "${ENV_FILE}" ]]; then
  cat > "${ENV_FILE}" <<'EOF'
# win-vm tunables. Edit, then re-run the module hook (or `dcli sync`).

VM_NAME="windows"

# Memory handed to the guest, in GiB. Host has 64 GiB; 32 leaves ample room
# for KDE + Hermes + the agent fleet.
VM_MEM_GIB=32

# Physical cores RESERVED FOR THE HOST. Everything else goes to the guest.
# On a 6-core 5600G: 2 host / 4 guest (= 8 vCPU with SMT).
# Do not drop below 2 — Hermes and KWin will fight over one core and you will
# feel it as input lag inside the RDP session, which looks like "the VM is slow"
# but is actually the host compositor starving.
HOST_RESERVED_CORES=2

# Guest disk. Sparse raw file; grows on demand. 500G is a working figure for a
# dev box carrying the Android SDK, Rust toolchains and node_modules.
VM_DISK_PATH="/var/lib/libvirt/images/windows.raw"
VM_DISK_SIZE="500G"

# Fixed MAC + fixed lease so `winbox` never has to discover the guest.
VM_MAC="52:54:00:be:ef:11"
VM_IP="192.168.122.50"

# Directory shared with the guest over virtiofs (appears as Z: in Windows).
WIN_SHARE_DIR="/srv/winshare"

# USB devices handed to the guest, space-separated vendor:product from `lsusb`.
# Leave empty on first run, then fill it in — you need the guest booted once to
# know what you actually want over there.
#
# Typical members: a USB audio interface or headset, a security key, a
# monitor's built-in USB hub, or the onboard Bluetooth radio (which enumerates
# as USB, so a Bluetooth headset can be given to the guest by handing over the
# radio itself).
#
#   lsusb                    list candidates
#   lsusb | grep -i blue     find the Bluetooth radio
#
# CAUTION: a radio has one owner. While the guest holds it, the HOST has no
# Bluetooth. A second USB BT dongle is the cheap fix. See README.
WIN_VM_USB=""
EOF
  chown "${TARGET_USER}:${TARGET_USER}" "${ENV_FILE}"
  say "Wrote default tunables to ${ENV_FILE}"
fi

# shellcheck source=/dev/null
source "${ENV_FILE}"

: "${VM_NAME:=windows}"
: "${VM_MEM_GIB:=32}"
: "${HOST_RESERVED_CORES:=2}"
: "${VM_DISK_PATH:=/var/lib/libvirt/images/windows.raw}"
: "${VM_DISK_SIZE:=500G}"
: "${VM_MAC:=52:54:00:be:ef:11}"
: "${VM_IP:=192.168.122.50}"
: "${WIN_SHARE_DIR:=/srv/winshare}"
: "${WIN_VM_USB:=}"
: "${WIN_VM_USER:=dylan}"
WIN_VM_PASSWORD_FILE="${ENV_DIR}/windows-password"
UNATTEND_ISO="/var/lib/libvirt/images/iso/windows-unattend.iso"
WINDOWS_SOURCE_ISO="/var/lib/libvirt/images/iso/win11.iso"
VIRTIO_ISO="/var/lib/libvirt/images/iso/virtio-win.iso"
INSTALLER_USB_IMAGE="/var/lib/libvirt/images/iso/windows-installer-usb.img"

[[ -f "${WIN_VM_PASSWORD_FILE}" ]] || die "Create ${WIN_VM_PASSWORD_FILE} (mode 0600) with the Windows password, then re-run this hook."
WIN_VM_PASSWORD="$(<"${WIN_VM_PASSWORD_FILE}")"
[[ -n "${WIN_VM_PASSWORD}" ]] || die "${WIN_VM_PASSWORD_FILE} is empty."
[[ -f "${WINDEV_BOOTSTRAP_SCRIPT}" ]] || die "windev-box bootstrap missing: ${WINDEV_BOOTSTRAP_SCRIPT}"
[[ -f "${WINDEV_VAULT_SCRIPT}" ]] || die "windev-box vault setup missing: ${WINDEV_VAULT_SCRIPT}"

# --------------------------------------------------------------------------
# 1. Hardware preflight. Fail loudly and early rather than at `virsh start`.
# --------------------------------------------------------------------------
say "Checking virtualisation support..."
if ! grep -qE '^flags.*\bsvm\b' /proc/cpuinfo; then
  die "AMD-V (svm) not present in /proc/cpuinfo.
       Enable SVM in the BIOS: Advanced -> CPU Configuration -> SVM Mode.
       (IOMMU is NOT required for this setup — only SVM.)"
fi
[[ -e /dev/kvm ]] || die "/dev/kvm missing. Is the kvm_amd module loaded? (modprobe kvm_amd)"
say "  ok — SVM present, /dev/kvm exists"

# --------------------------------------------------------------------------
# 2. libvirt daemon + group membership
# --------------------------------------------------------------------------
say "Enabling libvirtd and adding ${TARGET_USER} to libvirt/kvm..."
sudo systemctl enable --now libvirtd.socket >/dev/null
sudo usermod -aG libvirt,kvm "${TARGET_USER}"

# QEMU must run as the desktop user, not as `qemu`. Two reasons, both hard
# requirements here:
#   * PipeWire audio lives at /run/user/<uid>/pipewire-0 and is only reachable
#     by that user.
#   * virtiofsd needs to read/write the share as a real user, not nobody.
say "Pointing /etc/libvirt/qemu.conf at ${TARGET_USER}..."
sudo install -m 0644 /etc/libvirt/qemu.conf /etc/libvirt/qemu.conf.bak-win-vm 2>/dev/null || true
if grep -qE '^\s*#?\s*user\s*=' /etc/libvirt/qemu.conf; then
  sudo sed -i "s|^\s*#\?\s*user\s*=.*|user = \"${TARGET_USER}\"|" /etc/libvirt/qemu.conf
else
  printf 'user = "%s"\n' "${TARGET_USER}" | sudo tee -a /etc/libvirt/qemu.conf >/dev/null
fi
if grep -qE '^\s*#?\s*group\s*=' /etc/libvirt/qemu.conf; then
  sudo sed -i "s|^\s*#\?\s*group\s*=.*|group = \"${TARGET_USER}\"|" /etc/libvirt/qemu.conf
else
  printf 'group = "%s"\n' "${TARGET_USER}" | sudo tee -a /etc/libvirt/qemu.conf >/dev/null
fi
sudo systemctl restart libvirtd 2>/dev/null || true

# --------------------------------------------------------------------------
# 3. Default NAT network + fixed lease
# --------------------------------------------------------------------------
say "Ensuring libvirt default network is up with a fixed lease for the guest..."
sudo virsh net-autostart default >/dev/null 2>&1 || true
sudo virsh net-start default >/dev/null 2>&1 || true
# Remove any stale reservation for this MAC, then add ours. --live --config so
# it applies now and persists.
sudo virsh net-update default delete ip-dhcp-host \
  "<host mac='${VM_MAC}'/>" --live --config >/dev/null 2>&1 || true
sudo virsh net-update default add ip-dhcp-host \
  "<host mac='${VM_MAC}' name='${VM_NAME}' ip='${VM_IP}'/>" --live --config >/dev/null 2>&1 \
  || warn "Could not add DHCP reservation for ${VM_IP} — check it is inside the default network's range."

# --------------------------------------------------------------------------
# 4. Shared directory (virtiofs -> Z:)
# --------------------------------------------------------------------------
say "Preparing shared directory ${WIN_SHARE_DIR}..."
sudo install -d -o "${TARGET_USER}" -g "${TARGET_USER}" -m 0755 "${WIN_SHARE_DIR}"
sudo install -d -o "${TARGET_USER}" -g "${TARGET_USER}" -m 0755 \
  "${WIN_SHARE_DIR}/exchange" "${WIN_SHARE_DIR}/documents" "${WIN_SHARE_DIR}/screenshots"
if [[ ! -e "${USER_HOME}/winshare" ]]; then
  sudo -u "${TARGET_USER}" ln -sfn "${WIN_SHARE_DIR}" "${USER_HOME}/winshare"
fi
if [[ ! -f "${WIN_SHARE_DIR}/READ-ME-FIRST.txt" ]]; then
  sudo -u "${TARGET_USER}" tee "${WIN_SHARE_DIR}/READ-ME-FIRST.txt" >/dev/null <<'EOF'
This directory is shared between the Arch host and the Windows guest.
  Host:  /srv/winshare   (also ~/winshare)
  Guest: Z:\

USE IT FOR: documents, screenshots, logs, build artefacts, anything you want
to hand between the two sides.

DO NOT PUT GIT WORKTREES, node_modules, OR BUILD TREES HERE.

virtiofs does not give you POSIX symlink and case-sensitivity semantics that
match on both sides. pnpm's store is symlink-heavy, and a repo checked out on
one side and built on the other will produce breakage that looks like a code
bug and is not. Keep repos native to whichever OS builds them.
EOF
fi

# --------------------------------------------------------------------------
# 5. Disk image
# --------------------------------------------------------------------------
IMAGES_DIR="$(dirname "${VM_DISK_PATH}")"
sudo install -d -m 0711 "${IMAGES_DIR}"
sudo install -d -m 0755 "${IMAGES_DIR}/iso"

# Windows' DVD UEFI wrapper accepts a key for only a few milliseconds, which
# is unsuitable for a declarative VM setup.  Build a normal FAT32 USB installer
# instead.  FAT32 cannot contain the 6+ GiB install.wim, so wimlib splits it
# into install.swm parts — the format Windows Setup natively expects on USB.
if [[ ! -f "${INSTALLER_USB_IMAGE}" ]]; then
  [[ -f "${WINDOWS_SOURCE_ISO}" ]] || die "Windows source ISO missing: ${WINDOWS_SOURCE_ISO}"
  [[ -f "${VIRTIO_ISO}" ]] || die "VirtIO driver ISO missing: ${VIRTIO_ISO}"
  command -v wimlib-imagex >/dev/null || die "wimlib is required to build the virtual Windows installer USB"
  command -v 7z >/dev/null || die "7zip is required to build the virtual Windows installer USB"
  command -v parted >/dev/null || die "parted is required to build the virtual Windows installer USB"
  say "Building one-time FAT32 Windows installer USB..."
  INSTALLER_TREE="$(mktemp -d -p /var/tmp win-vm-installer.XXXXXX)"
  sudo truncate -s 10G "${INSTALLER_USB_IMAGE}"
  sudo parted -s "${INSTALLER_USB_IMAGE}" mklabel gpt \
    mkpart primary fat32 1MiB 100% set 1 esp on
  INSTALLER_LOOP="$(sudo losetup --find --show --partscan "${INSTALLER_USB_IMAGE}")"
  INSTALLER_PARTITION="${INSTALLER_LOOP}p1"
  sudo mkfs.fat -F 32 -n WIN11SETUP "${INSTALLER_PARTITION}" >/dev/null
  7z x -y -o"${INSTALLER_TREE}" "${WINDOWS_SOURCE_ISO}" >/dev/null
  # Setup automatically loads drivers from $WinPEDriver$ on installation media.
  # The guest disk is virtio-blk, so viostor is required before Disk 0 exists.
  mkdir -p "${INSTALLER_TREE}/\$WinPEDriver\$"
  7z x -y -o"${INSTALLER_TREE}/\$WinPEDriver\$" "${VIRTIO_ISO}" \
    'viostor/w11/amd64/*' >/dev/null
  INSTALL_WIM="$(mktemp -p /var/tmp win-vm-install.XXXXXX.wim)"
  mv "${INSTALLER_TREE}/sources/install.wim" "${INSTALL_WIM}"
  sudo mcopy -i "${INSTALLER_PARTITION}" -s "${INSTALLER_TREE}"/* ::
  sudo wimlib-imagex split "${INSTALL_WIM}" \
    "${INSTALLER_TREE}/sources/install.swm" 3800
  sudo mcopy -i "${INSTALLER_PARTITION}" "${INSTALLER_TREE}/sources/install"*.swm ::/sources/
  sudo losetup --detach "${INSTALLER_LOOP}"
  rm -f "${INSTALL_WIM}"
  sudo chown "${TARGET_USER}:${TARGET_USER}" "${INSTALLER_USB_IMAGE}"
  sudo chmod 0644 "${INSTALLER_USB_IMAGE}"
fi

# Windows Setup discovers Autounattend.xml on this CD; it also carries the
# first-login script that installs VirtIO, RDP and the shared drive.
UNATTEND_DIR="$(mktemp -d)"
trap 'rm -rf "${UNATTEND_DIR}"' EXIT
sed -e "s|@VM_USER@|${WIN_VM_USER}|g" -e "s|@VM_PASSWORD@|${WIN_VM_PASSWORD}|g" \
  "${UNATTEND_TEMPLATE}" > "${UNATTEND_DIR}/Autounattend.xml"
sed "s|@VM_NAME@|${VM_NAME}|g" "${GUEST_SETUP_SCRIPT}" > "${UNATTEND_DIR}/setup-vm-guest.ps1"
mkdir -p "${UNATTEND_DIR}/windev-box"
install -m 0644 "${WINDEV_BOOTSTRAP_SCRIPT}" "${UNATTEND_DIR}/windev-box/bootstrap.ps1"
install -m 0644 "${WINDEV_VAULT_SCRIPT}" "${UNATTEND_DIR}/windev-box/setup-vault.ps1"
install -m 0644 "${USER_HOME}/.ssh/win-vm-control.pub" "${UNATTEND_DIR}/host-authorized-key.pub"
sudo xorriso -as mkisofs -quiet -iso-level 3 -J -R -V WINSETUP -o "${UNATTEND_ISO}" "${UNATTEND_DIR}"
sudo chown "${TARGET_USER}:${TARGET_USER}" "${UNATTEND_ISO}"

# On btrfs, VM images MUST be nocow or fragmentation and snapshot cost explode.
# chattr +C only takes effect on files created afterwards, so it goes on the
# directory before the image exists. (Same reasoning as modules/docker's
# btrfs-nocow-migrate.sh.)
if [[ "$(stat -f -c %T "${IMAGES_DIR}")" == "btrfs" ]]; then
  say "  ${IMAGES_DIR} is btrfs — setting nocow (+C) on the directory"
  sudo chattr +C "${IMAGES_DIR}" 2>/dev/null || warn "chattr +C failed on ${IMAGES_DIR}"
fi

if [[ ! -f "${VM_DISK_PATH}" ]]; then
  say "Creating sparse ${VM_DISK_SIZE} raw image at ${VM_DISK_PATH}"
  sudo truncate -s "${VM_DISK_SIZE}" "${VM_DISK_PATH}"
  sudo chown "${TARGET_USER}:${TARGET_USER}" "${VM_DISK_PATH}"
  sudo chmod 0600 "${VM_DISK_PATH}"
else
  say "  disk already exists: ${VM_DISK_PATH} (left untouched)"
fi

# --------------------------------------------------------------------------
# 6. CPU pinning, computed from the real topology
# --------------------------------------------------------------------------
# Hardcoding cpusets is how pinning silently rots after a CPU swap or a kernel
# that enumerates siblings differently. Derive it instead.
say "Computing CPU pinning from live topology..."
mapfile -t CPU_CORE < <(lscpu -p=CPU,CORE | grep -v '^#')
declare -A CORE_THREADS=()
declare -a CORE_ORDER=()
for line in "${CPU_CORE[@]}"; do
  cpu="${line%%,*}"; core="${line##*,}"
  if [[ -z "${CORE_THREADS[$core]+x}" ]]; then
    CORE_THREADS[$core]="$cpu"; CORE_ORDER+=("$core")
  else
    CORE_THREADS[$core]="${CORE_THREADS[$core]} $cpu"
  fi
done

TOTAL_CORES="${#CORE_ORDER[@]}"
(( TOTAL_CORES > HOST_RESERVED_CORES )) \
  || die "HOST_RESERVED_CORES=${HOST_RESERVED_CORES} leaves nothing for the guest (${TOTAL_CORES} cores total)."

GUEST_CORES=$(( TOTAL_CORES - HOST_RESERVED_CORES ))
# Threads-per-core, read off core 0.
read -r -a _t0 <<< "${CORE_THREADS[${CORE_ORDER[0]}]}"
THREADS_PER_CORE="${#_t0[@]}"
VCPUS=$(( GUEST_CORES * THREADS_PER_CORE ))

HOST_CPUSET=""
CPUTUNE_LINES=""
vcpu=0
for idx in "${!CORE_ORDER[@]}"; do
  core="${CORE_ORDER[$idx]}"
  read -r -a threads <<< "${CORE_THREADS[$core]}"
  if (( idx < HOST_RESERVED_CORES )); then
    for t in "${threads[@]}"; do
      HOST_CPUSET="${HOST_CPUSET:+${HOST_CPUSET},}${t}"
    done
  else
    # Consecutive vCPUs land on the same physical core, so the guest's
    # cores=N threads=2 topology maps 1:1 onto real SMT pairs.
    for t in "${threads[@]}"; do
      CPUTUNE_LINES+="    <vcpupin vcpu='${vcpu}' cpuset='${t}'/>"$'\n'
      vcpu=$(( vcpu + 1 ))
    done
  fi
done

CPUTUNE="  <cputune>
${CPUTUNE_LINES}    <emulatorpin cpuset='${HOST_CPUSET}'/>
    <iothreadpin iothread='1' cpuset='${HOST_CPUSET}'/>
    <iothreadpin iothread='2' cpuset='${HOST_CPUSET}'/>
  </cputune>"

say "  ${TOTAL_CORES} cores / ${THREADS_PER_CORE} threads each"
say "  host keeps cpus ${HOST_CPUSET}; guest gets ${VCPUS} vCPU (${GUEST_CORES}c x ${THREADS_PER_CORE}t)"

# --------------------------------------------------------------------------
# 7. USB hostdev block
# --------------------------------------------------------------------------
HOSTDEV=""
if [[ -n "${WIN_VM_USB}" ]]; then
  say "  USB peripherals will attach only while winbox is open: ${WIN_VM_USB}"
else
  HOSTDEV=""
  warn "WIN_VM_USB is empty — no physical USB peripherals will follow winbox."
  warn "That is fine for playback, but NOT a faithful capture path for dictation work."
fi

# --------------------------------------------------------------------------
# 8. Render + define the domain
# --------------------------------------------------------------------------
[[ -f "${TEMPLATE}" ]] || die "Template missing: ${TEMPLATE}"

EXISTING_UUID="$(sudo virsh domuuid "${VM_NAME}" 2>/dev/null | tr -d '[:space:]' || true)"
UUID="${EXISTING_UUID:-$(uuidgen)}"

WORK_XML="$(mktemp)"
trap 'rm -f "${WORK_XML}"' EXIT

# Pure-bash substitution: ${var//pat/repl} handles multi-line replacements and,
# unlike sed, does not reinterpret & or backslashes in the replacement text —
# which matters because CPUTUNE and HOSTDEV are multi-line XML fragments.
# Also keeps this module free of a python dependency.
MEM_KIB=$(( VM_MEM_GIB * 1024 * 1024 ))
rendered="$(cat "${TEMPLATE}")"
rendered="${rendered//@NAME@/${VM_NAME}}"
rendered="${rendered//@UUID@/${UUID}}"
rendered="${rendered//@MEM_KIB@/${MEM_KIB}}"
rendered="${rendered//@VCPUS@/${VCPUS}}"
rendered="${rendered//@CORES@/${GUEST_CORES}}"
rendered="${rendered//@THREADS@/${THREADS_PER_CORE}}"
rendered="${rendered//@CPUTUNE@/${CPUTUNE}}"
rendered="${rendered//@DISK_PATH@/${VM_DISK_PATH}}"
rendered="${rendered//@INSTALLER_USB_IMAGE@/${INSTALLER_USB_IMAGE}}"
rendered="${rendered//@MAC@/${VM_MAC}}"
rendered="${rendered//@UID@/${USER_UID}}"
rendered="${rendered//@SHARE_DIR@/${WIN_SHARE_DIR}}"
rendered="${rendered//@HOSTDEV@/${HOSTDEV}}"
printf '%s\n' "${rendered}" > "${WORK_XML}"

if grep -qE '@[A-Z_]+@' "${WORK_XML}"; then
  die "Unsubstituted placeholders remain in the rendered XML: $(grep -oE '@[A-Z_]+@' "${WORK_XML}" | sort -u | tr '\n' ' ')"
fi

say "Defining domain '${VM_NAME}'..."
sudo virsh define "${WORK_XML}" >/dev/null
sudo virsh autostart "${VM_NAME}" >/dev/null 2>&1 || true
say "  defined (uuid ${UUID})"

# NetworkManager must leave libvirt's bridge and ephemeral vnet taps alone.
# Otherwise it may adopt a tap after boot and detach it from virbr0, leaving a
# Windows guest with APIPA instead of the reserved DHCP address.
NM_LIBVIRT_CONF='/etc/NetworkManager/conf.d/30-libvirt-unmanaged.conf'
if command -v nmcli >/dev/null 2>&1; then
  say "Keeping NetworkManager away from libvirt bridge/tap devices..."
  printf '%s\n' '[keyfile]' 'unmanaged-devices=interface-name:virbr*;interface-name:vnet*' | \
    sudo tee "${NM_LIBVIRT_CONF}" >/dev/null
  sudo nmcli general reload || warn "Could not reload NetworkManager configuration; it will apply after restart."
fi

# UFW defaults to denying routed traffic.  Libvirt's NAT rule can only
# masquerade packets that make it through FORWARD, so allow this guest bridge
# to initiate outbound connections on the active uplink.  Return traffic is
# still constrained by UFW's established/related rule.
if command -v ufw >/dev/null 2>&1 && sudo ufw status | grep -q 'Status: active'; then
  HOST_UPLINK="$(ip route show default | awk '/default/ {print $5; exit}')"
  if [[ -n "${HOST_UPLINK}" ]] && ! sudo ufw status | grep -Fq 'Windows VM NAT'; then
    say "Allowing Windows VM NAT through UFW (${HOST_UPLINK})..."
    sudo ufw route allow in on virbr0 out on "${HOST_UPLINK}" comment 'Windows VM NAT'
  fi
fi

# --------------------------------------------------------------------------
# 9. KWin rule — the piece that decides whether this feels transparent
# --------------------------------------------------------------------------
# Without this, KDE global shortcuts swallow Meta, Alt+Tab and every other
# bound key BEFORE the FreeRDP window sees them, and Windows feels subtly
# broken in a way that is very hard to diagnose from inside the guest.
say "Installing KWin rule so the RDP window receives all keys..."
KWIN_RULES="${USER_HOME}/.config/kwinrulesrc"
if ! grep -q 'win-vm-freerdp' "${KWIN_RULES}" 2>/dev/null; then
  RULE_INDEX=$(( $(grep -c '^\[' "${KWIN_RULES}" 2>/dev/null || echo 0) + 1 ))
  sudo -u "${TARGET_USER}" tee -a "${KWIN_RULES}" >/dev/null <<EOF

[${RULE_INDEX}]
Description=win-vm-freerdp
wmclass=freerdp
wmclasscomplete=false
wmclassmatch=2
ignoregeometry=true
ignoregeometryrule=3
disableglobalshortcuts=true
disableglobalshortcutsrule=2
fullscreen=true
fullscreenrule=3
above=true
aboverule=2
EOF
  say "  added rule to ${KWIN_RULES} (takes effect after: kwin_wayland --replace, or relogin)"
else
  say "  rule already present"
fi

# --------------------------------------------------------------------------
# 10. One physical key toggles into Windows and back out again.
# --------------------------------------------------------------------------
TOGGLE_INPUT="$(find /dev/input/by-id -maxdepth 1 -type l -name '*Dell*event-kbd' -print -quit 2>/dev/null || true)"
if [[ -n "${TOGGLE_INPUT}" ]]; then
  say "Installing Ctrl+Alt+F12 desktop-handoff key service..."
  sudo install -D -m 0755 "${TOGGLE_SCRIPT}" /usr/local/lib/win-vm/win-vm-toggle.py
  TOGGLE_UNIT="$(sed -e "s|@USER@|${TARGET_USER}|g" -e "s|@HOME@|${USER_HOME}|g" -e "s|@INPUT@|${TOGGLE_INPUT}|g" "${TOGGLE_SERVICE_TEMPLATE}")"
  printf '%s\n' "${TOGGLE_UNIT}" | sudo tee /etc/systemd/system/win-vm-toggle.service >/dev/null
  sudo systemctl daemon-reload
  sudo systemctl enable --now win-vm-toggle.service
else
  warn "Dell keyboard input was not found; Pause/Break handoff service was not installed."
fi

# --------------------------------------------------------------------------
# 11. Next steps
# --------------------------------------------------------------------------
cat <<EOF

[win-vm] ================= READY FOR WINDOWS INSTALL =================

Windows 11 Pro, VirtIO drivers, RDP, OpenSSH, the virtiofs share and the
host-local SSH control key are staged. Start it once with:

  virsh -c qemu:///system start ${VM_NAME}

The virtual USB installer starts automatically; all Windows installation and
guest configuration then runs automatically. Once
RDP becomes reachable, daily use is simply: winbox

Tunables:      ${ENV_FILE}
Shared drive:  ${WIN_SHARE_DIR}  (host)  ->  Z:  (guest)  ->  ~/winshare symlink
Guest address: ${VM_IP}
USB hotplug:   win-usb list | win-usb attach <vendor:product> | win-usb detach <vendor:product>

EOF
