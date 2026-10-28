#requires -Version 7.4
<#
.SYNOPSIS
  Deploys ProfileUnity, FlexApp, Stratusphere and CommandCTRL against an existing avd-landing-zone landing zone.
  Personal project, not for production use. Provided as is, without warranty of any kind. Not affiliated with the author's employer, with Liquidware or with Microsoft.

.DESCRIPTION
  One entry point for the whole tier (docs/deploy-spec.md). -Component picks what, -Action what to do:
    Plan       (default) what would change. Changes nothing.
    Check      what exists and whether it is healthy. Ends with RESULT PASS or FAIL.
    Deploy     ProfileUnity and FlexApp: Plan, then (after you confirm) the template, then the console
               download and hash check by Run Command when output/media.lock.json has the console.
    Configure  session hosts via drained Run Command (Sync-LiquidwareHosts.ps1).
    Promote    staged ProfileUnity configuration or FlexApp assignment on -Ring QA|All.
    Fix        Check, then repairs what it can.
    Cleanup    removes the tier peering and DNS links on the landing zone, then the tier resource group;
               then teardown evidence. Asks first; -Force skips; -WhatIf lists.

  Plan and Check are read-only. Every action writes a JSON report to output/ (git-ignored).
  What-if needs the Bicep CLI (Cloud Shell has it).

.EXAMPLE
  ./scripts/Deploy-LiquidwareTier.ps1 -NamePrefix avdlz -Environment dev -Component ProfileUnity,FlexApp,Stratusphere
.EXAMPLE
  ./scripts/Deploy-LiquidwareTier.ps1 -NamePrefix avdlz -Environment dev -Component ProfileUnity -Action Deploy
.EXAMPLE
  ./scripts/Deploy-LiquidwareTier.ps1 -NamePrefix avdlz -Environment dev -Component ProfileUnity -Action Cleanup -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
  [Parameter(Mandatory)] [string] $NamePrefix,
  [Parameter(Mandatory)] [string] $Environment,
  [Parameter(Mandatory)] [string[]] $Component,
  [ValidateSet('Plan', 'Check', 'Deploy', 'Configure', 'Promote', 'Fix', 'Cleanup')] [string] $Action = 'Plan',
  [string] $TierAddressPrefix = '10.61.0.0/24',
  [string] $SubscriptionId = '',
  # Object ID of the landing zone users group, when discovery finds none or several. Never commit it.
  [string] $UsersGroupId = '',
  # The media lock Publish-LiquidwareMedia.ps1 writes (default output/media.lock.json).
  [string] $MediaLockPath = '',
  # Where the JSON report goes (default output/, git-ignored).
  [string] $ReportDirectory = '',
  # Deploy and Cleanup without asking.
  [switch] $Force,
  # Cleanup: remove the tier resource group although it holds the only copy of the tier's data
  # (decision 0016 in avd-second-brain). -Force never implies it.
  [switch] $DiscardLastCopy,
  [switch] $Bastion,
  [switch] $Portability,
  [switch] $ApplicationRestrictions,
  [switch] $Packaging,
  [ValidateSet('QA', 'All')] [string] $Ring = 'QA',
  [string] $WindowEnd = ''
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'LiquidwareTier.psm1') -Force
$reportDir = $(if ($ReportDirectory) { $ReportDirectory } else { Join-Path $PSScriptRoot '../output' })

$argErrors = @(Get-LwArgumentError -NamePrefix $NamePrefix -Environment $Environment -Component $Component -TierAddressPrefix $TierAddressPrefix)
if ($argErrors.Count -gt 0) {
  $argErrors | ForEach-Object { Write-Host "FAIL   $_" }
  Write-Host 'RESULT FAIL invalid arguments'
  exit 1
}

