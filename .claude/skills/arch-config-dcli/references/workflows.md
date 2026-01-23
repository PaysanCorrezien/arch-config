# Workflows and decisions

Use this file when you need step-by-step guidance for common tasks.

## Decision guide

- Add/remove packages: edit module `packages.yaml` or `modules/<name>.yaml`; use `dcli find <package>` to locate entries.
- Host-specific tweaks: edit `hosts/<host>.yaml` `packages`, `exclude`, or `enabled_modules`.
- Complex module changes: use `modules/<name>/` with `module.yaml`, `packages.yaml`, and optional `dotfiles/` or `scripts/`.
- Unmanaged packages: use `dcli merge` to import installed packages into `modules/declared-packages.yaml`.
- Backups: use `dcli save-config` or `dcli backup` before risky changes.

## Add a package to an existing module

1. Use `dcli find <package>` to confirm the package is not already defined.
2. Edit the module's `packages.yaml` (or `modules/<name>.yaml`).
3. Run `dcli validate` (unless hooks are configured), then `dcli sync`.

## Create a new module

1. Simple package list: create `modules/<name>.yaml` with `description` and `packages`.
2. Module with dotfiles/hooks: create `modules/<name>/module.yaml` and `modules/<name>/packages.yaml`, plus optional `dotfiles/` and `scripts/`.
3. Add the module to `hosts/<host>.yaml` `enabled_modules` or run `dcli module enable <name>`.
4. Run `dcli validate` (unless hooks are configured), then `dcli sync`.

## Enable or disable a module for a host

1. Edit `hosts/<host>.yaml` `enabled_modules` directly, or use `dcli module enable/disable <name>`.
2. Run `dcli validate` (unless hooks are configured), then `dcli sync`.

## Add host-specific packages

1. Edit `hosts/<host>.yaml` `packages`.
2. Run `dcli validate` (unless hooks are configured), then `dcli sync`.

## Remove a package

1. Use `dcli find <package>` to locate where it is defined.
2. Remove it from the relevant module or host list.
3. Run `dcli sync` to remove it from the system.

## Troubleshoot or verify

1. Use `dcli status` to check drift and sync state.
2. Use `dcli validate` to catch schema issues early (or rely on hooks).
3. If needed, use `dcli module list` and `dcli module run-hook <name>`.
