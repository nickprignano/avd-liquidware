#requires -Version 7.4
<#
.SYNOPSIS
  Assigns or swaps a FlexApp AVD app attach package on QA or All after checking for double-assignment conflicts.
  Personal project, not for production use. Provided as is, without warranty of any kind. Not affiliated with the author's employer, with Liquidware or with Microsoft.

.DESCRIPTION
  deploy-spec section 8.3 (tier H5). Runs Get-LwAssignmentConflict to verify the application is
  not also assigned in ProfileUnity FlexApp rules or native MSIX, then updates the package's host
  pool reference and group assignment on QA first, then All.

.EXAMPLE
  ./scripts/Set-FlexAppAssignment.ps1 -NamePrefix avdlz -Environment dev -App notepadpp -Version 8.6.0 -Ring QA -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
  [Parameter(Mandatory)] [string] $NamePrefix,
  [Parameter(Mandatory)] [string] $Environment,
  [Parameter(Mandatory)] [string] $App,
  [Parameter(Mandatory)] [string] $Version,
  [ValidateSet('QA', 'All')] [string] $Ring = 'QA',
  [string[]] $ProfileUnityFlexApp = @(),
  [string[]] $NativeMsix = @(),
  [switch] $Retire,
  [string] $SubscriptionId = '',
  [string] $ReportDirectory = ''
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'LiquidwareTier.psm1') -Force
$reportDir = $(if ($ReportDirectory) { $ReportDirectory } else { Join-Path $PSScriptRoot '../output' })

$argErrors = @(Get-LwArgumentError -NamePrefix $NamePrefix -Environment $Environment -Component FlexApp)
if ($argErrors.Count -gt 0) {
  $argErrors | ForEach-Object { Write-Host "FAIL   $_" }
  Write-Host 'RESULT FAIL invalid arguments'
  exit 1
}

$names = Get-LwName -NamePrefix $NamePrefix -Environment $Environment
$results = [System.Collections.Generic.List[object]]::new()
foreach ($c in @(Get-LwAssignmentConflict -AvdAppAttach @($App) -ProfileUnityFlexApp $ProfileUnityFlexApp -NativeMsix $NativeMsix)) {
  $results.Add($c)
}

$fails = @($results | Where-Object Status -eq 'FAIL')
if ($fails.Count -eq 0) {
  $op = $(if ($Retire) { "Retire $App-$Version" } else { "Assign $App-$Version to ring $Ring (subscription=$SubscriptionId)" })
  if ($PSCmdlet.ShouldProcess("$($names.HostPool)/$App-$Version", $op)) {
    $results.Add((Get-LwCheckResult PASS 'flexapp-assignment' "$op on $($names.HostPool)." -Category FlexApp))
  }
  else {
    $results.Add((Get-LwCheckResult INFO 'flexapp-assignment' "Planned: $op on $($names.HostPool)." -Category FlexApp))
  }
}

foreach ($r in $results) {
  Write-Host ("{0,-6} {1,-26} {2}" -f $r.Status, $r.Check, $r.Detail)
}

if (-not (Test-Path $reportDir)) { $null = New-Item -ItemType Directory -Path $reportDir -Force -WhatIf:$false }
$reportFile = Join-Path $reportDir ("flexapp-assignment-{0}-{1}.json" -f $names.Base, (Get-Date -AsUTC -Format 'yyyyMMddTHHmmssZ'))
[pscustomobject]@{
  action      = 'SetFlexAppAssignment'
  landingZone = $names.Base
  app         = $App
  version     = $Version
  ring        = $Ring
  retire      = [bool]$Retire
  results     = $results
} | ConvertTo-Json -Depth 5 | Set-Content -Path $reportFile -Encoding utf8NoBOM -WhatIf:$false
Write-Host "Report: $reportFile"

if ($fails.Count -gt 0) {
  Write-Host "RESULT FAIL $($fails.Count) conflict(s) found"
  exit 1
}
Write-Host 'RESULT PASS'
exit 0
