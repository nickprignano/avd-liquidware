# Planning behind Deploy-Stratusphere.ps1: which roles to deploy, how healthy the
# deployed appliances are, and what Fix and Cleanup would do. Every function takes data
# already read from Azure and returns objects, so it is tested offline.
# Personal project, not for production use. Provided as is, without warranty of any kind. Not affiliated with the author's employer, with Liquidware or with Microsoft.

# Defaults that must match bicep/main.bicep (tests/Template.Tests.ps1 checks them).
$script:defaultIp = @{ Hub = '10.60.0.4'; Database = '10.60.0.5' }
$script:collectorIps = @('10.60.0.10', '10.60.0.11', '10.60.0.12', '10.60.0.13')
$script:roleOrder = @{ Hub = 0; Database = 1; Collector = 2 }

function Get-SsuxApplianceDefault {
  # The names and static IPs the template gives each appliance.
  [CmdletBinding()]
  param()
  [pscustomobject]@{ Ip = $script:defaultIp; CollectorIps = $script:collectorIps }
}

function Get-SsuxApplianceSpec {
  # The appliances a role set means: one row per VM with its name and expected IP.
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string] $NamePrefix,
    [switch] $Hub,
    [switch] $Database,
    [ValidateRange(0, 4)] [int] $CollectorCount = 0
  )
  if ($Hub) { [pscustomobject]@{ Role = 'Hub'; Name = "vm-$NamePrefix-hub"; PrivateIp = $script:defaultIp.Hub } }
  if ($Database) { [pscustomobject]@{ Role = 'Database'; Name = "vm-$NamePrefix-db"; PrivateIp = $script:defaultIp.Database } }
  for ($i = 1; $i -le $CollectorCount; $i++) {
    [pscustomobject]@{ Role = 'Collector'; Name = "vm-$NamePrefix-col$i"; PrivateIp = $script:collectorIps[$i - 1] }
  }
}

function Get-SsuxApplianceRole {
  # Role of an existing VM, from the tag the template sets (hub, database, collector-N).
  [CmdletBinding()]
  param([AllowEmptyString()] [string] $Tag = '')
  switch -Regex ($Tag) {
    '^hub$' { 'Hub' }
    '^database$' { 'Database' }
    '^collector-\d+$' { 'Collector' }
  }
}

function Get-SsuxApplianceArgumentError {
  # Values that go into environment variables and the template are validated strictly.
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string] $Action,
    [AllowEmptyCollection()] [string[]] $Role = @(),
    [Parameter(Mandatory)] [string] $NamePrefix,
    [hashtable] $Plan = @{},
    [string] $PeerVnetId = ''
  )
  $errors = @()
  if ($NamePrefix -cnotmatch '^[a-z0-9]{2,8}$') { $errors += "NamePrefix '$NamePrefix' must be 2-8 lowercase letters or digits." }
  foreach ($k in $Plan.Keys) {
    if ($Plan[$k] -and $Plan[$k] -notmatch '^[A-Za-z0-9._-]+$') { $errors += "Not a Marketplace plan name for ${k}: '$($Plan[$k])'" }
  }
  if ($PeerVnetId -and $PeerVnetId -notmatch '^/subscriptions/[0-9a-fA-F-]{36}/resourceGroups/[^/]+/providers/Microsoft\.Network/virtualNetworks/[^/]+$') {
    $errors += 'PeerVnetId must be a virtual network resource ID.'
  }
  if ($Action -eq 'Cleanup' -and @($Role).Count -eq 0) {
    $errors += 'Cleanup needs -Role: Collector or Database removes those appliances; Hub removes the whole environment.'
  }
  $errors
}

