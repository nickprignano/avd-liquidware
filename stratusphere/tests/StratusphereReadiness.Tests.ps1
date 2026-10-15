#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# Offline tests for the preflight checks: each takes data shaped like the Az cmdlet output.

BeforeAll {
  Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts/ops/StratusphereReadiness.psm1') -Force
}

Describe 'Get-SsuxPlanCheck' {
  It 'fails and lists the plans when none is chosen' {
    $r = Get-SsuxPlanCheck -AvailablePlans 'plan-a', 'plan-b' -Location eastus2
    $r.Status | Should -Be 'FAIL'
    $r.Detail | Should -Match 'plan-a, plan-b'
  }
  It 'fails when the chosen plan is not offered' {
    (Get-SsuxPlanCheck -AvailablePlans 'plan-a' -Plan 'plan-z' -Location eastus2).Status | Should -Be 'FAIL'
  }
  It 'fails clearly when nothing is offered in the region' {
    $r = Get-SsuxPlanCheck -AvailablePlans @() -Plan 'plan-a' -Location eastus2
    $r.Status | Should -Be 'FAIL'
    $r.Detail | Should -Match 'No Stratusphere plans'
  }
  It 'passes for an offered plan' {
    (Get-SsuxPlanCheck -AvailablePlans 'plan-a', 'plan-b' -Plan 'plan-b' -Location eastus2).Status | Should -Be 'PASS'
  }
}

Describe 'Get-SsuxImagePlanCheck' {
  It 'fails when the image has no purchase plan' {
    (Get-SsuxImagePlanCheck -PurchasePlan $null -Version '1.0.0').Status | Should -Be 'FAIL'
  }
  It 'passes when it has one' {
    (Get-SsuxImagePlanCheck -PurchasePlan ([pscustomobject]@{ Name = 'plan-a' }) -Version '1.0.0').Status | Should -Be 'PASS'
  }
}

Describe 'Get-SsuxQuotaCheck' {
  BeforeAll {
    function New-Usage($name, $current, $limit) { [pscustomobject]@{ Name = [pscustomobject]@{ Value = $name }; CurrentValue = $current; Limit = $limit } }
  }
  It 'passes with room in both the region and the family' {
    $u = @((New-Usage 'cores' 10 100), (New-Usage 'standardDSv5Family' 0 20))
    @(Get-SsuxQuotaCheck -VCpusNeeded 4 -Family 'standardDSv5Family' -Usage $u).Status | Should -Be @('PASS', 'PASS')
  }
  It 'fails when the family is full' {
    $u = @((New-Usage 'cores' 10 100), (New-Usage 'standardDSv5Family' 18 20))
    (@(Get-SsuxQuotaCheck -VCpusNeeded 4 -Family 'standardDSv5Family' -Usage $u) | Where-Object Check -eq 'quota-standardDSv5Family').Status | Should -Be 'FAIL'
  }
  It 'warns when a usage row is missing' {
    (@(Get-SsuxQuotaCheck -VCpusNeeded 4 -Family 'standardDSv5Family' -Usage @()) | Select-Object -First 1).Status | Should -Be 'WARN'
  }
}

Describe 'Get-SsuxVmSizeCheck' {
  It 'fails when the size is not offered' {
    (Get-SsuxVmSizeCheck -Sku $null -VmSize Standard_D4s_v5 -Location eastus2).Status | Should -Be 'FAIL'
  }
  It 'fails when the size is restricted for the subscription' {
    $sku = [pscustomobject]@{ Restrictions = @([pscustomobject]@{ ReasonCode = 'NotAvailableForSubscription'; Type = 'Location' }) }
    (Get-SsuxVmSizeCheck -Sku $sku -VmSize Standard_D4s_v5 -Location eastus2).Status | Should -Be 'FAIL'
  }
  It 'passes when available' {
    (Get-SsuxVmSizeCheck -Sku ([pscustomobject]@{ Restrictions = @() }) -VmSize Standard_D4s_v5 -Location eastus2).Status | Should -Be 'PASS'
  }
}
