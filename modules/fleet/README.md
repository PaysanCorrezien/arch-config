# fleet

Lightweight fleet tracking for the arch-config hosts. Reverse GitOps: each host
pushes a state file to `paysancorrezien/fleet` (GitHub) on a 4×/day timer. Any
host can run `fleet show` to render a dashboard of the whole fleet.

## What gets tracked

Per host, in `hosts/<hostname>.yaml` of the fleet repo:

- `arch_config_commit` — the SHA the host is currently on
- `arch_config_drift` — number of commits behind `origin/master`
- `synced_at` — timestamp of the last successful sync
- `kernel`, `uptime_seconds`
- `pending_updates` — count from `checkupdates` / `pacman -Qu`
- `backups[]` — restic timers, snapper snapshots, borg timers (auto-detected)

## Install

Enable the module on a host:

```yaml
enabled_modules:
  - fleet
```

Run `dcli sync`. The post-install hook will:

1. Install the `fleet` CLI to `/usr/local/bin/fleet`.
2. Install the user-level systemd units to `~/.config/systemd/user/`.
3. Clone the fleet repo to `~/.local/share/fleet-state` (prompts for SSH if needed).
4. Enable `fleet-sync.timer` (00:00, 06:00, 12:00, 18:00 daily).

## Commands

```bash
fleet sync     # collect local state, push to fleet repo (run by the timer)
fleet show     # pull fleet repo, render dashboard
fleet status   # show this host's local state, no network
```

## Auth

The fleet repo is private. Each host needs an SSH key with push access to
`git@github.com:paysancorrezien/fleet.git`. Add one deploy key per host or use
your personal key.

## Config

Optional `~/.config/fleet/config.yaml`:

```yaml
fleet_repo: git@github.com:paysancorrezien/fleet.git
fleet_repo_path: ~/.local/share/fleet-state
arch_config_path: ~/.config/arch-config
# extra units to track (auto-detection covers restic*/borg*/snapper)
extra_backup_units:
  - my-custom-backup.timer
```

## Drift signals

- `drift > 0` — host is behind. Run `dcli sync`.
- `synced_at` older than ~24h — the timer didn't run (host down? auth broken?).
- `backups[].last_result != success` — backup needs attention.
