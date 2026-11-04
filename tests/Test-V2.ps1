# Run with Windows PowerShell 5.1 or PowerShell 7. No external modules required.
# Only the /check branch may execute in a child process. Never dot-source the app.
$ErrorActionPreference = 'Stop'
$script:Passed = 0
$script:Skipped = 0
$repo = Split-Path -Parent $PSScriptRoot
$originalPath = Join-Path $repo 'Low-Latency-Corp-Menu_SPI_24H2_VisualizationFix.cmd'
$newPath = Join-Path $repo 'Low-Latency-Corp-Menu_v2.cmd'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw ('FAIL: ' + $Message) }
}

function Test-Case {
    param([string]$Name, [scriptblock]$Body)
    & $Body
    $script:Passed++
    Write-Host ('PASS: ' + $Name) -ForegroundColor Green
}

function Assert-Throws {
    param([scriptblock]$Body, [string]$MessageFragment)
    $caught = $null
    try { & $Body } catch { $caught = $_ }
    Assert-True ($null -ne $caught) 'Expected an exception.'
    Assert-True ($caught.Exception.Message.Contains($MessageFragment)) ('Unexpected exception: ' + $caught)
}

function Get-Payload {
    param([string]$Path)
    $lines = [IO.File]::ReadAllLines($Path)
    $markers = @(0..($lines.Length - 1) | Where-Object { $lines[$_] -eq '### POWERSHELL STARTS HERE ###' })
    Assert-True ($markers.Count -eq 1) ('Expected one payload marker: ' + $Path)
    return ($lines[($markers[0] + 1)..($lines.Length - 1)] -join "`n")
}

$originalSource = Get-Payload $originalPath
$newSource = Get-Payload $newPath
$asts = @{}
foreach ($entry in @(@{Name='original'; Source=$originalSource}, @{Name='v2'; Source=$newSource})) {
    $parseTokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($entry.Source, [ref]$parseTokens, [ref]$parseErrors)
    Assert-True ($parseErrors.Count -eq 0) ('Payload parse errors in {0}: {1}' -f $entry.Name, ($parseErrors -join '; '))
    $asts[$entry.Name] = $ast
    $script:Passed++
    Write-Host ('PASS: {0} payload parses' -f $entry.Name) -ForegroundColor Green
}

Test-Case 'original CMD is byte-for-byte the reviewed baseline' {
    $actual = (Get-FileHash -LiteralPath $originalPath -Algorithm SHA256).Hash.ToLowerInvariant()
    Assert-True ($actual -eq '931b36ce50635e2faaa816dabc4950999f52f35be5dbf764c703a8c32440f466') 'Original CMD was changed.'
}

Test-Case 'bundled Device Tweaker PowerShell source parses without execution' {
    $devicePath = Join-Path $repo 'DEVICE-TWEAKER/DEVICE-TWEAKER-UPDATE-2026-LLG-X-LLC-UPDATED.ps1'
    $deviceTokens = $null
    $deviceErrors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($devicePath, [ref]$deviceTokens, [ref]$deviceErrors)
    Assert-True ($deviceErrors.Count -eq 0) ('Device Tweaker parse errors: ' + ($deviceErrors -join '; '))
}

# Import function declarations only; no top-level application statement is run.
$required = @('Confirm-LlcBroadChanges', 'Assert-LlcDownloadLength', 'Get-LlcPreflightResult', 'Get-OriginalScriptFolder', 'Resolve-ScriptResourcePath', 'Format-ProcessArgument', 'Invoke-NvidiaProfileInspector', 'Invoke-NvidiaProfileInspectorImportAuto')
foreach ($name in $required) {
    $definitions = @($asts.v2.FindAll({ param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
    }, $true))
    Assert-True ($definitions.Count -eq 1) ('Expected one definition: ' + $name)
    . ([scriptblock]::Create($definitions[0].Extent.Text))
}

# Resolve against real temporary directories, not mocked Test-Path results.
# Nothing in the fixture is executable: these files contain marker text only.
function Test-ResourceFixture {
    param([scriptblock]$Body)
    $fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('llc-path-test-' + [guid]::NewGuid().ToString('N'))
    $previousSource = $env:THIS
    try {
        $null = New-Item -ItemType Directory -Path $fixtureRoot
        $env:THIS = Join-Path $fixtureRoot 'menu.cmd'
        [IO.File]::WriteAllText($env:THIS, 'fixture only')
        & $Body $fixtureRoot
    }
    finally {
        $env:THIS = $previousSource
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
    }
}

