#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# Offline tests for scripts/host/: they run on Windows PowerShell 5.1 with no modules (deploy-spec
# section 6), so a grammar check refuses PowerShell 7-only syntax, and the URI, token and hash
# logic is dot-sourced and run here with the network calls mocked.

BeforeAll {
  $script:root = Split-Path $PSScriptRoot -Parent
  $script:hostScripts = @(Get-ChildItem (Join-Path $script:root 'scripts/host') -Filter *.ps1)

  # Syntax Windows PowerShell 5.1 can't parse or run, found in the PowerShell 7 parser's tree.
  function Get-Ps7OnlySyntax([string] $Path) {
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref] $tokens, [ref] $errors)
    if ($errors) { return @($errors | ForEach-Object { "parse error: $($_.Message)" }) }
    $found = @()
    $found += @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.TernaryExpressionAst] }, $true) | ForEach-Object { "ternary at line $($_.Extent.StartLineNumber)" })
    $found += @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.PipelineChainAst] }, $true) | ForEach-Object { "&& or || at line $($_.Extent.StartLineNumber)" })
    $found += @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.BinaryExpressionAst] -and $args[0].Operator -eq 'QuestionQuestion' }, $true) | ForEach-Object { "?? at line $($_.Extent.StartLineNumber)" })
    $found += @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.AssignmentStatementAst] -and $args[0].Operator -eq 'QuestionQuestionEquals' }, $true) | ForEach-Object { "??= at line $($_.Extent.StartLineNumber)" })
    $found += @($ast.FindAll({ ($args[0] -is [System.Management.Automation.Language.MemberExpressionAst] -or $args[0] -is [System.Management.Automation.Language.IndexExpressionAst]) -and $args[0].NullConditional }, $true) | ForEach-Object { "?. or ?[] at line $($_.Extent.StartLineNumber)" })
    $found += @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.NamedBlockAst] -and "$($args[0].BlockKind)" -eq 'Clean' }, $true) | ForEach-Object { "clean block at line $($_.Extent.StartLineNumber)" })
    $found += @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] -and $args[0].GetCommandName() -in 'ForEach-Object', 'foreach', '%' -and @($args[0].CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] -and 'Parallel' -like "$($_.ParameterName)*" }).Count -gt 0 }, $true) | ForEach-Object { "ForEach-Object -Parallel at line $($_.Extent.StartLineNumber)" })
    $found += @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] -and $args[0].GetCommandName() -in 'Import-Module', 'Install-Module', 'ipmo' }, $true) | ForEach-Object { "module use at line $($_.Extent.StartLineNumber)" })
    $found
  }
}

Describe 'Host scripts' {
  It 'exist' {
    $script:hostScripts.Count | Should -BeGreaterThan 0
  }
  It 'use only Windows PowerShell 5.1 syntax and no modules' {
    foreach ($f in $script:hostScripts) {
      @(Get-Ps7OnlySyntax $f.FullName) | Should -BeNullOrEmpty -Because $f.Name
      (Get-Content $f.FullName -Raw) | Should -Match '(?m)^#requires -Version 5\.1\s*$' -Because $f.Name
    }
  }
  It 'are ASCII and carry the personal-project notice near the top' {
    foreach ($f in $script:hostScripts) {
      [System.IO.File]::ReadAllBytes($f.FullName) | Where-Object { $_ -gt 127 } | Should -BeNullOrEmpty -Because $f.Name
      (Get-Content $f.FullName -TotalCount 8) -join "`n" | Should -Match 'Personal project, not for production use' -Because $f.Name
    }
  }
  It 'never write a token or a bearer header to output' {
    foreach ($f in $script:hostScripts) {
      $text = Get-Content $f.FullName -Raw
      $text | Should -Not -Match 'Write-(Output|Host|Verbose|Information)[^\r\n]*\$(Token|response|headers)' -Because $f.Name
      $text | Should -Not -Match 'Start-Transcript' -Because $f.Name
    }
  }
  It 'the grammar check catches what it is meant to' {
    $probe = Join-Path $TestDrive 'probe.ps1'
    Set-Content $probe -Value @('$a = $b ?? 1', '$c = $true ? 1 : 2', 'git status && git log', '${d}?.e', '1..2 | ForEach-Object -Parallel { $_ }', 'Import-Module Az.Accounts')
    @(Get-Ps7OnlySyntax $probe).Count | Should -Be 6
  }
}

