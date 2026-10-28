# Pure functions behind Deploy-LiquidwareTier.ps1: names, landing zone discovery and checks.
# They take data already read from Azure and return objects, so they are tested offline
# (tests/LiquidwareTier.Tests.ps1). Design: docs/deploy-spec.md.
# Personal project, not for production use. Provided as is, without warranty of any kind. Not affiliated with the author's employer, with Liquidware or with Microsoft.

# The CIDR helpers already exist in the Stratusphere preflight; reuse them rather than copy them.
Import-Module (Join-Path $PSScriptRoot '../stratusphere/scripts/ops/StratusphereReadiness.psm1') -Force -Scope Local

$script:Environments = @('dev', 'test', 'prod')
$script:Components = @('ProfileUnity', 'FlexApp', 'Stratusphere', 'CommandCTRL')

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
    Clean                  = $clean
    Base                   = $base
    ResourceGroups         = [ordered]@{
      Network      = "rg-$base-network"
      Management   = "rg-$base-management"
      Storage      = "rg-$base-storage"
      ControlPlane = "rg-$base-avd"
      Hosts        = "rg-$base-hosts"
    }
    Vnet                   = "vnet-$base"
    HostPool               = "vdpool-$base"
    AppGroup               = "vdag-$base-desktop"
    LogAnalytics           = "log-$base"
    TierGroup              = "rg-$base-liquidware"
    TierVnet               = "vnet-$base-liquidware"
    PeeringToTier          = "peer-$base-to-liquidware"
    ConsoleVm              = "vm-$($clean)lwcon"
    PackagingVm            = "vm-$($clean)lwpkg"
    StratusphereNamePrefix = $ssux
    StratusphereGroup      = "rg-$ssux-stratusphere"
  }
}

function Get-LwLandingZone {
  # Finds the landing zone in what Azure returned. Never throws for a missing piece: each one is
  # listed in Missing, and Get-LwLandingZoneCheck turns the list into FAIL lines.
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
    Names                       = $n
    ConnectivityMode            = $mode
    Location                    = $(if ($Vnet) { $Vnet.Location } elseif ($hostPool) { $hostPool.Location } else { $null })
    VnetId                      = $(if ($Vnet) { $Vnet.Id } else { $null })
    VnetAddressPrefixes         = @($(if ($Vnet) { $Vnet.AddressPrefixes } else { @() }))
    SessionHostSubnetPrefix     = $(if ($hostSubnet) { $hostSubnet.AddressPrefix } else { $null })
    PrivateEndpointSubnetPrefix = $(if ($endpointSubnet) { $endpointSubnet.AddressPrefix } else { $null })
    Peerings                    = @($(if ($Vnet) { @($Vnet.Peerings | Where-Object { $_ }) } else { @() }))
    ProfilesAccountId           = $(if ($profiles) { $profiles.ResourceId } else { $null })
    KeyVaultId                  = $(if ($keyVault) { $keyVault.ResourceId } else { $null })
    LogAnalyticsId              = $(if ($law) { $law.ResourceId } else { $null })
    HostPoolId                  = $(if ($hostPool) { $hostPool.ResourceId } else { $null })
    AppGroupId                  = $(if ($appGroup) { $appGroup.ResourceId } else { $null })
    FileDnsZoneId               = $(if ($fileZone) { $fileZone.ResourceId } else { $null })
    VaultDnsZoneId              = $(if ($vaultZone) { $vaultZone.ResourceId } else { $null })
    Missing                     = $missing.ToArray()
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
  # account (decision 0005 in avd-landing-zone).
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
  # (which writes it to the tier Key Vault).
  [CmdletBinding()]
  [OutputType([securestring])]
  param([ValidateRange(16, 123)] [int] $Length = 24)
  $classes = @('ABCDEFGHJKLMNPQRSTUVWXYZ', 'abcdefghijkmnopqrstuvwxyz', '23456789', '!#%*-_=+?')
  $all = -join $classes
  $rng = [System.Security.Cryptography.RandomNumberGenerator]
  $chars = [System.Collections.Generic.List[char]]::new()
  foreach ($c in $classes) { $chars.Add($c[$rng::GetInt32($c.Length)]) }
  while ($chars.Count -lt $Length) { $chars.Add($all[$rng::GetInt32($all.Length)]) }
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
  # What the tier already has that the template must not redo: the console VM and the lw-licstr secret.
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
    [switch] $Bastion,
    [switch] $Portability,
    [switch] $ApplicationRestrictions,
    [switch] $Packaging,
    [securestring] $PackagingAdminPassword = $null,
    [switch] $Backup
  )
  $lz = $LandingZone
  if (-not $TierState.ConsoleExists -and -not $ConsoleAdminPassword) {
    throw 'A new console needs -ConsoleAdminPassword (Get-LwGeneratedPassword).'
  }
  if ($Packaging -and -not $PackagingAdminPassword) {
    throw 'A packaging VM needs -PackagingAdminPassword (Get-LwGeneratedPassword).'
  }
  if ($AutoShutdownTime -notmatch '^([01]\d|2[0-3])[0-5]\d$') { throw "AutoShutdownTime '$AutoShutdownTime' must be HHmm." }
  $profilesName = $(if ($lz.ProfilesAccountId) { ($lz.ProfilesAccountId -split '/')[-1] } else { '' })
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
    enablePortability                = [bool] $Portability
    profilesStorageAccountName       = $profilesName
    profilesResourceGroupName        = "$($lz.Names.ResourceGroups.Storage)"
    enableApplicationRestrictions    = [bool] $ApplicationRestrictions
    logAnalyticsWorkspaceId          = "$($lz.LogAnalyticsId)"
    deployPackagingVm                = [bool] $Packaging
    packagingAdminPassword           = $(if ($Packaging) { $PackagingAdminPassword } else { $null })
    enableBackup                     = [bool] $Backup
  }
}

