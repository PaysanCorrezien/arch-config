# dcli command overview

## Day-to-day
- `dcli status`: show configuration and sync status.
- `dcli validate`: validate repo structure and module schemas.
- `dcli sync`: install/remove packages to match configuration.
- `dcli update`: update system (respects version constraints).

## Modules and packages
- `dcli module list | enable | disable | run-hook`.
- `dcli find <package>`: locate where a package is defined.
- `dcli merge`: import unmanaged installed packages into config.
- `dcli install <package>` / `dcli remove <package>`: install/remove via pacman.

## Interactive tools
- `dcli search`: interactive package search.
- `dcli edit`: interactive config file selector.
- `dcli tui`: full interactive TUI.

## Backup and repo
- `dcli save-config` / `dcli restore-config`.
- `dcli backup` / `dcli restore`.
- `dcli repo`: git repository management.
- `dcli hooks`: post-install hook management.

## Bootstrap and migration
- `dcli init` or `dcli migrate`: use only when bootstrapping or migrating.

## Tips
- Use `dcli <command> --help` for subcommand details.
- Use `-j/--json` for structured output.
