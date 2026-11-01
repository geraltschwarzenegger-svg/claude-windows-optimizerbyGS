# UI-only regression checks. Never dot-source the application payload.
# Only /demo /snapshot is allowed to run as a complete child script.
$ErrorActionPreference = 'Stop'
$script:Passed = 0
$script:Skipped = 0
$repo = Split-Path -Parent $PSScriptRoot
$cmdPath = Join-Path $repo 'Low-Latency-Corp-Menu_v2.cmd'
$sourceLines = [IO.File]::ReadAllLines($cmdPath)
$markers = @(0..($sourceLines.Length - 1) | Where-Object { $sourceLines[$_] -eq '### POWERSHELL STARTS HERE ###' })
if ($markers.Count -ne 1) { throw 'Expected exactly one payload marker.' }
$payload = $sourceLines[($markers[0] + 1)..($sourceLines.Length - 1)] -join "`n"
$tokens = $null; $parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput($payload, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw ('Payload parse failure: ' + ($parseErrors -join '; ')) }

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

foreach ($name in @('Format-LlcMenuText', 'Get-LlcMenuEntries', 'Get-LlcMenuNextIndex', 'Get-LlcMenuValue', 'Get-LlcMenuFrame', 'ConvertTo-LlcMenuAnsiFrame', 'Get-LlcMainMenuItems', 'Invoke-Menu')) {
    $definitions = @($ast.FindAll({ param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
    }, $true))
    Assert-True ($definitions.Count -eq 1) ('Missing or duplicate UI helper: ' + $name)
    . ([scriptblock]::Create($definitions[0].Extent.Text))
}

$mainItems = @(Get-LlcMainMenuItems)
$mixedItems = @(
    $null, '',
    [pscustomobject]@{ Text='Section'; Kind='Header' },
    'First',
    [pscustomobject]@{ Text='Second'; Value='second'; Description='A description' },
    [pscustomobject]@{ Text='Ignored'; Selectable=$false },
    '   ',
    [pscustomobject]@{ Text='Third'; Value=17 },
    [pscustomobject]@{ Text='Fourth'; Value=$null }
)

