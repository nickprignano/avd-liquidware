# Personal project, not for production use. Provided as is, without warranty of any kind (MIT License, see LICENSE at the repo root). Not affiliated with the author's employer, with Liquidware or with Microsoft.
#requires -Version 5.1
<#
.SYNOPSIS
  Runs ON the ProfileUnity console VM: hashes the compiled INI, client.net.xml and plain-text
  export in C:\ProgramData\avd-liquidware\deploy and uploads them to the media account's staging
  container with the console's managed identity.
.DESCRIPTION
  Windows PowerShell 5.1, no modules, runs as SYSTEM by managed Run Command (deploy-spec
  section 7, D-C3, DN-C4). The console identity holds Storage Blob Data Contributor on the
  staging container only and can never write the live config share directly.

  Prints exactly one line starting with LW-RESULT:
    LW-RESULT status=<staged|failed> timestamp=<ts> iniSha256=<hash> detail=<text>
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Used by the main block below, which the analyzer does not follow.')]
[CmdletBinding()]
param(
  [string] $MediaAccountName = '',
  [string] $ConfigName = 'default',
  [string] $Timestamp = '',
  [string] $DeployFolder = 'C:\ProgramData\avd-liquidware\deploy',
  [string] $StorageSuffix = 'core.windows.net'
)

$ErrorActionPreference = 'Stop'

function Write-StagingResult([string] $Status, [string] $Ts, [string] $IniSha256, [string] $Detail) {
  $clean = ($Detail -replace '[\r\n]+', ' ').Trim()
  Write-Output ("LW-RESULT status={0} timestamp={1} iniSha256={2} detail={3}" -f $Status, $Ts, $IniSha256, $clean)
}

function Get-StagingBlobUri([string] $AccountName, [string] $Config, [string] $Ts, [string] $FileName, [string] $Suffix) {
  if ($AccountName -cnotmatch '^[a-z0-9]{3,24}$') { throw "Not a storage account name: '$AccountName'." }
  if ($Suffix -notmatch '^[a-z0-9.-]+$') { throw "Not a storage endpoint suffix: '$Suffix'." }
  if ($Config -notmatch '^[a-zA-Z0-9_-]{1,64}$') { throw "Not a configuration name: '$Config'." }
  if ($Ts -notmatch '^\d{8}T\d{6}Z$') { throw "Timestamp '$Ts' must be yyyyMMddTHHmmssZ." }
  if ($FileName -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$') { throw "Not a valid staging file name: '$FileName'." }
  "https://$AccountName.blob.$Suffix/staging/$Config/$Ts/$FileName"
}

function Get-StagingImdsToken {
  $uri = 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=' + [uri]::EscapeDataString('https://storage.azure.com/')
  $res = Invoke-RestMethod -Uri $uri -Headers @{ Metadata = 'true' } -Method Get -UseBasicParsing
  if (-not $res.access_token) { throw 'IMDS returned no access token: does the VM have a system-assigned identity?' }
  $res.access_token
}

function Send-StagingBlob([string] $Uri, [string] $Token, [string] $FilePath) {
  if ($Uri -notmatch '^https://') { throw 'Staging upload requires HTTPS.' }
  $putHeaders = @{
    Authorization    = "Bearer $Token"
    'x-ms-version'   = '2021-08-06'
    'x-ms-blob-type' = 'BlockBlob'
  }
  Invoke-RestMethod -Uri $Uri -Headers $putHeaders -Method Put -InFile $FilePath -ContentType 'application/octet-stream' -UseBasicParsing | Out-Null
}

if ($MyInvocation.InvocationName -ne '.') {
  $iniSha = ''
  if (-not $Timestamp) { $Timestamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ') }
  try {
    if (-not $MediaAccountName) { throw 'Pass -MediaAccountName.' }
    $iniFile = Join-Path $DeployFolder "$ConfigName.ini"
    $xmlFile = Join-Path $DeployFolder 'client.net.xml'
    $jsonFile = Join-Path $DeployFolder "$ConfigName.json"
    foreach ($required in @($iniFile, $xmlFile, $jsonFile)) {
      if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required deploy artifact not found: $required"
      }
    }
    $iniSha = (Get-FileHash -LiteralPath $iniFile -Algorithm SHA256).Hash.ToLowerInvariant()
    $xmlSha = (Get-FileHash -LiteralPath $xmlFile -Algorithm SHA256).Hash.ToLowerInvariant()
    $jsonSha = (Get-FileHash -LiteralPath $jsonFile -Algorithm SHA256).Hash.ToLowerInvariant()

    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $ProgressPreference = 'SilentlyContinue'
    $token = Get-StagingImdsToken
    foreach ($item in @(
        @{ Name = "$ConfigName.ini"; Path = $iniFile }
        @{ Name = 'client.net.xml'; Path = $xmlFile }
        @{ Name = "$ConfigName.json"; Path = $jsonFile }
      )) {
      $uri = Get-StagingBlobUri -AccountName $MediaAccountName -Config $ConfigName -Ts $Timestamp -FileName $item.Name -Suffix $StorageSuffix
      Send-StagingBlob -Uri $uri -Token $token -FilePath $item.Path
    }
    $token = $null
    Write-StagingResult 'staged' $Timestamp $iniSha "Uploaded $ConfigName ($Timestamp) to staging (xmlSha256=$xmlSha jsonSha256=$jsonSha)."
  }
  catch {
    Write-StagingResult 'failed' $Timestamp $iniSha $_.Exception.Message
    exit 1
  }
}
