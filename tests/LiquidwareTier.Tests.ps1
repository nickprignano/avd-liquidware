#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# Offline tests for scripts/LiquidwareTier.psm1. Fixtures are shaped like the Az cmdlets' output
# and, like ARM, omit empty properties (a VNet without peerings has no Peerings at all).

BeforeAll {
  $script:root = Split-Path $PSScriptRoot -Parent
  Import-Module (Join-Path $script:root 'scripts/LiquidwareTier.psm1') -Force
  function Get-Fixture([string] $Name) { Get-Content (Join-Path $PSScriptRoot "fixtures/$Name.json") -Raw | ConvertFrom-Json }
  function Get-DevLandingZone {
    param([scriptblock] $Change = {})
    $f = Get-Fixture 'landing-zone-dev'
    & $Change $f
    Get-LwLandingZone -NamePrefix avdlz -Environment dev -ResourceGroup $f.ResourceGroup -Resource $f.Resource -Vnet $f.Vnet
  }
}

Describe 'Get-LwArgumentError' {
  It 'accepts the dev landing zone' {
    @(Get-LwArgumentError -NamePrefix avdlz -Environment dev -Component ProfileUnity -TierAddressPrefix 10.61.0.0/24).Count | Should -Be 0
  }
  It 'rejects an unknown environment, component and prefix' {
    $e = @(Get-LwArgumentError -NamePrefix 'AVD_LZ' -Environment staging -Component Nerdio)
    $e.Count | Should -Be 3
    ($e -join "`n") | Should -Match 'Unknown component'
  }
  It 'needs at least one component' {
    @(Get-LwArgumentError -NamePrefix avdlz -Environment dev -Component @()) | Should -Match 'at least one'
  }
  It 'rejects a tier prefix that is not a CIDR or is smaller than /24' {
    @(Get-LwArgumentError -NamePrefix avdlz -Environment dev -Component FlexApp -TierAddressPrefix 'ten').Count | Should -Be 1
    @(Get-LwArgumentError -NamePrefix avdlz -Environment dev -Component FlexApp -TierAddressPrefix '10.61.0.0/26') | Should -Match '/24'
  }
}

Describe 'Get-LwName' {
  It 'follows the landing zone naming convention' {
    $n = Get-LwName -NamePrefix avd-lz -Environment dev
    $n.Base | Should -Be 'avdlz-dev'
    $n.ResourceGroups.Storage | Should -Be 'rg-avdlz-dev-storage'
    $n.HostPool | Should -Be 'vdpool-avdlz-dev'
    $n.TierGroup | Should -Be 'rg-avdlz-dev-liquidware'
  }
  It 'gives Stratusphere a prefix its own 2-8 character rule accepts' {
    (Get-LwName -NamePrefix avdlz -Environment prod).StratusphereNamePrefix | Should -Be 'avdlzp'
    (Get-LwName -NamePrefix abcdefgh -Environment test).StratusphereNamePrefix | Should -Be 'abcdefgt'
    (Get-LwName -NamePrefix abcdefgh -Environment test).StratusphereNamePrefix | Should -Match '^[a-z0-9]{2,8}$'
  }
}

