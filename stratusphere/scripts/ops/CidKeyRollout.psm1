# Planning and parsing behind Deploy-CidKey.ps1. Every function takes data already read
# from Azure (or a Run Command's output) and returns objects, so it is tested offline.
# Personal project, not for production use. Provided as is, without warranty of any kind (MIT License, see LICENSE). Not affiliated with the author's employer, with Liquidware or with Microsoft.

function Get-SsuxCidArgumentError {
  # Values are embedded in the script sent to each machine, so they are validated
  # strictly here rather than escaped.
  [CmdletBinding()]
  param(
    [string] $HubAddress,
    [string] $InstallerUrl,
    [string] $InstallerSha256,
    [Parameter(Mandatory)] [string] $Action
  )
  $errors = @()
  if ($HubAddress -and $HubAddress -notmatch '^[A-Za-z0-9]([A-Za-z0-9.-]{0,251}[A-Za-z0-9])?$') {
    $errors += "HubAddress '$HubAddress' is not a host name or IP address."
  }
  # Install, Fix and Uninstall run the installer; Cleanup uses it only when given one.
  $needsInstaller = $Action -in 'Install', 'Fix', 'Uninstall'
  if ($needsInstaller -or $InstallerUrl -or $InstallerSha256) {
    if (-not $InstallerUrl) { $errors += "-InstallerUrl is required for $Action." }
    elseif ($InstallerUrl -notmatch "^https://[^\s'`"]+$") { $errors += 'InstallerUrl must be an https URL with no spaces or quotes.' }
    if (-not $InstallerSha256) { $errors += "-InstallerSha256 is required with an installer, so every machine verifies what it runs." }
    elseif ($InstallerSha256 -notmatch '^[A-Fa-f0-9]{64}$') { $errors += 'InstallerSha256 must be 64 hex characters.' }
  }
  $errors
}

function Get-SsuxCidRemoteScript {
  # The endpoint script, wrapped in a script block and called with the validated arguments.
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string] $AgentScript,
    [Parameter(Mandatory)] [ValidateSet('Check', 'Install', 'Fix', 'Uninstall', 'Cleanup')] [string] $Action,
    [string] $HubAddress = '',
    [string] $InstallerUrl = '',
    [string] $InstallerSha256 = '',
    [switch] $Force
  )
  # A script block keeps the agent script's own param block, so it runs unchanged.
  $call = "-Action '$Action' -HubAddress '$HubAddress' -InstallerUrl '$InstallerUrl' -InstallerSha256 '$InstallerSha256'"
  if ($Force) { $call += ' -Force' }
  "& {`n$AgentScript`n} $call"
}

function Get-SsuxCidTargetPlan {
  # One row per VM: Run, or Skip with the reason. Input rows carry Name, ResourceGroupName,
  # OsType and PowerState (as Get-AzVM -Status reports it, e.g. 'VM running').
  [CmdletBinding()]
  param([AllowEmptyCollection()] [object[]] $Vm = @())
  foreach ($v in $Vm) {
    $reason = ''
    if ($v.OsType -ne 'Windows') { $reason = "OS is $($v.OsType); the Connector ID Key here is Windows only" }
    elseif ($v.PowerState -ne 'VM running') { $reason = "Power state is '$($v.PowerState)'; start it or rerun later" }
    [pscustomobject]@{
      Name              = $v.Name
      ResourceGroupName = $v.ResourceGroupName
      Plan              = $(if ($reason) { 'Skip' } else { 'Run' })
      Reason            = $reason
    }
  }
}

function Get-SsuxCidRunOutcome {
  # Parses the SSUX-RESULT line from a Run Command's output. No line means the script
  # never reached the end (timeout, agent not ready), which is reported with what came back.
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string] $Name,
    [AllowEmptyString()] [string] $Output = '',
    [AllowEmptyString()] [string] $ErrorText = ''
  )
  $line = ($Output -split "`r?`n" | Where-Object { $_ -like 'SSUX-RESULT *' } | Select-Object -Last 1)
  if ($line -match '^SSUX-RESULT status=(\S+) version=(\S*) detail=(.*)$') {
    return [pscustomobject]@{ Name = $Name; Status = $Matches[1]; Version = $Matches[2]; Detail = $Matches[3].Trim() }
  }
  $detail = (@($ErrorText, $Output) | Where-Object { $_ }) -join ' | '
  if (-not $detail) { $detail = 'Run Command returned no output' }
  [pscustomobject]@{ Name = $Name; Status = 'failed'; Version = ''; Detail = ($detail -replace '[\r\n]+', ' ').Trim() }
}

function Get-SsuxCidPersistenceWarning {
  # Run Command reaches the machines that exist now. Hosts added later (scaling, rebuilds
  # from an image) won't have the key unless it is in the image or assigned through Intune.
  [CmdletBinding()]
  param([bool] $FromHostPool, [int] $HostCount)
  if ($FromHostPool) {
    "Installed on the $HostCount session host(s) that exist now. Hosts created later from the image will not have the Connector ID Key: add it to the golden image (avd-landing-zone: scripts/image/custom/Invoke-CustomImageStep.ps1) or assign it through Intune."
  }
}

function Get-SsuxCidRetryTarget {
  # From a previous run's report: the machines that did not end healthy, with their resource groups.
  [CmdletBinding()]
  param([Parameter(Mandatory)] $Report)
  $good = 'present', 'installed', 'already-installed', 'repaired', 'already-healthy', 'uninstalled', 'cleaned', 'absent'
  $bad = @($Report.outcomes | Where-Object { $good -notcontains $_.Status } | ForEach-Object Name)
  @($Report.planned | Where-Object { $bad -contains $_.Name } | Select-Object Name, ResourceGroupName)
}

function Get-SsuxCidSummary {
  [CmdletBinding()]
  param([AllowEmptyCollection()] [object[]] $Outcome = @())
  $failed = @($Outcome | Where-Object { $_.Status -in 'failed', 'degraded' }).Count
  [pscustomobject]@{
    Total  = @($Outcome).Count
    Failed = $failed
    Result = $(if ($failed -gt 0) { 'FAIL' } else { 'PASS' })
  }
}

Export-ModuleMember -Function Get-SsuxCidArgumentError, Get-SsuxCidRemoteScript, Get-SsuxCidTargetPlan, Get-SsuxCidRunOutcome, Get-SsuxCidPersistenceWarning, Get-SsuxCidRetryTarget, Get-SsuxCidSummary
