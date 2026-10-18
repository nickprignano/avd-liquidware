# Pure functions behind Deploy-LiquidwareTier.ps1: names, landing zone discovery and checks.
# They take data already read from Azure and return objects, so they are tested offline
# (tests/LiquidwareTier.Tests.ps1). Design: docs/deploy-spec.md.
# Personal project, not for production use. Provided as is, without warranty of any kind. Not affiliated with the author's employer, with Liquidware or with Microsoft.

# The CIDR helpers already exist in the Stratusphere preflight; reuse them rather than copy them.
Import-Module (Join-Path $PSScriptRoot '../stratusphere/scripts/ops/StratusphereReadiness.psm1') -Force -Scope Local

$script:Environments = @('dev', 'test', 'prod')
$script:Components = @('ProfileUnity', 'FlexApp', 'Stratusphere')

function Get-LwCheckResult {
  # One check result, in the same shape as the Stratusphere scripts' results.
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [ValidateSet('PASS', 'WARN', 'FAIL', 'FIXED', 'INFO', 'SKIP')] [string] $Status,
    [Parameter(Mandatory)] [string] $Check,
    [Parameter(Mandatory)] [string] $Detail,
    [string] $Recommendation = '',
    [string] $Category = ''
  )
  [pscustomobject]@{ Category = $Category; Status = $Status; Check = $Check; Detail = $Detail; Recommendation = $Recommendation }
}

function Get-LwArgumentError {
  # Values that end up in resource names and template parameters are validated strictly.
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string] $NamePrefix,
    [Parameter(Mandatory)] [string] $Environment,
    [AllowEmptyCollection()] [string[]] $Component = @(),
    [string] $TierAddressPrefix = ''
  )
  $errors = @()
  if ($NamePrefix -cnotmatch '^[a-z0-9-]{2,8}$') { $errors += "NamePrefix '$NamePrefix' must be the landing zone's prefix: 2-8 lowercase letters, digits or hyphens." }
  if ($script:Environments -cnotcontains $Environment) { $errors += "Environment '$Environment' must be one of: $($script:Environments -join ', ')." }
  if (@($Component).Count -eq 0) { $errors += "Choose at least one -Component: $($script:Components -join ', ')." }
  foreach ($c in $Component) {
    if ($script:Components -notcontains $c) { $errors += "Unknown component '$c'. Known: $($script:Components -join ', ')." }
  }
  if ($TierAddressPrefix) {
    $r = Get-SsuxCidrRange $TierAddressPrefix
    if (-not $r) { $errors += "TierAddressPrefix '$TierAddressPrefix' is not an IPv4 CIDR." }
    elseif ($r.Length -gt 24) { $errors += "TierAddressPrefix '$TierAddressPrefix' must be /24 or larger (the tier's subnets need it)." }
  }
  $errors
}

function Get-LwName {
  # The landing zone's names (bicep/main.bicep in avd-landing-zone) and this tier's, from the prefix and environment.
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string] $NamePrefix,
    [Parameter(Mandatory)] [string] $Environment
  )
  $clean = $NamePrefix.ToLower().Replace('-', '')
  $base = "$clean-$Environment"
  # Stratusphere's own prefix rule is 2-8 lowercase letters or digits; keep the environment's first letter.
  $ssux = "$($clean.Substring(0, [Math]::Min($clean.Length, 7)))$($Environment.Substring(0, 1))"
  [pscustomobject]@{
    Clean          = $clean
    Base           = $base
    ResourceGroups = [ordered]@{
      Network      = "rg-$base-network"
      Management   = "rg-$base-management"
      Storage      = "rg-$base-storage"
      ControlPlane = "rg-$base-avd"
      Hosts        = "rg-$base-hosts"
    }
    Vnet           = "vnet-$base"
    HostPool       = "vdpool-$base"
    AppGroup       = "vdag-$base-desktop"
    LogAnalytics   = "log-$base"
    TierGroup      = "rg-$base-liquidware"
    TierVnet       = "vnet-$base-liquidware"
    PeeringToTier  = "peer-$base-to-liquidware"
    StratusphereNamePrefix = $ssux
    StratusphereGroup      = "rg-$ssux-stratusphere"
  }
}

