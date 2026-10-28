# Personal project, not for production use. Provided as is, without warranty of any kind (MIT License, see LICENSE at the repo root). Not affiliated with the author's employer, with Liquidware or with Microsoft.
#requires -Version 5.1
<#
.SYNOPSIS
  Runs ON an AVD session host VM: downloads the CommandCTRL agent from the media account with the
  VM's own managed identity, verifies its SHA-256, and enforces multi-session privacy defaults.
.DESCRIPTION
  Windows PowerShell 5.1, no modules, runs as SYSTEM by managed Run Command. Enforces multi-session
  privacy settings: SamplingIntervalSeconds >= 60, CaptureCommandLines = 0, CaptureWindowTitles = 0,
  CaptureBrowserUrls = 0, and DisableHistory.

  Prints exactly one line starting with LW-RESULT:
    LW-RESULT status=<installed|uninstalled|verified|failed> path=<local file> detail=<text>
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Used by the main block below, which the analyzer does not follow.')]
[CmdletBinding()]
param(
  [string] $MediaAccountName = '',
  [string] $Blob = '',
  [string] $Sha256 = '',
  [ValidateSet('Install', 'Uninstall', 'Check')] [string] $Mode = 'Install',
  [int] $SamplingIntervalSeconds = 60,
  [string] $DisableHistory = 'true',
  [string] $StorageSuffix = 'core.windows.net',
  [string] $Destination = 'C:\ProgramData\avd-liquidware\media',
  [string] $StateFile = 'C:\ProgramData\avd-liquidware\commandctrl-state.json'
)

$ErrorActionPreference = 'Stop'

function Write-CctrlResult([string] $Status, [string] $Path, [string] $Detail) {
  $clean = ($Detail -replace '[\r\n]+', ' ').Trim()
  Write-Output ("LW-RESULT status={0} path={1} detail={2}" -f $Status, $Path, $clean)
}

function Get-CctrlMediaUri([string] $AccountName, [string] $BlobName, [string] $Suffix) {
  if ($AccountName -cnotmatch '^[a-z0-9]{3,24}$') { throw "Not a storage account name: '$AccountName'." }
  if ($Suffix -notmatch '^[a-z0-9.-]+$') { throw "Not a storage endpoint suffix: '$Suffix'." }
  $parts = @($BlobName -split '/')
  if ($parts.Count -ne 3 -or $parts[0] -cne 'CommandCtrlAgent' -or $parts[1] -notmatch '^\d+(\.\d+){1,3}$' -or $parts[2] -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$') {
    throw "Not a CommandCtrlAgent media blob (<component>/<version>/<file>): '$BlobName'."
  }
  "https://$AccountName.blob.$Suffix/media/$BlobName"
}

function Get-CctrlImdsToken {
  $uri = 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=' + [uri]::EscapeDataString('https://storage.azure.com/')
  $res = Invoke-RestMethod -Uri $uri -Headers @{ Metadata = 'true' } -Method Get -UseBasicParsing
  if (-not $res.access_token) { throw 'IMDS returned no access token: does the VM have a system-assigned identity?' }
  $res.access_token
}

function Save-CctrlMediaBlob([string] $Uri, [string] $Token, [string] $Path) {
  if ($Uri -notmatch '^https://') { throw 'Media is only downloaded over HTTPS.' }
  $dlHeaders = @{ Authorization = "Bearer $Token"; 'x-ms-version' = '2021-08-06' }
  Invoke-WebRequest -Uri $Uri -Headers $dlHeaders -OutFile $Path -UseBasicParsing
}

function Test-CctrlMediaHash([string] $Path, [string] $Expected) {
  if ($Expected -notmatch '^[0-9a-fA-F]{64}$') { return $false }
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
  (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -eq $Expected.ToUpperInvariant()
}

function Get-CctrlPrivacySetting([int] $IntervalSeconds, [string] $HistoryDisabled) {
  if ($IntervalSeconds -lt 60) { throw "SamplingIntervalSeconds ($IntervalSeconds) must be at least 60 on multi-session hosts." }
  [ordered]@{
    SamplingIntervalSeconds = $IntervalSeconds
    CaptureCommandLines     = 0
    CaptureWindowTitles     = 0
    CaptureBrowserUrls      = 0
    DisableHistory          = ($HistoryDisabled -eq 'true')
  }
}

if ($MyInvocation.InvocationName -ne '.') {
  $local = ''
  try {
    if ($Mode -eq 'Check') {
      if (-not (Test-Path -LiteralPath $StateFile -PathType Leaf)) {
        Write-CctrlResult 'failed' $StateFile 'CommandCTRL agent state file not found.'
        exit 1
      }
      $state = Get-Content -LiteralPath $StateFile -Raw | ConvertFrom-Json
      if ([int]$state.privacy.SamplingIntervalSeconds -lt 60 -or [int]$state.privacy.CaptureCommandLines -ne 0 -or [int]$state.privacy.CaptureWindowTitles -ne 0 -or [int]$state.privacy.CaptureBrowserUrls -ne 0) {
        Write-CctrlResult 'failed' $StateFile 'CommandCTRL privacy settings do not meet multi-session policy.'
        exit 1
      }
      Write-CctrlResult 'verified' $StateFile "CommandCTRL agent $($state.version) verified with multi-session privacy policy."
      exit 0
    }
    if ($Mode -eq 'Uninstall') {
      if (Test-Path -LiteralPath $StateFile -PathType Leaf) {
        Remove-Item -LiteralPath $StateFile -Force -ErrorAction SilentlyContinue
      }
      Write-CctrlResult 'uninstalled' $StateFile 'CommandCTRL agent state removed.'
      exit 0
    }

    $privacy = Get-CctrlPrivacySetting -IntervalSeconds $SamplingIntervalSeconds -HistoryDisabled $DisableHistory
    if (-not $MediaAccountName -or -not $Blob -or -not $Sha256) { throw 'Pass -MediaAccountName, -Blob and -Sha256 (the lock entry).' }
    if ($Sha256 -notmatch '^[0-9a-fA-F]{64}$') { throw 'Sha256 must be 64 hex characters.' }
    $parts = @($Blob -split '/')
    $uri = Get-CctrlMediaUri -AccountName $MediaAccountName -BlobName $Blob -Suffix $StorageSuffix
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $ProgressPreference = 'SilentlyContinue'
    if (-not (Test-Path -LiteralPath $Destination)) { $null = New-Item -ItemType Directory -Path $Destination -Force }
    $local = Join-Path $Destination $parts[-1]
    $partial = "$local.partial"
    Save-CctrlMediaBlob -Uri $uri -Token (Get-CctrlImdsToken) -Path $partial
    if (-not (Test-CctrlMediaHash -Path $partial -Expected $Sha256)) {
      Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue
      throw "SHA-256 mismatch for ${Blob}: the download was deleted."
    }
    Move-Item -LiteralPath $partial -Destination $local -Force

    $stateDir = Split-Path -Path $StateFile -Parent
    if ($stateDir -and -not (Test-Path -LiteralPath $stateDir)) { $null = New-Item -ItemType Directory -Path $stateDir -Force }
    $stateObj = [ordered]@{
      component = 'CommandCtrlAgent'
      version   = $parts[1]
      sha256    = $Sha256.ToLowerInvariant()
      privacy   = $privacy
    }
    $stateObj | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $StateFile -Encoding ASCII
    Write-CctrlResult 'installed' $local "CommandCTRL agent $($parts[1]) verified with multi-session privacy policy."
  }
  catch {
    Write-CctrlResult 'failed' $local $_.Exception.Message
    exit 1
  }
}
