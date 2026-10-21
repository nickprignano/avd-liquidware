#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# Offline tests for the appliance lifecycle: roles, health, fix and cleanup planning.

BeforeAll {
  $script:root = Split-Path $PSScriptRoot -Parent
  Import-Module (Join-Path $script:root 'scripts/ops/StratusphereAppliance.psm1') -Force
  function Get-Vm([string] $Name, [string] $Ip, [string] $Power = 'VM running', [string] $Alloc = 'Static', [string] $State = 'Succeeded') {
    [pscustomobject]@{ Name = $Name; PrivateIp = $Ip; PowerState = $Power; IpAllocation = $Alloc; ProvisioningState = $State }
  }
}

Describe 'Get-SsuxApplianceSpec and role tags' {
  It 'names each appliance and gives it its static IP' {
    $s = @(Get-SsuxApplianceSpec -NamePrefix 'lab' -Hub -Database -CollectorCount 2)
    $s.Name | Should -Be @('vm-lab-hub', 'vm-lab-db', 'vm-lab-col1', 'vm-lab-col2')
    $s.PrivateIp | Should -Be @('10.60.0.4', '10.60.0.5', '10.60.0.10', '10.60.0.11')
  }
  It 'reads the role from the tag the template sets' {
    Get-SsuxApplianceRole -Tag 'hub' | Should -Be 'Hub'
    Get-SsuxApplianceRole -Tag 'collector-3' | Should -Be 'Collector'
    Get-SsuxApplianceRole -Tag '' | Should -BeNullOrEmpty
  }
}

Describe 'Get-SsuxApplianceArgumentError' {
  It 'rejects a bad prefix, plan or peer ID' {
    @(Get-SsuxApplianceArgumentError -Action Deploy -NamePrefix 'Lab_1').Count | Should -Be 1
    @(Get-SsuxApplianceArgumentError -Action Deploy -NamePrefix 'lab' -Plan @{ Hub = "x'; rm" }).Count | Should -Be 1
    @(Get-SsuxApplianceArgumentError -Action Deploy -NamePrefix 'lab' -PeerVnetId '/subscriptions/x').Count | Should -Be 1
  }
  It 'requires a role for Cleanup' {
    @(Get-SsuxApplianceArgumentError -Action Cleanup -NamePrefix 'lab') | Should -Match 'Cleanup needs -Role'
    @(Get-SsuxApplianceArgumentError -Action Cleanup -Role Collector -NamePrefix 'lab').Count | Should -Be 0
  }
}

Describe 'Get-SsuxDeployTarget' {
  It 'adds the Hub when only a Database or Collectors are asked for' {
    $t = Get-SsuxDeployTarget -Role Collector -CollectorCount 2 -Plan @{ Hub = 'h'; Collector = 'c' }
    $t.DeployHub | Should -BeTrue
    $t.CollectorCount | Should -Be 2
    $t.Notes | Should -Match 'report to a Hub'
    $t.Errors | Should -BeNullOrEmpty
  }
  It 'keeps existing roles and their plans in the template' {
    $existing = @(
      [pscustomobject]@{ Role = 'Hub'; Name = 'vm-lab-hub'; PlanName = 'hub-plan' }
      [pscustomobject]@{ Role = 'Database'; Name = 'vm-lab-db'; PlanName = 'db-plan' }
    )
    $t = Get-SsuxDeployTarget -Role Collector -CollectorCount 1 -Plan @{ Collector = 'col-plan' } -Existing $existing
    $t.DeployDatabase | Should -BeTrue
    $t.Plan['Hub'] | Should -Be 'hub-plan'
    $t.Plan['Database'] | Should -Be 'db-plan'
    $t.Errors | Should -BeNullOrEmpty
  }
  It 'never shrinks the Collectors, and says how to' {
    $existing = 1..3 | ForEach-Object { [pscustomobject]@{ Role = 'Collector'; Name = "vm-lab-col$_"; PlanName = 'c' } }
    $existing += [pscustomobject]@{ Role = 'Hub'; Name = 'vm-lab-hub'; PlanName = 'h' }
    $t = Get-SsuxDeployTarget -Role Collector -CollectorCount 1 -Existing $existing
    $t.CollectorCount | Should -Be 3
    $t.Notes | Should -Match 'Cleanup -Role Collector'
  }
  It 'refuses to change the plan of an existing appliance, and needs a plan for a new one' {
    $existing = @([pscustomobject]@{ Role = 'Hub'; Name = 'vm-lab-hub'; PlanName = 'old' })
    (Get-SsuxDeployTarget -Role Hub -Plan @{ Hub = 'new' } -Existing $existing).Errors | Should -Match "can't change"
    (Get-SsuxDeployTarget -Role Hub).Errors | Should -Match '-HubPlan is required'
  }
}

