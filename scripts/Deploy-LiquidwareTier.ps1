#requires -Version 7.4
<#
.SYNOPSIS
  Deploys ProfileUnity, FlexApp and Stratusphere against an existing avd-landing-zone landing zone.
  Personal project, not for production use. Provided as is, without warranty of any kind. Not affiliated with the author's employer, with Liquidware or with Microsoft.

.DESCRIPTION
  One entry point for the whole tier (docs/deploy-spec.md). -Component picks what, -Action what to do:
    Plan     (default) what would change. Changes nothing.
    Check    what exists and whether it is healthy. Ends with RESULT PASS or FAIL.
    Deploy, Configure, Promote, Fix, Cleanup   built slice by slice (deploy-spec section 15).

  Built so far (slice B1): the landing zone discovery, the tier address check and, for
  Stratusphere, the parameters its own scripts get when pointed at this landing zone.

  Read-only: nothing in this slice writes to Azure.

.EXAMPLE
  ./scripts/Deploy-LiquidwareTier.ps1 -NamePrefix avdlz -Environment dev -Component ProfileUnity,FlexApp,Stratusphere
.EXAMPLE
  ./scripts/Deploy-LiquidwareTier.ps1 -NamePrefix avdlz -Environment dev -Component Stratusphere -Action Check
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string] $NamePrefix,
  [Parameter(Mandatory)] [string] $Environment,
  [Parameter(Mandatory)] [string[]] $Component,
  [ValidateSet('Plan', 'Check', 'Deploy', 'Configure', 'Promote', 'Fix', 'Cleanup')] [string] $Action = 'Plan',
  [string] $TierAddressPrefix = '10.61.0.0/24',
  [string] $SubscriptionId = ''
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'LiquidwareTier.psm1') -Force

$argErrors = @(Get-LwArgumentError -NamePrefix $NamePrefix -Environment $Environment -Component $Component -TierAddressPrefix $TierAddressPrefix)
if ($argErrors.Count -gt 0) {
  $argErrors | ForEach-Object { Write-Host "FAIL   $_" }
  Write-Host 'RESULT FAIL invalid arguments'
  exit 1
}

foreach ($m in 'Az.Accounts', 'Az.Resources', 'Az.Network') {
  if (-not (Get-Module -ListAvailable -Name $m)) {
    Write-Host "Installing $m from the PowerShell Gallery ..."
    Install-Module $m -Scope CurrentUser -Force -AllowClobber
  }
  Import-Module $m
}
if ($SubscriptionId) { $null = Set-AzContext -SubscriptionId $SubscriptionId }
$context = Get-AzContext
if (-not $context) { Write-Host 'Not signed in. Run Connect-AzAccount (Cloud Shell is already signed in).'; exit 2 }

$names = Get-LwName -NamePrefix $NamePrefix -Environment $Environment
Write-Host "Subscription: $($context.Subscription.Name)   Landing zone: $($names.Base)   Components: $($Component -join ', ')   Action: $Action"

$results = [System.Collections.Generic.List[object]]::new()
function Add-Result($r) {
  foreach ($x in @($r)) {
    if (-not $x) { continue }
    $results.Add($x)
    $hint = $(if ($x.Recommendation -and $x.Status -in 'FAIL', 'WARN') { "  [fix: $($x.Recommendation)]" } else { '' })
    Write-Host ("{0,-6} {1,-26} {2}{3}" -f $x.Status, $x.Check, $x.Detail, $hint)
  }
}

# ---------- Reading the landing zone ----------
Write-Host 'Reading the landing zone (resource groups, resources, spoke VNet) ...'
$groups = @(Get-AzResourceGroup | Select-Object -ExpandProperty ResourceGroupName)
$resources = @()
foreach ($g in $names.ResourceGroups.Values) {
  if ($groups -contains $g) { $resources += @(Get-AzResource -ResourceGroupName $g) }
}
$vnet = $null
$az = Get-AzVirtualNetwork -ResourceGroupName $names.ResourceGroups.Network -Name $names.Vnet -ErrorAction SilentlyContinue
if ($az) {
  $vnet = [pscustomobject]@{
    Id              = $az.Id
    Location        = $az.Location
    AddressPrefixes = @($az.AddressSpace.AddressPrefixes)
    Subnets         = @($az.Subnets | ForEach-Object { [pscustomobject]@{ Name = $_.Name; AddressPrefix = @($_.AddressPrefix)[0] } })
    Peerings        = @($az.VirtualNetworkPeerings | Where-Object { $_ } | ForEach-Object {
        [pscustomobject]@{ Name = $_.Name; RemoteVnetId = $_.RemoteVirtualNetwork.Id; RemoteAddressPrefixes = @($_.RemoteVirtualNetworkAddressSpace.AddressPrefixes) }
      })
  }
}
$lz = Get-LwLandingZone -NamePrefix $NamePrefix -Environment $Environment -ResourceGroup $groups -Resource $resources -Vnet $vnet

Add-Result (Get-LwLandingZoneCheck -LandingZone $lz)
if (@($lz.VnetAddressPrefixes).Count -gt 0) {
  Add-Result (Get-LwAddressCheck -TierAddressPrefix $TierAddressPrefix -LandingZone $lz)
}

if ($Component -contains 'Stratusphere' -and @($lz.Missing).Count -eq 0) {
  $ssux = Get-LwStratusphereArgument -LandingZone $lz
  $line = ($ssux.GetEnumerator() | ForEach-Object { if ($_.Value -is [bool]) { if ($_.Value) { "-$($_.Key)" } } else { "-$($_.Key) $($_.Value)" } }) -join ' '
  Add-Result (Get-LwCheckResult INFO 'stratusphere-arguments' "stratusphere/scripts/ops/Test-StratusphereReadiness.ps1 $line" -Category Stratusphere)
}

Add-Result (Get-LwPlanSummary -Component $Component -Action $Action)

$fails = @($results | Where-Object Status -eq 'FAIL')
if ($fails.Count -gt 0) { Write-Host "RESULT FAIL $($fails.Count) check(s) failed"; exit 1 }
Write-Host 'RESULT PASS'
