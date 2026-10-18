<#
.SYNOPSIS
  Rolls the Stratusphere Connector ID Key out to Azure VMs: AVD session hosts or any Windows VM.
  Personal project, not for production use. Provided as is, without warranty of any kind. Not affiliated with the author's employer, with Liquidware or with Microsoft.

.DESCRIPTION
  Picks the targets (a host pool, a resource group, a tag or named VMs), skips what can't take
  the key (not running, not Windows), and runs scripts/agent/Invoke-CidKeyAction.ps1 on the rest
  through Azure Run Command, several machines at a time.

  -Action Plan (the default) only lists what would happen. Then:
    Check      which machines have the key: present, degraded (and what is wrong) or absent.
    Install    installs; skips machines that already have it unless -Force.
    Fix        repairs: installs where absent, starts stopped services, reinstalls a half-installed
               key. -Force reinstalls healthy ones too (for example to point them at another Hub).
    Uninstall  the installer's own uninstall.
    Cleanup    uninstalls with whatever uninstaller exists and removes leftovers (services,
               settings key, program folders). For teardown and for broken machines.
  -FromReport <output/cid-rollout-*.json> reruns on the machines that did not end healthy last time,
  for example: -FromReport output/cid-rollout-20261015-221500.json -Action Fix ...

  Every machine downloads the installer from -InstallerUrl and verifies -InstallerSha256 before
  running it. Use the installer you downloaded from your own Hub (Hub Administration > Connector
  ID Keys), served from somewhere the machines can reach: for example a storage container with a
  short-lived SAS URL. The repo never ships it.

  Results go to the console, one line per machine, and to output/cid-rollout-<time>.json
  (git-ignored: it holds machine names). The last line is RESULT PASS or RESULT FAIL.

.EXAMPLE
  ./scripts/ops/Deploy-CidKey.ps1 -HostPoolName hp-avdlz-dev -HostPoolResourceGroup rg-avdlz-dev-avd
