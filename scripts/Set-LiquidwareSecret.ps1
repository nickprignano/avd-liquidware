#requires -Version 7.4
<#
.SYNOPSIS
  Stores the ProfileUnity license string (lw-licstr) in the tier Key Vault, through the ARM management plane.
  Personal project, not for production use. Provided as is, without warranty of any kind. Not affiliated with the author's employer, with Liquidware or with Microsoft.

.DESCRIPTION
  deploy-spec section 10. Prompts with Read-Host -AsSecureString: the value is never a
  parameter, never echoed, never logged and never goes through chat. It is written as
  Microsoft.KeyVault/vaults/secrets through ARM, which works on the tier's private vault from
  Cloud Shell (DN-C1). Afterwards only VMs inside the network read it, each with its own identity.

  Run Deploy-LiquidwareTier.ps1 -Action Deploy again afterwards: the console's read role on the
  secret is granted only once the secret exists.

.EXAMPLE
  ./scripts/Set-LiquidwareSecret.ps1 -NamePrefix avdlz -Environment dev
#>
[CmdletBinding(SupportsShouldProcess)]
param(
  [Parameter(Mandatory)] [string] $NamePrefix,
  [Parameter(Mandatory)] [string] $Environment,
  [ValidateSet('lw-licstr')] [string] $Name = 'lw-licstr',
  [string] $SubscriptionId = ''
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'LiquidwareTier.psm1') -Force

$argErrors = @(Get-LwArgumentError -NamePrefix $NamePrefix -Environment $Environment -Component ProfileUnity)
if ($argErrors.Count -gt 0) {
  $argErrors | ForEach-Object { Write-Host "FAIL   $_" }
  Write-Host 'RESULT FAIL invalid arguments'
  exit 1
}

foreach ($m in 'Az.Accounts', 'Az.Resources') {
  if (-not (Get-Module -ListAvailable -Name $m)) {
    Write-Host "Installing $m from the PowerShell Gallery ..."
    Install-Module $m -Scope CurrentUser -Force -AllowClobber
  }
  Import-Module $m
}
if ($SubscriptionId) { $null = Set-AzContext -SubscriptionId $SubscriptionId }
if (-not (Get-AzContext)) { Write-Host 'Not signed in. Run Connect-AzAccount (Cloud Shell is already signed in).'; exit 2 }

$names = Get-LwName -NamePrefix $NamePrefix -Environment $Environment
$vault = @(Get-AzResource -ResourceGroupName $names.TierGroup -ResourceType 'Microsoft.KeyVault/vaults' -ErrorAction SilentlyContinue) | Select-Object -First 1
if (-not $vault) {
  Write-Host "FAIL   No Key Vault in $($names.TierGroup)  [fix: run Deploy-LiquidwareTier.ps1 -Action Deploy first]"
  Write-Host 'RESULT FAIL no tier Key Vault'
  exit 1
}
$secretPath = Get-LwSecretPath -KeyVaultId $vault.ResourceId -Name $Name

$secure = Read-Host -Prompt "Paste the ProfileUnity license string for $Name (input is hidden)" -AsSecureString
if (-not $secure -or $secure.Length -eq 0) { Write-Host 'RESULT FAIL nothing entered'; exit 1 }
if (-not $PSCmdlet.ShouldProcess("$($vault.Name)/$Name", 'Store the secret through the management plane')) { exit 0 }

$plain = [System.Net.NetworkCredential]::new('', $secure).Password
try {
  $body = @{ properties = @{ value = $plain; contentType = 'ProfileUnity license string' } } | ConvertTo-Json -Compress
  $response = Invoke-AzRestMethod -Method PUT -Path $secretPath -Payload $body
}
finally {
  $plain = $null
  $body = $null
  $secure.Dispose()
}
if ($response.StatusCode -notin 200, 201) {
  # The error body describes the request, never the value; print only the status and the code.
  $code = $(try { ($response.Content | ConvertFrom-Json).error.code } catch { '' })
  Write-Host "FAIL   Storing $Name returned HTTP $($response.StatusCode) $code  [fix: you need Key Vault Contributor or Owner on the tier resource group]"
  Write-Host 'RESULT FAIL secret not stored'
  exit 1
}
Write-Host "PASS   $Name stored in $($vault.Name) (value not shown)."
Write-Host 'Next: run Deploy-LiquidwareTier.ps1 -Action Deploy again, so the console gets its read role on this secret.'
Write-Host 'RESULT PASS'
