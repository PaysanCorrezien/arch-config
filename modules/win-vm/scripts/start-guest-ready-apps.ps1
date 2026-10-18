$ErrorActionPreference = 'Stop'

$workspaces = @(
  @{ Name = 'brassens'; Path = 'C:\code\brassens-monorepo' },
  @{ Name = 'chirac'; Path = 'C:\code\chirac' }
)
$claude = Join-Path $env:USERPROFILE '.local\bin\claude.exe'
$terminal = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\wt.exe'
$deadline = (Get-Date).AddMinutes(15)

# On a newly provisioned guest, the one-time windev-box bootstrap may still be
# installing the CLI and applications. Wait within this logon task rather than
# requiring another manual launch.
do {
  $startApps = Get-StartApps
  # Prefer the current ChatGPT desktop application.  Do not select the legacy
  # "ChatGPT Classic" package merely because it has a similar display name.
  $chatGpt = $startApps | Where-Object AppID -eq 'OpenAI.Codex_2p2nqsd0c76g0!App' | Select-Object -First 1
  $claudeDesktop = $startApps | Where-Object AppID -eq 'com.squirrel.AnthropicClaude.claude' | Select-Object -First 1
  $missingWorkspaces = @($workspaces | Where-Object { -not (Test-Path $_.Path) })
  $ready = ($missingWorkspaces.Count -eq 0) -and (Test-Path $claude) -and (Test-Path $terminal) -and $chatGpt -and $claudeDesktop
  if (-not $ready) { Start-Sleep -Seconds 15 }
} until ($ready -or (Get-Date) -ge $deadline)

if (-not $ready) {
  throw 'Claude Desktop, Claude CLI, both project workspaces, Windows Terminal, or current ChatGPT was not ready within 15 minutes.'
}

foreach ($workspace in $workspaces) {
  $sessionPattern = 'claude(?:\.exe)?.*--remote-control(?:\s+|=)' + [regex]::Escape($workspace.Name) + '(?:\s|$)'
  $claudeRunning = Get-CimInstance Win32_Process | Where-Object {
    $_.CommandLine -match $sessionPattern
  }
  if (-not $claudeRunning) {
    Start-Process -FilePath $terminal -ArgumentList @(
      '-w', 'new', '-d', $workspace.Path, $claude, '--remote-control', $workspace.Name
    )
  }
}

# Packaged apps are single-instance; Explorer activates their existing window
# when already running instead of creating duplicate processes.
Start-Process -FilePath "$env:SystemRoot\explorer.exe" -ArgumentList "shell:AppsFolder\$($chatGpt.AppID)"
Start-Process -FilePath "$env:SystemRoot\explorer.exe" -ArgumentList "shell:AppsFolder\$($claudeDesktop.AppID)"
