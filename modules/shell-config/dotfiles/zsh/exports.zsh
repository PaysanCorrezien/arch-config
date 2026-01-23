# Add ~/.local/bin to PATH (includes WSL clipboard wrapper)
export PATH="$HOME/.local/bin:$HOME/.local/share/pythonautomation/bin:$PATH"

# Default editor
export EDITOR=nvim

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
