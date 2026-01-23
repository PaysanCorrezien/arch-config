#!/usr/bin/env bash
# Rename tmux pane title based on current process or formatted path
# Updates all panes in the current window

# Get all panes in current window
panes=$(tmux list-panes -F '#{pane_id}')

# Shell processes that should show path instead
shell_processes=("zsh" "bash" "sh" "fish")

# Update each pane's title
for pane_id in $panes; do
  # Get pane info
  current_command=$(tmux display-message -t "$pane_id" -p '#{pane_current_command}')
  current_path=$(tmux display-message -t "$pane_id" -p '#{pane_current_path}')

  # Check if current command is a shell
  is_shell=false
  for shell in "${shell_processes[@]}"; do
    if [ "$current_command" = "$shell" ]; then
      is_shell=true
      break
    fi
  done

  if [ "$is_shell" = true ]; then
    # Format path: show last 2-3 directories
    # Replace $HOME with ~
    if [[ "$current_path" == "$HOME"* ]]; then
      formatted_path="~${current_path#$HOME}"
    else
      formatted_path="$current_path"
    fi

    # Split path and get last 2-3 components
    IFS='/' read -ra path_parts <<< "$formatted_path"

    # Filter out empty parts
    parts=()
    for part in "${path_parts[@]}"; do
      [ -n "$part" ] && parts+=("$part")
    done

    # Get last 2-3 parts, but prefer showing more context
    if [ ${#parts[@]} -eq 0 ]; then
      pane_title="~"
    elif [ ${#parts[@]} -le 2 ]; then
      pane_title=$(IFS='/'; echo "${parts[*]}")
    else
      # Show last 3 parts for better context
      pane_title=$(IFS='/'; echo "${parts[*]: -3}")
    fi

    # Limit length to avoid too long names
    if [ ${#pane_title} -gt 30 ]; then
      pane_title="...${pane_title: -27}"
    fi
  else
    # Use process name, but clean it up
    pane_title="$current_command"

    # Remove common prefixes/suffixes
    pane_title="${pane_title##*/}"
    pane_title="${pane_title%.exe}"
    pane_title="${pane_title%.out}"

    # Limit length
    if [ ${#pane_title} -gt 25 ]; then
      pane_title="${pane_title:0:22}..."
    fi
  fi

  # Set the pane title using user option (accessible via #{@pane_title})
  tmux set -t "$pane_id" @pane_title "$pane_title"
done
