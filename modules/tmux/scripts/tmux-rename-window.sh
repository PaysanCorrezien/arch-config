#!/usr/bin/env bash
# Rename tmux window based on active pane's process or formatted path
# Uses the same logic as pane titles

# Get the current window index
current_window_index=$(tmux display-message -p '#{window_index}')

# Get active pane info (the pane that currently has focus in the window)
# Use explicit window targeting to ensure we get the correct pane for this window
current_command=$(tmux display-message -t ":$current_window_index" -p '#{pane_current_command}')
current_path=$(tmux display-message -t ":$current_window_index" -p '#{pane_current_path}')

# Shell processes that should show path instead
shell_processes=("zsh" "bash" "sh" "fish")

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
    window_name="~"
  elif [ ${#parts[@]} -le 2 ]; then
    window_name=$(IFS='/'; echo "${parts[*]}")
  else
    # Show last 3 parts for better context
    window_name=$(IFS='/'; echo "${parts[*]: -3}")
  fi

  # Limit length to avoid too long names
  if [ ${#window_name} -gt 30 ]; then
    window_name="...${window_name: -27}"
  fi
else
  # Use process name, but clean it up
  window_name="$current_command"

  # Remove common prefixes/suffixes
  window_name="${window_name##*/}"
  window_name="${window_name%.exe}"
  window_name="${window_name%.out}"

  # Limit length
  if [ ${#window_name} -gt 25 ]; then
    window_name="${window_name:0:22}..."
  fi
fi

# Set the window name for the current window
tmux rename-window -t ":$current_window_index" "$window_name"
