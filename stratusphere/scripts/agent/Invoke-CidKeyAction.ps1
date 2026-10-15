# Personal project, not for production use. Provided as is, without warranty of any kind (MIT License, see LICENSE). Not affiliated with the author's employer, with Liquidware or with Microsoft.
<#
.SYNOPSIS
  Runs ON the endpoint: checks, installs, fixes, uninstalls or cleans up the Stratusphere Connector ID Key.
.DESCRIPTION
  Windows PowerShell 5.1, runs as SYSTEM (Azure Run Command, Intune, or a GPO startup script).

  Check      present (healthy), degraded (with what is wrong) or absent.
  Install    installs; skips a machine that already has the key unless -Force.
  Fix        absent: installs. Services stopped: sets them to Automatic and starts them.
             Half installed (settings without the program, or the reverse): reinstalls.
             -Force reinstalls a healthy key too, for example to point it at another Hub.
  Uninstall  runs the installer's /x /s.
  Cleanup    uninstalls with whatever uninstaller exists, then removes what is left: the
             key's services, its settings key and its Liquidware program folders. For teardown,
             and for machines a failed install or uninstall left behind.

  Prints exactly one line starting with SSUX-RESULT, which Deploy-CidKey.ps1 parses:
    SSUX-RESULT status=<present|degraded|absent|installed|already-installed|repaired|already-healthy|uninstalled|cleaned|failed> version=<v> detail=<text>
  The installer is never shipped with this repo: pass the URL of the one you downloaded
  from your own Hub (Hub Administration > Connector ID Keys), and its SHA-256.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Used by the functions below, which the analyzer does not follow.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Runs unattended as SYSTEM; -Action Check is the dry run.')]
[CmdletBinding()]
param(
  [Parameter(Mandatory)] [ValidateSet('Check', 'Install', 'Fix', 'Uninstall', 'Cleanup')] [string] $Action,
  [string] $HubAddress = '',
  [string] $InstallerUrl = '',
  [string] $InstallerSha256 = '',
  [switch] $Force
)

$ErrorActionPreference = 'Stop'
$settingsKeys = @('HKLM:\SOFTWARE\Liquidware Labs\Connector ID', 'HKLM:\SOFTWARE\WOW6432Node\Liquidware Labs\Connector ID')
$tempInstaller = Join-Path $env:TEMP 'ssux-cidkey-installer.exe'

function Write-Result([string] $Status, [string] $Version, [string] $Detail) {
  $clean = ($Detail -replace '[\r\n]+', ' ').Trim()
  Write-Output ("SSUX-RESULT status={0} version={1} detail={2}" -f $Status, $Version, $clean)
}

function Get-CidKeyState {
  # Settings key (6.7+), uninstall entry (version, uninstaller) and services, judged together.
  $settings = @($settingsKeys | Where-Object { Test-Path $_ })
  $entry = $null
  foreach ($root in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall') {
    if (-not (Test-Path $root)) { continue }
    $hit = Get-ChildItem $root | ForEach-Object { Get-ItemProperty $_.PSPath } |
      Where-Object { $_.PSObject.Properties['DisplayName'] -and $_.DisplayName -like '*Connector ID*' } |
      Select-Object -First 1
    if ($hit) { $entry = $hit; break }
  }
  $services = @(Get-CimInstance Win32_Service | Where-Object {
      $_.DisplayName -like '*Connector ID*' -or ($_.Name -like 'tnt*' -and $_.PathName -like '*Liquidware*')
    })
  $version = ''
  if ($entry -and $entry.PSObject.Properties['DisplayVersion']) { $version = [string]$entry.DisplayVersion }

  $problems = @()
  if ($entry -and $settings.Count -eq 0) { $problems += 'program installed but settings key missing' }
  if (-not $entry -and ($settings.Count -gt 0 -or $services.Count -gt 0)) { $problems += 'leftovers without an installed program' }
  if ($entry -and $services.Count -eq 0) { $problems += 'no Connector ID services found' }
  $stopped = @($services | Where-Object { $_.State -ne 'Running' })
  if ($stopped.Count -gt 0) { $problems += 'stopped: ' + (($stopped | ForEach-Object Name) -join ', ') }

  $state = 'absent'
  if ($entry -or $settings.Count -gt 0 -or $services.Count -gt 0) { $state = 'present' }
  if ($problems.Count -gt 0) { $state = 'degraded' }
  [pscustomobject]@{
    State      = $state
    Version    = $version
    Entry      = $entry
    Settings   = $settings
    Services   = $services
    Stopped    = $stopped
    Structural = @($problems | Where-Object { $_ -notlike 'stopped:*' }).Count -gt 0
    Problems   = $problems -join '; '
  }
}