function Get-LwWhatIfSummary {
  # One line per change what-if reports, and a FAIL for anything it would delete or for a landing
  # zone resource it would change other than the writes deploy-spec section 4 lists.
  [CmdletBinding()]
  param(
    [AllowEmptyCollection()] [object[]] $Change = @(),
    [Parameter(Mandatory)] $LandingZone
  )
  $n = $LandingZone.Names
  $net = "/resourceGroups/$([regex]::Escape($n.ResourceGroups.Network))/providers/Microsoft\.Network"
  $stg = "/resourceGroups/$([regex]::Escape($n.ResourceGroups.Storage))/providers/Microsoft\.Storage"
  $allowed = @(
    "$net/virtualNetworks/$([regex]::Escape($n.Vnet))/virtualNetworkPeerings/$([regex]::Escape($n.PeeringToTier))$"
    "$net/privateDnsZones/[^/]+/virtualNetworkLinks/link-$([regex]::Escape($n.Base))-liquidware$"
    "$stg/storageAccounts/[^/]+/fileServices/default/shares/portability$"
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

$script:MediaComponents = @('ProfileUnityConsole', 'ProfileUnityClient', 'FlexAppPackagingConsole', 'CommandCtrlAgent')
$script:LockFormat = 'avd-liquidware-media-lock/v1'

function Get-LwMediaBlobName {
  # Where an installer lives in the media container: <component>/<version>/<file> (deploy-spec section 6.4).
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
  # The lock file (media.lock.json) with one entry added or replaced.
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
  # The ARM path that writes a tier Key Vault secret through the management plane (DN-C1).
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

function Get-LwMediaLockEntry {
  # The newest lock entry for one component, or $null.
  [CmdletBinding()]
  param(
    $Lock = $null,
    [Parameter(Mandatory)] [string] $Component
  )
  if (-not $Lock -or -not $Lock.PSObject.Properties['entries']) { return $null }
  @($Lock.entries | Where-Object { $_ -and $_.component -eq $Component } | Sort-Object { [version] $_.version }) | Select-Object -Last 1
}

function Get-LwDeletedVault {
  # The tier's Key Vault, soft-deleted by an earlier Cleanup (lesson 0022, DN-M3).
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] $Names,
    [AllowEmptyCollection()] [object[]] $Removed = @()
  )
  $environment = ($Names.Base -split '-')[-1]
  $prefix = "kv$($Names.Clean)$($environment)lw"
  $pattern = "^$([regex]::Escape($prefix.Substring(0, [Math]::Min($prefix.Length, 24))))[a-z0-9]{0,5}$"
  $hits = @($Removed | Where-Object { $_ -and $_.VaultName -match $pattern -and $_.VaultName.Length -le 24 })
  if ($hits.Count -eq 0) { return [pscustomobject]@{ Vault = $null; Result = @() } }
  if ($hits.Count -gt 1) {
    return [pscustomobject]@{ Vault = $null; Result = @(Get-LwCheckResult FAIL 'deleted-key-vault' "$($hits.Count) soft-deleted vaults match $prefix*: $(@($hits.VaultName) -join ', ')." -Recommendation 'Recover the right one with Undo-AzKeyVaultRemoval, then run again.' -Category ProfileUnity) }
  }
  $v = $hits[0]
  [pscustomobject]@{
    Vault  = $v
    Result = @(Get-LwCheckResult INFO 'deleted-key-vault' "$($v.VaultName) is soft-deleted (purge protection, until $($v.ScheduledPurgeDate)): Deploy recovers it, with its secrets." -Category ProfileUnity)
  }
}

function Get-LwCleanupPlan {
  # What Cleanup removes, in order (deploy-spec section 11).
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] $Names,
    [bool] $TierGroupExists = $false,
    [AllowEmptyCollection()] [object[]] $Peering = @(),
    [AllowEmptyCollection()] [object[]] $DnsLink = @()
  )
  $tierVnet = "/resourceGroups/$($Names.TierGroup)/providers/Microsoft.Network/virtualNetworks/$($Names.TierVnet)"
  $steps = [System.Collections.Generic.List[object]]::new()
  foreach ($p in @($Peering | Where-Object { $_ -and $_.Name -eq $Names.PeeringToTier -and "$($_.RemoteVnetId)" -like "*$tierVnet" })) {
    $steps.Add([pscustomobject]@{ Kind = 'Peering'; Name = $p.Name; Parent = $Names.Vnet; ResourceGroup = $Names.ResourceGroups.Network; ResourceId = '' })
  }
  foreach ($l in @($DnsLink | Where-Object { $_ -and $_.Name -eq "link-$($Names.Base)-liquidware" -and "$($_.VirtualNetworkId)" -like "*$tierVnet" })) {
    $steps.Add([pscustomobject]@{ Kind = 'DnsLink'; Name = $l.Name; Parent = $l.ZoneName; ResourceGroup = $Names.ResourceGroups.Network; ResourceId = $l.ResourceId })
  }
  if ($TierGroupExists) {
    $steps.Add([pscustomobject]@{ Kind = 'ResourceGroup'; Name = $Names.TierGroup; Parent = ''; ResourceGroup = $Names.TierGroup; ResourceId = '' })
  }
  $steps.ToArray()
}

