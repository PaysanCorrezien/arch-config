---
name: arch-config-dcli
description: "Manage and modify this arch-config repository with dcli: edit hosts and modules, add or remove packages, sync/validate configuration, and run dcli workflows (status, find, module enable/disable, update, backup/restore). Use when working inside a dcli-based Arch Linux config repo with `config.yaml`, `hosts/`, and `modules/`."
---

# Arch-config management with dcli

Use this skill to make safe, structured changes to this repo's Arch Linux configuration and apply them with dcli.

## Quick start

1. Read `config.yaml` to confirm the active host.
2. Run `dcli status` for a snapshot of sync state.
3. Make edits; rely on the PostToolUse hook to run `dcli validate` automatically (see `references/hooks.md`). If hooks are not configured, run `dcli validate` before syncing.
4. Apply changes with `dcli sync` (or `dcli update` for system upgrades).

## Progressive discovery

- Use `references/repo-layout.md` for file and module layout details.
- Use `references/dcli.md` for command overview and tips.
- Use `references/workflows.md` for task-specific workflows and decision points.
- Use `references/hooks.md` to enable hooks that auto-run `dcli validate`.
