#!/usr/bin/env bash
# Copy tmux buffer to system clipboard

tmux show-buffer | "$HOME/.config/scripts/clipboard-copy.sh"
