#!/usr/bin/env bash
# Record pane switches in history
LOG_FILE="$HOME/.tmuxhistory.log"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [pane-history] $*" >> "$LOG_FILE"
}

log "=== Script started ==="
current_pane="$(tmux display-message -p '#{session_name}:#{window_index}.#{pane_index}')"
log "Current pane: $current_pane"

current_history="$(tmux show -gv @pane_history 2>/dev/null)"
if [ $? -ne 0 ]; then
  current_history=""
fi
log "Current history raw: '$current_history'"

# Convert pipe-delimited string to array
IFS='|' read -ra panes_array <<< "$current_history"
log "Current panes array length: ${#panes_array[@]}"

# Don't add if it's the same as the last pane in history
if [ ${#panes_array[@]} -gt 0 ] && [ "${panes_array[-1]}" = "$current_pane" ]; then
  log "Same pane as last, skipping"
  log "=== Script finished (skipped) ==="
  exit 0
fi

# Add current pane to array if not empty
if [ -n "$current_pane" ]; then
  panes_array+=("$current_pane")
fi

# Deduplicate: remove consecutive duplicates, keep first occurrence
new_panes=()
prev_pane=""
for pane in "${panes_array[@]}"; do
  if [ -n "$pane" ] && [ "$pane" != "$prev_pane" ]; then
    new_panes+=("$pane")
    prev_pane="$pane"
  fi
done

# Keep only last 100 entries
if [ ${#new_panes[@]} -gt 100 ]; then
  new_panes=("${new_panes[@]: -100}")
fi

log "New panes array length: ${#new_panes[@]}"

# Convert back to pipe-delimited string
new_history=$(IFS='|'; echo "${new_panes[*]}")
log "New history string: '$new_history'"

tmux set -g @pane_history "$new_history"
log "Set @pane_history"

# Set index to point to the last entry (current pane)
tmux set -g @pane_index $((${#new_panes[@]} - 1))
log "Set @pane_index to $((${#new_panes[@]} - 1))"
log "=== Script finished ==="