function Get-Installer([string] $Url, [string] $Sha256) {
  if (-not $Url) { throw 'InstallerUrl is required for this action.' }
  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
  Invoke-WebRequest -Uri $Url -OutFile $tempInstaller -UseBasicParsing
  if ($Sha256) {
    $actual = (Get-FileHash -Path $tempInstaller -Algorithm SHA256).Hash
    if ($actual -ne $Sha256.ToUpperInvariant()) {
      Remove-Item $tempInstaller -Force
      throw "Installer SHA-256 is $actual, expected $Sha256"
    }
  }
  $tempInstaller
}

function Invoke-Installer([string[]] $Arguments) {
  $installer = Get-Installer -Url $InstallerUrl -Sha256 $InstallerSha256
  try { (Start-Process -FilePath $installer -ArgumentList $Arguments -Wait -PassThru).ExitCode }
  finally { Remove-Item $installer -Force -ErrorAction SilentlyContinue }
}

function Install-CidKey {
  $arguments = @('/s')
  if ($HubAddress) { $arguments += "HUBADDRESS=$HubAddress" }
  Invoke-Installer -Arguments $arguments
}

function Start-CidKeyService($Services) {
  foreach ($s in $Services) {
    Set-Service -Name $s.Name -StartupType Automatic
    Start-Service -Name $s.Name
  }
}

function Remove-CidKeyLeftover {
  # Uninstall with what exists, then remove what remains. Folders are removed only under
  # a Liquidware path, so a wrong service match can never delete anything else.
  $removed = @()
  $state = Get-CidKeyState
  if ($state.Entry) {
    $quiet = ''
    if ($state.Entry.PSObject.Properties['QuietUninstallString']) { $quiet = [string]$state.Entry.QuietUninstallString }
    $plain = ''
    if ($state.Entry.PSObject.Properties['UninstallString']) { $plain = [string]$state.Entry.UninstallString }
    if ($plain -match '(?i)msiexec.*(\{[0-9A-F-]{36}\})') {
      Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/x', $Matches[1], '/qn', '/norestart') -Wait | Out-Null
      $removed += 'program (msiexec)'
    }
    elseif ($InstallerUrl) {
      Invoke-Installer -Arguments @('/x', '/s') | Out-Null
      $removed += 'program (installer /x)'
    }
    elseif ($quiet) {
      Start-Process -FilePath 'cmd.exe' -ArgumentList @('/c', $quiet) -Wait | Out-Null
      $removed += 'program (quiet uninstall)'
    }
  }
  $folders = @()
  foreach ($s in @((Get-CidKeyState).Services)) {
    $exe = ($s.PathName -replace '^"([^"]+)".*$', '$1') -replace '^(\S+\.exe).*$', '$1'
    if ($exe -like '*Liquidware*') { $folders += Split-Path $exe -Parent }
    Stop-Service -Name $s.Name -Force -ErrorAction SilentlyContinue
    & sc.exe delete $s.Name | Out-Null
    $removed += "service $($s.Name)"
  }
  foreach ($k in $settingsKeys) {
    if (Test-Path $k) { Remove-Item $k -Recurse -Force; $removed += 'settings key' }
  }
  foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ }) {
    $folders += @(Get-ChildItem (Join-Path $base 'Liquidware Labs') -Directory -Filter 'Connector ID*' -ErrorAction SilentlyContinue | ForEach-Object FullName)
  }
  foreach ($f in ($folders | Sort-Object -Unique)) {
    if ($f -like '*Liquidware*' -and (Test-Path $f)) { Remove-Item $f -Recurse -Force -ErrorAction SilentlyContinue; $removed += "folder $f" }
  }
  if (Test-Path $tempInstaller) { Remove-Item $tempInstaller -Force }
  $removed
}

