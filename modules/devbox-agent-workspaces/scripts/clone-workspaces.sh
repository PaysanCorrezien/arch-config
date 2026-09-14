#!/usr/bin/env bash
# Clone the project workspaces the login launcher opens, when missing.
# Uses SSH, so this host's key must already be on the GitHub account.
# Idempotent: existing checkouts are left untouched.
set -euo pipefail

if [[ "$(id -u)" -eq 0 ]]; then
  target_user="${SUDO_USER:-$(loginctl list-users --no-legend 2>/dev/null | awk '$1 >= 1000 { print $2; exit }')}"
  as_user() { sudo -u "$target_user" -H "$@"; }
else
  target_user="$USER"
  as_user() { "$@"; }
fi
user_home="$(getent passwd "$target_user" | cut -d: -f6)"

as_user mkdir -p "${user_home}/code"
# brassens-monorepo keeps binaries in Git LFS; without the filters a clone
# checks out pointer files (e.g. a 130-byte gradle-wrapper.jar).
if command -v git-lfs >/dev/null 2>&1; then
  as_user git lfs install >/dev/null
else
  echo "⚠ git-lfs is not installed; LFS files will be checked out as pointers"
fi
for repo in brassens-monorepo chirac; do
  dest="${user_home}/code/${repo}"
  if [[ -d "${dest}/.git" ]]; then
    echo "✓ ${repo} already cloned"
  elif as_user git clone "git@github.com:PaysanCorrezien/${repo}.git" "$dest"; then
    echo "✓ cloned ${repo}"
  else
    echo "⚠ could not clone ${repo} — is this host's SSH key on GitHub?"
  fi
done
