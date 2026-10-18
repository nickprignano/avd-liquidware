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

  Built so far (slices B1 to B3): the landing zone discovery, the tier address check, for
  Stratusphere the parameters its own scripts get when pointed at this landing zone and, for
  ProfileUnity and FlexApp, a what-if of profileunity/bicep/main.bicep (network, Key Vault,
  config, packages and media accounts, the console VM and its identity's roles) that fails on
  any change to the landing zone outside deploy-spec section 4. Installers go up with
  Publish-LiquidwareMedia.ps1, the license string with Set-LiquidwareSecret.ps1.

  Read-only: nothing in these slices writes to Azure. What-if needs the Bicep CLI (Cloud Shell has it).

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
  [string] $SubscriptionId = '',
  # Object ID of the landing zone users group, when discovery finds none or several. Never commit it.
  [string] $UsersGroupId = '',
  [switch] $Bastion
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'LiquidwareTier.psm1') -Force

$argErrors = @(Get-LwArgumentError -NamePrefix $NamePrefix -Environment $Environment -Component $Component -TierAddressPrefix $TierAddressPrefix)
if ($argErrors.Count -gt 0) {
  $argErrors | ForEach-Object { Write-Host "FAIL   $_" }
  Write-Host 'RESULT FAIL invalid arguments'
  exit 1
}

foreach ($m in 'Az.Accounts', 'Az.Resources', 'Az.Network', 'Az.Compute') {
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

$profileUnity = @($Component | Where-Object { $_ -in 'ProfileUnity', 'FlexApp' }).Count -gt 0
if ($profileUnity -and $Action -eq 'Plan' -and @($results | Where-Object Status -eq 'FAIL').Count -eq 0) {
  Write-Host 'Reading the users group and the Azure Virtual Desktop service principals ...'
  $assignments = @(Get-AzRoleAssignment -Scope $lz.ProfilesAccountId | ForEach-Object {
      [pscustomobject]@{ ObjectId = $_.ObjectId; ObjectType = $_.ObjectType; RoleDefinitionName = $_.RoleDefinitionName }
    })
  $users = Get-LwUsersGroup -RoleAssignment $assignments -Override $UsersGroupId
  Add-Result $users.Result
  # Azure Virtual Desktop and Azure Virtual Desktop ARM Provider: Microsoft's application IDs, the same in every tenant.
  $avd = @('9cdead84-a844-4324-93f2-b2e6bb768d07', '50e95039-b200-4007-bc97-8d5790743a63' | ForEach-Object {
      (Get-AzADServicePrincipal -ApplicationId $_ -ErrorAction SilentlyContinue).Id
    } | Where-Object { $_ })
  if ($avd.Count -ne 2) {
    Add-Result (Get-LwCheckResult FAIL 'avd-service-principals' "Found $($avd.Count) of the 2 Azure Virtual Desktop service principals." -Recommendation 'Register Microsoft.DesktopVirtualization; the landing zone deploy normally has.' -Category 'Landing zone')
  }
  # The operator uploads installers to media (Storage Blob Data Contributor there, for them only).
  $operator = Get-AzADUser -SignedIn -ErrorAction SilentlyContinue
  if (-not $operator) {
    Add-Result (Get-LwCheckResult FAIL 'operator' 'The signed-in account is not a user, so it cannot be the media operator.' -Recommendation 'Run from Cloud Shell signed in as yourself.' -Category 'ProfileUnity')
  }
  Write-Host 'Reading the console VM and the license secret (management plane) ...'
  $consoleVm = $null
  $licenseSecret = $null
  if ($groups -contains $names.TierGroup) {
    # Not found is an answer here, and the Az cmdlets throw it as a terminating error.
    $vm = $(try { Get-AzVM -ResourceGroupName $names.TierGroup -Name $names.ConsoleVm -ErrorAction Stop } catch { $null })
    if ($vm) { $consoleVm = [pscustomobject]@{ Name = $vm.Name; PrincipalId = $(if ($vm.Identity) { $vm.Identity.PrincipalId } else { '' }) } }
    $vault = @(Get-AzResource -ResourceGroupName $names.TierGroup -ResourceType 'Microsoft.KeyVault/vaults') | Select-Object -First 1
    if ($vault) { $licenseSecret = $(try { Get-AzResource -ResourceId "$($vault.ResourceId)/secrets/lw-licstr" -ErrorAction Stop } catch { $null }) }
  }
  $state = Get-LwTierState -Console $consoleVm -LicenseSecret $licenseSecret
  Add-Result $state.Result
  if ($operator -and $users.ObjectId -and $avd.Count -eq 2 -and @($state.Result | Where-Object Status -eq 'FAIL').Count -eq 0) {
    # Only a new console gets a password; it lives in this process and in the tier Key Vault, nowhere else.
    $password = $(if (-not $state.ConsoleExists) { Get-LwGeneratedPassword } else { $null })
    $params = Get-LwTemplateParameter -LandingZone $lz -TierAddressPrefix $TierAddressPrefix -UsersGroupObjectId $users.ObjectId -AvdServicePrincipalObjectId $avd `
      -OperatorObjectId $operator.Id -TierState $state -ConsoleAdminPassword $password -Bastion:$Bastion
    $templateParams = @{}
    foreach ($k in $params.Keys) {
      $v = $params[$k]
      # The deployment cmdlets take secure parameters as plain strings; convert at the last moment.
      if ($v -is [securestring]) { $v = [System.Net.NetworkCredential]::new('', $v).Password }
      elseif ($null -eq $v) { $v = '' }
      $templateParams[$k] = $v
    }
    Write-Host 'Running what-if on profileunity/bicep/main.bicep (read-only) ...'
    $whatIf = Get-AzSubscriptionDeploymentWhatIfResult -Name "liquidware-$($names.Base)" -Location $lz.Location `
      -TemplateFile (Join-Path $PSScriptRoot '../profileunity/bicep/main.bicep') -TemplateParameterObject $templateParams
    $changes = @($whatIf.Changes | ForEach-Object { [pscustomobject]@{ ChangeType = "$($_.ChangeType)"; ResourceId = $_.FullyQualifiedResourceId } })
    $templateParams.Remove('consoleAdminPassword')
    $password = $null
    Add-Result (Get-LwWhatIfSummary -Change $changes -LandingZone $lz)
  }
}

Add-Result (Get-LwPlanSummary -Component $Component -Action $Action)

$fails = @($results | Where-Object Status -eq 'FAIL')
if ($fails.Count -gt 0) { Write-Host "RESULT FAIL $($fails.Count) check(s) failed"; exit 1 }
Write-Host 'RESULT PASS'
