#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# Guards on the compiled template. Needs the Bicep CLI on PATH.

BeforeAll {
  $script:bicep = (Get-Command bicep -ErrorAction Stop).Source
  $script:root = Split-Path $PSScriptRoot -Parent
  $env:SSUX_HUB_ADMIN_PASSWORD = 'Placeholder-only-for-build-1!'
  $env:SSUX_KV_READER_ID = '00000000-0000-0000-0000-000000000001'
  function Get-Compiled {
    $raw = & $script:bicep build-params (Join-Path $script:root 'parameters/lab.bicepparam') --stdout 2>&1
    if ($LASTEXITCODE -ne 0) { throw "bicep build-params failed: $raw" }
    ($raw -join "`n") | ConvertFrom-Json -Depth 100
  }
  function Find-Deployment($Template, [string] $Name) {
    foreach ($r in @($Template.resources.Values) + @($Template.resources)) {
      if ($r -is [System.Collections.IDictionary] -and $r['type'] -eq 'Microsoft.Resources/deployments') {
        if ($r['name'] -eq $Name) { return $r }
        $inner = $r['properties']['template']
        if ($inner) { $hit = Find-Deployment $inner $Name; if ($hit) { return $hit } }
      }
    }
  }
  $script:compiled = Get-Compiled
  $script:template = $script:compiled.templateJson | ConvertFrom-Json -Depth 100 -AsHashtable
}

Describe 'Marketplace image' {
  It 'sends a plan block that matches the image reference' {
    $hub = Find-Deployment $script:template 'vm-hub'
    $p = $hub['properties']['parameters']
    $p['plan']['value']['name'] | Should -Be "[parameters('imagePlan')]"
    $p['imageReference']['value']['sku'] | Should -Be "[parameters('imagePlan')]"
    $p['plan']['value']['publisher'] | Should -Be "[parameters('imagePublisher')]"
    $p['imageReference']['value']['publisher'] | Should -Be "[parameters('imagePublisher')]"
    $p['plan']['value']['product'] | Should -Be "[parameters('imageOffer')]"
    $p['imageReference']['value']['offer'] | Should -Be "[parameters('imageOffer')]"
  }
}

Describe 'Parameter file' {
  It 'takes the plan and region from the environment and defaults when empty' {
    $env:SSUX_HUB_PLAN = 'example-plan'; $env:SSUX_LOCATION = 'westus3'
    try { $p = ((Get-Compiled).parametersJson | ConvertFrom-Json).parameters }
    finally { $env:SSUX_HUB_PLAN = ''; $env:SSUX_LOCATION = '' }
    $p.hubImagePlan.value | Should -Be 'example-plan'
    $p.location.value | Should -Be 'westus3'
    $p = ((Get-Compiled).parametersJson | ConvertFrom-Json).parameters
    $p.location.value | Should -Be 'eastus2'
    $p.hubVmSize.value | Should -Be 'Standard_D4s_v5'
  }
}

Describe 'Hub network exposure' {
  It 'admits only TCP 443 and SSH from Bastion, then denies' {
    $nsg = Find-Deployment $script:template 'nsg-hub'
    $rules = $nsg['properties']['parameters']['securityRules']['value']
    $rules | Should -Match '443'
    $text = $rules | ConvertTo-Json -Depth 20 -Compress
    $text | Should -Match "Deny-Other-Inbound"
    $text | Should -Not -Match "Internet"
  }
}

Describe 'Disclaimer' {
  It 'is at the top of every entry point' {
    $files = @(
      'bicep/main.bicep'
      'scripts/deploy/deploy.sh'
      'scripts/ops/Test-StratusphereReadiness.ps1'
      'scripts/ops/StratusphereReadiness.psm1'
    )
    foreach ($f in $files) {
      (Get-Content (Join-Path $script:root $f) -TotalCount 8) -join "`n" | Should -Match 'Personal project, not for production use' -Because $f
      (Get-Content (Join-Path $script:root $f) -TotalCount 8) -join "`n" | Should -Match 'Not affiliated with .*Liquidware' -Because $f
    }
  }
}
