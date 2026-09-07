$ErrorActionPreference = 'Stop'

$repo = 'C:\code\brassens-monorepo'
$claude = Join-Path $env:USERPROFILE '.local\bin\claude.exe'
$terminal = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\wt.exe'
$deadline = (Get-Date).AddMinutes(15)

# On a newly provisioned guest, the one-time windev-box bootstrap may still be
# installing the CLI and applications. Wait within this logon task rather than
# requiring another manual launch.
do {
  $chatGpt = Get-StartApps | Where-Object Name -eq 'ChatGPT' | Select-Object -First 1
  $ready = (Test-Path $repo) -and (Test-Path $claude) -and (Test-Path $terminal) -and $chatGpt
  if (-not $ready) { Start-Sleep -Seconds 15 }
} until ($ready -or (Get-Date) -ge $deadline)

if (-not $ready) {
  throw 'Claude, Brassens, Windows Terminal, or ChatGPT was not ready within 15 minutes.'
}

$claudeRunning = Get-CimInstance Win32_Process | Where-Object {
  $_.CommandLine -match 'claude(?:\.exe)? .*--remote-control(?:\s+|=)brassens'
}
if (-not $claudeRunning) {
  Start-Process -FilePath $terminal -ArgumentList @(
    '-w', 'new', '-d', $repo, $claude, '--remote-control', 'brassens'
  )
}

# Packaged ChatGPT is single-instance; Explorer activates the existing window
# when it is already running instead of creating duplicate processes.
Start-Process -FilePath "$env:SystemRoot\explorer.exe" -ArgumentList "shell:AppsFolder\$($chatGpt.AppID)"
