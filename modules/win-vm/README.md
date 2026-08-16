# win-vm

Windows 11 as a KVM guest on the `devbox` host, delivered as a fullscreen
multi-monitor RDP session on KDE. Arch underneath, Windows on top, Hermes
running natively on the host instead of on Windows.

## What this is not

There is **no GPU passthrough**. No VFIO, no `vfio-pci`, no IOMMU requirement,
no second graphics card, no Looking Glass, no monitor input switching. The
5600G's iGPU stays with the host and drives both monitors; the guest has no GPU
and its desktop travels over RDP.

The only BIOS change required is **SVM (AMD-V)**.

## Layout

```
Arch host — KDE Plasma 6 (Wayland), iGPU drives both monitors
├── Hermes                     systemd --user units
└── libvirt / KVM
    └── windows                4c/8t pinned, 32 GB, no GPU
        ├── virtiofs           /srv/winshare  ->  Z:
        ├── USB hostdev        audio devices, BT radio  -> real audio
        └── RDP :3389          <- winbox, fullscreen, /multimon
```

## Files

| Path | Role |
|---|---|
| `packages.yaml` | libvirt/QEMU, OVMF + swtpm (Win11 needs both), virtiofsd, freerdp |
| `templates/windows.xml.in` | Guest definition. **Edit this, never the live XML.** |
| `scripts/setup-win-vm.sh` | Preflight, libvirt config, share, disk, pinning, define, KWin rule |
| `dotfiles/bin/winbox` | Daily entry point — start + connect fullscreen |
| `dotfiles/bin/win-usb` | Hot-plug USB between host and guest |
| `~/.config/win-vm/win-vm.env` | All tunables. Generated on first run, yours thereafter. |

## Setup

1. **BIOS**: enable SVM. (`Advanced -> CPU Configuration -> SVM Mode`)
2. `dcli sync` with `host: devbox`, accept the `win-vm` hook.
3. Drop ISOs into `/var/lib/libvirt/images/iso/`:
   - `win11.iso` — must be **Windows 11 Pro**. Home has no RDP server and this
     whole design collapses without it.
   - `virtio-win.iso` — from the [virtio-win direct downloads](https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/)
4. Log out and back in (you were added to `libvirt` and `kvm`).
5. `winbox --console`, install Windows. At the disk-selection step the disk is
   invisible until you **Load driver** from the virtio-win CD → `viostor`.
6. Guest-side configuration is **`windev-box`'s job**, run manually inside the
   VM once it boots — see `windev-box/setup-vm-guest.ps1`. This module
   deliberately does not reach into the guest.
7. Detach both CDROMs, reboot, then `winbox`.

## Audio — read this before filing a bug

Two paths exist and they are not equivalent.

**Emulated (`ich9` HDA over PipeWire).** Always present, zero configuration.
Roughly 20–40 ms, resampled on the way in. Fine for system sounds, calls, and
playback.

**USB hostdev passthrough.** Windows gets the real device. This is the only
honest path for anything where capture fidelity or latency matters.

A **Bluetooth** headset cannot be passed directly — it is not a USB device, it
is a profile negotiated by the host's radio. Pass the **radio** instead (it
enumerates as USB, so a plain `<hostdev type='usb'>` handles it — no IOMMU
needed) and Windows pairs the headset itself with native drivers.

```bash
lsusb | grep -i blue      # find the radio
win-usb attach <id>       # hand it over
```

While the radio belongs to the guest, **the host has no Bluetooth**. That is
inherent to radio ownership, not a bug. A second USB Bluetooth dongle (~€10)
gives each side its own and ends the argument.

Do **not** validate latency-sensitive capture behaviour through RDP's `/sound` and
`/microphone` redirection. You will be measuring the transport.

## Shared drive

`/srv/winshare` on the host (symlinked at `~/winshare`) appears as `Z:` in the
guest via virtiofs. Guest side needs WinFsp plus the `VirtioFsSvc` service from
virtio-win — `windev-box` handles that.

**Do not put git worktrees, `node_modules`, or build trees on the share.**
virtiofs does not give matching symlink and case-sensitivity semantics on both
sides. pnpm's store is symlink-heavy, and a repo checked out on one side and
built on the other produces failures that look exactly like code bugs. Keep
repos native to whichever OS builds them; use the share for documents,
screenshots, logs, and artefacts.

This is also why `<memoryBacking>` uses `memfd` with `access mode='shared'` —
virtiofs requires shared memory backing. Converting that to static hugepages
kills the share (and would permanently subtract 32 GB from the host).

## The KWin rule

The setup script adds a rule matching `wmclass=freerdp` with
`disableglobalshortcuts=true`.

Without it, KDE global shortcuts intercept Meta, Alt+Tab, and everything else
you have bound **before the guest ever sees them**, and Windows feels subtly
broken in a way that is near-impossible to diagnose from inside the VM. With
it, the guest receives every key.

Keep one escape hatch bound in KWin's own namespace (a virtual-desktop switch)
so you can always get back out; FreeRDP's `Ctrl+Alt+Enter` also toggles
fullscreen.

## CPU pinning

Computed at setup time from `lscpu -p=CPU,CORE`, not hardcoded — hardcoded
cpusets rot silently after a CPU swap or a kernel that enumerates SMT siblings
differently. `HOST_RESERVED_CORES=2` keeps two physical cores for KDE and
Hermes; the rest go to the guest with consecutive vCPUs landing on the same
physical core so the guest's `cores=N threads=2` topology maps 1:1 onto real
SMT pairs.

Do not reserve fewer than 2. KWin and Hermes contending for one core shows up
as input lag *inside* the RDP session, which reads as "the VM is slow" and is
actually the host compositor starving.

## Honest limits

- **No GPU in the guest.** Windows renders through WARP, then the host encodes
  to RDP. IDE and terminal work is fine — that is what RDP is good at. Electron
  apps are usable but not crisp; Electron dev loops may need `--disable-gpu`.
  Anything GPU-accelerated you are testing will not reflect real users.
- **4 cores, not 6.** Builds are measurably slower than on bare metal. The
  alternative (more cores) means a non-G Ryzen, which has no iGPU, which means a
  second GPU, which means a new board — a different project.
- **RDP session ≠ console session.** UI-automation and window/focus tracking
  still work, but session lifetime, DPI, and lock-screen behaviour
  differ from bare metal. Validate this early if you rely on either.

## Troubleshooting

| Symptom | Cause |
|---|---|
| `winbox` times out on :3389 | Guest is Windows Home; or RDP not enabled; or Windows Firewall |
| No disk during Windows install | `viostor` not loaded from the virtio-win CD |
| Guest boots to UEFI shell | ISO not attached, or Secure Boot vars not enrolled — `virsh undefine --nvram` and re-run the hook |
| Z: missing in guest | WinFsp or `VirtioFsSvc` not installed/started |
| No audio in guest at all | QEMU not running as your user — check `user =` in `/etc/libvirt/qemu.conf` |
| Meta / Alt+Tab never reach Windows | KWin rule not applied — relogin, or `kwin_wayland --replace` |
| Every symbol key is wrong | `RDP_KBD` layout mismatch — French is `0x0000040C` |