try {
  $before = Get-CidKeyState
  switch ($Action) {
    'Check' {
      if ($before.State -eq 'absent') { Write-Result 'absent' '' 'Connector ID Key is not installed' }
      elseif ($before.State -eq 'degraded') { Write-Result 'degraded' $before.Version $before.Problems }
      else { Write-Result 'present' $before.Version 'Installed, services running' }
    }
    'Install' {
      if ($before.State -ne 'absent' -and -not $Force) {
        Write-Result 'already-installed' $before.Version "Skipped ($($before.State)); use -Action Fix to repair or -Force to reinstall"
        break
      }
      $code = Install-CidKey
      $after = Get-CidKeyState
      if ($code -ne 0) { Write-Result 'failed' $after.Version "Installer exit code $code" }
      elseif ($after.State -eq 'absent') { Write-Result 'failed' '' 'Installer returned 0 but nothing was installed' }
      elseif ($after.State -eq 'degraded') { Write-Result 'failed' $after.Version "Installed but degraded: $($after.Problems)" }
      else { Write-Result 'installed' $after.Version 'Installed' }
    }
    'Fix' {
      if ($before.State -eq 'present' -and -not $Force) { Write-Result 'already-healthy' $before.Version 'Nothing to fix'; break }
      $did = ''
      if ($before.State -eq 'degraded' -and -not $before.Structural -and -not $Force) {
        Start-CidKeyService -Services $before.Stopped
        $did = 'started ' + (($before.Stopped | ForEach-Object Name) -join ', ')
      }
      else {
        $code = Install-CidKey
        if ($code -ne 0) { Write-Result 'failed' $before.Version "Reinstall exit code $code (was: $($before.State) $($before.Problems))"; break }
        $did = "reinstalled (was: $($before.State) $($before.Problems))"
        $after = Get-CidKeyState
        if ($after.Stopped.Count -gt 0) { Start-CidKeyService -Services $after.Stopped; $did += '; started services' }
      }
      $after = Get-CidKeyState
      if ($after.State -eq 'present') { Write-Result 'repaired' $after.Version $did }
      else { Write-Result 'failed' $after.Version "After fix ($did): $($after.State) $($after.Problems)" }
    }
    'Uninstall' {
      if ($before.State -eq 'absent') { Write-Result 'absent' '' 'Nothing to uninstall'; break }
      $code = Invoke-Installer -Arguments @('/x', '/s')
      $after = Get-CidKeyState
      if ($code -ne 0 -or $after.State -ne 'absent') { Write-Result 'failed' $after.Version "Uninstall exit code $code; now $($after.State) $($after.Problems). Use -Action Cleanup to remove leftovers." }
      else { Write-Result 'uninstalled' $before.Version 'Uninstalled' }
    }
    'Cleanup' {
      if ($before.State -eq 'absent') { Write-Result 'absent' '' 'Nothing to clean up'; break }
      $removed = @(Remove-CidKeyLeftover)
      $after = Get-CidKeyState
      if ($after.State -ne 'absent') { Write-Result 'failed' $after.Version "Still $($after.State) after removing: $($removed -join ', '). Remaining: $($after.Problems)" }
      else { Write-Result 'cleaned' $before.Version ('Removed ' + ($removed -join ', ')) }
    }
  }
}
catch {
  Write-Result 'failed' '' ("{0}: {1}" -f $_.Exception.GetType().Name, $_.Exception.Message)
}
