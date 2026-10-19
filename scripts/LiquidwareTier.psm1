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
    ConsoleVm      = "vm-$($clean)lwcon"
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
  $endpointSubnet = $null
  if ($Vnet) {
    $hostSubnet = @($Vnet.Subnets | Where-Object { $_ -and $_.Name -eq 'snet-session-hosts' }) | Select-Object -First 1
    if (-not $hostSubnet) { $missing.Add("subnet snet-session-hosts in $($n.Vnet)") }
    $endpointSubnet = @($Vnet.Subnets | Where-Object { $_ -and $_.Name -eq 'snet-private-endpoints' }) | Select-Object -First 1
    if (-not $endpointSubnet) { $missing.Add("subnet snet-private-endpoints in $($n.Vnet)") }
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
    PrivateEndpointSubnetPrefix = $(if ($endpointSubnet) { $endpointSubnet.AddressPrefix } else { $null })
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

function Get-LwUsersGroup {
  # The landing zone's users group: the one group holding SMB Share Contributor on the profiles
  # account (decision 0005 in avd-landing-zone). RoleAssignment: Get-AzRoleAssignment shape
  # (ObjectId, ObjectType, RoleDefinitionName, Scope) for the profiles account's scope.
  [CmdletBinding()]
  param(
    [AllowEmptyCollection()] [object[]] $RoleAssignment = @(),
    [string] $Override = ''
  )
  $fix = 'Pass the users group with -UsersGroupId (its object ID; never commit it).'
  if ($Override) {
    return [pscustomobject]@{ ObjectId = $Override; Result = (Get-LwCheckResult PASS 'users-group' 'Users group given with -UsersGroupId' -Category 'Landing zone') }
  }
  $groups = @($RoleAssignment | Where-Object { $_ -and $_.ObjectType -eq 'Group' -and $_.RoleDefinitionName -eq 'Storage File Data SMB Share Contributor' } |
      Select-Object -ExpandProperty ObjectId -Unique)
  if ($groups.Count -eq 1) {
    return [pscustomobject]@{ ObjectId = $groups[0]; Result = (Get-LwCheckResult PASS 'users-group' 'Users group found: the group with SMB Share Contributor on the profiles account' -Category 'Landing zone') }
  }
  $detail = $(if ($groups.Count -eq 0) { 'No group holds SMB Share Contributor on the profiles account.' } else { "$($groups.Count) groups hold SMB Share Contributor on the profiles account; the tier needs one." })
  [pscustomobject]@{ ObjectId = $null; Result = (Get-LwCheckResult FAIL 'users-group' $detail -Recommendation $fix -Category 'Landing zone') }
}

function Get-LwGeneratedPassword {
  # A local admin password for a new VM, built in memory and only ever handed to the template
  # (which writes it to the tier Key Vault). 24 characters with all four character classes,
  # well inside Azure's Windows rules (12 to 123 characters, three of four classes).
  [CmdletBinding()]
  [OutputType([securestring])]
  param([ValidateRange(16, 123)] [int] $Length = 24)
  $classes = @('ABCDEFGHJKLMNPQRSTUVWXYZ', 'abcdefghijkmnopqrstuvwxyz', '23456789', '!#%*-_=+?')
  $all = -join $classes
  $rng = [System.Security.Cryptography.RandomNumberGenerator]
  $chars = [System.Collections.Generic.List[char]]::new()
  foreach ($c in $classes) { $chars.Add($c[$rng::GetInt32($c.Length)]) }
  while ($chars.Count -lt $Length) { $chars.Add($all[$rng::GetInt32($all.Length)]) }
  # Fisher-Yates, so the guaranteed classes aren't always the first four characters.
  for ($i = $chars.Count - 1; $i -gt 0; $i--) {
    $j = $rng::GetInt32($i + 1)
    $t = $chars[$i]; $chars[$i] = $chars[$j]; $chars[$j] = $t
  }
  $secure = [securestring]::new()
  foreach ($ch in $chars) { $secure.AppendChar($ch) }
  $chars.Clear()
  $secure.MakeReadOnly()
  $secure
}

function Get-LwTierState {
  # What the tier already has that the template must not redo: the console VM (an existing one
  # keeps the password it was created with, lesson 0002) and the lw-licstr secret (a role can
  # only be scoped to a secret that exists).
  #   Console:       $null, or the VM: Name and PrincipalId (its system-assigned identity).
  #   LicenseSecret: $null, or the ARM resource Microsoft.KeyVault/vaults/secrets/lw-licstr
  #                  (management plane: it exists, its value is never read).
  [CmdletBinding()]
  param(
    $Console = $null,
    $LicenseSecret = $null
  )
  $results = @()
  $principal = $(if ($Console -and $Console.PSObject.Properties['PrincipalId']) { "$($Console.PrincipalId)" } else { '' })
  if (-not $Console) {
    $results += Get-LwCheckResult INFO 'console' 'No console VM yet: the deploy creates it, with a password generated now and kept only in the tier Key Vault.' -Category ProfileUnity
  }
  elseif (-not $principal) {
    $results += Get-LwCheckResult FAIL 'console' "$($Console.Name) has no system-assigned identity, so it can't read media or write staging." -Recommendation 'Turn its system-assigned identity back on, or delete the VM so the deploy recreates it.' -Category ProfileUnity
  }
  else {
    $results += Get-LwCheckResult INFO 'console' "$($Console.Name) exists: the deploy leaves the VM and its password alone." -Category ProfileUnity
  }
  if ($LicenseSecret) {
    $results += Get-LwCheckResult PASS 'license-secret' 'lw-licstr is stored in the tier Key Vault.' -Category ProfileUnity
  }
  else {
    $results += Get-LwCheckResult WARN 'license-secret' 'lw-licstr is not stored yet, so the console gets no role on it.' -Recommendation 'Run scripts/Set-LiquidwareSecret.ps1 once the tier is deployed, then Deploy again.' -Category ProfileUnity
  }
  [pscustomobject]@{
    ConsoleExists      = [bool] $Console
    ConsolePrincipalId = $principal
    LicenseStored      = [bool] $LicenseSecret
    Result             = $results
  }
}

function Get-LwTemplateParameter {
  # The parameters of profileunity/bicep/main.bicep, from the discovered landing zone and the
  # tier's own state (Get-LwTierState). ConsoleAdminPassword is only for a new console.
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] $LandingZone,
    [Parameter(Mandatory)] [string] $TierAddressPrefix,
    [Parameter(Mandatory)] [string] $UsersGroupObjectId,
    [Parameter(Mandatory)] [string[]] $AvdServicePrincipalObjectId,
    [Parameter(Mandatory)] [string] $OperatorObjectId,
    [Parameter(Mandatory)] $TierState,
    [securestring] $ConsoleAdminPassword = $null,
    [string] $AutoShutdownTime = '1900',
    [switch] $Bastion
  )
  $lz = $LandingZone
  if (-not $TierState.ConsoleExists -and -not $ConsoleAdminPassword) {
    throw 'A new console needs -ConsoleAdminPassword (Get-LwGeneratedPassword).'
  }
  if ($AutoShutdownTime -notmatch '^([01]\d|2[0-3])[0-5]\d$') { throw "AutoShutdownTime '$AutoShutdownTime' must be HHmm." }
  [ordered]@{
    location                         = $lz.Location
    namePrefix                       = $lz.Names.Clean
    environment                      = ($lz.Names.Base -split '-')[-1]
    tierAddressPrefix                = $TierAddressPrefix
    spokeVnetId                      = $lz.VnetId
    spokeAddressPrefixes             = @($lz.VnetAddressPrefixes)
    sessionHostSubnetPrefix          = $lz.SessionHostSubnetPrefix
    spokePrivateEndpointSubnetPrefix = $lz.PrivateEndpointSubnetPrefix
    fileDnsZoneId                    = $lz.FileDnsZoneId
    vaultDnsZoneId                   = $lz.VaultDnsZoneId
    usersGroupObjectId               = $UsersGroupObjectId
    avdServicePrincipalObjectIds     = @($AvdServicePrincipalObjectId)
    deployBastion                    = [bool] $Bastion
    operatorObjectId                 = $OperatorObjectId
    consoleExists                    = [bool] $TierState.ConsoleExists
    consolePrincipalId               = "$($TierState.ConsolePrincipalId)"
    # An existing console keeps its password: the template doesn't deploy the VM or the secret then.
    consoleAdminPassword             = $(if ($TierState.ConsoleExists) { $null } else { $ConsoleAdminPassword })
    licenseStored                    = [bool] $TierState.LicenseStored
    autoShutdownTime                 = $AutoShutdownTime
  }
}