foreach ($m in 'Az.Accounts', 'Az.Resources', 'Az.Network', 'Az.Compute', 'Az.KeyVault', 'Az.PrivateDns') {
  if (-not (Get-Module -ListAvailable -Name $m)) {
    Write-Host "Installing $m from the PowerShell Gallery ..."
    Install-Module $m -Scope CurrentUser -Force -AllowClobber
  }
  Import-Module $m
}
if ($SubscriptionId) { $null = Set-AzContext -SubscriptionId $SubscriptionId }
$context = Get-AzContext
if (-not $context) { Write-Host 'Not signed in. Run Connect-AzAccount (Cloud Shell is already signed in).'; exit 2 }

$names = Get-LwName -NamePrefix $NamePrefix -Environment $Environment
Write-Host "Subscription: $($context.Subscription.Name)   Landing zone: $($names.Base)   Components: $($Component -join ', ')   Action: $Action   Ring: $Ring"

$results = [System.Collections.Generic.List[object]]::new()
function Add-Result($r) {
  foreach ($x in @($r)) {
    if (-not $x) { continue }
    $results.Add($x)
    $hint = $(if ($x.Recommendation -and $x.Status -in 'FAIL', 'WARN') { "  [fix: $($x.Recommendation)]" } else { '' })
    Write-Host ("{0,-6} {1,-26} {2}{3}" -f $x.Status, $x.Check, $x.Detail, $hint)
  }
}
# The JSON report every action leaves in output/ (git-ignored: it holds names from the tenant), then the result line.
function Complete-Run {
  $out = $reportDir
  # Written under -WhatIf too: the report is the record of what was listed.
  if (-not (Test-Path $out)) { $null = New-Item -ItemType Directory -Path $out -Force -WhatIf:$false }
  $file = Join-Path $out ("{0}-{1}-{2}.json" -f $Action.ToLower(), $names.Base, (Get-Date -AsUTC -Format 'yyyyMMddTHHmmssZ'))
  [pscustomobject]@{ action = $Action; landingZone = $names.Base; components = $Component; ring = $Ring; at = (Get-Date -AsUTC -Format o); results = $results } |
    ConvertTo-Json -Depth 5 | Set-Content -Path $file -Encoding utf8NoBOM -WhatIf:$false
  Write-Host "Report: $file"
  $fails = @($results | Where-Object Status -eq 'FAIL')
  if ($fails.Count -gt 0) { Write-Host "RESULT FAIL $($fails.Count) check(s) failed"; exit 1 }
  Write-Host 'RESULT PASS'
  exit 0
}
function Confirm-Step {
  # -WhatIf lists and does nothing; -Force skips the question; otherwise the operator types the name.
  [CmdletBinding(SupportsShouldProcess)]
  param([string] $Target, [string] $What, [switch] $Force)
  if (-not $PSCmdlet.ShouldProcess($Target, $What)) { return $false }
  if ($Force) { return $true }
  (Read-Host "$What on $Target. Type $Target to go ahead") -ceq $Target
}

# Actions not applicable to a component fail before anything is read or changed.
$summary = @(Get-LwPlanSummary -Component $Component -Action $Action)
if (@($summary | Where-Object Status -eq 'FAIL').Count -gt 0) {
  Add-Result $summary
  Complete-Run
}

# ---------- Reading the landing zone ----------
Write-Host 'Reading the landing zone (resource groups, resources, spoke VNet) ...'
$groups = @(Get-AzResourceGroup | Select-Object -ExpandProperty ResourceGroupName)
$resources = @()
foreach ($g in $names.ResourceGroups.Values) {
  if ($groups -contains $g) { $resources += @(Get-AzResource -ResourceGroupName $g) }
}
$vnet = $null
$az = Get-AzVirtualNetwork -ResourceGroupName $names.ResourceGroups.Network -Name $names.Vnet -ErrorAction SilentlyContinue
if ($az) {
  $vnet = [pscustomobject]@{
    Id              = $az.Id
    Location        = $az.Location
    AddressPrefixes = @($az.AddressSpace.AddressPrefixes)
    Subnets         = @($az.Subnets | ForEach-Object { [pscustomobject]@{ Name = $_.Name; AddressPrefix = @($_.AddressPrefix)[0] } })
    Peerings        = @($az.VirtualNetworkPeerings | Where-Object { $_ } | ForEach-Object {
        [pscustomobject]@{ Name = $_.Name; RemoteVnetId = $_.RemoteVirtualNetwork.Id; RemoteAddressPrefixes = @($_.RemoteVirtualNetworkAddressSpace.AddressPrefixes) }
      })
  }
}
$lz = Get-LwLandingZone -NamePrefix $NamePrefix -Environment $Environment -ResourceGroup $groups -Resource $resources -Vnet $vnet

