$ErrorActionPreference = 'Stop'

$answerVolume = Get-Volume | Where-Object FileSystemLabel -eq 'WINSETUP' | Select-Object -First 1
if (-not $answerVolume) {
  throw 'The WINSETUP answer media is not mounted; cannot configure Windows autologon.'
}

$answerPath = '{0}:\Autounattend.xml' -f $answerVolume.DriveLetter
if (-not (Test-Path $answerPath)) {
  throw "The Windows answer file was not found at $answerPath."
}

[xml]$answer = Get-Content -LiteralPath $answerPath -Raw
$namespaces = New-Object System.Xml.XmlNamespaceManager($answer.NameTable)
$namespaces.AddNamespace('u', 'urn:schemas-microsoft-com:unattend')
$autoLogon = $answer.SelectSingleNode(
  '/u:unattend/u:settings[@pass="oobeSystem"]/u:component[@name="Microsoft-Windows-Shell-Setup"]/u:AutoLogon',
  $namespaces
)
$username = $autoLogon.SelectSingleNode('u:Username', $namespaces).InnerText
$password = $autoLogon.SelectSingleNode('u:Password/u:Value', $namespaces).InnerText
if ([string]::IsNullOrWhiteSpace($username) -or [string]::IsNullOrEmpty($password)) {
  throw 'The answer file does not contain the Windows autologon credentials.'
}

$workDir = Join-Path $env:TEMP ('win-vm-autologon-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $workDir -Force | Out-Null
try {
  $archive = Join-Path $workDir 'AutoLogon.zip'
  Invoke-WebRequest -UseBasicParsing -Uri 'https://download.sysinternals.com/files/AutoLogon.zip' -OutFile $archive
  Expand-Archive -LiteralPath $archive -DestinationPath $workDir -Force

  $tool = Join-Path $workDir 'Autologon64.exe'
  if (-not (Test-Path $tool)) {
    throw 'The Sysinternals Autologon x64 executable was not in the downloaded archive.'
  }
  $signature = Get-AuthenticodeSignature -FilePath $tool
  if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'Microsoft Corporation') {
    throw 'The downloaded Autologon executable does not have a valid Microsoft signature.'
  }

  # Accept the Sysinternals EULA for this utility, then use its documented CLI.
  # It stores the password as an LSA secret rather than a Winlogon plaintext value.
  $sysinternalsKey = 'HKCU:\Software\Sysinternals\Autologon'
  New-Item -Path $sysinternalsKey -Force | Out-Null
  New-ItemProperty -Path $sysinternalsKey -Name EulaAccepted -PropertyType DWord -Value 1 -Force | Out-Null
  $winlogonKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
  # Unattend's one-time AutoLogonCount would otherwise disable persistent
  # automatic sign-in after its finite count is exhausted.
  Remove-ItemProperty -Path $winlogonKey -Name AutoLogonCount -ErrorAction SilentlyContinue
  & $tool $username $env:COMPUTERNAME $password
  if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) {
    throw "Sysinternals Autologon failed with exit code $LASTEXITCODE."
  }

  $settings = Get-ItemProperty -Path $winlogonKey
  if ($settings.AutoAdminLogon -ne '1' -or $settings.DefaultUserName -ne $username) {
    throw 'Windows did not retain the expected automatic sign-in settings.'
  }
  if ($settings.PSObject.Properties.Name -contains 'DefaultPassword') {
    Remove-ItemProperty -Path $winlogonKey -Name DefaultPassword -ErrorAction SilentlyContinue
  }

  Write-Output "Automatic Windows sign-in is configured for $username at every boot."
}
finally {
  $password = $null
  Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
}
