#!/usr/bin/env bash
# Toggle the arch-config tmux session.

set -euo pipefail

LOG_FILE="$HOME/.tmuxhistory.log"
SESSION_NAME="_config/arch-config"
SESSION_DIR="$HOME/.config/arch-config"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [config-toggle] $*" >> "$LOG_FILE"
}

current_session=$(tmux display-message -p '#{session_name}')
log "Current session: $current_session"

if [ "$current_session" = "$SESSION_NAME" ]; then
  if tmux switch-client -l 2>/dev/null; then
    log "Switched back to last session"
    exit 0
  fi

  last_session=$(tmux list-sessions -F '#{session_name}' | grep -v "^${SESSION_NAME}$" | tail -1)
  if [ -n "$last_session" ]; then
    tmux switch-client -t "$last_session"
    log "Switched to fallback session: $last_session"
  else
    log "No other sessions available"
  fi
  exit 0
fi

if ! tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
  tmux new-session -d -s "$SESSION_NAME" -c "$SESSION_DIR"
  log "Created session: $SESSION_NAME"
fi

tmux switch-client -t "$SESSION_NAME"
log "Switched to session: $SESSION_NAME"
