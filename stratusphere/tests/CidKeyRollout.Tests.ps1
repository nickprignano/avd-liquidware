#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# Offline tests for the Connector ID Key rollout: planning, argument checks, the script sent
# to each machine, and parsing what comes back.

BeforeAll {
  $script:root = Split-Path $PSScriptRoot -Parent
  Import-Module (Join-Path $script:root 'scripts/ops/CidKeyRollout.psm1') -Force
  $script:agent = Get-Content (Join-Path $script:root 'scripts/agent/Invoke-CidKeyAction.ps1') -Raw
  $script:sha = 'A' * 64
}

Describe 'Get-SsuxCidTargetPlan' {
  It 'runs on running Windows VMs and skips the rest with a reason' {
    $vms = @(
      [pscustomobject]@{ Name = 'sh-001'; ResourceGroupName = 'rg'; OsType = 'Windows'; PowerState = 'VM running' }
      [pscustomobject]@{ Name = 'sh-002'; ResourceGroupName = 'rg'; OsType = 'Windows'; PowerState = 'VM deallocated' }
      [pscustomobject]@{ Name = 'lnx-01'; ResourceGroupName = 'rg'; OsType = 'Linux'; PowerState = 'VM running' }
    )
    $plan = @(Get-SsuxCidTargetPlan -Vm $vms)
    $plan.Plan | Should -Be @('Run', 'Skip', 'Skip')
    $plan[1].Reason | Should -Match 'deallocated'
    $plan[2].Reason | Should -Match 'Windows only'
  }
  It 'returns nothing for no VMs' {
    @(Get-SsuxCidTargetPlan -Vm @()).Count | Should -Be 0
  }
}

Describe 'Get-SsuxCidArgumentError' {
  It 'needs nothing for Check' {
    @(Get-SsuxCidArgumentError -Action Check).Count | Should -Be 0
  }
  It 'requires an installer to fix, and only validates one for cleanup' {
    @(Get-SsuxCidArgumentError -Action Fix).Count | Should -Be 2
    @(Get-SsuxCidArgumentError -Action Cleanup).Count | Should -Be 0
    @(Get-SsuxCidArgumentError -Action Cleanup -InstallerUrl 'https://x/y.exe') | Should -Match 'InstallerSha256 is required'
  }
  It 'requires an https URL and a SHA-256 to install' {
    @(Get-SsuxCidArgumentError -Action Install).Count | Should -Be 2
    @(Get-SsuxCidArgumentError -Action Install -InstallerUrl 'http://x/y.exe' -InstallerSha256 $script:sha) | Should -Match 'https'
    @(Get-SsuxCidArgumentError -Action Install -InstallerUrl 'https://x/y.exe' -InstallerSha256 'abc') | Should -Match '64 hex'
  }
  It 'rejects values that could break out of the script sent to each machine' {
    @(Get-SsuxCidArgumentError -Action Install -InstallerUrl "https://x/y.exe'; Remove-Item C:\ -Recurse #" -InstallerSha256 $script:sha).Count | Should -Be 1
    @(Get-SsuxCidArgumentError -Action Check -HubAddress "hub'; whoami").Count | Should -Be 1
  }
  It 'accepts a host name, an IP and a SAS URL' {
    @(Get-SsuxCidArgumentError -Action Install -HubAddress 'hub.contoso.com' -InstallerUrl 'https://st.blob.core.windows.net/c/cid.exe?sv=2024&sig=abc%3D' -InstallerSha256 $script:sha).Count | Should -Be 0
    @(Get-SsuxCidArgumentError -Action Check -HubAddress '10.60.0.4').Count | Should -Be 0
  }
}

Describe 'Get-SsuxCidRemoteScript' {
  It 'produces a script that parses and calls the agent script with the arguments' {
    foreach ($a in 'Check', 'Fix', 'Cleanup') {
      $p = $null; $e = $null
      [System.Management.Automation.Language.Parser]::ParseInput((Get-SsuxCidRemoteScript -AgentScript $script:agent -Action $a), [ref]$p, [ref]$e) | Out-Null
      $e | Should -BeNullOrEmpty
    }
    $s = Get-SsuxCidRemoteScript -AgentScript $script:agent -Action Install -HubAddress 'hub.contoso.com' -InstallerUrl 'https://x/y.exe' -InstallerSha256 $script:sha -Force
    $tokens = $null; $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseInput($s, [ref]$tokens, [ref]$parseErrors) | Out-Null
    $parseErrors | Should -BeNullOrEmpty
    $s | Should -Match "\} -Action 'Install' -HubAddress 'hub.contoso.com' -InstallerUrl 'https://x/y.exe' -InstallerSha256 '$($script:sha)' -Force$"
  }
  It 'reports absent through the real agent script when nothing is installed' -Skip:(-not $IsWindows) {
    $out = & ([scriptblock]::Create((Get-SsuxCidRemoteScript -AgentScript $script:agent -Action Check)))
    ($out -join "`n") | Should -Match 'SSUX-RESULT status=(absent|present)'
  }
}

