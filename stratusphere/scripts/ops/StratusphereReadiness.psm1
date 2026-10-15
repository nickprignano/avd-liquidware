# Checks behind Test-StratusphereReadiness.ps1. The Get-Ssux*Check functions take
# data already read from Azure and return results, so they are tested offline.
# Personal project, not for production use. Provided as is, without warranty of any kind (MIT License, see LICENSE). Not affiliated with the author's employer, with Liquidware or with Microsoft.

function Get-SsuxCheckResult {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [ValidateSet('PASS', 'WARN', 'FAIL', 'FIXED')] [string] $Status,
    [Parameter(Mandatory)] [string] $Check,
    [Parameter(Mandatory)] [string] $Detail
  )
  [pscustomobject]@{ Status = $Status; Check = $Check; Detail = $Detail }
}

function Get-SsuxPlanCheck {
  # Is the chosen Marketplace plan offered in the region? Without one, list what is.
  [CmdletBinding()]
  param(
    [AllowEmptyCollection()] [string[]] $AvailablePlans = @(),
    [string] $Plan,
    [Parameter(Mandatory)] [string] $Location
  )
  $plans = @($AvailablePlans | Where-Object { $_ })
  if ($plans.Count -eq 0) {
    return Get-SsuxCheckResult FAIL 'marketplace-plan' "No Stratusphere plans are offered in $Location under this publisher and offer. Check the publisher and offer names, or try another region."
  }
  $list = $plans -join ', '
  if (-not $Plan) {
    return Get-SsuxCheckResult FAIL 'marketplace-plan' "Choose a plan with -Plan. Offered in ${Location}: $list"
  }
  if ($plans -notcontains $Plan) {
    return Get-SsuxCheckResult FAIL 'marketplace-plan' "Plan '$Plan' is not offered in $Location. Offered: $list"
  }
  Get-SsuxCheckResult PASS 'marketplace-plan' "Plan '$Plan' is offered in $Location"
}

function Get-SsuxImagePlanCheck {
  # A Marketplace image without a purchase plan must be deployed without a plan block,
  # and one with a plan must match it. hub.bicep always sends a plan block.
  [CmdletBinding()]
  param(
    $PurchasePlan,
    [Parameter(Mandatory)] [string] $Version
  )
  if (-not $PurchasePlan) {
    return Get-SsuxCheckResult FAIL 'image-purchase-plan' "Image version $Version has no purchase plan, so the plan block in hub.bicep would be rejected. Report this: the template needs a no-plan path."
  }
  Get-SsuxCheckResult PASS 'image-purchase-plan' "Image version $Version carries purchase plan '$($PurchasePlan.Name)'"
}

function Get-SsuxQuotaCheck {
  # Enough regional and VM-family vCPU quota for the Hub?
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [int] $VCpusNeeded,
    [Parameter(Mandatory)] [string] $Family,
    [AllowEmptyCollection()] [object[]] $Usage = @()
  )
  $results = foreach ($name in 'cores', $Family) {
    $row = @($Usage | Where-Object { $_.Name.Value -eq $name }) | Select-Object -First 1
    if (-not $row) {
      Get-SsuxCheckResult WARN "quota-$name" "No usage row for $name; could not check quota"
      continue
    }
    $free = [int]$row.Limit - [int]$row.CurrentValue
    if ($free -lt $VCpusNeeded) {
      Get-SsuxCheckResult FAIL "quota-$name" "$free vCPUs free in $name, $VCpusNeeded needed. Request a quota increase."
    }
    else {
      Get-SsuxCheckResult PASS "quota-$name" "$free vCPUs free in $name, $VCpusNeeded needed"
    }
  }
  $results
}

function Get-SsuxVmSizeCheck {
  # Is the size offered in the region and not restricted for this subscription?
  [CmdletBinding()]
  param(
    $Sku,
    [Parameter(Mandatory)] [string] $VmSize,
    [Parameter(Mandatory)] [string] $Location
  )
  if (-not $Sku) {
    return Get-SsuxCheckResult FAIL 'vm-size' "$VmSize is not offered in $Location"
  }
  $blocked = @($Sku.Restrictions | Where-Object { $_.ReasonCode -eq 'NotAvailableForSubscription' -and $_.Type -eq 'Location' })
  if ($blocked.Count -gt 0) {
    return Get-SsuxCheckResult FAIL 'vm-size' "$VmSize is restricted for this subscription in $Location"
  }
  Get-SsuxCheckResult PASS 'vm-size' "$VmSize is available in $Location"
}

Export-ModuleMember -Function Get-SsuxCheckResult, Get-SsuxPlanCheck, Get-SsuxImagePlanCheck, Get-SsuxQuotaCheck, Get-SsuxVmSizeCheck