function Get-SsuxDeployTarget {
  # What one deployment must contain. The template describes the whole environment, so
  # roles that already exist stay in it (and keep their plan): leaving one out would
  # not remove it, but would leave it out of the outputs and the checks.
  [CmdletBinding()]
  param(
    [AllowEmptyCollection()] [string[]] $Role = @(),
    [ValidateRange(1, 4)] [int] $CollectorCount = 1,
    [hashtable] $Plan = @{},
    # Existing appliances: Role, Name, PlanName.
    [AllowEmptyCollection()] [object[]] $Existing = @()
  )
  $errors = @(); $notes = @()
  $has = @{}
  foreach ($r in 'Hub', 'Database', 'Collector') { $has[$r] = @($Existing | Where-Object Role -eq $r) }

  $want = @{}
  foreach ($r in 'Hub', 'Database', 'Collector') { $want[$r] = ($Role -contains $r) -or $has[$r].Count -gt 0 }
  if (-not $want.Hub -and ($want.Database -or $want.Collector)) {
    $want.Hub = $true
    $notes += 'Database and Collectors report to a Hub, so the Hub is deployed too.'
  }

  $collectors = 0
  if ($want.Collector) {
    $collectors = [Math]::Max($has.Collector.Count, $(if ($Role -contains 'Collector') { $CollectorCount } else { 0 }))
    if ($Role -contains 'Collector' -and $CollectorCount -lt $has.Collector.Count) {
      $notes += "$($has.Collector.Count) Collectors exist; keeping them all. Use -Action Cleanup -Role Collector to remove Collectors."
    }
  }

  $plans = @{}
  foreach ($r in 'Hub', 'Database', 'Collector') {
    if (-not $want[$r]) { continue }
    $existingPlans = @($has[$r] | ForEach-Object PlanName | Where-Object { $_ } | Sort-Object -Unique)
    $asked = $Plan[$r]
    if ($asked -and $existingPlans.Count -gt 0 -and $existingPlans -notcontains $asked) {
      $errors += "The $r runs plan '$($existingPlans -join ', ')', not '$asked'. A VM's Marketplace plan can't change: clean up that role first, or drop -${r}Plan."
    }
    $plans[$r] = $(if ($asked) { $asked } elseif ($existingPlans.Count -gt 0) { $existingPlans[0] } else { '' })
    if (-not $plans[$r]) { $errors += "-${r}Plan is required to deploy the $r. The preflight lists the plans offered in your region." }
  }

  [pscustomobject]@{
    DeployHub      = [bool]$want.Hub
    DeployDatabase = [bool]$want.Database
    CollectorCount = $collectors
    Plan           = $plans
    Notes          = $notes
    Errors         = $errors
  }
}

function Get-SsuxApplianceHealth {
  # One result per expected appliance. Remedy says what Fix does: start, deploy
  # (the template puts back a missing VM, a dynamic IP or a failed provisioning) or
  # manual (nothing safe to do automatically).
  [CmdletBinding()]
  param(
    [AllowEmptyCollection()] [object[]] $Spec = @(),
    # Name, ProvisioningState, PowerState, PrivateIp, IpAllocation
    [AllowEmptyCollection()] [object[]] $Vm = @()
  )
  foreach ($s in $Spec) {
    $v = @($Vm | Where-Object Name -eq $s.Name) | Select-Object -First 1
    $check = "$($s.Role.ToLower()) $($s.Name)"
    if (-not $v) {
      [pscustomobject]@{ Status = 'FAIL'; Check = $check; Detail = 'VM not found'; Remedy = 'deploy'; Name = $s.Name }
      continue
    }
    $problems = @(); $remedy = ''
    if ($v.ProvisioningState -eq 'Failed') { $problems += 'provisioning failed'; $remedy = 'deploy' }
    if ($v.PrivateIp -ne $s.PrivateIp) { $problems += "IP is $($v.PrivateIp), expected $($s.PrivateIp)"; $remedy = 'deploy' }
    elseif ($v.IpAllocation -ne 'Static') { $problems += 'IP is not static'; $remedy = 'deploy' }
    if ($v.PowerState -in 'VM deallocated', 'VM stopped') {
      $problems += "power state '$($v.PowerState)'"
      if (-not $remedy) { $remedy = 'start' }
    }
    elseif ($v.PowerState -ne 'VM running') {
      [pscustomobject]@{ Status = 'WARN'; Check = $check; Detail = "Power state '$($v.PowerState)'; check again shortly"; Remedy = ''; Name = $s.Name }
      continue
    }
    if ($problems.Count -gt 0) {
      [pscustomobject]@{ Status = 'FAIL'; Check = $check; Detail = ($problems -join '; '); Remedy = $remedy; Name = $s.Name }
    }
    else {
      [pscustomobject]@{ Status = 'PASS'; Check = $check; Detail = "Running at $($v.PrivateIp)"; Remedy = ''; Name = $s.Name }
    }
  }
}