# ---------- Cleanup: only the tier's own names, even when the landing zone is half gone ----------
function Read-TierLeftover {
  $links = @()
  if ((@(Get-AzResourceGroup | Select-Object -ExpandProperty ResourceGroupName)) -contains $names.ResourceGroups.Network) {
    foreach ($z in @(Get-AzPrivateDnsZone -ResourceGroupName $names.ResourceGroups.Network)) {
      $links += @(Get-AzPrivateDnsVirtualNetworkLink -ResourceGroupName $names.ResourceGroups.Network -ZoneName $z.Name | ForEach-Object {
          [pscustomobject]@{ Name = $_.Name; ZoneName = $z.Name; VirtualNetworkId = $_.VirtualNetworkId; ResourceId = $_.ResourceId }
        })
    }
  }
  $spoke = Get-AzVirtualNetwork -ResourceGroupName $names.ResourceGroups.Network -Name $names.Vnet -ErrorAction SilentlyContinue
  [pscustomobject]@{
    TierGroupExists = (@(Get-AzResourceGroup | Select-Object -ExpandProperty ResourceGroupName)) -contains $names.TierGroup
    Peering         = @($(if ($spoke) { @($spoke.VirtualNetworkPeerings | Where-Object { $_ } | ForEach-Object { [pscustomobject]@{ Name = $_.Name; RemoteVnetId = $_.RemoteVirtualNetwork.Id } }) }))
    DnsLink         = $links
  }
}

if ($Action -eq 'Cleanup') {
  $before = Read-TierLeftover
  $steps = @(Get-LwCleanupPlan -Names $names -TierGroupExists $before.TierGroupExists -Peering $before.Peering -DnsLink $before.DnsLink)
  if ($steps.Count -eq 0) { Add-Result (Get-LwCheckResult PASS 'cleanup' 'Nothing of the tier is left to remove.' -Category Cleanup) }
  foreach ($st in $steps) { Add-Result (Get-LwCheckResult INFO 'cleanup-step' "$($st.Kind) $($st.Name)$(if ($st.Parent) { " on $($st.Parent)" })" -Category Cleanup) }
  $lastCopy = Get-LwLastCopyCheck -Steps $steps -DiscardLastCopy:$DiscardLastCopy
  if ($lastCopy) { Add-Result $lastCopy }
  # -WhatIf still lists the steps; a real run stops here.
  if ($lastCopy.Status -eq 'FAIL' -and -not $WhatIfPreference) { Complete-Run }
  if ($steps.Count -gt 0 -and (Confirm-Step -Target $names.TierGroup -What "Remove the $($steps.Count) items above" -Force:$Force)) {
    foreach ($st in $steps) {
      try {
        switch ($st.Kind) {
          'Peering' { Remove-AzVirtualNetworkPeering -Name $st.Name -VirtualNetworkName $st.Parent -ResourceGroupName $st.ResourceGroup -Force }
          'DnsLink' { Remove-AzPrivateDnsVirtualNetworkLink -ResourceId $st.ResourceId }
          'ResourceGroup' {
            Write-Host "Removing $($st.Name) (this takes several minutes) ..."
            $null = Remove-AzResourceGroup -Name $st.Name -Force
          }
        }
        Add-Result (Get-LwCheckResult PASS 'cleanup-step' "Removed $($st.Kind) $($st.Name)" -Category Cleanup)
      }
      catch {
        Add-Result (Get-LwCheckResult FAIL 'cleanup-step' "$($st.Kind) $($st.Name): $($_.Exception.Message)" -Recommendation 'Run Cleanup again.' -Category Cleanup)
      }
    }
    $after = Read-TierLeftover
    Add-Result (Get-LwTeardownCheck -Names $names -TierGroupExists $after.TierGroupExists -Peering $after.Peering -DnsLink $after.DnsLink)
    Add-Result (Get-LwCheckResult INFO 'key-vault' 'The tier Key Vault stays soft-deleted for 7 days (purge protection); a Deploy in that time recovers it.' -Category Cleanup)
    Add-Result (Get-LwCheckResult WARN 'entra-kerberos-app' 'Entra Kerberos may leave an app registration named [Storage Account] <config account>.file.core.windows.net (unconfirmed).' -Recommendation 'Look for it in Entra app registrations and delete it if it outlived the account.' -Category Cleanup)
  }
  Complete-Run
}

