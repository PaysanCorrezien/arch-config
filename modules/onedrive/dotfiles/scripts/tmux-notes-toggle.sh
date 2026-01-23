#!/usr/bin/env bash
# Toggle Notes session - if in Notes, go back; otherwise create/switch to Notes
LOG_FILE="$HOME/.tmuxhistory.log"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [notes-toggle] $*" >> "$LOG_FILE"
}

log "=== Script started ==="

# Get current session name
current_session=$(tmux display-message -p '#{session_name}')
log "Current session: $current_session"

# If we're in Notes session, go back to previous session/pane
if [ "$current_session" = "Notes" ]; then
  log "In Notes session, going back to previous session"

  # Get previous session from history
  hist=$(tmux show -gv @pane_history 2>/dev/null)
  if [ $? -ne 0 ]; then
    hist=""
  fi

  idx=$(tmux show -gv @pane_index 2>/dev/null)
  if [ $? -ne 0 ]; then
    idx="-1"
  fi

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

  # Find the last pane that's not in Notes session
  if [ ${#panes[@]} -gt 1 ]; then
    # Go backwards through history to find non-Notes session
    for ((i=$idx-1; i>=0; i--)); do
      target_pane=${panes[$i]}
      IFS=':.' read -ra parts <<< "$target_pane"
      session=${parts[0]}
      if [ "$session" != "Notes" ]; then
        window=${parts[1]}
        pane=${parts[2]}
        tmux set -g @pane_index $i
        tmux switch-client -t "$session" 2>/dev/null
        tmux select-window -t "$window" 2>/dev/null
        tmux select-pane -t "$pane" 2>/dev/null
        log "Switched back to session: $session"
        exit 0
      fi
    done
    # If no previous non-Notes session found, try going forward
    for ((i=$idx+1; i<${#panes[@]}; i++)); do
      target_pane=${panes[$i]}
      IFS=':.' read -ra parts <<< "$target_pane"
      session=${parts[0]}
      if [ "$session" != "Notes" ]; then
        window=${parts[1]}
        pane=${parts[2]}
        tmux set -g @pane_index $i
        tmux switch-client -t "$session" 2>/dev/null
        tmux select-window -t "$window" 2>/dev/null
        tmux select-pane -t "$pane" 2>/dev/null
        log "Switched forward to session: $session"
        exit 0
      fi
    done
  fi

  # Fallback: just switch to last session if available
  last_session=$(tmux list-sessions -F '#{session_name}' | grep -v "^Notes$" | tail -1)
  if [ -n "$last_session" ]; then
    tmux switch-client -t "$last_session"
    log "Switched to last non-Notes session: $last_session"
  else
    log "No other sessions available"
  fi
  exit 0
fi

# Not in Notes session - create/switch to Notes
log "Not in Notes session, creating/switching to Notes"

NOTES_DIR="$HOME/OneDrive/Notes"
log "Notes directory: $NOTES_DIR"

# Check if Notes session exists
if tmux has-session -t Notes 2>/dev/null; then
  log "Notes session exists, switching to it"
  tmux switch-client -t Notes
else
  log "Creating new Notes session"
  # Create session with nvim and open the Snacks dashboard file picker
  tmux new-session -d -s Notes -c "$NOTES_DIR" "nvim +\"lua Snacks.dashboard.pick('files')\""
  tmux switch-client -t Notes
  log "Created and switched to Notes session"
fi

log "=== Script finished (switched to Notes) ==="