function Get-LwLastCopyCheck {
  # Never delete the last copy (avd-second-brain decision 0016).
  [CmdletBinding()]
  param(
    [AllowEmptyCollection()] [object[]] $Steps = @(),
    [switch] $DiscardLastCopy
  )
  $group = @($Steps | Where-Object { $_ -and $_.Kind -eq 'ResourceGroup' })
  if ($group.Count -eq 0) { return }
  $what = "$($group[0].Name) holds the only copy of the live ProfileUnity configuration, the FlexApp packages and the console (and its backup outside dev)"
  if ($DiscardLastCopy) { return Get-LwCheckResult WARN 'last-copy' "$what. Removing it anyway: -DiscardLastCopy was given." -Category Cleanup }
  Get-LwCheckResult FAIL 'last-copy' "$what. Nothing was removed." -Recommendation 'Copy what you need to keep somewhere outside this resource group and check the copy, then run Cleanup again with -DiscardLastCopy.' -Category Cleanup
}

function Get-LwTeardownCheck {
  # Teardown evidence: after Cleanup, nothing in Get-LwCleanupPlan is left (deploy-spec section 13).
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] $Names,
    [bool] $TierGroupExists = $false,
    [AllowEmptyCollection()] [object[]] $Peering = @(),
    [AllowEmptyCollection()] [object[]] $DnsLink = @()
  )
  $left = @(Get-LwCleanupPlan -Names $Names -TierGroupExists $TierGroupExists -Peering $Peering -DnsLink $DnsLink)
  foreach ($s in $left) {
    Get-LwCheckResult FAIL 'teardown' "Still there: $($s.Kind) $($s.Name)$(if ($s.Parent) { " on $($s.Parent)" })" -Recommendation 'Run Cleanup again; if it stays, remove it in the portal and record why.' -Category Cleanup
  }
  if ($left.Count -eq 0) {
    Get-LwCheckResult PASS 'teardown' "$($Names.TierGroup) not found, no tier peering on $($Names.Vnet), no tier DNS links." -Category Cleanup
  }
}