function Get-LwWhatIfSummary {
  # One line per change what-if reports (Get-AzSubscriptionDeploymentWhatIfResult's Changes:
  # ChangeType, ResourceId), and a FAIL for anything it would delete or for a landing zone
  # resource it would change other than the writes deploy-spec section 4 lists.
  [CmdletBinding()]
  param(
    [AllowEmptyCollection()] [object[]] $Change = @(),
    [Parameter(Mandatory)] $LandingZone
  )
  $n = $LandingZone.Names
  $net = "/resourceGroups/$([regex]::Escape($n.ResourceGroups.Network))/providers/Microsoft\.Network"
  $allowed = @(
    "$net/virtualNetworks/$([regex]::Escape($n.Vnet))/virtualNetworkPeerings/$([regex]::Escape($n.PeeringToTier))$"
    "$net/privateDnsZones/[^/]+/virtualNetworkLinks/link-$([regex]::Escape($n.Base))-liquidware$"
  )
  foreach ($c in @($Change | Where-Object { $_ })) {
    $type = "$($c.ChangeType)"
    if ($type -in 'Ignore', 'NoChange') { continue }
    $id = "$($c.ResourceId)"
    $inTier = $id -match "/resourceGroups/$([regex]::Escape($n.TierGroup))(/|$)"
    $isAllowed = @($allowed | Where-Object { $id -match $_ }).Count -gt 0
    $short = ($id -split '/providers/')[-1]
    if ($type -eq 'Delete') {
      Get-LwCheckResult FAIL 'what-if' "$type $short" -Recommendation 'The tier never deletes on deploy; run Cleanup instead.' -Category 'Plan'
    }
    elseif (-not $inTier -and -not $isAllowed) {
      Get-LwCheckResult FAIL 'what-if' "$type $short (a landing zone resource outside deploy-spec section 4)" -Recommendation 'Stop: this would change the landing zone.' -Category 'Plan'
    }
    else {
      Get-LwCheckResult INFO 'what-if' "$type $short" -Category 'Plan'
    }
  }
}

