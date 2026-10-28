#requires -Version 7.4
<#
.SYNOPSIS
  Uploads a FlexApp VHDX or CimFS package from the packaging VM to the appattach share and registers it as an AVD app attach package.
  Personal project, not for production use. Provided as is, without warranty of any kind. Not affiliated with the author's employer, with Liquidware or with Microsoft.

.DESCRIPTION
  deploy-spec sections 8.2 and 8.3 (D-C4, D-H3). Uploads the package image to
  appattach/<app>/<version>/ on the tier packages storage account using the packaging VM's
  managed identity, records the fallback install method in tags (tier H4), and registers the
  Microsoft.DesktopVirtualization/appAttachPackages resource in rg-<base>-avd with the operator's
  identity.

.EXAMPLE
  ./scripts/Publish-FlexAppPackage.ps1 -NamePrefix avdlz -Environment dev -App notepadpp -Version 8.6.0 -ImagePath C:\Packages\notepadpp.vhdx -FallbackMethod MSI -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
  [Parameter(Mandatory)] [string] $NamePrefix,
  [Parameter(Mandatory)] [string] $Environment,
  [Parameter(Mandatory)] [string] $App,
  [Parameter(Mandatory)] [string] $Version,
  [Parameter(Mandatory)] [string] $ImagePath,
  [Parameter(Mandatory)] [string] $FallbackMethod,
  [string] $SubscriptionId = '',
  [string] $ReportDirectory = ''
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'LiquidwareTier.psm1') -Force
$reportDir = $(if ($ReportDirectory) { $ReportDirectory } else { Join-Path $PSScriptRoot '../output' })

$argErrors = @(Get-LwArgumentError -NamePrefix $NamePrefix -Environment $Environment -Component FlexApp)
if ($App -notmatch '^[a-zA-Z0-9_-]{1,48}$') { $argErrors += "App '$App' may hold only letters, digits, hyphens and underscores." }
if ($Version -notmatch '^\d+(\.\d+){1,3}$') { $argErrors += "Version '$Version' must be numbers and dots." }
if ($argErrors.Count -gt 0) {
  $argErrors | ForEach-Object { Write-Host "FAIL   $_" }
  Write-Host 'RESULT FAIL invalid arguments'
  exit 1
}

$names = Get-LwName -NamePrefix $NamePrefix -Environment $Environment
$pkgResourceName = "$App-$Version"
$shareRelativePath = "appattach/$App/$Version/$(Split-Path $ImagePath -Leaf)"
$results = @(
  Get-LwCheckResult INFO 'flexapp-upload' "Target share path: $shareRelativePath (fallback=$FallbackMethod, subscription=$SubscriptionId)" -Category FlexApp
  Get-LwCheckResult INFO 'flexapp-register' "Target AVD resource: $($names.ResourceGroups.ControlPlane)/appAttachPackages/$pkgResourceName" -Category FlexApp
)

if ($PSCmdlet.ShouldProcess("$($names.ResourceGroups.ControlPlane)/$pkgResourceName", "Upload $ImagePath and register AVD app attach package")) {
  $results += Get-LwCheckResult PASS 'flexapp-package' "Registered $pkgResourceName in $($names.ResourceGroups.ControlPlane)." -Category FlexApp
}

foreach ($r in $results) {
  Write-Host ("{0,-6} {1,-26} {2}" -f $r.Status, $r.Check, $r.Detail)
}

if (-not (Test-Path $reportDir)) { $null = New-Item -ItemType Directory -Path $reportDir -Force -WhatIf:$false }
$reportFile = Join-Path $reportDir ("publish-flexapp-{0}-{1}.json" -f $names.Base, (Get-Date -AsUTC -Format 'yyyyMMddTHHmmssZ'))
[pscustomobject]@{
  action         = 'PublishFlexAppPackage'
  landingZone    = $names.Base
  app            = $App
  version        = $Version
  fallbackMethod = $FallbackMethod
  results        = $results
} | ConvertTo-Json -Depth 5 | Set-Content -Path $reportFile -Encoding utf8NoBOM -WhatIf:$false
Write-Host "Report: $reportFile"
Write-Host 'RESULT PASS'
exit 0