function Get-LwRunCommandResult {
  # The one result line a host script prints (LW-RESULT status=... path=... detail=...), as a check.
  [CmdletBinding()]
  param(
    [AllowEmptyString()] [string] $Output = '',
    [Parameter(Mandatory)] [string] $Check,
    [string[]] $Pass = @('verified', 'installed', 'uninstalled', 'staged')
  )
  $line = @(($Output -split "`r?`n") | Where-Object { $_ -match '^LW-RESULT ' }) | Select-Object -Last 1
  if (-not $line) {
    return Get-LwCheckResult FAIL $Check "No LW-RESULT line. Output: $(($Output -replace '\s+', ' ').Trim())" -Recommendation 'Read the Run Command instance view; the script may not have started.' -Category ProfileUnity
  }
  $status = $(if ($line -match 'status=(\S+)') { $Matches[1] } else { '' })
  $detail = $(if ($line -match 'detail=(.*)$') { $Matches[1] } else { '' })
  if ($Pass -contains $status) { return Get-LwCheckResult PASS $Check "$status. $detail" -Category ProfileUnity }
  Get-LwCheckResult FAIL $Check "$status. $detail" -Recommendation 'Fix what the detail names, then Deploy again.' -Category ProfileUnity
}

function Get-LwHostPlan {
  # Per-host execution plan for Sync-LiquidwareHosts.ps1 (deploy-spec sections 6.2 and 6.3,
  # lesson 0026, DN-H1, DN-H2, D-H5).
  #   SessionHost: Name, AllowNewSession (bool), Sessions (int), ConfiguredVersion (string)
  #   Vm:          Name, PowerState ('VM running', 'VM deallocated', etc.), Tags (hashtable/psobject)
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $SessionHost,
    [AllowEmptyCollection()] [object[]] $Vm = @(),
    [ValidateSet('ProfileUnity', 'Stratusphere', 'CommandCTRL')] [string] $Component = 'ProfileUnity',
    [ValidateSet('Configure', 'Check', 'Cleanup')] [string] $Action = 'Configure',
    [bool] $BudgetLockActive = $false,
    [switch] $HoldUnconfigured
  )
  foreach ($h in @($SessionHost | Where-Object { $_ })) {
    $rawName = "$($h.Name)"
    $vmShort = (($rawName -split '/')[-1] -split '\.')[0]
    $vmObj = @($Vm | Where-Object { $_ -and (($_.Name -split '\.')[0] -eq $vmShort -or $_.Name -eq $rawName) }) | Select-Object -First 1
    $power = $(if ($vmObj -and $vmObj.PSObject.Properties['PowerState'] -and $vmObj.PowerState) { "$($vmObj.PowerState)" } else { 'VM deallocated' })
    $tags = @{}
    if ($vmObj -and $vmObj.PSObject.Properties['Tags'] -and $vmObj.Tags) {
      if ($vmObj.Tags -is [System.Collections.IDictionary]) {
        foreach ($k in $vmObj.Tags.Keys) { $tags["$k"] = "$($vmObj.Tags[$k])" }
      }
      else {
        foreach ($p in $vmObj.Tags.PSObject.Properties) { $tags[$p.Name] = "$($p.Value)" }
      }
    }
    $tierDrained = $tags.ContainsKey('liquidware-drained')
    $allowNew = $(if ($h.PSObject.Properties['AllowNewSession']) { [bool]$h.AllowNewSession } else { $true })
    $sessions = $(if ($h.PSObject.Properties['Sessions']) { [int]$h.Sessions } else { 0 })
    $version = $(if ($h.PSObject.Properties['ConfiguredVersion']) { "$($h.ConfiguredVersion)" } else { '' })
    $isConfigured = [bool]$version

    if ($BudgetLockActive) {
      [pscustomobject]@{
        HostName           = $rawName
        VmName             = $vmShort
        Component          = $Component
        Action             = 'SkipBudgetLock'
        OriginalPowerState = $power
        NeedsStart         = $false
        DrainAction        = 'Preserve'
        UndrainAfter       = $false
        RestoreStopAfter   = $false
        HoldTag            = ''
        Sessions           = $sessions
        ConfiguredVersion  = $version
      }
      continue
    }

    $needsStart = ($power -ne 'VM running')
    $drainAction = 'None'
    $undrainAfter = $false
    if ($Action -in 'Configure', 'Cleanup') {
      if ($allowNew) {
        $drainAction = 'DrainAndTag'
        $undrainAfter = $true
      }
      elseif ($tierDrained) {
        $drainAction = 'KeepTierDrain'
        $undrainAfter = $true
      }
      else {
        # Someone else (rotation, admin or scaling) drained this host; preserve their drain (DN-H1).
        $drainAction = 'Preserve'
        $undrainAfter = $false
      }
    }
    $holdTag = $(if ($HoldUnconfigured -and -not $isConfigured -and $Action -ne 'Cleanup') { 'liquidware-hold' } else { '' })
    $planAction = switch ($Action) {
      'Check' { if ($isConfigured) { 'Healthy' } else { 'Unconfigured' } }
      'Cleanup' { 'Uninstall' }
      'Configure' { if ($isConfigured) { 'NoOp' } else { 'Install' } }
    }
    [pscustomobject]@{
      HostName           = $rawName
      VmName             = $vmShort
      Component          = $Component
      Action             = $planAction
      OriginalPowerState = $power
      NeedsStart         = $needsStart
      DrainAction        = $drainAction
      UndrainAfter       = $undrainAfter
      RestoreStopAfter   = $needsStart
      HoldTag            = $holdTag
      Sessions           = $sessions
      ConfiguredVersion  = $version
    }
  }
}

