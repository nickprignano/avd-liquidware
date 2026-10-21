#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# Deploy-LiquidwareTier.ps1 run end to end with every Az cmdlet mocked: what Cleanup removes,
# and that an unbuilt action or a declined confirmation changes nothing. Offline; no Az modules.

BeforeAll {
  $script:entry = Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts/Deploy-LiquidwareTier.ps1'
  $sub = '/subscriptions/00000000-0000-0000-0000-000000000000'
  $global:LwTest = @{
    Sub      = $sub
    TierVnet = "$sub/resourceGroups/rg-avdlz-dev-liquidware/providers/Microsoft.Network/virtualNetworks/vnet-avdlz-dev-liquidware"
    HubVnet  = "$sub/resourceGroups/rg-hub/providers/Microsoft.Network/virtualNetworks/vnet-hub"
    Removed  = $false
  }
  # Empty Az modules on PSModulePath, so the script's module checks and imports work unmocked.
  $script:modulePath = $env:PSModulePath
  foreach ($m in 'Az.Accounts', 'Az.Resources', 'Az.Network', 'Az.Compute', 'Az.KeyVault', 'Az.PrivateDns') {
    $dir = New-Item -ItemType Directory -Path (Join-Path $TestDrive "modules/$m") -Force
    Set-Content -Path (Join-Path $dir "$m.psm1") -Value '# test stand-in'
  }
  $env:PSModulePath = (Join-Path $TestDrive 'modules') + [System.IO.Path]::PathSeparator + $env:PSModulePath
  # Stand-ins for the Az cmdlets the script calls (and Install-Module, absent where PowerShellGet
  # is), so Pester can mock them without the modules.
  foreach ($c in 'Get-AzContext', 'Set-AzContext', 'Get-AzResourceGroup', 'Get-AzResource', 'Get-AzVirtualNetwork', 'Get-AzPrivateDnsZone',
    'Get-AzPrivateDnsVirtualNetworkLink', 'Remove-AzVirtualNetworkPeering', 'Remove-AzPrivateDnsVirtualNetworkLink', 'Remove-AzResourceGroup',
    'New-AzSubscriptionDeployment', 'Get-AzSubscriptionDeploymentWhatIfResult', 'Get-AzRoleAssignment', 'Install-Module') {
    # One superset of the parameters the script passes, so mocks' parameter filters can read them.
    New-Item -Path "function:global:$c" -Value {
      param($Name, $VirtualNetworkName, $ResourceGroupName, $ResourceId, $ZoneName, $Location, $Scope, $ResourceType, $SubscriptionId,
        $TemplateFile, $TemplateParameterObject, [switch] $Force, [Parameter(ValueFromRemainingArguments)] $Rest)
    } -Force | Out-Null
  }
}

AfterAll {
  $env:PSModulePath = $script:modulePath
  Remove-Variable -Name LwTest -Scope Global -ErrorAction SilentlyContinue
}