.EXAMPLE
  ./scripts/ops/Deploy-CidKey.ps1 -HostPoolName hp-avdlz-dev -HostPoolResourceGroup rg-avdlz-dev-avd `
    -Action Install -HubAddress 10.60.0.4 -InstallerUrl $url -InstallerSha256 $sha
#>
[CmdletBinding(DefaultParameterSetName = 'HostPool')]
param(
  [Parameter(Mandatory, ParameterSetName = 'HostPool')] [string] $HostPoolName,
  [Parameter(Mandatory, ParameterSetName = 'HostPool')] [string] $HostPoolResourceGroup,
  [Parameter(Mandatory, ParameterSetName = 'ResourceGroup')] [string] $ResourceGroupName,
  [Parameter(ParameterSetName = 'ResourceGroup')] [string[]] $VmName,
  [Parameter(Mandatory, ParameterSetName = 'Tag')] [string] $TagName,
  [Parameter(Mandatory, ParameterSetName = 'Tag')] [string] $TagValue,
  [Parameter(Mandatory, ParameterSetName = 'Report')] [string] $FromReport,
  [ValidateSet('Plan', 'Check', 'Install', 'Fix', 'Uninstall', 'Cleanup')] [string] $Action = 'Plan',
  [string] $HubAddress = '',
  [string] $InstallerUrl = '',
  [string] $InstallerSha256 = '',
  [switch] $Force,
  [ValidateRange(1, 32)] [int] $ThrottleLimit = 8
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $PSScriptRoot 'CidKeyRollout.psm1') -Force

if ($Action -ne 'Plan') {
  $argErrors = @(Get-SsuxCidArgumentError -HubAddress $HubAddress -InstallerUrl $InstallerUrl -InstallerSha256 $InstallerSha256 -Action $Action)
  if ($argErrors.Count -gt 0) {
    $argErrors | ForEach-Object { Write-Host "FAIL   $_" }
    Write-Host 'RESULT FAIL invalid arguments'
    exit 1
  }
}

foreach ($m in 'Az.Accounts', 'Az.Compute', 'Az.DesktopVirtualization') {
  if (-not (Get-Module -ListAvailable -Name $m)) {
    Write-Host "Installing $m from the PowerShell Gallery ..."
    Install-Module $m -Scope CurrentUser -Force -AllowClobber
  }
  Import-Module $m
}
$context = Get-AzContext
if (-not $context) { Write-Host 'Not signed in. Run Connect-AzAccount (Cloud Shell is already signed in).'; exit 1 }

# ---------- Targets ----------
Write-Host "Finding target VMs in $($context.Subscription.Name) ..."
$vms = @()
switch ($PSCmdlet.ParameterSetName) {
  'HostPool' {
    $hosts = @(Get-AzWvdSessionHost -HostPoolName $HostPoolName -ResourceGroupName $HostPoolResourceGroup)
    $ids = @($hosts | ForEach-Object ResourceId | Where-Object { $_ })
    foreach ($rg in ($ids | ForEach-Object { ($_ -split '/')[4] } | Sort-Object -Unique)) {
      $names = $ids | Where-Object { ($_ -split '/')[4] -eq $rg } | ForEach-Object { ($_ -split '/')[-1] }
      $vms += @(Get-AzVM -ResourceGroupName $rg -Status | Where-Object { $names -contains $_.Name })
    }
  }
  'ResourceGroup' {
    $vms = @(Get-AzVM -ResourceGroupName $ResourceGroupName -Status | Where-Object { -not $VmName -or $VmName -contains $_.Name })
  }
  'Tag' {
    $vms = @(Get-AzVM -Status | Where-Object { $_.Tags -and $_.Tags[$TagName] -eq $TagValue })
  }
  'Report' {
    $retry = @(Get-SsuxCidRetryTarget -Report (Get-Content $FromReport -Raw | ConvertFrom-Json))
    Write-Host "$($retry.Count) machine(s) in $FromReport did not end healthy."
    foreach ($rg in ($retry | ForEach-Object ResourceGroupName | Sort-Object -Unique)) {
      $names = $retry | Where-Object ResourceGroupName -eq $rg | ForEach-Object Name
      $vms += @(Get-AzVM -ResourceGroupName $rg -Status | Where-Object { $names -contains $_.Name })
    }
  }
}

$rows = @($vms | ForEach-Object {
    [pscustomobject]@{ Name = $_.Name; ResourceGroupName = $_.ResourceGroupName; OsType = [string]$_.StorageProfile.OsDisk.OsType; PowerState = $_.PowerState }
  })
$plan = @(Get-SsuxCidTargetPlan -Vm $rows)
if ($plan.Count -eq 0) { Write-Host 'No VMs matched the target.'; Write-Host 'RESULT FAIL no targets'; exit 1 }

Write-Host ''
foreach ($p in $plan) { Write-Host ("{0,-5} {1,-24} {2}" -f $p.Plan, $p.Name, $p.Reason) }
$run = @($plan | Where-Object Plan -eq 'Run')
Write-Host ''
Write-Host "$($run.Count) of $($plan.Count) VM(s) would run '$Action'."
$warning = Get-SsuxCidPersistenceWarning -FromHostPool ($PSCmdlet.ParameterSetName -eq 'HostPool') -HostCount $run.Count
if ($warning) { Write-Host "NOTE   $warning" }
if ($Action -eq 'Plan') { Write-Host 'RESULT PASS plan only; rerun with -Action Check, Install, Fix, Uninstall or Cleanup'; exit 0 }
if ($run.Count -eq 0) { Write-Host 'RESULT FAIL nothing to run on'; exit 1 }

# ---------- Run ----------
$agentScript = Get-Content (Join-Path $repoRoot 'scripts/agent/Invoke-CidKeyAction.ps1') -Raw
$remote = Get-SsuxCidRemoteScript -AgentScript $agentScript -Action $Action -HubAddress $HubAddress -InstallerUrl $InstallerUrl -InstallerSha256 $InstallerSha256 -Force:$Force

Write-Host "Running '$Action' on $($run.Count) VM(s), $ThrottleLimit at a time (Run Command takes a minute or more per machine) ..."
$raw = $run | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
  $target = $_
  try {
    $r = Invoke-AzVMRunCommand -ResourceGroupName $target.ResourceGroupName -VMName $target.Name -CommandId 'RunPowerShellScript' `
      -ScriptString $using:remote -DefaultProfile $using:context -ErrorAction Stop
    [pscustomobject]@{ Name = $target.Name; Output = [string]$r.Value[0].Message; ErrorText = [string]$r.Value[1].Message }
  }
  catch {
    [pscustomobject]@{ Name = $target.Name; Output = ''; ErrorText = "Run Command failed: $($_.Exception.Message)" }
  }
}

$outcomes = @($raw | ForEach-Object { Get-SsuxCidRunOutcome -Name $_.Name -Output $_.Output -ErrorText $_.ErrorText } | Sort-Object Name)
Write-Host ''
foreach ($o in $outcomes) { Write-Host ("{0,-18} {1,-24} {2,-12} {3}" -f $o.Status, $o.Name, $o.Version, $o.Detail) }

$outDir = Join-Path $repoRoot 'output'
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
$report = Join-Path $outDir ("cid-rollout-{0:yyyyMMdd-HHmmss}.json" -f (Get-Date))
[pscustomobject]@{ action = $Action; hubAddress = $HubAddress; planned = $plan; outcomes = $outcomes } |
  ConvertTo-Json -Depth 5 | Set-Content -Path $report
Write-Host ''
Write-Host "Report: $report"

$summary = Get-SsuxCidSummary -Outcome $outcomes
if ($summary.Result -eq 'FAIL') {
  Write-Host "RESULT FAIL $($summary.Failed) of $($summary.Total) failed or degraded; rerun them with -FromReport $report -Action Fix (or Cleanup)"
  exit 1
}
Write-Host "RESULT PASS $($summary.Total) VM(s)"
