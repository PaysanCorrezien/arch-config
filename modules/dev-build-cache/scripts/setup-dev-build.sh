#!/usr/bin/env bash
# dev-build-cache hook. Idempotent.
#   - Route this account's GitHub URLs over SSH: cargo/pnpm git deps such as
#     PaysanCorrezien/windows-cli are private and HTTPS has no credentials,
#     while the host SSH key is on the account.
#   - Install Git LFS filters (brassens-monorepo keeps binaries in LFS).
#   - Enable the ydotool user daemon (brassens desktop paste on KDE, which has
#     no wlroots virtual keyboard for wtype).
set -euo pipefail

if [[ "$(id -u)" -eq 0 ]]; then
  target_user="${SUDO_USER:-$(loginctl list-users --no-legend 2>/dev/null | awk '$1 >= 1000 { print $2; exit }')}"
  as_user() { sudo -u "$target_user" -H "$@"; }
else
  target_user="$USER"
  as_user() { "$@"; }
fi
uid="$(id -u "$target_user")"

echo "[dev-build] git: PaysanCorrezien GitHub URLs over SSH"
as_user git config --global url."git@github.com:PaysanCorrezien/".insteadOf "https://github.com/PaysanCorrezien/"

if command -v git-lfs >/dev/null 2>&1; then
  as_user git lfs install >/dev/null
  echo "[dev-build] git-lfs filters installed"
fi

echo "[dev-build] ydotool user daemon"
as_user env XDG_RUNTIME_DIR="/run/user/${uid}" systemctl --user enable --now ydotool.service >/dev/null 2>&1 ||
  echo "[dev-build] ⚠ could not enable ydotool.service; run it from the desktop session"

echo "[dev-build] done"