function Get-LwLandingZone {
  # Finds the landing zone in what Azure returned. Never throws for a missing piece: each one is
  # listed in Missing, and Get-LwLandingZoneCheck turns the list into FAIL lines.
  #   ResourceGroup: names of the subscription's resource groups.
  #   Resource:      objects with ResourceId, Name, ResourceType, ResourceGroupName, Location and,
  #                  for storage accounts, Kind (Get-AzResource shape).
  #   Vnet:          the spoke, or $null: AddressPrefixes, Subnets (Name, AddressPrefix),
  #                  Peerings (Name, RemoteVnetId, RemoteAddressPrefixes).
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string] $NamePrefix,
    [Parameter(Mandatory)] [string] $Environment,
    [AllowEmptyCollection()] [string[]] $ResourceGroup = @(),
    [AllowEmptyCollection()] [object[]] $Resource = @(),
    $Vnet = $null
  )
  $n = Get-LwName -NamePrefix $NamePrefix -Environment $Environment
  $missing = [System.Collections.Generic.List[string]]::new()
  foreach ($k in $n.ResourceGroups.Keys) {
    if ($ResourceGroup -notcontains $n.ResourceGroups[$k]) { $missing.Add("resource group $($n.ResourceGroups[$k])") }
  }
  function Find-One([string] $Type, [string] $Group, [string] $Name = '', [string] $Kind = '') {
    @($Resource | Where-Object {
        $_ -and $_.ResourceType -eq $Type -and $_.ResourceGroupName -eq $Group -and
        (-not $Name -or $_.Name -eq $Name) -and (-not $Kind -or $_.Kind -eq $Kind)
      }) | Select-Object -First 1
  }
  $rg = $n.ResourceGroups
  $profiles = Find-One 'Microsoft.Storage/storageAccounts' $rg.Storage -Kind 'FileStorage'
  $keyVault = Find-One 'Microsoft.KeyVault/vaults' $rg.Management
  $law = Find-One 'Microsoft.OperationalInsights/workspaces' $rg.Management $n.LogAnalytics
  $hostPool = Find-One 'Microsoft.DesktopVirtualization/hostPools' $rg.ControlPlane $n.HostPool
  $appGroup = Find-One 'Microsoft.DesktopVirtualization/applicationGroups' $rg.ControlPlane $n.AppGroup
  $zones = @($Resource | Where-Object { $_ -and $_.ResourceType -eq 'Microsoft.Network/privateDnsZones' -and $_.ResourceGroupName -eq $rg.Network })
  $fileZone = @($zones | Where-Object Name -like 'privatelink.file.*') | Select-Object -First 1
  $vaultZone = @($zones | Where-Object Name -like 'privatelink.vaultcore.*') | Select-Object -First 1

  if (-not $Vnet) { $missing.Add("virtual network $($n.Vnet)") }
  $hostSubnet = $null
  if ($Vnet) {
    $hostSubnet = @($Vnet.Subnets | Where-Object { $_ -and $_.Name -eq 'snet-session-hosts' }) | Select-Object -First 1
    if (-not $hostSubnet) { $missing.Add("subnet snet-session-hosts in $($n.Vnet)") }
  }
  if (-not $profiles) { $missing.Add("profiles storage account (FileStorage) in $($rg.Storage)") }
  if (-not $keyVault) { $missing.Add("Key Vault in $($rg.Management)") }
  if (-not $law) { $missing.Add("Log Analytics workspace $($n.LogAnalytics)") }
  if (-not $hostPool) { $missing.Add("host pool $($n.HostPool)") }
  if (-not $appGroup) { $missing.Add("application group $($n.AppGroup)") }

  # Standalone landing zones own their privatelink zones; HubPeered ones use the platform's (no local zones).
  $mode = $(if ($fileZone) { 'Standalone' } else { 'HubPeered' })
  [pscustomobject]@{
    Names              = $n
    ConnectivityMode   = $mode
    Location           = $(if ($Vnet) { $Vnet.Location } elseif ($hostPool) { $hostPool.Location } else { $null })
    VnetId             = $(if ($Vnet) { $Vnet.Id } else { $null })
    VnetAddressPrefixes = @($(if ($Vnet) { $Vnet.AddressPrefixes } else { @() }))
    SessionHostSubnetPrefix = $(if ($hostSubnet) { $hostSubnet.AddressPrefix } else { $null })
    Peerings           = @($(if ($Vnet) { @($Vnet.Peerings | Where-Object { $_ }) } else { @() }))
    ProfilesAccountId  = $(if ($profiles) { $profiles.ResourceId } else { $null })
    KeyVaultId         = $(if ($keyVault) { $keyVault.ResourceId } else { $null })
    LogAnalyticsId     = $(if ($law) { $law.ResourceId } else { $null })
    HostPoolId         = $(if ($hostPool) { $hostPool.ResourceId } else { $null })
    AppGroupId         = $(if ($appGroup) { $appGroup.ResourceId } else { $null })
    FileDnsZoneId      = $(if ($fileZone) { $fileZone.ResourceId } else { $null })
    VaultDnsZoneId     = $(if ($vaultZone) { $vaultZone.ResourceId } else { $null })
    Missing            = $missing.ToArray()
  }
}