Describe 'Get-LwLandingZone' {
  It 'finds every piece of a Standalone dev landing zone' {
    $lz = Get-DevLandingZone
    @($lz.Missing).Count | Should -Be 0
    $lz.ConnectivityMode | Should -Be 'Standalone'
    $lz.Location | Should -Be 'northcentralus'
    $lz.SessionHostSubnetPrefix | Should -Be '10.100.0.0/23'
    $lz.PrivateEndpointSubnetPrefix | Should -Be '10.100.2.0/27'
    $lz.ProfilesAccountId | Should -Match 'stavdlzdevabc123$'
    $lz.FileDnsZoneId | Should -Match 'privatelink\.file\.'
    $lz.VaultDnsZoneId | Should -Match 'privatelink\.vaultcore\.'
  }
  It 'treats a VNet without peerings (ARM omits the property) as having none' {
    @((Get-DevLandingZone).Peerings).Count | Should -Be 0
  }
  It 'lists each missing piece instead of throwing' {
    $lz = Get-DevLandingZone -Change {
      param($f)
      $f.ResourceGroup = @($f.ResourceGroup | Where-Object { $_ -ne 'rg-avdlz-dev-hosts' })
      $f.Resource = @($f.Resource | Where-Object { $_.ResourceType -ne 'Microsoft.Storage/storageAccounts' })
    }
    $lz.Missing | Should -Contain 'resource group rg-avdlz-dev-hosts'
    ($lz.Missing -join "`n") | Should -Match 'profiles storage account'
  }
  It 'ignores a StorageV2 account: the profiles account is the FileStorage one' {
    $lz = Get-DevLandingZone -Change {
      param($f)
      foreach ($r in $f.Resource) { if ($r.ResourceType -eq 'Microsoft.Storage/storageAccounts') { $r.Kind = 'StorageV2' } }
    }
    $lz.ProfilesAccountId | Should -BeNullOrEmpty
  }
  It 'reports a missing VNet and a missing host subnet' {
    $f = Get-Fixture 'landing-zone-dev'
    (Get-LwLandingZone -NamePrefix avdlz -Environment dev -ResourceGroup $f.ResourceGroup -Resource $f.Resource -Vnet $null).Missing | Should -Contain 'virtual network vnet-avdlz-dev'
    $f.Vnet.Subnets = @($f.Vnet.Subnets | Where-Object Name -ne 'snet-session-hosts')
    (Get-LwLandingZone -NamePrefix avdlz -Environment dev -ResourceGroup $f.ResourceGroup -Resource $f.Resource -Vnet $f.Vnet).Missing | Should -Contain 'subnet snet-session-hosts in vnet-avdlz-dev'
  }
  It 'calls a landing zone without local privatelink zones HubPeered' {
    $lz = Get-DevLandingZone -Change { param($f) $f.Resource = @($f.Resource | Where-Object ResourceType -ne 'Microsoft.Network/privateDnsZones') }
    $lz.ConnectivityMode | Should -Be 'HubPeered'
  }
}

Describe 'Get-LwLandingZoneCheck' {
  It 'passes a complete Standalone landing zone' {
    $r = @(Get-LwLandingZoneCheck -LandingZone (Get-DevLandingZone))
    $r.Count | Should -Be 1
    $r[0].Status | Should -Be 'PASS'
  }
  It 'fails once per missing piece, with the landing zone deploy as the fix' {
    $lz = Get-DevLandingZone -Change { param($f) $f.Resource = @($f.Resource | Where-Object ResourceType -notlike 'Microsoft.DesktopVirtualization/*') }
    $fails = @(Get-LwLandingZoneCheck -LandingZone $lz | Where-Object Status -eq 'FAIL')
    $fails.Count | Should -Be 2
    $fails[0].Recommendation | Should -Match 'deploy.sh'
  }
  It 'fails HubPeered until it is built' {
    $lz = Get-DevLandingZone -Change { param($f) $f.Resource = @($f.Resource | Where-Object ResourceType -ne 'Microsoft.Network/privateDnsZones') }
    (Get-LwLandingZoneCheck -LandingZone $lz | Where-Object Check -eq 'connectivity-mode').Status | Should -Be 'FAIL'
  }
}

Describe 'Get-LwAddressCheck' {
  It 'passes the default tier range next to the default spoke' {
    $r = @(Get-LwAddressCheck -TierAddressPrefix 10.61.0.0/24 -LandingZone (Get-DevLandingZone))
    $r.Status | Should -Be 'PASS'
    $r.Check | Should -Be 'tier-address-space'
  }
  It 'fails a range inside the spoke' {
    (Get-LwAddressCheck -TierAddressPrefix 10.100.3.0/24 -LandingZone (Get-DevLandingZone)).Status | Should -Be 'FAIL'
  }
  It 'fails the Stratusphere range, which peers with the same spoke' {
    (Get-LwAddressCheck -TierAddressPrefix 10.60.0.0/24 -LandingZone (Get-DevLandingZone)).Status | Should -Be 'FAIL'
  }
  It 'fails a range another peering already uses, but not our own peering' {
    $lz = Get-DevLandingZone -Change {
      param($f)
      $f.Vnet | Add-Member -NotePropertyName Peerings -NotePropertyValue @(
        [pscustomobject]@{ Name = 'peer-avdlz-dev-to-liquidware'; RemoteAddressPrefixes = @('10.61.0.0/24') }
        [pscustomobject]@{ Name = 'peer-to-hub'; RemoteAddressPrefixes = @('10.0.0.0/16') }
      )
    }
    (Get-LwAddressCheck -TierAddressPrefix 10.61.0.0/24 -LandingZone $lz).Status | Should -Be 'PASS'
    $hit = Get-LwAddressCheck -TierAddressPrefix 10.0.5.0/24 -LandingZone $lz
    $hit.Status | Should -Be 'FAIL'
    $hit.Detail | Should -Match 'peer-to-hub'
  }
}