Test-Case 'normalization removes blank rows while preserving original indices and headers' {
    $entries = @(Get-LlcMenuEntries -Items $mixedItems)
    Assert-True (($entries.Index -join ',') -eq '2,3,4,5,7,8') 'Normalized original indices changed.'
    Assert-True (-not $entries[0].Selectable -and -not $entries[3].Selectable) 'Header became selectable.'
    Assert-True ($entries[2].Description -eq 'A description') 'Description was lost.'
}
Test-Case 'labels sanitize control characters before rendering' {
    $entry = @(Get-LlcMenuEntries -Items @(" A`r`nB$([char]27)[31m "))[0]
    Assert-True (-not ($entry.Text -match '[\x00-\x1f\x7f-\x9f]')) 'Label contains an escape or newline.'
    Assert-True ($entry.Text.StartsWith('A')) 'Label was not trimmed.'
}
Test-Case 'Home and End skip headers and return raw item indices' {
    Assert-True ((Get-LlcMenuNextIndex -Items $mixedItems -Key Home) -eq 3) 'Home selected a header.'
    Assert-True ((Get-LlcMenuNextIndex -Items $mixedItems -Key End) -eq 8) 'End selected an invalid row.'
}
Test-Case 'arrow navigation skips blank rows and headers and wraps at both ends' {
    Assert-True ((Get-LlcMenuNextIndex -Items $mixedItems -CurrentIndex 4 -Key DownArrow) -eq 7) 'Down selected a header.'
    Assert-True ((Get-LlcMenuNextIndex -Items $mixedItems -CurrentIndex 7 -Key UpArrow) -eq 4) 'Up selected a header.'
    Assert-True ((Get-LlcMenuNextIndex -Items $mixedItems -CurrentIndex 3 -Key UpArrow) -eq 8) 'Up did not wrap.'
    Assert-True ((Get-LlcMenuNextIndex -Items $mixedItems -CurrentIndex 8 -Key DownArrow) -eq 3) 'Down did not wrap.'
}
Test-Case 'page navigation advances selectable rows and clamps at boundaries' {
    Assert-True ((Get-LlcMenuNextIndex -Items $mixedItems -CurrentIndex 3 -Key PageDown -PageSize 2) -eq 7) 'PageDown ignored page size.'
    Assert-True ((Get-LlcMenuNextIndex -Items $mixedItems -CurrentIndex 8 -Key PageUp -PageSize 2) -eq 4) 'PageUp ignored page size.'
    Assert-True ((Get-LlcMenuNextIndex -Items $mixedItems -CurrentIndex 7 -Key PageDown -PageSize 100) -eq 8) 'PageDown wrapped instead of clamping.'
    Assert-True ((Get-LlcMenuNextIndex -Items $mixedItems -CurrentIndex 4 -Key PageUp -PageSize 100) -eq 3) 'PageUp wrapped instead of clamping.'
    Assert-True ((Get-LlcMenuNextIndex -Items $mixedItems -CurrentIndex 4 -Key PageDown -PageSize 0) -eq 7) 'Nonpositive page size failed.'
}
Test-Case 'invalid selection recovers and unsupported keys preserve a valid selection' {
    Assert-True ((Get-LlcMenuNextIndex -Items $mixedItems -CurrentIndex 999 -Key DownArrow) -eq 3) 'Invalid selection was not repaired.'
    Assert-True ((Get-LlcMenuNextIndex -Items $mixedItems -CurrentIndex 7 -Key F1) -eq 7) 'Unknown key moved selection.'
}
Test-Case 'empty and all-header menus return without reading terminal input' {
    $onlyHeaders = @($null, '', [pscustomobject]@{Text='Header'; Selectable=$false})
    Assert-True ((Get-LlcMenuNextIndex -Items @() -Key Home) -eq -1) 'Empty menu returned an index.'
    Assert-True ((Get-LlcMenuNextIndex -Items $onlyHeaders -Key End) -eq -1) 'Header-only menu returned an index.'
    Assert-True ((Invoke-Menu -Title 'Empty' -Items @()) -eq -1) 'Empty menu tried interactive rendering.'
    Assert-True ((Invoke-Menu -Title 'Headers' -Items $onlyHeaders) -eq -1) 'Header-only menu tried interactive rendering.'
}
Test-Case 'value contract preserves string integer null and raw index fallbacks' {
    Assert-True ((Get-LlcMenuValue -Items $mixedItems -Index 3) -eq 3) 'String item lost raw index.'
    Assert-True ((Get-LlcMenuValue -Items $mixedItems -Index 4) -ceq 'second') 'Explicit string value changed.'
    Assert-True ((Get-LlcMenuValue -Items $mixedItems -Index 7) -eq 17) 'Integer value changed.'
    Assert-True ($null -eq (Get-LlcMenuValue -Items $mixedItems -Index 8)) 'Explicit null value changed.'
    Assert-True ((Get-LlcMenuValue -Items $mixedItems -Index 2) -eq -1) 'Header can be selected.'
    Assert-True ((Get-LlcMenuValue -Items $mixedItems -Index 999) -eq -1) 'Missing index can be selected.'
}
Test-Case 'main menu factory preserves backend dispatch values with dynamic hardware labels' {
    $expected = 'preflight,autoRegistryTweaks,uac,qol,fullscreenOptimization,gamebarAndGameMode,services,powersaving,networkOptimization,mmcss,win32PrioritySeparation,clockInterrupts,hags,gpu,drivers,apps,autostart,powerPlan,activateWindows,exit'
    $entries = @(Get-LlcMenuEntries -Items $mainItems | Where-Object { $_.Selectable })
    Assert-True (($entries.Value -join ',') -ceq $expected) 'Main-menu dispatch contract changed.'
    $dynamic = @(Get-LlcMenuEntries -Items @(Get-LlcMainMenuItems -GpuText 'Test GPU' -DriverText 'Test drivers' -MmcssText 'Test stack'))
    Assert-True (($dynamic | Where-Object { $_.Value -eq 'gpu' }).Text -eq 'Test GPU') 'GPU label lost.'
    Assert-True (($dynamic | Where-Object { $_.Value -eq 'drivers' }).Text -eq 'Test drivers') 'Driver label lost.'
    Assert-True (($dynamic | Where-Object { $_.Value -eq 'mmcss' }).Text -eq 'Test stack') 'MMCSS label lost.'
}