function New-ResourceFixtureFile {
    param([string]$Path)
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force
    [IO.File]::WriteAllText($Path, 'fixture only')
}

Test-Case 'power plan gets the Exovance name and description even if already active; rename failure is reported' {
    $fn=$asts.v2.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Enable-LlcCertifiedPowerPlan'},$true)
    . ([scriptblock]::Create($fn.Extent.Text))
    $guid='8b24b027-1dee-4c65-8f35-5d5d91e51d87'
    function Test-PowerSchemeExists { param($SchemeGuid) return $true }
    function Get-ActivePowerSchemeGuid { return $guid }
    function Convert-NativeCommandOutputToText { param($Output) return [string]$Output }
    function Write-StatusLine { param($Ok,$Text) }
    function Invoke-NativeCommandCaptured {
        param($FilePath,$ArgumentList)
        Assert-True ($FilePath -eq 'powercfg.exe' -and ($ArgumentList -join '|') -eq ('/changename|'+$guid+'|Exovance v2|Made by Exovance')) 'Unexpected power operation.'
        $script:RenameCalls++
        return [pscustomobject]@{ExitCode=$script:RenameExit;Output='fixture'}
    }
    $script:RenameCalls=0; $script:RenameExit=0
    Assert-True (Enable-LlcCertifiedPowerPlan 'unused.pow' $guid) 'Existing active plan failed.'
    Assert-True ($script:RenameCalls -eq 1) 'Already-active plan retained old name/description.'
    $script:RenameExit=5
    Assert-True (-not (Enable-LlcCertifiedPowerPlan 'unused.pow' $guid)) 'Rename failure reported success.'
}