Describe 'Get-LwStratusphereArgument' {
  It 'points the Stratusphere scripts at the landing zone, without Bastion' {
    $a = Get-LwStratusphereArgument -LandingZone (Get-DevLandingZone)
    $a.Location | Should -Be 'northcentralus'
    $a.NamePrefix | Should -Be 'avdlzd'
    $a.PeerVnetId | Should -Match '/virtualNetworks/vnet-avdlz-dev$'
    $a.HostPoolName | Should -Be 'vdpool-avdlz-dev'
    $a.HostPoolResourceGroup | Should -Be 'rg-avdlz-dev-avd'
    $a.NoBastion | Should -BeTrue
  }
  It 'only names parameters Test-StratusphereReadiness.ps1 accepts' {
    $params = (Get-Command (Join-Path $script:root 'stratusphere/scripts/ops/Test-StratusphereReadiness.ps1')).Parameters.Keys
    foreach ($k in (Get-LwStratusphereArgument -LandingZone (Get-DevLandingZone)).Keys) { $params | Should -Contain $k }
  }
}

Describe 'Get-LwUsersGroup' {
  BeforeAll {
    $script:share = 'Storage File Data SMB Share Contributor'
    function New-Assignment($Id, $Type, $Role) { [pscustomobject]@{ ObjectId = $Id; ObjectType = $Type; RoleDefinitionName = $Role } }
  }
  It 'finds the one group with SMB Share Contributor on the profiles account' {
    $g = Get-LwUsersGroup -RoleAssignment @(
      New-Assignment 'group-1' 'Group' $script:share
      New-Assignment 'sp-1' 'ServicePrincipal' $script:share
      New-Assignment 'group-2' 'Group' 'Reader'
    )
    $g.ObjectId | Should -Be 'group-1'
    $g.Result.Status | Should -Be 'PASS'
  }
  It 'fails with none or several, and names the override' {
    (Get-LwUsersGroup -RoleAssignment @()).Result.Status | Should -Be 'FAIL'
    $two = Get-LwUsersGroup -RoleAssignment @((New-Assignment 'group-1' 'Group' $script:share), (New-Assignment 'group-2' 'Group' $script:share))
    $two.ObjectId | Should -BeNullOrEmpty
    $two.Result.Recommendation | Should -Match '-UsersGroupId'
  }
  It 'takes the override as given' {
    (Get-LwUsersGroup -RoleAssignment @() -Override 'group-9').ObjectId | Should -Be 'group-9'
  }
}

Describe 'Get-LwGeneratedPassword' {
  BeforeAll { function ConvertTo-Plain($s) { [System.Net.NetworkCredential]::new('', $s).Password } }
  It 'is a read-only SecureString of 24 characters with all four character classes' {
    $s = Get-LwGeneratedPassword
    $s | Should -BeOfType [securestring]
    $s.IsReadOnly() | Should -BeTrue
    $p = ConvertTo-Plain $s
    $p.Length | Should -Be 24
    $p | Should -MatchExactly '[A-Z]'
    $p | Should -MatchExactly '[a-z]'
    $p | Should -Match '[0-9]'
    $p | Should -Match '[^A-Za-z0-9]'
  }
  It 'differs on every call' {
    @(1..20 | ForEach-Object { ConvertTo-Plain (Get-LwGeneratedPassword) } | Sort-Object -Unique).Count | Should -Be 20
  }
}