Describe 'Deploy-LiquidwareTier.ps1 -Action Cleanup' {
  BeforeEach {
    $global:LwTest.Removed = $false
    Mock Install-Module { }
    Mock Get-AzContext { [pscustomobject]@{ Subscription = [pscustomobject]@{ Name = 'sandbox' } } }
    Mock Get-AzResourceGroup {
      $g = @('rg-avdlz-dev-network', 'rg-avdlz-dev-management', 'rg-avdlz-dev-storage', 'rg-avdlz-dev-avd', 'rg-avdlz-dev-hosts')
      if (-not $global:LwTest.Removed) { $g += 'rg-avdlz-dev-liquidware' }
      $g | ForEach-Object { [pscustomobject]@{ ResourceGroupName = $_ } }
    }
    Mock Get-AzResource { @() }
    Mock Get-AzVirtualNetwork {
      $peerings = @([pscustomobject]@{ Name = 'peer-avdlz-dev-to-hub'; RemoteVirtualNetwork = [pscustomobject]@{ Id = $global:LwTest.HubVnet } })
      if (-not $global:LwTest.Removed) { $peerings += [pscustomobject]@{ Name = 'peer-avdlz-dev-to-liquidware'; RemoteVirtualNetwork = [pscustomobject]@{ Id = $global:LwTest.TierVnet } } }
      [pscustomobject]@{ Id = '/x/vnet-avdlz-dev'; Location = 'northcentralus'; AddressSpace = [pscustomobject]@{ AddressPrefixes = @('10.100.0.0/22') }; Subnets = @(); VirtualNetworkPeerings = $peerings }
    }
    Mock Get-AzPrivateDnsZone { @([pscustomobject]@{ Name = 'privatelink.file.core.windows.net' }, [pscustomobject]@{ Name = 'privatelink.vaultcore.azure.net' }) }
    Mock Get-AzPrivateDnsVirtualNetworkLink {
      $l = @([pscustomobject]@{ Name = 'link-avdlz-dev'; VirtualNetworkId = '/x/vnet-avdlz-dev'; ResourceId = "/x/$ZoneName/link-avdlz-dev" })
      if (-not $global:LwTest.Removed) { $l += [pscustomobject]@{ Name = 'link-avdlz-dev-liquidware'; VirtualNetworkId = $global:LwTest.TierVnet; ResourceId = "/x/$ZoneName/link-avdlz-dev-liquidware" } }
      $l
    }
    Mock Remove-AzVirtualNetworkPeering { }
    Mock Remove-AzPrivateDnsVirtualNetworkLink { }
    Mock Remove-AzResourceGroup { $global:LwTest.Removed = $true; $true }
    Mock New-AzSubscriptionDeployment { }
    Mock Read-Host { 'rg-avdlz-dev-liquidware' }
    Mock Write-Host { }
  }

  It 'removes only the tier peering, the two tier DNS links and the tier resource group, then passes the teardown check' {
    & $script:entry -NamePrefix avdlz -Environment dev -Component ProfileUnity -Action Cleanup -ReportDirectory $TestDrive -DiscardLastCopy
    $LASTEXITCODE | Should -Be 0
    Should -Invoke Remove-AzVirtualNetworkPeering -Times 1 -Exactly -ParameterFilter { $Name -eq 'peer-avdlz-dev-to-liquidware' -and $VirtualNetworkName -eq 'vnet-avdlz-dev' -and $ResourceGroupName -eq 'rg-avdlz-dev-network' }
    Should -Invoke Remove-AzVirtualNetworkPeering -Times 1 -Exactly
    Should -Invoke Remove-AzPrivateDnsVirtualNetworkLink -Times 2 -Exactly -ParameterFilter { $ResourceId -like '*/link-avdlz-dev-liquidware' }
    Should -Invoke Remove-AzPrivateDnsVirtualNetworkLink -Times 2 -Exactly
    Should -Invoke Remove-AzResourceGroup -Times 1 -Exactly -ParameterFilter { $Name -eq 'rg-avdlz-dev-liquidware' }
    Should -Invoke Write-Host -ParameterFilter { "$Object" -match 'PASS\s+teardown' }
    Should -Invoke New-AzSubscriptionDeployment -Times 0
    $report = Get-ChildItem $TestDrive -Filter 'cleanup-avdlz-dev-*.json' | Sort-Object LastWriteTime | Select-Object -Last 1 | Get-Content -Raw | ConvertFrom-Json
    ($report.results | Where-Object check -eq 'teardown').status | Should -Be 'PASS'
  }

  It 'removes nothing without -DiscardLastCopy, and does not ask (never delete the last copy)' {
    & $script:entry -NamePrefix avdlz -Environment dev -Component ProfileUnity -Action Cleanup -ReportDirectory $TestDrive
    $LASTEXITCODE | Should -Be 1
    Should -Invoke Write-Host -ParameterFilter { "$Object" -match 'FAIL\s+last-copy' }
    Should -Invoke Read-Host -Times 0
    Should -Invoke Remove-AzResourceGroup -Times 0
    Should -Invoke Remove-AzVirtualNetworkPeering -Times 0
    Should -Invoke Remove-AzPrivateDnsVirtualNetworkLink -Times 0
  }

  It 'removes nothing when the operator does not type the resource group name' {
    Mock Read-Host { 'no' }
    & $script:entry -NamePrefix avdlz -Environment dev -Component ProfileUnity -Action Cleanup -ReportDirectory $TestDrive -DiscardLastCopy
    Should -Invoke Write-Host -Times 4 -Exactly -ParameterFilter { "$Object" -match 'INFO\s+cleanup-step' }
    Should -Invoke Remove-AzResourceGroup -Times 0
    Should -Invoke Remove-AzVirtualNetworkPeering -Times 0
    Should -Invoke Remove-AzPrivateDnsVirtualNetworkLink -Times 0
  }

  It 'removes nothing with -WhatIf, and does not ask' {
    & $script:entry -NamePrefix avdlz -Environment dev -Component ProfileUnity -Action Cleanup -ReportDirectory $TestDrive -WhatIf
    Should -Invoke Write-Host -Times 4 -Exactly -ParameterFilter { "$Object" -match 'INFO\s+cleanup-step' }
    Should -Invoke Remove-AzResourceGroup -Times 0
    Should -Invoke Remove-AzVirtualNetworkPeering -Times 0
    Should -Invoke Read-Host -Times 0
  }

  It 'fails an action that is not built before reading or changing anything' {
    & $script:entry -NamePrefix avdlz -Environment dev -Component Stratusphere -Action Cleanup -ReportDirectory $TestDrive
    $LASTEXITCODE | Should -Be 1
    Should -Invoke Get-AzResourceGroup -Times 0
    Should -Invoke Remove-AzResourceGroup -Times 0
  }
}