foreach ($resource in @('DEVICE-TWEAKER\RUN-DEVICE-TWEAKER.bat', 'POWER-PLAN\EXOVANCE.pow')) {
    foreach ($separator in @('\', '/')) {
        $relative = ('Resources\' + $resource).Replace('\', $separator)
        Test-Case ('resource resolver finds bundled {0} with separator [{1}]' -f $resource, $separator) {
            Test-ResourceFixture {
                param($fixtureRoot)
                $bundled = Join-Path $fixtureRoot $resource
                New-ResourceFixtureFile $bundled
                $actual = Resolve-ScriptResourcePath -RelativePath $relative
                Assert-True ($actual -eq $bundled) ('Expected bundled path, got ' + $actual)
            }
        }
        Test-Case ('resource resolver prefers Resources copy of {0} with separator [{1}]' -f $resource, $separator) {
            Test-ResourceFixture {
                param($fixtureRoot)
                $preferred = Join-Path $fixtureRoot $relative
                New-ResourceFixtureFile $preferred
                New-ResourceFixtureFile (Join-Path $fixtureRoot $resource)
                $actual = Resolve-ScriptResourcePath -RelativePath $relative
                Assert-True ($actual -eq $preferred) ('Expected preferred path, got ' + $actual)
            }
        }
        Test-Case ('missing {0} retains Resources path with separator [{1}]' -f $resource, $separator) {
            Test-ResourceFixture {
                param($fixtureRoot)
                $expected = Join-Path $fixtureRoot $relative
                $actual = Resolve-ScriptResourcePath -RelativePath $relative
                Assert-True ($actual -eq $expected) ('Missing file must retain preferred path, got ' + $actual)
                Assert-True (-not (Test-Path -LiteralPath $actual)) 'Fixture unexpectedly contains a resource.'
            }
        }
    }
    Test-Case ('resource resolver ignores bundled directory named like file ' + $resource) {
        Test-ResourceFixture {
            param($fixtureRoot)
            $null = New-Item -ItemType Directory -Path (Join-Path $fixtureRoot $resource) -Force
            $relative = 'Resources\' + $resource
            $actual = Resolve-ScriptResourcePath -RelativePath $relative
            Assert-True ($actual -eq (Join-Path $fixtureRoot $relative)) 'Directory must not satisfy a bundled file requirement.'
        }
    }
}

foreach ($separator in @('\', '/')) {
    Test-Case ('resource resolver does not redirect unrelated root files with separator [{0}]' -f $separator) {
        Test-ResourceFixture {
            param($fixtureRoot)
            $relative = 'Resources\7ZIP\7-Zip.exe'.Replace('\', $separator)
            New-ResourceFixtureFile (Join-Path $fixtureRoot '7ZIP\7-Zip.exe')
            $actual = Resolve-ScriptResourcePath -RelativePath $relative
            Assert-True ($actual -eq (Join-Path $fixtureRoot $relative)) 'Unrelated root-level file must not become a fallback.'
        }
    }
}

foreach ($scope in @('Auto', 'QOL')) {
    foreach ($answer in @('', 'yes', 'auto', 'qol', ' AUTO ', 'QOL ')) {
        Test-Case ('{0} cancels input [{1}]' -f $scope, $answer) {
            function Read-Host { param($Prompt) return $answer }
            $accepted = Confirm-LlcBroadChanges -Scope $scope 6>$null
            Assert-True ($accepted -eq $false) 'Unexpected confirmation.'
        }
    }
    Test-Case ($scope + ' accepts only its exact uppercase token') {
        function Read-Host { param($Prompt) return $scope.ToUpperInvariant() }
        $accepted = Confirm-LlcBroadChanges -Scope $scope 6>$null
        Assert-True ($accepted -eq $true) 'Expected explicit confirmation.'
    }
    Test-Case ($scope + ' cancels on input failure') {
        function Read-Host { param($Prompt) throw 'Input stream closed' }
        $accepted = Confirm-LlcBroadChanges -Scope $scope 6>$null
        Assert-True ($accepted -eq $false) 'Input failure must cancel.'
    }
    Test-Case ($scope + ' rejects the other operation token') {
        function Read-Host { param($Prompt) if ($scope -eq 'Auto') { return 'QOL' }; return 'AUTO' }
        $accepted = Confirm-LlcBroadChanges -Scope $scope 6>$null
        Assert-True ($accepted -eq $false) 'Operation confirmation must be specific.'
    }
}

Test-Case 'empty download is rejected even when size is unknown' {
    Assert-Throws { Assert-LlcDownloadLength -DownloadedBytes 0 -TotalBytes -1 } 'empty'
}
Test-Case 'zero advertised length cannot make an empty download pass' {
    Assert-Throws { Assert-LlcDownloadLength -DownloadedBytes 0 -TotalBytes 0 } 'empty'
}
Test-Case 'truncated download is rejected' {
    Assert-Throws { Assert-LlcDownloadLength -DownloadedBytes 100 -TotalBytes 101 } 'mismatch'
}
Test-Case 'oversized download is rejected' {
    Assert-Throws { Assert-LlcDownloadLength -DownloadedBytes 102 -TotalBytes 101 } 'mismatch'
}
Test-Case 'matching advertised length is accepted' {
    Assert-LlcDownloadLength -DownloadedBytes 101 -TotalBytes 101
}
Test-Case 'unknown size permits a nonempty download' {
    Assert-LlcDownloadLength -DownloadedBytes 101 -TotalBytes -1
}
Test-Case 'large installer length is compared as Int64' {
    Assert-LlcDownloadLength -DownloadedBytes 4294967296 -TotalBytes 4294967296
    Assert-Throws { Assert-LlcDownloadLength -DownloadedBytes 4294967295 -TotalBytes 4294967296 } 'mismatch'
}

# The real launcher is exercised with fixture paths and a stub process; no EXE runs.
function Test-NvpiFixture {
    param([scriptblock]$NvpiBody)
    Test-ResourceFixture {
        param($fixtureRoot)
        $toolDir = Join-Path $fixtureRoot 'Resources/NVIDIA-PROFILE-INSPECTOR'
        $null = New-Item -ItemType Directory -Path $toolDir -Force
        $exe = Join-Path $toolDir 'NVPI-R.exe'
        $profile = Join-Path $toolDir 'NvidiaV2.nip'
        [IO.File]::WriteAllText($exe, 'fixture only')
        [IO.File]::WriteAllText($profile, 'fixture only')
        $script:NvpiStarts = @()
        $script:NvpiExitCode = 0
        $script:NvpiThrow = $false
        function Write-BoxTitle { param($Title) }
        function Write-StatusLine { param($Ok, $Text) }
        function Start-Process {
            param($FilePath, $WorkingDirectory, $ArgumentList, [switch]$Wait, [switch]$PassThru, $ErrorAction)
            $script:NvpiStarts += [pscustomobject]@{FilePath=$FilePath; WorkingDirectory=$WorkingDirectory; Arguments=$ArgumentList; Wait=[bool]$Wait; PassThru=[bool]$PassThru}
            if ($script:NvpiThrow) { throw 'fixture process creation failure' }
            if ($PassThru) { return [pscustomobject]@{ExitCode=$script:NvpiExitCode} }
        }
        & $NvpiBody $exe $profile
    }
}

Test-Case 'bundled NvidiaV2 XML decodes with its declared encoding and retains ReBAR settings' {
    $profilePath = Join-Path $repo 'Resources/NVIDIA-PROFILE-INSPECTOR/NvidiaV2.nip'
    $reader = [Xml.XmlReader]::Create($profilePath)
    try { $document = New-Object Xml.XmlDocument; $document.Load($reader) } finally { $reader.Dispose() }
    $profiles = @($document.ArrayOfProfile.Profile)
    Assert-True ($profiles.Count -eq 1) 'Expected one global profile.'
    Assert-True ([string]::IsNullOrEmpty([string]$profiles[0].ProfileName)) 'Profile must target global settings.'
    $settings = @($profiles[0].Settings.ProfileSetting)
    Assert-True ($settings.Count -eq 43) 'User profile settings were lost.'
    $ids = @($settings | ForEach-Object { $_.SettingID })
    Assert-True (@($ids | Select-Object -Unique).Count -eq 43) 'Duplicate driver setting IDs.'
    $brand = @($settings | Where-Object { $_.SettingID -eq '538751439' })
    Assert-True ($brand.Count -eq 1 -and $brand[0].SettingValue -eq 'EXOVANCE' -and $brand[0].ValueType -eq 'String') 'Exovance profile metadata missing.'
    $rebar = @($settings | Where-Object { $_.SettingID -eq '784929' })
    Assert-True ($rebar.Count -eq 1 -and $rebar[0].SettingValue -eq '2' -and $rebar[0].ValueType -eq 'Dword') 'ReBAR Enable v2 must stay Enabled.'
    $size = @($settings | Where-Object { $_.SettingID -eq '983295' })
    Assert-True ($size.Count -eq 1 -and $size[0].SettingValue -eq '2147483648' -and $size[0].ValueType -eq 'Qword') 'ReBAR size limit must stay 2 GiB.'
}
Test-Case 'NVPI GUI launches without applying a profile or waiting for its window' {
    Test-NvpiFixture {
        param($exe, $profile)
        Remove-Item -LiteralPath $profile
        Assert-True (Invoke-NvidiaProfileInspector 6>$null) 'GUI launch should not need a profile.'
        Assert-True ($script:NvpiStarts.Count -eq 1) 'Expected one launch.'
        $call = $script:NvpiStarts[0]
        Assert-True ($call.FilePath -eq $exe -and $call.WorkingDirectory -eq (Split-Path -Parent $exe)) 'Wrong executable/working directory.'
        Assert-True (-not $call.Wait -and -not $call.PassThru -and $null -eq $call.Arguments) 'GUI launch must not import.'
    }
}
Test-Case 'NVPI import merges quoted profile paths and never reports verified success from exit 0' {
    Test-NvpiFixture {
        param($exe, $profile)
        # Include spaces to exercise Windows Start-Process argument quoting.
        $env:THIS = Join-Path (Split-Path -Parent $env:THIS) 'folder with spaces/menu.cmd'
        $target = Join-Path (Split-Path -Parent $env:THIS) 'Resources/NVIDIA-PROFILE-INSPECTOR'
        $null = New-Item -ItemType Directory -Path $target -Force
        Copy-Item -LiteralPath $exe -Destination $target
        Copy-Item -LiteralPath $profile -Destination $target
        $expectedProfile = Join-Path $target 'NvidiaV2.nip'
        $result = Invoke-NvidiaProfileInspector 6>$null -ImportProfile
        Assert-True ($result -eq $false) 'Unverifiable driver import must remain a warning.'
        Assert-True ($script:NvpiStarts.Count -eq 1) 'Expected one import launch.'
        $call = $script:NvpiStarts[0]
        Assert-True ($call.Wait -and $call.PassThru) 'Import must await its process.'
        Assert-True ($call.Arguments.Count -eq 2 -and $call.Arguments[0] -eq '-mergeImport') 'Import must explicitly merge, without silent/replace switches.'
        Assert-True ($call.Arguments[1] -eq ('"' + $expectedProfile + '"')) 'Profile path with spaces must be quoted.'
    }
}
foreach ($missing in @('exe', 'profile')) {
    Test-Case ('NVPI import does not start when missing ' + $missing) {
        Test-NvpiFixture {
            param($exe, $profile)
            $path = if ($missing -eq 'exe') { $exe } else { $profile }
            Remove-Item -LiteralPath $path
            Assert-True (-not (Invoke-NvidiaProfileInspector -ImportProfile 6>$null)) 'Missing resource must fail.'
            Assert-True ($script:NvpiStarts.Count -eq 0) 'Process started without required resource.'
        }
    }
}
Test-Case 'NVPI handles a nonzero exit code and process creation failure' {
    Test-NvpiFixture {
        $script:NvpiExitCode = 5
        Assert-True (-not (Invoke-NvidiaProfileInspector -ImportProfile 6>$null)) 'Nonzero exit must fail.'
        $script:NvpiThrow = $true
        Assert-True (-not (Invoke-NvidiaProfileInspector 6>$null)) 'Failed process creation must fail.'
    }
}
foreach ($vendor in @('AMD', '', 'NVIDIA', 'BOTH')) {
    Test-Case ('NVPI Auto dispatch for GPU vendor [' + $vendor + ']') {
        function Get-DetectedGpuVendorAuto { return $vendor }
        function Write-BoxTitle { param($Title) }
        $script:NvpiImportCalls = 0
        function Invoke-NvidiaProfileInspector {
            param([switch]$ImportProfile)
            Assert-True $ImportProfile 'Auto must request import.'
            $script:NvpiImportCalls++
            return $false
        }
        $result = Invoke-NvidiaProfileInspectorImportAuto 6>$null
        $supported = $vendor -in @('NVIDIA','BOTH')
        Assert-True ($script:NvpiImportCalls -eq [int]$supported) 'Incorrect GPU vendor dispatch.'
        Assert-True ($result -eq (-not $supported)) 'Import warning or non-NVIDIA skip result lost.'
    }
}

# Exercise the actual action functions' cancellation paths, replacing every
# external command they could call with a throwing stub. This catches a guard
# accidentally moved after an action, not just a changed confirmation helper.
foreach ($actionName in @('Invoke-AutoRegistryTweaks', 'Invoke-QolOptimize')) {
    Test-Case ($actionName + ' returns before any action when confirmation is cancelled') {
        $actionAst = $asts.v2.Find({ param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $actionName
        }, $true)
        Assert-True ($null -ne $actionAst) ('Missing action: ' + $actionName)
        & {
            . ([scriptblock]::Create($actionAst.Extent.Text))
            $commands = @($actionAst.FindAll({ param($node)
                $node -is [System.Management.Automation.Language.CommandAst]
            }, $true) | ForEach-Object { $_.GetCommandName() } | Where-Object { $_ } | Select-Object -Unique)
            foreach ($command in $commands) {
                if ($command -ne 'Confirm-LlcBroadChanges') {
                    Set-Item -Path ('Function:\' + $command) -Value { throw 'Action reached before confirmation.' }
                }
            }
            function Confirm-LlcBroadChanges { param($Scope) $script:ConfirmCalls++; return $false }
            $script:ConfirmCalls = 0
            & $actionName
            if ($script:ConfirmCalls -ne 1) { throw 'Expected exactly one confirmation.' }
        }
    }
}

Test-Case 'preflight exit precedes transcripts and native initialization' {
    $checkBranch = @($asts.v2.EndBlock.Statements | Where-Object {
        $_ -is [System.Management.Automation.Language.IfStatementAst] -and $_.Extent.Text.StartsWith("if (`$env:LLC_RUN_CHECK -eq '1')")
    })
    Assert-True ($checkBranch.Count -eq 1) 'Missing unique check branch.'
    $firstSensitiveCommand = @($asts.v2.FindAll({ param($node)
        if ($node -isnot [System.Management.Automation.Language.CommandAst] -or
            $node.GetCommandName() -notin @('Start-Transcript', 'Add-Type', 'Initialize-TrustedInstallerToken')) { return $false }
        # A function declaration does not execute its Add-Type body. Inspect
        # commands that can actually run while the script initializes.
        for ($parent = $node.Parent; $null -ne $parent; $parent = $parent.Parent) {
            if ($parent -is [System.Management.Automation.Language.FunctionDefinitionAst]) { return $false }
        }
        return $true
    }, $true) | Sort-Object { $_.Extent.StartOffset })[0]
    Assert-True ($checkBranch[0].Extent.EndOffset -lt $firstSensitiveCommand.Extent.StartOffset) 'Preflight must precede native initialization.'
    Assert-True ($checkBranch[0].Clauses[0].Item2.Statements[-1] -is [System.Management.Automation.Language.ExitStatementAst]) 'Check branch must exit unconditionally.'
}

# Run the real complete payload only with the check flag, in a child process.
# Environment and temporary files are restored even when an assertion fails.
Test-Case 'check-mode child process exits before transcript and reports actual host status' {
    $tmpDir = Join-Path ([IO.Path]::GetTempPath()) ('llc-v2-test-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $tmpDir
    $tmpScript = Join-Path $tmpDir 'payload.ps1'
    $tmpLog = Join-Path $tmpDir 'must-not-exist.log'
    $oldMode = $env:LLC_RUN_CHECK
    $oldSource = $env:THIS
    $oldLog = $env:LLC_MENU_DEBUG_LOG
    try {
        [IO.File]::WriteAllText($tmpScript, $newSource, (New-Object Text.UTF8Encoding($true)))
        $env:LLC_RUN_CHECK = '1'
        $env:THIS = $newPath
        $env:LLC_MENU_DEBUG_LOG = $tmpLog
        $engine = (Get-Process -Id $PID).Path
        $output = & $engine -NoLogo -NoProfile -File $tmpScript 2>&1
        $childExit = $LASTEXITCODE
        $expectedExit = if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT -and $PSVersionTable.PSEdition -eq 'Desktop' -and [Environment]::Is64BitProcess) { 0 } else { 2 }
        Assert-True ($childExit -eq $expectedExit) ('Unexpected check exit: {0}; output: {1}' -f $childExit, ($output -join "`n"))
        Assert-True (($output -join "`n").Contains('PASS: PowerShell payload syntax.')) 'Check did not report successful parsing.'
        Assert-True (-not (Test-Path -LiteralPath $tmpLog)) 'Check unexpectedly started a transcript.'
    }
    finally {
        $env:LLC_RUN_CHECK = $oldMode
        $env:THIS = $oldSource
        $env:LLC_MENU_DEBUG_LOG = $oldLog
        Remove-Item -LiteralPath $tmpDir -Recurse -Force
    }
}

if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
    Test-Case 'CMD /help exits without launching the application' {
        $output = & $env:ComSpec /d /c ('""{0}" /help"' -f $newPath) 2>&1
        Assert-True ($LASTEXITCODE -eq 0) 'CMD /help failed.'
        Assert-True (($output -join "`n").Contains('No tweaks applied.')) 'CMD help text was not shown.'
    }
    Test-Case 'CMD /check forwards syntax result and process exit code' {
        $output = & $env:ComSpec /d /c ('""{0}" /check"' -f $newPath) 2>&1
        $actualExit = $LASTEXITCODE
        $expectedExit = if ([Environment]::Is64BitProcess) { 0 } else { 2 }
        Assert-True ($actualExit -eq $expectedExit) ('CMD /check exit: ' + $actualExit)
        Assert-True (($output -join "`n").Contains('PASS: PowerShell payload syntax.')) 'CMD /check did not reach syntax check.'
    }
} else {
    $script:Skipped += 2
    Write-Host 'SKIP: CMD /help and /check launchers require Windows cmd.exe.' -ForegroundColor Yellow
}

Write-Host ('Completed: {0} passed, {1} skipped. Windows tweaks and hardware behavior were not exercised.' -f $script:Passed, $script:Skipped) -ForegroundColor Cyan
# /check deliberately returns 2 on Linux. Do not leak that expected child exit
# into the GitHub Actions PowerShell wrapper after all assertions have passed.
exit 0
