#requires -Version 7.4
<#
.SYNOPSIS
  Uploads one Liquidware installer to the tier's media account and pins its SHA-256 in output/media.lock.json.
  Personal project, not for production use. Provided as is, without warranty of any kind. Not affiliated with the author's employer, with Liquidware or with Microsoft.

.DESCRIPTION
  deploy-spec section 6.4. Run from Cloud Shell, signed in as the operator the deploy granted
  Storage Blob Data Contributor on the media container. Uploads with Entra (no key, no SAS) to
  media/<component>/<version>/<file>, then adds or replaces that entry in output/media.lock.json
  (component, version, file, SHA-256, size; no URLs, no secrets). Commit the lock to the
  customer's private repo, never to this one (profileunity/media.lock.example.json shows the shape).

  A version that is already uploaded is never overwritten: publish a new version instead, or pass
  -Force when the earlier upload was wrong. Installers come from Liquidware; this repo holds none.

.EXAMPLE
  ./scripts/Publish-LiquidwareMedia.ps1 -NamePrefix avdlz -Environment dev -Path ./ProfileUnityConsole.exe -Component ProfileUnityConsole -Version 6.9.5
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string] $NamePrefix,
  [Parameter(Mandatory)] [string] $Environment,
  [Parameter(Mandatory)] [string] $Path,
  [Parameter(Mandatory)] [ValidateSet('ProfileUnityConsole', 'ProfileUnityClient', 'FlexAppPackagingConsole')] [string] $Component,
  [Parameter(Mandatory)] [string] $Version,
  [string] $SubscriptionId = '',
  [string] $LockPath = '',
  [switch] $Force
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'LiquidwareTier.psm1') -Force

$argErrors = @(Get-LwArgumentError -NamePrefix $NamePrefix -Environment $Environment -Component ProfileUnity)
if ($argErrors.Count -gt 0) {
  $argErrors | ForEach-Object { Write-Host "FAIL   $_" }
  Write-Host 'RESULT FAIL invalid arguments'
  exit 1
}
if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Write-Host "FAIL   No file at $Path"; Write-Host 'RESULT FAIL missing file'; exit 1 }
$file = Get-Item -LiteralPath $Path
$blob = Get-LwMediaBlobName -Component $Component -Version $Version -FileName $file.Name
if (-not $LockPath) { $LockPath = Join-Path $PSScriptRoot '../output/media.lock.json' }

foreach ($m in 'Az.Accounts', 'Az.Storage') {
  if (-not (Get-Module -ListAvailable -Name $m)) {
    Write-Host "Installing $m from the PowerShell Gallery ..."
    Install-Module $m -Scope CurrentUser -Force -AllowClobber
  }
  Import-Module $m
}
if ($SubscriptionId) { $null = Set-AzContext -SubscriptionId $SubscriptionId }
if (-not (Get-AzContext)) { Write-Host 'Not signed in. Run Connect-AzAccount (Cloud Shell is already signed in).'; exit 2 }

$names = Get-LwName -NamePrefix $NamePrefix -Environment $Environment
$account = @(Get-AzStorageAccount -ResourceGroupName $names.TierGroup -ErrorAction SilentlyContinue |
    Where-Object { $_.Tags -and $_.Tags['liquidware-role'] -eq 'media' }) | Select-Object -First 1
if (-not $account) {
  Write-Host "FAIL   No media account (tag liquidware-role: media) in $($names.TierGroup)  [fix: run Deploy-LiquidwareTier.ps1 -Action Deploy first]"
  Write-Host 'RESULT FAIL no media account'
  exit 1
}

Write-Host "Hashing $($file.Name) ($([math]::Round($file.Length / 1MB, 1)) MiB) ..."
$sha = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLower()

# Entra only: the account has shared key off, so a key-based context would fail anyway.
$ctx = New-AzStorageContext -StorageAccountName $account.StorageAccountName -UseConnectedAccount
$existing = Get-AzStorageBlob -Container media -Blob $blob -Context $ctx -ErrorAction SilentlyContinue
if ($existing -and -not $Force) {
  Write-Host "FAIL   media/$blob is already uploaded  [fix: publish a new -Version, or -Force if the earlier upload was wrong]"
  Write-Host 'RESULT FAIL already published'
  exit 1
}
Write-Host "Uploading to $($account.StorageAccountName)/media/$blob ..."
$null = Set-AzStorageBlobContent -File $file.FullName -Container media -Blob $blob -Context $ctx -Force -Properties @{ ContentType = 'application/octet-stream' }

$lock = $null
if (Test-Path -LiteralPath $LockPath) { $lock = Get-Content -LiteralPath $LockPath -Raw | ConvertFrom-Json }
$lock = Get-LwMediaLock -Lock $lock -Component $Component -Version $Version -FileName $file.Name -Sha256 $sha -Size $file.Length
$dir = Split-Path $LockPath -Parent
if ($dir -and -not (Test-Path -LiteralPath $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }
$lock | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $LockPath -Encoding utf8NoBOM

Write-Host "PASS   media/$blob  sha256 $sha"
Write-Host "Lock written to $LockPath. Commit it to the customer's private repo, never to this one."
Write-Host 'RESULT PASS'