Describe 'Get-SsuxApplianceHealth' {
  BeforeAll { $script:spec = @(Get-SsuxApplianceSpec -NamePrefix 'lab' -Hub -Database -CollectorCount 1) }
  It 'passes a running appliance at its static IP' {
    $r = @(Get-SsuxApplianceHealth -Spec @($script:spec[0]) -Vm @(Get-Vm 'vm-lab-hub' '10.60.0.4'))
    $r.Status | Should -Be 'PASS'
  }
  It 'says what Fix would do for each problem' {
    $vms = @(
      Get-Vm 'vm-lab-hub' '10.60.0.4' -Power 'VM deallocated'
      Get-Vm 'vm-lab-db' '10.60.0.9' -Alloc 'Dynamic'
    )
    $r = @(Get-SsuxApplianceHealth -Spec $script:spec -Vm $vms)
    $r.Remedy | Should -Be @('start', 'deploy', 'deploy')
    $r[1].Detail | Should -Match 'expected 10.60.0.5'
    $r[2].Detail | Should -Be 'VM not found'
  }
  It 'warns, without a fix, while a VM is starting' {
    $r = Get-SsuxApplianceHealth -Spec @($script:spec[0]) -Vm @(Get-Vm 'vm-lab-hub' '10.60.0.4' -Power 'VM starting')
    $r.Status | Should -Be 'WARN'
    $r.Remedy | Should -BeNullOrEmpty
  }
  It 'redeploys a failed provisioning' {
    (Get-SsuxApplianceHealth -Spec @($script:spec[0]) -Vm @(Get-Vm 'vm-lab-hub' '10.60.0.4' -State 'Failed')).Remedy | Should -Be 'deploy'
  }
}

Describe 'Network, vault and terms health' {
  It 'needs the Postgres rule only with a Database or Collectors' {
    $rules = 'Allow-Https-Callbacks-And-Console', 'Deny-Other-Inbound'
    $r = @(Get-SsuxNetworkHealth -RuleName $rules -NeedPostgres $false -HasNatGateway $true -DefaultOutboundAccess $false)
    $r.Status | Should -Be @('PASS', 'PASS')
    $r = @(Get-SsuxNetworkHealth -RuleName $rules -NeedPostgres $true -HasNatGateway $false -DefaultOutboundAccess $null)
    $r.Status | Should -Be @('FAIL', 'FAIL')
    $r[0].Detail | Should -Match 'Allow-Postgres-Between-Appliances'
  }
  It 'recovers a soft-deleted vault, and never invents a password for existing appliances' {
    (Get-SsuxVaultHealth -RemovedVaultName 'kv-lab-ss-abcde' -AppliancesExist $true).Remedy | Should -Be 'recover-vault'
    (Get-SsuxVaultHealth -AppliancesExist $true).Remedy | Should -Be 'manual'
    (Get-SsuxVaultHealth -VaultName 'kv' -SecretName @('appliance-admin-username') -AppliancesExist $true).Remedy | Should -Be 'manual'
    (Get-SsuxVaultHealth -VaultName 'kv' -SecretName @('appliance-admin-username', 'appliance-admin-password')).Status | Should -Be 'PASS'
  }
  It 'accepts terms that are missing' {
    $r = @(Get-SsuxTermsHealth -Terms @([pscustomobject]@{ Plan = 'a'; Accepted = $true }, [pscustomobject]@{ Plan = 'b'; Accepted = $false }))
    $r.Remedy | Should -Be @('', 'accept-terms')
  }
}

