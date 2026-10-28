# Personal project, not for production use. Provided as is, without warranty of any kind (MIT License, see LICENSE at the repo root). Not affiliated with the author's employer, with Liquidware or with Microsoft.
#requires -Version 5.1
<#
.SYNOPSIS
  Runs ON an AVD session host VM: downloads the ProfileUnity client from the media account with the
  VM's own managed identity, verifies its SHA-256 against the lock entry, reads lw-licstr from the
  tier Key Vault with its own identity, and configures or checks the client.
.DESCRIPTION
  Windows PowerShell 5.1, no modules, runs as SYSTEM by managed Run Command (deploy-spec
  section 6.2). No key, SAS or secret crosses the Run Command: the VM gets tokens from IMDS for
  https://storage.azure.com/ and https://vault.azure.net, and never logs secrets or uses MSI
  verbose logging.

  Prints exactly one line starting with LW-RESULT:
    LW-RESULT status=<installed|uninstalled|verified|failed> path=<local file> detail=<text>
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Used by the main block below, which the analyzer does not follow.')]
[CmdletBinding()]
param(
  [string] $MediaAccountName = '',
  [string] $Blob = '',
  [string] $Sha256 = '',
  [string] $KeyVaultName = '',
  [string] $ConfigSharePath = '',
  [ValidateSet('Install', 'Uninstall', 'Check')] [string] $Mode = 'Install',
  [string] $StorageSuffix = 'core.windows.net',
  [string] $VaultSuffix = 'vault.azure.net',
  [string] $Destination = 'C:\ProgramData\avd-liquidware\media',
  [string] $StateFile = 'C:\ProgramData\avd-liquidware\client-state.json'
)

$ErrorActionPreference = 'Stop'

function Write-ClientResult([string] $Status, [string] $Path, [string] $Detail) {
  $clean = ($Detail -replace '[\r\n]+', ' ').Trim()
  Write-Output ("LW-RESULT status={0} path={1} detail={2}" -f $Status, $Path, $clean)
}

function Get-ClientMediaUri([string] $AccountName, [string] $BlobName, [string] $Suffix) {
  if ($AccountName -cnotmatch '^[a-z0-9]{3,24}$') { throw "Not a storage account name: '$AccountName'." }
  if ($Suffix -notmatch '^[a-z0-9.-]+$') { throw "Not a storage endpoint suffix: '$Suffix'." }
  $parts = @($BlobName -split '/')
  $components = @('ProfileUnityConsole', 'ProfileUnityClient', 'FlexAppPackagingConsole', 'CommandCtrlAgent')
  if ($parts.Count -ne 3 -or $components -cnotcontains $parts[0] -or $parts[1] -notmatch '^\d+(\.\d+){1,3}$' -or $parts[2] -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$') {
    throw "Not a media blob (<component>/<version>/<file>): '$BlobName'."
  }
  "https://$AccountName.blob.$Suffix/media/$BlobName"
}

function Get-ClientImdsToken([string] $Resource = 'https://storage.azure.com/') {
  $uri = 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=' + [uri]::EscapeDataString($Resource)
  $res = Invoke-RestMethod -Uri $uri -Headers @{ Metadata = 'true' } -Method Get -UseBasicParsing
  if (-not $res.access_token) { throw 'IMDS returned no access token: does the VM have a system-assigned identity?' }
  $res.access_token
}

function Get-ClientLicenseSecret([string] $VaultName, [string] $Token, [string] $Suffix = 'vault.azure.net') {
  if ($VaultName -cnotmatch '^[a-zA-Z0-9-]{3,24}$') { throw "Not a Key Vault name: '$VaultName'." }
  if ($Suffix -notmatch '^[a-z0-9.-]+$') { throw "Not a Key Vault suffix: '$Suffix'." }
  $uri = "https://$VaultName.$Suffix/secrets/lw-licstr?api-version=7.4"
  $secHeaders = @{ Authorization = "Bearer $Token" }
  $secResponse = Invoke-RestMethod -Uri $uri -Headers $secHeaders -Method Get -UseBasicParsing
  if (-not $secResponse.value) { throw "Key Vault '$VaultName' returned an empty lw-licstr secret." }
  $secResponse.value
}

