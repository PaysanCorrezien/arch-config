# Repository layout

## Root
- `config.yaml`: points to the active host configuration.
- `hosts/`: host-specific configuration files.
- `modules/`: module definitions (packages, dotfiles, hooks).
- `scripts/`: helper scripts referenced by modules.
- `state/`: runtime state/cache used by dcli.

## Hosts
- `hosts/<host>.yaml` commonly defines:
  - `host`, `description`
  - `enabled_modules`, `module_processing`
  - `packages`, `exclude`
  - `config_backups`, `system_backups`
  - `update_hooks`
  - `flatpak_scope`, `auto_prune`, `aur_helper`
  - `services`, `default_apps`

## Modules
Two supported patterns:

1) Single YAML module
- `modules/<name>.yaml` with `description` and `packages` list.

2) Directory module
- `modules/<name>/module.yaml`: module metadata, conflicts, dotfiles sync, hooks.
- `modules/<name>/packages.yaml`: package list for the module.
- `modules/<name>/dotfiles/`: config files synced to `~/.config/` when enabled.
- `modules/<name>/scripts/`: helper scripts referenced by hooks.

## Special module files
- `modules/declared-packages.yaml`: packages added via `dcli install` or `dcli search`.
