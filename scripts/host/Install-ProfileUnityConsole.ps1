# Personal project, not for production use. Provided as is, without warranty of any kind (MIT License, see LICENSE at the repo root). Not affiliated with the author's employer, with Liquidware or with Microsoft.
#requires -Version 5.1
<#
.SYNOPSIS
  Runs ON the ProfileUnity console VM: downloads the console installer from the media account
  with the VM's own managed identity and checks its SHA-256 against the lock entry.
.DESCRIPTION
  Windows PowerShell 5.1, no modules, runs as SYSTEM by managed Run Command (deploy-spec
  section 6.1). No key, SAS or secret crosses the Run Command: the VM gets a token for
  https://storage.azure.com/ from IMDS, and its identity holds Storage Blob Data Reader on the
  media container. The deploy passes the account name, the blob (<component>/<version>/<file>,
  from media.lock.json) and its SHA-256.

  The silent install switches for the 6.9.5 console are unverified (V18), so the script stops
  after the hash check and prints the console checklist (docs/console.md). It installs nothing.

  Prints exactly one line starting with LW-RESULT:
    LW-RESULT status=<verified|failed> path=<local file> detail=<text>
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Used by the main block below, which the analyzer does not follow.')]
[CmdletBinding()]
param(
  [string] $MediaAccountName = '',
  [string] $Blob = '',
  [string] $Sha256 = '',
  [string] $StorageSuffix = 'core.windows.net',
  [string] $Destination = 'C:\ProgramData\avd-liquidware\media'
)

$ErrorActionPreference = 'Stop'

function Write-Result([string] $Status, [string] $Path, [string] $Detail) {
  $clean = ($Detail -replace '[\r\n]+', ' ').Trim()
  Write-Output ("LW-RESULT status={0} path={1} detail={2}" -f $Status, $Path, $clean)
}

function Get-MediaUri([string] $AccountName, [string] $BlobName, [string] $Suffix) {
  # Strict: the same rules as Get-LwMediaBlobName, so nothing but the media container is reachable.
  if ($AccountName -cnotmatch '^[a-z0-9]{3,24}$') { throw "Not a storage account name: '$AccountName'." }
  if ($Suffix -notmatch '^[a-z0-9.-]+$') { throw "Not a storage endpoint suffix: '$Suffix'." }
  $parts = @($BlobName -split '/')
  $components = @('ProfileUnityConsole', 'ProfileUnityClient', 'FlexAppPackagingConsole')
  if ($parts.Count -ne 3 -or $components -cnotcontains $parts[0] -or $parts[1] -notmatch '^\d+(\.\d+){1,3}$' -or $parts[2] -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$') {
    throw "Not a media blob (<component>/<version>/<file>): '$BlobName'."
  }
  "https://$AccountName.blob.$Suffix/media/$BlobName"
}

function Get-ImdsStorageToken {
  # The VM's own identity, from the Instance Metadata Service. The token is never printed.
  $uri = 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=' + [uri]::EscapeDataString('https://storage.azure.com/')
  $response = Invoke-RestMethod -Uri $uri -Headers @{ Metadata = 'true' } -Method Get -UseBasicParsing
  if (-not $response.access_token) { throw 'IMDS returned no access token: does the VM have a system-assigned identity?' }
  $response.access_token
}

function Save-MediaBlob([string] $Uri, [string] $Token, [string] $Path) {
  if ($Uri -notmatch '^https://') { throw 'Media is only downloaded over HTTPS.' }
  $headers = @{ Authorization = "Bearer $Token"; 'x-ms-version' = '2021-08-06' }
  Invoke-WebRequest -Uri $Uri -Headers $headers -OutFile $Path -UseBasicParsing
}

function Test-MediaHash([string] $Path, [string] $Expected) {
  # True only for an exact SHA-256 match. A malformed pin never matches.
  if ($Expected -notmatch '^[0-9a-fA-F]{64}$') { return $false }
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
  (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -eq $Expected.ToUpperInvariant()
}

function Get-ConsoleChecklist([string] $Path) {
  # The manual steps until V18 passes (docs/console.md has the full list).
  @(
    'Console checklist (docs/console.md), until the silent install is verified (V18):'
    "  1. Sign in to this VM as lwadmin through Bastion; the password is lw-console-password in the tier Key Vault."
    "  2. Run the verified installer: $Path"
    '  3. Follow the Liquidware ProfileUnity 6.9.5 console install guide.'
    '  4. Set the deploy path to C:\ProgramData\avd-liquidware\deploy (local, never the live config share).'
    '  5. Enter the license from lw-licstr, read on this VM (docs/console.md shows how with its own identity).'
    '  6. Leave the Swagger API off.'
    '  7. Run Deploy-LiquidwareTier.ps1 -Action Check from Cloud Shell.'
  )
}

if ($MyInvocation.InvocationName -ne '.') {
  $local = ''
  try {
    if (-not $MediaAccountName -or -not $Blob -or -not $Sha256) { throw 'Pass -MediaAccountName, -Blob and -Sha256 (the lock entry).' }
    if ($Sha256 -notmatch '^[0-9a-fA-F]{64}$') { throw 'Sha256 must be 64 hex characters.' }
    $uri = Get-MediaUri -AccountName $MediaAccountName -BlobName $Blob -Suffix $StorageSuffix
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $ProgressPreference = 'SilentlyContinue'
    if (-not (Test-Path -LiteralPath $Destination)) { $null = New-Item -ItemType Directory -Path $Destination -Force }
    $local = Join-Path $Destination (@($Blob -split '/')[-1])
    $partial = "$local.partial"
    Save-MediaBlob -Uri $uri -Token (Get-ImdsStorageToken) -Path $partial
    if (-not (Test-MediaHash -Path $partial -Expected $Sha256)) {
      Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue
      throw "SHA-256 mismatch for ${Blob}: the download was deleted. Check the lock entry against the uploaded file."
    }
    Move-Item -LiteralPath $partial -Destination $local -Force
    Get-ConsoleChecklist -Path $local | ForEach-Object { Write-Output $_ }
    Write-Result 'verified' $local "SHA-256 matches the lock; install by hand until V18 (docs/console.md)."
  }
  catch {
    Write-Result 'failed' $local $_.Exception.Message
    exit 1
  }
}