function Assert-FrameBounds {
    param([object]$Frame, [int]$Width, [int]$Height)
    Assert-True ($Frame.Lines.Count -le [Math]::Max(0, $Height - 1)) 'Frame crosses the bottom viewport row.'
    Assert-True ($Frame.Lines.Count -eq $Frame.Styles.Count) 'Styles and text rows differ.'
    foreach ($line in $Frame.Lines) {
        Assert-True ($line.Length -le [Math]::Max(0, $Width - 1)) 'ASCII frame line could wrap.'
        Assert-True (-not ($line -match '[\x00-\x1f\x7f-\x9f]')) 'A frame line contains terminal control characters.'
    }
}
Test-Case '80x30 main menu contains exactly one selection and keeps the final item visible' {
    $lastIndex = Get-LlcMenuNextIndex -Items $mainItems -Key End
    $frame = Get-LlcMenuFrame -Title 'Main menu' -Items $mainItems -SelectedIndex $lastIndex -Width 80 -Height 30
    Assert-FrameBounds $frame 80 30
    Assert-True ($frame.VisibleIndices -contains $lastIndex) 'Selected final item is below the viewport.'
    Assert-True ($frame.TopIndex -gt 0) 'Long menu did not scroll.'
    Assert-True (@($frame.Styles | Where-Object { $_ -eq 'selected' }).Count -eq 1) 'Selection is missing or duplicated.'
    Assert-True ($frame.Lines[$frame.SelectedRow].Contains('Exit')) 'Selected row points to the wrong item.'
}
Test-Case 'viewport matrix stays bounded from zero size through large terminals' {
    foreach ($width in @(0, 1, 2, 10, 39, 40, 80, 180)) {
        foreach ($height in @(0, 1, 2, 5, 9, 10, 30, 60)) {
            $frame = Get-LlcMenuFrame -Title ('Very long title ' * 30) -Items $mainItems -SelectedIndex 22 -Width $width -Height $height
            Assert-FrameBounds $frame $width $height
            Assert-True ($frame.IsTooSmall -eq ($width -lt 40 -or $height -lt 10)) 'Small-terminal status is wrong.'
            if ($frame.IsTooSmall) {
                Assert-True ($frame.SelectedRow -eq -1 -and $frame.VisibleRows -eq 0) 'Tiny viewport exposed an actionable item.'
            } else {
                Assert-True ($frame.VisibleIndices -contains 22) 'Selection was clipped.'
            }
        }
    }
}
Test-Case 'long labels title and descriptions never add physical terminal rows' {
    $items = @([pscustomobject]@{ Text=('Label ' * 100) + "`nBAD$([char]27)"; Description=('Details ' * 100) + "`r`nBAD" })
    $frame = Get-LlcMenuFrame -Title ("Title`n" * 100) -Items $items -SelectedIndex 0 -Width 40 -Height 10
    Assert-FrameBounds $frame 40 10
    Assert-True ($frame.SelectedRow -ge 0) 'Long label hid selected item.'
}
Test-Case 'scrolling upward repairs an old viewport offset and extreme offsets are clamped' {
    foreach ($top in @(-100, 0, 10000)) {
        $frame = Get-LlcMenuFrame -Title 'Top' -Items $mainItems -SelectedIndex 0 -TopIndex $top -Width 80 -Height 10
        Assert-True ($frame.TopIndex -eq 0 -and $frame.VisibleIndices -contains 0) 'Selection did not pull viewport upward.'
    }
}
Test-Case 'selection and description survive repeated paging and resizing' {
    $index = 0; $top = 0
    foreach ($step in @(@('End',80,30), @('PageUp',40,10), @('Home',80,20), @('DownArrow',120,60), @('PageDown',40,12))) {
        $index = Get-LlcMenuNextIndex -Items $mainItems -CurrentIndex $index -Key $step[0] -PageSize 4
        $frame = Get-LlcMenuFrame -Title 'Resize' -Items $mainItems -SelectedIndex $index -TopIndex $top -Width $step[1] -Height $step[2]
        $top = $frame.TopIndex
        Assert-FrameBounds $frame $step[1] $step[2]
        Assert-True ($frame.VisibleIndices -contains $index) 'Resize hid selected item.'
        Assert-True (@($frame.Styles | Where-Object { $_ -eq 'selected' }).Count -eq 1) 'Resize duplicated selection.'
    }
    $frame = Get-LlcMenuFrame -Title 'Details' -Items $mainItems -SelectedIndex 0 -Width 100 -Height 30
    Assert-True (($frame.Lines -join "`n").Contains('No system tweaks are applied.')) 'Selected-item description is missing.'
}
Test-Case 'formatter retains Unicode graphemes and clips wide glyphs without splitting surrogate pairs' {
    $accent = 'e' + [char]0x0301
    $emoji = [char]::ConvertFromUtf32(0x1f680)
    $wide = ([char]0x754c).ToString()
    Assert-True ((Format-LlcMenuText -Text ($accent + 'x') -Width 1) -ceq $accent) 'Combining accent split.'
    Assert-True ((Format-LlcMenuText -Text $emoji -Width 1) -ceq '') 'Half of a wide emoji was emitted.'
    Assert-True ((Format-LlcMenuText -Text ($emoji + 'x') -Width 2) -ceq $emoji) 'Emoji surrogate pair split.'
    Assert-True ((Format-LlcMenuText -Text ($wide + 'x') -Width 2) -ceq $wide) 'Wide CJK cell was clipped incorrectly.'
}