Describe 'Install-ProfileUnityConsole.ps1' {
  BeforeAll {
    . (Join-Path $script:root 'scripts/host/Install-ProfileUnityConsole.ps1')
    $script:file = Join-Path $TestDrive 'console.exe'
    [System.IO.File]::WriteAllBytes($script:file, [byte[]] (1..64))
    $script:hash = (Get-FileHash -LiteralPath $script:file -Algorithm SHA256).Hash
  }
  It 'builds the media URI from the account and the lock entry' {
    Get-MediaUri -AccountName stavdlzdevlwmabcde -BlobName 'ProfileUnityConsole/6.9.5/console.exe' -Suffix core.windows.net |
      Should -Be 'https://stavdlzdevlwmabcde.blob.core.windows.net/media/ProfileUnityConsole/6.9.5/console.exe'
  }
  It 'refuses anything but a media blob on a storage account' {
    { Get-MediaUri -AccountName 'evil.example.com/x' -BlobName 'ProfileUnityConsole/6.9.5/a.exe' -Suffix core.windows.net } | Should -Throw '*storage account*'
    { Get-MediaUri -AccountName stabc -BlobName 'ProfileUnityConsole/6.9.5/a.exe' -Suffix 'example.com/x?' } | Should -Throw '*suffix*'
    foreach ($bad in '../staging/x.ini', 'ProfileUnityConsole/6.9.5/../x', 'Other/6.9.5/a.exe', 'ProfileUnityConsole/6.9.5', 'ProfileUnityConsole/6.9.5/a.exe?sv=1') {
      { Get-MediaUri -AccountName stabc -BlobName $bad -Suffix core.windows.net } | Should -Throw '*media blob*' -Because $bad
    }
  }
  It 'asks IMDS for a storage token with the Metadata header' {
    Mock Invoke-RestMethod { [pscustomobject]@{ access_token = 'token-1' } }
    Get-ImdsStorageToken | Should -Be 'token-1'
    Should -Invoke Invoke-RestMethod -Times 1 -ParameterFilter {
      $Uri -like 'http://169.254.169.254/metadata/identity/oauth2/token?*' -and $Uri -like '*resource=https%3A%2F%2Fstorage.azure.com%2F*' -and $Headers.Metadata -eq 'true'
    }
  }
  It 'fails clearly when the VM has no identity' {
    Mock Invoke-RestMethod { [pscustomobject]@{} }
    { Get-ImdsStorageToken } | Should -Throw '*system-assigned identity*'
  }
  It 'downloads only over HTTPS, with the bearer token and a storage API version' {
    Mock Invoke-WebRequest { }
    Save-MediaBlob -Uri 'https://stabc.blob.core.windows.net/media/a' -Token 'token-1' -Path (Join-Path $TestDrive 'a')
    Should -Invoke Invoke-WebRequest -Times 1 -ParameterFilter { $Headers.Authorization -eq 'Bearer token-1' -and $Headers['x-ms-version'] }
    { Save-MediaBlob -Uri 'http://stabc.blob.core.windows.net/media/a' -Token 'token-1' -Path (Join-Path $TestDrive 'a') } | Should -Throw '*HTTPS*'
  }
  It 'accepts the exact SHA-256 in either case, and nothing else' {
    Test-MediaHash -Path $script:file -Expected $script:hash | Should -BeTrue
    Test-MediaHash -Path $script:file -Expected $script:hash.ToLower() | Should -BeTrue
    Test-MediaHash -Path $script:file -Expected ('0' * 64) | Should -BeFalse
    Test-MediaHash -Path $script:file -Expected '' | Should -BeFalse
    Test-MediaHash -Path $script:file -Expected "$($script:hash)00" | Should -BeFalse
    Test-MediaHash -Path (Join-Path $TestDrive 'missing.exe') -Expected $script:hash | Should -BeFalse
  }
  It 'prints the checklist with the deploy path, the license and Swagger steps' {
    $c = (Get-ConsoleChecklist -Path 'C:\x\console.exe') -join "`n"
    $c | Should -Match 'docs/console.md'
    $c | Should -Match 'C:\\ProgramData\\avd-liquidware\\deploy'
    $c | Should -Match 'lw-licstr'
    $c | Should -Match 'Swagger'
  }
}

Describe 'Install-ProfileUnityConsole.ps1, run end to end with the network mocked' {
  BeforeAll {
    $script:script = Join-Path $script:root 'scripts/host/Install-ProfileUnityConsole.ps1'
    $script:payload = [byte[]] (1..32)
    $script:sha = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash($script:payload)).Replace('-', '')
  }
  It 'keeps a verified download and reports it' {
    $dest = Join-Path $TestDrive 'ok'
    Mock Invoke-RestMethod { [pscustomobject]@{ access_token = 'token-1' } }
    Mock Invoke-WebRequest { [System.IO.File]::WriteAllBytes($OutFile, [byte[]] (1..32)) }
    $out = & $script:script -MediaAccountName stabc -Blob 'ProfileUnityConsole/6.9.5/console.exe' -Sha256 $script:sha -Destination $dest
    ($out | Where-Object { $_ -like 'LW-RESULT*' }) | Should -Match 'status=verified'
    Test-Path (Join-Path $dest 'console.exe') | Should -BeTrue
    Test-Path (Join-Path $dest 'console.exe.partial') | Should -BeFalse
  }
  It 'deletes a download whose hash does not match' {
    # A failing run exits 1, so it runs in its own process with the network calls stubbed.
    $dest = Join-Path $TestDrive 'bad'
    $out = pwsh -NoProfile -Command "& { function Invoke-RestMethod { [pscustomobject]@{ access_token = 't' } }; function Invoke-WebRequest { param(`$Uri, `$Headers, `$OutFile, [switch] `$UseBasicParsing) [System.IO.File]::WriteAllBytes(`$OutFile, [byte[]] (9, 9, 9)) }; & '$($script:script)' -MediaAccountName stabc -Blob 'ProfileUnityConsole/6.9.5/console.exe' -Sha256 '$($script:sha)' -Destination '$dest'; exit `$LASTEXITCODE }"
    $LASTEXITCODE | Should -Be 1
    ($out | Where-Object { $_ -like 'LW-RESULT*' }) | Should -Match 'status=failed.*mismatch'
    @(Get-ChildItem $dest -ErrorAction SilentlyContinue) | Should -BeNullOrEmpty
  }
}