$script:MediaComponents = @('ProfileUnityConsole', 'ProfileUnityClient', 'FlexAppPackagingConsole')
$script:LockFormat = 'avd-liquidware-media-lock/v1'

function Get-LwMediaBlobName {
  # Where an installer lives in the media container: <component>/<version>/<file> (deploy-spec
  # section 6.4). Strict, because the name ends up in a URL a host script builds.
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string] $Component,
    [Parameter(Mandatory)] [string] $Version,
    [Parameter(Mandatory)] [string] $FileName
  )
  if ($script:MediaComponents -cnotcontains $Component) { throw "Unknown media component '$Component'. Known: $($script:MediaComponents -join ', ')." }
  if ($Version -notmatch '^\d+(\.\d+){1,3}$') { throw "Version '$Version' must be numbers and dots, like 6.9.5." }
  if ($FileName -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$') { throw "File name '$FileName' may hold only letters, digits, dots, hyphens and underscores." }
  "$Component/$Version/$FileName"
}

function Get-LwMediaLock {
  # The lock file (media.lock.json) with one entry added or replaced: component, version, file,
  # SHA-256 and size. No URLs, no secrets. The lock belongs in the customer's private repo.
  #   Lock: the parsed existing lock, or $null for the first upload.
  [CmdletBinding()]
  param(
    $Lock = $null,
    [Parameter(Mandatory)] [string] $Component,
    [Parameter(Mandatory)] [string] $Version,
    [Parameter(Mandatory)] [string] $FileName,
    [Parameter(Mandatory)] [string] $Sha256,
    [Parameter(Mandatory)] [long] $Size
  )
  $blob = Get-LwMediaBlobName -Component $Component -Version $Version -FileName $FileName
  if ($Sha256 -notmatch '^[0-9a-fA-F]{64}$') { throw 'Sha256 must be 64 hex characters.' }
  if ($Lock -and $Lock.PSObject.Properties['format'] -and $Lock.format -ne $script:LockFormat) {
    throw "The existing lock is '$($Lock.format)', not $script:LockFormat."
  }
  $kept = @()
  if ($Lock -and $Lock.PSObject.Properties['entries']) {
    $kept = @($Lock.entries | Where-Object { $_ -and -not ($_.component -eq $Component -and $_.version -eq $Version) })
  }
  $entry = [pscustomobject][ordered]@{ component = $Component; version = $Version; file = $FileName; blob = $blob; sha256 = $Sha256.ToLower(); size = $Size }
  [pscustomobject][ordered]@{
    format  = $script:LockFormat
    entries = @(@($kept) + $entry | Sort-Object component, { [version] $_.version })
  }
}

function Get-LwSecretPath {
  # The ARM path that writes a tier Key Vault secret through the management plane, which works on
  # a private vault from Cloud Shell (DN-C1). Only the secrets the operator sets are allowed.
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string] $KeyVaultId,
    [Parameter(Mandatory)] [ValidateSet('lw-licstr')] [string] $Name
  )
  if ($KeyVaultId -notmatch '^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\.KeyVault/vaults/[A-Za-z0-9-]{3,24}$') {
    throw "Not a Key Vault resource ID: '$KeyVaultId'."
  }
  "$KeyVaultId/secrets/$($Name)?api-version=2023-07-01"
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

Export-ModuleMember -Function Get-LwCheckResult, Get-LwArgumentError, Get-LwName, Get-LwLandingZone, Get-LwLandingZoneCheck, Get-LwAddressCheck, Get-LwStratusphereArgument, Get-LwUsersGroup, Get-LwGeneratedPassword, Get-LwTierState, Get-LwTemplateParameter, Get-LwWhatIfSummary, Get-LwMediaBlobName, Get-LwMediaLock, Get-LwSecretPath, Get-LwPlanSummary
