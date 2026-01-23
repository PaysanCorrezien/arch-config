# NOTE: amazing post about zsh where got most of the code :
# https://stackoverflow.com/questions/5407916/zsh-zle-shift-selection
#
# Define functions for region handling
#

clipboard_helper=${CLIPBOARD_HELPER:-$HOME/.config/scripts/clipboard-copy.sh}

r-delregion() {
  if ((REGION_ACTIVE)); then
    zle kill-region
  else
    local widget_name=$1
    shift
    zle $widget_name -- $@
  fi
}

r-deselect() {
  ((REGION_ACTIVE = 0))
  local widget_name=$1
  shift
  zle $widget_name -- $@
}

r-select() {
  ((REGION_ACTIVE)) || zle set-mark-command
  local widget_name=$1
  shift
  zle $widget_name -- $@
}

# Function to select the entire line
select-entire-line() {
  zle beginning-of-line
  zle set-mark-command
  zle end-of-line
}

# Create the zle widget for selecting the entire line
zle -N select-entire-line

# Bind Ctrl+A to select the entire line
bindkey '^A' select-entire-line

# Bind keys for region handling
for key kcap seq mode widget (
  sleft kLFT $'\e[1;2D' select backward-char
  sright kRIT $'\e[1;2C' select forward-char
  sup kri $'\e[1;2A' select up-line-or-history
  sdown kind $'\e[1;2B' select down-line-or-history
  send kEND $'\E[1;2F' select end-of-line
  send2 x $'\E[4;2~' select end-of-line
  shome kHOM $'\E[1;2H' select beginning-of-line
  shome2 x $'\E[1;2~' select beginning-of-line
  left kcub1 $'\EOD' deselect backward-char
  right kcuf1 $'\EOC' deselect forward-char
  end kend $'\EOF' deselect end-of-line
  end2 x $'\E4~' deselect end-of-line
  home khome $'\EOH' deselect beginning-of-line
  home2 x $'\E1~' deselect beginning-of-line
  csleft x $'\E[1;6D' select backward-word
  csright x $'\E[1;6C' select forward-word
  csend x $'\E[1;6F' select end-of-line
  cshome x $'\E[1;6H' select beginning-of-line
  cleft x $'\E[1;5D' deselect backward-word
  cright x $'\E[1;5C' deselect forward-word
  del kdch1 $'\E[3~' delregion delete-char
  bs x $'^?' delregion backward-delete-char
) {
  eval "key-$key() {
    r-$mode $widget \$@
  }"
  zle -N key-$key
  bindkey ${terminfo[$kcap]-$seq} key-$key
}

# Restore backward-delete-char for Backspace in the incremental search keymap
bindkey -M isearch '^?' backward-delete-char

# Function to select the entire command, including multiline
zle -N widget::select-all
function widget::select-all() {
    local buflen=$(echo -n "$BUFFER" | wc -m | bc)
    CURSOR=$buflen   # If this is messing up try: CURSOR=9999999
    zle set-mark-command
    while [[ $CURSOR > 0 ]]; do
        zle beginning-of-line
    done
}

# Function to cut selected text to clipboard using xclip
zle -N widget::cut-selection
function widget::cut-selection() {
    if ((REGION_ACTIVE)); then
        zle kill-region
        printf "%s" "$CUTBUFFER" | "$clipboard_helper"
    fi
}

# Function to copy selected text to clipboard using xclip
zle -N widget::copy-selection
function widget::copy-selection {
    if ((REGION_ACTIVE)); then
        zle copy-region-as-kill
        printf "%s" "$CUTBUFFER" | "$clipboard_helper"
    fi
}

# bindkey '^_' aichat_zsh
bindkey '^Y' widget::copy-selection

# Bind Ctrl+A to select the entire command
bindkey '^A' widget::select-all

# Bind Ctrl+X to cut the selected text to clipboard
bindkey '^X' widget::cut-selection

bindkey '^U' undo

# Open line in editor
# #  Best Shortcut EDIT IN NEOVIM current line
autoload -Uz edit-command-line
zle -N edit-command-line
bindkey '^E' edit-command-line

# Up in history
bindkey '^K' up-line-or-history

# Down in history
bindkey '^J' down-line-or-history

# Clear the current line
bindkey '^D' kill-whole-line

# Move to the start of the previous word (originally on 'H')
bindkey '^B' backward-word

# Move to the end of the next word (originally on 'L')
bindkey '^F' forward-word

# right arrow accept
bindkey '^[[C' autosuggest-accept

# Delete the word after the cursor
bindkey '^W' kill-word

# Redo the last undone editing command / CTRL R is not acailable its the standard history search
bindkey '^H' redo

# List choices for completion based on current input
# bindkey '^O' beginning-of-line

# Delete the word before the cursor
# bindkey '^X' backward-kill-word

# ctrl + end accept
bindkey '^[[1;5F' autosuggest-accept

# Bind Ctrl+P and Ctrl+N for history substring search
# TODO: maybe make ti launchfzf history to previous one instead ?
bindkey '^P' history-substring-search-up
bindkey '^N' history-substring-search-down