Describe 'Get-LwTierState' {
  It 'plans a new console and warns that the license is not stored, when the tier is new' {
    $s = Get-LwTierState
    $s.ConsoleExists | Should -BeFalse
    $s.LicenseStored | Should -BeFalse
    ($s.Result | Where-Object Check -eq 'console').Status | Should -Be 'INFO'
    ($s.Result | Where-Object Check -eq 'license-secret').Status | Should -Be 'WARN'
    ($s.Result | Where-Object Check -eq 'license-secret').Recommendation | Should -Match 'Set-LiquidwareSecret'
  }
  It 'keeps an existing console and passes its identity on' {
    $s = Get-LwTierState -Console ([pscustomobject]@{ Name = 'vm-avdlzlwcon'; PrincipalId = 'principal-1' }) -LicenseSecret ([pscustomobject]@{ Name = 'lw-licstr' })
    $s.ConsoleExists | Should -BeTrue
    $s.ConsolePrincipalId | Should -Be 'principal-1'
    $s.LicenseStored | Should -BeTrue
    @($s.Result | Where-Object Status -in 'FAIL', 'WARN') | Should -BeNullOrEmpty
  }
  It 'fails a console without its identity (ARM omits it)' {
    $s = Get-LwTierState -Console ([pscustomobject]@{ Name = 'vm-avdlzlwcon' })
    ($s.Result | Where-Object Check -eq 'console').Status | Should -Be 'FAIL'
  }
}