# Minimal buffered terminal model: supports the renderer's CSI SGR, home and
# erase-display commands. Repaint over an existing screen, including old tails.
function Apply-AnsiFrame {
    param([string]$Ansi, [object]$Screen)
    $row = 0; $column = 0; $style = ''
    $i = 0
    while ($i -lt $Ansi.Length) {
        $ch = $Ansi[$i]
        if ($ch -eq [char]27) {
            $match = [regex]::Match($Ansi.Substring($i), '^\x1b\[([0-9;]*)([mHJ])')
            Assert-True $match.Success 'Unexpected renderer control sequence.'
            $args = $match.Groups[1].Value
            switch ($match.Groups[2].Value) {
                'm' { $style = $args }
                'H' { $row = 0; $column = 0 }
                'J' {
                    Assert-True ($args -eq '2') 'Renderer must erase the complete display.'
                    for ($y=0; $y -lt $Screen.Height; $y++) {
                        for ($x=0; $x -lt $Screen.Width; $x++) { $Screen.Cells[$y,$x] = ' '; $Screen.Styles[$y,$x] = '' }
                    }
                }
            }
            $i += $match.Length
            continue
        }
        if ($ch -eq "`r") { $column = 0; $i++; continue }
        if ($ch -eq "`n") { $row++; $i++; continue }
        Assert-True ($row -lt $Screen.Height -and $column -lt $Screen.Width) 'Renderer overflowed terminal cells.'
        $Screen.Cells[$row,$column] = [string]$ch
        $Screen.Styles[$row,$column] = $style
        $column++; $i++
    }
}
Test-Case 'ANSI repaint clears old rows and leaves exactly one highlight after long-to-short menus' {
    $screen = [pscustomobject]@{ Width=80; Height=30; Cells=(New-Object 'string[,]' 30,80); Styles=(New-Object 'string[,]' 30,80) }
    $frames = @(
        (Get-LlcMenuFrame -Title 'Main' -Items $mainItems -SelectedIndex 0 -Width 80 -Height 30),
        (Get-LlcMenuFrame -Title 'Main' -Items $mainItems -SelectedIndex 22 -Width 80 -Height 30),
        (Get-LlcMenuFrame -Title 'Short' -Items @('One', 'Two') -SelectedIndex 1 -Width 40 -Height 12),
        (Get-LlcMenuFrame -Title 'Tiny' -Items $mainItems -SelectedIndex 0 -Width 30 -Height 6)
    )
    foreach ($frame in $frames) {
        $ansi = ConvertTo-LlcMenuAnsiFrame -Frame $frame
        Assert-True (-not $ansi.EndsWith("`n")) 'Trailing newline could scroll the viewport.'
        Apply-AnsiFrame -Ansi $ansi -Screen $screen
        $highlightedRows = @()
        for ($y=0; $y -lt $screen.Height; $y++) {
            $expected = if ($y -lt $frame.Lines.Count) { $frame.Lines[$y].PadRight(80) } else { ' ' * 80 }
            $actual = -join (0..79 | ForEach-Object { $screen.Cells[$y,$_] })
            Assert-True ($actual -ceq $expected) ('Screen retained old text at row ' + $y)
            if (@(0..79 | Where-Object { $screen.Styles[$y,$_] -match '48;2;27;54;78' }).Count -gt 0) { $highlightedRows += $y }
        }
        $expectedCount = if ($frame.IsTooSmall) { 0 } else { 1 }
        Assert-True ($highlightedRows.Count -eq $expectedCount) 'Screen retained a duplicate selection highlight.'
        if ($expectedCount) { Assert-True ($highlightedRows[0] -eq $frame.SelectedRow) 'Highlight is on the wrong row.' }
    }
}

