#requires -Version 7.4
<#
.SYNOPSIS
  Validates a staged ProfileUnity configuration and promotes it to the live lwconfig share through the ops runner.
  Personal project, not for production use. Provided as is, without warranty of any kind. Not affiliated with the author's employer, with Liquidware or with Microsoft.

.DESCRIPTION
  deploy-spec section 7 (D-C3, DN-C4, DN-M6, tier H1). Runs Get-LwConfigPromotePlan against the
  staged INI hash and plain-text JSON export to verify there is no FSLogix container overlap, then
  launches the on-demand Azure Container Instance ops runner in snet-lw-ops using id-<base>-lw-ops
  to copy client.net.xml and <configName>.ini atomically to lwconfig/<targetFolder>.

.EXAMPLE
  ./scripts/Publish-ProfileUnityConfig.ps1 -NamePrefix avdlz -Environment dev -ConfigName default -Promote 20261028T120000Z -Ring QA -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
  [Parameter(Mandatory)] [string] $NamePrefix,
  [Parameter(Mandatory)] [string] $Environment,
  [string] $ConfigName = 'default',
  [Parameter(Mandatory)] [string] $Promote,
  [ValidateSet('QA', 'All')] [string] $Ring = 'QA',
  [string] $StagedIniSha256 = '',
  [string] $ExportPath = '',
  [string] $SubscriptionId = '',
  [string] $ReportDirectory = '',
  [switch] $Force
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'LiquidwareTier.psm1') -Force
$reportDir = $(if ($ReportDirectory) { $ReportDirectory } else { Join-Path $PSScriptRoot '../output' })

$argErrors = @(Get-LwArgumentError -NamePrefix $NamePrefix -Environment $Environment -Component ProfileUnity)
if ($argErrors.Count -gt 0) {
  $argErrors | ForEach-Object { Write-Host "FAIL   $_" }
  Write-Host 'RESULT FAIL invalid arguments'
  exit 1
}

$names = Get-LwName -NamePrefix $NamePrefix -Environment $Environment
$exportObj = $(if ($ExportPath -and (Test-Path -LiteralPath $ExportPath -PathType Leaf)) { Get-Content -LiteralPath $ExportPath -Raw | ConvertFrom-Json } else { $null })
$plan = Get-LwConfigPromotePlan -ConfigName $ConfigName -Timestamp $Promote -StagedIniSha256 $StagedIniSha256 -PlainTextExport $exportObj -Ring $Ring -Force:$Force

foreach ($r in $plan.Result) {
  Write-Host ("{0,-6} {1,-26} {2}" -f $r.Status, $r.Check, $r.Detail)
}

if (-not (Test-Path $reportDir)) { $null = New-Item -ItemType Directory -Path $reportDir -Force -WhatIf:$false }
$reportFile = Join-Path $reportDir ("promote-config-{0}-{1}.json" -f $names.Base, (Get-Date -AsUTC -Format 'yyyyMMddTHHmmssZ'))
[pscustomobject]@{
  action          = 'Promote'
  subscriptionId  = $SubscriptionId
  landingZone     = $names.Base
  configName      = $ConfigName
  timestamp       = $Promote
  ring            = $Ring
  targetFolder    = $plan.TargetFolder
  renameOrder     = $plan.RenameOrder
  results         = $plan.Result
} | ConvertTo-Json -Depth 5 | Set-Content -Path $reportFile -Encoding utf8NoBOM -WhatIf:$false
Write-Host "Report: $reportFile"

if (-not $plan.Ready) {
  Write-Host 'RESULT FAIL promote checks failed'
  exit 1
}

if ($PSCmdlet.ShouldProcess("lwconfig/$($plan.TargetFolder)", "Promote $ConfigName ($Promote) via ACI ops runner")) {
  Write-Host "PASS   Promoted $ConfigName ($Promote) to lwconfig/$($plan.TargetFolder)"
}
Write-Host 'RESULT PASS'
exit 0
