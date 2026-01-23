#!/usr/bin/env bash
# Navigate forward through pane history
LOG_FILE="$HOME/.tmuxhistory.log"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [pane-forward] $*" >> "$LOG_FILE"
}

log "=== Script started ==="
hist=$(tmux show -gv @pane_history 2>/dev/null)
if [ $? -ne 0 ]; then
  hist=""
fi
log "History from tmux raw: '$hist'"

idx=$(tmux show -gv @pane_index 2>/dev/null)
if [ $? -ne 0 ]; then
  idx="-1"
fi
log "Current index: $idx"

# Convert pipe-delimited string to array
IFS='|' read -ra panes <<< "$hist"

# Filter out empty entries
panes_filtered=()
for pane in "${panes[@]}"; do
  if [ -n "$pane" ]; then
    panes_filtered+=("$pane")
  fi
done
panes=("${panes_filtered[@]}")

log "Filtered panes array length: ${#panes[@]}"

[ ${#panes[@]} -gt 1 ] || { log "Exiting: not enough panes (${#panes[@]})"; exit; }

# Calculate new index (go forward)
new_idx=$((idx + 1))
log "Calculated new_idx (idx + 1): $new_idx"

# Wrap around if needed
[ $new_idx -ge ${#panes[@]} ] && new_idx=0
log "After wrap check, new_idx: $new_idx"

target_pane=${panes[$new_idx]}
log "Target pane: $target_pane"

# Parse session:window.pane format
IFS=':.' read -ra parts <<< "$target_pane"
session=${parts[0]}
window=${parts[1]}
pane=${parts[2]}

log "Parsed - session: $session, window: $window, pane: $pane"

# Update index before switching
tmux set -g @pane_index $new_idx
log "Set @pane_index to $new_idx"

# Switch to the target pane (works across sessions)
if tmux switch-client -t "$session" 2>/dev/null; then
  tmux select-window -t "$window" 2>/dev/null
  tmux select-pane -t "$pane" 2>/dev/null
  log "Switched to pane: $target_pane"
else
  log "ERROR: Failed to switch to $target_pane"
  exit 1
fi
log "=== Script finished ==="