function Get-LwLandingZoneCheck {
  # PASS when everything the tier reads is there; one FAIL per missing piece otherwise.
  [CmdletBinding()]
  param([Parameter(Mandatory)] $LandingZone)
  $lz = $LandingZone
  $fix = "Deploy the landing zone first (avd-landing-zone: scripts/deploy/deploy.sh), or check -NamePrefix and -Environment."
  foreach ($m in @($lz.Missing)) {
    Get-LwCheckResult FAIL 'landing-zone' "Not found: $m" -Recommendation $fix -Category 'Landing zone'
  }
  if (@($lz.Missing).Count -eq 0) {
    Get-LwCheckResult PASS 'landing-zone' "$($lz.Names.Base) found in $($lz.Location) ($($lz.ConnectivityMode))" -Category 'Landing zone'
  }
  if ($lz.ConnectivityMode -eq 'HubPeered') {
    Get-LwCheckResult FAIL 'connectivity-mode' 'No local privatelink zones: a HubPeered landing zone. The tier specifies HubPeered (deploy-spec section 4) but builds Standalone first.' -Recommendation 'Use a Standalone landing zone for now.' -Category 'Landing zone'
  }
}

function Get-LwAddressCheck {
  # The tier's VNet must not overlap the spoke (the peering would be refused), anything the spoke
  # already peers with, or the Stratusphere VNet, which peers with the same spoke.
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string] $TierAddressPrefix,
    [Parameter(Mandatory)] $LandingZone,
    [string] $StratusphereAddressPrefix = '10.60.0.0/24'
  )
  $other = @()
  foreach ($p in @($LandingZone.VnetAddressPrefixes)) { if ($p) { $other += [pscustomobject]@{ Source = 'the spoke'; Prefix = $p; Blocking = $true } } }
  foreach ($peer in @($LandingZone.Peerings)) {
    # Our own peering to the tier VNet is expected: skip it.
    if (-not $peer -or $peer.Name -eq $LandingZone.Names.PeeringToTier) { continue }
    foreach ($p in @($peer.RemoteAddressPrefixes)) { if ($p) { $other += [pscustomobject]@{ Source = "peered: $($peer.Name)"; Prefix = $p; Blocking = $true } } }
  }
  if ($StratusphereAddressPrefix) { $other += [pscustomobject]@{ Source = 'the Stratusphere VNet'; Prefix = $StratusphereAddressPrefix; Blocking = $true } }
  foreach ($r in @(Get-SsuxAddressOverlapCheck -AddressPrefix $TierAddressPrefix -Other $other)) {
    $r.Check = 'tier-address-space'
    $r.Category = 'Network'
    if ($r.Recommendation) { $r.Recommendation = 'Pick a free range with -TierAddressPrefix (default 10.61.0.0/24).' }
    $r
  }
}

function Get-LwStratusphereArgument {
  # The Stratusphere scripts' parameters, pointed at the landing zone (deploy-spec section 9).
  [CmdletBinding()]
  param([Parameter(Mandatory)] $LandingZone)
  $lz = $LandingZone
  $hp = $(if ($lz.HostPoolId) { ($lz.HostPoolId -split '/') } else { @() })
  [ordered]@{
    Location              = $lz.Location
    NamePrefix            = $lz.Names.StratusphereNamePrefix
    PeerVnetId            = $lz.VnetId
    HostPoolName          = $(if ($hp.Count -ge 9) { $hp[8] } else { '' })
    HostPoolResourceGroup = $(if ($hp.Count -ge 5) { $hp[4] } else { '' })
    NoBastion             = $true
  }
}

function Get-LwPlanSummary {
  # What each component would do, for the slice that is built. Unbuilt steps say so.
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string[]] $Component,
    [Parameter(Mandatory)] [string] $Action
  )
  $built = @{ Plan = $true; Check = $true }
  foreach ($c in $Component) {
    if ($built.ContainsKey($Action)) { continue }
    Get-LwCheckResult FAIL "$($c.ToLower())-$($Action.ToLower())" "$Action for $c is not built yet (deploy-spec section 15)." -Category $c
  }
}

Export-ModuleMember -Function Get-LwCheckResult, Get-LwArgumentError, Get-LwName, Get-LwLandingZone, Get-LwLandingZoneCheck, Get-LwAddressCheck, Get-LwStratusphereArgument, Get-LwPlanSummary
