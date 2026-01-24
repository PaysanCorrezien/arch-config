# Add ~/.local/bin to PATH (includes WSL clipboard wrapper)
export PATH="$HOME/.local/bin:$HOME/.local/share/pythonautomation/bin:$PATH"

# Wayland display (for wl-clipboard support in terminals)
if [[ -z "$WAYLAND_DISPLAY" && -d "$XDG_RUNTIME_DIR" ]]; then
  # Auto-detect Wayland socket (niri uses wayland-1)
  for sock in "$XDG_RUNTIME_DIR"/wayland-*; do
    if [[ -S "$sock" && ! "$sock" =~ \.lock$ ]]; then
      export WAYLAND_DISPLAY="${sock##*/}"
      break
    fi
  done
fi

# Default editor
export EDITOR=nvim

# SSH Agent (systemd user socket)
export SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/ssh-agent.socket"

# Common clipboard helper (WSL-safe)
export CLIPBOARD_HELPER="$HOME/.config/scripts/clipboard-copy.sh"

# FZF Configuration
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"

export FZF_CTRL_T_OPTS="
  --preview 'bat -n --color=always {}'"

# configure default command
export FZF_DEFAULT_COMMAND='fd --type f --strip-cwd-prefix --hidden --follow --exclude .git'
# export FZF_DEFAULT_COMMAND="rg --files --follow --no-ignore-vcs --hidden -g '!{**/node_modules/*,**/.git/*,**/snap/*,**/.icons/*,**/.themes/*}'"

# CTRL-Y to copy the command into clipboard using xclip
export FZF_CTRL_R_OPTS="
  --preview 'echo {}' --preview-window up:3:hidden:wrap
  --bind 'ctrl-/:toggle-preview'
  --bind 'ctrl-y:execute-silent(echo -n {2..} | ${CLIPBOARD_HELPER:-$HOME/.config/scripts/clipboard-copy.sh})+abort'
  --color header:italic
  --header 'Press CTRL-Y to copy command into clipboard'"