Describe 'Get-LwTemplateParameter' {
  BeforeAll {
    $script:newTier = Get-LwTierState
    function Get-Param([object] $State = $script:newTier, [securestring] $Password = (Get-LwGeneratedPassword)) {
      Get-LwTemplateParameter -LandingZone (Get-DevLandingZone) -TierAddressPrefix 10.61.0.0/24 -UsersGroupObjectId 'group-1' -AvdServicePrincipalObjectId 'sp-1', 'sp-2' `
        -OperatorObjectId 'operator-1' -TierState $State -ConsoleAdminPassword $Password
    }
  }
  It 'names exactly the parameters of profileunity/bicep/main.bicep' {
    $p = Get-Param
    $bicep = Get-Content (Join-Path $script:root 'profileunity/bicep/main.bicep') -Raw
    $declared = @([regex]::Matches($bicep, '(?m)^param (\w+)') | ForEach-Object { $_.Groups[1].Value } | Where-Object { $_ -ne 'tags' })
    @($p.Keys | Sort-Object) | Should -Be @($declared | Sort-Object)
  }
  It 'fills them from the landing zone' {
    $p = Get-Param
    $p.namePrefix | Should -Be 'avdlz'
    $p.environment | Should -Be 'dev'
    $p.spokeAddressPrefixes | Should -Be @('10.100.0.0/22')
    $p.spokePrivateEndpointSubnetPrefix | Should -Be '10.100.2.0/27'
    $p.avdServicePrincipalObjectIds.Count | Should -Be 2
    $p.deployBastion | Should -BeFalse
    $p.operatorObjectId | Should -Be 'operator-1'
    $p.autoShutdownTime | Should -Be '1900'
  }
  It 'passes a password, as a SecureString, only for a new console' {
    $new = Get-Param
    $new.consoleExists | Should -BeFalse
    $new.consoleAdminPassword | Should -BeOfType [securestring]
    $existing = Get-Param -State (Get-LwTierState -Console ([pscustomobject]@{ Name = 'vm-avdlzlwcon'; PrincipalId = 'principal-1' }))
    $existing.consoleExists | Should -BeTrue
    $existing.consolePrincipalId | Should -Be 'principal-1'
    $existing.consoleAdminPassword | Should -BeNullOrEmpty
  }
  It 'refuses a new console without a password' {
    { Get-LwTemplateParameter -LandingZone (Get-DevLandingZone) -TierAddressPrefix 10.61.0.0/24 -UsersGroupObjectId 'group-1' -AvdServicePrincipalObjectId 'sp-1', 'sp-2' -OperatorObjectId 'operator-1' -TierState $script:newTier } |
      Should -Throw '*ConsoleAdminPassword*'
  }
  It 'grants the license role only once the secret is stored' {
    (Get-Param).licenseStored | Should -BeFalse
    (Get-Param -State (Get-LwTierState -LicenseSecret ([pscustomobject]@{ Name = 'lw-licstr' }))).licenseStored | Should -BeTrue
  }
}

Describe 'Get-LwWhatIfSummary' {
  BeforeAll {
    $script:sub = '/subscriptions/00000000-0000-0000-0000-000000000000'
    function New-Change($Type, $Id) { [pscustomobject]@{ ChangeType = $Type; ResourceId = "$script:sub$Id" } }
  }
  It 'reports tier resources and the listed landing zone writes as information' {
    $r = @(Get-LwWhatIfSummary -LandingZone (Get-DevLandingZone) -Change @(
        New-Change 'Create' '/resourceGroups/rg-avdlz-dev-liquidware'
        New-Change 'Create' '/resourceGroups/rg-avdlz-dev-liquidware/providers/Microsoft.Network/virtualNetworks/vnet-avdlz-dev-liquidware'
        New-Change 'Create' '/resourceGroups/rg-avdlz-dev-network/providers/Microsoft.Network/virtualNetworks/vnet-avdlz-dev/virtualNetworkPeerings/peer-avdlz-dev-to-liquidware'
        New-Change 'Create' '/resourceGroups/rg-avdlz-dev-network/providers/Microsoft.Network/privateDnsZones/privatelink.file.core.windows.net/virtualNetworkLinks/link-avdlz-dev-liquidware'
        New-Change 'NoChange' '/resourceGroups/rg-avdlz-dev-network/providers/Microsoft.Network/virtualNetworks/vnet-avdlz-dev'
      ))
    $r.Count | Should -Be 4
    @($r | Where-Object Status -ne 'INFO').Count | Should -Be 0
  }
  It 'fails a change to any other landing zone resource' {
    $r = Get-LwWhatIfSummary -LandingZone (Get-DevLandingZone) -Change @(New-Change 'Modify' '/resourceGroups/rg-avdlz-dev-network/providers/Microsoft.Network/virtualNetworks/vnet-avdlz-dev')
    $r.Status | Should -Be 'FAIL'
    $r.Detail | Should -Match 'outside deploy-spec section 4'
  }
  It 'fails any delete, even in the tier' {
    (Get-LwWhatIfSummary -LandingZone (Get-DevLandingZone) -Change @(New-Change 'Delete' '/resourceGroups/rg-avdlz-dev-liquidware/providers/Microsoft.KeyVault/vaults/kvx')).Status | Should -Be 'FAIL'
  }
  It 'does not let a look-alike peering through' {
    (Get-LwWhatIfSummary -LandingZone (Get-DevLandingZone) -Change @(New-Change 'Create' '/resourceGroups/rg-avdlz-dev-network/providers/Microsoft.Network/virtualNetworks/vnet-avdlz-dev/virtualNetworkPeerings/peer-avdlz-dev-to-liquidware-2')).Status | Should -Be 'FAIL'
  }
}

Describe 'Get-LwMediaBlobName' {
  It 'puts an installer under component, version and file' {
    Get-LwMediaBlobName -Component ProfileUnityClient -Version 6.9.5 -FileName 'ProfileUnityClient.exe' | Should -Be 'ProfileUnityClient/6.9.5/ProfileUnityClient.exe'
  }
  It 'refuses names that could leave the container path or the URL' {
    { Get-LwMediaBlobName -Component Other -Version 6.9.5 -FileName a.exe } | Should -Throw '*Unknown media component*'
    { Get-LwMediaBlobName -Component ProfileUnityClient -Version '6.9.5/../x' -FileName a.exe } | Should -Throw '*Version*'
    foreach ($bad in '../a.exe', 'a b.exe', '.hidden', 'a?x=1', 'a%2f.exe') {
      { Get-LwMediaBlobName -Component ProfileUnityClient -Version 6.9.5 -FileName $bad } | Should -Throw '*File name*' -Because $bad
    }
  }
}

Describe 'Get-LwMediaLock' {
  BeforeAll { $script:hash = 'AB' * 32 }
  It 'starts a lock with one entry, the hash in lower case' {
    $l = Get-LwMediaLock -Component ProfileUnityConsole -Version 6.9.5 -FileName console.exe -Sha256 $script:hash -Size 10
    $l.format | Should -Be 'avd-liquidware-media-lock/v1'
    @($l.entries).Count | Should -Be 1
    $l.entries[0].sha256 | Should -Be ('ab' * 32)
    $l.entries[0].blob | Should -Be 'ProfileUnityConsole/6.9.5/console.exe'
  }
  It 'replaces the same component and version, keeps the others, and survives a JSON round trip' {
    $l = Get-LwMediaLock -Component ProfileUnityConsole -Version 6.9.5 -FileName console.exe -Sha256 $script:hash -Size 10
    $l = Get-LwMediaLock -Lock $l -Component ProfileUnityClient -Version 6.9.5 -FileName client.exe -Sha256 $script:hash -Size 20
    $l = ($l | ConvertTo-Json -Depth 5 | ConvertFrom-Json)
    $l = Get-LwMediaLock -Lock $l -Component ProfileUnityConsole -Version 6.9.5 -FileName console2.exe -Sha256 ('cd' * 32) -Size 30
    @($l.entries).Count | Should -Be 2
    ($l.entries | Where-Object component -eq ProfileUnityConsole).file | Should -Be 'console2.exe'
  }
  It 'reads a lock without entries (ARM-style omission) and refuses a bad hash or another format' {
    @((Get-LwMediaLock -Lock ([pscustomobject]@{ format = 'avd-liquidware-media-lock/v1' }) -Component ProfileUnityClient -Version 6.9.5 -FileName c.exe -Sha256 $script:hash -Size 1).entries).Count | Should -Be 1
    { Get-LwMediaLock -Component ProfileUnityClient -Version 6.9.5 -FileName c.exe -Sha256 'abc' -Size 1 } | Should -Throw '*64 hex*'
    { Get-LwMediaLock -Lock ([pscustomobject]@{ format = 'v0' }) -Component ProfileUnityClient -Version 6.9.5 -FileName c.exe -Sha256 $script:hash -Size 1 } | Should -Throw '*v0*'
  }
  It 'matches the example lock in this repo, which holds no real hash' {
    $example = Get-Content (Join-Path $script:root 'profileunity/media.lock.example.json') -Raw | ConvertFrom-Json
    $example.format | Should -Be 'avd-liquidware-media-lock/v1'
    foreach ($e in $example.entries) {
      Get-LwMediaBlobName -Component $e.component -Version $e.version -FileName $e.file | Should -Be $e.blob
      $e.sha256 | Should -Match '^0{64}$'
    }
  }
}

Describe 'Get-LwSecretPath' {
  It 'writes lw-licstr through the management plane' {
    $kv = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-avdlz-dev-liquidware/providers/Microsoft.KeyVault/vaults/kvavdlzdevlwabcde'
    Get-LwSecretPath -KeyVaultId $kv -Name lw-licstr | Should -Be "$kv/secrets/lw-licstr?api-version=2023-07-01"
  }
  It 'refuses the console password, which only the deploy writes, and anything that is not a vault' {
    { Get-LwSecretPath -KeyVaultId '/subscriptions/x/resourceGroups/y/providers/Microsoft.KeyVault/vaults/kv1' -Name lw-console-password } | Should -Throw
    { Get-LwSecretPath -KeyVaultId '/subscriptions/x/resourceGroups/y/providers/Microsoft.Storage/storageAccounts/st1' -Name lw-licstr } | Should -Throw '*Key Vault*'
  }
}

Describe 'Get-LwPlanSummary' {
  It 'says nothing but the budget warning for the actions built for ProfileUnity and FlexApp' {
    @(Get-LwPlanSummary -Component ProfileUnity, FlexApp -Action Check).Count | Should -Be 0
    @(Get-LwPlanSummary -Component ProfileUnity, FlexApp -Action Cleanup).Count | Should -Be 0
    $d = @(Get-LwPlanSummary -Component ProfileUnity -Action Deploy)
    $d.Count | Should -Be 1
    $d[0].Check | Should -Be 'budget'
    $d[0].Status | Should -Be 'WARN'
  }
  It 'fails, per component, for an action not built yet' {
    $r = @(Get-LwPlanSummary -Component ProfileUnity, FlexApp -Action Promote)
    $r.Count | Should -Be 2
    $r[0].Detail | Should -Match 'not built yet'
    @(Get-LwPlanSummary -Component Stratusphere -Action Deploy | Where-Object Status -eq 'FAIL').Count | Should -Be 1
  }
}

Describe 'Get-LwMediaLockEntry' {
  It 'picks the newest version of one component, and nothing from an empty lock' {
    $lock = [pscustomobject]@{ entries = @(
        [pscustomobject]@{ component = 'ProfileUnityConsole'; version = '6.9.10'; blob = 'a' }
        [pscustomobject]@{ component = 'ProfileUnityConsole'; version = '6.9.5'; blob = 'b' }
        [pscustomobject]@{ component = 'ProfileUnityClient'; version = '7.0'; blob = 'c' }
      )
    }
    (Get-LwMediaLockEntry -Lock $lock -Component ProfileUnityConsole).blob | Should -Be 'a'
    Get-LwMediaLockEntry -Lock $null -Component ProfileUnityConsole | Should -BeNullOrEmpty
    Get-LwMediaLockEntry -Lock ([pscustomobject]@{ format = 'avd-liquidware-media-lock/v1' }) -Component ProfileUnityConsole | Should -BeNullOrEmpty
  }
}

Describe 'Get-LwDeletedVault' {
  BeforeAll {
    $script:n = Get-LwName -NamePrefix avdlz -Environment dev
    function New-Removed($Name) { [pscustomobject]@{ VaultName = $Name; Location = 'northcentralus'; ScheduledPurgeDate = '2026-10-26' } }
  }
  It 'finds the tier vault an earlier Cleanup soft-deleted' {
    $r = Get-LwDeletedVault -Names $script:n -Removed @((New-Removed 'kvavdlzdevlwab12c'), (New-Removed 'kv-other'))
    $r.Vault.VaultName | Should -Be 'kvavdlzdevlwab12c'
    $r.Result[0].Status | Should -Be 'INFO'
  }
  It 'ignores other landing zones and environments' {
    (Get-LwDeletedVault -Names $script:n -Removed @((New-Removed 'kvavdlztestlwab12c'), (New-Removed 'kvavdlzdevlwab12cextra'), (New-Removed 'kvavdlzxdevlwab12c'))).Vault | Should -BeNullOrEmpty
    @((Get-LwDeletedVault -Names $script:n).Result).Count | Should -Be 0
  }
  It 'fails rather than guess between two' {
    $r = Get-LwDeletedVault -Names $script:n -Removed @((New-Removed 'kvavdlzdevlwab12c'), (New-Removed 'kvavdlzdevlwzz99y'))
    $r.Vault | Should -BeNullOrEmpty
    $r.Result[0].Status | Should -Be 'FAIL'
  }
}

Describe 'Get-LwCleanupPlan' {
  BeforeAll {
    $script:n = Get-LwName -NamePrefix avdlz -Environment dev
    $script:tierVnet = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-avdlz-dev-liquidware/providers/Microsoft.Network/virtualNetworks/vnet-avdlz-dev-liquidware'
    $script:otherVnet = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/virtualNetworks/vnet-hub'
    function New-Link($Name, $Zone, $Vnet) { [pscustomobject]@{ Name = $Name; ZoneName = $Zone; VirtualNetworkId = $Vnet; ResourceId = "/x/$Zone/$Name" } }
  }
  It 'removes the peering and DNS links first, then the tier resource group' {
    $steps = @(Get-LwCleanupPlan -Names $script:n -TierGroupExists $true `
        -Peering @([pscustomobject]@{ Name = 'peer-avdlz-dev-to-liquidware'; RemoteVnetId = $script:tierVnet }) `
        -DnsLink @((New-Link 'link-avdlz-dev-liquidware' 'privatelink.file.core.windows.net' $script:tierVnet), (New-Link 'link-avdlz-dev-liquidware' 'privatelink.vaultcore.azure.net' $script:tierVnet)))
    @($steps.Kind) | Should -Be @('Peering', 'DnsLink', 'DnsLink', 'ResourceGroup')
    $steps[-1].Name | Should -Be 'rg-avdlz-dev-liquidware'
    $steps[0].Parent | Should -Be 'vnet-avdlz-dev'
    $steps[0].ResourceGroup | Should -Be 'rg-avdlz-dev-network'
  }
  It 'never touches a landing zone peering or link that is not the tier one' {
    $steps = @(Get-LwCleanupPlan -Names $script:n `
        -Peering @([pscustomobject]@{ Name = 'peer-avdlz-dev-to-hub'; RemoteVnetId = $script:otherVnet }, [pscustomobject]@{ Name = 'peer-avdlz-dev-to-liquidware'; RemoteVnetId = $script:otherVnet }) `
        -DnsLink @((New-Link 'link-avdlz-dev' 'privatelink.file.core.windows.net' '/x/vnet-avdlz-dev'), (New-Link 'link-avdlz-dev-liquidware' 'privatelink.file.core.windows.net' $script:otherVnet)))
    $steps | Should -BeNullOrEmpty
  }
  It 'does nothing when nothing is left (ARM omits empty peerings)' {
    @(Get-LwCleanupPlan -Names $script:n) | Should -BeNullOrEmpty
  }
}

Describe 'Get-LwTeardownCheck' {
  BeforeAll { $script:n = Get-LwName -NamePrefix avdlz -Environment dev }
  It 'passes when the resource group, peering and links are gone' {
    $r = @(Get-LwTeardownCheck -Names $script:n)
    $r.Count | Should -Be 1
    $r[0].Status | Should -Be 'PASS'
  }
  It 'fails once per thing left' {
    $r = @(Get-LwTeardownCheck -Names $script:n -TierGroupExists $true)
    $r.Count | Should -Be 1
    $r[0].Status | Should -Be 'FAIL'
    $r[0].Detail | Should -Match 'rg-avdlz-dev-liquidware'
  }
}

Describe 'Get-LwRunCommandResult' {
  It 'passes a verified console download' {
    $r = Get-LwRunCommandResult -Output "Console checklist ...`nLW-RESULT status=verified path=C:\x.exe detail=SHA-256 matches" -Check 'console-install'
    $r.Status | Should -Be 'PASS'
    $r.Detail | Should -Match 'SHA-256 matches'
  }
  It 'fails a failed run, or output without the result line, and shows what came back' {
    (Get-LwRunCommandResult -Output 'LW-RESULT status=failed path= detail=SHA-256 mismatch' -Check 'console-install').Status | Should -Be 'FAIL'
    $none = Get-LwRunCommandResult -Output "Access denied`r`n" -Check 'console-install'
    $none.Status | Should -Be 'FAIL'
    $none.Detail | Should -Match 'Access denied'
    (Get-LwRunCommandResult -Output '' -Check 'console-install').Status | Should -Be 'FAIL'
  }
}

Describe 'Entry points' {
  It 'carry the personal-project notice near the top' {
    foreach ($f in 'scripts/Deploy-LiquidwareTier.ps1', 'scripts/LiquidwareTier.psm1', 'scripts/Publish-LiquidwareMedia.ps1', 'scripts/Set-LiquidwareSecret.ps1') {
      (Get-Content (Join-Path $script:root $f) -TotalCount 8) -join "`n" | Should -Match 'Personal project, not for production use' -Because $f
    }
  }
}

Describe 'Set-LiquidwareSecret.ps1' {
  BeforeAll {
    $script:path = Join-Path $script:root 'scripts/Set-LiquidwareSecret.ps1'
    $script:ast = [System.Management.Automation.Language.Parser]::ParseFile($script:path, [ref] $null, [ref] $null)
    $script:text = Get-Content $script:path -Raw
  }
  It 'takes the value only from a hidden prompt, never as a parameter' {
    $params = @($script:ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
    $params | Should -Not -Contain 'Value'
    $params | Should -Not -Contain 'Secret'
    @($script:ast.ParamBlock.Parameters | Where-Object { $_.StaticType -in [securestring], [pscredential] }) | Should -BeNullOrEmpty
    $script:text | Should -Match 'Read-Host [^\r\n]*-AsSecureString'
  }
  It 'never prints, logs or exports the value' {
    $script:text | Should -Not -Match '(Write-\w+|Out-\w+|Set-Content|Add-Content|Export-\w+|Start-Transcript)[^\r\n]*\$(plain|body|secure)\b'
    $script:text | Should -Not -Match 'ConvertFrom-SecureString'
  }
  It 'writes through the management plane, not the vault data plane' {
    $script:text | Should -Match 'Invoke-AzRestMethod -Method PUT -Path \$secretPath'
    $script:text | Should -Not -Match 'Set-AzKeyVaultSecret|vault\.azure\.net'
  }
}
