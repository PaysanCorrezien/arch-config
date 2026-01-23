# --- Windows PowerShell aliases for WSL/tmux ---

# Normal PowerShell
alias pwsh-win="/mnt/c/Program\ Files/PowerShell/7/pwsh.exe"

# Elevated PowerShell via gsudo (must be installed on Windows)
alias pwsh-admin='"/mnt/c/Program Files/gsudo/Current/gsudo.exe" -d pwsh'

# Interactive PowerShell launcher (prompts for elevation/user)
alias pwsh-interactive="$HOME/.config/scripts/pwsh-interactive.sh"

