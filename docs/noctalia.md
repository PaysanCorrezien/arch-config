# Noctalia Shell

Quick notes for running Noctalia as a user service and finding logs.

## Service
- Restart: `systemctl --user restart noctalia.service`
- Status: `systemctl --user status noctalia.service`
- Reload unit files after edits: `systemctl --user daemon-reload`

## Dev service config
- Override file: `~/.config/systemd/user/noctalia.service.d/override.conf`
- Repo source: `modules/onedrive/dotfiles/systemd/user/noctalia.service.d/override.conf`
- Debug hot-reload env: `Environment="NOCTALIA_DEBUG=1"`

## Logs
- Quickshell by-id logs: `/run/user/$UID/quickshell/by-id/<run-id>/log.qslog`
- Find latest: `ls -lt /run/user/$UID/quickshell/by-id/`
- Tail latest: `tail -f /run/user/$UID/quickshell/by-id/<run-id>/log.qslog`
- Service journal: `journalctl --user -u noctalia.service -n 200 --no-pager`