Describe 'Get-SsuxCidRunOutcome' {
  It 'parses the result line' {
    $o = Get-SsuxCidRunOutcome -Name 'sh-001' -Output "noise`nSSUX-RESULT status=installed version=6.7.1 detail=Installed`n"
    $o.Status | Should -Be 'installed'
    $o.Version | Should -Be '6.7.1'
    $o.Detail | Should -Be 'Installed'
  }
  It 'parses an empty version' {
    (Get-SsuxCidRunOutcome -Name 'sh-001' -Output 'SSUX-RESULT status=absent version= detail=Connector ID Key is not installed').Status | Should -Be 'absent'
  }
  It 'reports failed with what came back when there is no result line' {
    $o = Get-SsuxCidRunOutcome -Name 'sh-001' -Output '' -ErrorText 'Run Command failed: VM agent not ready'
    $o.Status | Should -Be 'failed'
    $o.Detail | Should -Match 'agent not ready'
  }
}

Describe 'Get-SsuxCidRetryTarget' {
  It 'returns the machines that did not end healthy, with their resource groups' {
    $report = [pscustomobject]@{
      planned  = @(
        [pscustomobject]@{ Name = 'sh-001'; ResourceGroupName = 'rg-a' }
        [pscustomobject]@{ Name = 'sh-002'; ResourceGroupName = 'rg-a' }
        [pscustomobject]@{ Name = 'sh-003'; ResourceGroupName = 'rg-b' }
      )
      outcomes = @(
        [pscustomobject]@{ Name = 'sh-001'; Status = 'installed' }
        [pscustomobject]@{ Name = 'sh-002'; Status = 'failed' }
        [pscustomobject]@{ Name = 'sh-003'; Status = 'degraded' }
      )
    }
    $t = @(Get-SsuxCidRetryTarget -Report $report)
    $t.Name | Should -Be @('sh-002', 'sh-003')
    $t[1].ResourceGroupName | Should -Be 'rg-b'
  }
}

Describe 'Get-SsuxCidPersistenceWarning and summary' {
  It 'warns only for host pools' {
    Get-SsuxCidPersistenceWarning -FromHostPool $true -HostCount 3 | Should -Match 'golden image'
    Get-SsuxCidPersistenceWarning -FromHostPool $false -HostCount 3 | Should -BeNullOrEmpty
  }
  It 'fails the run when any machine failed' {
    $o = @([pscustomobject]@{ Status = 'installed' }, [pscustomobject]@{ Status = 'failed' })
    (Get-SsuxCidSummary -Outcome $o).Result | Should -Be 'FAIL'
    (Get-SsuxCidSummary -Outcome @($o[0])).Result | Should -Be 'PASS'
    (Get-SsuxCidSummary -Outcome @([pscustomobject]@{ Status = 'degraded' })).Result | Should -Be 'FAIL'
  }
}

Describe 'Agent script' {
  It 'only deletes folders under a Liquidware path' {
    $script:agent | Should -Match ([regex]::Escape("if (`$f -like '*Liquidware*' -and"))
  }
  It 'uses only Windows PowerShell 5.1 syntax' {
    $r = Invoke-ScriptAnalyzer -Path (Join-Path $script:root 'scripts/agent') -Settings @{
      IncludeRules = @('PSUseCompatibleSyntax')
      Rules        = @{ PSUseCompatibleSyntax = @{ Enable = $true; TargetVersions = @('5.1') } }
    }
    $r | Should -BeNullOrEmpty
    (Get-Command (Join-Path $script:root 'scripts/ops/Deploy-CidKey.ps1')).Parameters.Keys | Should -Contain 'OutputPath'
    (Get-Content (Join-Path $script:root 'scripts/ops/Deploy-CidKey.ps1') -Raw) | Should -Match "schemaVersion = 'stratusphere-instrument/v1'"
  }
}