Add-Result (Get-LwLandingZoneCheck -LandingZone $lz)
if (@($lz.VnetAddressPrefixes).Count -gt 0) {
  Add-Result (Get-LwAddressCheck -TierAddressPrefix $TierAddressPrefix -LandingZone $lz)
}

if ($Component -contains 'Stratusphere' -and @($lz.Missing).Count -eq 0) {
  $ssux = Get-LwStratusphereArgument -LandingZone $lz
  $line = ($ssux.GetEnumerator() | ForEach-Object { if ($_.Value -is [bool]) { if ($_.Value) { "-$($_.Key)" } } else { "-$($_.Key) $($_.Value)" } }) -join ' '
  Add-Result (Get-LwCheckResult INFO 'stratusphere-arguments' "stratusphere/scripts/ops/Test-StratusphereReadiness.ps1 $line" -Category Stratusphere)
  Add-Result (Get-LwStratusphereWindowCheck -WindowEnd $WindowEnd)
}

$profileUnity = @($Component | Where-Object { $_ -in 'ProfileUnity', 'FlexApp' }).Count -gt 0
if ($profileUnity -and $Action -in 'Plan', 'Deploy' -and @($results | Where-Object Status -eq 'FAIL').Count -eq 0) {
  Write-Host 'Reading the users group and the Azure Virtual Desktop service principals ...'
  $assignments = @(Get-AzRoleAssignment -Scope $lz.ProfilesAccountId | ForEach-Object {
      [pscustomobject]@{ ObjectId = $_.ObjectId; ObjectType = $_.ObjectType; RoleDefinitionName = $_.RoleDefinitionName }
    })
  $users = Get-LwUsersGroup -RoleAssignment $assignments -Override $UsersGroupId
  Add-Result $users.Result
  # Azure Virtual Desktop and Azure Virtual Desktop ARM Provider: Microsoft's application IDs, the same in every tenant.
  $avd = @('9cdead84-a844-4324-93f2-b2e6bb768d07', '50e95039-b200-4007-bc97-8d5790743a63' | ForEach-Object {
      (Get-AzADServicePrincipal -ApplicationId $_ -ErrorAction SilentlyContinue).Id
    } | Where-Object { $_ })
  if ($avd.Count -ne 2) {
    Add-Result (Get-LwCheckResult FAIL 'avd-service-principals' "Found $($avd.Count) of the 2 Azure Virtual Desktop service principals." -Recommendation 'Register Microsoft.DesktopVirtualization; the landing zone deploy normally has.' -Category 'Landing zone')
  }
  # The operator uploads installers to media (Storage Blob Data Contributor there, for them only).
  $operator = Get-AzADUser -SignedIn -ErrorAction SilentlyContinue
  if (-not $operator) {
    Add-Result (Get-LwCheckResult FAIL 'operator' 'The signed-in account is not a user, so it cannot be the media operator.' -Recommendation 'Run from Cloud Shell signed in as yourself.' -Category 'ProfileUnity')
  }
  Write-Host 'Reading the console VM and the license secret (management plane) ...'
  $consoleVm = $null
  $licenseSecret = $null
  if ($groups -contains $names.TierGroup) {
    $vm = $(try { Get-AzVM -ResourceGroupName $names.TierGroup -Name $names.ConsoleVm -ErrorAction Stop } catch { $null })
    if ($vm) { $consoleVm = [pscustomobject]@{ Name = $vm.Name; PrincipalId = $(if ($vm.Identity) { $vm.Identity.PrincipalId } else { '' }) } }
    $vault = @(Get-AzResource -ResourceGroupName $names.TierGroup -ResourceType 'Microsoft.KeyVault/vaults') | Select-Object -First 1
    if ($vault) { $licenseSecret = $(try { Get-AzResource -ResourceId "$($vault.ResourceId)/secrets/lw-licstr" -ErrorAction Stop } catch { $null }) }
  }
  $removed = @(Get-AzKeyVault -InRemovedState -ErrorAction SilentlyContinue | ForEach-Object {
      [pscustomobject]@{ VaultName = $_.VaultName; Location = $_.Location; ScheduledPurgeDate = $_.ScheduledPurgeDate }
    })
  $deleted = Get-LwDeletedVault -Names $names -Removed $removed
  Add-Result $deleted.Result
  $state = Get-LwTierState -Console $consoleVm -LicenseSecret $licenseSecret
  Add-Result $state.Result
  if ($operator -and $users.ObjectId -and $avd.Count -eq 2 -and @($results | Where-Object Status -eq 'FAIL').Count -eq 0) {
    $password = $(if (-not $state.ConsoleExists) { Get-LwGeneratedPassword } else { $null })
    $pkgPassword = $(if ($Packaging) { Get-LwGeneratedPassword } else { $null })
    $enableBackup = ($Environment -in 'test', 'prod')
    $params = Get-LwTemplateParameter -LandingZone $lz -TierAddressPrefix $TierAddressPrefix -UsersGroupObjectId $users.ObjectId -AvdServicePrincipalObjectId $avd `
      -OperatorObjectId $operator.Id -TierState $state -ConsoleAdminPassword $password -Bastion:$Bastion `
      -Portability:$Portability -ApplicationRestrictions:$ApplicationRestrictions -Packaging:$Packaging -PackagingAdminPassword $pkgPassword -Backup:$enableBackup
    $templateParams = @{}
    foreach ($k in $params.Keys) {
      $v = $params[$k]
      if ($v -is [securestring]) { $v = [System.Net.NetworkCredential]::new('', $v).Password }
      elseif ($null -eq $v) { $v = '' }
      $templateParams[$k] = $v
    }
    Write-Host 'Running what-if on profileunity/bicep/main.bicep (read-only) ...'
    $whatIf = Get-AzSubscriptionDeploymentWhatIfResult -Name "liquidware-$($names.Base)" -Location $lz.Location `
      -TemplateFile (Join-Path $PSScriptRoot '../profileunity/bicep/main.bicep') -TemplateParameterObject $templateParams
    $changes = @($whatIf.Changes | ForEach-Object { [pscustomobject]@{ ChangeType = "$($_.ChangeType)"; ResourceId = $_.FullyQualifiedResourceId } })
    Add-Result (Get-LwWhatIfSummary -Change $changes -LandingZone $lz)

    $deployment = $null
    if ($Action -eq 'Deploy' -and @($results | Where-Object Status -eq 'FAIL').Count -eq 0 -and
      (Confirm-Step -Target $names.TierGroup -What 'Deploy the changes above' -Force:$Force)) {
      if ($deleted.Vault) {
        if ($groups -notcontains $names.TierGroup) { $null = New-AzResourceGroup -Name $names.TierGroup -Location $lz.Location }
        Write-Host "Recovering $($deleted.Vault.VaultName) ..."
        $null = Undo-AzKeyVaultRemoval -VaultName $deleted.Vault.VaultName -ResourceGroupName $names.TierGroup -Location $deleted.Vault.Location
      }
      Write-Host 'Deploying profileunity/bicep/main.bicep (several minutes) ...'
      $deployment = $null
      try {
        $deployment = New-AzSubscriptionDeployment -Name "liquidware-$($names.Base)" -Location $lz.Location `
          -TemplateFile (Join-Path $PSScriptRoot '../profileunity/bicep/main.bicep') -TemplateParameterObject $templateParams
      }
      catch { Add-Result (Get-LwCheckResult FAIL 'deploy' $_.Exception.Message -Recommendation 'Read the deployment in the portal (subscription, Deployments), fix, then Deploy again.' -Category ProfileUnity) }
      if ($deployment -and $deployment.ProvisioningState -eq 'Succeeded') {
        Add-Result (Get-LwCheckResult PASS 'deploy' "liquidware-$($names.Base) succeeded." -Category ProfileUnity)
      }
      elseif ($deployment) {
        Add-Result (Get-LwCheckResult FAIL 'deploy' "liquidware-$($names.Base) ended $($deployment.ProvisioningState)." -Recommendation 'Read the deployment in the portal, fix, then Deploy again.' -Category ProfileUnity)
      }
    }
    $templateParams.Remove('consoleAdminPassword')
    $templateParams.Remove('packagingAdminPassword')
    $password = $null
    $pkgPassword = $null

    if ($deployment -and $deployment.ProvisioningState -eq 'Succeeded') {
      if (-not $MediaLockPath) { $MediaLockPath = Join-Path $PSScriptRoot '../output/media.lock.json' }
      $lock = $(if (Test-Path -LiteralPath $MediaLockPath) { Get-Content -LiteralPath $MediaLockPath -Raw | ConvertFrom-Json } else { $null })
      $entry = Get-LwMediaLockEntry -Lock $lock -Component ProfileUnityConsole
      $vmStatus = Get-AzVM -ResourceGroupName $names.TierGroup -Name $names.ConsoleVm -Status
      $power = @($vmStatus.Statuses | Where-Object Code -like 'PowerState/*').Code
      if (-not $entry) {
        Add-Result (Get-LwCheckResult WARN 'console-install' "No ProfileUnityConsole entry in $MediaLockPath." -Recommendation 'Publish the installer with Publish-LiquidwareMedia.ps1, then Deploy again.' -Category ProfileUnity)
      }
      elseif ($power -ne 'PowerState/running') {
        Add-Result (Get-LwCheckResult WARN 'console-install' "$($names.ConsoleVm) is $power; a Run Command needs it running." -Recommendation 'Start it, then Deploy again.' -Category ProfileUnity)
      }
      else {
        Write-Host "Downloading and checking $($entry.blob) on $($names.ConsoleVm) by Run Command ..."
        $rcArgs = @{ ResourceGroupName = $names.TierGroup; VMName = $names.ConsoleVm; RunCommandName = 'lw-profileunity-console' }
        try {
          $null = Set-AzVMRunCommand @rcArgs -Location $lz.Location -ScriptLocalPath (Join-Path $PSScriptRoot 'host/Install-ProfileUnityConsole.ps1') `
            -Parameter @(@{ Name = 'MediaAccountName'; Value = $deployment.Outputs['mediaAccountName'].Value }, @{ Name = 'Blob'; Value = $entry.blob }, @{ Name = 'Sha256'; Value = $entry.sha256 })
          $view = (Get-AzVMRunCommand @rcArgs -Expand InstanceView).InstanceView
          Add-Result (Get-LwRunCommandResult -Output "$($view.Output)`n$($view.Error)" -Check 'console-install')
        }
        catch { Add-Result (Get-LwCheckResult FAIL 'console-install' $_.Exception.Message -Recommendation 'Read the Run Command instance view on the console, then Deploy again.' -Category ProfileUnity) }
      }
    }
  }
}

Add-Result @($summary | Where-Object Status -ne 'FAIL')
Complete-Run