function Get-LwConfigPromotePlan {
  # Validates a staged configuration export before promoting it to lwconfig (deploy-spec section 7,
  # D-C3, DN-C4, DN-M6, tier H1).
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string] $ConfigName,
    [Parameter(Mandatory)] [string] $Timestamp,
    [Parameter(Mandatory)] [string] $StagedIniSha256,
    $PlainTextExport = $null,
    [ValidateSet('QA', 'All')] [string] $Ring = 'QA',
    [string] $LiveIniSha256 = '',
    [switch] $Force
  )
  $results = [System.Collections.Generic.List[object]]::new()
  $targetFolder = $(if ($Ring -eq 'QA') { "$ConfigName-qa" } else { $ConfigName })
  if ($StagedIniSha256 -notmatch '^[0-9a-fA-F]{64}$') {
    $results.Add((Get-LwCheckResult FAIL 'promote-hash' "StagedIniSha256 '$StagedIniSha256' is not 64 hex characters." -Recommendation 'Re-stage from the console.' -Category Promote))
  }
  if (-not $PlainTextExport) {
    $results.Add((Get-LwCheckResult FAIL 'promote-export' 'No plain-text export (.json) accompanies the staged INI (DN-C4).' -Recommendation 'Export the configuration in plain text on the console and stage again.' -Category Promote))
  }
  else {
    $expTs = $(if ($PlainTextExport.PSObject.Properties['timestamp']) { "$($PlainTextExport.timestamp)" } else { '' })
    $expSha = $(if ($PlainTextExport.PSObject.Properties['iniSha256']) { "$($PlainTextExport.iniSha256)" } else { '' })
    if ($expTs -ne $Timestamp -or $expSha.ToLowerInvariant() -ne $StagedIniSha256.ToLowerInvariant()) {
      $results.Add((Get-LwCheckResult FAIL 'promote-export' "Plain-text export ($expTs / $expSha) does not match the staged INI ($Timestamp / $StagedIniSha256)." -Recommendation 'Re-stage both from the same console deploy.' -Category Promote))
    }
    $rules = @($(if ($PlainTextExport.PSObject.Properties['rules']) { $PlainTextExport.rules } else { @() }))
    $paths = @($(if ($PlainTextExport.PSObject.Properties['portabilityPaths']) { $PlainTextExport.portabilityPaths } else { @() }))
    if ($rules.Count -eq 0 -and $paths.Count -eq 0) {
      $results.Add((Get-LwCheckResult FAIL 'promote-empty' 'The staged configuration has no rules or portability paths.' -Recommendation 'Check the configuration in the console before promoting.' -Category Promote))
    }
    $forbidden = @('OneDrive', 'Teams', 'Outlook', 'Packages', 'OST', 'ODFC')
    foreach ($p in $paths) {
      $hit = @($forbidden | Where-Object { "$p" -match "(?i)(^|[\\/])$([regex]::Escape($_))([\\/]|$)" })
      if ($hit.Count -gt 0) {
        $results.Add((Get-LwCheckResult FAIL 'promote-fslogix-overlap' "Portability path '$p' overlaps FSLogix container path ($($hit -join ', ')) (tier H1)." -Recommendation 'Exclude OneDrive, Teams, Outlook and MSIX Packages from Portability; FSLogix owns them.' -Category Promote))
      }
    }
  }
  if ($LiveIniSha256 -and $LiveIniSha256.ToLowerInvariant() -eq $StagedIniSha256.ToLowerInvariant() -and -not $Force) {
    $results.Add((Get-LwCheckResult FAIL 'promote-unchanged' "lwconfig/$targetFolder already runs INI SHA-256 $StagedIniSha256." -Recommendation 'Pass -Force to re-promote the same hash.' -Category Promote))
  }
  if (@($results | Where-Object Status -eq 'FAIL').Count -eq 0) {
    $results.Add((Get-LwCheckResult PASS 'promote-plan' "Ready to promote $ConfigName ($Timestamp) to lwconfig/$targetFolder (client.net.xml renamed before $ConfigName.ini)." -Category Promote))
  }
  [pscustomobject]@{
    TargetFolder = $targetFolder
    RenameOrder  = @('client.net.xml', "$ConfigName.ini")
    Ready        = (@($results | Where-Object Status -eq 'FAIL').Count -eq 0)
    Result       = $results.ToArray()
  }
}

