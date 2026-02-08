# arch-config

Host-based dcli configuration for CachyOS/Arch.

## Quick Start (Fresh CachyOS Install)

1. Update the system and install required tools:

```bash
sudo pacman -Syu
sudo pacman -S git
```

2. Install `dcli` (follow upstream instructions for your install method).

3. Bootstrap the repo and run `dcli sync`:

```bash
curl -fsSL https://raw.githubusercontent.com/PaysanCorrezien/arch-config/refs/heads/master/scripts/bootstrap.sh | bash
```

This will:
- Install `git`, `base-devel`, `fzf`, and `paru`.
- Install `dcli` from AUR (`dcli-arch-git`).
- Clone the repo into `~/.config/arch-config`.
- Ask you to pick a host (unless `ARCH_CONFIG_HOST` is set).
- Set `config.yaml` and run `dcli sync`.

## Host Selection

- `hosts/workstation.yaml`: Full workstation setup.
- `hosts/homebot.yaml`: Minimal desktop software with Niri + SDDM autologin.

Switch hosts by editing `config.yaml`:

```yaml
host: homebot
```

## Homebot Setup Notes

### SDDM Autologin
Homebot uses SDDM autologin via a host-specific module:
- Module: `modules/homebot-sddm`
- Config written to `/etc/sddm.conf.d/20-autologin.conf`
- Session: `niri.desktop`

### Niri Monitor Layout
Monitor and workspace assignments are host-specific and live in `~/.config/niri/monitors.kdl`.

- Workstation source: `modules/workstation-niri/dotfiles/niri/monitors.kdl`
- Homebot source: `modules/homebot-niri/dotfiles/niri/monitors.kdl`

On the homebot device, run this to get your TV output name:

```bash
niri msg outputs
```

Then update `modules/homebot-niri/dotfiles/niri/monitors.kdl` with the correct output name and mode.

### HDMI-CEC (Optional)
If the device exposes `/dev/cec*`, you can use `cec-ctl` to control TV power.
Install `v4l-utils` and use:

```bash
cec-ctl -d/dev/cecX --to 0 --standby
cec-ctl -d/dev/cecX --to 0 --image-view-on
```

## Troubleshooting

- If `dcli sync` fails due to a hook path, check module hook paths are relative to their module folder.
- If Niri cannot load `monitors.kdl`, ensure your Niri version supports `include` (v25.11+).