function Get-SsuxNetworkHealth {
  # NSG rules the roles need, and explicit egress on the appliance subnet.
  [CmdletBinding()]
  param(
    [AllowEmptyCollection()] [string[]] $RuleName = @(),
    [bool] $NeedPostgres,
    [bool] $HasNatGateway,
    $DefaultOutboundAccess
  )
  $need = @('Allow-Https-Callbacks-And-Console', 'Deny-Other-Inbound')
  if ($NeedPostgres) { $need += 'Allow-Postgres-Between-Appliances' }
  $missing = @($need | Where-Object { $RuleName -notcontains $_ })
  if ($missing.Count -gt 0) {
    [pscustomobject]@{ Status = 'FAIL'; Check = 'nsg'; Detail = 'Missing rules: ' + ($missing -join ', '); Remedy = 'deploy'; Name = '' }
  }
  else {
    [pscustomobject]@{ Status = 'PASS'; Check = 'nsg'; Detail = 'Rules in place: ' + ($need -join ', '); Remedy = ''; Name = '' }
  }
  if (-not $HasNatGateway -or $DefaultOutboundAccess -ne $false) {
    [pscustomobject]@{ Status = 'FAIL'; Check = 'egress'; Detail = 'Subnet should have default outbound access off and a NAT Gateway'; Remedy = 'deploy'; Name = '' }
  }
  else {
    [pscustomobject]@{ Status = 'PASS'; Check = 'egress'; Detail = 'NAT Gateway, default outbound access off'; Remedy = ''; Name = '' }
  }
}

function Get-SsuxVaultHealth {
  # The vault holds the only copy of the appliance password.
  [CmdletBinding()]
  param(
    [string] $VaultName,
    [string] $RemovedVaultName,
    [AllowEmptyCollection()] [string[]] $SecretName = @(),
    [bool] $AppliancesExist
  )
  if (-not $VaultName) {
    if ($RemovedVaultName) {
      return [pscustomobject]@{ Status = 'FAIL'; Check = 'key-vault'; Detail = "$RemovedVaultName is soft-deleted; Fix recovers it with its secrets"; Remedy = 'recover-vault'; Name = $RemovedVaultName }
    }
    if ($AppliancesExist) {
      return [pscustomobject]@{ Status = 'FAIL'; Check = 'key-vault'; Detail = 'No Key Vault, so the appliance password is lost. Reset it from the appliance console, then redeploy.'; Remedy = 'manual'; Name = '' }
    }
    return [pscustomobject]@{ Status = 'FAIL'; Check = 'key-vault'; Detail = 'No Key Vault'; Remedy = 'deploy'; Name = '' }
  }
  $missing = @('appliance-admin-username', 'appliance-admin-password' | Where-Object { $SecretName -notcontains $_ })
  if ($missing.Count -gt 0) {
    $remedy = $(if ($AppliancesExist) { 'manual' } else { 'deploy' })
    return [pscustomobject]@{ Status = 'FAIL'; Check = 'key-vault'; Detail = "$VaultName is missing " + ($missing -join ', '); Remedy = $remedy; Name = $VaultName }
  }
  [pscustomobject]@{ Status = 'PASS'; Check = 'key-vault'; Detail = "$VaultName holds the appliance credential"; Remedy = ''; Name = $VaultName }
}

function Get-SsuxTermsHealth {
  # Marketplace terms per plan in use; a redeploy fails without them.
  [CmdletBinding()]
  param([AllowEmptyCollection()] [object[]] $Terms = @())
  foreach ($t in $Terms) {
    if ($t.Accepted) { [pscustomobject]@{ Status = 'PASS'; Check = 'marketplace-terms'; Detail = "Accepted for $($t.Plan)"; Remedy = ''; Name = $t.Plan } }
    else { [pscustomobject]@{ Status = 'FAIL'; Check = 'marketplace-terms'; Detail = "Not accepted for $($t.Plan)"; Remedy = 'accept-terms'; Name = $t.Plan } }
  }
}

