# Host configuration recovered on 18 October 2026

This consolidation brings the useful local changes on gpu, vps1 and homebot
into arch-config. It changes the repository; it does not apply dcli sync to
the running hosts or restart their agents.

| Source | Preserved setup |
| --- | --- |
| gpu | 4 GiB Gradle heap, four build workers, smaller Kotlin heap, Cargo/CMake job defaults, private disk-backed temp files and the existing memory notes. |
| gpu and vps1 | Smaller tmux history; disable expensive pane-content capture and save every 15 minutes. Existing panes and histories are left intact. |
| gpu | Claude project sessions in tmux, terminal attachment at KDE login, packaged ChatGPT launcher with restart on failure, media WebDAV/SFTP port fixes and updated boot checks. |
| vps1 | Six registered runner unit definitions, four enabled runner choices and their restart drop-ins, existing watchdog, Btrfs allocation guard, deployment-backup retention, Docker/Tailscale boot ordering and Hermes protection drop-ins. |
| vps1 | Existing Hermes service under /opt/hermes-agent and its protection settings. Private application service definitions, checkouts and environment files remain local. |
| homebot | Restic USB backup policy and daily timer; Calibre import script and timer. Backup credentials are excluded. |
| homebot | Replace the obsolete 4 TB /dev/sda formatting hook with mounting the existing @data subvolume. |

Shared Claude settings retain the current hooks and Expo marketplace, add the
VPS Codex/Vercel plugins and GPU model setting, and keep remote control and
notifications enabled. The VPS-only removal of hooks and disabling of automatic
compaction were not spread to the other hosts. Shell PATH includes the VPS's
Cargo and npm-global paths; its noninteractive Cargo setup is preserved.

The auth and homebot hooks install definitions and enable the existing timers
for the next boot. They do not run cleanup, prune backups or restart current
processes during sync. The two third runner definitions stay disabled. Private application services
are not published or modified. Missing runtime files prevent the recovered
services from being newly enabled. Existing working checkouts and
registrations must be restored separately on a fresh host.

For homebot, the existing local backup script is preserved on an upgrade. On a
fresh installation, restore /etc/homebot-backup.env and its password file using
the example in modules/homebot-local-services. The replacement uses the USB
mount's fstab entry instead of guessing /dev/sdc1. Neither the failing backup nor
the old Hermes dashboard is claimed repaired by this repository consolidation.
The current upstream Hermes module already replaces the obsolete dashboard.

The GPU's installed OpenAI desktop package is locally named chatgpt-bin. The
[AUR package with that name](https://aur.archlinux.org/packages/chatgpt-bin)
is an unrelated command-line client. The recovered launcher supports the
working desktop binary, but this consolidation does not substitute that AUR
package for the existing desktop declaration. Its actual installer/package
recipe still needs to be recovered before fresh desktop installation is fully
reproducible.

Not imported: host-selection config.yaml changes; runtime-generated OneDrive
copies of Hermes/fleet units; debug overrides; monitor backups; transient
project test services; private application services; account state and credentials. Upstream changes newer
than each host checkout are retained. Workstation and gpu-runner were offline,
and Windows SSH was unavailable; their local-only changes remain unaudited.

Validation: run `python3 scripts/test-host-consolidation.py` with Bash 4+,
ShellCheck on changed shell scripts, and dcli validate for each host in an
isolated copy. No test needs a package upgrade or service restart.
