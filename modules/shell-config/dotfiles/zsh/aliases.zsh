# NOTE: top tier aliases
  alias q="exit"

  alias rm="rm -irv"

  alias rmf="rm -rf"

  alias x="chmod +x"

  alias s='sudo'

  alias n="nvim"

  alias t="tmux"

  alias tr="tmux kill-server; tmux"

  alias mcd='f() { mkdir -p "$1" && cd "$1"; unset -f f; }; f'

  alias l='lsd -l --size default --classify --icon auto'

  alias lg="lazygit"

  alias dk="lazydocker"

  alias md="mkdir -p"

  # general use

  alias ll='lsd -l --classify --icon auto'

  alias ls='lsd -l --classify --icon auto --sort time'

  alias lS='lsd -1 --icon=never'			                                                  # one column, just names

  alias lt='lsd --tree --depth=2 --icon=auto'                                         # tree

  alias aran="autorandr -l"

  # git 

  alias ga="git add"

  alias gc="git commit -m"

  alias gl="git pull --rebase --autostash"

  alias gp="git push"

  # Enhanced NH aliases

  alias nos="nh os switch . --dry && nh home switch . --dry"     # Safe preview of system changes

  alias nosa="nh os switch . && nh home switch ."  # System + Home-manager switch

  alias ndiff="nvd diff /run/current-system /nix/var/nix/profiles/system"    # View system differences

  alias nhs="nh home switch ."         # Home-manager switch

  alias ngc="nh clean all --keep-since 7d --keep 10"             # Clean both user and system

  alias ngcd="nh clean all --dry --keep-since 7d --keep 10"             # Clean both user and system

  alias ns="nh search"                # Quick package search

  # cat alias...
  alias cat="bat";
  # cd alias...nosa
  alias cd="z";

  #alias y="yazi";
  alias ccd="claude --dangerously-skip-permissions"
  alias cod='codex --dangerously-bypass-approvals-and-sandbox'

  # inv - use INVENTAIRE_PATH as first argument to xlsx
  inv() {
    xlsx "$INVENTAIRE_PATH" "$@"
  }



  alias oneD="$HOME/.config/scripts/oneD"