function Get-LwAssignmentConflict {
  # Double-assignment check (deploy-spec section 8.3, tier H5): an application assigned in more
  # than one of AVD app attach, ProfileUnity FlexApp rules, or native MSIX is a FAIL.
  [CmdletBinding()]
  param(
    [AllowEmptyCollection()] [string[]] $AvdAppAttach = @(),
    [AllowEmptyCollection()] [string[]] $ProfileUnityFlexApp = @(),
    [AllowEmptyCollection()] [string[]] $NativeMsix = @()
  )
  $map = @{}
  foreach ($source in @(
      @{ Name = 'AvdAppAttach'; Items = $AvdAppAttach }
      @{ Name = 'ProfileUnityFlexApp'; Items = $ProfileUnityFlexApp }
      @{ Name = 'NativeMsix'; Items = $NativeMsix }
    )) {
    foreach ($app in @($source.Items | Where-Object { $_ })) {
      $key = $app.Trim().ToLowerInvariant()
      if (-not $map.ContainsKey($key)) { $map[$key] = [System.Collections.Generic.List[string]]::new() }
      if (-not $map[$key].Contains($source.Name)) { $map[$key].Add($source.Name) }
    }
  }
  $conflicts = @()
  foreach ($k in ($map.Keys | Sort-Object)) {
    if ($map[$k].Count -gt 1) {
      $conflicts += Get-LwCheckResult FAIL 'assignment-conflict' "Application '$k' is assigned in multiple systems: $($map[$k] -join ', ') (tier H5)." -Recommendation 'Keep each application in exactly one assignment system (Set-FlexAppAssignment.ps1).' -Category FlexApp
    }
  }
  if ($conflicts.Count -eq 0) {
    return @(Get-LwCheckResult PASS 'assignment-conflict' "No duplicate application assignments across AvdAppAttach, ProfileUnityFlexApp and NativeMsix." -Category FlexApp)
  }
  $conflicts
}