Test-Case 'demo branch exits before backend initialization and only invokes UI helpers' {
    $demoBranch = @($ast.EndBlock.Statements | Where-Object {
        $_ -is [System.Management.Automation.Language.IfStatementAst] -and $_.Extent.Text.StartsWith("if (`$env:LLC_MENU_DEMO -eq '1')")
    })
    Assert-True ($demoBranch.Count -eq 1) 'Demo entry point missing.'
    $body = $demoBranch[0].Clauses[0].Item2
    Assert-True ($body.Statements[-1] -is [System.Management.Automation.Language.ExitStatementAst]) 'Demo must unconditionally exit.'
    $commands = @($body.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true))
    foreach ($command in $commands) {
        Assert-True ($command.GetCommandName() -in @('Get-LlcMainMenuItems', 'Get-LlcMenuFrame', 'Invoke-Menu')) ('Demo invoked a backend command: ' + $command.GetCommandName())
    }
    $hostAssignment = @($ast.EndBlock.Statements | Where-Object { $_.Extent.Text.StartsWith('$llcPreflight =') })[0]
    Assert-True ($demoBranch[0].Extent.EndOffset -lt $hostAssignment.Extent.StartOffset) 'Demo did not bypass host setup.'
}
Test-Case 'demo snapshot child runs without admin or transcript and matches the 80x30 frame' {
    $tmpDir = Join-Path ([IO.Path]::GetTempPath()) ('llc-ui-test-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $tmpDir
    $scriptPath = Join-Path $tmpDir 'payload.ps1'
    $logPath = Join-Path $tmpDir 'must-not-exist.log'
    $oldDemo = $env:LLC_MENU_DEMO; $oldSnapshot = $env:LLC_MENU_SNAPSHOT; $oldLog = $env:LLC_MENU_DEBUG_LOG
    try {
        [IO.File]::WriteAllText($scriptPath, $payload, (New-Object Text.UTF8Encoding($true)))
        $env:LLC_MENU_DEMO='1'; $env:LLC_MENU_SNAPSHOT='1'; $env:LLC_MENU_DEBUG_LOG=$logPath
        $engine = (Get-Process -Id $PID).Path
        $output = @(& $engine -NoLogo -NoProfile -File $scriptPath 2>&1)
        Assert-True ($LASTEXITCODE -eq 0) ('Demo child failed: ' + ($output -join "`n"))
        $items = @(Get-LlcMainMenuItems -GpuText 'GPU - demo adapter' -DriverText 'Drivers - demo adapter' -MmcssText 'MMCSS - demo stack')
        $expected = Get-LlcMenuFrame -Title 'UI PREVIEW - no system changes' -Items $items -SelectedIndex 0 -Width 80 -Height 30
        Assert-True (($output -join "`n") -ceq ($expected.Lines -join "`n")) 'Demo output differs from pure frame.'
        Assert-True ($output.Count -le 29) 'Demo snapshot exceeds 80x30 viewport.'
        Assert-True (-not (Test-Path -LiteralPath $logPath)) 'Demo started backend transcript.'
    } finally {
        $env:LLC_MENU_DEMO=$oldDemo; $env:LLC_MENU_SNAPSHOT=$oldSnapshot; $env:LLC_MENU_DEBUG_LOG=$oldLog
        Remove-Item -LiteralPath $tmpDir -Recurse -Force
    }
}
Test-Case 'interactive demo with redirected output fails clearly without initializing backend' {
    $tmpDir = Join-Path ([IO.Path]::GetTempPath()) ('llc-ui-no-tty-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $tmpDir
    $scriptPath = Join-Path $tmpDir 'payload.ps1'
    $logPath = Join-Path $tmpDir 'must-not-exist.log'
    $oldDemo = $env:LLC_MENU_DEMO; $oldSnapshot = $env:LLC_MENU_SNAPSHOT; $oldLog = $env:LLC_MENU_DEBUG_LOG
    try {
        [IO.File]::WriteAllText($scriptPath, $payload, (New-Object Text.UTF8Encoding($true)))
        $env:LLC_MENU_DEMO='1'; $env:LLC_MENU_SNAPSHOT=$null; $env:LLC_MENU_DEBUG_LOG=$logPath
        $engine = (Get-Process -Id $PID).Path
        # Capturing output deliberately removes the interactive output terminal.
        $output = @(& $engine -NoLogo -NoProfile -File $scriptPath 2>&1)
        $actualExit = $LASTEXITCODE
        $text = $output -join "`n"
        Assert-True ($actualExit -eq 2) ('Redirected interactive demo must return 2, got ' + $actualExit + ': ' + $text)
        Assert-True ($text -match 'interactive terminal is required') 'Missing actionable terminal diagnostic.'
        Assert-True (-not $text.Contains('UI preview closed.')) 'Failed preview falsely reported successful closure.'
        Assert-True (-not (Test-Path -LiteralPath $logPath)) 'Failed preview started backend transcript.'
    } finally {
        $env:LLC_MENU_DEMO=$oldDemo; $env:LLC_MENU_SNAPSHOT=$oldSnapshot; $env:LLC_MENU_DEBUG_LOG=$oldLog
        Remove-Item -LiteralPath $tmpDir -Recurse -Force
    }
}
if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
    Test-Case 'CMD /demo /snapshot launches the isolated UI on Windows' {
        $output = @(& $env:ComSpec /d /c ('""{0}" /demo /snapshot"' -f $cmdPath) 2>&1)
        Assert-True ($LASTEXITCODE -eq 0) 'Windows CMD demo failed.'
        Assert-True (($output -join "`n").Contains('UI PREVIEW - no system changes')) 'CMD demo did not produce the UI.'
        Assert-True ($output.Count -le 29) 'CMD demo exceeded viewport height.'
    }
} else {
    $script:Skipped++
    Write-Host 'SKIP: CMD /demo /snapshot launcher requires Windows cmd.exe.' -ForegroundColor Yellow
}
Write-Host ('Menu checks: {0} passed, {1} skipped. No Windows tweaks were applied.' -f $script:Passed, $script:Skipped) -ForegroundColor Cyan
exit 0