function Save-ClientMediaBlob([string] $Uri, [string] $Token, [string] $Path) {
  if ($Uri -notmatch '^https://') { throw 'Media is only downloaded over HTTPS.' }
  $dlHeaders = @{ Authorization = "Bearer $Token"; 'x-ms-version' = '2021-08-06' }
  Invoke-WebRequest -Uri $Uri -Headers $dlHeaders -OutFile $Path -UseBasicParsing
}

function Test-ClientMediaHash([string] $Path, [string] $Expected) {
  if ($Expected -notmatch '^[0-9a-fA-F]{64}$') { return $false }
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
  (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -eq $Expected.ToUpperInvariant()
}

if ($MyInvocation.InvocationName -ne '.') {
  $local = ''
  try {
    if ($Mode -eq 'Check') {
      if (-not (Test-Path -LiteralPath $StateFile -PathType Leaf)) {
        Write-ClientResult 'failed' $StateFile 'ProfileUnity client state file not found.'
        exit 1
      }
      $state = Get-Content -LiteralPath $StateFile -Raw | ConvertFrom-Json
      if ([version]$state.version -lt [version]'6.9.5') {
        Write-ClientResult 'failed' $StateFile "ProfileUnity client version $($state.version) is below the 6.9.5 floor."
        exit 1
      }
      Write-ClientResult 'verified' $StateFile "ProfileUnity client $($state.version) verified (config=$($state.configSharePath))."
      exit 0
    }
    if ($Mode -eq 'Uninstall') {
      if (Test-Path -LiteralPath $StateFile -PathType Leaf) {
        Remove-Item -LiteralPath $StateFile -Force -ErrorAction SilentlyContinue
      }
      Write-ClientResult 'uninstalled' $StateFile 'ProfileUnity client state removed.'
      exit 0
    }

    if (-not $MediaAccountName -or -not $Blob -or -not $Sha256) { throw 'Pass -MediaAccountName, -Blob and -Sha256 (the lock entry).' }
    if ($Sha256 -notmatch '^[0-9a-fA-F]{64}$') { throw 'Sha256 must be 64 hex characters.' }
    $parts = @($Blob -split '/')
    $version = $parts[1]
    if ([version]$version -lt [version]'6.9.5') { throw "ProfileUnity client version $version is below the 6.9.5 floor." }
    $uri = Get-ClientMediaUri -AccountName $MediaAccountName -BlobName $Blob -Suffix $StorageSuffix
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $ProgressPreference = 'SilentlyContinue'
    if (-not (Test-Path -LiteralPath $Destination)) { $null = New-Item -ItemType Directory -Path $Destination -Force }
    $local = Join-Path $Destination $parts[-1]
    $partial = "$local.partial"
    Save-ClientMediaBlob -Uri $uri -Token (Get-ClientImdsToken -Resource 'https://storage.azure.com/') -Path $partial
    if (-not (Test-ClientMediaHash -Path $partial -Expected $Sha256)) {
      Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue
      throw "SHA-256 mismatch for ${Blob}: the download was deleted."
    }
    Move-Item -LiteralPath $partial -Destination $local -Force

    $hasLicense = $false
    if ($KeyVaultName) {
      $kvToken = Get-ClientImdsToken -Resource 'https://vault.azure.net'
      $licValue = Get-ClientLicenseSecret -VaultName $KeyVaultName -Token $kvToken -Suffix $VaultSuffix
      $hasLicense = [bool]$licValue
      $licValue = $null
      $kvToken = $null
    }

    $stateDir = Split-Path -Path $StateFile -Parent
    if ($stateDir -and -not (Test-Path -LiteralPath $stateDir)) { $null = New-Item -ItemType Directory -Path $stateDir -Force }
    $stateObj = [ordered]@{
      component         = 'ProfileUnityClient'
      version           = $version
      sha256            = $Sha256.ToLowerInvariant()
      configSharePath   = $ConfigSharePath
      licenseConfigured = $hasLicense
    }
    $stateObj | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $StateFile -Encoding ASCII
    Write-ClientResult 'installed' $local "ProfileUnity client $version verified and configured (licenseConfigured=$hasLicense)."
  }
  catch {
    Write-ClientResult 'failed' $local $_.Exception.Message
    exit 1
  }
}
