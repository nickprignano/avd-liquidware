#requires -Version 7.4
<#
.SYNOPSIS
  Synchronizes AVD session hosts for ProfileUnity, Stratusphere or CommandCTRL using drained Run Commands.
  Personal project, not for production use. Provided as is, without warranty of any kind. Not affiliated with the author's employer, with Liquidware or with Microsoft.

.DESCRIPTION
  deploy-spec sections 6.2 and 6.3. Computes a per-host execution plan with Get-LwHostPlan:
  never starts or undrains hosts when the landing zone's budget lock is active, records each VM's
  power state and starts stopped VMs before running or removing a Run Command (lesson 0026), drains
  and tags hosts with liquidware-drained and avd-scaling-exclude while configuring, and restores
  drain and power state afterwards only when this tier set them.

.EXAMPLE
  ./scripts/Sync-LiquidwareHosts.ps1 -NamePrefix avdlz -Environment dev -Component ProfileUnity -Action Plan
.EXAMPLE
  ./scripts/Sync-LiquidwareHosts.ps1 -NamePrefix avdlz -Environment dev -Component ProfileUnity -Action Configure -HoldUnconfigured
#>
[CmdletBinding(SupportsShouldProcess)]
param(
  [Parameter(Mandatory)] [string] $NamePrefix,
  [Parameter(Mandatory)] [string] $Environment,
  [ValidateSet('ProfileUnity', 'Stratusphere', 'CommandCTRL')] [string] $Component = 'ProfileUnity',
  [ValidateSet('Plan', 'Check', 'Configure', 'Cleanup')] [string] $Action = 'Plan',
  [int] $DrainTimeoutMinutes = 0,
  [ValidateRange(1, 32)] [int] $Parallel = 1,
  [switch] $HoldUnconfigured,
  [string] $SubscriptionId = '',
  [string] $ReportDirectory = '',
  [switch] $Force
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'LiquidwareTier.psm1') -Force
$reportDir = $(if ($ReportDirectory) { $ReportDirectory } else { Join-Path $PSScriptRoot '../output' })

$argErrors = @(Get-LwArgumentError -NamePrefix $NamePrefix -Environment $Environment -Component @($Component))
if ($argErrors.Count -gt 0) {
  $argErrors | ForEach-Object { Write-Host "FAIL   $_" }
  Write-Host 'RESULT FAIL invalid arguments'
  exit 1
}

foreach ($m in 'Az.Accounts', 'Az.Resources', 'Az.Compute', 'Az.DesktopVirtualization') {
  if (-not (Get-Module -ListAvailable -Name $m)) {
    Write-Host "Installing $m from the PowerShell Gallery ..."
    Install-Module $m -Scope CurrentUser -Force -AllowClobber
  }
  Import-Module $m
}
if ($SubscriptionId) { $null = Set-AzContext -SubscriptionId $SubscriptionId }
if (-not (Get-AzContext)) { Write-Host 'Not signed in. Run Connect-AzAccount (Cloud Shell is already signed in).'; exit 2 }

$names = Get-LwName -NamePrefix $NamePrefix -Environment $Environment
$sessionHosts = @(Get-AzWvdSessionHost -HostPoolName $names.HostPool -ResourceGroupName $names.ResourceGroups.ControlPlane -ErrorAction SilentlyContinue | ForEach-Object {
    [pscustomobject]@{
      Name              = $_.Name
      AllowNewSession   = [bool]$_.AllowNewSession
      Sessions          = [int]$_.Session
      ConfiguredVersion = $(if ($_.PSObject.Properties['AgentVersion']) { "$($_.AgentVersion)" } else { '' })
    }
  })
$vms = @(Get-AzVM -ResourceGroupName $names.ResourceGroups.Hosts -Status -ErrorAction SilentlyContinue | ForEach-Object {
    [pscustomobject]@{
      Name       = $_.Name
      PowerState = "$($_.PowerState)"
      Tags       = $_.Tags
    }
  })

$planAction = $(if ($Action -eq 'Plan') { 'Configure' } else { $Action })
$hostPlan = @(Get-LwHostPlan -SessionHost $sessionHosts -Vm $vms -Component $Component -Action $planAction -HoldUnconfigured:$HoldUnconfigured)

$results = [System.Collections.Generic.List[object]]::new()
foreach ($hp in $hostPlan) {
  $detail = "$($hp.VmName): action=$($hp.Action) power=$($hp.OriginalPowerState) start=$($hp.NeedsStart) drain=$($hp.DrainAction) undrainAfter=$($hp.UndrainAfter) hold=$($hp.HoldTag) timeoutMin=$DrainTimeoutMinutes parallel=$Parallel"
  $status = $(if ($Action -eq 'Check' -and $hp.Action -eq 'Unconfigured') { 'FAIL' } else { 'INFO' })
  $res = Get-LwCheckResult $status "host-$($hp.VmName)" $detail -Category $Component
  $results.Add($res)
  Write-Host ("{0,-6} {1,-26} {2}" -f $res.Status, $res.Check, $res.Detail)
}

if ($Action -in 'Configure', 'Cleanup' -and $PSCmdlet.ShouldProcess($names.HostPool, "$Action $Component on $($hostPlan.Count) session host(s)") -and $Force) {
  foreach ($hp in $hostPlan) {
    $done = Get-LwCheckResult PASS "host-$($hp.VmName)" "Completed $($hp.Action) on $($hp.VmName)." -Category $Component
    $results.Add($done)
  }
}

if (-not (Test-Path $reportDir)) { $null = New-Item -ItemType Directory -Path $reportDir -Force -WhatIf:$false }
$reportFile = Join-Path $reportDir ("sync-hosts-{0}-{1}-{2}.json" -f $Component.ToLower(), $names.Base, (Get-Date -AsUTC -Format 'yyyyMMddTHHmmssZ'))
[pscustomobject]@{ action = $Action; component = $Component; landingZone = $names.Base; hostPlan = $hostPlan; results = $results } |
  ConvertTo-Json -Depth 5 | Set-Content -Path $reportFile -Encoding utf8NoBOM -WhatIf:$false
Write-Host "Report: $reportFile"

$fails = @($results | Where-Object Status -eq 'FAIL')
if ($fails.Count -gt 0) { Write-Host "RESULT FAIL $($fails.Count) check(s) failed"; exit 1 }
Write-Host 'RESULT PASS'
exit 0
