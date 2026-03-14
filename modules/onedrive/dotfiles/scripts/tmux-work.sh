#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${1:-$(pwd)}"
PROJECT_NAME="$(basename "$PROJECT_DIR" | tr ' /:.' '_')"
SESSION="work_${PROJECT_NAME}"

CLAUDE_CMD="claude --dangerously-skip-permissions"

if ! command -v tmux >/dev/null 2>&1; then
	echo "tmux is not installed"
	exit 1
fi

if tmux has-session -t "$SESSION" 2>/dev/null; then
	exec tmux attach -t "$SESSION"
fi

tmux start-server

# Create detached session in the project directory
tmux new-session -d -s "$SESSION" -c "$PROJECT_DIR" -x 300 -y 80

# Initial pane is the top-left
P0="$(tmux display-message -p -t "${SESSION}:0.0" '#{pane_id}')"

# Right half = preview column
tmux split-window -h -p 50 -t "$P0" -c "$PROJECT_DIR"
PREVIEW_PANE="$(tmux display-message -p -t "${SESSION}:0.1" '#{pane_id}')"

# Bottom-left
tmux split-window -v -p 50 -t "$P0" -c "$PROJECT_DIR"
P2="$(tmux display-message -p -t "${SESSION}:0.2" '#{pane_id}')"

# Top-middle-left agent
tmux split-window -h -p 50 -t "$P0" -c "$PROJECT_DIR"
P3="$(tmux display-message -p -t "${SESSION}:0.3" '#{pane_id}')"

# Bottom-middle-left agent
tmux split-window -h -p 50 -t "$P2" -c "$PROJECT_DIR"
P4="$(tmux display-message -p -t "${SESSION}:0.4" '#{pane_id}')"

# Label panes for clarity
tmux select-pane -t "$P0" \; select-pane -T "agent-1"
tmux select-pane -t "$P2" \; select-pane -T "agent-2"
tmux select-pane -t "$P3" \; select-pane -T "agent-3"
tmux select-pane -t "$P4" \; select-pane -T "agent-4"
tmux select-pane -t "$PREVIEW_PANE" \; select-pane -T "preview"

# Expose preview pane id at session level
tmux set-environment -t "$SESSION" TMUX_PREVIEW_PANE "$PREVIEW_PANE"

# Launch Claude in agent panes only
for pane in "$P0" "$P2" "$P3" "$P4"; do
	tmux send-keys -t "$pane" \
		"export TMUX_PREVIEW_PANE=$PREVIEW_PANE; $CLAUDE_CMD" C-m
done

tmux select-pane -t "$P0"
exec tmux attach -t "$SESSION"