function Get-LwCostEstimate {
  # Cost estimate lines from retail meter records (deploy-spec section 13, decision 0010) plus the
  # mandatory warning that the landing zone budget lock does not cover this tier.
  [CmdletBinding()]
  param(
    [AllowEmptyCollection()] [object[]] $Meter = @(),
    [string[]] $Component = @('ProfileUnity'),
    [switch] $Portability,
    [switch] $Packaging,
    [switch] $Backup
  )
  $items = [System.Collections.Generic.List[object]]::new()
  if (@($Component | Where-Object { $_ -in 'ProfileUnity', 'FlexApp' }).Count -gt 0) {
    $items.Add(@{ Name = 'Console VM (Standard_D2as_v5)'; Sku = 'Standard_D2as_v5' })
    $items.Add(@{ Name = 'NAT Gateway'; Sku = 'Standard NAT Gateway' })
    $items.Add(@{ Name = 'Private endpoints (3x)'; Sku = 'Private Endpoint' })
    $items.Add(@{ Name = 'Tier storage (config, packages, media)'; Sku = 'Standard_LRS' })
  }
  if ($Portability) { $items.Add(@{ Name = 'Portability share (100 GiB Premium Files)'; Sku = 'Premium_LRS' }) }
  if ($Packaging) { $items.Add(@{ Name = 'Packaging VM (Standard_D2as_v5)'; Sku = 'Standard_D2as_v5' }) }
  if ($Backup) { $items.Add(@{ Name = 'Recovery Services backup vault'; Sku = 'Azure Backup' }) }
  if ($Component -contains 'Stratusphere') { $items.Add(@{ Name = 'Stratusphere Hub (Standard_D4s_v5 + Marketplace plan)'; Sku = 'Standard_D4s_v5' }) }

  $lines = foreach ($item in $items) {
    $hit = @($Meter | Where-Object { $_ -and $_.Sku -eq $item.Sku })
    $priceText = $(if ($hit.Count -eq 1) { "$($hit[0].UnitPrice) $($hit[0].CurrencyCode) per $($hit[0].UnitOfMeasure)" } elseif ($hit.Count -gt 1) { "multiple meters ($($hit.Count)) matched $($item.Sku)" } else { 'unpriced (offline; query prices.azure.com before a live run)' })
    [pscustomobject]@{
      Line   = $item.Name
      Sku    = $item.Sku
      Priced = ($hit.Count -eq 1)
      Detail = "$($item.Name): $priceText"
    }
  }
  $warning = Get-LwCheckResult WARN 'budget' "The landing zone's budget Lock doesn't stop this tier: the console, NAT Gateway, private endpoints and storage keep billing." -Recommendation 'In dev, run Cleanup the same day (D-H6).' -Category Cost
  [pscustomobject]@{
    Lines   = @($lines)
    Warning = $warning
  }
}

function Get-LwStratusphereWindowCheck {
  # Checks the stratusphere-window-end tag on the Stratusphere resource group (deploy-spec section 9).
  [CmdletBinding()]
  param(
    [string] $WindowEnd = '',
    [datetime] $Now = [datetime]::UtcNow,
    [int] $DefaultDays = 28
  )
  if (-not $WindowEnd) {
    $proposed = $Now.ToUniversalTime().AddDays($DefaultDays).ToString('yyyy-MM-dd')
    return Get-LwCheckResult INFO 'stratusphere-window' "No stratusphere-window-end tag yet; Deploy sets it to $proposed ($DefaultDays days)." -Category Stratusphere
  }
  $parsed = [datetime]::MinValue
  if (-not [datetime]::TryParse($WindowEnd, [ref]$parsed)) {
    return Get-LwCheckResult FAIL 'stratusphere-window' "Tag stratusphere-window-end '$WindowEnd' is not a valid ISO date." -Recommendation 'Set stratusphere-window-end to yyyy-MM-dd.' -Category Stratusphere
  }
  $daysLeft = [math]::Ceiling(($parsed.ToUniversalTime() - $Now.ToUniversalTime()).TotalDays)
  if ($daysLeft -lt 0) {
    return Get-LwCheckResult FAIL 'stratusphere-window' "Stratusphere assessment window ended on $WindowEnd ($([math]::Abs($daysLeft)) day(s) ago)." -Recommendation 'Export assessment data and run Deploy-LiquidwareTier.ps1 -Component Stratusphere -Action Cleanup -DiscardLastCopy.' -Category Stratusphere
  }
  if ($daysLeft -le 7) {
    return Get-LwCheckResult WARN 'stratusphere-window' "Stratusphere assessment window ends on $WindowEnd ($daysLeft day(s) left)." -Recommendation 'Export assessment data before the window ends, then run Cleanup.' -Category Stratusphere
  }
  Get-LwCheckResult PASS 'stratusphere-window' "Stratusphere assessment window active until $WindowEnd ($daysLeft day(s) left)." -Category Stratusphere
}

