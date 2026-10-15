<#
.SYNOPSIS
  Pre-deployment checks for the Stratusphere UX assessment environment.
  Personal project, not for production use. Provided as is, without warranty of any kind (MIT License, see LICENSE). Not affiliated with the author's employer, with Liquidware or with Microsoft.

.DESCRIPTION
  Reads the subscription and reports PASS, WARN or FAIL for each check: signed in,
  resource providers, the Stratusphere Hub plans offered in the region, the image's
  purchase plan, the Marketplace terms, the VM size and vCPU quota. Run it with no
  -Plan first to list the plans offered in a region.

  With -Fix it registers missing resource providers and accepts the Marketplace terms
  for the chosen plan. Nothing else is changed.

.EXAMPLE
  pwsh ./scripts/ops/Test-StratusphereReadiness.ps1 -Location eastus2
  pwsh ./scripts/ops/Test-StratusphereReadiness.ps1 -Location eastus2 -Plan <plan> -Fix
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string] $Location,
  [string] $Plan,
  [string] $VmSize = 'Standard_D4s_v5',
  [string] $Publisher = 'liquidware',
  [string] $Offer = 'stratusphere',
  [switch] $Fix
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'StratusphereReadiness.psm1') -Force

foreach ($m in 'Az.Accounts', 'Az.Resources', 'Az.Compute', 'Az.MarketplaceOrdering') {
  if (-not (Get-Module -ListAvailable -Name $m)) {
    Write-Host "Installing $m from the PowerShell Gallery ..."
    Install-Module $m -Scope CurrentUser -Force -AllowClobber
  }
  Import-Module $m
}

$results = [System.Collections.Generic.List[object]]::new()
function Add-Result($r) { foreach ($x in @($r)) { $results.Add($x); Write-Host ("{0,-6} {1,-22} {2}" -f $x.Status, $x.Check, $x.Detail) } }

$context = Get-AzContext
if (-not $context) {
  Add-Result (Get-SsuxCheckResult FAIL 'signed-in' "Not signed in. Run Connect-AzAccount (Cloud Shell is already signed in).")
  Write-Host 'RESULT FAIL'
  exit 1
}
Add-Result (Get-SsuxCheckResult PASS 'signed-in' "$($context.Account.Id) on $($context.Subscription.Name)")

foreach ($ns in 'Microsoft.Compute', 'Microsoft.Network', 'Microsoft.KeyVault', 'Microsoft.MarketplaceOrdering') {
  $state = (Get-AzResourceProvider -ProviderNamespace $ns | Select-Object -First 1).RegistrationState
  if ($state -eq 'Registered') { Add-Result (Get-SsuxCheckResult PASS "provider" "$ns registered"); continue }
  if ($Fix) {
    Write-Host "Registering $ns ..."
    Register-AzResourceProvider -ProviderNamespace $ns | Out-Null
    Add-Result (Get-SsuxCheckResult FIXED 'provider' "$ns registration started (it can take a few minutes)")
  }
  else {
    Add-Result (Get-SsuxCheckResult FAIL 'provider' "$ns is $state. Run with -Fix.")
  }
}

Write-Host "Reading the Stratusphere plans offered in $Location ..."
$skus = @()
try { $skus = @(Get-AzVMImageSku -Location $Location -PublisherName $Publisher -Offer $Offer | ForEach-Object Skus) }
catch { Write-Host "  Get-AzVMImageSku: $($_.Exception.Message)" }
$planResult = Get-SsuxPlanCheck -AvailablePlans $skus -Plan $Plan -Location $Location
Add-Result $planResult

if ($planResult.Status -eq 'PASS') {
  $versions = @(Get-AzVMImage -Location $Location -PublisherName $Publisher -Offer $Offer -Skus $Plan)
  $latest = ($versions | Sort-Object { [version]($_.Version -replace '[^0-9.]', '') } | Select-Object -Last 1).Version
  $image = Get-AzVMImage -Location $Location -PublisherName $Publisher -Offer $Offer -Skus $Plan -Version $latest
  Add-Result (Get-SsuxImagePlanCheck -PurchasePlan $image.PurchasePlan -Version $latest)

  $terms = Get-AzMarketplaceTerms -Publisher $Publisher -Product $Offer -Name $Plan -OfferType 'virtualmachine'
  if ($terms.Accepted) {
    Add-Result (Get-SsuxCheckResult PASS 'marketplace-terms' "Accepted for $Publisher/$Offer/$Plan")
  }
  elseif ($Fix) {
    Set-AzMarketplaceTerms -Publisher $Publisher -Product $Offer -Name $Plan -Terms $terms -Accept | Out-Null
    Add-Result (Get-SsuxCheckResult FIXED 'marketplace-terms' "Accepted for $Publisher/$Offer/$Plan")
  }
  else {
    Add-Result (Get-SsuxCheckResult FAIL 'marketplace-terms' "Not accepted for $Publisher/$Offer/$Plan. Run with -Fix (deploy.sh also accepts them).")
  }
}

Write-Host "Reading VM sizes and quota in $Location ..."
$sku = Get-AzComputeResourceSku -Location $Location | Where-Object { $_.ResourceType -eq 'virtualMachines' -and $_.Name -eq $VmSize } | Select-Object -First 1
$sizeResult = Get-SsuxVmSizeCheck -Sku $sku -VmSize $VmSize -Location $Location
Add-Result $sizeResult
if ($sizeResult.Status -eq 'PASS') {
  $vcpus = [int](($sku.Capabilities | Where-Object Name -eq 'vCPUs').Value)
  Add-Result (Get-SsuxQuotaCheck -VCpusNeeded $vcpus -Family $sku.Family -Usage @(Get-AzVMUsage -Location $Location))
}

$failed = @($results | Where-Object Status -eq 'FAIL').Count
Write-Host ''
if ($failed -gt 0) {
  Write-Host "RESULT FAIL $failed check(s) failed"
  exit 1
}
Write-Host 'RESULT PASS ready to deploy'
