#!/usr/bin/env bash
# Clipboard copy helper - works with xclip or wl-clipboard

if command -v wl-copy &>/dev/null; then
  # Wayland
  wl-copy
elif command -v xclip &>/dev/null; then
  # X11
  xclip -selection clipboard
else
  echo "Error: Neither wl-copy nor xclip found" >&2
  exit 1
fi