function Test-LwInstrumentReport {
  # Validates a Stratusphere report object against contracts/schemas/stratusphere-instrument.schema.json (C16).
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] $Report,
    [string] $SchemaPath = ''
  )
  if (-not $SchemaPath) { $SchemaPath = Join-Path $PSScriptRoot '../contracts/schemas/stratusphere-instrument.schema.json' }
  $schema = Get-Content -LiteralPath $SchemaPath -Raw | ConvertFrom-Json
  $errors = [System.Collections.Generic.List[string]]::new()
  foreach ($req in @($schema.required)) {
    if (-not $Report.PSObject.Properties[$req] -or -not $Report.$req) {
      $errors.Add("Missing required property '$req'.")
    }
  }
  if ($Report.PSObject.Properties['schemaVersion'] -and $Report.schemaVersion -ne $schema.properties.schemaVersion.const) {
    $errors.Add("schemaVersion '$($Report.schemaVersion)' must be '$($schema.properties.schemaVersion.const)'.")
  }
  $allowedKinds = @($schema.properties.reportKind.enum)
  if ($Report.PSObject.Properties['reportKind'] -and $allowedKinds -notcontains "$($Report.reportKind)") {
    $errors.Add("reportKind '$($Report.reportKind)' must be one of: $($allowedKinds -join ', ').")
  }
  [pscustomobject]@{
    IsValid = ($errors.Count -eq 0)
    Errors  = $errors.ToArray()
  }
}

function Get-LwPlanSummary {
  # Whether each component's action is applicable (deploy-spec section 11), and what Plan and Deploy
  # must say about cost.
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string[]] $Component,
    [Parameter(Mandatory)] [string] $Action
  )
  $built = @{
    ProfileUnity = @('Plan', 'Check', 'Deploy', 'Configure', 'Promote', 'Fix', 'Cleanup')
    FlexApp      = @('Plan', 'Check', 'Deploy', 'Promote', 'Fix', 'Cleanup')
    Stratusphere = @('Plan', 'Check', 'Deploy', 'Configure', 'Fix', 'Cleanup')
    CommandCTRL  = @('Plan', 'Check', 'Configure', 'Cleanup')
  }
  foreach ($c in $Component) {
    if (@($built[$c]) -contains $Action) { continue }
    Get-LwCheckResult FAIL "$($c.ToLower())-$($Action.ToLower())" "$Action for $c is not applicable or not built (deploy-spec section 11)." -Category $c
  }
  if ($Action -in 'Plan', 'Deploy' -and @($Component | Where-Object { $_ -in 'ProfileUnity', 'FlexApp' }).Count -gt 0) {
    Get-LwCheckResult WARN 'budget' "The landing zone's budget Lock doesn't stop this tier: the console, NAT Gateway, private endpoints and storage keep billing." -Recommendation 'In dev, run Cleanup the same day (D-H6).' -Category Cost
  }
}

Export-ModuleMember -Function Get-LwCheckResult, Get-LwArgumentError, Get-LwName, Get-LwLandingZone, Get-LwLandingZoneCheck, Get-LwAddressCheck, Get-LwStratusphereArgument, Get-LwUsersGroup, Get-LwGeneratedPassword, Get-LwTierState, Get-LwTemplateParameter, Get-LwWhatIfSummary, Get-LwMediaBlobName, Get-LwMediaLock, Get-LwSecretPath, Get-LwMediaLockEntry, Get-LwDeletedVault, Get-LwCleanupPlan, Get-LwLastCopyCheck, Get-LwTeardownCheck, Get-LwRunCommandResult, Get-LwHostPlan, Get-LwConfigPromotePlan, Get-LwAssignmentConflict, Get-LwCostEstimate, Get-LwStratusphereWindowCheck, Test-LwInstrumentReport, Get-LwPlanSummary
