#!/usr/bin/env bash
# Save current tmux session/window
tmux display-message -p '#S:#I' > "$HOME/.tmux_saved_context"