Describe 'Get-SsuxFixPlan' {
  It 'orders terms and vault before one deployment, then starts, and lists what it cannot fix' {
    $results = @(
      [pscustomobject]@{ Status = 'FAIL'; Check = 'hub vm-lab-hub'; Detail = 'stopped'; Remedy = 'start'; Name = 'vm-lab-hub' }
      [pscustomobject]@{ Status = 'FAIL'; Check = 'nsg'; Detail = 'x'; Remedy = 'deploy'; Name = '' }
      [pscustomobject]@{ Status = 'FAIL'; Check = 'db vm-lab-db'; Detail = 'x'; Remedy = 'deploy'; Name = 'vm-lab-db' }
      [pscustomobject]@{ Status = 'FAIL'; Check = 'key-vault'; Detail = 'gone'; Remedy = 'recover-vault'; Name = 'kv' }
      [pscustomobject]@{ Status = 'FAIL'; Check = 'marketplace-terms'; Detail = 'x'; Remedy = 'accept-terms'; Name = 'p' }
      [pscustomobject]@{ Status = 'FAIL'; Check = 'key-vault'; Detail = 'lost'; Remedy = 'manual'; Name = '' }
      [pscustomobject]@{ Status = 'PASS'; Check = 'egress'; Detail = 'ok'; Remedy = ''; Name = '' }
    )
    (Get-SsuxFixPlan -Result $results).Step | Should -Be @('accept-terms', 'recover-vault', 'deploy', 'start', 'manual')
  }
  It 'does nothing when everything passes' {
    @(Get-SsuxFixPlan -Result @([pscustomobject]@{ Status = 'PASS'; Remedy = '' })).Count | Should -Be 0
  }
}

Describe 'Get-SsuxCleanupPlan' {
  BeforeAll {
    $script:existing = @(
      [pscustomobject]@{ Role = 'Collector'; Name = 'vm-lab-col2' }
      [pscustomobject]@{ Role = 'Hub'; Name = 'vm-lab-hub' }
      [pscustomobject]@{ Role = 'Collector'; Name = 'vm-lab-col1' }
      [pscustomobject]@{ Role = 'Database'; Name = 'vm-lab-db' }
    )
  }
  It 'removes only the VMs of the roles asked for' {
    $p = Get-SsuxCleanupPlan -Role Collector -Existing $script:existing -ResourceGroupName 'rg'
    $p.Scope | Should -Be 'Vm'
    $p.Target | Should -Be @('vm-lab-col1', 'vm-lab-col2')
  }
  It 'warns before removing the Database a Hub uses' {
    (Get-SsuxCleanupPlan -Role Database -Existing $script:existing -ResourceGroupName 'rg').Notes | Should -Match 'Point the Hub back'
  }
  It 'removes the whole environment for the Hub' {
    $p = Get-SsuxCleanupPlan -Role Hub, Collector -Existing $script:existing -ResourceGroupName 'rg-lab-stratusphere'
    $p.Scope | Should -Be 'ResourceGroup'
    $p.Notes -join ' ' | Should -Match 'soft-deleted.*recovers'
  }
  It 'removes Collectors without -DiscardLastCopy: they hold no data of their own' {
    (Get-SsuxCleanupPlan -Role Collector -Existing $script:existing -ResourceGroupName 'rg').Blocked | Should -BeNullOrEmpty
  }
  It 'refuses the Hub or the Database, the only copy of the assessment data, without -DiscardLastCopy' {
    (Get-SsuxCleanupPlan -Role Hub -Existing $script:existing -ResourceGroupName 'rg').Blocked | Should -Match 'only copy.*-DiscardLastCopy'
    (Get-SsuxCleanupPlan -Role Database -Existing $script:existing -ResourceGroupName 'rg').Blocked | Should -Match 'Database'
    (Get-SsuxCleanupPlan -Role Hub -Existing $script:existing -ResourceGroupName 'rg' -DiscardLastCopy).Blocked | Should -BeNullOrEmpty
  }
}

Describe 'Get-SsuxRandomPassword and summary' {
  It 'meets the VM password rules and differs each time' {
    $a = Get-SsuxRandomPassword
    $a.Length | Should -Be 28
    $a | Should -MatchExactly '[A-Z]'; $a | Should -MatchExactly '[a-z]'; $a | Should -Match '[0-9]'; $a | Should -Match '#'
    Get-SsuxRandomPassword | Should -Not -Be $a
  }
  It 'fails when any check failed' {
    (Get-SsuxApplianceSummary -Result @([pscustomobject]@{ Status = 'PASS' }, [pscustomobject]@{ Status = 'WARN' })).Result | Should -Be 'PASS'
    (Get-SsuxApplianceSummary -Result @([pscustomobject]@{ Status = 'FAIL' })).Result | Should -Be 'FAIL'
  }
}
