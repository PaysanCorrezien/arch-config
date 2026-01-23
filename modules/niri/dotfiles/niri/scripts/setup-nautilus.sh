#!/usr/bin/env bash
# Configure Nautilus defaults and sidebar bookmarks.

set -euo pipefail

echo "  • Nautilus preferences"
if ! command -v gsettings >/dev/null 2>&1; then
  echo "    - gsettings not found; skipping preferences"
else
  if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
    echo "    - no DBUS session; skipping preferences"
  else
    if gsettings list-schemas | grep -qx "org.gnome.nautilus.preferences"; then
      gsettings set org.gnome.nautilus.preferences show-hidden-files true
      gsettings set org.gnome.nautilus.preferences default-folder-viewer "list-view"
      gsettings set org.gnome.nautilus.list-view default-visible-columns "['name','size','type','date_modified']"
      gsettings set org.gnome.nautilus.list-view default-column-order "['name','size','type','date_modified']"

      echo "    - show-hidden-files: $(gsettings get org.gnome.nautilus.preferences show-hidden-files)"
      echo "    - default-folder-viewer: $(gsettings get org.gnome.nautilus.preferences default-folder-viewer)"
      echo "    - default-visible-columns: $(gsettings get org.gnome.nautilus.list-view default-visible-columns)"
      echo "    - default-column-order: $(gsettings get org.gnome.nautilus.list-view default-column-order)"
    else
      echo "    - org.gnome.nautilus.preferences schema not found; skipping"
    fi
  fi
fi

echo "  • Nautilus bookmarks"
if ! command -v python3 >/dev/null 2>&1; then
  echo "    - python3 not found; skipping bookmarks"
  exit 0
fi

config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
bookmark_files=(
  "${config_home}/gtk-3.0/bookmarks"
  "${config_home}/gtk-4.0/bookmarks"
)

bookmark_uri() {
  python3 - "$1" <<'PY'
import pathlib
import sys
import urllib.parse

path = pathlib.Path(sys.argv[1]).expanduser().resolve()
print("file://" + urllib.parse.quote(str(path)))
PY
}

ensure_bookmark() {
  local path="$1"
  local label="${2:-}"

  if [ ! -e "$path" ]; then
    echo "    - skipping missing: $path"
    return 0
  fi

  local uri
  uri="$(bookmark_uri "$path")"
  local line="$uri"
  if [ -n "$label" ]; then
    line="$uri $label"
  fi

  for file in "${bookmark_files[@]}"; do
    mkdir -p "$(dirname "$file")"
    touch "$file"
    if ! grep -Fqx "$line" "$file" && ! grep -Fq "^$uri" "$file"; then
      echo "$line" >> "$file"
      echo "    - added to $(basename "$(dirname "$file")") bookmarks: $line"
    fi
  done
}

default_bookmarks=(
  "$HOME/repo|repo"
  "$HOME/repo/arch-config|arch-config"
  "$HOME/.config/arch-config|arch-config (config)"
)

for entry in "${default_bookmarks[@]}"; do
  path="${entry%%|*}"
  label="${entry#*|}"
  ensure_bookmark "$path" "$label"
done

for entry in "$@"; do
  if [[ "$entry" == *":"* ]]; then
    ensure_bookmark "${entry%%:*}" "${entry#*:}"
  else
    ensure_bookmark "$entry"
  fi
done
