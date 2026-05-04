# arch-config — common workflows
# Run `just` (no args) to list recipes.

set shell := ["bash", "-euo", "pipefail", "-c"]
set dotenv-load := false

config := "config.yaml"

# default: list recipes
default:
    @just --list

# ─── status / inspection ──────────────────────────────────────────────────

# show dcli status for the active host
status:
    dcli status

# validate the full configuration (syntax + references)
validate:
    dcli validate

# validate every host by swapping the pointer (non-destructive, restores after)
validate-all:
    #!/usr/bin/env bash
    set -euo pipefail
    original=$(awk '/^host:/ {print $2}' {{config}})
    trap 'sed -i "s/^host: .*/host: '"$original"'/" {{config}}' EXIT
    for h in $(ls hosts/*.yaml | xargs -n1 basename | sed 's/\.yaml$//'); do
      [[ "$h" == profiles ]] && continue
      echo "── $h ──"
      sed -i "s/^host: .*/host: $h/" {{config}}
      dcli validate 2>&1 | tail -3
    done

# list modules enabled for the active host (including imports)
modules:
    dcli status 2>&1 | grep -E "^  ✓|^Enabled modules"

# find where a package is declared
find PKG:
    dcli find {{PKG}}

# ─── host switching ───────────────────────────────────────────────────────

# switch active host (edits config.yaml)
use HOST:
    #!/usr/bin/env bash
    set -euo pipefail
    test -f hosts/{{HOST}}.yaml || { echo "✗ hosts/{{HOST}}.yaml not found"; exit 1; }
    sed -i 's/^host: .*/host: {{HOST}}/' {{config}}
    echo "✓ active host: {{HOST}}"
    dcli validate 2>&1 | tail -3

# show the currently active host
host:
    @awk '/^host:/ {print $2}' {{config}}

# list all hosts
hosts:
    @ls hosts/*.yaml | xargs -n1 basename | sed 's/\.yaml$//' | grep -v '^profiles$'

# ─── sync / update ────────────────────────────────────────────────────────

# preview what `dcli sync` would do (no changes)
diff:
    dcli sync --dry-run 2>&1 || dcli sync -n 2>&1 || echo "(dcli has no dry-run; use 'just status' to inspect state)"

# apply the configuration to the system
sync:
    dcli sync

# system update (paru -Syu + flatpak) — respects module version constraints
update:
    dcli update

# ─── modules ──────────────────────────────────────────────────────────────

# list all available modules
list-modules:
    dcli module list

# enable a module on the active host (edits the host YAML)
enable MOD:
    dcli module enable {{MOD}}

# disable a module on the active host
disable MOD:
    dcli module disable {{MOD}}

# re-run a module's post-install hook
run-hook MOD:
    dcli module run-hook {{MOD}}

# ─── backup / restore ─────────────────────────────────────────────────────

# save a backup of the current configuration
save-config:
    dcli save-config

# list configuration backups
list-backups:
    dcli restore-config --list 2>&1 || dcli backup list

# create a system snapshot (snapper/timeshift per host config)
snapshot:
    dcli backup

# ─── git ──────────────────────────────────────────────────────────────────

# show repo status
git-status:
    git status --short

# commit + push all changes with a message
push MSG:
    git add -A
    git commit -m "{{MSG}}"
    git push

# pull + sync in one step
pull-sync:
    git pull --rebase
    dcli sync
