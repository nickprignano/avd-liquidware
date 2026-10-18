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

Describe 'Get-LwPlanSummary' {
  It 'says nothing for the actions this slice builds' {
    @(Get-LwPlanSummary -Component ProfileUnity, FlexApp -Action Check).Count | Should -Be 0
  }
  It 'fails, per component, for an action not built yet' {
    $r = @(Get-LwPlanSummary -Component ProfileUnity, FlexApp -Action Deploy)
    $r.Count | Should -Be 2
    $r[0].Detail | Should -Match 'not built yet'
  }
}

Describe 'Entry points' {
  It 'carry the personal-project notice near the top' {
    foreach ($f in 'scripts/Deploy-LiquidwareTier.ps1', 'scripts/LiquidwareTier.psm1') {
      (Get-Content (Join-Path $script:root $f) -TotalCount 8) -join "`n" | Should -Match 'Personal project, not for production use' -Because $f
    }
  }
}
