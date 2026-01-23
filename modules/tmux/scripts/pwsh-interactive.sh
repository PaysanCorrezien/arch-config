#!/usr/bin/env bash
# Interactive PowerShell launcher with optional elevation (WSL/Windows)

PWSH="/mnt/c/Program Files/PowerShell/7/pwsh.exe"
GSUDO="/mnt/c/Program Files/gsudo/Current/gsudo.exe"

if [ ! -e "$PWSH" ]; then
  echo "pwsh.exe not found at $PWSH" >&2
  exit 2
fi

if ! command -v "$GSUDO" >/dev/null 2>&1 && [ ! -e "$GSUDO" ]; then
  echo "gsudo not found. Install with: winget install gerardog.gsudo" >&2
  exit 2
fi

printf "PowerShell launcher options:\n"
printf "  1) Current user (non-admin)\n"
printf "  2) Current user (admin)\n"
printf "  3) Other user (admin-interactive)\n"
printf "Select option [1/2/3]: "
read -r option

case "$option" in
  1)
    exec "$PWSH"
    ;;
  2)
    exec "$GSUDO" -d pwsh
    ;;
  3)
    read -rp "Enter Windows user to elevate as (e.g. DOMAIN\\AdminUser or .\\Administrator): " WINUSER
    if [ -z "${WINUSER:-}" ]; then
      echo "No user specified. Aborting." >&2
      exit 1
    fi
    exec "$GSUDO" -u "$WINUSER" -d pwsh
    ;;
  *)
    echo "Invalid option. Aborting." >&2
    exit 1
    ;;
esac