function Get-SsuxFixPlan {
  # Ordered steps for -Action Fix: terms and the vault first (a deployment needs both),
  # then one deployment for everything the template puts back, then start what is stopped.
  [CmdletBinding()]
  param([AllowEmptyCollection()] [object[]] $Result = @())
  $failed = @($Result | Where-Object { $_.Status -eq 'FAIL' })
  foreach ($r in @($failed | Where-Object Remedy -eq 'accept-terms')) { [pscustomobject]@{ Step = 'accept-terms'; Target = $r.Name } }
  foreach ($r in @($failed | Where-Object Remedy -eq 'recover-vault')) { [pscustomobject]@{ Step = 'recover-vault'; Target = $r.Name } }
  if (@($failed | Where-Object Remedy -eq 'deploy').Count -gt 0) { [pscustomobject]@{ Step = 'deploy'; Target = '' } }
  foreach ($r in @($failed | Where-Object Remedy -eq 'start')) { [pscustomobject]@{ Step = 'start'; Target = $r.Name } }
  foreach ($r in @($failed | Where-Object Remedy -eq 'manual')) { [pscustomobject]@{ Step = 'manual'; Target = "$($r.Check): $($r.Detail)" } }
}

function Get-SsuxCleanupPlan {
  # Collector or Database: remove those VMs (their disks and NICs go with them).
  # Hub: remove the whole environment, since nothing else works without it.
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string[]] $Role,
    # Existing appliances: Role, Name
    [AllowEmptyCollection()] [object[]] $Existing = @(),
    [Parameter(Mandatory)] [string] $ResourceGroupName
  )
  if ($Role -contains 'Hub') {
    return [pscustomobject]@{
      Scope = 'ResourceGroup'; Target = @($ResourceGroupName)
      Notes = @(
        "Removes $ResourceGroupName and everything in it, and the peering on the other VNet if there is one."
        'The Key Vault stays soft-deleted for 7 days (purge protection); the next Deploy recovers it with the same password.'
      )
    }
  }
  $vms = @($Existing | Where-Object { $Role -contains $_.Role } | Sort-Object { $script:roleOrder[$_.Role] }, Name | ForEach-Object Name)
  $notes = @()
  if ($Role -contains 'Database' -and @($Existing | Where-Object Role -eq 'Hub').Count -gt 0) {
    $notes += 'Point the Hub back at its own database first (Hub Administration > Database), or it loses its data store.'
  }
  [pscustomobject]@{ Scope = 'Vm'; Target = $vms; Notes = $notes }
}

function Get-SsuxRandomPassword {
  # 24 random letters and digits, plus one of each character class the VM requires.
  [CmdletBinding()]
  param()
  $chars = [char[]]'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789'
  $bytes = [byte[]]::new(24)
  [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
  (-join ($bytes | ForEach-Object { $chars[$_ % $chars.Length] })) + '#Aa1'
}

function Get-SsuxApplianceSummary {
  [CmdletBinding()]
  param([AllowEmptyCollection()] [object[]] $Result = @())
  $failed = @($Result | Where-Object Status -eq 'FAIL').Count
  [pscustomobject]@{ Total = @($Result).Count; Failed = $failed; Result = $(if ($failed -gt 0) { 'FAIL' } else { 'PASS' }) }
}

Export-ModuleMember -Function Get-SsuxApplianceDefault, Get-SsuxApplianceSpec, Get-SsuxApplianceRole, Get-SsuxApplianceArgumentError,
Get-SsuxDeployTarget, Get-SsuxApplianceHealth, Get-SsuxNetworkHealth, Get-SsuxVaultHealth, Get-SsuxTermsHealth,
Get-SsuxFixPlan, Get-SsuxCleanupPlan, Get-SsuxRandomPassword, Get-SsuxApplianceSummary
