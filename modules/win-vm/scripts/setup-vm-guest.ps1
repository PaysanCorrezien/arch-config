$ErrorActionPreference = 'Continue'
$log = 'C:\ProgramData\win-vm-guest-setup.log'
Start-Transcript -Path $log -Append -ErrorAction SilentlyContinue | Out-Null

# FirstLogonCommands starts in the local administrator's unelevated session.
# Re-launch once with a full token so RDP, OpenSSH, driver installation and the
# network settings do not silently fail behind UAC.
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
  Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $arguments
  Stop-Transcript -ErrorAction SilentlyContinue
  exit
}

# The address is deliberately pinned to the libvirt reservation.  Windows may
# take a while to renew after a host network restart; this makes SSH and RDP
# deterministic even during that window.
$vmNic = Get-NetAdapter | Where-Object {
  $_.Status -ne 'Disabled' -and $_.InterfaceDescription -match 'E1000|82574|VirtIO|Red Hat'
} | Select-Object -First 1
if ($vmNic) {
  Set-NetIPInterface -InterfaceIndex $vmNic.ifIndex -Dhcp Disabled -ErrorAction SilentlyContinue
  Get-NetIPAddress -InterfaceIndex $vmNic.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
  New-NetIPAddress -InterfaceIndex $vmNic.ifIndex -IPAddress '192.168.122.50' -PrefixLength 24 -DefaultGateway '192.168.122.1' -ErrorAction SilentlyContinue | Out-Null
  # Use a direct resolver first: the libvirt DNS proxy is retained as fallback,
  # but Windows optional-feature downloads must not depend on host DNS startup.
  Set-DnsClientServerAddress -InterfaceIndex $vmNic.ifIndex -ServerAddresses @('1.1.1.1', '192.168.122.1') -ErrorAction SilentlyContinue
}
$virtio = Get-Volume | Where-Object { $_.DriveLetter -and (Test-Path ("{0}:\guest-agent" -f $_.DriveLetter)) } | Select-Object -First 1
if ($virtio) {
  $root = "{0}:" -f $virtio.DriveLetter
  Get-ChildItem "$root\" -Recurse -Filter '*.inf' | Where-Object { $_.FullName -match '\\w11\\amd64\\' } | ForEach-Object { pnputil.exe /add-driver $_.FullName /install | Out-Null }
  $agent = Get-ChildItem "$root\guest-agent" -Filter 'qemu-ga-x86_64.msi' | Select-Object -First 1
  if ($agent) { Start-Process msiexec.exe -ArgumentList @('/i', $agent.FullName, '/qn', '/norestart') -Wait }

  # virtiofs-win is a service backed by WinFsp. Stage its executable now; the
  # service is created after WinFsp is installed below and mounts winshare as Z:.
  $viofs = Join-Path $root 'viofs\w11\amd64\virtiofs.exe'
  if (Test-Path $viofs) {
    $viofsDir = 'C:\Program Files\Virtio-Win\VioFS'
    New-Item -ItemType Directory -Path $viofsDir -Force | Out-Null
    Copy-Item $viofs (Join-Path $viofsDir 'virtiofs.exe') -Force
  }
}
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -Value 0
New-NetFirewallRule -DisplayName 'win-vm RDP from KVM host' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 3389 -RemoteAddress '192.168.122.0/24' -Profile Any -ErrorAction SilentlyContinue | Out-Null
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Start-Service sshd
Set-Service -Name sshd -StartupType Automatic
$answer = Get-Volume | Where-Object { $_.FileSystemLabel -eq 'WINSETUP' } | Select-Object -First 1
if ($answer) {
  $key = Get-Content ("{0}:\host-authorized-key.pub" -f $answer.DriveLetter)
  $auth = 'C:\ProgramData\ssh\administrators_authorized_keys'
  New-Item -ItemType File -Path $auth -Force | Out-Null
  if (-not (Select-String -Path $auth -SimpleMatch $key -Quiet)) { Add-Content -Path $auth -Value $key }
  # Use SIDs rather than localized group names: this image is French, while
  # the OpenSSH documentation examples use English "Administrators".
  icacls $auth /inheritance:r /grant '*S-1-5-32-544:F' /grant '*S-1-5-18:F' | Out-Null
}
New-NetFirewallRule -DisplayName 'win-vm SSH from KVM host' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 22 -RemoteAddress '192.168.122.0/24' -Profile Any -ErrorAction SilentlyContinue | Out-Null
# LocalSend uses TCP and UDP 53317. Permit it only from the libvirt host
# subnet; the Windows VM remains undiscoverable from other LAN clients.
foreach ($ruleName in 'win-vm-localsend-tcp','win-vm-localsend-udp') {
  Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue
}
New-NetFirewallRule -Name 'win-vm-localsend-tcp' -DisplayName 'win-vm LocalSend TCP from KVM host' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 53317 -RemoteAddress '192.168.122.0/24' -Profile Any | Out-Null
New-NetFirewallRule -Name 'win-vm-localsend-udp' -DisplayName 'win-vm LocalSend UDP from KVM host' -Direction Inbound -Action Allow -Protocol UDP -LocalPort 53317 -RemoteAddress '192.168.122.0/24' -Profile Any | Out-Null
# WinGet's source bundle is initialized per interactive user session.  Running
# its first source refresh through Windows OpenSSH can leave the source cache
# empty (0x8a15000f), so schedule that first refresh at the user's next desktop
# logon instead.  The task deletes itself after succeeding.
try {
  $wingetTask = 'WindevBox-InitializeWinget'
  $wingetUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
  $wingetAction = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\cmd.exe" -Argument "/c winget source reset --force && winget source update && schtasks /Delete /TN $wingetTask /F"
  $wingetTrigger = New-ScheduledTaskTrigger -AtLogOn -User $wingetUser
  $wingetPrincipal = New-ScheduledTaskPrincipal -UserId $wingetUser -LogonType Interactive -RunLevel Limited
  Register-ScheduledTask -TaskName $wingetTask -Action $wingetAction -Trigger $wingetTrigger -Principal $wingetPrincipal -Description 'Initialize WinGet sources from an interactive Windows desktop session.' -Force | Out-Null
} catch { Write-Warning "Could not schedule interactive WinGet initialization: $($_.Exception.Message)" }
powercfg /hibernate off; powercfg -change -standby-timeout-ac 0; powercfg -change -monitor-timeout-ac 0
Start-Sleep -Seconds 5
# WinFsp is optional for the first bootstrap: it needs internet access, whereas
# RDP and SSH must become available even when the NAT bridge was just repaired.
# Prefer winget, but fall back to the signed upstream stable MSI: fresh Windows
# installations often have an empty or non-responsive winget source catalog.
$winFspDll = Join-Path ${env:ProgramFiles(x86)} 'WinFsp\bin\winfsp-x64.dll'
if (-not (Test-Path $winFspDll) -and (Get-Command winget -ErrorAction SilentlyContinue) -and (Test-NetConnection -ComputerName 1.1.1.1 -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue)) {
  winget install --id WinFsp.WinFsp --silent --accept-package-agreements --accept-source-agreements
}
if (-not (Test-Path $winFspDll) -and (Test-NetConnection -ComputerName 1.1.1.1 -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue)) {
  $winFspMsi = 'C:\Windows\Temp\winfsp-2.1.25156.msi'
  Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/winfsp/winfsp/releases/download/v2.1/winfsp-2.1.25156.msi' -OutFile $winFspMsi
  if ((Get-FileHash -Algorithm SHA256 $winFspMsi).Hash -ne '073A70E00F77423E34BED98B86E600DEF93393BA5822204FAC57A29324DB9F7A') { throw 'WinFsp checksum mismatch' }
  $install = Start-Process msiexec.exe -ArgumentList @('/i', $winFspMsi, '/qn', '/norestart') -Wait -PassThru
  if ($install.ExitCode -notin 0, 3010) { throw "WinFsp install failed: $($install.ExitCode)" }
}
$viofsService = 'C:\Program Files\Virtio-Win\VioFS\virtiofs.exe'
if ((Test-Path $viofsService) -and -not (Get-Service -Name VirtioFsSvc -ErrorAction SilentlyContinue)) {
  New-Service -Name VirtioFsSvc -BinaryPathName "`"$viofsService`" -t winshare -m Z:" -DisplayName 'VirtioFsSvc' -StartupType Automatic | Out-Null
}
Set-Service -Name VirtioFsSvc -StartupType Automatic -ErrorAction SilentlyContinue
Start-Service -Name VirtioFsSvc -ErrorAction SilentlyContinue

# The KVM integration above must finish before the development bootstrap: it
# gives that bootstrap its one Drive source, Z:\GoogleDrive. Run the generic
# windev-box bootstrap once at the next interactive logon, but in VM mode so it
# does not install Google Drive for Desktop as a second sync client.
if ($answer) {
  $bootstrapTask = 'WinVm-DevBootstrap'
  $bootstrapPath = "{0}:\windev-box\bootstrap.ps1" -f $answer.DriveLetter
  if (Test-Path $bootstrapPath) {
    try {
      $bootstrapArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$bootstrapPath`" -ComputerName `"@VM_NAME@`" -UseHostDriveShare -HostDriveRoot `"Z:\GoogleDrive`" -ManagementSourceRanges `"192.168.122.0/24`" -CompletionTaskName `"$bootstrapTask`""
      $bootstrapAction = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument $bootstrapArgs
      $bootstrapTrigger = New-ScheduledTaskTrigger -AtLogOn -User ([Security.Principal.WindowsIdentity]::GetCurrent().Name)
      $bootstrapPrincipal = New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Highest
      Register-ScheduledTask -TaskName $bootstrapTask -Action $bootstrapAction -Trigger $bootstrapTrigger -Principal $bootstrapPrincipal -Description 'One-time dev bootstrap for the Windows KVM guest.' -Force | Out-Null
    } catch { Write-Warning "Could not schedule the Windows dev bootstrap: $($_.Exception.Message)" }
  } else {
    Write-Warning 'windev-box bootstrap was not present on the answer media.'
  }
}
Stop-Transcript -ErrorAction SilentlyContinue
Restart-Computer -Force
