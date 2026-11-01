@echo off
setlocal EnableExtensions
title Low Latency Corp Menu v2
set "LLC_RUN_CHECK="
set "LLC_MENU_DEMO="
set "LLC_MENU_SNAPSHOT="
if /i "%~1"=="/demo" goto llcDemoArgs
if not "%~2"=="" goto llcUsage
if "%~1"=="" goto llcArgsReady
if /i "%~1"=="/check" (
    set "LLC_RUN_CHECK=1"
    goto llcArgsReady
)
if /i "%~1"=="/help" goto llcHelp
if /i "%~1"=="/?" goto llcHelp
goto llcUsage
:llcDemoArgs
if not "%~3"=="" goto llcUsage
set "LLC_MENU_DEMO=1"
if "%~2"=="" goto llcArgsReady
if /i not "%~2"=="/snapshot" goto llcUsage
set "LLC_MENU_SNAPSHOT=1"
goto llcArgsReady
:llcUsage
echo Unknown arguments. Use /check, /demo, /demo /snapshot or /help.
exit /b 2
:llcHelp
echo Low Latency Corp Menu v2
echo   No arguments: open the interactive menu as Administrator.
echo   /check      : check payload syntax and basic host prerequisites only.
echo                 No administrator rights required. No tweaks applied.
echo   /demo       : preview the interactive UI without applying any settings.
echo   /demo /snapshot : print a noninteractive UI preview and exit.
echo   /help       : show this help.
echo /check exit codes: 0=basic checks passed, 1=payload error, 2=unsupported host.
echo Missing Resources are reported but do not fail the basic host check.
exit /b 0
:llcArgsReady
set "THIS=%~f0"
set "PSPAYLOAD=%TEMP%\Windows_Tweaks_Menu_%RANDOM%_%RANDOM%.ps1"
set "LLC_MENU_DEBUG_LOG=%TEMP%\LowLatencyCorpMenu_Debug_%RANDOM%_%RANDOM%.log"

powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $src=$env:THIS; $out=$env:PSPAYLOAD; $marker='### POWERSHELL STARTS HERE ###'; $lines=Get-Content -LiteralPath $src; $i=[Array]::IndexOf($lines,$marker); if($i -lt 0){ throw 'PowerShell payload marker not found.' }; $lines[($i+1)..($lines.Count-1)] | Set-Content -LiteralPath $out -Encoding UTF8"
if errorlevel 1 (
    echo.
    echo FAILED: Could not extract PowerShell payload from this CMD file.
    echo This usually means the script marker is missing or the file was damaged.
    echo.
    del "%PSPAYLOAD%" >nul 2>&1
    if not defined LLC_RUN_CHECK if not defined LLC_MENU_DEMO pause
    exit /b 1
)

powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%PSPAYLOAD%"
set "APP_EXIT=%ERRORLEVEL%"
if defined LLC_RUN_CHECK goto llcCleanup
if defined LLC_MENU_DEMO goto llcCleanup

if not "%APP_EXIT%"=="0" (
    echo.
    echo ============================================================
    echo FAILED: The PowerShell payload exited with code %APP_EXIT%.
    echo The error output should be visible above.
    echo.
    echo Debug log:
    echo "%LLC_MENU_DEBUG_LOG%"
    echo ============================================================
    echo.
    if exist "%LLC_MENU_DEBUG_LOG%" (
        echo Full debug log:
        echo ------------------------------------------------------------
        powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Get-Content -LiteralPath $env:LLC_MENU_DEBUG_LOG -ErrorAction Stop } catch { Write-Host $_.Exception.Message }"
        echo ------------------------------------------------------------
        echo.
    ) else (
        echo The debug log was not created. That usually means PowerShell failed while parsing the script before startup code could run.
        echo In that case, use the visible error text above.
        echo.
    )
    pause
)

:llcCleanup
del "%PSPAYLOAD%" >nul 2>&1
exit /b %APP_EXIT%

### POWERSHELL STARTS HERE ###
# V2: read-only preflight runs before transcripts, native types and system changes.
function Get-LlcPreflightResult {
    $issues = @()
    $isWindowsHost = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
    if (-not $isWindowsHost) { $issues += 'Windows is required; no tweaks were executed.' }
    if (($PSVersionTable.PSVersion -lt [version]'5.1') -or ($PSVersionTable.PSEdition -ne 'Desktop')) {
        $issues += 'Use Windows PowerShell 5.1 (powershell.exe), not PowerShell 7 (pwsh.exe).'
    }
    if (-not [Environment]::Is64BitProcess) {
        $issues += 'Use a 64-bit Windows PowerShell process.'
    }
    $sourceDirectory = if ([string]::IsNullOrWhiteSpace($env:THIS)) { $PSScriptRoot } else { Split-Path -Parent $env:THIS }
    $resourcesPath = Join-Path $sourceDirectory 'Resources'
    return [pscustomobject]@{
        Ready = ($issues.Count -eq 0)
        Issues = $issues
        HostVersion = [string]$PSVersionTable.PSVersion
        HostEdition = [string]$PSVersionTable.PSEdition
        Is64Bit = [Environment]::Is64BitProcess
        ResourcesPresent = (Test-Path -LiteralPath $resourcesPath -PathType Container)
        ResourcesPath = $resourcesPath
        BundledDeviceTweakerPresent = (Test-Path -LiteralPath (Join-Path $sourceDirectory 'DEVICE-TWEAKER\RUN-DEVICE-TWEAKER.bat') -PathType Leaf)
        BundledPowerPlanPresent = (Test-Path -LiteralPath (Join-Path $sourceDirectory 'POWER-PLAN\LLC-CERTIFIED.pow') -PathType Leaf)
    }
}

function Write-LlcPreflightReport {
    param([Parameter(Mandatory=$true)][object]$Result)
    Write-Host 'Low Latency Corp Menu v2 - preflight' -ForegroundColor Cyan
    Write-Host ('PowerShell: {0} ({1}); 64-bit process: {2}' -f $Result.HostVersion, $Result.HostEdition, $Result.Is64Bit)
    foreach ($issue in $Result.Issues) { Write-Host ('FAIL: ' + $issue) -ForegroundColor Red }
    if ($Result.Ready) { Write-Host 'PASS: basic host prerequisites.' -ForegroundColor Green }
    if ($Result.ResourcesPresent) {
        Write-Host ('Resources directory found: ' + $Result.ResourcesPath)
        Write-Host 'Its presence does not verify individual tools, profiles or installers.' -ForegroundColor Yellow
    } else {
        Write-Host ('OPTIONAL: Resources directory is missing: ' + $Result.ResourcesPath) -ForegroundColor Yellow
        Write-Host 'Other Apps, local driver installers and .nip import require additional files.' -ForegroundColor Yellow
    }
    Write-Host ('Bundled Device Tweaker launcher present: ' + $Result.BundledDeviceTweakerPresent)
    Write-Host ('Bundled power plan present: ' + $Result.BundledPowerPlanPresent)
    Write-Host 'File presence does not verify authenticity or compatibility.' -ForegroundColor Yellow
    Write-Host 'This is a host and syntax check, not a dry run or a compatibility test of every tweak.'
    Write-Host 'No registry, service, power, display or network changes were applied by preflight.'
}

function Confirm-LlcBroadChanges {
    param([Parameter(Mandatory=$true)][ValidateSet('Auto', 'QOL')][string]$Scope)
    Write-Host ''
    Write-Host ('Review before applying ' + $Scope) -ForegroundColor Yellow
    if ($Scope -eq 'Auto') {
        Write-Host 'Auto disables UAC and selected services, applies QOL across user profiles, disables OneDrive,'
        Write-Host 'and changes display, power, network, scheduling and GPU settings.'
    } else {
        Write-Host 'QOL changes current, other and Default user profiles plus machine policies.'
        Write-Host 'It disables OneDrive, clears Explorer history and resets taskbar pins to Explorer only.'
    }
    Write-Host 'There is no complete automatic backup or rollback. Prepare a backup first.' -ForegroundColor Yellow
    Write-Host ('Type ' + $Scope.ToUpperInvariant() + ' to continue. Enter or any other input cancels.')
    try { $answer = Read-Host 'Confirm' } catch { return $false }
    return ([string]$answer -ceq $Scope.ToUpperInvariant())
}

function Assert-LlcDownloadLength {
    param(
        [Parameter(Mandatory=$true)][Int64]$DownloadedBytes,
        [Parameter(Mandatory=$true)][Int64]$TotalBytes
    )
    if ($DownloadedBytes -le 0) { throw 'Download is empty; installer was not saved.' }
    if (($TotalBytes -ge 0) -and ($DownloadedBytes -ne $TotalBytes)) {
        throw ('Download size mismatch: expected {0} bytes, received {1}; installer was not saved.' -f $TotalBytes, $DownloadedBytes)
    }
}

# The menu is a bounded full frame. Never grow the buffer or cache scrollback rows.
function Format-LlcMenuText {
    param([AllowNull()][string]$Text, [int]$Width, [switch]$Pad)
    $widthLimit = [Math]::Max(0, $Width)
    $clean = ([string]$Text -replace '[\x00-\x1f\x7f-\x9f]', ' ')
    $builder = New-Object Text.StringBuilder
    $cells = 0
    $elements = [Globalization.StringInfo]::GetTextElementEnumerator($clean)
    while ($elements.MoveNext()) {
        $element = $elements.GetTextElement()
        $point = [char]::ConvertToUtf32($element, 0)
        $wide = (($point -ge 0x1100 -and $point -le 0x115f) -or
            ($point -ge 0x2e80 -and $point -le 0xa4cf) -or
            ($point -ge 0xac00 -and $point -le 0xd7a3) -or
            ($point -ge 0xf900 -and $point -le 0xfaff) -or
            ($point -ge 0xfe10 -and $point -le 0xfe6f) -or
            ($point -ge 0xff01 -and $point -le 0xff60) -or
            ($point -ge 0x1f000))
        $size = if ($wide) { 2 } else { 1 }
        if (($cells + $size) -gt $widthLimit) { break }
        [void]$builder.Append($element)
        $cells += $size
    }
    if ($Pad -and $cells -lt $widthLimit) { [void]$builder.Append(' ' * ($widthLimit - $cells)) }
    return $builder.ToString()
}

function Get-LlcMenuEntries {
    param([AllowEmptyCollection()][object[]]$Items)
    for ($i = 0; $i -lt $Items.Count; $i++) {
        $item = $Items[$i]
        if ($null -eq $item) { continue }
        $text = [string]$item
        $selectable = $true
        $value = $i
        $description = ''
        if ($item -isnot [string]) {
            if ($item.PSObject.Properties['Text']) { $text = [string]$item.Text }
            if ($item.PSObject.Properties['Selectable']) { $selectable = [bool]$item.Selectable }
            elseif ($item.PSObject.Properties['Kind'] -and $item.Kind -eq 'Header') { $selectable = $false }
            if ($item.PSObject.Properties['Value']) { $value = $item.Value }
            if ($item.PSObject.Properties['Description']) { $description = [string]$item.Description }
        }
        $text = ($text -replace '[\x00-\x1f\x7f-\x9f]', ' ').Trim()
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        [pscustomobject]@{ Index=$i; Text=$text; Selectable=$selectable; Value=$value; Description=$description }
    }
}

function Get-LlcMenuNextIndex {
    param(
        [AllowEmptyCollection()][object[]]$Items,
        [int]$CurrentIndex = -1,
        [string]$Key = 'Home',
        [int]$PageSize = 1
    )
    $entries = @(Get-LlcMenuEntries -Items $Items)
    $selectable = @($entries | Where-Object { $_.Selectable })
    if ($selectable.Count -eq 0) { return -1 }
    if ($Key -eq 'Home') { return [int]$selectable[0].Index }
    if ($Key -eq 'End') { return [int]$selectable[-1].Index }
    $position = -1
    for ($i = 0; $i -lt $selectable.Count; $i++) {
        if ($selectable[$i].Index -eq $CurrentIndex) { $position = $i; break }
    }
    if ($position -lt 0) { return [int]$selectable[0].Index }
    switch ($Key) {
        'UpArrow' { return [int]$selectable[(($position - 1 + $selectable.Count) % $selectable.Count)].Index }
        'DownArrow' { return [int]$selectable[(($position + 1) % $selectable.Count)].Index }
        'PageUp' { return [int]$selectable[[Math]::Max(0, $position - [Math]::Max(1, $PageSize))].Index }
        'PageDown' { return [int]$selectable[[Math]::Min($selectable.Count - 1, $position + [Math]::Max(1, $PageSize))].Index }
        default { return $CurrentIndex }
    }
}

function Get-LlcMenuValue {
    param([AllowEmptyCollection()][object[]]$Items, [int]$Index)
    $entry = @(Get-LlcMenuEntries -Items $Items | Where-Object { $_.Index -eq $Index -and $_.Selectable })
    if ($entry.Count -eq 0) { return -1 }
    return $entry[0].Value
}

function Get-LlcMenuFrame {
    param(
        [string]$Title,
        [AllowEmptyCollection()][object[]]$Items,
        [int]$SelectedIndex,
        [int]$TopIndex = 0,
        [int]$Width = 80,
        [int]$Height = 30
    )
    $lineWidth = [Math]::Max(0, [Math]::Min(104, $Width - 1))
    $rowLimit = [Math]::Max(0, $Height - 1)
    $lines = New-Object 'Collections.Generic.List[string]'
    $styles = New-Object 'Collections.Generic.List[string]'
    $visible = New-Object 'Collections.Generic.List[int]'
    $entries = @(Get-LlcMenuEntries -Items $Items)
    $selectedRow = -1
    $tooSmall = ($Width -lt 40 -or $Height -lt 10)
    if ($tooSmall) {
        foreach ($text in @('Resize terminal to at least 40 x 10.', 'ESC: back')) {
            if ($lines.Count -ge $rowLimit) { break }
            $lines.Add((Format-LlcMenuText -Text $text -Width $lineWidth -Pad))
            $styles.Add('hint')
        }
        return [pscustomobject]@{ Lines=$lines.ToArray(); Styles=$styles.ToArray(); TopIndex=0; VisibleRows=0; VisibleIndices=@(); SelectedRow=-1; IsTooSmall=$true }
    }
    $capacity = [Math]::Max(1, $Height - 8)
    $rows = [Math]::Min($capacity, $entries.Count)
    $selectedPosition = -1
    for ($i = 0; $i -lt $entries.Count; $i++) {
        if ($entries[$i].Index -eq $SelectedIndex -and $entries[$i].Selectable) { $selectedPosition = $i; break }
    }
    $top = [Math]::Max(0, [Math]::Min($TopIndex, [Math]::Max(0, $entries.Count - $rows)))
    if ($selectedPosition -ge 0) {
        if ($selectedPosition -lt $top) { $top = $selectedPosition }
        if ($selectedPosition -ge ($top + $rows)) { $top = $selectedPosition - $rows + 1 }
    }
    $lines.Add((Format-LlcMenuText -Text ' LOW LATENCY  /  by GS                         v2  PREVIEW 3' -Width $lineWidth -Pad)); $styles.Add('brand')
    $lines.Add((Format-LlcMenuText -Text (' ' + $Title) -Width $lineWidth -Pad)); $styles.Add('title')
    $divider = ' ' + (([char]0x2500).ToString() * [Math]::Max(0, $lineWidth - 2))
    $lines.Add((Format-LlcMenuText -Text $divider -Width $lineWidth -Pad)); $styles.Add('border')
    for ($row = 0; $row -lt $rows; $row++) {
        $entry = $entries[$top + $row]
        $visible.Add([int]$entry.Index)
        if (-not $entry.Selectable) {
            $text = '  [ ' + $entry.Text.TrimEnd(':').ToUpperInvariant() + ' ]'
            $style = 'group'
        } elseif ($entry.Index -eq $SelectedIndex) {
            $selectedRow = $lines.Count
            $text = '  > ' + $entry.Text
            $style = 'selected'
        } else {
            $text = '    ' + $entry.Text
            $style = 'normal'
        }
        $lines.Add((Format-LlcMenuText -Text $text -Width $lineWidth -Pad)); $styles.Add($style)
    }
    $lines.Add((Format-LlcMenuText -Text $divider -Width $lineWidth -Pad)); $styles.Add('border')
    $status = ' Rows {0}-{1} / {2}    PgUp/PgDn: page    Home/End' -f ($top + 1), ($top + $rows), $entries.Count
    $lines.Add((Format-LlcMenuText -Text $status -Width $lineWidth -Pad)); $styles.Add('hint')
    $detail = ' Select an item. Changes run only after you press ENTER.'
    if ($selectedPosition -ge 0 -and -not [string]::IsNullOrWhiteSpace($entries[$selectedPosition].Description)) {
        $detail = ' ' + $entries[$selectedPosition].Description
    }
    $lines.Add((Format-LlcMenuText -Text $detail -Width $lineWidth -Pad)); $styles.Add('detail')
    $lines.Add((Format-LlcMenuText -Text ' UP/DOWN  move    ENTER  select    ESC  back' -Width $lineWidth -Pad)); $styles.Add('footer')
    return [pscustomobject]@{ Lines=$lines.ToArray(); Styles=$styles.ToArray(); TopIndex=$top; VisibleRows=$rows; VisibleIndices=$visible.ToArray(); SelectedRow=$selectedRow; IsTooSmall=$false }
}

function ConvertTo-LlcMenuAnsiFrame {
    param([Parameter(Mandatory=$true)][object]$Frame)
    $esc = ([char]27).ToString()
    $builder = New-Object Text.StringBuilder
    [void]$builder.Append($esc + '[0m' + $esc + '[H' + $esc + '[2J')
    for ($i = 0; $i -lt $Frame.Lines.Count; $i++) {
        $colors = switch ($Frame.Styles[$i]) {
            'brand' { '1;38;2;91;225;239;48;2;10;20;37' }
            'title' { '1;38;2;241;246;255;48;2;10;20;37' }
            'selected' { '1;38;2;132;237;249;48;2;27;54;78' }
            'group' { '1;38;2;177;157;247;48;2;10;20;37' }
            'border' { '38;2;57;83;119;48;2;10;20;37' }
            'detail' { '38;2;160;184;210;48;2;10;20;37' }
            default { '38;2;190;205;225;48;2;10;20;37' }
        }
        [void]$builder.Append($esc + '[' + $colors + 'm' + $Frame.Lines[$i] + $esc + '[0m')
        if ($i -lt ($Frame.Lines.Count - 1)) { [void]$builder.Append("`r`n") }
    }
    return $builder.ToString()
}

function Enable-LlcMenuVirtualTerminal {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { return [pscustomobject]@{ Enabled=$true; Changed=$false } }
    try {
        if (-not ('LlcMenuConsoleMode' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class LlcMenuConsoleMode {
    [DllImport("kernel32.dll")] public static extern IntPtr GetStdHandle(int n);
    [DllImport("kernel32.dll")] public static extern bool GetConsoleMode(IntPtr h, out uint mode);
    [DllImport("kernel32.dll")] public static extern bool SetConsoleMode(IntPtr h, uint mode);
}
'@
        }
        $handle = [LlcMenuConsoleMode]::GetStdHandle(-11)
        [uint32]$mode = 0
        if (-not [LlcMenuConsoleMode]::GetConsoleMode($handle, [ref]$mode)) { return [pscustomobject]@{ Enabled=$false; Changed=$false } }
        if (($mode -band 4) -eq 4) { return [pscustomobject]@{ Enabled=$true; Changed=$false } }
        $enabled = [LlcMenuConsoleMode]::SetConsoleMode($handle, ($mode -bor 4))
        return [pscustomobject]@{ Enabled=$enabled; Changed=$enabled; Handle=$handle; OriginalMode=$mode }
    } catch { return [pscustomobject]@{ Enabled=$false; Changed=$false } }
}

function Get-LlcMenuConsoleSize {
    $width = 80; $height = 25
    try { $width = [Math]::Min([Console]::WindowWidth, [Console]::BufferWidth); $height = [Console]::WindowHeight } catch { }
    return [pscustomobject]@{ Width=$width; Height=$height }
}

function Write-LlcMenuFrame {
    param([object]$Frame, [bool]$UseAnsi)
    if ($UseAnsi) { [Console]::Write((ConvertTo-LlcMenuAnsiFrame -Frame $Frame)); return }
    # Classic console fallback: bounded native writes, no PowerShell host writes or newline.
    [Console]::Clear()
    $origin = [Console]::WindowTop
    for ($i = 0; $i -lt $Frame.Lines.Count; $i++) {
        [Console]::SetCursorPosition(0, ($origin + $i))
        [Console]::BackgroundColor = [ConsoleColor]::Black
        [Console]::ForegroundColor = switch ($Frame.Styles[$i]) {
            'selected' { [Console]::BackgroundColor = [ConsoleColor]::DarkBlue; [ConsoleColor]::Cyan }
            'brand' { [ConsoleColor]::Cyan }
            'title' { [ConsoleColor]::White }
            'group' { [ConsoleColor]::Magenta }
            default { [ConsoleColor]::Gray }
        }
        [Console]::Write($Frame.Lines[$i])
    }
    [Console]::ResetColor()
}

function Reset-LlcMenuInput {
    try { while ([Console]::KeyAvailable) { [void][Console]::ReadKey($true) } } catch { }
}

function Invoke-Menu {
    param([Parameter(Mandatory=$true)][string]$Title, [AllowEmptyCollection()][object[]]$Items)
    $index = Get-LlcMenuNextIndex -Items $Items -Key Home
    if ($index -lt 0) { return -1 }
    if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) {
        throw 'An interactive terminal is required for the menu. Use /check or /demo /snapshot for noninteractive output.'
    }
    $oldForeground = [Console]::ForegroundColor
    $oldBackground = [Console]::BackgroundColor
    $oldEncoding = [Console]::OutputEncoding
    $oldVisible = $true
    try { $oldVisible = [Console]::CursorVisible } catch { }
    $terminalState = Enable-LlcMenuVirtualTerminal
    $useAnsi = [bool]$terminalState.Enabled
    try {
        try { [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false) } catch { }
        if ($useAnsi) { [Console]::Write(([char]27).ToString() + '[?25l') }
        else { try { [Console]::CursorVisible = $false } catch { } }
        Reset-LlcMenuInput
        $top = 0
        $lastSignature = ''
        $dirty = $true
        while ($true) {
            $size = Get-LlcMenuConsoleSize
            $signature = '{0}x{1}' -f $size.Width, $size.Height
            if ($dirty -or $signature -ne $lastSignature) {
                $frame = Get-LlcMenuFrame -Title $Title -Items $Items -SelectedIndex $index -TopIndex $top -Width $size.Width -Height $size.Height
                Write-LlcMenuFrame -Frame $frame -UseAnsi $useAnsi
                $top = $frame.TopIndex
                $lastSignature = $signature
                $dirty = $false
            }
            if (-not [Console]::KeyAvailable) { Start-Sleep -Milliseconds 20; continue }
            $key = [Console]::ReadKey($true).Key.ToString()
            if ($key -eq 'Escape') { Reset-LlcMenuInput; return -1 }
            if ($frame.IsTooSmall) { continue }
            if ($key -eq 'Enter') { Reset-LlcMenuInput; return (Get-LlcMenuValue -Items $Items -Index $index) }
            $next = Get-LlcMenuNextIndex -Items $Items -CurrentIndex $index -Key $key -PageSize $frame.VisibleRows
            if ($next -ne $index) { $index = $next; $dirty = $true }
        }
    }
    finally {
        if ($useAnsi) {
            $cursorMode = if ($oldVisible) { '[?25h' } else { '[?25l' }
            [Console]::Write(([char]27).ToString() + '[0m' + ([char]27).ToString() + $cursorMode + ([char]27).ToString() + '[H' + ([char]27).ToString() + '[2J')
        }
        else { try { [Console]::Clear(); [Console]::CursorVisible = $oldVisible } catch { } }
        if ($terminalState.Changed) {
            try { [void][LlcMenuConsoleMode]::SetConsoleMode($terminalState.Handle, $terminalState.OriginalMode) } catch { }
        }
        try { [Console]::ForegroundColor = $oldForeground; [Console]::BackgroundColor = $oldBackground; [Console]::OutputEncoding = $oldEncoding } catch { }
    }
}

function Get-LlcMainMenuItems {
    param([string]$GpuText='GPU', [string]$DriverText='Drivers', [string]$MmcssText='MMCSS')
    @(
        [pscustomobject]@{ Text='Preflight / About v2'; Value='preflight'; Selectable=$true; Description='Host and resource checks. No system tweaks are applied.' },
        [pscustomobject]@{ Text='System and registry'; Selectable=$false },
        [pscustomobject]@{ Text='Auto Registry Tweaks'; Value='autoRegistryTweaks'; Selectable=$true; Description='Broad system changes. Review the list and type AUTO to confirm.' },
        [pscustomobject]@{ Text='UAC'; Value='uac'; Selectable=$true; Description='Enable or disable User Account Control.' },
        [pscustomobject]@{ Text='QOL'; Value='qol'; Selectable=$true; Description='Explorer, profiles, OneDrive and taskbar. Type QOL to confirm.' },
        [pscustomobject]@{ Text='Fullscreen Optimization'; Value='fullscreenOptimization'; Selectable=$true },
        [pscustomobject]@{ Text='Gamebar and Game Mode'; Value='gamebarAndGameMode'; Selectable=$true },
        [pscustomobject]@{ Text='Services'; Value='services'; Selectable=$true; Description='Service startup presets. Restore defaults is not a full backup.' },
        [pscustomobject]@{ Text='Powersaving'; Value='powersaving'; Selectable=$true },
        [pscustomobject]@{ Text='Network Optimization'; Value='networkOptimization'; Selectable=$true; Description='Wired Ethernet settings. Review the documented parameters first.' },
        [pscustomobject]@{ Text=$MmcssText; Value='mmcss'; Selectable=$true },
        [pscustomobject]@{ Text='Win32PrioritySeparation'; Value='win32PrioritySeparation'; Selectable=$true },
        [pscustomobject]@{ Text='Clock Interrupts'; Value='clockInterrupts'; Selectable=$true },
        [pscustomobject]@{ Text='Hardware-Accelerated GPU Scheduling'; Value='hags'; Selectable=$true },
        [pscustomobject]@{ Text=$GpuText; Value='gpu'; Selectable=$true },
        [pscustomobject]@{ Text='Drivers and apps'; Selectable=$false },
        [pscustomobject]@{ Text=$DriverText; Value='drivers'; Selectable=$true },
        [pscustomobject]@{ Text='Apps'; Value='apps'; Selectable=$true },
        [pscustomobject]@{ Text='Other'; Selectable=$false },
        [pscustomobject]@{ Text='Autostart'; Value='autostart'; Selectable=$true },
        [pscustomobject]@{ Text='Power Plan'; Value='powerPlan'; Selectable=$true },
        [pscustomobject]@{ Text='Activate Windows'; Value='activateWindows'; Selectable=$true },
        [pscustomobject]@{ Text='Exit'; Value='exit'; Selectable=$true; Description='Close the menu without starting another action.' }
    )
}

# A UI-only entry point must exit before host checks, transcript and system initialization.
if ($env:LLC_MENU_DEMO -eq '1') {
    $demoItems = @(Get-LlcMainMenuItems -GpuText 'GPU - demo adapter' -DriverText 'Drivers - demo adapter' -MmcssText 'MMCSS - demo stack')
    if ($env:LLC_MENU_SNAPSHOT -eq '1') {
        $demoFrame = Get-LlcMenuFrame -Title 'UI PREVIEW - no system changes' -Items $demoItems -SelectedIndex 0 -Width 80 -Height 30
        [Console]::WriteLine(($demoFrame.Lines -join [Environment]::NewLine))
    } else {
        $demoChoice = Invoke-Menu -Title 'UI PREVIEW - no system changes' -Items $demoItems
        [Console]::WriteLine('UI preview closed. No settings were applied.')
    }
    exit 0
}


$llcPreflight = Get-LlcPreflightResult
if ($env:LLC_RUN_CHECK -eq '1') {
    $checkTokens = $null
    $checkErrors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($PSCommandPath, [ref]$checkTokens, [ref]$checkErrors)
    if ($checkErrors.Count -gt 0) {
        $checkErrors | ForEach-Object { Write-Host $_.Message -ForegroundColor Red }
        exit 1
    }
    Write-Host 'PASS: PowerShell payload syntax.' -ForegroundColor Green
    Write-LlcPreflightReport -Result $llcPreflight
    if (-not $llcPreflight.Ready) { exit 2 }
    exit 0
}
if (-not $llcPreflight.Ready) {
    Write-LlcPreflightReport -Result $llcPreflight
    exit 2
}


$ErrorActionPreference = 'Stop'
$script:LowLatencyDebugLog = $env:LLC_MENU_DEBUG_LOG
if ([string]::IsNullOrWhiteSpace($script:LowLatencyDebugLog)) {
    $script:LowLatencyDebugLog = Join-Path ([IO.Path]::GetTempPath()) ("LowLatencyCorpMenu_Debug_{0:yyyyMMdd_HHmmss}_{1}.log" -f (Get-Date), $PID)
}
try {
    Start-Transcript -LiteralPath $script:LowLatencyDebugLog -Append -Force | Out-Null
}
catch {
    Write-Host ("WARNING: could not start debug transcript: {0}" -f $_.Exception.Message) -ForegroundColor Yellow
}

trap {
    $err = $_
    Write-Host ''
    Write-Host 'FATAL ERROR - the script stopped unexpectedly.' -ForegroundColor Red
    Write-Host ("Debug log: {0}" -f $script:LowLatencyDebugLog) -ForegroundColor Yellow
    Write-Host ''
    Write-Host 'Detailed error record:' -ForegroundColor Yellow
    try { $err | Format-List * -Force } catch { Write-Host $err }
    if ($err.InvocationInfo) {
        Write-Host ''
        Write-Host 'Invocation info:' -ForegroundColor Yellow
        try { $err.InvocationInfo | Format-List * -Force } catch { }
    }
    if ($err.ScriptStackTrace) {
        Write-Host ''
        Write-Host 'Script stack trace:' -ForegroundColor Yellow
        Write-Host $err.ScriptStackTrace
    }
    Write-Host ''
    try { Stop-Transcript | Out-Null } catch { }
    try {
        if (Get-Command Wait-ForEnterToContinue -ErrorAction SilentlyContinue) {
            Wait-ForEnterToContinue -Prompt 'Press Enter to exit'
        } else {
            Read-Host 'Press Enter to exit' | Out-Null
        }
    } catch { }
    exit 1
}


function Clear-ConsoleScreen {
    try { [Console]::ResetColor() } catch { }
    try {
        [Console]::Clear()
    } catch {
        Microsoft.PowerShell.Utility\Clear-Host
    }
    try { [Console]::ResetColor() } catch { }
}

function Clear-ConsoleInputBuffer {
    param([int]$DelayMilliseconds = 0)

    if ($DelayMilliseconds -gt 0) {
        Start-Sleep -Milliseconds $DelayMilliseconds
    }

    try {
        while ([Console]::KeyAvailable) {
            [void][Console]::ReadKey($true)
        }
    } catch { }
}

function Ensure-ConsoleBufferHeight {
    param([int]$RequiredHeight)

    if ($RequiredHeight -lt 1) { return }

    try {
        $targetHeight = [Math]::Max($RequiredHeight, [Console]::WindowHeight)
        if ([Console]::BufferHeight -lt $targetHeight) {
            [Console]::BufferHeight = $targetHeight
        }
    } catch { }
}

function Set-ConsoleCursorPositionSafe {
    param(
        [int]$Left,
        [int]$Top
    )

    try {
        if ($Left -lt 0) { $Left = 0 }
        if ($Top -lt 0) { $Top = 0 }

        Ensure-ConsoleBufferHeight -RequiredHeight ($Top + 1)

        $bufferWidth = [Console]::BufferWidth
        $bufferHeight = [Console]::BufferHeight
        if (($bufferWidth -lt 1) -or ($bufferHeight -lt 1)) { return $false }

        if ($Left -ge $bufferWidth) { $Left = $bufferWidth - 1 }
        if ($Top -ge $bufferHeight) { $Top = $bufferHeight - 1 }

        [Console]::SetCursorPosition($Left, $Top)
        return $true
    } catch {
        return $false
    }
}

function Wait-ForEnterToContinue {
    param([string]$Prompt = 'Press Enter to continue')

    try {
        Write-Host -NoNewline $Prompt -ForegroundColor White
        while ($true) {
            $key = [Console]::ReadKey($true)
            if ($key.Key -eq 'Enter') {
                Write-Host ''
                Clear-ConsoleInputBuffer -DelayMilliseconds 75
                return
            }
        }
    } catch {
        Write-Host -NoNewline $Prompt -ForegroundColor White
        Read-Host | Out-Null
        Clear-ConsoleInputBuffer -DelayMilliseconds 75
    }
}


function Test-ConsoleNavigationInputAccepted {
    param(
        [Parameter(Mandatory=$true)][System.ConsoleKey]$Key,
        [Parameter(Mandatory=$true)][Diagnostics.Stopwatch]$Stopwatch,
        [Parameter(Mandatory=$true)][ref]$LastMoveMilliseconds,
        [int]$MinimumIntervalMilliseconds = 24
    )

    if (($Key -ne [System.ConsoleKey]::UpArrow) -and ($Key -ne [System.ConsoleKey]::DownArrow)) {
        return $true
    }

    $nowMilliseconds = [int64]$Stopwatch.ElapsedMilliseconds
    $lastMilliseconds = [int64]$LastMoveMilliseconds.Value

    if (($lastMilliseconds -ge 0) -and (($nowMilliseconds - $lastMilliseconds) -lt $MinimumIntervalMilliseconds)) {
        return $false
    }

    $LastMoveMilliseconds.Value = $nowMilliseconds
    return $true
}

function Write-StatusLine {
    param(
        [Parameter(Mandatory=$true)][bool]$Ok,
        [Parameter(Mandatory=$true)][string]$Text,
        [switch]$Warning
    )

    if ($Warning) {
        Write-Host ("WARNING: " + $Text) -ForegroundColor Yellow
    } elseif ($Ok) {
        Write-Host ("SUCCESS: " + $Text) -ForegroundColor Green
    } else {
        Write-Host ("FAILED : " + $Text) -ForegroundColor Red
    }
}

function Write-BoxTitle {
    param(
        [Parameter(Mandatory=$true)][string]$Title,
        [int]$MinimumInnerWidth = 30
    )

    $displayTitle = $Title.Trim()
    try {
        $consoleWidth = [Math]::Max(20, [Console]::BufferWidth - 1)
    } catch {
        $consoleWidth = 120
    }

    $padding = 1
    $maxInnerWidth = [Math]::Max(10, $consoleWidth - 2)
    $innerWidth = [Math]::Max($MinimumInnerWidth, $displayTitle.Length + ($padding * 2))
    if ($innerWidth -gt $maxInnerWidth) {
        $innerWidth = $maxInnerWidth
    }

    $maxTitleWidth = [Math]::Max(1, $innerWidth - ($padding * 2))
    if ($displayTitle.Length -gt $maxTitleWidth) {
        if ($maxTitleWidth -gt 3) {
            $displayTitle = $displayTitle.Substring(0, $maxTitleWidth - 3) + '...'
        } else {
            $displayTitle = $displayTitle.Substring(0, $maxTitleWidth)
        }
    }

    $rightPad = $innerWidth - $displayTitle.Length - $padding
    Write-Host ('+' + ('=' * $innerWidth) + '+') -ForegroundColor White
    Write-Host ('|' + (' ' * $padding) + $displayTitle + (' ' * $rightPad) + '|') -ForegroundColor White
    Write-Host ('+' + ('=' * $innerWidth) + '+') -ForegroundColor White
}


function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}


if (-not ([System.Management.Automation.PSTypeName]'TI.TokenPriv').Type) {
    Add-Type -Namespace TI -Name TokenPriv -MemberDefinition @'
[DllImport("advapi32.dll", ExactSpelling=true, SetLastError=true)]
public static extern bool AdjustTokenPrivileges(
    IntPtr htok, bool disAll, ref TokPriv1Luid newState, int len, IntPtr prev, IntPtr relen);
[DllImport("advapi32.dll", ExactSpelling=true, SetLastError=true)]
public static extern bool OpenProcessToken(IntPtr h, int acc, ref IntPtr phtok);
[DllImport("advapi32.dll", SetLastError=true)]
public static extern bool LookupPrivilegeValue(string host, string name, ref long pluid);
[StructLayout(LayoutKind.Sequential, Pack=1)]
public struct TokPriv1Luid { public int Count; public long Luid; public int Attr; }
public const int SE_PRIVILEGE_ENABLED = 0x00000002;
public const int TOKEN_QUERY          = 0x00000008;
public const int TOKEN_ADJUST_PRIVS   = 0x00000020;
public static bool Enable(long processHandle, string privilege) {
    TokPriv1Luid tp; IntPtr htok = IntPtr.Zero;
    bool ok = OpenProcessToken(new IntPtr(processHandle), TOKEN_ADJUST_PRIVS | TOKEN_QUERY, ref htok);
    tp.Count = 1; tp.Luid = 0; tp.Attr = SE_PRIVILEGE_ENABLED;
    LookupPrivilegeValue(null, privilege, ref tp.Luid);
    AdjustTokenPrivileges(htok, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
    return ok;
}
'@
}

if (-not ([System.Management.Automation.PSTypeName]'TI.Helper').Type) {
    Add-Type -Namespace TI -Name Helper -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError=true)]
public static extern IntPtr OpenProcess(uint processAccess, bool bInheritHandle, int processId);

[DllImport("kernel32.dll", SetLastError=true)]
[return: MarshalAs(UnmanagedType.Bool)]
public static extern bool CloseHandle(IntPtr hObject);

[DllImport("advapi32.dll", SetLastError=true)]
[return: MarshalAs(UnmanagedType.Bool)]
public static extern bool OpenProcessToken(IntPtr ProcessHandle, uint DesiredAccess, out IntPtr TokenHandle);

[DllImport("advapi32.dll", SetLastError=true)]
[return: MarshalAs(UnmanagedType.Bool)]
public static extern bool DuplicateTokenEx(
    IntPtr hExistingToken, uint dwDesiredAccess, IntPtr lpTokenAttributes,
    int ImpersonationLevel, int TokenType, out IntPtr phNewToken);

[DllImport("advapi32.dll", SetLastError=true)]
[return: MarshalAs(UnmanagedType.Bool)]
public static extern bool ImpersonateLoggedOnUser(IntPtr hToken);

[DllImport("advapi32.dll", SetLastError=true)]
[return: MarshalAs(UnmanagedType.Bool)]
public static extern bool RevertToSelf();

[DllImport("kernel32.dll")]
public static extern IntPtr GetCurrentThread();

[DllImport("advapi32.dll", SetLastError=true)]
[return: MarshalAs(UnmanagedType.Bool)]
public static extern bool OpenThreadToken(IntPtr hThread, uint desiredAccess, bool openAsSelf, out IntPtr hToken);

[DllImport("advapi32.dll", SetLastError=true)]
[return: MarshalAs(UnmanagedType.Bool)]
public static extern bool AdjustTokenPrivileges(
    IntPtr hToken, bool disableAllPrivileges,
    ref LUID_AND_ATTRIBUTES newState, int bufLen, IntPtr prevState, IntPtr returnLen);

[DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
[return: MarshalAs(UnmanagedType.Bool)]
public static extern bool LookupPrivilegeValue(string lpSystemName, string lpName, out long lpLuid);

[StructLayout(LayoutKind.Sequential)]
public struct LUID_AND_ATTRIBUTES { public long Luid; public int Attributes; }

public const uint PROCESS_QUERY_INFORMATION         = 0x0400;
public const uint PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;
public const uint TOKEN_ALL_ACCESS                  = 0x000F01FF;
public const uint TOKEN_DUPLICATE                   = 0x0002;
public const uint TOKEN_QUERY                       = 0x0008;
public const uint TOKEN_IMPERSONATE                 = 0x0004;
public const uint TOKEN_ADJUST_PRIVILEGES           = 0x0020;
public const int  SecurityImpersonation             = 2;
public const int  TokenImpersonation                = 2;
public const int  SE_PRIVILEGE_ENABLED              = 0x00000002;

public static bool EnablePrivilegeOnToken(IntPtr hToken, string privilege) {
    LUID_AND_ATTRIBUTES la = new LUID_AND_ATTRIBUTES();
    la.Attributes = SE_PRIVILEGE_ENABLED;
    if (!LookupPrivilegeValue(null, privilege, out la.Luid)) return false;
    return AdjustTokenPrivileges(hToken, false, ref la, 0, IntPtr.Zero, IntPtr.Zero);
}

public static void EnableRegistryPrivsOnCurrentThread() {
    IntPtr hTok = IntPtr.Zero;
    if (OpenThreadToken(GetCurrentThread(), TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, false, out hTok) && hTok != IntPtr.Zero) {
        EnablePrivilegeOnToken(hTok, "SeBackupPrivilege");
        EnablePrivilegeOnToken(hTok, "SeRestorePrivilege");
        EnablePrivilegeOnToken(hTok, "SeTakeOwnershipPrivilege");
        CloseHandle(hTok);
    }
}
'@
}

function Enable-TITokenPrivilege {
    param([string]$Privilege)
    try {
        $handle = (Get-Process -Id $PID).Handle
        [TI.TokenPriv]::Enable($handle, $Privilege) | Out-Null
    } catch { }
}

function Enable-TIRegistryPrivileges {
    Enable-TITokenPrivilege "SeTakeOwnershipPrivilege"
    Enable-TITokenPrivilege "SeRestorePrivilege"
    Enable-TITokenPrivilege "SeBackupPrivilege"
    try { [TI.Helper]::EnableRegistryPrivsOnCurrentThread() } catch {}
}


if (-not ([System.Management.Automation.PSTypeName]'TI.RegistryNative').Type) {
    Add-Type -Namespace TI -Name RegistryNative -MemberDefinition @'
[DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
public static extern int RegCreateKeyEx(
    IntPtr hKey, string lpSubKey, int Reserved, string lpClass, int dwOptions,
    int samDesired, IntPtr lpSecurityAttributes, out IntPtr phkResult, out int lpdwDisposition);

[DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
public static extern int RegOpenKeyEx(
    IntPtr hKey, string lpSubKey, int ulOptions, int samDesired, out IntPtr phkResult);

[DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode, EntryPoint="RegSetValueEx")]
public static extern int RegSetValueExDword(
    IntPtr hKey, string lpValueName, int Reserved, int dwType, ref UInt32 lpData, int cbData);

[DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode, EntryPoint="RegSetValueEx")]
public static extern int RegSetValueExString(
    IntPtr hKey, string lpValueName, int Reserved, int dwType, string lpData, int cbData);

[DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode, EntryPoint="RegSetValueEx")]
public static extern int RegSetValueExBinary(
    IntPtr hKey, string lpValueName, int Reserved, int dwType, byte[] lpData, int cbData);

[DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
public static extern int RegDeleteValue(IntPtr hKey, string lpValueName);

[DllImport("advapi32.dll", SetLastError=true)]
public static extern int RegCloseKey(IntPtr hKey);

public static readonly IntPtr HKEY_CLASSES_ROOT   = new IntPtr(unchecked((int)0x80000000));
public static readonly IntPtr HKEY_CURRENT_USER   = new IntPtr(unchecked((int)0x80000001));
public static readonly IntPtr HKEY_LOCAL_MACHINE  = new IntPtr(unchecked((int)0x80000002));
public static readonly IntPtr HKEY_USERS          = new IntPtr(unchecked((int)0x80000003));

public const int KEY_QUERY_VALUE          = 0x0001;
public const int KEY_SET_VALUE            = 0x0002;
public const int KEY_CREATE_SUB_KEY       = 0x0004;
public const int KEY_ENUMERATE_SUB_KEYS   = 0x0008;
public const int KEY_NOTIFY               = 0x0010;
public const int READ_CONTROL             = 0x00020000;
public const int KEY_WOW64_64KEY          = 0x0100;
public const int KEY_READ                 = READ_CONTROL | KEY_QUERY_VALUE | KEY_ENUMERATE_SUB_KEYS | KEY_NOTIFY;
public const int KEY_WRITE                = READ_CONTROL | KEY_SET_VALUE | KEY_CREATE_SUB_KEY;
public const int REG_OPTION_NON_VOLATILE  = 0x00000000;
public const int REG_OPTION_BACKUP_RESTORE= 0x00000004;
public const int REG_SZ                   = 1;
public const int REG_BINARY               = 3;
public const int REG_DWORD                = 4;
public const int ERROR_FILE_NOT_FOUND     = 2;
'@
}

$script:TI_Initialized = $false
$script:TI_UsePrivOnly  = $false

function script:Clear-TILastPInvokeError {
    try   { [System.Runtime.InteropServices.Marshal]::SetLastPInvokeError(0) } catch {
        try { [System.Runtime.InteropServices.Marshal]::SetLastWin32Error(0) } catch {}
    }
}

function Initialize-TrustedInstallerToken {
    Enable-TITokenPrivilege "SeDebugPrivilege"

    $tiSvc = Get-Service "TrustedInstaller" -ErrorAction SilentlyContinue
    if ($tiSvc) {
        if ($tiSvc.Status -ne 'Running') {
            try   { Start-Service "TrustedInstaller" -ErrorAction Stop }
            catch { & sc.exe start TrustedInstaller 2>&1 | Out-Null }
            $dl = (Get-Date).AddSeconds(10)
            while ((Get-Service "TrustedInstaller" -EA SilentlyContinue).Status -ne 'Running' `
                   -and (Get-Date) -lt $dl) { Start-Sleep -Milliseconds 200 }
        }
        $script:TI_Initialized = $true
        $script:TI_UsePrivOnly  = $false
    } else {
        $script:TI_UsePrivOnly  = $true
    }
}

function Cleanup-TrustedInstallerToken {
    try { [TI.Helper]::RevertToSelf() | Out-Null } catch {}
    $script:TI_Initialized = $false
    $script:TI_UsePrivOnly  = $false
}

function Invoke-AsTrustedInstaller {
    param([scriptblock]$Action)

    Enable-TITokenPrivilege "SeDebugPrivilege"
    try {
        $curProc = [System.Diagnostics.Process]::GetCurrentProcess()
        [TI.TokenPriv]::Enable($curProc.Handle.ToInt64(), "SeDebugPrivilege") | Out-Null
    } catch {}

    $maxAttempts = 5
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {

        $tiSvc = Get-Service "TrustedInstaller" -ErrorAction SilentlyContinue
        if (-not $tiSvc) { break }
        if ($tiSvc.Status -ne 'Running') {
            try {
                Start-Service "TrustedInstaller" -ErrorAction Stop
                $dl = (Get-Date).AddSeconds(8)
                while ((Get-Service "TrustedInstaller").Status -ne 'Running' -and (Get-Date) -lt $dl) {
                    Start-Sleep -Milliseconds 100
                }
            } catch {
                Start-Sleep -Milliseconds 500
                continue
            }
        }

        $tiProc = $null
        $procDl = (Get-Date).AddSeconds(3)
        while ((Get-Date) -lt $procDl) {
            $tiProc = Get-Process -Name "TrustedInstaller" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($tiProc) { break }
            Start-Sleep -Milliseconds 100
        }
        if (-not $tiProc) {
            try {
                Stop-Service "TrustedInstaller" -Force -ErrorAction SilentlyContinue
                Start-Sleep -Milliseconds 300
                Start-Service "TrustedInstaller" -ErrorAction Stop
                $procDl2 = (Get-Date).AddSeconds(3)
                while ((Get-Date) -lt $procDl2) {
                    $tiProc = Get-Process -Name "TrustedInstaller" -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($tiProc) { break }
                    Start-Sleep -Milliseconds 100
                }
            } catch {}
            if (-not $tiProc) { Start-Sleep -Milliseconds 500; continue }
        }

        $winlogonProc = Get-Process -Name "winlogon" -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $winlogonProc) {
            Start-Sleep -Milliseconds 500
            continue
        }

        script:Clear-TILastPInvokeError
        $hWinlogon = [TI.Helper]::OpenProcess([TI.Helper]::PROCESS_QUERY_INFORMATION, $false, $winlogonProc.Id)
        if ($hWinlogon -eq [IntPtr]::Zero) {
            $hWinlogon = [TI.Helper]::OpenProcess([TI.Helper]::PROCESS_QUERY_LIMITED_INFORMATION, $false, $winlogonProc.Id)
        }
        if ($hWinlogon -eq [IntPtr]::Zero) {
            Start-Sleep -Milliseconds 500
            continue
        }

        $attemptSucceeded = $false
        try {
            $hSysToken = [IntPtr]::Zero
            $sysAccess = [TI.Helper]::TOKEN_DUPLICATE -bor [TI.Helper]::TOKEN_QUERY -bor [TI.Helper]::TOKEN_IMPERSONATE
            script:Clear-TILastPInvokeError
            if (-not [TI.Helper]::OpenProcessToken($hWinlogon, $sysAccess, [ref]$hSysToken)) {
                script:Clear-TILastPInvokeError
                [TI.Helper]::OpenProcessToken($hWinlogon, [TI.Helper]::TOKEN_ALL_ACCESS, [ref]$hSysToken) | Out-Null
            }
            if ($hSysToken -eq [IntPtr]::Zero) {
                Start-Sleep -Milliseconds 500
                continue
            }

            try {
                $hSysImpToken = [IntPtr]::Zero
                script:Clear-TILastPInvokeError
                [TI.Helper]::DuplicateTokenEx(
                    $hSysToken,
                    [TI.Helper]::TOKEN_ALL_ACCESS,
                    [IntPtr]::Zero,
                    [TI.Helper]::SecurityImpersonation,
                    [TI.Helper]::TokenImpersonation,
                    [ref]$hSysImpToken) | Out-Null
                if ($hSysImpToken -eq [IntPtr]::Zero) { continue }

                try {
                    if (-not [TI.Helper]::ImpersonateLoggedOnUser($hSysImpToken)) { continue }

                    $hTIProc = [TI.Helper]::OpenProcess([TI.Helper]::PROCESS_QUERY_INFORMATION, $false, $tiProc.Id)
                    if ($hTIProc -eq [IntPtr]::Zero) {
                        $hTIProc = [TI.Helper]::OpenProcess([TI.Helper]::PROCESS_QUERY_LIMITED_INFORMATION, $false, $tiProc.Id)
                    }
                    if ($hTIProc -eq [IntPtr]::Zero) {
                        [TI.Helper]::RevertToSelf() | Out-Null
                        continue
                    }

                    try {
                        $hTIToken = [IntPtr]::Zero
                        $tiAccess = [TI.Helper]::TOKEN_ALL_ACCESS
                        script:Clear-TILastPInvokeError
                        if (-not [TI.Helper]::OpenProcessToken($hTIProc, $tiAccess, [ref]$hTIToken)) {
                            $tiAccess = [TI.Helper]::TOKEN_DUPLICATE -bor [TI.Helper]::TOKEN_QUERY -bor [TI.Helper]::TOKEN_IMPERSONATE
                            script:Clear-TILastPInvokeError
                            [TI.Helper]::OpenProcessToken($hTIProc, $tiAccess, [ref]$hTIToken) | Out-Null
                        }
                        if ($hTIToken -eq [IntPtr]::Zero) {
                            [TI.Helper]::RevertToSelf() | Out-Null
                            continue
                        }

                        try {
                            $hImpToken = [IntPtr]::Zero
                            script:Clear-TILastPInvokeError
                            [TI.Helper]::DuplicateTokenEx(
                                $hTIToken,
                                [TI.Helper]::TOKEN_ALL_ACCESS,
                                [IntPtr]::Zero,
                                [TI.Helper]::SecurityImpersonation,
                                [TI.Helper]::TokenImpersonation,
                                [ref]$hImpToken) | Out-Null
                            if ($hImpToken -eq [IntPtr]::Zero) {
                                [TI.Helper]::RevertToSelf() | Out-Null
                                continue
                            }

                            try {
                                [TI.Helper]::RevertToSelf() | Out-Null
                                if (-not [TI.Helper]::ImpersonateLoggedOnUser($hImpToken)) { continue }
                                try {
                                    Enable-TIRegistryPrivileges
                                    & $Action
                                    $attemptSucceeded = $true
                                    return $true
                                } catch {
                                    return $false
                                } finally {
                                    [TI.Helper]::RevertToSelf() | Out-Null
                                }
                            } finally {
                                [TI.Helper]::CloseHandle($hImpToken) | Out-Null
                            }
                        } finally {
                            [TI.Helper]::CloseHandle($hTIToken) | Out-Null
                        }
                    } finally {
                        [TI.Helper]::CloseHandle($hTIProc) | Out-Null
                        if (-not $attemptSucceeded) { [TI.Helper]::RevertToSelf() | Out-Null }
                    }
                } finally {
                    [TI.Helper]::CloseHandle($hSysImpToken) | Out-Null
                }
            } finally {
                [TI.Helper]::CloseHandle($hSysToken) | Out-Null
            }
        } finally {
            [TI.Helper]::CloseHandle($hWinlogon) | Out-Null
        }
    }

    $script:TI_UsePrivOnly = $true
    try {
        Enable-TIRegistryPrivileges
        & $Action
        return $true
    } catch {
        return $false
    }
}


function Invoke-AsLocalSystem {
    param([scriptblock]$Action)

    Enable-TITokenPrivilege "SeDebugPrivilege"
    try {
        $curProc = [System.Diagnostics.Process]::GetCurrentProcess()
        [TI.TokenPriv]::Enable($curProc.Handle.ToInt64(), "SeDebugPrivilege") | Out-Null
    } catch {}

    $maxAttempts = 5
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        $winlogonProc = Get-Process -Name "winlogon" -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $winlogonProc) {
            Start-Sleep -Milliseconds 500
            continue
        }

        script:Clear-TILastPInvokeError
        $hWinlogon = [TI.Helper]::OpenProcess([TI.Helper]::PROCESS_QUERY_INFORMATION, $false, $winlogonProc.Id)
        if ($hWinlogon -eq [IntPtr]::Zero) {
            $hWinlogon = [TI.Helper]::OpenProcess([TI.Helper]::PROCESS_QUERY_LIMITED_INFORMATION, $false, $winlogonProc.Id)
        }
        if ($hWinlogon -eq [IntPtr]::Zero) {
            Start-Sleep -Milliseconds 500
            continue
        }

        try {
            $hSysToken = [IntPtr]::Zero
            $sysAccess = [TI.Helper]::TOKEN_DUPLICATE -bor [TI.Helper]::TOKEN_QUERY -bor [TI.Helper]::TOKEN_IMPERSONATE
            script:Clear-TILastPInvokeError
            if (-not [TI.Helper]::OpenProcessToken($hWinlogon, $sysAccess, [ref]$hSysToken)) {
                script:Clear-TILastPInvokeError
                [TI.Helper]::OpenProcessToken($hWinlogon, [TI.Helper]::TOKEN_ALL_ACCESS, [ref]$hSysToken) | Out-Null
            }
            if ($hSysToken -eq [IntPtr]::Zero) {
                Start-Sleep -Milliseconds 500
                continue
            }

            try {
                $hSysImpToken = [IntPtr]::Zero
                script:Clear-TILastPInvokeError
                [TI.Helper]::DuplicateTokenEx(
                    $hSysToken,
                    [TI.Helper]::TOKEN_ALL_ACCESS,
                    [IntPtr]::Zero,
                    [TI.Helper]::SecurityImpersonation,
                    [TI.Helper]::TokenImpersonation,
                    [ref]$hSysImpToken) | Out-Null
                if ($hSysImpToken -eq [IntPtr]::Zero) { continue }

                try {
                    if (-not [TI.Helper]::ImpersonateLoggedOnUser($hSysImpToken)) { continue }
                    try {
                        Enable-TIRegistryPrivileges
                        & $Action
                        return $true
                    } catch {
                        return $false
                    } finally {
                        [TI.Helper]::RevertToSelf() | Out-Null
                    }
                } finally {
                    [TI.Helper]::CloseHandle($hSysImpToken) | Out-Null
                }
            } finally {
                [TI.Helper]::CloseHandle($hSysToken) | Out-Null
            }
        } finally {
            [TI.Helper]::CloseHandle($hWinlogon) | Out-Null
        }
    }

    return $false
}


function Convert-ToUInt32Value {
    param(
        [Parameter(Mandatory=$true)][object]$Value
    )

    if ($Value -is [string]) {
        $text = $Value.Trim()
        if ($text -match '^0x[0-9a-fA-F]+$') {
            return [Convert]::ToUInt32($text.Substring(2), 16)
        }
        return [Convert]::ToUInt32($text, 10)
    }

    return [Convert]::ToUInt32($Value)
}

function Convert-RegistryDwordReadToUInt32 {
    param(
        [Parameter(Mandatory=$true)][object]$Value
    )

    if ($Value -is [int]) {
        return [BitConverter]::ToUInt32([BitConverter]::GetBytes([int]$Value), 0)
    }

    if (($Value -is [long]) -and ([long]$Value -lt 0)) {
        return [BitConverter]::ToUInt32([BitConverter]::GetBytes([int]$Value), 0)
    }

    return [Convert]::ToUInt32($Value)
}

function Convert-QolNativeArgumentToCommandLineToken {
    param([AllowNull()][string]$Argument)

    if ($null -eq $Argument) { return '""' }
    $arg = [string]$Argument
    if ($arg.Length -eq 0) { return '""' }
    if ($arg -notmatch '[\s"]') { return $arg }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('"')
    $backslashes = 0
    foreach ($ch in $arg.ToCharArray()) {
        if ($ch -eq [char]92) {
            $backslashes++
            continue
        }
        if ($ch -eq [char]34) {
            if ($backslashes -gt 0) { [void]$sb.Append(('\' * ($backslashes * 2))) }
            $backslashes = 0
            [void]$sb.Append('\"')
            continue
        }
        if ($backslashes -gt 0) { [void]$sb.Append(('\' * $backslashes)) }
        $backslashes = 0
        [void]$sb.Append($ch)
    }
    if ($backslashes -gt 0) { [void]$sb.Append(('\' * ($backslashes * 2))) }
    [void]$sb.Append('"')
    return $sb.ToString()
}

function Invoke-QolNativeCommandCaptured {
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [AllowEmptyString()][AllowNull()][Parameter(Mandatory=$true)][string[]]$Arguments,
        [int]$TimeoutSeconds = 45
    )

    $process = $null
    try {
        $argumentText = (@($Arguments) | ForEach-Object { Convert-QolNativeArgumentToCommandLineToken -Argument $_ }) -join ' '

        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $FilePath
        $psi.Arguments = $argumentText
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true

        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $psi
        [void]$process.Start()

        $timeoutMilliseconds = [Math]::Max(1, $TimeoutSeconds) * 1000
        if (-not $process.WaitForExit($timeoutMilliseconds)) {
            try { $process.Kill() } catch { }
            return [pscustomobject]@{
                ExitCode = 124
                Output   = @(("native command timed out after {0}s: {1} {2}" -f $TimeoutSeconds, $FilePath, $argumentText))
            }
        }

        $stdout = ''
        $stderr = ''
        try { $stdout = $process.StandardOutput.ReadToEnd() } catch { }
        try { $stderr = $process.StandardError.ReadToEnd() } catch { }
        try { $process.WaitForExit() } catch { }

        $lines = New-Object System.Collections.Generic.List[string]
        foreach ($block in @($stdout, $stderr)) {
            if ([string]::IsNullOrEmpty($block)) { continue }
            foreach ($line in ($block -split "`r?`n")) {
                if ($line.Length -gt 0) { [void]$lines.Add($line) }
            }
        }

        return [pscustomobject]@{
            ExitCode = [int]$process.ExitCode
            Output   = @($lines.ToArray())
        }
    }
    catch {
        return [pscustomobject]@{
            ExitCode = 125
            Output   = @(("native command launch failed for {0}: {1}" -f $FilePath, $_.Exception.Message))
        }
    }
    finally {
        if ($null -ne $process) { try { $process.Dispose() } catch { } }
    }
}

function Convert-QolDwordToRegistryProviderValue {
    param([Parameter(Mandatory=$true)][object]$Value)

    $uintValue = Convert-ToUInt32Value -Value $Value
    return [BitConverter]::ToInt32([BitConverter]::GetBytes([uint32]$uintValue), 0)
}

function Set-QolRegistryValueViaProvider {
    param(
        [Parameter(Mandatory=$true)][string]$Key,
        [AllowEmptyString()][Parameter(Mandatory=$true)][string]$Name,
        [AllowEmptyString()][Parameter(Mandatory=$true)][object]$Value,
        [Parameter(Mandatory=$true)][ValidateSet('DWord','String','Binary')][string]$Type
    )

    $psPath = "Registry::$Key"
    if (-not (Test-Path -LiteralPath $psPath)) {
        throw "key not found: $Key"
    }

    switch ($Type) {
        'DWord' {
            $providerValue = Convert-QolDwordToRegistryProviderValue -Value $Value
            New-ItemProperty -LiteralPath $psPath -Name $Name -PropertyType DWord -Value $providerValue -Force -ErrorAction Stop | Out-Null
            break
        }
        'String' {
            if ([string]::IsNullOrEmpty($Name)) {
                $registryKey = Get-Item -LiteralPath $psPath -ErrorAction Stop
                $registryKey.SetValue('', [string]$Value, [Microsoft.Win32.RegistryValueKind]::String)
            } else {
                New-ItemProperty -LiteralPath $psPath -Name $Name -PropertyType String -Value ([string]$Value) -Force -ErrorAction Stop | Out-Null
            }
            break
        }
        'Binary' {
            $bytes = Convert-ToRegistryBinaryBytes -Value $Value
            New-ItemProperty -LiteralPath $psPath -Name $Name -PropertyType Binary -Value ([byte[]]$bytes) -Force -ErrorAction Stop | Out-Null
            break
        }
    }
}

function Remove-QolRegistryValueViaProvider {
    param(
        [Parameter(Mandatory=$true)][string]$Key,
        [Parameter(Mandatory=$true)][string]$Name
    )

    $psPath = "Registry::$Key"
    if (-not (Test-Path -LiteralPath $psPath)) { return }
    Remove-ItemProperty -LiteralPath $psPath -Name $Name -ErrorAction Stop
}

function Test-QolTemporaryLoadedHiveRegistryKey {
    param([Parameter(Mandatory=$true)][string]$Key)

    $normalized = (($Key -replace '/', '\\').Trim('\'))
    return ($normalized -match '(?i)^HKEY_USERS\\(LLC_QOL__|\.DEFAULT(?:\\|$)|S-1-5-21-[^\\]+(?:\\|$))')
}

function Split-QolRegistryKeyForDotNet {
    param([Parameter(Mandatory=$true)][string]$Key)

    $normalized = (($Key -replace '/', '\').Trim('\'))
    $parts = $normalized -split '\\', 2
    if ($parts.Count -lt 1) { throw "invalid registry key: $Key" }

    $root = $parts[0].ToUpperInvariant()
    $subKey = ''
    if ($parts.Count -gt 1) { $subKey = $parts[1].Trim('\') }

    switch ($root) {
        'HKEY_USERS'         { $hive = [Microsoft.Win32.RegistryHive]::Users; break }
        'HKU'                { $hive = [Microsoft.Win32.RegistryHive]::Users; break }
        'HKEY_LOCAL_MACHINE' { $hive = [Microsoft.Win32.RegistryHive]::LocalMachine; break }
        'HKLM'               { $hive = [Microsoft.Win32.RegistryHive]::LocalMachine; break }
        'HKEY_CURRENT_USER'  { $hive = [Microsoft.Win32.RegistryHive]::CurrentUser; break }
        'HKCU'               { $hive = [Microsoft.Win32.RegistryHive]::CurrentUser; break }
        default              { throw "unsupported registry root '$root' for ACL repair: $Key" }
    }

    return [pscustomobject]@{ Hive = $hive; SubKey = $subKey }
}


function Convert-QolCurrentUserRegistryKeyToUsersHive {
    param([Parameter(Mandatory=$true)][string]$Key)

    $normalized = (($Key -replace '/', '\').Trim('\'))
    if ($normalized -notmatch '(?i)^(HKEY_CURRENT_USER|HKCU)(\\.*)?$') { return $Key }

    $tail = ''
    $split = $normalized -split '\\', 2
    if ($split.Count -gt 1) { $tail = $split[1].Trim('\') }

    try { $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value } catch { $sid = '' }
    if ([string]::IsNullOrWhiteSpace($sid) -or $sid -eq 'S-1-5-18') { return $Key }

    $converted = "HKEY_USERS\$sid"
    if (-not [string]::IsNullOrWhiteSpace($tail)) { $converted = "$converted\$tail" }

    try {
        if (Test-Path -LiteralPath "Registry::HKEY_USERS\$sid") { return $converted }
    } catch { }

    return $Key
}

function Get-QolNativeRegistryRootHandle {
    param([Parameter(Mandatory=$true)]$Hive)

    switch ([string]$Hive) {
        'CurrentUser'  { return [TI.RegistryNative]::HKEY_CURRENT_USER }
        'LocalMachine' { return [TI.RegistryNative]::HKEY_LOCAL_MACHINE }
        'Users'        { return [TI.RegistryNative]::HKEY_USERS }
        'ClassesRoot'  { return [TI.RegistryNative]::HKEY_CLASSES_ROOT }
        default        { throw "unsupported native registry hive '$Hive'" }
    }
}

function Get-QolWin32ErrorText {
    param([Parameter(Mandatory=$true)][int]$ErrorCode)
    try { return (New-Object System.ComponentModel.Win32Exception -ArgumentList $ErrorCode).Message }
    catch { return "Win32 error $ErrorCode" }
}

function Invoke-QolNativeRegistrySetValue {
    param(
        [Parameter(Mandatory=$true)][string]$Key,
        [AllowEmptyString()][Parameter(Mandatory=$true)][string]$Name,
        [AllowEmptyString()][Parameter(Mandatory=$true)][object]$Value,
        [Parameter(Mandatory=$true)][ValidateSet('DWord','String','Binary')][string]$Type,
        [switch]$CreateKey
    )

    $effectiveKey = Convert-QolCurrentUserRegistryKeyToUsersHive -Key $Key
    $parsed = Split-QolRegistryKeyForDotNet -Key $effectiveKey
    $rootHandle = Get-QolNativeRegistryRootHandle -Hive $parsed.Hive
    $subKey = ([string]$parsed.SubKey).Trim('\')
    $handle = [IntPtr]::Zero
    $disposition = 0

    try {
        Enable-TIRegistryPrivileges

        $desired = [TI.RegistryNative]::KEY_QUERY_VALUE -bor [TI.RegistryNative]::KEY_SET_VALUE -bor [TI.RegistryNative]::KEY_CREATE_SUB_KEY -bor [TI.RegistryNative]::KEY_WOW64_64KEY
        if ($CreateKey) {
            $status = [TI.RegistryNative]::RegCreateKeyEx($rootHandle, $subKey, 0, $null, [TI.RegistryNative]::REG_OPTION_BACKUP_RESTORE, $desired, [IntPtr]::Zero, [ref]$handle, [ref]$disposition)
            if ($status -ne 0) {
                $status = [TI.RegistryNative]::RegCreateKeyEx($rootHandle, $subKey, 0, $null, [TI.RegistryNative]::REG_OPTION_NON_VOLATILE, $desired, [IntPtr]::Zero, [ref]$handle, [ref]$disposition)
            }
        } else {
            $status = [TI.RegistryNative]::RegOpenKeyEx($rootHandle, $subKey, 0, $desired, [ref]$handle)
        }

        if ($status -ne 0 -or $handle -eq [IntPtr]::Zero) {
            return [pscustomobject]@{ Ok = $false; Message = ("native open/create failed for {0}: {1} ({2})" -f $effectiveKey, (Get-QolWin32ErrorText -ErrorCode $status), $status) }
        }

        switch ($Type) {
            'DWord' {
                $dword = [uint32](Convert-ToUInt32Value -Value $Value)
                $status = [TI.RegistryNative]::RegSetValueExDword($handle, $Name, 0, [TI.RegistryNative]::REG_DWORD, [ref]$dword, 4)
                break
            }
            'String' {
                $stringData = [string]$Value
                $byteCount = [System.Text.Encoding]::Unicode.GetByteCount($stringData + [char]0)
                $status = [TI.RegistryNative]::RegSetValueExString($handle, $Name, 0, [TI.RegistryNative]::REG_SZ, $stringData, $byteCount)
                break
            }
            'Binary' {
                $bytes = [byte[]](Convert-ToRegistryBinaryBytes -Value $Value)
                $status = [TI.RegistryNative]::RegSetValueExBinary($handle, $Name, 0, [TI.RegistryNative]::REG_BINARY, $bytes, $bytes.Length)
                break
            }
        }

        if ($status -ne 0) {
            return [pscustomobject]@{ Ok = $false; Message = ("native set failed for {0}\{1}: {2} ({3})" -f $effectiveKey, $Name, (Get-QolWin32ErrorText -ErrorCode $status), $status) }
        }

        if ($effectiveKey -ne $Key) {
            return [pscustomobject]@{ Ok = $true; Message = "native RegSetValueEx/backup-restore ($Key -> $effectiveKey)" }
        }
        return [pscustomobject]@{ Ok = $true; Message = 'native RegSetValueEx/backup-restore' }
    }
    catch {
        return [pscustomobject]@{ Ok = $false; Message = "native registry set exception for $effectiveKey\${Name}: $($_.Exception.Message)" }
    }
    finally {
        if ($handle -ne [IntPtr]::Zero) { try { [TI.RegistryNative]::RegCloseKey($handle) | Out-Null } catch { } }
    }
}

function Invoke-QolNativeRegistryRemoveValue {
    param(
        [Parameter(Mandatory=$true)][string]$Key,
        [Parameter(Mandatory=$true)][string]$Name
    )

    $effectiveKey = Convert-QolCurrentUserRegistryKeyToUsersHive -Key $Key
    $parsed = Split-QolRegistryKeyForDotNet -Key $effectiveKey
    $rootHandle = Get-QolNativeRegistryRootHandle -Hive $parsed.Hive
    $subKey = ([string]$parsed.SubKey).Trim('\')
    $handle = [IntPtr]::Zero
    $disposition = 0

    try {
        Enable-TIRegistryPrivileges
        $desired = [TI.RegistryNative]::KEY_QUERY_VALUE -bor [TI.RegistryNative]::KEY_SET_VALUE -bor [TI.RegistryNative]::KEY_WOW64_64KEY
        $status = [TI.RegistryNative]::RegCreateKeyEx($rootHandle, $subKey, 0, $null, [TI.RegistryNative]::REG_OPTION_BACKUP_RESTORE, $desired, [IntPtr]::Zero, [ref]$handle, [ref]$disposition)
        if ($status -ne 0) {
            $status = [TI.RegistryNative]::RegOpenKeyEx($rootHandle, $subKey, 0, $desired, [ref]$handle)
        }
        if ($status -ne 0 -or $handle -eq [IntPtr]::Zero) {
            if ($status -eq [TI.RegistryNative]::ERROR_FILE_NOT_FOUND) { return [pscustomobject]@{ Ok = $true; Warning = $true; Message = "key not found: $effectiveKey" } }
            return [pscustomobject]@{ Ok = $false; Message = ("native open failed for {0}: {1} ({2})" -f $effectiveKey, (Get-QolWin32ErrorText -ErrorCode $status), $status) }
        }

        $status = [TI.RegistryNative]::RegDeleteValue($handle, $Name)
        if ($status -eq 0) { return [pscustomobject]@{ Ok = $true; Message = 'native RegDeleteValue/backup-restore' } }
        if ($status -eq [TI.RegistryNative]::ERROR_FILE_NOT_FOUND) { return [pscustomobject]@{ Ok = $true; Warning = $true; Message = "value not found: $effectiveKey\$Name" } }
        return [pscustomobject]@{ Ok = $false; Message = ("native delete failed for {0}\{1}: {2} ({3})" -f $effectiveKey, $Name, (Get-QolWin32ErrorText -ErrorCode $status), $status) }
    }
    catch {
        return [pscustomobject]@{ Ok = $false; Message = "native registry delete exception for $effectiveKey\${Name}: $($_.Exception.Message)" }
    }
    finally {
        if ($handle -ne [IntPtr]::Zero) { try { [TI.RegistryNative]::RegCloseKey($handle) | Out-Null } catch { } }
    }
}

function Repair-QolTemporaryLoadedHiveRegistryAccess {
    param(
        [Parameter(Mandatory=$true)][string]$Key,
        [switch]$ForceProtectedAcl
    )

    if (-not (Test-QolTemporaryLoadedHiveRegistryKey -Key $Key)) {
        return [pscustomobject]@{ Ok = $false; Message = 'ACL repair skipped: unsupported HKU user hive key' }
    }

    try { Enable-TIRegistryPrivileges } catch { }

    $parsed = Split-QolRegistryKeyForDotNet -Key $Key
    if ($parsed.Hive -ne [Microsoft.Win32.RegistryHive]::Users) {
        return [pscustomobject]@{ Ok = $false; Message = 'ACL repair skipped: only HKU user hives are handled' }
    }

    $baseKey = $null
    $messages = New-Object System.Collections.Generic.List[string]

    try {
        $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey($parsed.Hive, [Microsoft.Win32.RegistryView]::Default)
        $target = ([string]$parsed.SubKey).Trim('\')
        if ([string]::IsNullOrWhiteSpace($target)) {
            return [pscustomobject]@{ Ok = $false; Message = 'ACL repair skipped: empty HKU subkey' }
        }

        $parts = $target -split '\\'
        $candidates = New-Object System.Collections.Generic.List[string]
        for ($i = $parts.Count; $i -ge 1; $i--) {
            [void]$candidates.Add(($parts[0..($i - 1)] -join '\'))
        }

        $ownerSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
        $adminsSid = New-Object System.Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-32-544'
        $systemSid = New-Object System.Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-18'
        $fullControl = [System.Security.AccessControl.RegistryRights]::FullControl
        $inheritFlags = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit
        $propFlags = [System.Security.AccessControl.PropagationFlags]::None
        $allowType = [System.Security.AccessControl.AccessControlType]::Allow

        foreach ($candidate in $candidates) {
            $takeKey = $null
            try {
                $takeRights = [System.Security.AccessControl.RegistryRights]::TakeOwnership
                $takeKey = $baseKey.OpenSubKey($candidate, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree, $takeRights)
                if ($null -eq $takeKey) {
                    [void]$messages.Add("not found: HKU\${candidate}")
                    continue
                }

                $ownerAcl = New-Object System.Security.AccessControl.RegistrySecurity
                $ownerAcl.SetOwner($ownerSid)
                $takeKey.SetAccessControl($ownerAcl)
            } catch {
                [void]$messages.Add("owner set failed on HKU\${candidate}: $($_.Exception.Message)")
                continue
            } finally {
                if ($null -ne $takeKey) { try { $takeKey.Close() } catch { } }
            }

            $permKey = $null
            try {
                $permRights = [System.Security.AccessControl.RegistryRights]::ChangePermissions -bor [System.Security.AccessControl.RegistryRights]::ReadPermissions
                $permKey = $baseKey.OpenSubKey($candidate, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree, $permRights)
                if ($null -eq $permKey) {
                    [void]$messages.Add("cannot reopen permissions on HKU\${candidate}")
                    continue
                }

                $acl = $permKey.GetAccessControl([System.Security.AccessControl.AccessControlSections]::All)
                if ($ForceProtectedAcl) {
                    try {
                        $acl.SetAccessRuleProtection($true, $false)
                        foreach ($rule in @($acl.Access)) {
                            try { [void]$acl.RemoveAccessRuleSpecific($rule) } catch { }
                        }
                    } catch { }
                }

                $ownerRule = New-Object System.Security.AccessControl.RegistryAccessRule -ArgumentList $ownerSid, $fullControl, $inheritFlags, $propFlags, $allowType
                $adminsRule = New-Object System.Security.AccessControl.RegistryAccessRule -ArgumentList $adminsSid, $fullControl, $inheritFlags, $propFlags, $allowType
                $systemRule = New-Object System.Security.AccessControl.RegistryAccessRule -ArgumentList $systemSid, $fullControl, $inheritFlags, $propFlags, $allowType
                $acl.SetAccessRule($ownerRule)
                $acl.SetAccessRule($adminsRule)
                $acl.SetAccessRule($systemRule)
                $permKey.SetAccessControl($acl)

                return [pscustomobject]@{ Ok = $true; Message = "ACL repaired on HKU\${candidate}" }
            } catch {
                [void]$messages.Add("permission set failed on HKU\${candidate}: $($_.Exception.Message)")
                continue
            } finally {
                if ($null -ne $permKey) { try { $permKey.Close() } catch { } }
            }
        }

        $messageText = ($messages.ToArray() -join ' | ')
        if ([string]::IsNullOrWhiteSpace($messageText)) { $messageText = 'no existing candidate key could be repaired' }
        return [pscustomobject]@{ Ok = $false; Message = $messageText }
    } catch {
        return [pscustomobject]@{ Ok = $false; Message = $_.Exception.Message }
    } finally {
        if ($null -ne $baseKey) { try { $baseKey.Close() } catch { } }
    }
}

function Invoke-QolRegistryAclRepairSetValue {
    param(
        [Parameter(Mandatory=$true)][string]$Key,
        [AllowEmptyString()][Parameter(Mandatory=$true)][string]$Name,
        [AllowEmptyString()][Parameter(Mandatory=$true)][object]$Value,
        [Parameter(Mandatory=$true)][ValidateSet('DWord','String','Binary')][string]$Type
    )

    if (-not (Test-QolTemporaryLoadedHiveRegistryKey -Key $Key)) {
        return [pscustomobject]@{ Ok = $false; Message = 'not an ACL-repair-supported HKU user hive key' }
    }

    $psPath = "Registry::$Key"
    $messages = New-Object System.Collections.Generic.List[string]

    foreach ($force in @($false, $true)) {
        $repair = Repair-QolTemporaryLoadedHiveRegistryAccess -Key $Key -ForceProtectedAcl:([bool]$force)
        [void]$messages.Add($repair.Message)
        if (-not $repair.Ok) { continue }

        try {
            if (-not (Test-Path -LiteralPath $psPath)) {
                New-Item -Path $psPath -Force -ErrorAction Stop | Out-Null
            }
            Set-QolRegistryValueViaProvider -Key $Key -Name $Name -Value $Value -Type $Type
            return [pscustomobject]@{ Ok = $true; Message = $repair.Message }
        } catch {
            [void]$messages.Add("provider write after ACL repair failed: $($_.Exception.Message)")
        }

        $nativeAfterRepair = Invoke-QolNativeRegistrySetValue -Key $Key -Name $Name -Value $Value -Type $Type -CreateKey
        [void]$messages.Add($nativeAfterRepair.Message)
        if ($nativeAfterRepair.Ok) {
            return [pscustomobject]@{ Ok = $true; Message = "$($repair.Message); $($nativeAfterRepair.Message)" }
        }
    }

    return [pscustomobject]@{ Ok = $false; Message = ($messages.ToArray() -join ' | ') }
}

function Invoke-QolRegistryAclRepairRemoveValue {
    param(
        [Parameter(Mandatory=$true)][string]$Key,
        [Parameter(Mandatory=$true)][string]$Name
    )

    if (-not (Test-QolTemporaryLoadedHiveRegistryKey -Key $Key)) {
        return [pscustomobject]@{ Ok = $false; Message = 'not an ACL-repair-supported HKU user hive key' }
    }

    $messages = New-Object System.Collections.Generic.List[string]

    foreach ($force in @($false, $true)) {
        $repair = Repair-QolTemporaryLoadedHiveRegistryAccess -Key $Key -ForceProtectedAcl:([bool]$force)
        [void]$messages.Add($repair.Message)
        if (-not $repair.Ok) { continue }

        try {
            Remove-QolRegistryValueViaProvider -Key $Key -Name $Name
            return [pscustomobject]@{ Ok = $true; Message = $repair.Message }
        } catch {
            [void]$messages.Add("provider delete after ACL repair failed: $($_.Exception.Message)")
        }

        $nativeAfterRepair = Invoke-QolNativeRegistryRemoveValue -Key $Key -Name $Name
        [void]$messages.Add($nativeAfterRepair.Message)
        if ($nativeAfterRepair.Ok) {
            return [pscustomobject]@{ Ok = $true; Message = "$($repair.Message); $($nativeAfterRepair.Message)" }
        }
    }

    return [pscustomobject]@{ Ok = $false; Message = ($messages.ToArray() -join ' | ') }
}

function Invoke-QolRegistrySetValueFallbacks {
    param(
        [Parameter(Mandatory=$true)][string]$Key,
        [AllowEmptyString()][Parameter(Mandatory=$true)][string]$Name,
        [AllowEmptyString()][Parameter(Mandatory=$true)][object]$Value,
        [Parameter(Mandatory=$true)][ValidateSet('DWord','String','Binary')][string]$Type
    )

    $fallbackKey = Convert-QolCurrentUserRegistryKeyToUsersHive -Key $Key

    $nativeCurrent = Invoke-QolNativeRegistrySetValue -Key $fallbackKey -Name $Name -Value $Value -Type $Type -CreateKey
    if ($nativeCurrent.Ok) {
        return [pscustomobject]@{ Ok = $true; Message = $nativeCurrent.Message }
    }

    $script:_tiRegistryProviderOk = $false
    $script:_tiRegistryProviderError = ''
    $script:_qolTiKey = $fallbackKey
    $script:_qolTiName = $Name
    $script:_qolTiValue = $Value
    $script:_qolTiType = $Type
    $tiOk = Invoke-AsTrustedInstaller {
        try {
            Set-QolRegistryValueViaProvider -Key $script:_qolTiKey -Name $script:_qolTiName -Value $script:_qolTiValue -Type $script:_qolTiType
            $script:_tiRegistryProviderOk = $true
        } catch {
            $script:_tiRegistryProviderError = $_.Exception.Message
            $script:_tiRegistryProviderOk = $false
        }
    }
    $tiText = $script:_tiRegistryProviderError
    if ([string]::IsNullOrWhiteSpace($tiText)) { $tiText = 'TrustedInstaller/provider fallback did not complete' }
    if ($tiOk -and $script:_tiRegistryProviderOk) {
        return [pscustomobject]@{ Ok = $true; Message = 'TrustedInstaller/provider' }
    }

    $script:_systemRegistryProviderOk = $false
    $script:_systemRegistryProviderError = ''
    $script:_qolSystemKey = $fallbackKey
    $script:_qolSystemName = $Name
    $script:_qolSystemValue = $Value
    $script:_qolSystemType = $Type
    $systemOk = Invoke-AsLocalSystem {
        try {
            Set-QolRegistryValueViaProvider -Key $script:_qolSystemKey -Name $script:_qolSystemName -Value $script:_qolSystemValue -Type $script:_qolSystemType
            $script:_systemRegistryProviderOk = $true
        } catch {
            $script:_systemRegistryProviderError = $_.Exception.Message
            $script:_systemRegistryProviderOk = $false
        }
    }
    $systemText = $script:_systemRegistryProviderError
    if ([string]::IsNullOrWhiteSpace($systemText)) { $systemText = 'SYSTEM/provider fallback did not complete' }
    if ($systemOk -and $script:_systemRegistryProviderOk) {
        return [pscustomobject]@{ Ok = $true; Message = 'SYSTEM/provider' }
    }

    $script:_tiRegistryNativeOk = $false
    $script:_tiRegistryNativeText = ''
    $script:_qolTiNativeKey = $fallbackKey
    $script:_qolTiNativeName = $Name
    $script:_qolTiNativeValue = $Value
    $script:_qolTiNativeType = $Type
    $tiNativeOk = Invoke-AsTrustedInstaller {
        $nativeResult = Invoke-QolNativeRegistrySetValue -Key $script:_qolTiNativeKey -Name $script:_qolTiNativeName -Value $script:_qolTiNativeValue -Type $script:_qolTiNativeType -CreateKey
        $script:_tiRegistryNativeText = $nativeResult.Message
        $script:_tiRegistryNativeOk = [bool]$nativeResult.Ok
    }
    if ($tiNativeOk -and $script:_tiRegistryNativeOk) {
        return [pscustomobject]@{ Ok = $true; Message = "TrustedInstaller/native ($script:_tiRegistryNativeText)" }
    }
    if ([string]::IsNullOrWhiteSpace($script:_tiRegistryNativeText)) { $script:_tiRegistryNativeText = 'TrustedInstaller/native fallback did not complete' }

    $script:_systemRegistryNativeOk = $false
    $script:_systemRegistryNativeText = ''
    $script:_qolSystemNativeKey = $fallbackKey
    $script:_qolSystemNativeName = $Name
    $script:_qolSystemNativeValue = $Value
    $script:_qolSystemNativeType = $Type
    $systemNativeOk = Invoke-AsLocalSystem {
        $nativeResult = Invoke-QolNativeRegistrySetValue -Key $script:_qolSystemNativeKey -Name $script:_qolSystemNativeName -Value $script:_qolSystemNativeValue -Type $script:_qolSystemNativeType -CreateKey
        $script:_systemRegistryNativeText = $nativeResult.Message
        $script:_systemRegistryNativeOk = [bool]$nativeResult.Ok
    }
    if ($systemNativeOk -and $script:_systemRegistryNativeOk) {
        return [pscustomobject]@{ Ok = $true; Message = "SYSTEM/native ($script:_systemRegistryNativeText)" }
    }
    if ([string]::IsNullOrWhiteSpace($script:_systemRegistryNativeText)) { $script:_systemRegistryNativeText = 'SYSTEM/native fallback did not complete' }

    $aclRepair = Invoke-QolRegistryAclRepairSetValue -Key $fallbackKey -Name $Name -Value $Value -Type $Type
    if ($aclRepair.Ok) {
        return [pscustomobject]@{ Ok = $true; Message = "ACL repair/provider-native ($($aclRepair.Message))" }
    }

    return [pscustomobject]@{ Ok = $false; Message = "native/current fallback: $($nativeCurrent.Message) | TI/provider fallback: $tiText | SYSTEM/provider fallback: $systemText | TI/native fallback: $script:_tiRegistryNativeText | SYSTEM/native fallback: $script:_systemRegistryNativeText | ACL repair fallback: $($aclRepair.Message)" }
}

function Invoke-QolRegistryRemoveValueFallbacks {
    param(
        [Parameter(Mandatory=$true)][string]$Key,
        [Parameter(Mandatory=$true)][string]$Name
    )

    $fallbackKey = Convert-QolCurrentUserRegistryKeyToUsersHive -Key $Key

    $nativeCurrent = Invoke-QolNativeRegistryRemoveValue -Key $fallbackKey -Name $Name
    if ($nativeCurrent.Ok) {
        return [pscustomobject]@{ Ok = $true; Message = $nativeCurrent.Message; Warning = $nativeCurrent.Warning }
    }

    $script:_tiRegistryProviderOk = $false
    $script:_tiRegistryProviderError = ''
    $script:_qolTiKey = $fallbackKey
    $script:_qolTiName = $Name
    $tiOk = Invoke-AsTrustedInstaller {
        try {
            Remove-QolRegistryValueViaProvider -Key $script:_qolTiKey -Name $script:_qolTiName
            $script:_tiRegistryProviderOk = $true
        } catch {
            $script:_tiRegistryProviderError = $_.Exception.Message
            $script:_tiRegistryProviderOk = $false
        }
    }
    $tiText = $script:_tiRegistryProviderError
    if ([string]::IsNullOrWhiteSpace($tiText)) { $tiText = 'TrustedInstaller/provider fallback did not complete' }
    if ($tiOk -and $script:_tiRegistryProviderOk) {
        return [pscustomobject]@{ Ok = $true; Message = 'TrustedInstaller/provider' }
    }

    $script:_systemRegistryProviderOk = $false
    $script:_systemRegistryProviderError = ''
    $script:_qolSystemKey = $fallbackKey
    $script:_qolSystemName = $Name
    $systemOk = Invoke-AsLocalSystem {
        try {
            Remove-QolRegistryValueViaProvider -Key $script:_qolSystemKey -Name $script:_qolSystemName
            $script:_systemRegistryProviderOk = $true
        } catch {
            $script:_systemRegistryProviderError = $_.Exception.Message
            $script:_systemRegistryProviderOk = $false
        }
    }
    $systemText = $script:_systemRegistryProviderError
    if ([string]::IsNullOrWhiteSpace($systemText)) { $systemText = 'SYSTEM/provider fallback did not complete' }
    if ($systemOk -and $script:_systemRegistryProviderOk) {
        return [pscustomobject]@{ Ok = $true; Message = 'SYSTEM/provider' }
    }

    $script:_tiRegistryNativeOk = $false
    $script:_tiRegistryNativeText = ''
    $script:_qolTiNativeKey = $fallbackKey
    $script:_qolTiNativeName = $Name
    $tiNativeOk = Invoke-AsTrustedInstaller {
        $nativeResult = Invoke-QolNativeRegistryRemoveValue -Key $script:_qolTiNativeKey -Name $script:_qolTiNativeName
        $script:_tiRegistryNativeText = $nativeResult.Message
        $script:_tiRegistryNativeOk = [bool]$nativeResult.Ok
    }
    if ($tiNativeOk -and $script:_tiRegistryNativeOk) {
        return [pscustomobject]@{ Ok = $true; Message = "TrustedInstaller/native ($script:_tiRegistryNativeText)" }
    }
    if ([string]::IsNullOrWhiteSpace($script:_tiRegistryNativeText)) { $script:_tiRegistryNativeText = 'TrustedInstaller/native fallback did not complete' }

    $script:_systemRegistryNativeOk = $false
    $script:_systemRegistryNativeText = ''
    $script:_qolSystemNativeKey = $fallbackKey
    $script:_qolSystemNativeName = $Name
    $systemNativeOk = Invoke-AsLocalSystem {
        $nativeResult = Invoke-QolNativeRegistryRemoveValue -Key $script:_qolSystemNativeKey -Name $script:_qolSystemNativeName
        $script:_systemRegistryNativeText = $nativeResult.Message
        $script:_systemRegistryNativeOk = [bool]$nativeResult.Ok
    }
    if ($systemNativeOk -and $script:_systemRegistryNativeOk) {
        return [pscustomobject]@{ Ok = $true; Message = "SYSTEM/native ($script:_systemRegistryNativeText)" }
    }
    if ([string]::IsNullOrWhiteSpace($script:_systemRegistryNativeText)) { $script:_systemRegistryNativeText = 'SYSTEM/native fallback did not complete' }

    $aclRepair = Invoke-QolRegistryAclRepairRemoveValue -Key $fallbackKey -Name $Name
    if ($aclRepair.Ok) {
        return [pscustomobject]@{ Ok = $true; Message = "ACL repair/provider-native ($($aclRepair.Message))" }
    }

    return [pscustomobject]@{ Ok = $false; Message = "native/current fallback: $($nativeCurrent.Message) | TI/provider fallback: $tiText | SYSTEM/provider fallback: $systemText | TI/native fallback: $script:_tiRegistryNativeText | SYSTEM/native fallback: $script:_systemRegistryNativeText | ACL repair fallback: $($aclRepair.Message)" }
}


function Set-RegistryDword {
    param(
        [Parameter(Mandatory=$true)][string]$Key,
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][object]$Value,
        [switch]$CreateKey
    )

    $psPath = "Registry::$Key"

    try {
        if (-not (Test-Path -LiteralPath $psPath)) {
            if ($CreateKey) {
                try { New-Item -Path $psPath -Force | Out-Null }
                catch {
                    $script:_tiRegistryProviderOk = $false
                    $script:_tiRegistryProviderError = ''
                    $script:_qolTiPsPath = $psPath
                    $tiCreateOk = Invoke-AsTrustedInstaller {
                        try {
                            New-Item -Path $script:_qolTiPsPath -Force -ErrorAction Stop | Out-Null
                            $script:_tiRegistryProviderOk = $true
                        } catch {
                            $script:_tiRegistryProviderError = $_.Exception.Message
                            $script:_tiRegistryProviderOk = $false
                        }
                    }
                    if ((-not $tiCreateOk) -or (-not $script:_tiRegistryProviderOk) -or (-not (Test-Path -LiteralPath $psPath))) {
                        $detail = $script:_tiRegistryProviderError
                        if ([string]::IsNullOrWhiteSpace($detail)) { $detail = 'TrustedInstaller/provider key creation did not complete' }
                        $nativeCreateWrite = Invoke-QolNativeRegistrySetValue -Key $Key -Name $Name -Value $Value -Type 'DWord' -CreateKey
                        if ($nativeCreateWrite.Ok) { return $nativeCreateWrite }
                        return [pscustomobject]@{ Ok = $false; Message = "cannot create key (even under TI/provider/native): $Key | $detail | $($nativeCreateWrite.Message)" }
                    }
                }
            } else {
                return [pscustomobject]@{ Ok = $true; Warning = $true; Message = "key not found: $Key" }
            }
        }

        $uintValue = Convert-ToUInt32Value -Value $Value
        $dwordText = ('0x{0:x8}' -f $uintValue)

        $native = Invoke-QolNativeCommandCaptured -FilePath 'reg.exe' -Arguments @('add', $Key, '/v', $Name, '/t', 'REG_DWORD', '/d', $dwordText, '/f')
        if ($native.ExitCode -ne 0) {
            $fallback = Invoke-QolRegistrySetValueFallbacks -Key $Key -Name $Name -Value $uintValue -Type 'DWord'
            if (-not $fallback.Ok) {
                $nativeText = ($native.Output -join ' ')
                return [pscustomobject]@{ Ok = $false; Message = ("reg.exe exit code $($native.ExitCode) for $Key\$Name | $nativeText | $($fallback.Message)") }
            }
        }

        try {
            $actual = (Get-ItemProperty -LiteralPath $psPath -Name $Name -ErrorAction Stop).$Name
            $actualUint = Convert-RegistryDwordReadToUInt32 -Value $actual
            if ($actualUint -ne $uintValue) {
                return [pscustomobject]@{ Ok = $false; Message = "verification mismatch: $Key\$Name expected $dwordText but read $('0x{0:x8}' -f $actualUint)" }
            }
        } catch {
        }

        return [pscustomobject]@{ Ok = $true; Message = "$Key\$Name = $dwordText" }
    }
    catch {
        return [pscustomobject]@{ Ok = $false; Message = "$Key\$Name -> $($_.Exception.Message)" }
    }
}


function Set-RegistryString {
    param(
        [Parameter(Mandatory=$true)][string]$Key,
        [Parameter(Mandatory=$true)][string]$Name,
        [AllowEmptyString()][Parameter(Mandatory=$true)][string]$Value,
        [switch]$CreateKey
    )

    $psPath = "Registry::$Key"

    try {
        if (-not (Test-Path -LiteralPath $psPath)) {
            if ($CreateKey) {
                try { New-Item -Path $psPath -Force | Out-Null }
                catch {
                    $script:_tiRegistryProviderOk = $false
                    $script:_tiRegistryProviderError = ''
                    $script:_qolTiPsPath = $psPath
                    $tiCreateOk = Invoke-AsTrustedInstaller {
                        try {
                            New-Item -Path $script:_qolTiPsPath -Force -ErrorAction Stop | Out-Null
                            $script:_tiRegistryProviderOk = $true
                        } catch {
                            $script:_tiRegistryProviderError = $_.Exception.Message
                            $script:_tiRegistryProviderOk = $false
                        }
                    }
                    if ((-not $tiCreateOk) -or (-not $script:_tiRegistryProviderOk) -or (-not (Test-Path -LiteralPath $psPath))) {
                        $detail = $script:_tiRegistryProviderError
                        if ([string]::IsNullOrWhiteSpace($detail)) { $detail = 'TrustedInstaller/provider key creation did not complete' }
                        $nativeCreateWrite = Invoke-QolNativeRegistrySetValue -Key $Key -Name $Name -Value $Value -Type 'String' -CreateKey
                        if ($nativeCreateWrite.Ok) { return $nativeCreateWrite }
                        return [pscustomobject]@{ Ok = $false; Message = "cannot create key (even under TI/provider/native): $Key | $detail | $($nativeCreateWrite.Message)" }
                    }
                }
            } else {
                return [pscustomobject]@{ Ok = $true; Warning = $true; Message = "key not found: $Key" }
            }
        }

        $native = Invoke-QolNativeCommandCaptured -FilePath 'reg.exe' -Arguments @('add', $Key, '/v', $Name, '/t', 'REG_SZ', '/d', $Value, '/f')
        if ($native.ExitCode -ne 0) {
            $fallback = Invoke-QolRegistrySetValueFallbacks -Key $Key -Name $Name -Value $Value -Type 'String'
            if (-not $fallback.Ok) {
                $nativeText = ($native.Output -join ' ')
                return [pscustomobject]@{ Ok = $false; Message = ("reg.exe exit code $($native.ExitCode) for $Key\$Name | $nativeText | $($fallback.Message)") }
            }
        }

        try {
            $actual = (Get-ItemProperty -LiteralPath $psPath -Name $Name -ErrorAction Stop).$Name
            if ([string]$actual -ne $Value) {
                return [pscustomobject]@{ Ok = $false; Message = "verification mismatch: $Key\$Name expected '$Value' but read '$actual'" }
            }
        } catch {
        }

        return [pscustomobject]@{ Ok = $true; Message = "$Key\$Name = '$Value'" }
    }
    catch {
        return [pscustomobject]@{ Ok = $false; Message = "$Key\$Name -> $($_.Exception.Message)" }
    }
}


function Set-RegistryDefaultString {
    param(
        [Parameter(Mandatory=$true)][string]$Key,
        [AllowEmptyString()][string]$Value = '',
        [switch]$CreateKey
    )

    $psPath = "Registry::$Key"

    try {
        if (-not (Test-Path -LiteralPath $psPath)) {
            if ($CreateKey) {
                try { New-Item -Path $psPath -Force -ErrorAction Stop | Out-Null }
                catch {
                    $fallbackCreate = Invoke-QolRegistrySetValueFallbacks -Key $Key -Name '' -Value ([string]$Value) -Type 'String'
                    if ($fallbackCreate.Ok) {
                        return [pscustomobject]@{ Ok = $true; Message = "$Key\(Default) = '$Value' ($($fallbackCreate.Message))" }
                    }
                    return [pscustomobject]@{ Ok = $false; Message = "cannot create/set default value for $Key | $($fallbackCreate.Message)" }
                }
            } else {
                return [pscustomobject]@{ Ok = $true; Warning = $true; Message = "key not found: $Key" }
            }
        }

        try {
            $registryKey = Get-Item -LiteralPath $psPath -ErrorAction Stop
            $registryKey.SetValue('', [string]$Value, [Microsoft.Win32.RegistryValueKind]::String)
        }
        catch {
            $fallback = Invoke-QolRegistrySetValueFallbacks -Key $Key -Name '' -Value ([string]$Value) -Type 'String'
            if (-not $fallback.Ok) {
                return [pscustomobject]@{ Ok = $false; Message = "default value write failed for $Key | provider: $($_.Exception.Message) | $($fallback.Message)" }
            }
        }

        try {
            $registryKey = Get-Item -LiteralPath $psPath -ErrorAction Stop
            $actual = $registryKey.GetValue('', $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            if ($null -eq $actual) {
                return [pscustomobject]@{ Ok = $false; Message = "verification mismatch: $Key\(Default) is absent, expected blank REG_SZ" }
            }
            if ([string]$actual -ne [string]$Value) {
                return [pscustomobject]@{ Ok = $false; Message = "verification mismatch: $Key\(Default) expected '$Value' but read '$actual'" }
            }
        } catch {
            return [pscustomobject]@{ Ok = $false; Message = "verification failed for $Key\(Default) -> $($_.Exception.Message)" }
        }

        return [pscustomobject]@{ Ok = $true; Message = "$Key\(Default) = '$Value'" }
    }
    catch {
        return [pscustomobject]@{ Ok = $false; Message = "$Key\(Default) -> $($_.Exception.Message)" }
    }
}


function Convert-ToRegistryBinaryBytes {
    param(
        [Parameter(Mandatory=$true)][object]$Value
    )

    if ($Value -is [byte[]]) {
        return [byte[]]$Value
    }

    if (($Value -is [System.Collections.IEnumerable]) -and -not ($Value -is [string])) {
        $list = New-Object System.Collections.Generic.List[byte]
        foreach ($entry in @($Value)) {
            [void]$list.Add([Convert]::ToByte($entry))
        }
        return [byte[]]$list.ToArray()
    }

    $text = ([string]$Value).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) {
        throw 'binary registry value was empty'
    }

    $text = $text -replace '^hex\([0-9]+\):', ''
    $text = $text -replace '^hex:', ''
    $hex = ($text -replace '[^0-9a-fA-F]', '')
    if (($hex.Length -eq 0) -or (($hex.Length % 2) -ne 0)) {
        throw "binary registry value '$Value' is not valid even-length hex"
    }

    $bytes = New-Object byte[] ($hex.Length / 2)
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        $bytes[$i] = [Convert]::ToByte($hex.Substring($i * 2, 2), 16)
    }
    return [byte[]]$bytes
}

function Convert-RegistryBinaryBytesToHexText {
    param(
        [Parameter(Mandatory=$true)][byte[]]$Bytes,
        [switch]$Compact
    )

    $parts = @($Bytes | ForEach-Object { '{0:X2}' -f $_ })
    if ($Compact) { return ($parts -join '') }
    return ($parts -join ' ')
}

function Set-RegistryBinary {
    param(
        [Parameter(Mandatory=$true)][string]$Key,
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][object]$Value,
        [switch]$CreateKey
    )

    $psPath = "Registry::$Key"

    try {
        if (-not (Test-Path -LiteralPath $psPath)) {
            if ($CreateKey) {
                try { New-Item -Path $psPath -Force | Out-Null }
                catch {
                    $script:_tiRegistryProviderOk = $false
                    $script:_tiRegistryProviderError = ''
                    $script:_qolTiPsPath = $psPath
                    $tiCreateOk = Invoke-AsTrustedInstaller {
                        try {
                            New-Item -Path $script:_qolTiPsPath -Force -ErrorAction Stop | Out-Null
                            $script:_tiRegistryProviderOk = $true
                        } catch {
                            $script:_tiRegistryProviderError = $_.Exception.Message
                            $script:_tiRegistryProviderOk = $false
                        }
                    }
                    if ((-not $tiCreateOk) -or (-not $script:_tiRegistryProviderOk) -or (-not (Test-Path -LiteralPath $psPath))) {
                        $detail = $script:_tiRegistryProviderError
                        if ([string]::IsNullOrWhiteSpace($detail)) { $detail = 'TrustedInstaller/provider key creation did not complete' }
                        $nativeCreateWrite = Invoke-QolNativeRegistrySetValue -Key $Key -Name $Name -Value $Value -Type 'Binary' -CreateKey
                        if ($nativeCreateWrite.Ok) { return $nativeCreateWrite }
                        return [pscustomobject]@{ Ok = $false; Message = "cannot create key (even under TI/provider/native): $Key | $detail | $($nativeCreateWrite.Message)" }
                    }
                }
            } else {
                return [pscustomobject]@{ Ok = $true; Warning = $true; Message = "key not found: $Key" }
            }
        }

        $bytes = Convert-ToRegistryBinaryBytes -Value $Value
        $hexCompact = Convert-RegistryBinaryBytesToHexText -Bytes $bytes -Compact
        $hexDisplay = Convert-RegistryBinaryBytesToHexText -Bytes $bytes

        $native = Invoke-QolNativeCommandCaptured -FilePath 'reg.exe' -Arguments @('add', $Key, '/v', $Name, '/t', 'REG_BINARY', '/d', $hexCompact, '/f')
        if ($native.ExitCode -ne 0) {
            $fallback = Invoke-QolRegistrySetValueFallbacks -Key $Key -Name $Name -Value $bytes -Type 'Binary'
            if (-not $fallback.Ok) {
                $nativeText = ($native.Output -join ' ')
                return [pscustomobject]@{ Ok = $false; Message = ("reg.exe exit code $($native.ExitCode) for $Key\$Name | $nativeText | $($fallback.Message)") }
            }
        }

        try {
            $actual = (Get-ItemProperty -LiteralPath $psPath -Name $Name -ErrorAction Stop).$Name
            if (-not ($actual -is [byte[]])) {
                return [pscustomobject]@{ Ok = $false; Message = "verification mismatch: $Key\$Name expected REG_BINARY but read $($actual.GetType().FullName)" }
            }

            $actualBytes = [byte[]]$actual
            if ($actualBytes.Length -ne $bytes.Length) {
                $actualText = Convert-RegistryBinaryBytesToHexText -Bytes $actualBytes
                return [pscustomobject]@{ Ok = $false; Message = "verification mismatch: $Key\$Name expected hex:$hexDisplay but read hex:$actualText" }
            }

            for ($i = 0; $i -lt $bytes.Length; $i++) {
                if ($actualBytes[$i] -ne $bytes[$i]) {
                    $actualText = Convert-RegistryBinaryBytesToHexText -Bytes $actualBytes
                    return [pscustomobject]@{ Ok = $false; Message = "verification mismatch: $Key\$Name expected hex:$hexDisplay but read hex:$actualText" }
                }
            }
        } catch {
        }

        return [pscustomobject]@{ Ok = $true; Message = "$Key\$Name = hex:$hexDisplay" }
    }
    catch {
        return [pscustomobject]@{ Ok = $false; Message = "$Key\$Name -> $($_.Exception.Message)" }
    }
}


function Remove-RegistryValue {
    param(
        [Parameter(Mandatory=$true)][string]$Key,
        [Parameter(Mandatory=$true)][string]$Name
    )

    $psPath = "Registry::$Key"

    try {
        if (-not (Test-Path -LiteralPath $psPath)) {
            return [pscustomobject]@{ Ok = $true; Message = "already absent: $Key\$Name (key not found)" }
        }

        $property = Get-ItemProperty -LiteralPath $psPath -Name $Name -ErrorAction SilentlyContinue
        if ($null -eq $property -or -not ($property.PSObject.Properties.Name -contains $Name)) {
            return [pscustomobject]@{ Ok = $true; Message = "already absent: $Key\$Name" }
        }

        $native = Invoke-QolNativeCommandCaptured -FilePath 'reg.exe' -Arguments @('delete', $Key, '/v', $Name, '/f')
        if ($native.ExitCode -ne 0) {
            $fallback = Invoke-QolRegistryRemoveValueFallbacks -Key $Key -Name $Name
            if (-not $fallback.Ok) {
                $nativeText = ($native.Output -join ' ')
                return [pscustomobject]@{ Ok = $false; Message = ("reg.exe exit code $($native.ExitCode) for delete $Key\$Name | $nativeText | $($fallback.Message)") }
            }
        }

        $check = Get-ItemProperty -LiteralPath $psPath -Name $Name -ErrorAction SilentlyContinue
        if ($null -ne $check -and ($check.PSObject.Properties.Name -contains $Name)) {
            return [pscustomobject]@{ Ok = $false; Message = "verification mismatch: $Key\$Name still exists" }
        }

        return [pscustomobject]@{ Ok = $true; Message = "deleted: $Key\$Name" }
    }
    catch {
        return [pscustomobject]@{ Ok = $false; Message = "$Key\$Name -> $($_.Exception.Message)" }
    }
}


function Invoke-RegistrySet {
    param(
        [Parameter(Mandatory=$true)][string]$Title,
        [Parameter(Mandatory=$true)][object[]]$Items,
        [Parameter(Mandatory=$false)][AllowEmptyString()][string]$AfterMessage = ''
    )

    Clear-ConsoleScreen
    Write-BoxTitle -Title $Title
    Write-Host ""

    $failed = 0
    foreach ($item in $Items) {
        $create = $false
        if ($item.PSObject.Properties.Name -contains 'CreateKey') { $create = [bool]$item.CreateKey }

        $type = 'DWord'
        if ($item.PSObject.Properties.Name -contains 'Type') { $type = [string]$item.Type }

        switch -Regex ($type) {
            '^(DWord|REG_DWORD)$' {
                $result = Set-RegistryDword -Key $item.Key -Name $item.Name -Value $item.Value -CreateKey:$create
                break
            }
            '^(String|REG_SZ)$' {
                $result = Set-RegistryString -Key $item.Key -Name $item.Name -Value ([string]$item.Value) -CreateKey:$create
                break
            }
            '^(DefaultString|DefaultValue|REG_SZ_DEFAULT|REG_DEFAULT_SZ)$' {
                $value = ''
                if ($item.PSObject.Properties.Name -contains 'Value') { $value = [string]$item.Value }
                $result = Set-RegistryDefaultString -Key $item.Key -Value $value -CreateKey:$create
                break
            }
            '^(Binary|REG_BINARY)$' {
                $result = Set-RegistryBinary -Key $item.Key -Name $item.Name -Value $item.Value -CreateKey:$create
                break
            }
            '^(Delete|DeleteValue|Remove|RemoveValue|REG_DELETE)$' {
                $result = Remove-RegistryValue -Key $item.Key -Name $item.Name
                break
            }
            default {
                $result = [pscustomobject]@{ Ok = $false; Message = "unsupported registry value type '$type' for $($item.Key)\$($item.Name)" }
                break
            }
        }

        if (-not $result.Ok) { $failed++ }
        $isWarning = $false
        if ($result.PSObject.Properties.Name -contains 'Warning') { $isWarning = [bool]$result.Warning }
        Write-StatusLine -Ok $result.Ok -Text $result.Message -Warning:$isWarning
    }

    Write-Host ""
    if ($failed -eq 0) {
        Write-Host "OVERALL: SUCCESS" -ForegroundColor Green
    } else {
        Write-Host "OVERALL: FAILED - $failed item(s) failed." -ForegroundColor Red
    }

    if (-not [string]::IsNullOrWhiteSpace($AfterMessage)) {
        Write-Host ""
        Write-Host $AfterMessage
    }

    Write-Host ""
    Wait-ForEnterToContinue
}


function Get-OriginalScriptFolder {
    $scriptPath = $env:THIS
    if ([string]::IsNullOrWhiteSpace($scriptPath)) {
        $scriptPath = $PSCommandPath
    }

    try {
        $resolvedScriptPath = (Resolve-Path -LiteralPath $scriptPath -ErrorAction Stop).Path
        return (Split-Path -Parent $resolvedScriptPath)
    }
    catch {
        return (Split-Path -Parent $scriptPath)
    }
}

function Resolve-ScriptResourcePath {
    param([Parameter(Mandatory=$true)][string]$RelativePath)

    $scriptFolder = Get-OriginalScriptFolder
    $preferredPath = Join-Path -Path $scriptFolder -ChildPath $RelativePath
    if (Test-Path -LiteralPath $preferredPath -PathType Leaf) { return $preferredPath }

    # Support the two resources distributed beside this CMD in the repository.
    # Resources\ remains preferred; do not redirect arbitrary external tools.
    $bundledPaths = @{
        'Resources\DEVICE-TWEAKER\RUN-DEVICE-TWEAKER.bat' = 'DEVICE-TWEAKER\RUN-DEVICE-TWEAKER.bat'
        'Resources\POWER-PLAN\LLC-CERTIFIED.pow' = 'POWER-PLAN\LLC-CERTIFIED.pow'
    }
    $lookupPath = $RelativePath.Replace('/', '\')
    if ($bundledPaths.ContainsKey($lookupPath)) {
        $bundledPath = Join-Path -Path $scriptFolder -ChildPath $bundledPaths[$lookupPath]
        if (Test-Path -LiteralPath $bundledPath -PathType Leaf) { return $bundledPath }
    }
    return $preferredPath
}

function Invoke-NativeCommandCaptured {
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [string[]]$ArgumentList = @()
    )

    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& $FilePath @ArgumentList 2>&1)
        $exitCode = $LASTEXITCODE
        if ($null -eq $exitCode) { $exitCode = 0 }
        return [pscustomobject]@{ ExitCode = [int]$exitCode; Output = @($output) }
    }
    catch {
        return [pscustomobject]@{ ExitCode = 9999; Output = @($_.Exception.Message) }
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
}

function Convert-NativeCommandOutputToText {
    param([object[]]$Output)

    $text = ((@($Output) | ForEach-Object { [string]$_ }) -join ' ').Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return '<no output>' }
    return ($text -replace '\s+', ' ')
}

function Test-PowerSchemeExists {
    param([Parameter(Mandatory=$true)][string]$SchemeGuid)

    $queryResult = Invoke-NativeCommandCaptured -FilePath 'powercfg.exe' -ArgumentList @('/query', $SchemeGuid)
    return ($queryResult.ExitCode -eq 0)
}

function Get-ActivePowerSchemeGuid {
    $activeResult = Invoke-NativeCommandCaptured -FilePath 'powercfg.exe' -ArgumentList @('/getactivescheme')
    if ($activeResult.ExitCode -ne 0) { return '' }

    $activeText = Convert-NativeCommandOutputToText -Output $activeResult.Output
    $match = [regex]::Match($activeText, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}')
    if (-not $match.Success) { return '' }

    return $match.Value.ToLowerInvariant()
}

function Enable-LlcCertifiedPowerPlan {
    param(
        [Parameter(Mandatory=$true)][string]$PowerPlanPath,
        [Parameter(Mandatory=$true)][string]$SchemeGuid
    )

    $schemeGuidNormalized = $SchemeGuid.ToLowerInvariant()
    $schemeExists = Test-PowerSchemeExists -SchemeGuid $SchemeGuid

    if ($schemeExists) {
        Write-StatusLine -Ok $true -Text 'power plan already exists; continuing'
    } else {
        if (-not (Test-Path -LiteralPath $PowerPlanPath -PathType Leaf)) {
            Write-StatusLine -Ok $false -Text "power plan file not found: $PowerPlanPath"
            return $false
        }

        $importResult = Invoke-NativeCommandCaptured -FilePath 'powercfg.exe' -ArgumentList @('/import', $PowerPlanPath, $SchemeGuid)

        if ($importResult.ExitCode -eq 0) {
            Write-StatusLine -Ok $true -Text 'imported power plan'
        } else {
            $schemeExistsAfterImport = Test-PowerSchemeExists -SchemeGuid $SchemeGuid
            if ($schemeExistsAfterImport) {
                Write-StatusLine -Ok $true -Text 'power plan already exists; continuing'
            } else {
                Write-StatusLine -Ok $false -Text ("powercfg /import exit code {0}: {1}" -f $importResult.ExitCode, (Convert-NativeCommandOutputToText -Output $importResult.Output))
                return $false
            }
        }
    }

    $activeSchemeGuid = Get-ActivePowerSchemeGuid
    if ($activeSchemeGuid -ieq $schemeGuidNormalized) {
        Write-StatusLine -Ok $true -Text 'power plan already present and active'
        return $true
    }

    $activateResult = Invoke-NativeCommandCaptured -FilePath 'powercfg.exe' -ArgumentList @('/setactive', $SchemeGuid)
    if ($activateResult.ExitCode -eq 0) {
        $activeSchemeGuid = Get-ActivePowerSchemeGuid
        if ($activeSchemeGuid -ieq $schemeGuidNormalized) {
            Write-StatusLine -Ok $true -Text 'activated power plan'
        } else {
            Write-StatusLine -Ok $true -Text 'power plan activation command completed'
        }
        return $true
    }

    $activeSchemeGuid = Get-ActivePowerSchemeGuid
    if ($activeSchemeGuid -ieq $schemeGuidNormalized) {
        Write-StatusLine -Ok $true -Text 'power plan already present and active'
        return $true
    }

    Write-StatusLine -Ok $false -Text ("powercfg /setactive exit code {0}: {1}" -f $activateResult.ExitCode, (Convert-NativeCommandOutputToText -Output $activateResult.Output))
    return $false
}

function Invoke-PowerPlanImportAndActivate {
    Clear-ConsoleScreen
    Write-BoxTitle -Title 'Power Plan - Import and Activate'
    Write-Host ""

    $powerPlanPath = Resolve-ScriptResourcePath -RelativePath 'Resources\POWER-PLAN\LLC-CERTIFIED.pow'
    $schemeGuid = '8b24b027-1dee-4c65-8f35-5d5d91e51d87'

    if (Test-Path -LiteralPath $powerPlanPath -PathType Leaf) {
        Write-Host "Power plan file: $powerPlanPath" -ForegroundColor Green
    } else {
        Write-Host "Power plan file: $powerPlanPath" -ForegroundColor DarkGray
    }
    Write-Host "Power scheme GUID: $schemeGuid" -ForegroundColor Green
    Write-Host ""

    $ok = Enable-LlcCertifiedPowerPlan -PowerPlanPath $powerPlanPath -SchemeGuid $schemeGuid

    Write-Host ""
    if ($ok) {
        Write-Host "OVERALL: SUCCESS" -ForegroundColor Green
    } else {
        Write-Host "OVERALL: FAILED" -ForegroundColor Red
    }

    Write-Host ""
    Wait-ForEnterToContinue
}


function Invoke-WindowsActivationSettings {
    Invoke-ExternalBatchLauncher -Title 'Activate Windows - Activate WIN' -RelativePath 'Resources\ACTIVATE-WINDOWS\ACTIVATE-WINDOWS.bat'
}

function Invoke-ExternalBatchLauncher {
    param(
        [Parameter(Mandatory=$true)][string]$Title,
        [Parameter(Mandatory=$true)][string]$RelativePath
    )

    Clear-ConsoleScreen
    Write-BoxTitle -Title $Title
    Write-Host ""

    $batchPath = Resolve-ScriptResourcePath -RelativePath $RelativePath
    if (-not (Test-Path -LiteralPath $batchPath -PathType Leaf)) {
        Write-StatusLine -Ok $false -Text "batch file not found: $batchPath"
        Write-Host ""
        Wait-ForEnterToContinue
        return
    }

    Write-Host "Launching: $batchPath"
    Write-Host ""

    $workingDirectory = Split-Path -Parent $batchPath
    $exitCode = 0

    Push-Location -LiteralPath $workingDirectory
    try {
        & $batchPath
        $exitCode = $LASTEXITCODE
    }
    catch {
        Write-StatusLine -Ok $false -Text $_.Exception.Message
        Write-Host ""
        Wait-ForEnterToContinue
        return
    }
    finally {
        Pop-Location
    }

    Write-Host ""
    if ($exitCode -eq 0) {
        Write-StatusLine -Ok $true -Text "$Title completed"
        Write-Host ""
        Write-Host "OVERALL: SUCCESS" -ForegroundColor Green
    } else {
        Write-StatusLine -Ok $false -Text "$Title exited with code $exitCode"
        Write-Host ""
        Write-Host "OVERALL: FAILED" -ForegroundColor Red
    }

    Write-Host ""
    Wait-ForEnterToContinue
}

function Format-ProcessArgument {
    param([Parameter(Mandatory=$true)][string]$Argument)

    if ($Argument -match '[\s"]') {
        return ('"' + ($Argument -replace '"', '\"') + '"')
    }

    return $Argument
}

function Invoke-ExternalExecutableLauncher {
    param(
        [Parameter(Mandatory=$true)][string]$Title,
        [Parameter(Mandatory=$true)][string]$RelativePath,
        [string[]]$Arguments = @(),
        [string[]]$RelativeArgumentPaths = @(),
        [switch]$WaitForExit
    )

    Clear-ConsoleScreen
    Write-BoxTitle -Title $Title
    Write-Host ""

    $exePath = Resolve-ScriptResourcePath -RelativePath $RelativePath
    if (-not (Test-Path -LiteralPath $exePath -PathType Leaf)) {
        Write-StatusLine -Ok $false -Text "executable not found: $exePath"
        Write-Host ""
        Wait-ForEnterToContinue
        return
    }

    $resolvedArguments = @()

    foreach ($argument in $Arguments) {
        if (-not [string]::IsNullOrWhiteSpace($argument)) {
            $resolvedArguments += $argument
        }
    }

    foreach ($relativeArgumentPath in $RelativeArgumentPaths) {
        if ([string]::IsNullOrWhiteSpace($relativeArgumentPath)) {
            continue
        }

        $argumentPath = Resolve-ScriptResourcePath -RelativePath $relativeArgumentPath
        if (-not (Test-Path -LiteralPath $argumentPath -PathType Leaf)) {
            Write-StatusLine -Ok $false -Text "argument file not found: $argumentPath"
            Write-Host ""
            Wait-ForEnterToContinue
            return
        }

        $resolvedArguments += $argumentPath
    }

    Write-Host "Launching: $exePath"
    if ($resolvedArguments.Count -gt 0) {
        Write-Host ("Arguments: {0}" -f ($resolvedArguments -join ' '))
    }
    Write-Host ""

    $workingDirectory = Split-Path -Parent $exePath
    $startArguments = @{}
    $startArguments['FilePath'] = $exePath
    $startArguments['WorkingDirectory'] = $workingDirectory
    $startArguments['ErrorAction'] = 'Stop'

    if ($resolvedArguments.Count -gt 0) {
        $startArguments['ArgumentList'] = @($resolvedArguments | ForEach-Object { Format-ProcessArgument -Argument $_ })
    }

    if ($WaitForExit) {
        $startArguments['Wait'] = $true
        $startArguments['PassThru'] = $true
    }

    try {
        $process = Start-Process @startArguments
    }
    catch {
        Write-StatusLine -Ok $false -Text $_.Exception.Message
        Write-Host ""
        Wait-ForEnterToContinue
        return
    }

    Write-Host ""
    if ($WaitForExit) {
        if ($process.ExitCode -eq 0) {
            Write-StatusLine -Ok $true -Text "$Title completed"
            Write-Host ""
            Write-Host "OVERALL: SUCCESS" -ForegroundColor Green
        } else {
            Write-StatusLine -Ok $false -Text "$Title exited with code $($process.ExitCode)"
            Write-Host ""
            Write-Host "OVERALL: FAILED" -ForegroundColor Red
        }
    } else {
        Write-StatusLine -Ok $true -Text "$Title completed"
        Write-Host ""
        Write-Host "OVERALL: SUCCESS" -ForegroundColor Green
    }

    Write-Host ""
    Wait-ForEnterToContinue
}

function Format-DownloadByteSize {
    param([Parameter(Mandatory=$true)][Int64]$Bytes)

    $units = @('B', 'KB', 'MB', 'GB', 'TB')
    $value = [double]$Bytes
    $unitIndex = 0

    while (($value -ge 1024) -and ($unitIndex -lt ($units.Count - 1))) {
        $value = $value / 1024
        $unitIndex++
    }

    if ($unitIndex -eq 0) {
        return ('{0:N0} {1}' -f $value, $units[$unitIndex])
    }

    return ('{0:N2} {1}' -f $value, $units[$unitIndex])
}

function Get-UniqueDownloadPath {
    param([Parameter(Mandatory=$true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $Path
    }

    $directory = Split-Path -Parent $Path
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    $extension = [System.IO.Path]::GetExtension($Path)

    for ($i = 1; $i -lt 10000; $i++) {
        $candidate = Join-Path $directory ('{0} ({1}){2}' -f $baseName, $i, $extension)
        if (-not (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }

    throw "Could not create a unique download path for: $Path"
}

function Format-DownloadPercent {
    param([Parameter(Mandatory=$true)][double]$Percent)

    $boundedPercent = [Math]::Min(100.0, [Math]::Max(0.0, $Percent))
    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    return ($boundedPercent.ToString('0.00', $culture).PadLeft(6) + '%')
}

function New-DownloadProgressBar {
    param(
        [Parameter(Mandatory=$true)][double]$Percent,
        [Parameter(Mandatory=$true)][int]$Width
    )

    $boundedPercent = [Math]::Min(100.0, [Math]::Max(0.0, $Percent))
    if ($Width -lt 1) { return '' }

    $filledCells = [int][Math]::Round(($boundedPercent / 100.0) * [double]$Width)
    if ($filledCells -lt 0) { $filledCells = 0 }
    if ($filledCells -gt $Width) { $filledCells = $Width }

    $emptyCells = $Width - $filledCells
    return (('=' * $filledCells) + ('-' * $emptyCells))
}

function New-DownloadProgressState {
    return @{
        LastBytes = [Int64]0
        LastTicks = [System.Diagnostics.Stopwatch]::GetTimestamp()
        SpeedBytesPerSecond = [double]0
        LastProgressLine = ''
        LastProgressWidth = 0
    }
}

function Write-ConsoleProgressLine {
    param(
        [Parameter(Mandatory=$true)][string]$Line,
        [Parameter(Mandatory=$true)][int]$Top,
        [Parameter(Mandatory=$true)][int]$ConsoleWidth,
        [Parameter(Mandatory=$true)][hashtable]$State
    )

    if ($ConsoleWidth -lt 1) { return }
    if ($Line.Length -gt $ConsoleWidth) {
        $Line = $Line.Substring(0, $ConsoleWidth)
    }

    try {
        $previousLine = [string]$State.LastProgressLine
        $previousWidth = [int]$State.LastProgressWidth

        if ($previousWidth -ne $ConsoleWidth) {
            [Console]::SetCursorPosition(0, $Top)
            [Console]::Write((' ' * $ConsoleWidth))
            $previousLine = ''
        }

        $writeLength = [Math]::Max($Line.Length, $previousLine.Length)
        if ($writeLength -gt $ConsoleWidth) { $writeLength = $ConsoleWidth }

        $newLine = $Line.PadRight($writeLength)
        $oldLine = $previousLine.PadRight($writeLength)

        $index = 0
        while ($index -lt $writeLength) {
            if ($newLine[$index] -eq $oldLine[$index]) {
                $index++
                continue
            }

            $startIndex = $index
            while (($index -lt $writeLength) -and ($newLine[$index] -ne $oldLine[$index])) {
                $index++
            }

            [Console]::SetCursorPosition($startIndex, $Top)
            [Console]::Write($newLine.Substring($startIndex, $index - $startIndex))
        }

        $State.LastProgressLine = $Line
        $State.LastProgressWidth = $ConsoleWidth
    } catch {
        Write-Host $Line
    }
}

function Write-DownloadProgressLine {
    param(
        [Parameter(Mandatory=$true)][Int64]$DownloadedBytes,
        [Parameter(Mandatory=$true)][Int64]$TotalBytes,
        [Parameter(Mandatory=$true)][datetime]$StartTime,
        [Parameter(Mandatory=$true)][int]$Top,
        [Parameter(Mandatory=$true)][hashtable]$State
    )

    $nowTicks = [System.Diagnostics.Stopwatch]::GetTimestamp()
    $ticksPerSecond = [double][System.Diagnostics.Stopwatch]::Frequency
    $deltaSeconds = ([double]($nowTicks - [Int64]$State.LastTicks)) / $ticksPerSecond
    $deltaBytes = $DownloadedBytes - [Int64]$State.LastBytes

    if (($deltaSeconds -gt 0) -and ($deltaBytes -ge 0)) {
        $State.SpeedBytesPerSecond = [Math]::Max(0.0, [double]$deltaBytes / $deltaSeconds)
        $State.LastBytes = $DownloadedBytes
        $State.LastTicks = $nowTicks
    }

    $speedText = (Format-DownloadByteSize -Bytes ([Int64][Math]::Round([double]$State.SpeedBytesPerSecond))) + '/s'
    $downloadedText = ('{0:N0} bytes' -f $DownloadedBytes)

    try {
        $consoleWidth = [Math]::Max(40, [Console]::BufferWidth - 1)
    } catch {
        $consoleWidth = 120
    }

    if ($TotalBytes -gt 0) {
        $percent = [Math]::Min(100.0, ([double]$DownloadedBytes / [double]$TotalBytes) * 100.0)
        $percentText = Format-DownloadPercent -Percent $percent
        $totalText = ('{0:N0} bytes' -f $TotalBytes)
        $fixedWidth = $percentText.Length + $downloadedText.Length + $totalText.Length + $speedText.Length + 10
        $barWidth = [Math]::Min(80, [Math]::Max(12, $consoleWidth - $fixedWidth))
        $bar = New-DownloadProgressBar -Percent $percent -Width $barWidth
        $line = ('{0} [{1}] {2} / {3} | {4}' -f $percentText, $bar, $downloadedText, $totalText, $speedText)
    } else {
        $spinnerChars = @('|', '/', '-', '\')
        $spinnerIndex = [int]($DownloadedBytes % $spinnerChars.Count)
        $barWidth = [Math]::Min(80, [Math]::Max(12, $consoleWidth - ($downloadedText.Length + $speedText.Length + 29)))
        $bar = ($spinnerChars[$spinnerIndex] * $barWidth)
        $line = ('unknown [{0}] {1} / unknown total | {2}' -f $bar, $downloadedText, $speedText)
    }

    Write-ConsoleProgressLine -Line $line -Top $Top -ConsoleWidth $consoleWidth -State $State
}

function New-DriverDownloadRequest {
    param(
        [Parameter(Mandatory=$true)][string]$Url,
        [ValidateSet('GET','HEAD')][string]$Method = 'GET',
        [string]$Referer = '',
        [System.Net.CookieContainer]$CookieContainer = $null
    )

    $request = [System.Net.HttpWebRequest]::Create($Url)
    $request.Method = $Method
    $request.AllowAutoRedirect = $true
    $request.MaximumAutomaticRedirections = 10
    $request.KeepAlive = $true
    if ($CookieContainer -ne $null) {
        $request.CookieContainer = $CookieContainer
    }
    if (-not [string]::IsNullOrWhiteSpace($Referer)) {
        $request.Referer = $Referer
    }
    $request.UserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/124.0 Safari/537.36'
    $request.Accept = '*/*'
    try { $request.Headers['Accept-Language'] = 'en-US,en;q=0.9' } catch { }
    try { $request.Headers['Accept-Encoding'] = 'identity' } catch { }
    try { $request.AutomaticDecompression = [System.Net.DecompressionMethods]::None } catch { }
    $request.Timeout = 30000
    $request.ReadWriteTimeout = 30000
    return $request
}

function Get-DriverDownloadHeaderInt64 {
    param(
        [Parameter(Mandatory=$true)][System.Collections.Specialized.NameValueCollection]$Headers,
        [Parameter(Mandatory=$true)][string]$Name
    )

    try {
        $raw = [string]$Headers[$Name]
        if ([string]::IsNullOrWhiteSpace($raw)) { return [Int64]-1 }

        $firstValue = (($raw -split ',')[0]).Trim()
        $parsedValue = [Int64]0
        if ([Int64]::TryParse($firstValue, [ref]$parsedValue)) {
            return $parsedValue
        }
    } catch { }

    return [Int64]-1
}

function Get-DriverDownloadResponseContentLength {
    param([Parameter(Mandatory=$true)][System.Net.WebResponse]$Response)

    try {
        $contentRange = [string]$Response.Headers['Content-Range']
        if ($contentRange -match '/(?<total>[0-9]+)\s*$') {
            return [Int64]$Matches['total']
        }
    } catch { }

    foreach ($headerName in @('Content-Length', 'x-ms-blob-content-length', 'X-Original-Content-Length')) {
        try {
            $headerLength = Get-DriverDownloadHeaderInt64 -Headers $Response.Headers -Name $headerName
            if ($headerLength -gt 0) { return $headerLength }
        } catch { }
    }

    try {
        $length = [Int64]$Response.ContentLength
        if ($length -gt 0) { return $length }
    } catch { }

    return [Int64]-1
}

function Test-DriverDownloadResponseLooksLikeHtml {
    param([Parameter(Mandatory=$true)][System.Net.WebResponse]$Response)

    $responseUri = ''
    try { $responseUri = [string]$Response.ResponseUri.AbsoluteUri } catch { }
    if ($responseUri -match 'Download-Incomplete\.html') { return $true }

    $contentType = ''
    try { $contentType = [string]$Response.ContentType } catch { }
    if ($contentType -match 'text/html|application/xhtml') { return $true }

    return $false
}

function Assert-DriverDownloadResponseIsInstaller {
    param(
        [Parameter(Mandatory=$true)][System.Net.WebResponse]$Response,
        [Parameter(Mandatory=$true)][string]$FileName
    )

    if (Test-DriverDownloadResponseLooksLikeHtml -Response $Response) {
        $finalUrl = ''
        try { $finalUrl = [string]$Response.ResponseUri.AbsoluteUri } catch { }
        if ([string]::IsNullOrWhiteSpace($finalUrl)) { $finalUrl = 'unknown final URL' }
        throw "Server returned an HTML page instead of $FileName. Final URL: $finalUrl"
    }
}

function Invoke-DriverDownloadPrimer {
    param(
        [Parameter(Mandatory=$true)][string]$Url,
        [System.Net.CookieContainer]$CookieContainer = $null
    )

    $response = $null
    $stream = $null
    try {
        $request = New-DriverDownloadRequest -Url $Url -Method 'GET' -CookieContainer $CookieContainer
        $response = $request.GetResponse()
        $stream = $response.GetResponseStream()
        $buffer = New-Object byte[] 4096
        [void]$stream.Read($buffer, 0, $buffer.Length)
    } catch { }
    finally {
        try { if ($stream -ne $null) { $stream.Close() } } catch { }
        try { if ($response -ne $null) { $response.Close() } } catch { }
    }
}

function Get-DriverDownloadContentLength {
    param(
        [Parameter(Mandatory=$true)][string]$Url,
        [string]$Referer = '',
        [System.Net.CookieContainer]$CookieContainer = $null
    )

    $response = $null
    try {
        $request = New-DriverDownloadRequest -Url $Url -Method 'HEAD' -Referer $Referer -CookieContainer $CookieContainer
        $response = $request.GetResponse()
        if (-not (Test-DriverDownloadResponseLooksLikeHtml -Response $response)) {
            $length = Get-DriverDownloadResponseContentLength -Response $response
            if ($length -gt 0) {
                return $length
            }
        }
    } catch { }
    finally {
        try { if ($response -ne $null) { $response.Close() } } catch { }
    }

    $response = $null
    try {
        $request = New-DriverDownloadRequest -Url $Url -Method 'GET' -Referer $Referer -CookieContainer $CookieContainer
        try { $request.AddRange(0, 0) } catch { }
        $response = $request.GetResponse()

        if (-not (Test-DriverDownloadResponseLooksLikeHtml -Response $response)) {
            $contentRange = [string]$response.Headers['Content-Range']
            if ($contentRange -match '/(?<total>[0-9]+)\s*$') {
                return [Int64]$Matches['total']
            }

            $length = Get-DriverDownloadResponseContentLength -Response $response
            $statusCode = 0
            try { $statusCode = [int]$response.StatusCode } catch { }

            if (($length -gt 1) -and ($statusCode -ne 206)) {
                return $length
            }
        }
    } catch { }
    finally {
        try { if ($response -ne $null) { $response.Close() } } catch { }
    }

    return [Int64]-1
}

function Invoke-NvidiaDriverDownload {
    param(
        [Parameter(Mandatory=$true)][string]$Title,
        [Parameter(Mandatory=$true)][string]$Url,
        [Parameter(Mandatory=$true)][string]$FileName,
        [switch]$ProbeContentLength,
        [string]$Referer = ''
    )

    Clear-ConsoleScreen
    Write-BoxTitle -Title $Title
    Write-Host ""

    $downloadDirectory = Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads'
    if (-not (Test-Path -LiteralPath $downloadDirectory -PathType Container)) {
        New-Item -Path $downloadDirectory -ItemType Directory -Force | Out-Null
    }

    $targetPath = Get-UniqueDownloadPath -Path (Join-Path $downloadDirectory $FileName)
    $partialPath = $targetPath + '.partial'

    Write-Host "URL: $Url"
    Write-Host "Saving to: $targetPath"
    Write-Host ""
    Write-Host "Download starts automatically."
    Write-Host ""

    $oldCursorVisible = $true
    try { $oldCursorVisible = [Console]::CursorVisible } catch { }

    $response = $null
    $inputStream = $null
    $outputStream = $null

    try {
        try { [Console]::CursorVisible = $false } catch { }
        try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }

        $cookieContainer = New-Object System.Net.CookieContainer
        if (-not [string]::IsNullOrWhiteSpace($Referer)) {
            Invoke-DriverDownloadPrimer -Url $Referer -CookieContainer $cookieContainer
        }

        $totalBytesHint = [Int64]-1
        if ($ProbeContentLength) {
            $totalBytesHint = Get-DriverDownloadContentLength -Url $Url -Referer $Referer -CookieContainer $cookieContainer
        }

        $request = New-DriverDownloadRequest -Url $Url -Method 'GET' -Referer $Referer -CookieContainer $cookieContainer

        $response = $request.GetResponse()
        Assert-DriverDownloadResponseIsInstaller -Response $response -FileName $FileName
        $totalBytes = Get-DriverDownloadResponseContentLength -Response $response
        if (($totalBytes -le 0) -and ($totalBytesHint -gt 0)) {
            $totalBytes = $totalBytesHint
        }
        $inputStream = $response.GetResponseStream()
        $outputStream = [System.IO.File]::Open($partialPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)

        $buffer = New-Object byte[] 65536
        $downloadedBytes = [Int64]0
        $startTime = Get-Date
        $progressState = New-DownloadProgressState
        $progressTop = [Console]::CursorTop
        $progressIntervalTicks = [Int64]([System.Diagnostics.Stopwatch]::Frequency / 10)
        if ($progressIntervalTicks -lt 1) { $progressIntervalTicks = [Int64]1 }
        $nextProgressTicks = [System.Diagnostics.Stopwatch]::GetTimestamp()

        Write-DownloadProgressLine -DownloadedBytes $downloadedBytes -TotalBytes $totalBytes -StartTime $startTime -Top $progressTop -State $progressState

        while ($true) {
            $bytesRead = $inputStream.Read($buffer, 0, $buffer.Length)
            if ($bytesRead -le 0) {
                break
            }

            $outputStream.Write($buffer, 0, $bytesRead)
            $downloadedBytes += [Int64]$bytesRead

            $nowTicks = [System.Diagnostics.Stopwatch]::GetTimestamp()
            if ($nowTicks -ge $nextProgressTicks) {
                Write-DownloadProgressLine -DownloadedBytes $downloadedBytes -TotalBytes $totalBytes -StartTime $startTime -Top $progressTop -State $progressState
                $nextProgressTicks = $nowTicks + $progressIntervalTicks
            }
        }

        Write-DownloadProgressLine -DownloadedBytes $downloadedBytes -TotalBytes $totalBytes -StartTime $startTime -Top $progressTop -State $progressState

        $outputStream.Flush()
        $outputStream.Close()
        $outputStream = $null

        Assert-LlcDownloadLength -DownloadedBytes $downloadedBytes -TotalBytes $totalBytes
        if ($totalBytes -lt 0) {
            Write-Host 'WARNING: server did not supply a size; completeness could not be verified.' -ForegroundColor Yellow
        }
        Write-Host 'Size checks do not verify the publisher. Verify the installer signature before running it.' -ForegroundColor Yellow
        if (Test-Path -LiteralPath $targetPath) {
            Remove-Item -LiteralPath $targetPath -Force
        }
        Move-Item -LiteralPath $partialPath -Destination $targetPath -Force

        try { [Console]::SetCursorPosition(0, $progressTop + 1) } catch { Write-Host "" }
        Write-Host ""
        Write-StatusLine -Ok $true -Text "download completed: $targetPath"
        Write-Host ""
        Write-Host "OVERALL: SUCCESS" -ForegroundColor Green
    }
    catch {
        try { if ($outputStream -ne $null) { $outputStream.Close() } } catch { }
        try { if (Test-Path -LiteralPath $partialPath) { Remove-Item -LiteralPath $partialPath -Force } } catch { }
        Write-Host ""
        Write-StatusLine -Ok $false -Text $_.Exception.Message
        Write-Host ""
        Write-Host "OVERALL: FAILED" -ForegroundColor Red
    }
    finally {
        try { if ($inputStream -ne $null) { $inputStream.Close() } } catch { }
        try { if ($response -ne $null) { $response.Close() } } catch { }
        try { [Console]::CursorVisible = $oldCursorVisible } catch { }
    }

    Write-Host ""
    Wait-ForEnterToContinue
}


$gameConfigKey = 'HKCU\System\GameConfigStore'
$gameDvrKey = 'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR'
$gameDvrPolicyKey = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\GameDVR'
$gameBarKey = 'HKCU\SOFTWARE\Microsoft\GameBar'

$gameBarDisable = @(
    [pscustomobject]@{ Key=$gameDvrPolicyKey; Name='AllowGameDVR';              Value=0; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gameDvrKey;       Name='AppCaptureEnabled';         Value=0; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gameDvrKey;       Name='AudioCaptureEnabled';       Value=0; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gameDvrKey;       Name='MicrophoneCaptureEnabled';  Value=0; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gameDvrKey;       Name='CursorCaptureEnabled';      Value=0; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gameDvrKey;       Name='HistoricalCaptureEnabled';  Value=0; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gameConfigKey;    Name='GameDVR_Enabled';           Value=0; Type='DWord'; CreateKey=$true }
)

$gameBarEnable = @(
    [pscustomobject]@{ Key=$gameDvrPolicyKey; Name='AllowGameDVR';              Value=1; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gameDvrKey;       Name='AppCaptureEnabled';         Value=1; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gameDvrKey;       Name='AudioCaptureEnabled';       Value=1; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gameDvrKey;       Name='MicrophoneCaptureEnabled';  Value=1; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gameDvrKey;       Name='CursorCaptureEnabled';      Value=1; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gameDvrKey;       Name='HistoricalCaptureEnabled';  Value=1; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gameConfigKey;    Name='GameDVR_Enabled';           Value=1; Type='DWord'; CreateKey=$true }
)

$gameModeDisable = @(
    [pscustomobject]@{ Key=$gameBarKey; Name='AllowAutoGameMode';  Value=0; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gameBarKey; Name='AutoGameModeEnabled'; Value=0; Type='DWord'; CreateKey=$true }
)

$gameModeEnable = @(
    [pscustomobject]@{ Key=$gameBarKey; Name='AllowAutoGameMode';  Value=1; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gameBarKey; Name='AutoGameModeEnabled'; Value=1; Type='DWord'; CreateKey=$true }
)

$clockInterruptsCore0 = @(
    [pscustomobject]@{ Key='HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel'; Name='SerializeTimerExpiration'; Value=1; Type='DWord'; CreateKey=$true }
)

$win32PrioritySeparation18Hex = @(
    [pscustomobject]@{ Key='HKLM\SYSTEM\CurrentControlSet\Control\PriorityControl'; Name='Win32PrioritySeparation'; Value='0x18'; Type='DWord'; CreateKey=$true }
)

$mouseAccelerationKey = 'HKCU\Control Panel\Mouse'

$mouseAccelerationDisable = @(
    [pscustomobject]@{ Key=$mouseAccelerationKey; Name='MouseSpeed';      Value='0'; Type='String'; CreateKey=$true },
    [pscustomobject]@{ Key=$mouseAccelerationKey; Name='MouseThreshold1'; Value='0'; Type='String'; CreateKey=$true },
    [pscustomobject]@{ Key=$mouseAccelerationKey; Name='MouseThreshold2'; Value='0'; Type='String'; CreateKey=$true }
)


$uacSystemKey = 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'

$uacDisable = @(
    [pscustomobject]@{ Key=$uacSystemKey; Name='EnableLUA';                  Value=0; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$uacSystemKey; Name='ConsentPromptBehaviorAdmin'; Value=0; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$uacSystemKey; Name='ConsentPromptBehaviorUser';  Value=0; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$uacSystemKey; Name='PromptOnSecureDesktop';      Value=0; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$uacSystemKey; Name='EnableInstallerDetection';   Value=0; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$uacSystemKey; Name='EnableVirtualization';       Value=0; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$uacSystemKey; Name='FilterAdministratorToken';   Value=0; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$uacSystemKey; Name='EnableUIADesktopToggle';     Value=0; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$uacSystemKey; Name='ValidateAdminCodeSignatures'; Value=0; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$uacSystemKey; Name='EnableSecureUIAPaths';       Value=0; Type='DWord'; CreateKey=$true }
)

$uacEnable = @(
    [pscustomobject]@{ Key=$uacSystemKey; Name='EnableLUA';                  Value=1; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$uacSystemKey; Name='ConsentPromptBehaviorAdmin'; Value=5; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$uacSystemKey; Name='ConsentPromptBehaviorUser';  Value=3; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$uacSystemKey; Name='PromptOnSecureDesktop';      Value=1; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$uacSystemKey; Name='EnableInstallerDetection';   Value=1; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$uacSystemKey; Name='EnableVirtualization';       Value=1; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$uacSystemKey; Name='FilterAdministratorToken';   Value=0; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$uacSystemKey; Name='EnableUIADesktopToggle';     Value=0; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$uacSystemKey; Name='ValidateAdminCodeSignatures'; Value=0; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$uacSystemKey; Name='EnableSecureUIAPaths';       Value=1; Type='DWord'; CreateKey=$true }
)

$notificationCurrentUserPushKey = 'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\PushNotifications'
$notificationCurrentUserSettingsKey = 'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings'
$notificationUserPushPolicyKey = 'HKCU\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\PushNotifications'
$notificationMachinePushPolicyKey = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\PushNotifications'
$notificationUserExplorerPolicyKey = 'HKCU\SOFTWARE\Policies\Microsoft\Windows\Explorer'
$notificationMachineExplorerPolicyKey = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Explorer'
$notificationCurrentUserExplorerPolicyKey = 'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'
$notificationWindowsSecurityPolicyKey = 'HKLM\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Notifications'
$notificationAccountPolicyKey = 'HKCU\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\AccountNotifications'

$notificationsDisable = @(
    [pscustomobject]@{ Key=$notificationCurrentUserPushKey;           Name='ToastEnabled';                                  Value=0; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$notificationCurrentUserSettingsKey;       Name='NOC_GLOBAL_SETTING_TOASTS_ENABLED';            Value=0; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$notificationUserPushPolicyKey;            Name='NoToastApplicationNotification';               Value=1; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$notificationMachinePushPolicyKey;         Name='NoToastApplicationNotification';               Value=1; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$notificationUserPushPolicyKey;            Name='NoToastApplicationNotificationOnLockScreen';   Value=1; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$notificationUserPushPolicyKey;            Name='NoTileApplicationNotification';                Value=1; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$notificationUserPushPolicyKey;            Name='DisallowNotificationMirroring';                Value=1; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$notificationMachinePushPolicyKey;         Name='NoCloudApplicationNotification';               Value=1; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$notificationUserExplorerPolicyKey;        Name='DisableNotificationCenter';                    Value=1; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$notificationMachineExplorerPolicyKey;     Name='DisableNotificationCenter';                    Value=1; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$notificationCurrentUserExplorerPolicyKey; Name='TaskbarNoNotification';                        Value=1; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$notificationWindowsSecurityPolicyKey;     Name='DisableNotifications';                         Value=1; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$notificationWindowsSecurityPolicyKey;     Name='DisableEnhancedNotifications';                 Value=1; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$notificationAccountPolicyKey;             Name='DisableAccountNotifications';                  Value=1; Type='DWord'; CreateKey=$true }
)

$fsoEnable = @(
    [pscustomobject]@{ Key=$gameConfigKey; Name='GameDVR_DXGIHonorFSEWindowsCompatible'; Value=0; CreateKey=$true },
    [pscustomobject]@{ Key=$gameConfigKey; Name='GameDVR_HonorUserFSEBehaviorMode';      Value=0; CreateKey=$true },
    [pscustomobject]@{ Key=$gameConfigKey; Name='GameDVR_FSEBehaviorMode';               Value=0; CreateKey=$true },
    [pscustomobject]@{ Key=$gameConfigKey; Name='GameDVR_FSEBehavior';                   Value=0; CreateKey=$true },
    [pscustomobject]@{ Key=$gameConfigKey; Name='GameDVR_DSEBehavior';                   Value=0; CreateKey=$true }
)

$fsoDisable = @(
    [pscustomobject]@{ Key=$gameConfigKey; Name='GameDVR_DXGIHonorFSEWindowsCompatible'; Value=1; CreateKey=$true },
    [pscustomobject]@{ Key=$gameConfigKey; Name='GameDVR_HonorUserFSEBehaviorMode';      Value=0; CreateKey=$true },
    [pscustomobject]@{ Key=$gameConfigKey; Name='GameDVR_FSEBehaviorMode';               Value=2; CreateKey=$true },
    [pscustomobject]@{ Key=$gameConfigKey; Name='GameDVR_FSEBehavior';                   Value=2; CreateKey=$true },
    [pscustomobject]@{ Key=$gameConfigKey; Name='GameDVR_DSEBehavior';                   Value=2; CreateKey=$true }
)

$hagsGraphicsDriversKey = 'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'

$hagsEnable = @(
    [pscustomobject]@{ Key=$hagsGraphicsDriversKey; Name='HwSchMode'; Value=2; Type='DWord'; CreateKey=$true }
)

$hagsDisable = @(
    [pscustomobject]@{ Key=$hagsGraphicsDriversKey; Name='HwSchMode'; Value=1; Type='DWord'; CreateKey=$true }
)


$gpuDisplayClassKey = 'HKLM\SYSTEM\ControlSet001\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0000'

$nvidiaGpuOptimize = @(
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RMAERRForceDisable'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RMNoECCFuseCheck'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RMDisableRCOnDBE'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RM1441072'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RMAERRHandling'; Value='0x00000000'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RMChkSuppl200405980Driv'; Value='0x13deed31'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RmDisableACPI'; Value='0x000003FF'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RMDisableGpuASPMFlags'; Value='0x00000003'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RMPowerFeature'; Value='0x54455555'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RMPowerFeature2'; Value='0x05555555'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableDynamicPstate'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RMOPSB'; Value='0x00002AA2'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RmClkPowerOffDramPllWhenUnused'; Value='0x00000000'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RmMIONoPowerOff'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RMClkSlowDown'; Value='0x05400000'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RM2779240'; Value='0x00000005'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RmOverrideIdleSlowdownSettings'; Value='0x00000000'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RmPmgrPwrPolicyOverride'; Value='0x0000000F'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RmPerfCfOverride'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RmRcWatchdog'; Value='0x00000000'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RMHdcpKeyglobZero'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RmThermPolicySwSlowdownOverride'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RmThermPolicyOverride'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RmPerfCfPolicyOverrides'; Value='0x00000003'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='MaxPerfWithPerfMon'; Value='0x00000000'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RM572548'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='PowerMizerEnable'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='PowerMizerLevel'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='PowerMizerLevelAC'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='PowerMizerHardLevel'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='PowerMizerHardLevelAC'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='PowerMizerDefault'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='PowerMizerDefaultAC'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableAsyncPstates'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RmOptp2LowerMclk'; Value='0x00000000'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='VarBusLinkWidth'; Value='0x00000002'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RMDisableOptimalPowerForPadlinkPll'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RMGC6Feature'; Value='0x000aa800'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RMGC6Parameters'; Value='0x0000003f'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RMForceRtd3D3Hot'; Value='0x00000002'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RMElpgStateOnInit'; Value='0x00000003'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RmPgCtrlParameters'; Value='0x15555155'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RmDwbMscg'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RmDisableVblankMscg'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RmLpwrCtrlMsLtcParameters'; Value='0x00000005'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RmLpwrCtrlMsDifrSwAsrParameters'; Value='0x00001555'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RmLpwrCtrlMsDifrCgParameters'; Value='0x00000555'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RmPgCtrlDiParameters'; Value='0x00000015'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RmPgCtrlGrParameters'; Value='0x55555554'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RmLpwrCtrlGrRgParameters'; Value='0x05455555'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RMIntrDetailedLogs'; Value='0x00000000'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RMNvTelemetryCollection'; Value='0x00000000'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RMNvTelemetryTest'; Value='0x00000000'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RMNvLog'; Value='0x00000000'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RMPcieLtrOverride'; Value='0x00008005'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RmFbhubRelaxedOrderingOverride'; Value='0x000004D5'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RmEnableRmTaskWatchcat'; Value='0x00000000'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RmGlobalPoisonOverride'; Value='0x00000002'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RmDisableGlobalCeUtils'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RMDiWakeupTimer'; Value='0x80000000'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RMOnDemandVBlank'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DP2X_IGNORE_CABLE_ID_CAPS'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='EnableRS2FlipCollapse'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='EnableRS2ImmediateFlipCompletionReporting'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RMNoECCFBScrub'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RMDisableScrubOnFree'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RMDisableAsyncMemScrub'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RMDisableFastScrubber'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RMUcodeEncryption'; Value='0x00015555'; Type='DWord'; CreateKey=$true }
)

$nvidiaGpuRevert = @(
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RMAERRForceDisable'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RMNoECCFuseCheck'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RMDisableRCOnDBE'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RM1441072'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RMAERRHandling'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RMChkSuppl200405980Driv'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RmDisableACPI'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RMDisableGpuASPMFlags'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RMPowerFeature'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RMPowerFeature2'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableDynamicPstate'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RMOPSB'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RmClkPowerOffDramPllWhenUnused'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RmMIONoPowerOff'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RMClkSlowDown'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RM2779240'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RmOverrideIdleSlowdownSettings'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RmPmgrPwrPolicyOverride'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RmPerfCfOverride'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RmRcWatchdog'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RMHdcpKeyglobZero'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RmThermPolicySwSlowdownOverride'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RmThermPolicyOverride'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RmPerfCfPolicyOverrides'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='MaxPerfWithPerfMon'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RM572548'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='PowerMizerEnable'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='PowerMizerLevel'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='PowerMizerLevelAC'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='PowerMizerHardLevel'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='PowerMizerHardLevelAC'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='PowerMizerDefault'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='PowerMizerDefaultAC'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableAsyncPstates'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RmOptp2LowerMclk'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='VarBusLinkWidth'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RMDisableOptimalPowerForPadlinkPll'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RMGC6Feature'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RMGC6Parameters'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RMForceRtd3D3Hot'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RMElpgStateOnInit'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RmPgCtrlParameters'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RmDwbMscg'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RmDisableVblankMscg'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RmLpwrCtrlMsLtcParameters'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RmLpwrCtrlMsDifrSwAsrParameters'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RmLpwrCtrlMsDifrCgParameters'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RmPgCtrlDiParameters'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RmPgCtrlGrParameters'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RmLpwrCtrlGrRgParameters'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RMIntrDetailedLogs'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RMNvTelemetryCollection'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RMNvTelemetryTest'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RMNvLog'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RMPcieLtrOverride'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RmFbhubRelaxedOrderingOverride'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RmEnableRmTaskWatchcat'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RmGlobalPoisonOverride'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RmDisableGlobalCeUtils'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RMDiWakeupTimer'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RMOnDemandVBlank'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DP2X_IGNORE_CABLE_ID_CAPS'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='EnableRS2FlipCollapse'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='EnableRS2ImmediateFlipCompletionReporting'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RMNoECCFBScrub'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RMDisableScrubOnFree'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RMDisableAsyncMemScrub'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RMDisableFastScrubber'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='RMUcodeEncryption'; Type='DeleteValue' }
)

$amdGpuOptimize = @(
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DalDisableClockGating'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableAcpPowerGating'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableCpPowerGating'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableDrmdmaPowerGating'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableDynamicGfxMGPowerGating'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableUVDPowerGatingDynamic'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableAllClockGating'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableGDSPowerGating'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableGfxCGPowerGating'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableGfxClockGating'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableGfxCoarseGrainClockGating'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableGfxMediumGrainClockGating'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableGFXPipelinePowerGating'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableGmcPowerGating'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableHdpClockPowerGating'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableHdpMGClockGating'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableMcMediumGrainClockGating'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableNbioMediumGrainClockGating'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisablePowerGating'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableQuickGfxMGPowerGating'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableRomMediumGrainClockGating'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableRomMGCGClockGating'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableSamuClockGating'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableSAMUPowerGating'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableStaticGfxMGPowerGating'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableSysClockGating'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableUVDPowerGating'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableVceClockGating'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableVCEPowerGating'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableXdmaPowerGating'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableXdmaSclkGating'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='PP_DisableThermalManagement'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='EnableUlps'; Value='0x00000000'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableSdmaMGCG'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableSdmaMGLS'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DalDisableDSC'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DalDisableFEC'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DalDisableIdlePowerOptimizations'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableGfxCpLightSleep'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableGfxRlcLightSleep'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableHdpLightSleep'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableMcMGCG'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='PP_GPUPowerDownEnabled'; Value='0x00000000'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableMcLightSleep'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableBifLightSleep'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableBifMGCG'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableDrmLightSleep'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableGfxCoarseGrainLightSleep'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableGfxMediumGrainLightSleep'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableNbioMediumGrainLightSleep'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableXdmaLightSleep'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableVceLightSleep'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='EnableVcePllSpreadSpectrum'; Value='0x00000000'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='EnableSpreadSpectrum'; Value='0x00000000'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='ECCMode'; Value='0x00000000'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='EnableDfDramScrub'; Value='0x00000000'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='KMD_EnableContextBasedPowerManagement'; Value='0x00000000'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableAspmL0s'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableAspmL1'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableAspmSWL1'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='KMD_EnableMSHWS'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='KMD_EnableHWS'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='EnableGfxClockGatingThruSmu'; Value='0x00000000'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='EnableSysClockGatingThruSmu'; Value='0x00000000'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableDrmdmaMGCG'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableDrmMGCG'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableGfxCGTS'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableGfxCGTS_LS'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableGfxMGCGPerfMon'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='KMD_RTPMEnabled'; Value='0x00000000'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='KMD_EnableUvdRTPM'; Value='0x00000000'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='KMD_EnableVcnRTPM'; Value='0x00000000'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='KMD_EnableVpeRTPM'; Value='0x00000000'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='PP_EnableHardwareThermalProtection'; Value='0x00000000'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DalEnableFreesyncPowerOptimization'; Value='0x00000000'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DalPSRPowerOpt'; Value='0x00000000'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DalReplayPowerOpt'; Value='0x00000000'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DalMemLowPowerSupport'; Value='0x00000000'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DalDisableMemLowPower'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DalDisableIPS'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DalDisableIPSInVideoPlayBack'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DalDisableDppPG'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DalDisableHubpPG'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DalDisableMpcOtgPG'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DalDisableDscPG'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='EnableUvdClockGating'; Value='0x00000000'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='EnableVceSwClockGating'; Value='0x00000000'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='EnableCoolerMasterRGB'; Value='0x00000000'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='IRQMgrDisableIHClockGating'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='KmdEnableHwFlipQueue'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='KMD_EnableHWSHighPriorityQueue'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='KMD_EnableInternalLargePage'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='KMD_EnableLargePageSupport'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='PP_EnableULV'; Value='0x00000000'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='PP_DisableULV'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DalDisableDcc'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='PP_ForceHighDPMLevel'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DalDisableZ10'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableClkReqSupport'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='KMD_EnableUTCL1LargePage'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='KMD_EnableAllSDMAEngines=1'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisablePllOffInL1'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='EnablePllOffInL1'; Value='0x00000000'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DalDisableStutter'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableLTR'; Value='0x00000000'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='BGM_EnableLTR'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableLTREnforcement'; Value='0x00000000'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableLTRNoSnoopRequirement'; Value='0x00000000'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableLTRSnoopRequirement'; Value='0x00000000'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableLTRStrap'; Value='0x00000000'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='BGM_LTRWithSnoop'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='BGM_LTRWithNoSnoop'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='BGM_LTRMaxSnoopLatencyScale'; Value='0x00000000'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='BGM_LTRMaxSnoopLatencyValue'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='BGM_LTRMaxNoSnoopLatencyScale'; Value='0x00000000'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='BGM_LTRMaxNoSnoopLatencyValue'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='BGM_LTRSnoopL0Latency'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='BGM_LTRSnoopL1Latency'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='BGM_LTRNoSnoopL0Latency'; Value='0x00000001'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='BGM_LTRNoSnoopL1Latency'; Value='0x00000001'; Type='DWord'; CreateKey=$true }
)

$amdGpuRevert = @(
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DalDisableClockGating'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableAcpPowerGating'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableCpPowerGating'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableDrmdmaPowerGating'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableDynamicGfxMGPowerGating'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableUVDPowerGatingDynamic'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableAllClockGating'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableGDSPowerGating'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableGfxCGPowerGating'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableGfxClockGating'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableGfxCoarseGrainClockGating'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableGfxMediumGrainClockGating'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableGFXPipelinePowerGating'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableGmcPowerGating'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableHdpClockPowerGating'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableHdpMGClockGating'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableMcMediumGrainClockGating'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableNbioMediumGrainClockGating'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisablePowerGating'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableQuickGfxMGPowerGating'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableRomMediumGrainClockGating'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableRomMGCGClockGating'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableSamuClockGating'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableSAMUPowerGating'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableStaticGfxMGPowerGating'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableSysClockGating'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableUVDPowerGating'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableVceClockGating'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableVCEPowerGating'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableXdmaPowerGating'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableXdmaSclkGating'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='PP_DisableThermalManagement'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='EnableUlps'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableSdmaMGCG'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableSdmaMGLS'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DalDisableDSC'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DalDisableFEC'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DalDisableIdlePowerOptimizations'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableGfxCpLightSleep'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableGfxRlcLightSleep'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableHdpLightSleep'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableMcMGCG'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='PP_GPUPowerDownEnabled'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableMcLightSleep'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableBifLightSleep'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableBifMGCG'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableDrmLightSleep'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableGfxCoarseGrainLightSleep'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableGfxMediumGrainLightSleep'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableNbioMediumGrainLightSleep'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableXdmaLightSleep'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableVceLightSleep'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='EnableVcePllSpreadSpectrum'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='EnableSpreadSpectrum'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='BGM_EnableLTR'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='ECCMode'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='EnableDfDramScrub'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='KMD_EnableContextBasedPowerManagement'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableAspmL0s'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableAspmL1'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableAspmSWL1'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='KMD_EnableMSHWS'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='KMD_EnableHWS'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='EnableGfxClockGatingThruSmu'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='EnableSysClockGatingThruSmu'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableDrmdmaMGCG'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableDrmMGCG'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableGfxCGTS'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableGfxCGTS_LS'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableGfxMGCGPerfMon'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='KMD_RTPMEnabled'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='KMD_EnableUvdRTPM'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='KMD_EnableVcnRTPM'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='KMD_EnableVpeRTPM'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='PP_EnableHardwareThermalProtection'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DalEnableFreesyncPowerOptimization'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DalPSRPowerOpt'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DalReplayPowerOpt'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DalMemLowPowerSupport'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DalDisableMemLowPower'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DalDisableIPS'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DalDisableIPSInVideoPlayBack'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DalDisableDppPG'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DalDisableHubpPG'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DalDisableMpcOtgPG'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DalDisableDscPG'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='EnableUvdClockGating'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='EnableVceSwClockGating'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='EnableCoolerMasterRGB'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='IRQMgrDisableIHClockGating'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='KmdEnableHwFlipQueue'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='KMD_EnableHWSHighPriorityQueue'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='KMD_EnableInternalLargePage'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='KMD_EnableLargePageSupport'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='PP_EnableULV'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='PP_DisableULV'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DalDisableDcc'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='PP_ForceHighDPMLevel'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DalDisableZ10'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableClkReqSupport'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='KMD_EnableUTCL1LargePage'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='KMD_EnableAllSDMAEngines=1'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisablePllOffInL1'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='EnablePllOffInL1'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DalDisableStutter'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableLTR'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableLTREnforcement'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableLTRNoSnoopRequirement'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableLTRSnoopRequirement'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='DisableLTRStrap'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='BGM_LTRWithSnoop'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='BGM_LTRWithNoSnoop'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='BGM_LTRMaxSnoopLatencyScale'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='BGM_LTRMaxSnoopLatencyValue'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='BGM_LTRMaxNoSnoopLatencyScale'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='BGM_LTRMaxNoSnoopLatencyValue'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='BGM_LTRSnoopL0Latency'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='BGM_LTRSnoopL1Latency'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='BGM_LTRNoSnoopL0Latency'; Type='DeleteValue' },
    [pscustomobject]@{ Key=$gpuDisplayClassKey; Name='BGM_LTRNoSnoopL1Latency'; Type='DeleteValue' }
)

$servicesToDisable = @(
    'rdpbus',
    'umbus',
    'CompositeBus',
    'vid',
    'vdrvroot',
    'NdisVirtualBus',
    'Themes',
    'Spooler',
    'WSearch',
    'edgeupdate',
    'luafv',
    'RmSvc',
    'SessionEnv',
    'GameInputSvc',
    'MsRPC',
    'bam',
    'amdfendr',
    'AMD Crash Defender Service',
    'AMD External Events Utility'
) | ForEach-Object {
    [pscustomobject]@{ Key="HKLM\SYSTEM\CurrentControlSet\Services\$_"; Name='Start'; Value=4; CreateKey=$false }
}

$serviceDefaults = @(
    [pscustomobject]@{ Service='rdpbus';                      Start=3 },
    [pscustomobject]@{ Service='umbus';                       Start=3 },
    [pscustomobject]@{ Service='CompositeBus';                Start=3 },
    [pscustomobject]@{ Service='vid';                         Start=1 },
    [pscustomobject]@{ Service='vdrvroot';                    Start=0 },
    [pscustomobject]@{ Service='NdisVirtualBus';              Start=3 },
    [pscustomobject]@{ Service='Themes';                      Start=2 },
    [pscustomobject]@{ Service='Spooler';                     Start=2 },
    [pscustomobject]@{ Service='WSearch';                     Start=2 },
    [pscustomobject]@{ Service='edgeupdate';                  Start=2 },
    [pscustomobject]@{ Service='luafv';                       Start=2 },
    [pscustomobject]@{ Service='RmSvc';                       Start=3 },
    [pscustomobject]@{ Service='SessionEnv';                  Start=3 },
    [pscustomobject]@{ Service='GameInputSvc';                Start=3 },
    [pscustomobject]@{ Service='MsRPC';                       Start=3 },
    [pscustomobject]@{ Service='bam';                         Start=1 },
    [pscustomobject]@{ Service='amdfendr';                    Start=3 },
    [pscustomobject]@{ Service='AMD Crash Defender Service';  Start=2 },
    [pscustomobject]@{ Service='AMD External Events Utility'; Start=2 }
)

$servicesToEnable = $serviceDefaults | ForEach-Object {
    [pscustomobject]@{ Key="HKLM\SYSTEM\CurrentControlSet\Services\$($_.Service)"; Name='Start'; Value=$_.Start; CreateKey=$false }
}

$mmcssServiceKey = 'HKLM\SYSTEM\CurrentControlSet\Services\MMCSS'
$mmcssSystemProfileKey = 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
$mmcssAudioTaskKey = 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Audio'
$mmcssProAudioTaskKey = 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Pro Audio'
$mmcssPlaybackTaskKey = 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Playback'

$mmcssEnable = @(
    [pscustomobject]@{ Key=$mmcssServiceKey; Name='Start'; Value=2; Type='DWord'; CreateKey=$false }
)

$mmcssDisable = @(
    [pscustomobject]@{ Key=$mmcssServiceKey; Name='Start'; Value=4; Type='DWord'; CreateKey=$false }
)

$mmcssOptimize = @(
    [pscustomobject]@{ Key=$mmcssSystemProfileKey; Name='NoLazyMode';                 Value=0;            Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$mmcssSystemProfileKey; Name='NetworkThrottlingIndex';     Value=10;           Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$mmcssSystemProfileKey; Name='LazyModeTimeout';            Value='0xffffffff'; Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$mmcssSystemProfileKey; Name='SchedulerPeriod';            Value=1000000;      Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$mmcssSystemProfileKey; Name='IdleDetectionCycles';        Value=1;            Type='DWord'; CreateKey=$true },
    [pscustomobject]@{ Key=$mmcssSystemProfileKey; Name='SchedulerTimerResolution';   Value=10000;        Type='DWord'; CreateKey=$true },

    [pscustomobject]@{ Key=$mmcssAudioTaskKey; Name='Priority';                       Value=1;            Type='DWord';  CreateKey=$true },
    [pscustomobject]@{ Key=$mmcssAudioTaskKey; Name='Scheduling Category';            Value='Medium';     Type='String'; CreateKey=$true },
    [pscustomobject]@{ Key=$mmcssAudioTaskKey; Name='Priority When Yielded';          Value=16;           Type='DWord';  CreateKey=$true },

    [pscustomobject]@{ Key=$mmcssProAudioTaskKey; Name='Priority';                    Value=1;            Type='DWord';  CreateKey=$true },
    [pscustomobject]@{ Key=$mmcssProAudioTaskKey; Name='Scheduling Category';         Value='Medium';     Type='String'; CreateKey=$true },
    [pscustomobject]@{ Key=$mmcssProAudioTaskKey; Name='Priority When Yielded';       Value=16;           Type='DWord';  CreateKey=$true },

    [pscustomobject]@{ Key=$mmcssPlaybackTaskKey; Name='Priority';                    Value=1;            Type='DWord';  CreateKey=$true },
    [pscustomobject]@{ Key=$mmcssPlaybackTaskKey; Name='Scheduling Category';         Value='Medium';     Type='String'; CreateKey=$true },
    [pscustomobject]@{ Key=$mmcssPlaybackTaskKey; Name='Priority When Yielded';       Value=16;           Type='DWord';  CreateKey=$true }
)

$mmcssFixAudioStutters = @(
    [pscustomobject]@{ Key=$mmcssSystemProfileKey; Name='SchedulerTimerResolution';   Value=1;            Type='DWord';  CreateKey=$true },

    [pscustomobject]@{ Key=$mmcssAudioTaskKey; Name='Scheduling Category';            Value='High';       Type='String'; CreateKey=$true },
    [pscustomobject]@{ Key=$mmcssAudioTaskKey; Name='Priority When Yielded';          Value=19;           Type='DWord';  CreateKey=$true },

    [pscustomobject]@{ Key=$mmcssProAudioTaskKey; Name='Scheduling Category';         Value='High';       Type='String'; CreateKey=$true },
    [pscustomobject]@{ Key=$mmcssProAudioTaskKey; Name='Priority When Yielded';       Value=19;           Type='DWord';  CreateKey=$true },

    [pscustomobject]@{ Key=$mmcssPlaybackTaskKey; Name='Scheduling Category';         Value='High';       Type='String'; CreateKey=$true },
    [pscustomobject]@{ Key=$mmcssPlaybackTaskKey; Name='Priority When Yielded';       Value=19;           Type='DWord';  CreateKey=$true }
)


$DisablePowerSavingPayload = @'
$ErrorActionPreference = 'Stop'

function Get-Text {
    param([object]$Value)

    if ($null -eq $Value) { return '' }

    if ($Value -is [System.Array]) {
        foreach ($item in $Value) {
            $text = Get-Text $item
            if (-not [string]::IsNullOrWhiteSpace($text)) { return $text }
        }
        return ''
    }

    return ([string]$Value).Trim()
}

function First-Text {
    foreach ($item in $args) {
        $text = Get-Text $item
        if (-not [string]::IsNullOrWhiteSpace($text)) { return $text }
    }
    return ''
}

function Test-Administrator {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]::new($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Invoke-AdapterQuery {
    param(
        [string]$Namespace,
        [string]$ClassName,
        [string]$Filter
    )

    try {
        if (Get-Command Get-CimInstance -ErrorAction SilentlyContinue) {
            return @(Get-CimInstance -Namespace $Namespace -ClassName $ClassName -Filter $Filter -ErrorAction Stop)
        }
    } catch { }

    try {
        return @(Get-WmiObject -Namespace $Namespace -Class $ClassName -Filter $Filter -ErrorAction Stop)
    } catch { }

    return @()
}

function Test-PhysicalAdapter {
    param([object]$Adapter)

    if ($null -eq $Adapter) { return $false }
    if ([string]::IsNullOrWhiteSpace((Get-Text $Adapter.PNPDeviceID))) { return $false }

    try {
        if ($null -ne $Adapter.Virtual -and [bool]$Adapter.Virtual) { return $false }
    } catch { }

    try {
        if ($null -ne $Adapter.HardwareInterface -and -not [bool]$Adapter.HardwareInterface) { return $false }
    } catch { }

    try {
        if ($null -ne $Adapter.PhysicalAdapter -and -not [bool]$Adapter.PhysicalAdapter) { return $false }
    } catch { }

    return $true
}

function Get-ObjectPropertyValue {
    param(
        [object]$Object,
        [string]$Name
    )

    if ($null -eq $Object -or [string]::IsNullOrWhiteSpace($Name)) { return $null }

    try {
        $property = $Object.PSObject.Properties[$Name]
        if ($null -ne $property) { return $property.Value }
    } catch { }

    try {
        return $Object.$Name
    } catch {
        return $null
    }
}

function Get-ObjectPropertyText {
    param(
        [object]$Object,
        [string]$Name
    )

    return Get-Text (Get-ObjectPropertyValue -Object $Object -Name $Name)
}

function Try-ParseNetworkUInt32 {
    param(
        [string]$Value,
        [ref]$Result
    )

    $Result.Value = [uint32]0
    $text = Get-Text $Value
    if ([string]::IsNullOrWhiteSpace($text)) { return $false }

    if ($text -ieq '<none>' -or $text -ieq 'none' -or $text -ieq '<empty>' -or $text -ieq 'unknown') { return $false }

    if ($text.Contains('/')) {
        $text = ($text -split '/', 2)[0].Trim()
    }

    try {
        $Result.Value = [Convert]::ToUInt32($text, [System.Globalization.CultureInfo]::InvariantCulture)
        return $true
    } catch {
        return $false
    }
}

function Normalize-NetworkNdisValue {
    param([string]$Value)

    $text = Get-Text $Value
    if ([string]::IsNullOrWhiteSpace($text)) { return '' }

    if ($text -ieq '<none>' -or
        $text -ieq 'none' -or
        $text -ieq '<empty>' -or
        $text -ieq 'unknown' -or
        $text -ieq 'OtherOrUnknown') { return '' }

    $parsed = [uint32]0
    if (Try-ParseNetworkUInt32 -Value $text -Result ([ref]$parsed)) {
        return $parsed.ToString([System.Globalization.CultureInfo]::InvariantCulture)
    }

    if ($text.IndexOf('NdisMediumNative802_11', [StringComparison]::OrdinalIgnoreCase) -ge 0) { return '16' }
    if ($text.IndexOf('NdisPhysicalMediumNative802_11', [StringComparison]::OrdinalIgnoreCase) -ge 0) { return '9' }
    if ($text.IndexOf('Native802_11', [StringComparison]::OrdinalIgnoreCase) -ge 0) { return '9' }
    if ($text.IndexOf('WirelessLan', [StringComparison]::OrdinalIgnoreCase) -ge 0) { return '1' }
    if ($text.IndexOf('Bluetooth', [StringComparison]::OrdinalIgnoreCase) -ge 0) { return '10' }
    if ($text.IndexOf('WirelessWan', [StringComparison]::OrdinalIgnoreCase) -ge 0) { return '8' }
    if ($text.IndexOf('WiMax', [StringComparison]::OrdinalIgnoreCase) -ge 0) { return '12' }

    return $text
}

function Test-NetworkAdapterKindWeak {
    param([string]$Kind)

    $text = Get-Text $Kind
    return ([string]::IsNullOrWhiteSpace($text) -or
            $text -ieq 'OtherOrUnknown' -or
            $text -ieq 'EthernetOrUnknown')
}

function Get-NetworkAdapterKind {
    param(
        [string]$NdisPhysicalMediumText,
        [string]$NdisMediumText
    )

    $ndisPhysicalMedium = [uint32]0
    if (Try-ParseNetworkUInt32 -Value (Normalize-NetworkNdisValue $NdisPhysicalMediumText) -Result ([ref]$ndisPhysicalMedium)) {
        switch ($ndisPhysicalMedium) {
            1  { return 'WiFi' }
            9  { return 'WiFi' }
            14 { return 'WiredEthernet' }
            10 { return 'Bluetooth' }
            8  { return 'WirelessWAN' }
            12 { return 'WiMAX' }
        }
    }

    $ndisMedium = [uint32]0
    if (Try-ParseNetworkUInt32 -Value (Normalize-NetworkNdisValue $NdisMediumText) -Result ([ref]$ndisMedium)) {
        if ($ndisMedium -eq 16) { return 'WiFi' }
        if ($ndisMedium -eq 0) { return 'EthernetOrUnknown' }
    }

    return 'OtherOrUnknown'
}

function Get-NetworkAdapterKindFromMedia {
    param(
        [string]$NdisPhysicalMediumText,
        [string]$NdisMediumText,
        [string]$AdapterTypeIdText
    )

    $baseKind = Get-NetworkAdapterKind -NdisPhysicalMediumText (Normalize-NetworkNdisValue $NdisPhysicalMediumText) -NdisMediumText (Normalize-NetworkNdisValue $NdisMediumText)
    if (-not (Test-NetworkAdapterKindWeak $baseKind)) { return $baseKind }

    $adapterTypeId = [uint32]0
    if (Try-ParseNetworkUInt32 -Value $AdapterTypeIdText -Result ([ref]$adapterTypeId)) {
        switch ($adapterTypeId) {
            9  { return 'WiFi' }
            0  { return 'WiredEthernet' }
            3  { return 'WirelessWAN' }
            10 { return 'Bluetooth' }
        }
    }

    if ($baseKind -ieq 'EthernetOrUnknown') { return 'WiredEthernet' }
    return 'OtherOrUnknown'
}

function New-AdapterInfo {
    param(
        [object]$Adapter,
        [string]$Source = ''
    )

    $name = First-Text `
        (Get-ObjectPropertyText -Object $Adapter -Name 'InterfaceDescription') `
        (Get-ObjectPropertyText -Object $Adapter -Name 'Name') `
        (Get-ObjectPropertyText -Object $Adapter -Name 'NetConnectionID')

    $pnpId = Get-ObjectPropertyText -Object $Adapter -Name 'PNPDeviceID'
    $adapterTypeId = Get-ObjectPropertyText -Object $Adapter -Name 'AdapterTypeID'
    $ndisPhysicalMedium = Normalize-NetworkNdisValue (Get-ObjectPropertyText -Object $Adapter -Name 'NdisPhysicalMedium')
    $ndisMedium = Normalize-NetworkNdisValue (Get-ObjectPropertyText -Object $Adapter -Name 'NdisMedium')
    $mediaSource = ''
    if (-not [string]::IsNullOrWhiteSpace($ndisPhysicalMedium) -or -not [string]::IsNullOrWhiteSpace($ndisMedium)) {
        $mediaSource = Get-Text $Source
    }

    [pscustomobject]@{
        Name                 = $name
        InterfaceDescription = First-Text (Get-ObjectPropertyText -Object $Adapter -Name 'InterfaceDescription') $name
        PNPDeviceID          = $pnpId
        AdapterTypeID        = $adapterTypeId
        NdisPhysicalMedium   = $ndisPhysicalMedium
        NdisMedium           = $ndisMedium
        NdisMediaSource      = $mediaSource
        NetworkAdapterKind   = Get-NetworkAdapterKindFromMedia -NdisPhysicalMediumText $ndisPhysicalMedium -NdisMediumText $ndisMedium -AdapterTypeIdText $adapterTypeId
    }
}

function Merge-AdapterInfo {
    param(
        [object]$Target,
        [object]$Source
    )

    if ($null -eq $Target -or $null -eq $Source) { return }

    foreach ($name in @('AdapterTypeID','NdisPhysicalMedium','NdisMedium','NdisMediaSource')) {
        $current = Get-Text $Target.$name
        $incoming = Get-Text $Source.$name
        if ([string]::IsNullOrWhiteSpace($current) -and -not [string]::IsNullOrWhiteSpace($incoming)) {
            $Target.$name = $incoming
        }
    }

    $Target.NetworkAdapterKind = Get-NetworkAdapterKindFromMedia -NdisPhysicalMediumText $Target.NdisPhysicalMedium -NdisMediumText $Target.NdisMedium -AdapterTypeIdText $Target.AdapterTypeID
}

function Remove-DuplicateAdaptersByPnpId {
    param([object[]]$Adapters)

    $seen = @{}
    $result = @()

    foreach ($adapter in @($Adapters)) {
        if ($null -eq $adapter) { continue }
        $pnp = Get-Text $adapter.PNPDeviceID
        if ([string]::IsNullOrWhiteSpace($pnp)) { continue }

        $key = $pnp.ToUpperInvariant()
        if ($seen.ContainsKey($key)) { continue }

        $seen[$key] = $true
        $result += $adapter
    }

    return @($result)
}

function Get-PhysicalNetworkAdapters {
    $candidates = @()
    $win32Infos = @()

    $win32Adapters = Invoke-AdapterQuery -Namespace 'root\cimv2' -ClassName 'Win32_NetworkAdapter' -Filter 'PhysicalAdapter=True'
    foreach ($adapter in @($win32Adapters)) {
        if (-not (Test-PhysicalAdapter $adapter)) { continue }
        $win32Infos += New-AdapterInfo -Adapter $adapter -Source 'Win32_NetworkAdapter'
    }

    $msftAdapters = Invoke-AdapterQuery -Namespace 'root\StandardCimv2' -ClassName 'MSFT_NetAdapter' -Filter 'Virtual=False'
    foreach ($adapter in @($msftAdapters)) {
        if (-not (Test-PhysicalAdapter $adapter)) { continue }
        $candidates += New-AdapterInfo -Adapter $adapter -Source 'MSFT_NetAdapter'
    }

    $candidates = Remove-DuplicateAdaptersByPnpId $candidates
    $win32Infos = Remove-DuplicateAdaptersByPnpId $win32Infos

    if (@($candidates).Count -gt 0) {
        $win32ByPnp = @{}
        $win32ByName = @{}
        foreach ($info in @($win32Infos)) {
            $pnp = Get-Text $info.PNPDeviceID
            if (-not [string]::IsNullOrWhiteSpace($pnp)) { $win32ByPnp[$pnp.ToUpperInvariant()] = $info }

            $name = Get-Text $info.Name
            if (-not [string]::IsNullOrWhiteSpace($name)) { $win32ByName[$name.ToUpperInvariant()] = $info }
        }

        foreach ($candidate in @($candidates)) {
            $match = $null
            $pnp = Get-Text $candidate.PNPDeviceID
            if (-not [string]::IsNullOrWhiteSpace($pnp)) { $match = $win32ByPnp[$pnp.ToUpperInvariant()] }

            if ($null -eq $match) {
                $name = Get-Text $candidate.Name
                if (-not [string]::IsNullOrWhiteSpace($name)) { $match = $win32ByName[$name.ToUpperInvariant()] }
            }

            if ($null -ne $match) { Merge-AdapterInfo -Target $candidate -Source $match }
        }

        return @($candidates)
    }

    return @($win32Infos)
}

function Write-NetworkAdapterDetection {
    param([object]$Result)

    $driver = First-Text $Result.DriverModel 'NDIS'
    $driverDisplay = 'NDIS'
    if ($driver -ieq 'NetAdapterCx') { $driverDisplay = 'NETADAPTERCX' }

    $kind = First-Text $Result.NetworkAdapterKind 'OtherOrUnknown'
    $physical = First-Text $Result.NdisPhysicalMedium '<none>'
    $medium = First-Text $Result.NdisMedium '<none>'
    $adapterTypeId = First-Text $Result.AdapterTypeID '<none>'
    $source = First-Text $Result.NdisMediaSource '<none>'

    Write-Output ('Driver     : {0}' -f $driverDisplay)
    Write-Output ('Media      : {0}' -f $kind)
    Write-Output ('NDIS media : NdisPhysicalMedium={0}, NdisMedium={1}, AdapterTypeID={2}, Source={3}' -f $physical, $medium, $adapterTypeId, $source)
}

function Get-RegistryStringValue {
    param(
        [string]$Path,
        [string]$Name
    )

    try {
        $item = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop
        return Get-Text $item.$Name
    } catch {
        return ''
    }
}

function Convert-HklmProviderPathToRegPath {
    param([string]$Path)

    $text = Get-Text $Path
    if ($text -match '^HKLM:\\') {
        return ('HKEY_LOCAL_MACHINE\' + $text.Substring(6))
    }
    return $text
}

function Resolve-NetworkDriverImagePath {
    param([string]$ImagePath)

    $resolved = Get-Text $ImagePath
    if ([string]::IsNullOrWhiteSpace($resolved)) { return '' }

    try { $resolved = [Environment]::ExpandEnvironmentVariables($resolved) } catch { }

    if ($resolved.StartsWith('"')) {
        $closing = $resolved.IndexOf('"', 1)
        if ($closing -gt 1) { $resolved = $resolved.Substring(1, $closing - 1) }
    } else {
        $sysIndex = $resolved.IndexOf('.sys', [StringComparison]::OrdinalIgnoreCase)
        if ($sysIndex -ge 0) {
            $resolved = $resolved.Substring(0, $sysIndex + 4)
        } elseif ($resolved.Contains(' ')) {
            $resolved = ($resolved -split '\s+', 2)[0]
        }
    }

    try {
        $systemRoot = [Environment]::GetFolderPath([Environment+SpecialFolder]::Windows)
        if ([string]::IsNullOrWhiteSpace($systemRoot)) { $systemRoot = $env:windir }

        if ($resolved.StartsWith('\SystemRoot', [StringComparison]::OrdinalIgnoreCase)) {
            $resolved = $systemRoot + $resolved.Substring('\SystemRoot'.Length)
        } elseif ($resolved.StartsWith('System32', [StringComparison]::OrdinalIgnoreCase)) {
            $resolved = Join-Path $systemRoot $resolved
        } elseif ($resolved.StartsWith('\??\', [StringComparison]::OrdinalIgnoreCase)) {
            $resolved = $resolved.Substring(4)
        }

        $resolved = $resolved.Replace('%SystemRoot%', $systemRoot).Replace('%systemroot%', $systemRoot)
    } catch { }

    return $resolved
}

function Get-NetworkDriverTypeFromBinary {
    param([string]$ResolvedPath)

    if ([string]::IsNullOrWhiteSpace($ResolvedPath) -or -not (Test-Path -LiteralPath $ResolvedPath)) { return 'NDIS' }

    $stream = $null
    try {
        $stream = [System.IO.File]::Open($ResolvedPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $bytesToRead = [int][Math]::Min($stream.Length, 1048576L)
        if ($bytesToRead -le 0) { return 'NDIS' }

        $buffer = New-Object byte[] $bytesToRead
        $offset = 0
        while ($offset -lt $bytesToRead) {
            $read = $stream.Read($buffer, $offset, $bytesToRead - $offset)
            if ($read -le 0) { break }
            $offset += $read
        }

        $text = [System.Text.Encoding]::ASCII.GetString($buffer, 0, $offset)
        if ($text.IndexOf('NetAdapter', [StringComparison]::OrdinalIgnoreCase) -ge 0) { return 'NetAdapterCx' }
    } catch {
    } finally {
        if ($null -ne $stream) { $stream.Close() }
    }

    return 'NDIS'
}

function Resolve-AdapterClassPath {
    param([object]$Adapter)

    $pnpId = Get-Text $Adapter.PNPDeviceID
    if ([string]::IsNullOrWhiteSpace($pnpId)) { return $null }

    $enumPath = 'HKLM:\SYSTEM\CurrentControlSet\Enum\' + $pnpId
    $driver = Get-RegistryStringValue -Path $enumPath -Name 'Driver'
    if ([string]::IsNullOrWhiteSpace($driver)) { return $null }

    $classProviderPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\' + $driver
    if (-not (Test-Path -LiteralPath $classProviderPath)) { return $null }

    $service = Get-RegistryStringValue -Path ($classProviderPath + '\Ndi') -Name 'Service'
    if (-not [string]::IsNullOrWhiteSpace($service)) { $service = $service.TrimEnd('.').Trim() }

    $servicePath = ''
    $imagePath = ''
    if (-not [string]::IsNullOrWhiteSpace($service)) {
        $servicePath = 'HKLM:\SYSTEM\CurrentControlSet\Services\' + $service
        $imagePath = Get-RegistryStringValue -Path $servicePath -Name 'ImagePath'
    }

    $resolvedImagePath = Resolve-NetworkDriverImagePath -ImagePath $imagePath
    $driverModel = Get-NetworkDriverTypeFromBinary -ResolvedPath $resolvedImagePath
    $adapterKind = Get-NetworkAdapterKindFromMedia -NdisPhysicalMediumText $Adapter.NdisPhysicalMedium -NdisMediumText $Adapter.NdisMedium -AdapterTypeIdText $Adapter.AdapterTypeID

    [pscustomobject]@{
        Name               = Get-Text $Adapter.Name
        PNPDeviceID        = $pnpId
        DriverModel        = $driverModel
        NetworkAdapterKind = $adapterKind
        NdisPhysicalMedium = Normalize-NetworkNdisValue $Adapter.NdisPhysicalMedium
        NdisMedium         = Normalize-NetworkNdisValue $Adapter.NdisMedium
        NdisMediaSource    = Get-Text $Adapter.NdisMediaSource
        AdapterTypeID      = Get-Text $Adapter.AdapterTypeID
        Service            = $service
        ServicePath        = $servicePath
        ImagePath          = $imagePath
        ResolvedImagePath  = $resolvedImagePath
        ProviderPath       = $classProviderPath
        ProviderClassPath  = $classProviderPath
        ClassPath          = Convert-HklmProviderPathToRegPath $classProviderPath
    }
}


function Remove-DuplicateResolvedClassPaths {
    param([object[]]$ResolvedAdapters)

    $seen = @{}
    $result = @()

    foreach ($item in @($ResolvedAdapters)) {
        if ($null -eq $item) { continue }
        $key = (Get-Text $item.ProviderPath).ToUpperInvariant()
        if ([string]::IsNullOrWhiteSpace($key)) { continue }
        if ($seen.ContainsKey($key)) { continue }

        $seen[$key] = $true
        $result += $item
    }

    return @($result)
}

function Convert-DwordValueToUInt32 {
    param([object]$Value)

    if ($Value -is [int]) {
        return [BitConverter]::ToUInt32([BitConverter]::GetBytes([int]$Value), 0)
    }

    if (($Value -is [long]) -and ([long]$Value -lt 0)) {
        return [BitConverter]::ToUInt32([BitConverter]::GetBytes([int]$Value), 0)
    }

    return [Convert]::ToUInt32($Value)
}

function Set-RegistryValueExact {
    param(
        [string]$Path,
        [string]$Name,
        [object]$Value,
        [ValidateSet('String','DWord')]
        [string]$PropertyType
    )

    $exists = $false
    $currentValue = $null
    try {
        $item = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop
        if ($item.PSObject.Properties.Name -contains $Name) {
            $exists = $true
            $currentValue = $item.$Name
        }
    } catch { }

    if ($exists) {
        try {
            if ($PropertyType -eq 'DWord') {
                if ((Convert-DwordValueToUInt32 -Value $currentValue) -eq (Convert-DwordValueToUInt32 -Value $Value)) { return 'Unchanged' }
            } elseif ([string]$currentValue -eq [string]$Value) {
                return 'Unchanged'
            }
        } catch { }
    }

    try {
        New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType $PropertyType -Force -ErrorAction Stop | Out-Null
    } catch {
        $tiPath = $Path; $tiName = $Name; $tiValue = $Value; $tiType = $PropertyType
        $tiOk = Invoke-AsTrustedInstaller {
            New-ItemProperty -LiteralPath $using:tiPath -Name $using:tiName -Value $using:tiValue -PropertyType $using:tiType -Force -ErrorAction Stop | Out-Null
        }
        if (-not $tiOk) { throw $_ }
    }

    if ($exists) { return 'Updated' }
    return 'Created'
}

$stringValues = [ordered]@{
    '*DeviceSleepOnDisconnect' = '0'
    '*WakeOnMagicPacket' = '0'
    '*WakeOnPattern' = '0'
    '*NicAutoPowerSaver' = '0'
    'EEELinkAdvertisement' = '0'
    'EnableModernStandby' = '0'
    'EnablePowerManagement' = '0'
    'EnablePME' = '0'
    'ForceWakeFromMagicPacketOnModernStandby' = '0'
    'WakeFromS5' = '0'
    'WakeOn' = '0'
    'WakeOnLink' = '0'
    'LinkNegotiationProcess' = '0'
    'WaitForValidPhyIDRead' = '0'
    'WaitAutoNegComplete' = '0'
    'SleepWhileWaiting' = '0'
    'EnableETW' = '0'
    'OBFFEnabled' = '0'
    'ULPMode' = '0'
    'I218DisablePLLShut' = '1'
    'I218DisablePLLShutGiga' = '1'
    'I219DisableK1Off' = '1'
    'DisableDelayedPowerUp' = '1'
    '*EEE' = '0'
    'DisableIntelRST' = '1'
    'ForceHostExitUlp' = '1'
    'ForceLtrValue' = '0'
    'EnableDisconnectedStandby' = '0'
    'DMACoalescing' = '0'
    'EnableWakeOnManagmentOnTCO' = '0'
    'EnablePHYFlexibleSpeed' = '0'
    'EnablePHYWakeUp' = '0'
    'EnableD0PHYFlexibleSpeed' = '0'
    'EnableSavePowerNow' = '0'
    'AutoPowerSaveModeEnabled' = '0'
    'SipsEnabled' = '0'
    'WakeOnFastStartup' = '0'
    'ReduceSpeedOnPowerDown' = '0'
    '*EnableDynamicPowerGating' = '0'
    'EnableD3ColdInS0' = '0'
    '*SSIdleTimeout' = '1'
    '*SSIdleTimeoutScreenOff' = '1'
    'SSIdleTimeoutMS' = '1'
    'LatencyToleranceReporting' = '0'
    '*SelectiveSuspend' = '0'
    '*IdleRestriction' = '1'
    'AdvancedEEE' = '0'
    'ASPM' = '0'
    'CLKREQ' = '0'
    'EEEPlus' = '0'
    'EnableAspm' = '0'
    'DynamicLTR' = '0'
    'EnableGreenEthernet' = '0'
    'GigaLite' = '0'
    'PowerDownPll' = '0'
    'PowerSavingMode' = '0'
    'WolShutdownLinkSpeed' = '2'
    'LTROBFF' = '0'
    'S0MgcPkt' = '0'
    'S5WakeOnLan' = '0'
}

$dwordValues = [ordered]@{
    'HwOption' = [uint32]0x00C00000
    'HwOptionV2' = [uint32]0x00000004
    'HwOptionV3' = [uint32]0x00040000
}

if (-not (Test-Administrator)) {
    Write-Error 'This script must be run as Administrator because it writes to HKLM network adapter class keys.'
    exit 2
}

$results = @()
foreach ($adapter in @(Get-PhysicalNetworkAdapters)) {
    $resolved = Resolve-AdapterClassPath -Adapter $adapter
    if ($null -ne $resolved) { $results += $resolved }
}

$results = Remove-DuplicateResolvedClassPaths $results

if ($results.Count -eq 0) {
    Write-Error 'No physical network adapter class path was found.'
    exit 1
}

$totalCreated = 0
$totalUpdated = 0
$totalUnchanged = 0
$totalFailed = 0
$firstResult = $true

foreach ($result in $results) {
    $pathCreated = 0
    $pathUpdated = 0
    $pathUnchanged = 0

    if (-not $firstResult) { Write-Output '' }
    $firstResult = $false

    Write-Output ('Name       : {0}' -f $result.Name)
    Write-NetworkAdapterDetection -Result $result
    Write-Output ('CLASS_PATH : {0}' -f $result.ClassPath)

    $media = First-Text $result.NetworkAdapterKind 'OtherOrUnknown'
    if ($media -ine 'WiredEthernet') {
        Write-Output ('SKIPPED    : Disable powersaving was not applied because Media is {0}, not WiredEthernet.' -f $media)
        Write-Output ('Values     : created=0, updated=0, unchanged=0')
        continue
    }

    foreach ($entry in $stringValues.GetEnumerator()) {
        try {
            $status = Set-RegistryValueExact -Path $result.ProviderPath -Name $entry.Key -Value ([string]$entry.Value) -PropertyType 'String'
            switch ($status) {
                'Created' {
                    $pathCreated++
                    $totalCreated++
                    break
                }
                'Updated' {
                    $pathUpdated++
                    $totalUpdated++
                    break
                }
                'Unchanged' {
                    $pathUnchanged++
                    $totalUnchanged++
                    break
                }
                default {
                    $pathUpdated++
                    $totalUpdated++
                    break
                }
            }
        } catch {
            $totalFailed++
        }
    }

    foreach ($entry in $dwordValues.GetEnumerator()) {
        try {
            $status = Set-RegistryValueExact -Path $result.ProviderPath -Name $entry.Key -Value ([uint32]$entry.Value) -PropertyType 'DWord'
            switch ($status) {
                'Created' {
                    $pathCreated++
                    $totalCreated++
                    break
                }
                'Updated' {
                    $pathUpdated++
                    $totalUpdated++
                    break
                }
                'Unchanged' {
                    $pathUnchanged++
                    $totalUnchanged++
                    break
                }
                default {
                    $pathUpdated++
                    $totalUpdated++
                    break
                }
            }
        } catch {
            $totalFailed++
        }
    }

    Write-Output ('Values     : created={0}, updated={1}, unchanged={2}' -f $pathCreated, $pathUpdated, $pathUnchanged)
}

Write-Output ''
Write-Output ('Total      : adapters={0}, created={1}, updated={2}, unchanged={3}, failed={4}' -f @($results).Count, $totalCreated, $totalUpdated, $totalUnchanged, $totalFailed)

if ($totalFailed -gt 0) { exit 3 }
exit 0
'@

$DisableDevicePowerSavingPayload = @'
$results = New-Object System.Collections.Generic.List[object]
function Add-Result {
param([string]$Area,[string]$Target,[bool]$Success,[string]$Message,[bool]$Warning=$false)
$null = $results.Add([pscustomobject]@{Area=$Area;Target=$Target;Success=$Success;Message=$Message;Warning=$Warning})
}
$pnpNameMap = @{}
try {
@(Get-WmiObject -Class Win32_PnPEntity -ErrorAction Stop) | ForEach-Object {
if ($_.PNPDeviceID -and -not $pnpNameMap.ContainsKey($_.PNPDeviceID)) {
if ([string]::IsNullOrWhiteSpace($_.Name)) {
$pnpNameMap[$_.PNPDeviceID] = $_.PNPDeviceID
} else {
$pnpNameMap[$_.PNPDeviceID] = $_.Name
}
}
}
} catch {
Add-Result 'Environment' 'Win32_PnPEntity' $false $_.Exception.Message
}
function Resolve-DeviceLabel {
param([string]$Id)
if ([string]::IsNullOrWhiteSpace($Id)) { return $Id }
if ($pnpNameMap.ContainsKey($Id)) { return $pnpNameMap[$Id] }
if ($Id -match '^(.*)_\d+$') {
if ($pnpNameMap.ContainsKey($matches[1])) { return $pnpNameMap[$matches[1]] }
}
return $Id
}
function Apply-WmiDisable {
param([string]$ClassName,[string]$Area)
try {
$items = @(Get-WmiObject -Namespace root\wmi -Class $ClassName -ErrorAction Stop)
} catch {
Add-Result $Area $ClassName $false ("Query failed: " + $_.Exception.Message)
return
}
if (-not $items -or $items.Count -eq 0) {
Add-Result $Area $ClassName $true 'No applicable devices found.'
return
}
foreach ($item in $items) {
$instanceName = [string]$item.InstanceName
$label = Resolve-DeviceLabel $instanceName
try {
$current = $false
if ($null -ne $item.Enable) { $current = [bool]$item.Enable }
if ($current) {
$item.Enable = $false
$null = $item.Put()
Add-Result $Area $label $true ("Disabled. InstanceName=" + $instanceName)
} else {
Add-Result $Area $label $true ("Already disabled. InstanceName=" + $instanceName)
}
} catch {
Add-Result $Area $label $false ("Failed. InstanceName=" + $instanceName + " Error=" + $_.Exception.Message)
}
}
}
Apply-WmiDisable -ClassName 'MSPower_DeviceEnable' -Area 'Allow turn-off to save power'
Apply-WmiDisable -ClassName 'MSPower_DeviceWakeEnable' -Area 'Allow wake computer'
try {
$wakeDevices = @(& powercfg -devicequery wake_programmable 2>$null | Where-Object { $_ -and $_.Trim() })
if (-not $wakeDevices -or $wakeDevices.Count -eq 0) {
Add-Result 'Wake disable via powercfg' 'wake_programmable' $true 'No wake-programmable devices found.'
} else {
foreach ($deviceName in $wakeDevices) {
try {
$output = @(& powercfg -devicedisablewake "$deviceName" 2>&1)
if ($LASTEXITCODE -eq 0) {
Add-Result 'Wake disable via powercfg' $deviceName $true 'Wake disabled via powercfg.'
} else {
Add-Result 'Wake disable via powercfg' $deviceName $false (($output -join ' ') -replace '\s+',' ')
}
} catch {
Add-Result 'Wake disable via powercfg' $deviceName $false $_.Exception.Message
}
}
}
} catch {
Add-Result 'Wake disable via powercfg' 'powercfg' $false $_.Exception.Message
}
try {
Import-Module NetAdapter -ErrorAction Stop | Out-Null
} catch {
Add-Result 'Network adapter power management' 'NetAdapter module' $false $_.Exception.Message
}
if (Get-Command Disable-NetAdapterPowerManagement -ErrorAction SilentlyContinue) {
try {
$adapters = @(Get-NetAdapter -IncludeHidden -ErrorAction Stop)
} catch {
$adapters = @()
Add-Result 'Network adapter power management' 'Get-NetAdapter' $false $_.Exception.Message
}
if (-not $adapters -or $adapters.Count -eq 0) {
Add-Result 'Network adapter power management' 'Adapters' $true 'No network adapters found.'
} else {
foreach ($adapter in $adapters) {
$target = $adapter.Name
if (-not [string]::IsNullOrWhiteSpace($adapter.InterfaceDescription)) {
$target = $adapter.Name + ' | ' + $adapter.InterfaceDescription
}
try {
Disable-NetAdapterPowerManagement -Name $adapter.Name -IncludeHidden -ErrorAction Stop | Out-Null
Add-Result 'Network adapter power management' $target $true 'Disable-NetAdapterPowerManagement applied.'
} catch {
$message = [string]$_.Exception.Message
if ($message -match 'No MSFT_NetAdapterPowerManagementSettingData objects found') {
Add-Result 'Network adapter power management' $target $true $message $true
} else {
Add-Result 'Network adapter power management' $target $false $message
}
}
}
}
} else {
Add-Result 'Network adapter power management' 'Disable-NetAdapterPowerManagement' $false 'Cmdlet not available on this system.'
}
function Format-RegistryValue {
param($Value,[string]$Kind)
if ($null -eq $Value) { return '<missing>' }
$suffix = ''
if (-not [string]::IsNullOrWhiteSpace($Kind)) {
$suffix = ' (' + $Kind + ')'
}
if ($Value -is [byte[]]) {
if ($Value.Length -eq 0) { return '[]' + $suffix }
return ('[' + (($Value | ForEach-Object { $_.ToString('X2') }) -join ' ') + ']') + $suffix
}
if ($Value -is [System.Array]) {
return ('[' + (($Value | ForEach-Object { [string]$_ }) -join ', ') + ']') + $suffix
}
return ([string]$Value) + $suffix
}
function Convert-RegistryValueToInt {
param($Value)
if ($null -eq $Value) { return $null }
if ($Value -is [byte[]]) {
if ($Value.Length -eq 0) { return 0 }
$buffer = New-Object byte[] 4
[Array]::Copy($Value, $buffer, [Math]::Min($Value.Length, 4))
return [BitConverter]::ToInt32($buffer, 0)
}
if ($Value -is [System.Array]) {
if ($Value.Count -eq 0) { return 0 }
try { return [int]$Value[0] } catch { return $null }
}
try { return [int]$Value } catch { return $null }
}
$usbRoots = @(
'HKLM:\SYSTEM\CurrentControlSet\Enum\USB',
'HKLM:\SYSTEM\CurrentControlSet\Enum\USBSTOR',
'HKLM:\SYSTEM\CurrentControlSet\Enum\USBPRINT',
'HKLM:\SYSTEM\CurrentControlSet\Enum\BTHUSB'
)
$usbValueNames = @(
'EnhancedPowerManagementEnabled',
'SelectiveSuspendEnabled',
'EnableSelectiveSuspend',
'AllowIdleIrpInD3'
)
$usbDeviceParamPaths = @()
foreach ($root in $usbRoots) {
if (Test-Path -LiteralPath $root) {
$found = @(Get-ChildItem -LiteralPath $root -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -eq 'Device Parameters' } | Select-Object -ExpandProperty PSPath)
if ($found.Count -gt 0) {
$usbDeviceParamPaths += $found
} else {
Add-Result 'USB per-device registry' $root $true 'Root present but no Device Parameters keys found.'
}
} else {
Add-Result 'USB per-device registry' $root $true 'Root not present on this system.'
}
}
$usbDeviceParamPaths = @($usbDeviceParamPaths | Sort-Object -Unique)
if (-not $usbDeviceParamPaths -or $usbDeviceParamPaths.Count -eq 0) {
Add-Result 'USB per-device registry' 'USB roots' $true 'No USB Device Parameters keys found.'
} else {
foreach ($path in $usbDeviceParamPaths) {
try {
$keyItem = Get-Item -LiteralPath $path -ErrorAction Stop
$relative = $keyItem.Name -replace '^HKEY_LOCAL_MACHINE\\SYSTEM\\CurrentControlSet\\Enum\\',''
$pnpId = $relative -replace '\\Device Parameters$',''
$label = Resolve-DeviceLabel $pnpId
$notes = New-Object System.Collections.Generic.List[string]
$allOk = $true
foreach ($valueName in $usbValueNames) {
try {
$before = $null
$beforeKind = $null
$valueExists = $false
try {
if ($keyItem.GetValueNames() -contains $valueName) {
$valueExists = $true
$beforeKind = [string]$keyItem.GetValueKind($valueName)
$before = $keyItem.GetValue($valueName, $null, 'DoNotExpandEnvironmentNames')
}
} catch {
$valueExists = $false
$before = $null
$beforeKind = $null
}
if (-not $valueExists) {
New-ItemProperty -LiteralPath $path -Name $valueName -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
$notes.Add($valueName + '=0 created')
continue
}
if ($beforeKind -ne 'DWord') {
Remove-ItemProperty -LiteralPath $path -Name $valueName -Force -ErrorAction Stop
New-ItemProperty -LiteralPath $path -Name $valueName -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
$notes.Add($valueName + ': ' + (Format-RegistryValue -Value $before -Kind $beforeKind) + ' -> 0 (recreated as DWord)')
continue
}
Set-ItemProperty -LiteralPath $path -Name $valueName -Value 0 -ErrorAction Stop
$beforeInt = Convert-RegistryValueToInt -Value $before
if ($null -eq $beforeInt) {
$notes.Add($valueName + ': ' + (Format-RegistryValue -Value $before -Kind $beforeKind) + ' -> 0')
} elseif ($beforeInt -eq 0) {
$notes.Add($valueName + ' already 0')
} else {
$notes.Add($valueName + ': ' + [string]$beforeInt + ' -> 0')
}
} catch {
$allOk = $false
$notes.Add($valueName + ' failed: ' + $_.Exception.Message)
}
}
Add-Result 'USB per-device registry' ($label + ' | ' + $pnpId) $allOk ($notes -join '; ')
} catch {
Add-Result 'USB per-device registry' $path $false $_.Exception.Message
}
}
}
$areaOrder = @(
'Allow turn-off to save power',
'Allow wake computer',
'Wake disable via powercfg',
'Network adapter power management',
'USB per-device registry',
'Environment'
)
$seenAreas = @{}
foreach ($area in $areaOrder) {
$seenAreas[$area] = $true
$group = @($results | Where-Object { $_.Area -eq $area })
if ($group.Count -gt 0) {
Write-Host ''
Write-Host ('=== ' + $area + ' ===') -ForegroundColor Green
foreach ($entry in $group | Sort-Object Target) {
if ($entry.Success -and $entry.Warning) {
Write-Host ('[WARNING] ' + $entry.Target + ' - ' + $entry.Message) -ForegroundColor Yellow
} elseif ($entry.Success) {
Write-Host ('[OK] ' + $entry.Target + ' - ' + $entry.Message) -ForegroundColor Green
} else {
Write-Host ('[FAIL] ' + $entry.Target + ' - ' + $entry.Message) -ForegroundColor Red
}
}
}
}
$extraAreas = @($results | Select-Object -ExpandProperty Area -Unique | Where-Object { -not $seenAreas.ContainsKey($_) })
foreach ($area in $extraAreas) {
$group = @($results | Where-Object { $_.Area -eq $area })
if ($group.Count -gt 0) {
Write-Host ''
Write-Host ('=== ' + $area + ' ===') -ForegroundColor Green
foreach ($entry in $group | Sort-Object Target) {
if ($entry.Success -and $entry.Warning) {
Write-Host ('[WARNING] ' + $entry.Target + ' - ' + $entry.Message) -ForegroundColor Yellow
} elseif ($entry.Success) {
Write-Host ('[OK] ' + $entry.Target + ' - ' + $entry.Message) -ForegroundColor Green
} else {
Write-Host ('[FAIL] ' + $entry.Target + ' - ' + $entry.Message) -ForegroundColor Red
}
}
}
}
$successCount = @($results | Where-Object { $_.Success }).Count
$failureCount = @($results | Where-Object { -not $_.Success }).Count
$totalCount = $successCount + $failureCount
$successRatio = 0
if ($totalCount -gt 0) {
$successRatio = $successCount / $totalCount
}
Write-Host ''
if ($failureCount -eq 0) {
Write-Host ('[SUCCESS] Success=' + $successCount + ' Failed=' + $failureCount) -ForegroundColor Green
exit 0
} elseif ($totalCount -gt 0 -and $successRatio -ge 0.75) {
Write-Host ('[WARNING] Partial success. Success=' + $successCount + ' Failed=' + $failureCount + ' SuccessRate=' + [math]::Round(($successRatio * 100), 2) + '%') -ForegroundColor Yellow
exit 10
} else {
Write-Host ('[ERROR] Success=' + $successCount + ' Failed=' + $failureCount + ' SuccessRate=' + [math]::Round(($successRatio * 100), 2) + '%') -ForegroundColor Red
exit 1
}
'@

$OptimizeNetworkingPayload = @'
$ErrorActionPreference = 'Stop'

$AdapterRegistrySettings = @(
    [pscustomobject]@{ Name = '*EncapsulatedPacketTaskOffloadNvgre'; Value = '1' },
    [pscustomobject]@{ Name = '*EncapsulatedPacketTaskOffloadVxlan'; Value = '1' },
    [pscustomobject]@{ Name = '*EncapsulatedPacketTaskOffload'; Value = '1' },
    [pscustomobject]@{ Name = '*IPChecksumOffloadIPv4'; Value = '3' },
    [pscustomobject]@{ Name = '*LsoV1IPv4'; Value = '1' },
    [pscustomobject]@{ Name = '*LsoV2IPv4'; Value = '1' },
    [pscustomobject]@{ Name = '*LsoV2IPv6'; Value = '1' },
    [pscustomobject]@{ Name = '*TCPChecksumOffloadIPv4'; Value = '3' },
    [pscustomobject]@{ Name = '*TCPChecksumOffloadIPv6'; Value = '3' },
    [pscustomobject]@{ Name = '*UDPChecksumOffloadIPv4'; Value = '3' },
    [pscustomobject]@{ Name = '*UDPChecksumOffloadIPv6'; Value = '3' },
    [pscustomobject]@{ Name = '*IPsecOffloadV1IPv4'; Value = '3' },
    [pscustomobject]@{ Name = '*IPsecOffloadV2'; Value = '3' },
    [pscustomobject]@{ Name = '*IPsecOffloadV2IPv4'; Value = '3' },
    [pscustomobject]@{ Name = '*TCPConnectionOffloadIPv4'; Value = '1' },
    [pscustomobject]@{ Name = '*TCPConnectionOffloadIPv6'; Value = '1' },
    [pscustomobject]@{ Name = '*TCPUDPChecksumOffloadIPv4'; Value = '3' },
    [pscustomobject]@{ Name = '*TCPUDPChecksumOffloadIPv6'; Value = '3' },
    [pscustomobject]@{ Name = '*UsoIPv4'; Value = '1' },
    [pscustomobject]@{ Name = '*UsoIPv6'; Value = '1' },
    [pscustomobject]@{ Name = 'TeredoOffload'; Value = '1' },
    [pscustomobject]@{ Name = '*QoSOffload'; Value = '1' },
    [pscustomobject]@{ Name = '*Rss'; Value = '1' },
    [pscustomobject]@{ Name = '*NumRssQueues'; Value = '1' },
    [pscustomobject]@{ Name = 'RssV2'; Value = '1' },
    [pscustomobject]@{ Name = '*VMQ'; Value = '0' },
    [pscustomobject]@{ Name = 'VMQSupported'; Value = '0' },
    [pscustomobject]@{ Name = '*FlowControl'; Value = '0' },
    [pscustomobject]@{ Name = 'FecMode'; Value = '0' },
    [pscustomobject]@{ Name = '*RscIPv4'; Value = '1' },
    [pscustomobject]@{ Name = '*RscIPv6'; Value = '1' },
    [pscustomobject]@{ Name = 'ForceRscEnabled'; Value = '1' },
    [pscustomobject]@{ Name = '*UdpRsc'; Value = '1' },
    [pscustomobject]@{ Name = '*InterruptModeration'; Value = '0' },
    [pscustomobject]@{ Name = 'TxIntModeration'; Value = '0' },
    [pscustomobject]@{ Name = 'RxIntModeration'; Value = '0' },
    [pscustomobject]@{ Name = '*JumboPacket'; Value = '1514' },
    [pscustomobject]@{ Name = 'DisableLLDP'; Value = '1' },
    [pscustomobject]@{ Name = '*HeaderDataSplit'; Value = '1' },
    [pscustomobject]@{ Name = 'HDSplitAlways'; Value = '1' },
    [pscustomobject]@{ Name = '*ReceiveBuffers'; Value = '4096' },
    [pscustomobject]@{ Name = 'StoreBadPackets'; Value = '0' },
    [pscustomobject]@{ Name = 'RecvCompletionMethod'; Value = '4' },
    [pscustomobject]@{ Name = 'AsyncReceiveIndicate'; Value = '2' },
    [pscustomobject]@{ Name = 'ThreadedDpcEnable'; Value = '0' },
    [pscustomobject]@{ Name = '*TransmitBuffers'; Value = '4096' },
    [pscustomobject]@{ Name = 'DropHighlyFragmentedPacket'; Value = '1' },
    [pscustomobject]@{ Name = 'EnableCoalesce'; Value = '0' },
    [pscustomobject]@{ Name = 'TxThreadedDpcEnable'; Value = '0' },
    [pscustomobject]@{ Name = 'SendCompletionMethod'; Value = '2' },
    [pscustomobject]@{ Name = 'ThreadPoll'; Value = '200000' },
    [pscustomobject]@{ Name = '*PacketCoalescing'; Value = '0' },
    [pscustomobject]@{ Name = '*PacketDirect'; Value = '1' },
    [pscustomobject]@{ Name = '*NdisPoll'; Value = '1' },
    [pscustomobject]@{ Name = '*NetworkDirect'; Value = '0' },
    [pscustomobject]@{ Name = 'CongestionMonitoringEnable'; Value = '0' },
    [pscustomobject]@{ Name = '*SRIOV'; Value = '0' }
)


$NdisParameterDwordSettings = @(
    [pscustomobject]@{ Name = 'DisableNDISWatchDog'; Value = 1 },
    [pscustomobject]@{ Name = 'DisableNaps'; Value = 1 },
    [pscustomobject]@{ Name = 'NoPauseOnSuspend'; Value = 1 },
    [pscustomobject]@{ Name = 'DebugLoggingMode'; Value = 0 },
    [pscustomobject]@{ Name = 'DisableWDIWatchdogForceBugcheck'; Value = 1 },
    [pscustomobject]@{ Name = 'DisableReenumerationTimeoutBugcheck'; Value = 1 },
    [pscustomobject]@{ Name = 'EnableNicAutoPowerSaverInSleepStudy'; Value = 0 }
)

function Get-Text {
    param([object]$Value)

    if ($null -eq $Value) { return '' }

    if ($Value -is [System.Array]) {
        foreach ($item in $Value) {
            $text = Get-Text $item
            if (-not [string]::IsNullOrWhiteSpace($text)) { return $text }
        }
        return ''
    }

    return ([string]$Value).Trim()
}

function First-Text {
    foreach ($item in $args) {
        $text = Get-Text $item
        if (-not [string]::IsNullOrWhiteSpace($text)) { return $text }
    }
    return ''
}

function New-FailureRecord {
    param(
        [string]$Area,
        [string]$Operation,
        [string]$Path,
        [string]$Name,
        [object]$Value,
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $message = ''
    $exceptionType = ''
    $category = ''
    $errorId = ''
    $target = ''
    $position = ''

    if ($null -ne $ErrorRecord) {
        $message = Get-Text $ErrorRecord.Exception.Message
        if ($null -ne $ErrorRecord.Exception) {
            $exceptionType = $ErrorRecord.Exception.GetType().FullName
        }
        $category = Get-Text $ErrorRecord.CategoryInfo
        $errorId = Get-Text $ErrorRecord.FullyQualifiedErrorId
        $target = Get-Text $ErrorRecord.TargetObject
        $position = Get-Text $ErrorRecord.InvocationInfo.PositionMessage
    }

    [pscustomobject]@{
        Area          = Get-Text $Area
        Operation     = Get-Text $Operation
        Path          = Get-Text $Path
        Name          = Get-Text $Name
        Value         = Get-Text $Value
        Error         = $message
        ExceptionType = $exceptionType
        Category      = $category
        ErrorId       = $errorId
        Target        = $target
        Position      = $position
    }
}

function Write-FailureReport {
    param([object[]]$Failures)

    Write-Host ''
    Write-Host 'Failures:'

    $index = 1
    foreach ($failure in @($Failures)) {
        Write-Host ('[{0}] Area      : {1}' -f $index, $failure.Area)
        Write-Host ('    Operation : {0}' -f $failure.Operation)

        if (-not [string]::IsNullOrWhiteSpace((Get-Text $failure.Path))) {
            Write-Host ('    Path      : {0}' -f $failure.Path)
        }
        if (-not [string]::IsNullOrWhiteSpace((Get-Text $failure.Name))) {
            Write-Host ('    Name      : {0}' -f $failure.Name)
        }
        if (-not [string]::IsNullOrWhiteSpace((Get-Text $failure.Value))) {
            Write-Host ('    Value     : {0}' -f $failure.Value)
        }
        if (-not [string]::IsNullOrWhiteSpace((Get-Text $failure.Error))) {
            Write-Host ('    Error     : {0}' -f $failure.Error)
        }
        if (-not [string]::IsNullOrWhiteSpace((Get-Text $failure.ExceptionType))) {
            Write-Host ('    Exception : {0}' -f $failure.ExceptionType)
        }
        if (-not [string]::IsNullOrWhiteSpace((Get-Text $failure.Category))) {
            Write-Host ('    Category  : {0}' -f $failure.Category)
        }
        if (-not [string]::IsNullOrWhiteSpace((Get-Text $failure.ErrorId))) {
            Write-Host ('    ErrorId   : {0}' -f $failure.ErrorId)
        }
        if (-not [string]::IsNullOrWhiteSpace((Get-Text $failure.Target))) {
            Write-Host ('    Target    : {0}' -f $failure.Target)
        }
        if (-not [string]::IsNullOrWhiteSpace((Get-Text $failure.Position))) {
            Write-Host ('    Position  :')
            Write-Host $failure.Position
        }

        Write-Host ''
        $index++
    }
}

function Test-IsElevated {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Invoke-AdapterQuery {
    param(
        [string]$Namespace,
        [string]$ClassName,
        [string]$Filter
    )

    try {
        if (Get-Command Get-CimInstance -ErrorAction SilentlyContinue) {
            return @(Get-CimInstance -Namespace $Namespace -ClassName $ClassName -Filter $Filter -ErrorAction Stop)
        }
    } catch { }

    try {
        return @(Get-WmiObject -Namespace $Namespace -Class $ClassName -Filter $Filter -ErrorAction Stop)
    } catch { }

    return @()
}

function Test-PhysicalAdapter {
    param([object]$Adapter)

    if ($null -eq $Adapter) { return $false }
    if ([string]::IsNullOrWhiteSpace((Get-Text $Adapter.PNPDeviceID))) { return $false }

    try {
        if ($null -ne $Adapter.Virtual -and [bool]$Adapter.Virtual) { return $false }
    } catch { }

    try {
        if ($null -ne $Adapter.HardwareInterface -and -not [bool]$Adapter.HardwareInterface) { return $false }
    } catch { }

    try {
        if ($null -ne $Adapter.PhysicalAdapter -and -not [bool]$Adapter.PhysicalAdapter) { return $false }
    } catch { }

    return $true
}

function Get-ObjectPropertyValue {
    param(
        [object]$Object,
        [string]$Name
    )

    if ($null -eq $Object -or [string]::IsNullOrWhiteSpace($Name)) { return $null }

    try {
        $property = $Object.PSObject.Properties[$Name]
        if ($null -ne $property) { return $property.Value }
    } catch { }

    try {
        return $Object.$Name
    } catch {
        return $null
    }
}

function Get-ObjectPropertyText {
    param(
        [object]$Object,
        [string]$Name
    )

    return Get-Text (Get-ObjectPropertyValue -Object $Object -Name $Name)
}

function Try-ParseNetworkUInt32 {
    param(
        [string]$Value,
        [ref]$Result
    )

    $Result.Value = [uint32]0
    $text = Get-Text $Value
    if ([string]::IsNullOrWhiteSpace($text)) { return $false }

    if ($text -ieq '<none>' -or $text -ieq 'none' -or $text -ieq '<empty>' -or $text -ieq 'unknown') { return $false }

    if ($text.Contains('/')) {
        $text = ($text -split '/', 2)[0].Trim()
    }

    try {
        $Result.Value = [Convert]::ToUInt32($text, [System.Globalization.CultureInfo]::InvariantCulture)
        return $true
    } catch {
        return $false
    }
}

function Normalize-NetworkNdisValue {
    param([string]$Value)

    $text = Get-Text $Value
    if ([string]::IsNullOrWhiteSpace($text)) { return '' }

    if ($text -ieq '<none>' -or
        $text -ieq 'none' -or
        $text -ieq '<empty>' -or
        $text -ieq 'unknown' -or
        $text -ieq 'OtherOrUnknown') { return '' }

    $parsed = [uint32]0
    if (Try-ParseNetworkUInt32 -Value $text -Result ([ref]$parsed)) {
        return $parsed.ToString([System.Globalization.CultureInfo]::InvariantCulture)
    }

    if ($text.IndexOf('NdisMediumNative802_11', [StringComparison]::OrdinalIgnoreCase) -ge 0) { return '16' }
    if ($text.IndexOf('NdisPhysicalMediumNative802_11', [StringComparison]::OrdinalIgnoreCase) -ge 0) { return '9' }
    if ($text.IndexOf('Native802_11', [StringComparison]::OrdinalIgnoreCase) -ge 0) { return '9' }
    if ($text.IndexOf('WirelessLan', [StringComparison]::OrdinalIgnoreCase) -ge 0) { return '1' }
    if ($text.IndexOf('Bluetooth', [StringComparison]::OrdinalIgnoreCase) -ge 0) { return '10' }
    if ($text.IndexOf('WirelessWan', [StringComparison]::OrdinalIgnoreCase) -ge 0) { return '8' }
    if ($text.IndexOf('WiMax', [StringComparison]::OrdinalIgnoreCase) -ge 0) { return '12' }

    return $text
}

function Test-NetworkAdapterKindWeak {
    param([string]$Kind)

    $text = Get-Text $Kind
    return ([string]::IsNullOrWhiteSpace($text) -or
            $text -ieq 'OtherOrUnknown' -or
            $text -ieq 'EthernetOrUnknown')
}

function Get-NetworkAdapterKind {
    param(
        [string]$NdisPhysicalMediumText,
        [string]$NdisMediumText
    )

    $ndisPhysicalMedium = [uint32]0
    if (Try-ParseNetworkUInt32 -Value (Normalize-NetworkNdisValue $NdisPhysicalMediumText) -Result ([ref]$ndisPhysicalMedium)) {
        switch ($ndisPhysicalMedium) {
            1  { return 'WiFi' }
            9  { return 'WiFi' }
            14 { return 'WiredEthernet' }
            10 { return 'Bluetooth' }
            8  { return 'WirelessWAN' }
            12 { return 'WiMAX' }
        }
    }

    $ndisMedium = [uint32]0
    if (Try-ParseNetworkUInt32 -Value (Normalize-NetworkNdisValue $NdisMediumText) -Result ([ref]$ndisMedium)) {
        if ($ndisMedium -eq 16) { return 'WiFi' }
        if ($ndisMedium -eq 0) { return 'EthernetOrUnknown' }
    }

    return 'OtherOrUnknown'
}

function Get-NetworkAdapterKindFromMedia {
    param(
        [string]$NdisPhysicalMediumText,
        [string]$NdisMediumText,
        [string]$AdapterTypeIdText
    )

    $baseKind = Get-NetworkAdapterKind -NdisPhysicalMediumText (Normalize-NetworkNdisValue $NdisPhysicalMediumText) -NdisMediumText (Normalize-NetworkNdisValue $NdisMediumText)
    if (-not (Test-NetworkAdapterKindWeak $baseKind)) { return $baseKind }

    $adapterTypeId = [uint32]0
    if (Try-ParseNetworkUInt32 -Value $AdapterTypeIdText -Result ([ref]$adapterTypeId)) {
        switch ($adapterTypeId) {
            9  { return 'WiFi' }
            0  { return 'WiredEthernet' }
            3  { return 'WirelessWAN' }
            10 { return 'Bluetooth' }
        }
    }

    if ($baseKind -ieq 'EthernetOrUnknown') { return 'WiredEthernet' }
    return 'OtherOrUnknown'
}

function New-AdapterInfo {
    param(
        [object]$Adapter,
        [string]$Source = ''
    )

    $name = First-Text `
        (Get-ObjectPropertyText -Object $Adapter -Name 'InterfaceDescription') `
        (Get-ObjectPropertyText -Object $Adapter -Name 'Name') `
        (Get-ObjectPropertyText -Object $Adapter -Name 'NetConnectionID')

    $pnpId = Get-ObjectPropertyText -Object $Adapter -Name 'PNPDeviceID'
    $adapterTypeId = Get-ObjectPropertyText -Object $Adapter -Name 'AdapterTypeID'
    $ndisPhysicalMedium = Normalize-NetworkNdisValue (Get-ObjectPropertyText -Object $Adapter -Name 'NdisPhysicalMedium')
    $ndisMedium = Normalize-NetworkNdisValue (Get-ObjectPropertyText -Object $Adapter -Name 'NdisMedium')
    $mediaSource = ''
    if (-not [string]::IsNullOrWhiteSpace($ndisPhysicalMedium) -or -not [string]::IsNullOrWhiteSpace($ndisMedium)) {
        $mediaSource = Get-Text $Source
    }

    [pscustomobject]@{
        Name                 = $name
        InterfaceDescription = First-Text (Get-ObjectPropertyText -Object $Adapter -Name 'InterfaceDescription') $name
        PNPDeviceID          = $pnpId
        AdapterTypeID        = $adapterTypeId
        NdisPhysicalMedium   = $ndisPhysicalMedium
        NdisMedium           = $ndisMedium
        NdisMediaSource      = $mediaSource
        NetworkAdapterKind   = Get-NetworkAdapterKindFromMedia -NdisPhysicalMediumText $ndisPhysicalMedium -NdisMediumText $ndisMedium -AdapterTypeIdText $adapterTypeId
    }
}

function Merge-AdapterInfo {
    param(
        [object]$Target,
        [object]$Source
    )

    if ($null -eq $Target -or $null -eq $Source) { return }

    foreach ($name in @('AdapterTypeID','NdisPhysicalMedium','NdisMedium','NdisMediaSource')) {
        $current = Get-Text $Target.$name
        $incoming = Get-Text $Source.$name
        if ([string]::IsNullOrWhiteSpace($current) -and -not [string]::IsNullOrWhiteSpace($incoming)) {
            $Target.$name = $incoming
        }
    }

    $Target.NetworkAdapterKind = Get-NetworkAdapterKindFromMedia -NdisPhysicalMediumText $Target.NdisPhysicalMedium -NdisMediumText $Target.NdisMedium -AdapterTypeIdText $Target.AdapterTypeID
}

function Remove-DuplicateAdaptersByPnpId {
    param([object[]]$Adapters)

    $seen = @{}
    $result = @()

    foreach ($adapter in @($Adapters)) {
        if ($null -eq $adapter) { continue }
        $pnp = Get-Text $adapter.PNPDeviceID
        if ([string]::IsNullOrWhiteSpace($pnp)) { continue }

        $key = $pnp.ToUpperInvariant()
        if ($seen.ContainsKey($key)) { continue }

        $seen[$key] = $true
        $result += $adapter
    }

    return @($result)
}

function Get-PhysicalNetworkAdapters {
    $candidates = @()
    $win32Infos = @()

    $win32Adapters = Invoke-AdapterQuery -Namespace 'root\cimv2' -ClassName 'Win32_NetworkAdapter' -Filter 'PhysicalAdapter=True'
    foreach ($adapter in @($win32Adapters)) {
        if (-not (Test-PhysicalAdapter $adapter)) { continue }
        $win32Infos += New-AdapterInfo -Adapter $adapter -Source 'Win32_NetworkAdapter'
    }

    $msftAdapters = Invoke-AdapterQuery -Namespace 'root\StandardCimv2' -ClassName 'MSFT_NetAdapter' -Filter 'Virtual=False'
    foreach ($adapter in @($msftAdapters)) {
        if (-not (Test-PhysicalAdapter $adapter)) { continue }
        $candidates += New-AdapterInfo -Adapter $adapter -Source 'MSFT_NetAdapter'
    }

    $candidates = Remove-DuplicateAdaptersByPnpId $candidates
    $win32Infos = Remove-DuplicateAdaptersByPnpId $win32Infos

    if (@($candidates).Count -gt 0) {
        $win32ByPnp = @{}
        $win32ByName = @{}
        foreach ($info in @($win32Infos)) {
            $pnp = Get-Text $info.PNPDeviceID
            if (-not [string]::IsNullOrWhiteSpace($pnp)) { $win32ByPnp[$pnp.ToUpperInvariant()] = $info }

            $name = Get-Text $info.Name
            if (-not [string]::IsNullOrWhiteSpace($name)) { $win32ByName[$name.ToUpperInvariant()] = $info }
        }

        foreach ($candidate in @($candidates)) {
            $match = $null
            $pnp = Get-Text $candidate.PNPDeviceID
            if (-not [string]::IsNullOrWhiteSpace($pnp)) { $match = $win32ByPnp[$pnp.ToUpperInvariant()] }

            if ($null -eq $match) {
                $name = Get-Text $candidate.Name
                if (-not [string]::IsNullOrWhiteSpace($name)) { $match = $win32ByName[$name.ToUpperInvariant()] }
            }

            if ($null -ne $match) { Merge-AdapterInfo -Target $candidate -Source $match }
        }

        return @($candidates)
    }

    return @($win32Infos)
}

function Write-NetworkAdapterDetection {
    param([object]$Result)

    $driver = First-Text $Result.DriverModel 'NDIS'
    $driverDisplay = 'NDIS'
    if ($driver -ieq 'NetAdapterCx') { $driverDisplay = 'NETADAPTERCX' }

    $kind = First-Text $Result.NetworkAdapterKind 'OtherOrUnknown'
    $physical = First-Text $Result.NdisPhysicalMedium '<none>'
    $medium = First-Text $Result.NdisMedium '<none>'
    $adapterTypeId = First-Text $Result.AdapterTypeID '<none>'
    $source = First-Text $Result.NdisMediaSource '<none>'

    Write-Output ('Driver     : {0}' -f $driverDisplay)
    Write-Output ('Media      : {0}' -f $kind)
    Write-Output ('NDIS media : NdisPhysicalMedium={0}, NdisMedium={1}, AdapterTypeID={2}, Source={3}' -f $physical, $medium, $adapterTypeId, $source)
}

function Get-RegistryStringValue {
    param(
        [string]$Path,
        [string]$Name
    )

    try {
        $item = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop
        return Get-Text $item.$Name
    } catch {
        return ''
    }
}

function Convert-HklmProviderPathToRegPath {
    param([string]$Path)

    $text = Get-Text $Path
    if ($text -match '^HKLM:\\') {
        return ('HKEY_LOCAL_MACHINE\' + $text.Substring(6))
    }
    return $text
}

function Convert-HklmProviderPathToSubKey {
    param([string]$Path)

    $text = Get-Text $Path
    if ($text -notmatch '^HKLM:\\(.+)$') {
        throw ('Unsupported registry path: {0}' -f $Path)
    }

    return $Matches[1]
}

function Resolve-NetworkDriverImagePath {
    param([string]$ImagePath)

    $resolved = Get-Text $ImagePath
    if ([string]::IsNullOrWhiteSpace($resolved)) { return '' }

    try { $resolved = [Environment]::ExpandEnvironmentVariables($resolved) } catch { }

    if ($resolved.StartsWith('"')) {
        $closing = $resolved.IndexOf('"', 1)
        if ($closing -gt 1) { $resolved = $resolved.Substring(1, $closing - 1) }
    } else {
        $sysIndex = $resolved.IndexOf('.sys', [StringComparison]::OrdinalIgnoreCase)
        if ($sysIndex -ge 0) {
            $resolved = $resolved.Substring(0, $sysIndex + 4)
        } elseif ($resolved.Contains(' ')) {
            $resolved = ($resolved -split '\s+', 2)[0]
        }
    }

    try {
        $systemRoot = [Environment]::GetFolderPath([Environment+SpecialFolder]::Windows)
        if ([string]::IsNullOrWhiteSpace($systemRoot)) { $systemRoot = $env:windir }

        if ($resolved.StartsWith('\SystemRoot', [StringComparison]::OrdinalIgnoreCase)) {
            $resolved = $systemRoot + $resolved.Substring('\SystemRoot'.Length)
        } elseif ($resolved.StartsWith('System32', [StringComparison]::OrdinalIgnoreCase)) {
            $resolved = Join-Path $systemRoot $resolved
        } elseif ($resolved.StartsWith('\??\', [StringComparison]::OrdinalIgnoreCase)) {
            $resolved = $resolved.Substring(4)
        }

        $resolved = $resolved.Replace('%SystemRoot%', $systemRoot).Replace('%systemroot%', $systemRoot)
    } catch { }

    return $resolved
}

function Get-NetworkDriverTypeFromBinary {
    param([string]$ResolvedPath)

    if ([string]::IsNullOrWhiteSpace($ResolvedPath) -or -not (Test-Path -LiteralPath $ResolvedPath)) { return 'NDIS' }

    $stream = $null
    try {
        $stream = [System.IO.File]::Open($ResolvedPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $bytesToRead = [int][Math]::Min($stream.Length, 1048576L)
        if ($bytesToRead -le 0) { return 'NDIS' }

        $buffer = New-Object byte[] $bytesToRead
        $offset = 0
        while ($offset -lt $bytesToRead) {
            $read = $stream.Read($buffer, $offset, $bytesToRead - $offset)
            if ($read -le 0) { break }
            $offset += $read
        }

        $text = [System.Text.Encoding]::ASCII.GetString($buffer, 0, $offset)
        if ($text.IndexOf('NetAdapter', [StringComparison]::OrdinalIgnoreCase) -ge 0) { return 'NetAdapterCx' }
    } catch {
    } finally {
        if ($null -ne $stream) { $stream.Close() }
    }

    return 'NDIS'
}

function Resolve-AdapterClassPath {
    param([object]$Adapter)

    $pnpId = Get-Text $Adapter.PNPDeviceID
    if ([string]::IsNullOrWhiteSpace($pnpId)) { return $null }

    $enumPath = 'HKLM:\SYSTEM\CurrentControlSet\Enum\' + $pnpId
    $driver = Get-RegistryStringValue -Path $enumPath -Name 'Driver'
    if ([string]::IsNullOrWhiteSpace($driver)) { return $null }

    $classProviderPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\' + $driver
    if (-not (Test-Path -LiteralPath $classProviderPath)) { return $null }

    $service = Get-RegistryStringValue -Path ($classProviderPath + '\Ndi') -Name 'Service'
    if (-not [string]::IsNullOrWhiteSpace($service)) { $service = $service.TrimEnd('.').Trim() }

    $servicePath = ''
    $imagePath = ''
    if (-not [string]::IsNullOrWhiteSpace($service)) {
        $servicePath = 'HKLM:\SYSTEM\CurrentControlSet\Services\' + $service
        $imagePath = Get-RegistryStringValue -Path $servicePath -Name 'ImagePath'
    }

    $resolvedImagePath = Resolve-NetworkDriverImagePath -ImagePath $imagePath
    $driverModel = Get-NetworkDriverTypeFromBinary -ResolvedPath $resolvedImagePath
    $adapterKind = Get-NetworkAdapterKindFromMedia -NdisPhysicalMediumText $Adapter.NdisPhysicalMedium -NdisMediumText $Adapter.NdisMedium -AdapterTypeIdText $Adapter.AdapterTypeID

    [pscustomobject]@{
        Name               = Get-Text $Adapter.Name
        PNPDeviceID        = $pnpId
        DriverModel        = $driverModel
        NetworkAdapterKind = $adapterKind
        NdisPhysicalMedium = Normalize-NetworkNdisValue $Adapter.NdisPhysicalMedium
        NdisMedium         = Normalize-NetworkNdisValue $Adapter.NdisMedium
        NdisMediaSource    = Get-Text $Adapter.NdisMediaSource
        AdapterTypeID      = Get-Text $Adapter.AdapterTypeID
        Service            = $service
        ServicePath        = $servicePath
        ImagePath          = $imagePath
        ResolvedImagePath  = $resolvedImagePath
        ProviderPath       = $classProviderPath
        ProviderClassPath  = $classProviderPath
        ClassPath          = Convert-HklmProviderPathToRegPath $classProviderPath
    }
}


function Test-RegistryValueMatches {
    param(
        [object]$CurrentValue,
        [object]$ExpectedValue,
        [Microsoft.Win32.RegistryValueKind]$Kind
    )

    try {
        switch ($Kind) {
            ([Microsoft.Win32.RegistryValueKind]::DWord) { return ([int]$CurrentValue -eq [int]$ExpectedValue) }
            ([Microsoft.Win32.RegistryValueKind]::QWord)  { return ([long]$CurrentValue -eq [long]$ExpectedValue) }
            ([Microsoft.Win32.RegistryValueKind]::MultiString) {
                $currentItems = @($CurrentValue)
                $expectedItems = @($ExpectedValue)
                if ($currentItems.Count -ne $expectedItems.Count) { return $false }
                for ($i = 0; $i -lt $currentItems.Count; $i++) {
                    if ([string]$currentItems[$i] -ne [string]$expectedItems[$i]) { return $false }
                }
                return $true
            }
            default { return ([string]$CurrentValue -eq [string]$ExpectedValue) }
        }
    } catch {
        return $false
    }
}

function Set-AdapterRegistryValue {
    param(
        [string]$Path,
        [string]$Name,
        [string]$Value
    )

    $subKey = Convert-HklmProviderPathToSubKey -Path $Path
    $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($subKey, $true)
    if ($null -eq $key) {
        throw ('Could not open registry key for writing: HKLM:\{0}' -f $subKey)
    }

    try {
        $currentValue = $key.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        $exists = $null -ne $currentValue
        if ($exists) {
            $kind = $key.GetValueKind($Name)
        } else {
            $kind = [Microsoft.Win32.RegistryValueKind]::String
        }

        switch ($kind) {
            ([Microsoft.Win32.RegistryValueKind]::DWord) {
                $typedValue = [int]$Value
                break
            }
            ([Microsoft.Win32.RegistryValueKind]::QWord) {
                $typedValue = [long]$Value
                break
            }
            ([Microsoft.Win32.RegistryValueKind]::MultiString) {
                $typedValue = [string[]]@($Value)
                break
            }
            default {
                $typedValue = [string]$Value
                if ($kind -eq [Microsoft.Win32.RegistryValueKind]::Unknown -or $kind -eq [Microsoft.Win32.RegistryValueKind]::Binary) {
                    $kind = [Microsoft.Win32.RegistryValueKind]::String
                }
                break
            }
        }

        if ($exists -and (Test-RegistryValueMatches -CurrentValue $currentValue -ExpectedValue $typedValue -Kind $kind)) {
            return 'unchanged'
        }

        $key.SetValue($Name, $typedValue, $kind)

        if ($exists) { return 'updated' }
        return 'created'
    } finally {
        $key.Close()
    }
}


function Set-HklmDwordRegistryValue {
    param(
        [string]$Path,
        [string]$Name,
        [int]$Value
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        try { New-Item -Path $Path -Force | Out-Null }
        catch {
            Invoke-AsTrustedInstaller { New-Item -Path $using:Path -Force | Out-Null } | Out-Null
            if (-not (Test-Path -LiteralPath $Path)) { throw $_ }
        }
    }

    $exists = $false
    $currentValue = $null
    try {
        $item = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop
        if ($null -ne $item.$Name) {
            $exists = $true
            $currentValue = $item.$Name
        }
    } catch { }

    if ($exists) {
        try {
            if ([int]$currentValue -eq [int]$Value) { return 'unchanged' }
        } catch { }
    }

    try {
        New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType DWord -Force -ErrorAction Stop | Out-Null
    } catch {
        $tiPath = $Path; $tiName = $Name; $tiValue = $Value
        $tiOk = Invoke-AsTrustedInstaller {
            New-ItemProperty -LiteralPath $using:tiPath -Name $using:tiName -Value $using:tiValue -PropertyType DWord -Force -ErrorAction Stop | Out-Null
        }
        if (-not $tiOk) { throw $_ }
    }

    if ($exists) { return 'updated' }
    return 'created'
}

function Invoke-NetOffloadGlobalSettings {
    $failures = @()

    $commands = @(
        [pscustomobject]@{
            Name        = 'ReceiveSegmentCoalescing'
            Value       = 'Enable'
            CommandText = 'Set-NetOffloadGlobalSetting -ReceiveSegmentCoalescing Enable'
            ScriptBlock = { Set-NetOffloadGlobalSetting -ReceiveSegmentCoalescing Enable -ErrorAction Stop }
        },
        [pscustomobject]@{
            Name        = 'PacketCoalescingFilter'
            Value       = 'Disable'
            CommandText = 'Set-NetOffloadGlobalSetting -PacketCoalescingFilter Disable'
            ScriptBlock = { Set-NetOffloadGlobalSetting -PacketCoalescingFilter Disable -ErrorAction Stop }
        }
    )

    foreach ($command in $commands) {
        try {
            & $command.ScriptBlock
            Write-Host ('Global     : {0} applied' -f $command.CommandText)
        } catch {
            $failures += New-FailureRecord `
                -Area 'Global' `
                -Operation $command.CommandText `
                -Name $command.Name `
                -Value $command.Value `
                -ErrorRecord $_
        }
    }

    return @($failures)
}

function Invoke-NdisParameterDwordSettings {
    param([object[]]$Settings)

    $path = 'HKLM:\SYSTEM\CurrentControlSet\Services\NDIS\Parameters'
    $created = 0
    $updated = 0
    $unchanged = 0
    $failures = @()

    foreach ($setting in @($Settings)) {
        try {
            $action = Set-HklmDwordRegistryValue -Path $path -Name $setting.Name -Value ([int]$setting.Value)
            switch ($action) {
                'created' {
                    $created++
                    break
                }
                'updated' {
                    $updated++
                    break
                }
                'unchanged' {
                    $unchanged++
                    break
                }
                default {
                    $updated++
                    break
                }
            }
        } catch {
            $failures += New-FailureRecord `
                -Area 'NDIS' `
                -Operation 'Set HKLM DWORD registry value' `
                -Path $path `
                -Name $setting.Name `
                -Value $setting.Value `
                -ErrorRecord $_
        }
    }

    Write-Host ('NDIS       : HKLM\SYSTEM\CurrentControlSet\Services\NDIS\Parameters DWORDs created={0}, updated={1}, unchanged={2}, failed={3}' -f $created, $updated, $unchanged, $failures.Count)
    return @($failures)
}

if (-not (Test-IsElevated)) {
    Write-Warning 'This script writes to HKLM and should be run as Administrator.'
}

$results = @()
foreach ($adapter in @(Get-PhysicalNetworkAdapters)) {
    $resolved = Resolve-AdapterClassPath -Adapter $adapter
    if ($null -ne $resolved) { $results += $resolved }
}

if ($results.Count -eq 0) {
    Write-Error 'No physical network adapter class path was found.'
    exit 1
}

$wiredResults = @($results | Where-Object { (First-Text $_.NetworkAdapterKind 'OtherOrUnknown') -ieq 'WiredEthernet' })
$adapterMediaFailures = 0
$errors = @()

if ($wiredResults.Count -gt 0) {
    $errors += Invoke-NetOffloadGlobalSettings
    $errors += Invoke-NdisParameterDwordSettings -Settings $NdisParameterDwordSettings
    Write-Output ''
} else {
    Write-Output 'SKIPPED    : Optimize networking was not applied because no adapter Media is WiredEthernet.'
    Write-Output ''
}

$totalCreated = 0
$totalUpdated = 0
$totalUnchanged = 0

foreach ($result in $results) {
    Write-Output ('Name       : {0}' -f $result.Name)
    Write-NetworkAdapterDetection -Result $result
    Write-Output ('CLASS_PATH : {0}' -f $result.ClassPath)

    $created = 0
    $updated = 0
    $unchanged = 0
    $media = First-Text $result.NetworkAdapterKind 'OtherOrUnknown'

    if ($media -ine 'WiredEthernet') {
        $adapterMediaFailures++
        Write-Output ('SKIPPED    : Optimize networking was not applied because Media is {0}, not WiredEthernet.' -f $media)
        Write-Output ('Values     : created=0, updated=0, unchanged=0')
        Write-Output ''
        continue
    }

    foreach ($setting in $AdapterRegistrySettings) {
        try {
            $action = Set-AdapterRegistryValue -Path $result.ProviderClassPath -Name $setting.Name -Value $setting.Value
            switch ($action) {
                'created' {
                    $created++
                    $totalCreated++
                    break
                }
                'updated' {
                    $updated++
                    $totalUpdated++
                    break
                }
                'unchanged' {
                    $unchanged++
                    $totalUnchanged++
                    break
                }
                default {
                    $updated++
                    $totalUpdated++
                    break
                }
            }
        } catch {
            $errors += New-FailureRecord `
                -Area 'Adapter' `
                -Operation 'Set adapter registry value' `
                -Path $result.ClassPath `
                -Name $setting.Name `
                -Value $setting.Value `
                -ErrorRecord $_
        }
    }

    Write-Output ('Values     : created={0}, updated={1}, unchanged={2}' -f $created, $updated, $unchanged)
    Write-Output ''
}

$totalFailed = $errors.Count
Write-Output ('Total      : adapters={0}, created={1}, updated={2}, unchanged={3}, skipped={4}, failed={5}' -f $results.Count, $totalCreated, $totalUpdated, $totalUnchanged, $adapterMediaFailures, $totalFailed)

if ($errors.Count -gt 0) {
    Write-FailureReport -Failures $errors
}

if ($totalFailed -gt 0) { exit 2 }

exit 0
'@

$RemoveNetworkOptimizationPayload = @'
$ErrorActionPreference = 'Stop'

function Get-Text {
    param([object]$Value)

    if ($null -eq $Value) { return '' }

    if ($Value -is [System.Array]) {
        foreach ($item in $Value) {
            $text = Get-Text $item
            if (-not [string]::IsNullOrWhiteSpace($text)) { return $text }
        }
        return ''
    }

    return ([string]$Value).Trim()
}

function First-Text {
    foreach ($item in $args) {
        $text = Get-Text $item
        if (-not [string]::IsNullOrWhiteSpace($text)) { return $text }
    }
    return ''
}

function Test-Administrator {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]::new($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Invoke-AdapterQuery {
    param(
        [string]$Namespace,
        [string]$ClassName,
        [string]$Filter
    )

    try {
        if (Get-Command Get-CimInstance -ErrorAction SilentlyContinue) {
            return @(Get-CimInstance -Namespace $Namespace -ClassName $ClassName -Filter $Filter -ErrorAction Stop)
        }
    } catch { }

    try {
        return @(Get-WmiObject -Namespace $Namespace -Class $ClassName -Filter $Filter -ErrorAction Stop)
    } catch { }

    return @()
}

function Test-PhysicalAdapter {
    param([object]$Adapter)

    if ($null -eq $Adapter) { return $false }
    if ([string]::IsNullOrWhiteSpace((Get-Text $Adapter.PNPDeviceID))) { return $false }

    try {
        if ($null -ne $Adapter.Virtual -and [bool]$Adapter.Virtual) { return $false }
    } catch { }

    try {
        if ($null -ne $Adapter.HardwareInterface -and -not [bool]$Adapter.HardwareInterface) { return $false }
    } catch { }

    try {
        if ($null -ne $Adapter.PhysicalAdapter -and -not [bool]$Adapter.PhysicalAdapter) { return $false }
    } catch { }

    return $true
}

function Get-ObjectPropertyValue {
    param(
        [object]$Object,
        [string]$Name
    )

    if ($null -eq $Object -or [string]::IsNullOrWhiteSpace($Name)) { return $null }

    try {
        $property = $Object.PSObject.Properties[$Name]
        if ($null -ne $property) { return $property.Value }
    } catch { }

    try {
        return $Object.$Name
    } catch {
        return $null
    }
}

function Get-ObjectPropertyText {
    param(
        [object]$Object,
        [string]$Name
    )

    return Get-Text (Get-ObjectPropertyValue -Object $Object -Name $Name)
}

function Try-ParseNetworkUInt32 {
    param(
        [string]$Value,
        [ref]$Result
    )

    $Result.Value = [uint32]0
    $text = Get-Text $Value
    if ([string]::IsNullOrWhiteSpace($text)) { return $false }

    if ($text -ieq '<none>' -or $text -ieq 'none' -or $text -ieq '<empty>' -or $text -ieq 'unknown') { return $false }

    if ($text.Contains('/')) {
        $text = ($text -split '/', 2)[0].Trim()
    }

    try {
        $Result.Value = [Convert]::ToUInt32($text, [System.Globalization.CultureInfo]::InvariantCulture)
        return $true
    } catch {
        return $false
    }
}

function Normalize-NetworkNdisValue {
    param([string]$Value)

    $text = Get-Text $Value
    if ([string]::IsNullOrWhiteSpace($text)) { return '' }

    if ($text -ieq '<none>' -or
        $text -ieq 'none' -or
        $text -ieq '<empty>' -or
        $text -ieq 'unknown' -or
        $text -ieq 'OtherOrUnknown') { return '' }

    $parsed = [uint32]0
    if (Try-ParseNetworkUInt32 -Value $text -Result ([ref]$parsed)) {
        return $parsed.ToString([System.Globalization.CultureInfo]::InvariantCulture)
    }

    if ($text.IndexOf('NdisMediumNative802_11', [StringComparison]::OrdinalIgnoreCase) -ge 0) { return '16' }
    if ($text.IndexOf('NdisPhysicalMediumNative802_11', [StringComparison]::OrdinalIgnoreCase) -ge 0) { return '9' }
    if ($text.IndexOf('Native802_11', [StringComparison]::OrdinalIgnoreCase) -ge 0) { return '9' }
    if ($text.IndexOf('WirelessLan', [StringComparison]::OrdinalIgnoreCase) -ge 0) { return '1' }
    if ($text.IndexOf('Bluetooth', [StringComparison]::OrdinalIgnoreCase) -ge 0) { return '10' }
    if ($text.IndexOf('WirelessWan', [StringComparison]::OrdinalIgnoreCase) -ge 0) { return '8' }
    if ($text.IndexOf('WiMax', [StringComparison]::OrdinalIgnoreCase) -ge 0) { return '12' }

    return $text
}

function Test-NetworkAdapterKindWeak {
    param([string]$Kind)

    $text = Get-Text $Kind
    return ([string]::IsNullOrWhiteSpace($text) -or
            $text -ieq 'OtherOrUnknown' -or
            $text -ieq 'EthernetOrUnknown')
}

function Get-NetworkAdapterKind {
    param(
        [string]$NdisPhysicalMediumText,
        [string]$NdisMediumText
    )

    $ndisPhysicalMedium = [uint32]0
    if (Try-ParseNetworkUInt32 -Value (Normalize-NetworkNdisValue $NdisPhysicalMediumText) -Result ([ref]$ndisPhysicalMedium)) {
        switch ($ndisPhysicalMedium) {
            1  { return 'WiFi' }
            9  { return 'WiFi' }
            14 { return 'WiredEthernet' }
            10 { return 'Bluetooth' }
            8  { return 'WirelessWAN' }
            12 { return 'WiMAX' }
        }
    }

    $ndisMedium = [uint32]0
    if (Try-ParseNetworkUInt32 -Value (Normalize-NetworkNdisValue $NdisMediumText) -Result ([ref]$ndisMedium)) {
        if ($ndisMedium -eq 16) { return 'WiFi' }
        if ($ndisMedium -eq 0) { return 'EthernetOrUnknown' }
    }

    return 'OtherOrUnknown'
}

function Get-NetworkAdapterKindFromMedia {
    param(
        [string]$NdisPhysicalMediumText,
        [string]$NdisMediumText,
        [string]$AdapterTypeIdText
    )

    $baseKind = Get-NetworkAdapterKind -NdisPhysicalMediumText (Normalize-NetworkNdisValue $NdisPhysicalMediumText) -NdisMediumText (Normalize-NetworkNdisValue $NdisMediumText)
    if (-not (Test-NetworkAdapterKindWeak $baseKind)) { return $baseKind }

    $adapterTypeId = [uint32]0
    if (Try-ParseNetworkUInt32 -Value $AdapterTypeIdText -Result ([ref]$adapterTypeId)) {
        switch ($adapterTypeId) {
            9  { return 'WiFi' }
            0  { return 'WiredEthernet' }
            3  { return 'WirelessWAN' }
            10 { return 'Bluetooth' }
        }
    }

    if ($baseKind -ieq 'EthernetOrUnknown') { return 'WiredEthernet' }
    return 'OtherOrUnknown'
}

function New-AdapterInfo {
    param(
        [object]$Adapter,
        [string]$Source = ''
    )

    $name = First-Text `
        (Get-ObjectPropertyText -Object $Adapter -Name 'InterfaceDescription') `
        (Get-ObjectPropertyText -Object $Adapter -Name 'Name') `
        (Get-ObjectPropertyText -Object $Adapter -Name 'NetConnectionID')

    $pnpId = Get-ObjectPropertyText -Object $Adapter -Name 'PNPDeviceID'
    $adapterTypeId = Get-ObjectPropertyText -Object $Adapter -Name 'AdapterTypeID'
    $ndisPhysicalMedium = Normalize-NetworkNdisValue (Get-ObjectPropertyText -Object $Adapter -Name 'NdisPhysicalMedium')
    $ndisMedium = Normalize-NetworkNdisValue (Get-ObjectPropertyText -Object $Adapter -Name 'NdisMedium')
    $mediaSource = ''
    if (-not [string]::IsNullOrWhiteSpace($ndisPhysicalMedium) -or -not [string]::IsNullOrWhiteSpace($ndisMedium)) {
        $mediaSource = Get-Text $Source
    }

    [pscustomobject]@{
        Name                 = $name
        InterfaceDescription = First-Text (Get-ObjectPropertyText -Object $Adapter -Name 'InterfaceDescription') $name
        PNPDeviceID          = $pnpId
        AdapterTypeID        = $adapterTypeId
        NdisPhysicalMedium   = $ndisPhysicalMedium
        NdisMedium           = $ndisMedium
        NdisMediaSource      = $mediaSource
        NetworkAdapterKind   = Get-NetworkAdapterKindFromMedia -NdisPhysicalMediumText $ndisPhysicalMedium -NdisMediumText $ndisMedium -AdapterTypeIdText $adapterTypeId
    }
}

function Merge-AdapterInfo {
    param(
        [object]$Target,
        [object]$Source
    )

    if ($null -eq $Target -or $null -eq $Source) { return }

    foreach ($name in @('AdapterTypeID','NdisPhysicalMedium','NdisMedium','NdisMediaSource')) {
        $current = Get-Text $Target.$name
        $incoming = Get-Text $Source.$name
        if ([string]::IsNullOrWhiteSpace($current) -and -not [string]::IsNullOrWhiteSpace($incoming)) {
            $Target.$name = $incoming
        }
    }

    $Target.NetworkAdapterKind = Get-NetworkAdapterKindFromMedia -NdisPhysicalMediumText $Target.NdisPhysicalMedium -NdisMediumText $Target.NdisMedium -AdapterTypeIdText $Target.AdapterTypeID
}

function Remove-DuplicateAdaptersByPnpId {
    param([object[]]$Adapters)

    $seen = @{}
    $result = @()

    foreach ($adapter in @($Adapters)) {
        if ($null -eq $adapter) { continue }
        $pnp = Get-Text $adapter.PNPDeviceID
        if ([string]::IsNullOrWhiteSpace($pnp)) { continue }

        $key = $pnp.ToUpperInvariant()
        if ($seen.ContainsKey($key)) { continue }

        $seen[$key] = $true
        $result += $adapter
    }

    return @($result)
}

function Get-PhysicalNetworkAdapters {
    $candidates = @()
    $win32Infos = @()

    $win32Adapters = Invoke-AdapterQuery -Namespace 'root\cimv2' -ClassName 'Win32_NetworkAdapter' -Filter 'PhysicalAdapter=True'
    foreach ($adapter in @($win32Adapters)) {
        if (-not (Test-PhysicalAdapter $adapter)) { continue }
        $win32Infos += New-AdapterInfo -Adapter $adapter -Source 'Win32_NetworkAdapter'
    }

    $msftAdapters = Invoke-AdapterQuery -Namespace 'root\StandardCimv2' -ClassName 'MSFT_NetAdapter' -Filter 'Virtual=False'
    foreach ($adapter in @($msftAdapters)) {
        if (-not (Test-PhysicalAdapter $adapter)) { continue }
        $candidates += New-AdapterInfo -Adapter $adapter -Source 'MSFT_NetAdapter'
    }

    $candidates = Remove-DuplicateAdaptersByPnpId $candidates
    $win32Infos = Remove-DuplicateAdaptersByPnpId $win32Infos

    if (@($candidates).Count -gt 0) {
        $win32ByPnp = @{}
        $win32ByName = @{}
        foreach ($info in @($win32Infos)) {
            $pnp = Get-Text $info.PNPDeviceID
            if (-not [string]::IsNullOrWhiteSpace($pnp)) { $win32ByPnp[$pnp.ToUpperInvariant()] = $info }

            $name = Get-Text $info.Name
            if (-not [string]::IsNullOrWhiteSpace($name)) { $win32ByName[$name.ToUpperInvariant()] = $info }
        }

        foreach ($candidate in @($candidates)) {
            $match = $null
            $pnp = Get-Text $candidate.PNPDeviceID
            if (-not [string]::IsNullOrWhiteSpace($pnp)) { $match = $win32ByPnp[$pnp.ToUpperInvariant()] }

            if ($null -eq $match) {
                $name = Get-Text $candidate.Name
                if (-not [string]::IsNullOrWhiteSpace($name)) { $match = $win32ByName[$name.ToUpperInvariant()] }
            }

            if ($null -ne $match) { Merge-AdapterInfo -Target $candidate -Source $match }
        }

        return @($candidates)
    }

    return @($win32Infos)
}

function Write-NetworkAdapterDetection {
    param([object]$Result)

    $driver = First-Text $Result.DriverModel 'NDIS'
    $driverDisplay = 'NDIS'
    if ($driver -ieq 'NetAdapterCx') { $driverDisplay = 'NETADAPTERCX' }

    $kind = First-Text $Result.NetworkAdapterKind 'OtherOrUnknown'
    $physical = First-Text $Result.NdisPhysicalMedium '<none>'
    $medium = First-Text $Result.NdisMedium '<none>'
    $adapterTypeId = First-Text $Result.AdapterTypeID '<none>'
    $source = First-Text $Result.NdisMediaSource '<none>'

    Write-Output ('Driver     : {0}' -f $driverDisplay)
    Write-Output ('Media      : {0}' -f $kind)
    Write-Output ('NDIS media : NdisPhysicalMedium={0}, NdisMedium={1}, AdapterTypeID={2}, Source={3}' -f $physical, $medium, $adapterTypeId, $source)
}

function Get-RegistryStringValue {
    param(
        [string]$Path,
        [string]$Name
    )

    try {
        $item = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop
        return Get-Text $item.$Name
    } catch {
        return ''
    }
}

function Convert-HklmProviderPathToRegPath {
    param([string]$Path)

    $text = Get-Text $Path
    if ($text -match '^HKLM:\\') {
        return ('HKEY_LOCAL_MACHINE\' + $text.Substring(6))
    }
    return $text
}

function Convert-HklmProviderPathToSubKey {
    param([string]$Path)

    $text = Get-Text $Path
    if ($text -notmatch '^HKLM:\\(.+)$') {
        throw ('Unsupported registry path: {0}' -f $Path)
    }

    return $Matches[1]
}

function Resolve-NetworkDriverImagePath {
    param([string]$ImagePath)

    $resolved = Get-Text $ImagePath
    if ([string]::IsNullOrWhiteSpace($resolved)) { return '' }

    try { $resolved = [Environment]::ExpandEnvironmentVariables($resolved) } catch { }

    if ($resolved.StartsWith('"')) {
        $closing = $resolved.IndexOf('"', 1)
        if ($closing -gt 1) { $resolved = $resolved.Substring(1, $closing - 1) }
    } else {
        $sysIndex = $resolved.IndexOf('.sys', [StringComparison]::OrdinalIgnoreCase)
        if ($sysIndex -ge 0) {
            $resolved = $resolved.Substring(0, $sysIndex + 4)
        } elseif ($resolved.Contains(' ')) {
            $resolved = ($resolved -split '\s+', 2)[0]
        }
    }

    try {
        $systemRoot = [Environment]::GetFolderPath([Environment+SpecialFolder]::Windows)
        if ([string]::IsNullOrWhiteSpace($systemRoot)) { $systemRoot = $env:windir }

        if ($resolved.StartsWith('\SystemRoot', [StringComparison]::OrdinalIgnoreCase)) {
            $resolved = $systemRoot + $resolved.Substring('\SystemRoot'.Length)
        } elseif ($resolved.StartsWith('System32', [StringComparison]::OrdinalIgnoreCase)) {
            $resolved = Join-Path $systemRoot $resolved
        } elseif ($resolved.StartsWith('\??\', [StringComparison]::OrdinalIgnoreCase)) {
            $resolved = $resolved.Substring(4)
        }

        $resolved = $resolved.Replace('%SystemRoot%', $systemRoot).Replace('%systemroot%', $systemRoot)
    } catch { }

    return $resolved
}

function Get-NetworkDriverTypeFromBinary {
    param([string]$ResolvedPath)

    if ([string]::IsNullOrWhiteSpace($ResolvedPath) -or -not (Test-Path -LiteralPath $ResolvedPath)) { return 'NDIS' }

    $stream = $null
    try {
        $stream = [System.IO.File]::Open($ResolvedPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $bytesToRead = [int][Math]::Min($stream.Length, 1048576L)
        if ($bytesToRead -le 0) { return 'NDIS' }

        $buffer = New-Object byte[] $bytesToRead
        $offset = 0
        while ($offset -lt $bytesToRead) {
            $read = $stream.Read($buffer, $offset, $bytesToRead - $offset)
            if ($read -le 0) { break }
            $offset += $read
        }

        $text = [System.Text.Encoding]::ASCII.GetString($buffer, 0, $offset)
        if ($text.IndexOf('NetAdapter', [StringComparison]::OrdinalIgnoreCase) -ge 0) { return 'NetAdapterCx' }
    } catch {
    } finally {
        if ($null -ne $stream) { $stream.Close() }
    }

    return 'NDIS'
}

function Resolve-AdapterClassPath {
    param([object]$Adapter)

    $pnpId = Get-Text $Adapter.PNPDeviceID
    if ([string]::IsNullOrWhiteSpace($pnpId)) { return $null }

    $enumPath = 'HKLM:\SYSTEM\CurrentControlSet\Enum\' + $pnpId
    $driver = Get-RegistryStringValue -Path $enumPath -Name 'Driver'
    if ([string]::IsNullOrWhiteSpace($driver)) { return $null }

    $classProviderPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\' + $driver
    if (-not (Test-Path -LiteralPath $classProviderPath)) { return $null }

    $service = Get-RegistryStringValue -Path ($classProviderPath + '\Ndi') -Name 'Service'
    if (-not [string]::IsNullOrWhiteSpace($service)) { $service = $service.TrimEnd('.').Trim() }

    $servicePath = ''
    $imagePath = ''
    if (-not [string]::IsNullOrWhiteSpace($service)) {
        $servicePath = 'HKLM:\SYSTEM\CurrentControlSet\Services\' + $service
        $imagePath = Get-RegistryStringValue -Path $servicePath -Name 'ImagePath'
    }

    $resolvedImagePath = Resolve-NetworkDriverImagePath -ImagePath $imagePath
    $driverModel = Get-NetworkDriverTypeFromBinary -ResolvedPath $resolvedImagePath
    $adapterKind = Get-NetworkAdapterKindFromMedia -NdisPhysicalMediumText $Adapter.NdisPhysicalMedium -NdisMediumText $Adapter.NdisMedium -AdapterTypeIdText $Adapter.AdapterTypeID

    [pscustomobject]@{
        Name               = Get-Text $Adapter.Name
        PNPDeviceID        = $pnpId
        DriverModel        = $driverModel
        NetworkAdapterKind = $adapterKind
        NdisPhysicalMedium = Normalize-NetworkNdisValue $Adapter.NdisPhysicalMedium
        NdisMedium         = Normalize-NetworkNdisValue $Adapter.NdisMedium
        NdisMediaSource    = Get-Text $Adapter.NdisMediaSource
        AdapterTypeID      = Get-Text $Adapter.AdapterTypeID
        Service            = $service
        ServicePath        = $servicePath
        ImagePath          = $imagePath
        ResolvedImagePath  = $resolvedImagePath
        ProviderPath       = $classProviderPath
        ProviderClassPath  = $classProviderPath
        ClassPath          = Convert-HklmProviderPathToRegPath $classProviderPath
    }
}


function Remove-DuplicateResolvedClassPaths {
    param([object[]]$ResolvedAdapters)

    $seen = @{}
    $result = @()

    foreach ($item in @($ResolvedAdapters)) {
        if ($null -eq $item) { continue }
        $key = (Get-Text $item.ProviderPath).ToUpperInvariant()
        if ([string]::IsNullOrWhiteSpace($key)) { continue }
        if ($seen.ContainsKey($key)) { continue }

        $seen[$key] = $true
        $result += $item
    }

    return @($result)
}

function Remove-HklmRegistryValuesExact {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string[]]$Names,
        [Parameter(Mandatory=$true)][string]$Label
    )

    $removed = 0
    $missing = 0
    $failed = 0
    $subKey = ''

    try {
        $subKey = Convert-HklmProviderPathToSubKey -Path $Path
        $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($subKey, $true)
    } catch {
        Write-Host ('FAILED : {0} -> {1}' -f $Path, $_.Exception.Message) -ForegroundColor Red
        return [pscustomobject]@{ Removed = 0; Missing = 0; Failed = @($Names).Count }
    }

    if ($null -eq $key) {
        Write-Host ('SKIPPED: {0} path not found: {1}' -f $Label, $Path) -ForegroundColor Yellow
        return [pscustomobject]@{ Removed = 0; Missing = @($Names).Count; Failed = 0 }
    }

    try {
        foreach ($name in @($Names)) {
            try {
                $value = $key.GetValue($name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                if ($null -ne $value) {
                    $key.DeleteValue($name, $false)
                    $removed++
                } else {
                    $missing++
                }
            } catch {
                $failed++
                Write-Host ('FAILED : {0}\{1} -> {2}' -f $Path, $name, $_.Exception.Message) -ForegroundColor Red
            }
        }
    } finally {
        $key.Close()
    }

    if ($failed -eq 0) {
        Write-Host ('SUCCESS: {0} removed={1}, missing={2}, failed={3}' -f $Label, $removed, $missing, $failed) -ForegroundColor Green
    } else {
        Write-Host ('FAILED : {0} removed={1}, missing={2}, failed={3}' -f $Label, $removed, $missing, $failed) -ForegroundColor Red
    }

    [pscustomobject]@{ Removed = $removed; Missing = $missing; Failed = $failed }
}

$AdapterValueNames = @(
    '*EncapsulatedPacketTaskOffloadNvgre',
    '*EncapsulatedPacketTaskOffloadVxlan',
    '*EncapsulatedPacketTaskOffload',
    '*IPChecksumOffloadIPv4',
    '*LsoV1IPv4',
    '*LsoV2IPv4',
    '*LsoV2IPv6',
    '*TCPChecksumOffloadIPv4',
    '*TCPChecksumOffloadIPv6',
    '*UDPChecksumOffloadIPv4',
    '*UDPChecksumOffloadIPv6',
    '*IPsecOffloadV1IPv4',
    '*IPsecOffloadV2',
    '*IPsecOffloadV2IPv4',
    '*TCPConnectionOffloadIPv4',
    '*TCPConnectionOffloadIPv6',
    '*TCPUDPChecksumOffloadIPv4',
    '*TCPUDPChecksumOffloadIPv6',
    '*UsoIPv4',
    '*UsoIPv6',
    'TeredoOffload',
    '*QoSOffload',
    '*Rss',
    '*NumRssQueues',
    'RssV2',
    '*VMQ',
    'VMQSupported',
    '*FlowControl',
    'FecMode',
    '*RscIPv4',
    '*RscIPv6',
    'ForceRscEnabled',
    '*UdpRsc',
    '*InterruptModeration',
    'TxIntModeration',
    'RxIntModeration',
    '*JumboPacket',
    'DisableLLDP',
    '*HeaderDataSplit',
    'HDSplitAlways',
    '*ReceiveBuffers',
    'StoreBadPackets',
    'RecvCompletionMethod',
    'AsyncReceiveIndicate',
    'ThreadedDpcEnable',
    '*TransmitBuffers',
    'DropHighlyFragmentedPacket',
    'EnableCoalesce',
    'TxThreadedDpcEnable',
    'SendCompletionMethod',
    'ThreadPoll',
    '*PacketCoalescing',
    '*PacketDirect',
    '*NdisPoll',
    '*NetworkDirect',
    'CongestionMonitoringEnable',
    '*SRIOV',
    '*DeviceSleepOnDisconnect',
    '*WakeOnMagicPacket',
    '*WakeOnPattern',
    '*NicAutoPowerSaver',
    'EEELinkAdvertisement',
    'EnableModernStandby',
    'EnablePowerManagement',
    'EnablePME',
    'ForceWakeFromMagicPacketOnModernStandby',
    'WakeFromS5',
    'WakeOn',
    'WakeOnLink',
    'LinkNegotiationProcess',
    'WaitForValidPhyIDRead',
    'WaitAutoNegComplete',
    'SleepWhileWaiting',
    'EnableETW',
    'OBFFEnabled',
    'ULPMode',
    'I218DisablePLLShut',
    'I218DisablePLLShutGiga',
    'I219DisableK1Off',
    'DisableDelayedPowerUp',
    '*EEE',
    'DisableIntelRST',
    'ForceHostExitUlp',
    'ForceLtrValue',
    'EnableDisconnectedStandby',
    'DMACoalescing',
    'EnableWakeOnManagmentOnTCO',
    'EnablePHYFlexibleSpeed',
    'EnablePHYWakeUp',
    'EnableD0PHYFlexibleSpeed',
    'EnableSavePowerNow',
    'AutoPowerSaveModeEnabled',
    'SipsEnabled',
    'WakeOnFastStartup',
    'ReduceSpeedOnPowerDown',
    '*EnableDynamicPowerGating',
    'EnableD3ColdInS0',
    '*SSIdleTimeout',
    '*SSIdleTimeoutScreenOff',
    'SSIdleTimeoutMS',
    'LatencyToleranceReporting',
    '*SelectiveSuspend',
    '*IdleRestriction',
    'AdvancedEEE',
    'ASPM',
    'CLKREQ',
    'EEEPlus',
    'EnableAspm',
    'DynamicLTR',
    'EnableGreenEthernet',
    'GigaLite',
    'PowerDownPll',
    'PowerSavingMode',
    'WolShutdownLinkSpeed',
    'LTROBFF',
    'S0MgcPkt',
    'S5WakeOnLan',
    'HwOption',
    'HwOptionV2',
    'HwOptionV3'
)

$NdisParameterNames = @(
    'DisableNDISWatchDog',
    'DisableNaps',
    'NoPauseOnSuspend',
    'DebugLoggingMode',
    'DisableWDIWatchdogForceBugcheck',
    'DisableReenumerationTimeoutBugcheck',
    'EnableNicAutoPowerSaverInSleepStudy'
)

if (-not (Test-Administrator)) {
    Write-Error 'This script must be run as Administrator because it deletes HKLM network optimization parameters.'
    exit 2
}

Write-Host 'Deleting every registry parameter written by Network Optimization Enable.'
Write-Host 'No replacement defaults are written.'
Write-Host ''

$totalRemoved = 0
$totalMissing = 0
$totalFailed = 0

$results = @()
foreach ($adapter in @(Get-PhysicalNetworkAdapters)) {
    $resolved = Resolve-AdapterClassPath -Adapter $adapter
    if ($null -ne $resolved) { $results += $resolved }
}

$results = Remove-DuplicateResolvedClassPaths $results
$wiredResults = @($results | Where-Object { (First-Text $_.NetworkAdapterKind 'OtherOrUnknown') -ieq 'WiredEthernet' })

if ($wiredResults.Count -gt 0) {
    $ndisResult = Remove-HklmRegistryValuesExact -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\NDIS\Parameters' -Names $NdisParameterNames -Label 'NDIS parameters'
    $totalRemoved += [int]$ndisResult.Removed
    $totalMissing += [int]$ndisResult.Missing
    $totalFailed += [int]$ndisResult.Failed
    Write-Host ''
} else {
    Write-Host 'FAILED     : Network Optimization Disable was not applied because no adapter Media is WiredEthernet.' -ForegroundColor Red
    Write-Host ''
}

if (@($results).Count -eq 0) {
    Write-Host 'WARNING: No physical network adapter class path was found. Adapter class parameters were not removed.' -ForegroundColor Yellow
} else {
    foreach ($result in @($results)) {
        Write-Host ('Name       : {0}' -f $result.Name)
        Write-NetworkAdapterDetection -Result $result
        Write-Host ('CLASS_PATH : {0}' -f $result.ClassPath)

        $media = First-Text $result.NetworkAdapterKind 'OtherOrUnknown'
        if ($media -ine 'WiredEthernet') {
            $totalFailed++
            Write-Host ('FAILED     : Network Optimization Disable was not applied because Media is {0}, not WiredEthernet.' -f $media) -ForegroundColor Red
            Write-Host ''
            continue
        }

        $label = 'Adapter parameters'
        if (-not [string]::IsNullOrWhiteSpace((Get-Text $result.Name))) {
            $label = 'Adapter parameters - ' + (Get-Text $result.Name)
        }

        $adapterResult = Remove-HklmRegistryValuesExact -Path $result.ProviderPath -Names $AdapterValueNames -Label $label
        $totalRemoved += [int]$adapterResult.Removed
        $totalMissing += [int]$adapterResult.Missing
        $totalFailed += [int]$adapterResult.Failed
        Write-Host ''
    }
}

Write-Host ('Total      : adapterPaths={0}, removed={1}, missing={2}, failed={3}' -f @($results).Count, $totalRemoved, $totalMissing, $totalFailed)

if ($totalFailed -gt 0) { exit 3 }
exit 0
'@

function Write-EmbeddedPayloadOutputLine {
    param([Parameter(Mandatory=$true)][object]$Line)

    $escapePattern = [regex]::Escape([string][char]27) + '\[[0-?]*[ -/]*[@-~]'
    $text = ([string]$Line) -replace $escapePattern, ''
    $text = $text.TrimStart([char]0xFEFF)
    $classifyText = $text.TrimStart()

    if ($classifyText -match '^.*?\[OK\]\s') {
        Write-Host $text -ForegroundColor Green
    } elseif ($classifyText -match '^.*?\[SUCCESS\]\s' -or $classifyText -match '^SUCCESS\s*:') {
        Write-Host $text -ForegroundColor Green
    } elseif ($classifyText -match '^\[WARNING\]\s' -or $classifyText -match '^OVERALL:\s+WARNING\b') {
        Write-Host $text -ForegroundColor Yellow
    } elseif (($classifyText -match '^\[FAIL\]\s') -and ($classifyText -match 'No MSFT_NetAdapterPowerManagementSettingData objects found')) {
        Write-Host $text -ForegroundColor Yellow
    } elseif ($classifyText -match '^\[FAIL\]\s' -or $classifyText -match '^\[ERROR\]\s' -or $classifyText -match '^FAILED\s*:') {
        Write-Host $text -ForegroundColor Red
    } elseif ($classifyText -match '^===\s' -or $classifyText -match '^----\s' -or $classifyText -match 'Already disabled|Disabled\.|No applicable devices found|No wake-programmable devices found|Root not present|Root present but no Device Parameters keys found|already 0|=0 created| -> 0|Success=|Total\s*:|Values\s*:') {
        Write-Host $text -ForegroundColor Green
    } else {
        Write-Host $text -ForegroundColor White
    }
}

function Invoke-EmbeddedPowerShellPayload {
    param(
        [Parameter(Mandatory=$true)][string]$Title,
        [Parameter(Mandatory=$true)][string]$Payload
    )

    $guid = [Guid]::NewGuid().ToString('N')
    $tempPath = Join-Path $env:TEMP "Windows_Tweaks_Menu_Network_${guid}_$PID.ps1"

    try {
        Set-Content -LiteralPath $tempPath -Value $Payload -Encoding UTF8
        Write-Host "---- $Title ----" -ForegroundColor White
        & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $tempPath 2>&1 | ForEach-Object {
            if ($_ -is [System.Management.Automation.ErrorRecord]) {
                Write-Host ($_.ToString()) -ForegroundColor Red
            } else {
                Write-EmbeddedPayloadOutputLine $_
            }
        }
        $rc = $LASTEXITCODE
        if (($rc -ne 0) -and ($rc -ne 10)) { Write-Host ("Exit code : " + $rc) -ForegroundColor White }
        return [int]$rc
    }
    catch {
        Write-Host ("FAILED : " + $Title + " -> " + $_.Exception.Message) -ForegroundColor Red
        return 99
    }
    finally {
        Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-NetworkOptimizationEnable {
    Clear-ConsoleScreen
    Write-BoxTitle -Title 'Network Optimization - Enable'
    Write-Host ""

    $rcPower = Invoke-EmbeddedPowerShellPayload -Title 'Disable powersaving' -Payload $DisablePowerSavingPayload
    Write-Host ""
    $rcNetwork = Invoke-EmbeddedPowerShellPayload -Title 'Optimize networking' -Payload $OptimizeNetworkingPayload

    Write-Host ""
    if (($rcPower -eq 0) -and ($rcNetwork -eq 0)) {
        Write-Host "OVERALL: SUCCESS" -ForegroundColor Green
    } else {
        Write-Host ("OVERALL: FAILED - Disable powersaving exit code={0}, Optimize networking exit code={1}" -f $rcPower, $rcNetwork) -ForegroundColor Red
    }

    Write-Host ""
    Wait-ForEnterToContinue
}

function Invoke-NetworkOptimizationDisable {
    Clear-ConsoleScreen
    Write-BoxTitle -Title 'Network Optimization - Disable'
    Write-Host ""
    Write-Host "Disable deletes the registry parameters written by Network Optimization Enable."
    Write-Host ""

    $rc = Invoke-EmbeddedPowerShellPayload -Title 'Delete enabled network optimization parameters' -Payload $RemoveNetworkOptimizationPayload

    Write-Host ""
    if ($rc -eq 0) {
        Write-Host "OVERALL: SUCCESS" -ForegroundColor Green
    } else {
        Write-Host ("OVERALL: FAILED - Exit code: {0}" -f $rc) -ForegroundColor Red
    }

    Write-Host ""
    Wait-ForEnterToContinue
}


function Invoke-DisableDevicePowerSaving {
    Clear-ConsoleScreen
    Write-BoxTitle -Title 'Powersaving - Disable device powersaving'
    Write-Host ""

    $rc = Invoke-EmbeddedPowerShellPayload -Title 'Disable device powersaving' -Payload $DisableDevicePowerSavingPayload

    Write-Host ""
    if ($rc -eq 0) {
        Write-Host "OVERALL: SUCCESS" -ForegroundColor Green
    } elseif ($rc -eq 10) {
        Write-Host "OVERALL: WARNING - Partial success. Check the per-device output above." -ForegroundColor Yellow
    } else {
        Write-Host ("OVERALL: FAILED - Exit code: {0}" -f $rc) -ForegroundColor Red
    }

    Write-Host ""
    Wait-ForEnterToContinue
}


function Format-AutostartPreviewText {
    param(
        [AllowNull()][object]$Text,
        [int]$MaxLength = 100
    )

    if ($null -eq $Text) { return '' }
    $preview = [string]$Text
    $preview = [regex]::Replace($preview, '\s+', ' ').Trim()

    if ($preview.Length -gt $MaxLength) {
        if ($MaxLength -gt 3) {
            return ($preview.Substring(0, $MaxLength - 3) + '...')
        }
        return $preview.Substring(0, $MaxLength)
    }

    return $preview
}

function Invoke-AutostartFullListMenu {
    param(
        [Parameter(Mandatory=$true)][string]$Title,
        [Parameter(Mandatory=$true)][object[]]$Items
    )

    function New-AutostartMenuEntries {
        param([Parameter(Mandatory=$true)][object[]]$AutostartItems)

        $entries = @()
        $entries += [pscustomobject]@{ Type='DisableAll'; Selectable=$true; Item=$null; Label='Disable all' }

        if ($AutostartItems.Count -eq 0) {
            $entries += [pscustomobject]@{ Type='Info'; Selectable=$false; Item=$null; Label='No autostart entries found' }
        } else {
            foreach ($item in $AutostartItems) {
                $entries += [pscustomobject]@{ Type='Item'; Selectable=$true; Item=$item; Label='' }
            }
        }

        $entries += [pscustomobject]@{ Type='Back'; Selectable=$true; Item=$null; Label='Back' }
        return @($entries)
    }

    function Ensure-AutostartConsoleBufferHeight {
        param([Parameter(Mandatory=$true)][int]$RequiredHeight)

        try {
            $required = [Math]::Max([Console]::WindowHeight, $RequiredHeight)
            if ($required -gt [Console]::BufferHeight) {
                $targetHeight = [Math]::Min(32766, $required)
                [Console]::SetBufferSize([Console]::BufferWidth, $targetHeight)
            }
        }
        catch { }
    }

    function Get-SelectableAutostartMenuIndex {
        param(
            [Parameter(Mandatory=$true)][object[]]$Entries,
            [Parameter(Mandatory=$true)][int]$CurrentIndex,
            [Parameter(Mandatory=$true)][int]$Direction
        )

        if ($Entries.Count -le 0) { return 0 }

        $candidate = $CurrentIndex
        for ($attempt = 0; $attempt -lt $Entries.Count; $attempt++) {
            $candidate += $Direction
            if ($candidate -lt 0) { $candidate = $Entries.Count - 1 }
            if ($candidate -ge $Entries.Count) { $candidate = 0 }

            if ($Entries[$candidate].Selectable) { return $candidate }
        }

        return $CurrentIndex
    }

    function Get-AutostartVisibleRowCount {
        param(
            [Parameter(Mandatory=$true)][int]$ItemTop,
            [Parameter(Mandatory=$true)][int]$EntryCount
        )

        try {
            $available = [Console]::WindowHeight - $ItemTop - 1
        }
        catch {
            $available = 20
        }

        $maximumStableRows = 18
        $available = [Math]::Max(1, [Math]::Min($available, $maximumStableRows))
        return [Math]::Max(1, [Math]::Min($EntryCount, $available))
    }

    function Get-AutostartViewportTopIndex {
        param(
            [Parameter(Mandatory=$true)][int]$SelectedIndex,
            [Parameter(Mandatory=$true)][int]$CurrentTopIndex,
            [Parameter(Mandatory=$true)][int]$VisibleRows,
            [Parameter(Mandatory=$true)][int]$EntryCount
        )

        if ($EntryCount -le 0 -or $VisibleRows -ge $EntryCount) { return 0 }

        $maxTopIndex = [Math]::Max(0, $EntryCount - $VisibleRows)
        $top = [Math]::Min([Math]::Max(0, $CurrentTopIndex), $maxTopIndex)

        if ($SelectedIndex -lt $top) {
            $top = $SelectedIndex
        }
        elseif ($SelectedIndex -ge ($top + $VisibleRows)) {
            $top = $SelectedIndex - $VisibleRows + 1
        }

        return [Math]::Min([Math]::Max(0, $top), $maxTopIndex)
    }

    function Get-AutostartMenuEntryText {
        param([Parameter(Mandatory=$true)][object]$Entry)

        switch ($Entry.Type) {
            'DisableAll' { return '[Action  ] Disable all' }
            'Item'       { return (Format-AutostartItemForMenu -Item $Entry.Item) }
            'Info'       { return $Entry.Label }
            'Back'       { return 'Back' }
            default      { return [string]$Entry.Label }
        }
    }

    $entries = @(New-AutostartMenuEntries -AutostartItems $Items)
    if ($entries.Count -le 0) { return -1 }

    $index = 0
    if (-not $entries[$index].Selectable) {
        $index = Get-SelectableAutostartMenuIndex -Entries $entries -CurrentIndex $index -Direction 1
    }

    try { $oldCursorVisible = [Console]::CursorVisible } catch { $oldCursorVisible = $true }

    try {
        try { [Console]::ResetColor() } catch { }
        Clear-ConsoleInputBuffer
        Clear-ConsoleScreen
        try { [Console]::CursorVisible = $false } catch { }

        Write-BoxTitle -Title $Title
        Write-Host ''
        Write-Host ('Entries: {0}' -f $Items.Count) -ForegroundColor DarkGray
        Write-Host ''

        $itemTop = [Console]::CursorTop
        $visibleRows = Get-AutostartVisibleRowCount -ItemTop $itemTop -EntryCount $entries.Count
        $footerTop = $itemTop + $visibleRows
        $topIndex = Get-AutostartViewportTopIndex -SelectedIndex $index -CurrentTopIndex 0 -VisibleRows $visibleRows -EntryCount $entries.Count
        Ensure-AutostartConsoleBufferHeight -RequiredHeight ($footerTop + 1)

        $getLineWidth = {
            try {
                $windowWidth = [Console]::WindowWidth
                $bufferWidth = [Console]::BufferWidth
                return [Math]::Max(1, ([Math]::Min($windowWidth, $bufferWidth) - 1))
            } catch {
                return 120
            }
        }

        $getDefaultFooterText = {
            return ''
        }

        $writeMenuRow = {
            param(
                [Parameter(Mandatory=$true)][int]$ViewRowIndex,
                [Parameter(Mandatory=$true)][bool]$Selected
            )

            try { [Console]::SetCursorPosition(0, ($itemTop + $ViewRowIndex)) } catch { return }

            $entryIndex = $topIndex + $ViewRowIndex
            $width = & $getLineWidth

            if ($entryIndex -ge $entries.Count) {
                Write-Host (' '.PadRight($width)) -ForegroundColor White -NoNewline
                return
            }

            $entry = $entries[$entryIndex]
            $prefix = if ($Selected) { '> ' } else { '  ' }
            $line = $prefix + (Get-AutostartMenuEntryText -Entry $entry)

            if ($line.Length -gt $width) { $line = $line.Substring(0, $width) }
            $line = $line.PadRight($width)

            if ($Selected) {
                Write-Host $line -ForegroundColor Cyan -NoNewline
            } elseif ($entry.Type -eq 'Info') {
                Write-Host $line -ForegroundColor Yellow -NoNewline
            } else {
                Write-Host $line -ForegroundColor White -NoNewline
            }
        }

        $writeFooter = {
            param(
                [string]$Text = $null,
                [ConsoleColor]$Color = [ConsoleColor]::DarkGray
            )

            if ([string]::IsNullOrWhiteSpace($Text)) { $Text = & $getDefaultFooterText }
            try { [Console]::SetCursorPosition(0, $footerTop) } catch { return }
            $width = & $getLineWidth
            if ($Text.Length -gt $width) { $Text = $Text.Substring(0, $width) }
            $line = $Text.PadRight($width)
            Write-Host $line -ForegroundColor $Color -NoNewline
        }

        $clearMenuArea = {
            param([int]$RowsToClear)

            $width = & $getLineWidth
            $rows = [Math]::Max(1, $RowsToClear)
            for ($row = 0; $row -le $rows; $row++) {
                try {
                    [Console]::SetCursorPosition(0, ($itemTop + $row))
                    Write-Host (' '.PadRight($width)) -ForegroundColor White -NoNewline
                } catch { }
            }
        }

        $redrawVisibleRows = {
            for ($row = 0; $row -lt $visibleRows; $row++) {
                & $writeMenuRow $row (($topIndex + $row) -eq $index)
            }
            & $writeFooter
            try { [Console]::SetCursorPosition(0, $footerTop) } catch { }
        }

        $redrawVisibleRows.Invoke()

        $getConsoleSignature = {
            try {
                return ('{0}x{1}:{2}x{3}' -f [Console]::WindowWidth, [Console]::WindowHeight, [Console]::BufferWidth, [Console]::BufferHeight)
            } catch {
                return 'unknown'
            }
        }
        $lastConsoleSignature = & $getConsoleSignature
        $navigationStopwatch = [Diagnostics.Stopwatch]::StartNew()
        $lastNavigationMoveMilliseconds = [int64]-1
        $minimumNavigationIntervalMilliseconds = 24

        while ($true) {
            while (-not [Console]::KeyAvailable) {
                Start-Sleep -Milliseconds 10
                $currentConsoleSignature = & $getConsoleSignature
                if ($currentConsoleSignature -ne $lastConsoleSignature) {
                    Clear-ConsoleScreen
                    Write-BoxTitle -Title $Title
                    Write-Host ''
                    Write-Host ('Entries: {0}' -f $Items.Count) -ForegroundColor DarkGray
                    Write-Host ''

                    $itemTop = [Console]::CursorTop
                    $visibleRows = Get-AutostartVisibleRowCount -ItemTop $itemTop -EntryCount $entries.Count
                    $footerTop = $itemTop + $visibleRows
                    Ensure-AutostartConsoleBufferHeight -RequiredHeight ($footerTop + 1)
                    $topIndex = Get-AutostartViewportTopIndex -SelectedIndex $index -CurrentTopIndex $topIndex -VisibleRows $visibleRows -EntryCount $entries.Count
                    & $redrawVisibleRows
                    $lastConsoleSignature = & $getConsoleSignature
                }
            }

            $key = [Console]::ReadKey($true)
            if (-not (Test-ConsoleNavigationInputAccepted -Key $key.Key -Stopwatch $navigationStopwatch -LastMoveMilliseconds ([ref]$lastNavigationMoveMilliseconds) -MinimumIntervalMilliseconds $minimumNavigationIntervalMilliseconds)) {
                continue
            }

            $previousIndex = $index
            $previousTopIndex = $topIndex
            $previousVisibleRows = $visibleRows

            switch ($key.Key) {
                'UpArrow'   { $index = Get-SelectableAutostartMenuIndex -Entries $entries -CurrentIndex $index -Direction -1 }
                'DownArrow' { $index = Get-SelectableAutostartMenuIndex -Entries $entries -CurrentIndex $index -Direction 1 }
                'Home'      { $index = 0; if (-not $entries[$index].Selectable) { $index = Get-SelectableAutostartMenuIndex -Entries $entries -CurrentIndex $index -Direction 1 } }
                'End'       { $index = $entries.Count - 1; if (-not $entries[$index].Selectable) { $index = Get-SelectableAutostartMenuIndex -Entries $entries -CurrentIndex $index -Direction -1 } }
                'Escape'    { Clear-ConsoleInputBuffer -DelayMilliseconds 75; return -1 }
                'Enter' {
                    $entry = $entries[$index]

                    if ($entry.Type -eq 'Back') {
                        Clear-ConsoleInputBuffer -DelayMilliseconds 75
                        return -1
                    }

                    if ($entry.Type -eq 'DisableAll') {
                        $failed = @()
                        $changed = $false
                        $scheduledTaskItems = @()

                        & $writeFooter -Text 'Disabling enabled autostart items...' -Color ([ConsoleColor]::DarkGray)

                        for ($row = 0; $row -lt $entries.Count; $row++) {
                            if ($entries[$row].Type -ne 'Item') { continue }
                            $item = $entries[$row].Item
                            if (-not [bool]$item.Enabled) { continue }

                            if ([string]$item.Kind -eq 'ScheduledTask') {
                                $scheduledTaskItems += $item
                                continue
                            }

                            $result = Set-AutostartItemStatus -Item $item -Enable:$false
                            if ($result.Ok) {
                                $changed = $true
                            } else {
                                $failed += [string]$result.Message
                            }
                        }

                        if ($scheduledTaskItems.Count -gt 0) {
                            $bulkResult = Set-AutostartScheduledTaskItemsStatusFast -Items $scheduledTaskItems -Enable:$false

                            if (($null -ne $bulkResult) -and [bool]$bulkResult.UsedFastPath) {
                                if ([int]$bulkResult.Successful -gt 0) { $changed = $true }

                                foreach ($failure in @($bulkResult.Failed)) {
                                    $fallbackResult = Set-AutostartItemStatus -Item $failure.Item -Enable:$false
                                    if ($fallbackResult.Ok) {
                                        $changed = $true
                                    } else {
                                        $failed += [string]$fallbackResult.Message
                                    }
                                }
                            } else {
                                foreach ($scheduledTaskItem in @($scheduledTaskItems)) {
                                    $result = Set-AutostartItemStatus -Item $scheduledTaskItem -Enable:$false
                                    if ($result.Ok) {
                                        $changed = $true
                                    } else {
                                        $failed += [string]$result.Message
                                    }
                                }
                            }
                        }

                        & $redrawVisibleRows

                        if ($failed.Count -gt 0) {
                            & $writeFooter -Text ('FAILED: {0} item(s) could not be disabled. {1}' -f $failed.Count, $failed[0]) -Color ([ConsoleColor]::Red)
                        } elseif (-not $changed) {
                            & $writeFooter -Text 'No enabled autostart items found.' -Color ([ConsoleColor]::Yellow)
                        } else {
                            & $writeFooter
                        }
                    }
                    elseif ($entry.Type -eq 'Item') {
                        $targetEnabled = -not [bool]$entry.Item.Enabled
                        $result = Set-AutostartItemStatus -Item $entry.Item -Enable:$targetEnabled

                        & $writeMenuRow ($index - $topIndex) $true

                        if ($result.Ok) {
                            & $writeFooter
                        } else {
                            & $writeFooter -Text ('FAILED: ' + [string]$result.Message) -Color ([ConsoleColor]::Red)
                        }
                    }

                    Clear-ConsoleInputBuffer -DelayMilliseconds 75
                }
            }

            $currentConsoleSignatureAfterInput = & $getConsoleSignature
            if ($currentConsoleSignatureAfterInput -ne $lastConsoleSignature) {
                Clear-ConsoleScreen
                Write-BoxTitle -Title $Title
                Write-Host ''
                Write-Host ('Entries: {0}' -f $Items.Count) -ForegroundColor DarkGray
                Write-Host ''

                $itemTop = [Console]::CursorTop
                $visibleRows = Get-AutostartVisibleRowCount -ItemTop $itemTop -EntryCount $entries.Count
                $footerTop = $itemTop + $visibleRows
                Ensure-AutostartConsoleBufferHeight -RequiredHeight ($footerTop + 1)
                $topIndex = Get-AutostartViewportTopIndex -SelectedIndex $index -CurrentTopIndex $topIndex -VisibleRows $visibleRows -EntryCount $entries.Count
                & $redrawVisibleRows
                $lastConsoleSignature = & $getConsoleSignature
                continue
            }

            $visibleRows = Get-AutostartVisibleRowCount -ItemTop $itemTop -EntryCount $entries.Count
            $footerTop = $itemTop + $visibleRows
            Ensure-AutostartConsoleBufferHeight -RequiredHeight ($footerTop + 1)
            $topIndex = Get-AutostartViewportTopIndex -SelectedIndex $index -CurrentTopIndex $topIndex -VisibleRows $visibleRows -EntryCount $entries.Count
            $lastConsoleSignature = & $getConsoleSignature

            if (($index -ne $previousIndex) -or ($topIndex -ne $previousTopIndex) -or ($visibleRows -ne $previousVisibleRows)) {
                if (($topIndex -ne $previousTopIndex) -or ($visibleRows -ne $previousVisibleRows)) {
                    if ($visibleRows -ne $previousVisibleRows) {
                        & $clearMenuArea ([Math]::Max($previousVisibleRows, $visibleRows) + 1)
                    }
                    & $redrawVisibleRows
                } else {
                    $previousViewRow = $previousIndex - $topIndex
                    $currentViewRow = $index - $topIndex
                    if (($previousViewRow -ge 0) -and ($previousViewRow -lt $visibleRows)) {
                        & $writeMenuRow $previousViewRow $false
                    }
                    if (($currentViewRow -ge 0) -and ($currentViewRow -lt $visibleRows)) {
                        & $writeMenuRow $currentViewRow $true
                    }
                    try { [Console]::SetCursorPosition(0, $footerTop) } catch { }
                }
            }
        }
    }
    finally {
        try { [Console]::CursorVisible = $oldCursorVisible } catch { }
        try { [Console]::ResetColor() } catch { }
    }
}

function Get-AutostartRegistryDisabledStorePath {
    return 'HKCU:\Software\WindowsTweaksMenu\AutostartDisabled\Registry'
}

function Get-AutostartRegistryRecordId {
    param(
        [Parameter(Mandatory=$true)][string]$RegistryPath,
        [Parameter(Mandatory=$true)][string]$Name
    )

    $payload = $RegistryPath.ToUpperInvariant() + "`n" + $Name
    $bytes = [Text.Encoding]::UTF8.GetBytes($payload)
    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha256.ComputeHash($bytes)
    }
    finally {
        $sha256.Dispose()
    }

    return (($hash | ForEach-Object { $_.ToString('x2') }) -join '')
}

function ConvertTo-AutostartRegistryRecordData {
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory=$true)][string]$ValueKind
    )

    if ($null -eq $Value) { return $null }

    switch ($ValueKind) {
        'Binary' { return [Convert]::ToBase64String([byte[]]$Value) }
        'MultiString' { return @([string[]]$Value) }
        default { return [string]$Value }
    }
}

function ConvertFrom-AutostartRegistryRecordData {
    param(
        [AllowNull()][object]$Data,
        [Parameter(Mandatory=$true)][string]$ValueKind
    )

    if ($null -eq $Data) { return $null }

    switch ($ValueKind) {
        'Binary' { return [Convert]::FromBase64String([string]$Data) }
        'DWord' { return [int]([Convert]::ToInt32([string]$Data, 10)) }
        'QWord' { return [long]([Convert]::ToInt64([string]$Data, 10)) }
        'MultiString' { return [string[]]@($Data) }
        default { return [string]$Data }
    }
}


function Get-AutostartRegistryValueInfo {
    param(
        [AllowNull()][string]$RegistryPath,
        [AllowNull()][string]$Name
    )

    $info = [pscustomobject]@{
        Exists = $false
        Path = [string]$RegistryPath
        Name = [string]$Name
        ValueKind = ''
        ValueData = $null
    }

    if ([string]::IsNullOrWhiteSpace($RegistryPath) -or [string]::IsNullOrWhiteSpace($Name)) {
        return $info
    }

    try {
        if (-not (Test-Path -LiteralPath $RegistryPath)) { return $info }

        $registryKey = Get-Item -LiteralPath $RegistryPath -ErrorAction Stop
        $matchingName = $null
        foreach ($valueName in @($registryKey.GetValueNames())) {
            if ([string]::Equals([string]$valueName, [string]$Name, [System.StringComparison]::OrdinalIgnoreCase)) {
                $matchingName = [string]$valueName
                break
            }
        }

        if ($null -eq $matchingName) { return $info }

        $info.Exists = $true
        $info.Name = $matchingName
        $info.ValueKind = $registryKey.GetValueKind($matchingName).ToString()
        $info.ValueData = $registryKey.GetValue($matchingName, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    }
    catch { }

    return $info
}

function Get-AutostartRegistryLocations {
    return @(
        [pscustomobject]@{ Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'; Label='HKCU Run' },
        [pscustomobject]@{ Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce'; Label='HKCU RunOnce' },
        [pscustomobject]@{ Path='HKCU:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Run'; Label='HKCU Wow6432Node Run' },
        [pscustomobject]@{ Path='HKCU:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\RunOnce'; Label='HKCU Wow6432Node RunOnce' },
        [pscustomobject]@{ Path='HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'; Label='HKLM Run' },
        [pscustomobject]@{ Path='HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce'; Label='HKLM RunOnce' },
        [pscustomobject]@{ Path='HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Run'; Label='HKLM Wow6432Node Run' },
        [pscustomobject]@{ Path='HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\RunOnce'; Label='HKLM Wow6432Node RunOnce' }
    )
}

function Get-AutostartRegistryStartupApprovedPath {
    param([AllowNull()][string]$RegistryPath)

    if ([string]::IsNullOrWhiteSpace($RegistryPath)) { return '' }
    $path = ([string]$RegistryPath).TrimEnd([char]92).ToUpperInvariant()

    switch ($path) {
        'HKCU:\SOFTWARE\MICROSOFT\WINDOWS\CURRENTVERSION\RUN' {
            return 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
        }
        'HKCU:\SOFTWARE\WOW6432NODE\MICROSOFT\WINDOWS\CURRENTVERSION\RUN' {
            return 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32'
        }
        'HKLM:\SOFTWARE\MICROSOFT\WINDOWS\CURRENTVERSION\RUN' {
            return 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
        }
        'HKLM:\SOFTWARE\WOW6432NODE\MICROSOFT\WINDOWS\CURRENTVERSION\RUN' {
            return 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32'
        }
    }

    return ''
}

function Get-AutostartStartupApprovedInfo {
    param(
        [AllowNull()][string]$StartupApprovedPath,
        [AllowNull()][string]$Name
    )

    $info = [pscustomobject]@{
        Path = [string]$StartupApprovedPath
        Exists = $false
        Enabled = $true
        State = 'Missing'
        Data = $null
    }

    if ([string]::IsNullOrWhiteSpace($StartupApprovedPath) -or [string]::IsNullOrWhiteSpace($Name)) {
        $info.State = 'NotControlled'
        return $info
    }

    try {
        if (-not (Test-Path -LiteralPath $StartupApprovedPath)) { return $info }
        $key = Get-Item -LiteralPath $StartupApprovedPath -ErrorAction Stop
        $valueNames = @($key.GetValueNames())
        $matchingName = $null
        foreach ($valueName in $valueNames) {
            if ([string]::Equals([string]$valueName, [string]$Name, [System.StringComparison]::OrdinalIgnoreCase)) {
                $matchingName = [string]$valueName
                break
            }
        }
        if ($null -eq $matchingName) { return $info }

        $rawData = $key.GetValue($matchingName, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        $bytes = @()
        if ($null -ne $rawData) { $bytes = [byte[]]$rawData }

        $stateByte = if ($bytes.Count -gt 0) { [byte]$bytes[0] } else { [byte]0 }
        $disabled = ($stateByte -eq 3 -or $stateByte -eq 7)

        $info.Exists = $true
        $info.Enabled = (-not $disabled)
        $info.State = if ($disabled) { 'Disabled' } else { 'Enabled' }
        $info.Data = $bytes
    }
    catch {
        $info.State = 'Unknown'
        $info.Enabled = $true
    }

    return $info
}

function New-AutostartStartupApprovedBinary {
    param([Parameter(Mandatory=$true)][bool]$Enable)

    $bytes = New-Object byte[] 12
    if ($Enable) {
        $bytes[0] = 2
        return [byte[]]$bytes
    }

    $bytes[0] = 3
    $fileTimeBytes = [BitConverter]::GetBytes([DateTime]::UtcNow.ToFileTimeUtc())
    [Array]::Copy($fileTimeBytes, 0, $bytes, 4, 8)
    return [byte[]]$bytes
}

function Set-AutostartStartupApprovedStatus {
    param(
        [Parameter(Mandatory=$true)][string]$StartupApprovedPath,
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][bool]$Enable
    )

    if ([string]::IsNullOrWhiteSpace($StartupApprovedPath)) {
        throw 'StartupApproved registry path is empty.'
    }
    if ([string]::IsNullOrWhiteSpace($Name)) {
        throw 'StartupApproved value name is empty.'
    }

    if (-not (Test-Path -LiteralPath $StartupApprovedPath)) {
        try { New-Item -Path $StartupApprovedPath -Force | Out-Null }
        catch {
            Invoke-AsTrustedInstaller { New-Item -Path $using:StartupApprovedPath -Force | Out-Null } | Out-Null
        }
    }

    $bytes = New-AutostartStartupApprovedBinary -Enable:$Enable
    try {
        New-ItemProperty -LiteralPath $StartupApprovedPath -Name $Name -PropertyType Binary -Value $bytes -Force | Out-Null
    } catch {
        $tiSAP = $StartupApprovedPath; $tiN = $Name; $tiB = $bytes
        $tiOk = Invoke-AsTrustedInstaller {
            New-ItemProperty -LiteralPath $using:tiSAP -Name $using:tiN -PropertyType Binary -Value $using:tiB -Force | Out-Null
        }
        if (-not $tiOk) { throw $_ }
    }
}

function Get-AutostartRegistryItems {
    $items = @()

    foreach ($location in Get-AutostartRegistryLocations) {
        try {
            if (-not (Test-Path -LiteralPath $location.Path)) { continue }
            $registryKey = Get-Item -LiteralPath $location.Path -ErrorAction Stop
            $startupApprovedPath = Get-AutostartRegistryStartupApprovedPath -RegistryPath $location.Path

            foreach ($valueName in $registryKey.GetValueNames()) {
                if ([string]::IsNullOrWhiteSpace($valueName)) { continue }

                $valueKind = $registryKey.GetValueKind($valueName).ToString()
                $valueData = $registryKey.GetValue($valueName, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                $startupApprovedInfo = Get-AutostartStartupApprovedInfo -StartupApprovedPath $startupApprovedPath -Name $valueName

                $items += [pscustomobject]@{
                    Kind = 'Registry'
                    Source = $location.Label
                    DisplayName = $valueName
                    EntryName = $valueName
                    Details = (Format-AutostartPreviewText -Text $valueData -MaxLength 140)
                    Enabled = [bool]$startupApprovedInfo.Enabled
                    RegistryPath = $location.Path
                    ValueKind = $valueKind
                    ValueData = $valueData
                    RecordId = (Get-AutostartRegistryRecordId -RegistryPath $location.Path -Name $valueName)
                    StartupApprovedPath = $startupApprovedPath
                    StartupApprovedState = [string]$startupApprovedInfo.State
                    StartupApprovedExists = [bool]$startupApprovedInfo.Exists
                    StartupApprovedData = $startupApprovedInfo.Data
                }
            }
        }
        catch { }
    }

    $storePath = Get-AutostartRegistryDisabledStorePath
    try {
        if (Test-Path -LiteralPath $storePath) {
            $storeKey = Get-Item -LiteralPath $storePath -ErrorAction Stop
            foreach ($recordId in $storeKey.GetValueNames()) {
                try {
                    $json = [string]$storeKey.GetValue($recordId)
                    if ([string]::IsNullOrWhiteSpace($json)) { continue }
                    $record = $json | ConvertFrom-Json -ErrorAction Stop
                    $existingValueInfo = Get-AutostartRegistryValueInfo -RegistryPath ([string]$record.RegistryPath) -Name ([string]$record.Name)
                    if ($existingValueInfo.Exists) {
                        Remove-ItemProperty -LiteralPath $storePath -Name $recordId -ErrorAction SilentlyContinue
                        continue
                    }

                    $dataText = ConvertFrom-AutostartRegistryRecordData -Data $record.Data -ValueKind ([string]$record.ValueKind)
                    $startupApprovedPath = Get-AutostartRegistryStartupApprovedPath -RegistryPath ([string]$record.RegistryPath)

                    $items += [pscustomobject]@{
                        Kind = 'Registry'
                        Source = if ([string]::IsNullOrWhiteSpace([string]$record.Source)) { 'Registry startup' } else { [string]$record.Source }
                        DisplayName = [string]$record.Name
                        EntryName = [string]$record.Name
                        Details = (Format-AutostartPreviewText -Text $dataText -MaxLength 140)
                        Enabled = $false
                        RegistryPath = [string]$record.RegistryPath
                        ValueKind = [string]$record.ValueKind
                        ValueData = $record.Data
                        RecordId = [string]$recordId
                        DisabledRecord = $record
                        StartupApprovedPath = $startupApprovedPath
                        StartupApprovedState = 'Removed'
                        StartupApprovedExists = $false
                        StartupApprovedData = $null
                    }
                }
                catch { }
            }
        }
    }
    catch { }

    return @($items)
}

function Get-AutostartFolderDefinitions {
    $definitions = @()

    try {
        $currentStartup = [Environment]::GetFolderPath([Environment+SpecialFolder]::Startup)
        if (-not [string]::IsNullOrWhiteSpace($currentStartup)) {
            $definitions += [pscustomobject]@{
                Folder = $currentStartup
                DisabledFolder = (Join-Path -Path (Split-Path -Parent $currentStartup) -ChildPath 'Startup.WindowsTweaksDisabled')
                Label = 'Startup folder - current user'
            }
        }
    }
    catch { }

    try {
        $commonStartup = [Environment]::GetFolderPath([Environment+SpecialFolder]::CommonStartup)
        if (-not [string]::IsNullOrWhiteSpace($commonStartup)) {
            $definitions += [pscustomobject]@{
                Folder = $commonStartup
                DisabledFolder = (Join-Path -Path (Split-Path -Parent $commonStartup) -ChildPath 'Startup.WindowsTweaksDisabled')
                Label = 'Startup folder - all users'
            }
        }
    }
    catch { }

    return @($definitions)
}

function Get-AutostartFolderItems {
    $items = @()

    foreach ($definition in Get-AutostartFolderDefinitions) {
        try {
            if (Test-Path -LiteralPath $definition.Folder) {
                Get-ChildItem -LiteralPath $definition.Folder -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
                    $items += [pscustomobject]@{
                        Kind = 'StartupFolder'
                        Source = $definition.Label
                        DisplayName = $_.Name
                        EntryName = $_.Name
                        Details = $_.FullName
                        Enabled = $true
                        Path = $_.FullName
                        Folder = $definition.Folder
                        DisabledFolder = $definition.DisabledFolder
                    }
                }
            }
        }
        catch { }

        try {
            if (Test-Path -LiteralPath $definition.DisabledFolder) {
                Get-ChildItem -LiteralPath $definition.DisabledFolder -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
                    $items += [pscustomobject]@{
                        Kind = 'StartupFolder'
                        Source = $definition.Label
                        DisplayName = $_.Name
                        EntryName = $_.Name
                        Details = $_.FullName
                        Enabled = $false
                        Path = $_.FullName
                        Folder = $definition.Folder
                        DisabledFolder = $definition.DisabledFolder
                    }
                }
            }
        }
        catch { }
    }

    return @($items)
}

function Test-ScheduledTaskTriggerIsAutostart {
    param([AllowNull()][object]$Trigger)

    if ($null -eq $Trigger) { return $false }

    $className = ''
    try { $className = [string]$Trigger.CimClass.CimClassName } catch { }
    if ($className -match '(?i)(Boot|Logon)Trigger') { return $true }

    foreach ($propertyName in @('TriggerType', 'Type')) {
        try {
            if ($Trigger.PSObject.Properties.Name -contains $propertyName) {
                $propertyValue = [string]$Trigger.$propertyName
                if ($propertyValue -match '(?i)Boot|Logon|Startup') { return $true }
            }
        }
        catch { }
    }

    return $false
}

function Test-ScheduledTaskTriggerEnabled {
    param([AllowNull()][object]$Trigger)

    if ($null -eq $Trigger) { return $false }

    try {
        $enabledProperty = $Trigger.PSObject.Properties['Enabled']
        if (($null -ne $enabledProperty) -and ($null -ne $enabledProperty.Value)) {
            return [bool]$enabledProperty.Value
        }
    }
    catch { }

    return $true
}

function Set-ScheduledTaskTriggerEnabledValue {
    param(
        [Parameter(Mandatory=$true)][object]$Trigger,
        [Parameter(Mandatory=$true)][bool]$Enable
    )

    try {
        $enabledProperty = $Trigger.PSObject.Properties['Enabled']
        if ($null -ne $enabledProperty) {
            $enabledProperty.Value = $Enable
            return $true
        }
    }
    catch { }

    try {
        $Trigger.Enabled = $Enable
        return $true
    }
    catch { }

    return $false
}

function Get-ScheduledTaskAutostartTriggerInfo {
    param([Parameter(Mandatory=$true)][object]$Task)

    $totalCount = 0
    $enabledCount = 0

    foreach ($trigger in @($Task.Triggers)) {
        if (-not (Test-ScheduledTaskTriggerIsAutostart -Trigger $trigger)) { continue }

        $totalCount++
        if (Test-ScheduledTaskTriggerEnabled -Trigger $trigger) { $enabledCount++ }
    }

    return [pscustomobject]@{
        TotalCount = [int]$totalCount
        EnabledCount = [int]$enabledCount
        DisabledCount = [int]($totalCount - $enabledCount)
        HasAutostartTrigger = ($totalCount -gt 0)
        HasEnabledAutostartTrigger = ($enabledCount -gt 0)
        Summary = ('autostart triggers {0}/{1} enabled' -f $enabledCount, $totalCount)
    }
}

function Test-ScheduledTaskHasAutostartTrigger {
    param([Parameter(Mandatory=$true)][object]$Task)

    $info = Get-ScheduledTaskAutostartTriggerInfo -Task $Task
    return [bool]$info.HasAutostartTrigger
}

function Set-ScheduledTaskAutostartTriggerStatus {
    param(
        [Parameter(Mandatory=$true)][string]$TaskName,
        [Parameter(Mandatory=$true)][string]$TaskPath,
        [Parameter(Mandatory=$true)][bool]$Enable
    )

    $task = Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction Stop

    $autostartCount = 0
    $changedCount = 0
    $unchangedCount = 0
    $failedCount = 0

    foreach ($trigger in @($task.Triggers)) {
        if (-not (Test-ScheduledTaskTriggerIsAutostart -Trigger $trigger)) { continue }

        $autostartCount++
        $isEnabled = Test-ScheduledTaskTriggerEnabled -Trigger $trigger
        if ($isEnabled -eq $Enable) {
            $unchangedCount++
            continue
        }

        if (Set-ScheduledTaskTriggerEnabledValue -Trigger $trigger -Enable:$Enable) {
            $changedCount++
        } else {
            $failedCount++
        }
    }

    if ($autostartCount -lt 1) {
        throw 'scheduled task no longer has a boot/logon autostart trigger'
    }
    if ($failedCount -gt 0) {
        throw ('could not edit {0} scheduled task autostart trigger(s)' -f $failedCount)
    }

    if ($changedCount -gt 0) {
        Set-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -Trigger @($task.Triggers) -ErrorAction Stop | Out-Null
    }

    $updatedTask = Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction Stop
    $updatedInfo = Get-ScheduledTaskAutostartTriggerInfo -Task $updatedTask
    $updatedTaskState = [string]$updatedTask.State
    $updatedActionText = Get-AutostartScheduledTaskActionText -Task $updatedTask
    $updatedDetailParts = @([string]$updatedInfo.Summary)
    if ($updatedTaskState -eq 'Disabled') { $updatedDetailParts += 'task itself is disabled' }
    if (-not [string]::IsNullOrWhiteSpace($updatedActionText)) { $updatedDetailParts += $updatedActionText }

    return [pscustomobject]@{
        AutostartTriggerCount = [int]$updatedInfo.TotalCount
        EnabledAutostartTriggerCount = [int]$updatedInfo.EnabledCount
        DisabledAutostartTriggerCount = [int]$updatedInfo.DisabledCount
        ChangedCount = [int]$changedCount
        UnchangedCount = [int]$unchangedCount
        TaskState = $updatedTaskState
        TaskGloballyEnabled = ($updatedTaskState -ne 'Disabled')
        Details = (Format-AutostartPreviewText -Text ($updatedDetailParts -join '; ') -MaxLength 140)
    }
}

function ConvertTo-ScheduledTaskComFolderPath {
    param([AllowNull()][string]$TaskPath)

    $path = ([string]$TaskPath).Trim()
    if ([string]::IsNullOrWhiteSpace($path)) { return '\' }
    if (-not $path.StartsWith('\')) { $path = '\' + $path }

    while (($path.Length -gt 1) -and $path.EndsWith('\')) {
        $path = $path.Substring(0, $path.Length - 1)
    }

    if ([string]::IsNullOrWhiteSpace($path)) { return '\' }
    return $path
}

function Test-ScheduledTaskComTriggerIsAutostart {
    param([AllowNull()][object]$Trigger)

    if ($null -eq $Trigger) { return $false }

    try {
        $triggerType = [int]$Trigger.Type
        if (($triggerType -eq 8) -or ($triggerType -eq 9)) { return $true }
    }
    catch { }

    try {
        $triggerTypeText = [string]$Trigger.Type
        if ($triggerTypeText -match '(?i)Boot|Logon|Startup') { return $true }
    }
    catch { }

    return $false
}

function Get-ScheduledTaskComStateText {
    param([AllowNull()][object]$State)

    try {
        switch ([int]$State) {
            0 { return 'Unknown' }
            1 { return 'Disabled' }
            2 { return 'Queued' }
            3 { return 'Ready' }
            4 { return 'Running' }
            default { return [string]$State }
        }
    }
    catch {
        return [string]$State
    }
}

function Get-AutostartScheduledTaskFastDetailText {
    param(
        [Parameter(Mandatory=$true)][object]$Item,
        [Parameter(Mandatory=$true)][int]$EnabledAutostartTriggerCount,
        [Parameter(Mandatory=$true)][int]$AutostartTriggerCount,
        [AllowNull()][string]$TaskState
    )

    $detailParts = @('autostart triggers {0}/{1} enabled' -f $EnabledAutostartTriggerCount, $AutostartTriggerCount)
    if ([string]$TaskState -eq 'Disabled') { $detailParts += 'task itself is disabled' }

    $oldDetails = [string]$Item.Details
    if (-not [string]::IsNullOrWhiteSpace($oldDetails)) {
        $oldDetails = [regex]::Replace($oldDetails, '(?i)^autostart triggers\s+\d+/\d+\s+enabled(?:;\s*task itself is disabled)?(?:;\s*)?', '')
        if (-not [string]::IsNullOrWhiteSpace($oldDetails)) { $detailParts += $oldDetails }
    }

    return (Format-AutostartPreviewText -Text ($detailParts -join '; ') -MaxLength 140)
}

function Set-AutostartScheduledTaskItemsStatusFast {
    param(
        [Parameter(Mandatory=$true)][object[]]$Items,
        [Parameter(Mandatory=$true)][bool]$Enable
    )

    $failed = @()
    $processed = 0
    $successful = 0
    $updated = 0
    $unchanged = 0

    if (($null -eq $Items) -or ($Items.Count -lt 1)) {
        return [pscustomobject]@{
            UsedFastPath = $true
            Ok           = $true
            Processed    = 0
            Successful   = 0
            Updated      = 0
            Unchanged    = 0
            Failed       = @()
        }
    }

    try {
        $service = New-Object -ComObject 'Schedule.Service'
        $service.Connect()
    }
    catch {
        return [pscustomobject]@{
            UsedFastPath = $false
            Ok           = $false
            Processed    = 0
            Successful   = 0
            Updated      = 0
            Unchanged    = 0
            Failed       = @()
            Message      = ('Schedule.Service COM fast path unavailable: ' + $_.Exception.Message)
        }
    }

    foreach ($item in @($Items)) {
        $processed++

        try {
            if (($Enable -and [bool]$item.Enabled) -or ((-not $Enable) -and (-not [bool]$item.Enabled))) {
                $unchanged++
                $successful++
                continue
            }

            $folderPath = ConvertTo-ScheduledTaskComFolderPath -TaskPath ([string]$item.TaskPath)
            $taskName = [string]$item.TaskName
            if ([string]::IsNullOrWhiteSpace($taskName)) { throw 'scheduled task name is blank' }

            $folder = $service.GetFolder($folderPath)
            $registeredTask = $folder.GetTask($taskName)
            $definition = $registeredTask.Definition

            $autostartCount = 0
            $enabledBefore = 0
            $enabledAfter = 0
            $changedCount = 0

            for ($triggerIndex = 1; $triggerIndex -le [int]$definition.Triggers.Count; $triggerIndex++) {
                $trigger = $definition.Triggers.Item($triggerIndex)
                if (-not (Test-ScheduledTaskComTriggerIsAutostart -Trigger $trigger)) { continue }

                $autostartCount++

                $wasEnabled = $true
                try { $wasEnabled = [bool]$trigger.Enabled } catch { $wasEnabled = $true }
                if ($wasEnabled) { $enabledBefore++ }

                if ($wasEnabled -ne $Enable) {
                    try {
                        $trigger.Enabled = $Enable
                        $changedCount++
                    }
                    catch {
                        throw ('could not edit scheduled task autostart trigger #{0}: {1}' -f $autostartCount, $_.Exception.Message)
                    }
                }

                if ($Enable) {
                    $enabledAfter++
                } elseif (-not $wasEnabled) {
                } else {
                }
            }

            if ($autostartCount -lt 1) {
                throw 'scheduled task no longer has a boot/logon autostart trigger'
            }

            if ($changedCount -gt 0) {
                $registeredTask = $folder.RegisterTaskDefinition($taskName, $definition, 6, $null, $null, 0, $null)
                $updated++
            } else {
                $unchanged++
            }

            if ($Enable) {
                $enabledAfter = $autostartCount
            } else {
                $enabledAfter = [Math]::Max(0, $enabledBefore - $changedCount)
            }

            $taskState = [string]$item.TaskState
            try { $taskState = Get-ScheduledTaskComStateText -State $registeredTask.State } catch { }

            Set-AutostartObjectProperty -Object $item -Name 'Enabled' -Value ($enabledAfter -gt 0)
            Set-AutostartObjectProperty -Object $item -Name 'TaskState' -Value $taskState
            Set-AutostartObjectProperty -Object $item -Name 'TaskGloballyEnabled' -Value ($taskState -ne 'Disabled')
            Set-AutostartObjectProperty -Object $item -Name 'AutostartTriggerCount' -Value ([int]$autostartCount)
            Set-AutostartObjectProperty -Object $item -Name 'EnabledAutostartTriggerCount' -Value ([int]$enabledAfter)
            Set-AutostartObjectProperty -Object $item -Name 'DisabledAutostartTriggerCount' -Value ([int]($autostartCount - $enabledAfter))
            Set-AutostartObjectProperty -Object $item -Name 'Details' -Value (Get-AutostartScheduledTaskFastDetailText -Item $item -EnabledAutostartTriggerCount $enabledAfter -AutostartTriggerCount $autostartCount -TaskState $taskState)

            $successful++
        }
        catch {
            $displayName = [string]$item.DisplayName
            if ([string]::IsNullOrWhiteSpace($displayName)) { $displayName = [string]$item.TaskName }
            $failed += [pscustomobject]@{
                Item    = $item
                Message = ('{0} -> {1}' -f $displayName, $_.Exception.Message)
            }
        }
    }

    return [pscustomobject]@{
        UsedFastPath = $true
        Ok           = ($failed.Count -eq 0)
        Processed    = [int]$processed
        Successful   = [int]$successful
        Updated      = [int]$updated
        Unchanged    = [int]$unchanged
        Failed       = @($failed)
    }
}

function Get-AutostartScheduledTaskActionText {
    param([Parameter(Mandatory=$true)][object]$Task)

    $parts = @()
    foreach ($action in @($Task.Actions)) {
        if ($null -eq $action) { continue }
        $execute = ''
        $arguments = ''
        try { $execute = [string]$action.Execute } catch { }
        try { $arguments = [string]$action.Arguments } catch { }
        $text = ($execute + ' ' + $arguments).Trim()
        if (-not [string]::IsNullOrWhiteSpace($text)) { $parts += $text }
    }

    return (Format-AutostartPreviewText -Text ($parts -join '; ') -MaxLength 140)
}

function Get-AutostartScheduledTaskItems {
    $items = @()

    try {
        $tasks = Get-ScheduledTask -ErrorAction Stop
    }
    catch {
        return @($items)
    }

    foreach ($task in @($tasks)) {
        try {
            $triggerInfo = Get-ScheduledTaskAutostartTriggerInfo -Task $task
            if (-not $triggerInfo.HasAutostartTrigger) { continue }

            $fullName = ([string]$task.TaskPath + [string]$task.TaskName)
            $taskState = [string]$task.State
            $actionText = Get-AutostartScheduledTaskActionText -Task $task
            $detailParts = @([string]$triggerInfo.Summary)
            if ($taskState -eq 'Disabled') { $detailParts += 'task itself is disabled' }
            if (-not [string]::IsNullOrWhiteSpace($actionText)) { $detailParts += $actionText }

            $items += [pscustomobject]@{
                Kind = 'ScheduledTask'
                Source = 'Scheduled task'
                DisplayName = $fullName
                EntryName = $fullName
                Details = (Format-AutostartPreviewText -Text ($detailParts -join '; ') -MaxLength 140)
                Enabled = [bool]$triggerInfo.HasEnabledAutostartTrigger
                TaskName = [string]$task.TaskName
                TaskPath = [string]$task.TaskPath
                TaskState = $taskState
                TaskGloballyEnabled = ($taskState -ne 'Disabled')
                AutostartTriggerCount = [int]$triggerInfo.TotalCount
                EnabledAutostartTriggerCount = [int]$triggerInfo.EnabledCount
                DisabledAutostartTriggerCount = [int]$triggerInfo.DisabledCount
            }
        }
        catch { }
    }

    return @($items)
}

function Get-AutostartItems {
    $items = @()
    $items += @(Get-AutostartRegistryItems)
    $items += @(Get-AutostartFolderItems)
    $items += @(Get-AutostartScheduledTaskItems)

    return @($items | Sort-Object @{Expression='Enabled'; Descending=$true}, Source, EntryName)
}

function Format-AutostartItemForMenu {
    param([Parameter(Mandatory=$true)][object]$Item)

    $status = if ($Item.Enabled) { 'Enabled ' } else { 'Disabled' }
    $name = Format-AutostartPreviewText -Text $Item.DisplayName -MaxLength 70
    $details = Format-AutostartPreviewText -Text $Item.Details -MaxLength 90

    if ([string]::IsNullOrWhiteSpace($details)) {
        return ('[{0}] {1}: {2}' -f $status, $Item.Source, $name)
    }

    return ('[{0}] {1}: {2} -> {3}' -f $status, $Item.Source, $name, $details)
}

function Set-AutostartObjectProperty {
    param(
        [Parameter(Mandatory=$true)][object]$Object,
        [Parameter(Mandatory=$true)][string]$Name,
        [AllowNull()][object]$Value
    )

    $property = $Object.PSObject.Properties[$Name]
    if ($null -ne $property) {
        $property.Value = $Value
    } else {
        Add-Member -InputObject $Object -MemberType NoteProperty -Name $Name -Value $Value -Force
    }
}

function Set-AutostartRegistryItemStatus {
    param(
        [Parameter(Mandatory=$true)][object]$Item,
        [Parameter(Mandatory=$true)][bool]$Enable
    )

    $storePath = Get-AutostartRegistryDisabledStorePath

    try {
        if ($Enable) {
            if ($Item.Enabled) { return [pscustomobject]@{ Ok=$true; Message="already enabled: $($Item.DisplayName)" } }

            $targetPath = [string]$Item.RegistryPath
            $valueName = [string]$Item.EntryName
            $valueKind = [string]$Item.ValueKind
            if ([string]::IsNullOrWhiteSpace($valueKind)) { $valueKind = 'String' }
            $valueData = $Item.ValueData
            $restoredRegistryValue = $false

            if ($null -ne $Item.DisabledRecord) {
                $record = $Item.DisabledRecord
                $targetPath = [string]$record.RegistryPath
                $valueName = [string]$record.Name
                $valueKind = [string]$record.ValueKind
                if ([string]::IsNullOrWhiteSpace($valueKind)) { $valueKind = 'String' }
                $valueData = ConvertFrom-AutostartRegistryRecordData -Data $record.Data -ValueKind $valueKind

                $existingValueInfo = Get-AutostartRegistryValueInfo -RegistryPath $targetPath -Name $valueName
                if ($existingValueInfo.Exists) {
                    $valueName = [string]$existingValueInfo.Name
                    $valueKind = [string]$existingValueInfo.ValueKind
                    if ([string]::IsNullOrWhiteSpace($valueKind)) { $valueKind = 'String' }
                    $valueData = $existingValueInfo.ValueData
                } else {
                    if (-not (Test-Path -LiteralPath $targetPath)) {
                        try { New-Item -Path $targetPath -Force | Out-Null }
                        catch { Invoke-AsTrustedInstaller { New-Item -Path $using:targetPath -Force | Out-Null } | Out-Null }
                    }

                    try {
                        New-ItemProperty -LiteralPath $targetPath -Name $valueName -PropertyType $valueKind -Value $valueData -Force | Out-Null
                    } catch {
                        $tiTP = $targetPath; $tiVN = $valueName; $tiVK = $valueKind; $tiVD = $valueData
                        Invoke-AsTrustedInstaller {
                            New-ItemProperty -LiteralPath $using:tiTP -Name $using:tiVN -PropertyType $using:tiVK -Value $using:tiVD -Force | Out-Null
                        } | Out-Null
                    }
                    $restoredRegistryValue = $true
                }

                if (Test-Path -LiteralPath $storePath) {
                    Remove-ItemProperty -LiteralPath $storePath -Name $Item.RecordId -ErrorAction SilentlyContinue
                }
            }
            elseif (-not (Test-Path -LiteralPath $targetPath)) {
                return [pscustomobject]@{ Ok=$false; Message="missing registry path for $($Item.DisplayName): $targetPath" }
            }

            $startupApprovedPath = [string]$Item.StartupApprovedPath
            if ([string]::IsNullOrWhiteSpace($startupApprovedPath)) {
                $startupApprovedPath = Get-AutostartRegistryStartupApprovedPath -RegistryPath $targetPath
            }
            if (-not [string]::IsNullOrWhiteSpace($startupApprovedPath)) {
                Set-AutostartStartupApprovedStatus -StartupApprovedPath $startupApprovedPath -Name $valueName -Enable:$true
            }

            Set-AutostartObjectProperty -Object $Item -Name 'Enabled' -Value $true
            Set-AutostartObjectProperty -Object $Item -Name 'RegistryPath' -Value $targetPath
            Set-AutostartObjectProperty -Object $Item -Name 'DisplayName' -Value $valueName
            Set-AutostartObjectProperty -Object $Item -Name 'EntryName' -Value $valueName
            Set-AutostartObjectProperty -Object $Item -Name 'ValueKind' -Value $valueKind
            Set-AutostartObjectProperty -Object $Item -Name 'ValueData' -Value $valueData
            Set-AutostartObjectProperty -Object $Item -Name 'Details' -Value (Format-AutostartPreviewText -Text $valueData -MaxLength 140)
            Set-AutostartObjectProperty -Object $Item -Name 'DisabledRecord' -Value $null
            Set-AutostartObjectProperty -Object $Item -Name 'StartupApprovedPath' -Value $startupApprovedPath
            Set-AutostartObjectProperty -Object $Item -Name 'StartupApprovedState' -Value 'Enabled'
            Set-AutostartObjectProperty -Object $Item -Name 'StartupApprovedExists' -Value (-not [string]::IsNullOrWhiteSpace($startupApprovedPath))
            Set-AutostartObjectProperty -Object $Item -Name 'StartupApprovedData' -Value (New-AutostartStartupApprovedBinary -Enable:$true)

            if ($restoredRegistryValue) {
                return [pscustomobject]@{ Ok=$true; Message="enabled registry startup and restored saved Run value: $valueName" }
            }
            return [pscustomobject]@{ Ok=$true; Message="enabled registry startup without overwriting existing Run value: $valueName" }
        }

        if (-not $Item.Enabled) { return [pscustomobject]@{ Ok=$true; Message="already disabled: $($Item.DisplayName)" } }

        $startupApprovedPath = [string]$Item.StartupApprovedPath
        if ([string]::IsNullOrWhiteSpace($startupApprovedPath)) {
            $startupApprovedPath = Get-AutostartRegistryStartupApprovedPath -RegistryPath ([string]$Item.RegistryPath)
        }

        if (-not [string]::IsNullOrWhiteSpace($startupApprovedPath)) {
            Set-AutostartStartupApprovedStatus -StartupApprovedPath $startupApprovedPath -Name ([string]$Item.EntryName) -Enable:$false

            Set-AutostartObjectProperty -Object $Item -Name 'Enabled' -Value $false
            Set-AutostartObjectProperty -Object $Item -Name 'StartupApprovedPath' -Value $startupApprovedPath
            Set-AutostartObjectProperty -Object $Item -Name 'StartupApprovedState' -Value 'Disabled'
            Set-AutostartObjectProperty -Object $Item -Name 'StartupApprovedExists' -Value $true
            Set-AutostartObjectProperty -Object $Item -Name 'StartupApprovedData' -Value (New-AutostartStartupApprovedBinary -Enable:$false)

            return [pscustomobject]@{ Ok=$true; Message="disabled registry startup through Windows Startup Apps: $($Item.DisplayName)" }
        }

        try { New-Item -Path $storePath -Force | Out-Null }
        catch { Invoke-AsTrustedInstaller { New-Item -Path $using:storePath -Force | Out-Null } | Out-Null }
        $record = [ordered]@{
            Kind = 'Registry'
            Source = [string]$Item.Source
            RegistryPath = [string]$Item.RegistryPath
            Name = [string]$Item.EntryName
            ValueKind = [string]$Item.ValueKind
            Data = (ConvertTo-AutostartRegistryRecordData -Value $Item.ValueData -ValueKind ([string]$Item.ValueKind))
            DisabledAt = (Get-Date).ToString('o')
        }
        $json = $record | ConvertTo-Json -Compress -Depth 6
        try {
            New-ItemProperty -LiteralPath $storePath -Name $Item.RecordId -PropertyType String -Value $json -Force | Out-Null
        } catch {
            $tiSP = $storePath; $tiRID = $Item.RecordId; $tiJSON = $json
            Invoke-AsTrustedInstaller {
                New-ItemProperty -LiteralPath $using:tiSP -Name $using:tiRID -PropertyType String -Value $using:tiJSON -Force | Out-Null
            } | Out-Null
        }

        try {
            Remove-ItemProperty -LiteralPath $Item.RegistryPath -Name $Item.EntryName -ErrorAction Stop
        }
        catch {
            $tiRP = $Item.RegistryPath; $tiEN = $Item.EntryName
            $tiOk = Invoke-AsTrustedInstaller {
                Remove-ItemProperty -LiteralPath $using:tiRP -Name $using:tiEN -ErrorAction Stop
            }
            if (-not $tiOk) {
                Remove-ItemProperty -LiteralPath $storePath -Name $Item.RecordId -ErrorAction SilentlyContinue
                throw
            }
        }

        Set-AutostartObjectProperty -Object $Item -Name 'Enabled' -Value $false
        Set-AutostartObjectProperty -Object $Item -Name 'DisabledRecord' -Value ([pscustomobject]$record)
        Set-AutostartObjectProperty -Object $Item -Name 'ValueData' -Value $record.Data

        return [pscustomobject]@{ Ok=$true; Message="disabled registry startup by removing Run value: $($Item.DisplayName)" }
    }
    catch {
        return [pscustomobject]@{ Ok=$false; Message="$($Item.DisplayName) -> $($_.Exception.Message)" }
    }
}

function Set-AutostartFolderItemStatus {
    param(
        [Parameter(Mandatory=$true)][object]$Item,
        [Parameter(Mandatory=$true)][bool]$Enable
    )

    try {
        $fileName = Split-Path -Leaf $Item.Path
        if ($Enable) {
            if ($Item.Enabled) { return [pscustomobject]@{ Ok=$true; Message="already enabled: $($Item.DisplayName)" } }
            if (-not (Test-Path -LiteralPath $Item.Path -PathType Leaf)) { return [pscustomobject]@{ Ok=$false; Message="missing disabled startup file: $($Item.Path)" } }
            if (-not (Test-Path -LiteralPath $Item.Folder)) { New-Item -ItemType Directory -Path $Item.Folder -Force | Out-Null }
            $targetPath = Join-Path -Path $Item.Folder -ChildPath $fileName
            if (Test-Path -LiteralPath $targetPath) { return [pscustomobject]@{ Ok=$false; Message="cannot enable; target already exists: $targetPath" } }
            Move-Item -LiteralPath $Item.Path -Destination $targetPath -ErrorAction Stop

            Set-AutostartObjectProperty -Object $Item -Name 'Enabled' -Value $true
            Set-AutostartObjectProperty -Object $Item -Name 'Path' -Value $targetPath
            Set-AutostartObjectProperty -Object $Item -Name 'Details' -Value $targetPath

            return [pscustomobject]@{ Ok=$true; Message="enabled startup folder item: $fileName" }
        }

        if (-not $Item.Enabled) { return [pscustomobject]@{ Ok=$true; Message="already disabled: $($Item.DisplayName)" } }
        if (-not (Test-Path -LiteralPath $Item.Path -PathType Leaf)) { return [pscustomobject]@{ Ok=$false; Message="missing startup file: $($Item.Path)" } }
        if (-not (Test-Path -LiteralPath $Item.DisabledFolder)) { New-Item -ItemType Directory -Path $Item.DisabledFolder -Force | Out-Null }
        $targetPath = Join-Path -Path $Item.DisabledFolder -ChildPath $fileName
        if (Test-Path -LiteralPath $targetPath) { return [pscustomobject]@{ Ok=$false; Message="cannot disable; disabled copy already exists: $targetPath" } }
        Move-Item -LiteralPath $Item.Path -Destination $targetPath -ErrorAction Stop

        Set-AutostartObjectProperty -Object $Item -Name 'Enabled' -Value $false
        Set-AutostartObjectProperty -Object $Item -Name 'Path' -Value $targetPath
        Set-AutostartObjectProperty -Object $Item -Name 'Details' -Value $targetPath

        return [pscustomobject]@{ Ok=$true; Message="disabled startup folder item: $fileName" }
    }
    catch {
        return [pscustomobject]@{ Ok=$false; Message="$($Item.DisplayName) -> $($_.Exception.Message)" }
    }
}

function Set-AutostartScheduledTaskStatus {
    param(
        [Parameter(Mandatory=$true)][object]$Item,
        [Parameter(Mandatory=$true)][bool]$Enable
    )

    try {
        if ($Enable) {
            if ($Item.Enabled) { return [pscustomobject]@{ Ok=$true; Message="already enabled: $($Item.DisplayName)" } }

            $status = Set-ScheduledTaskAutostartTriggerStatus -TaskName ([string]$Item.TaskName) -TaskPath ([string]$Item.TaskPath) -Enable:$true

            Set-AutostartObjectProperty -Object $Item -Name 'Enabled' -Value ($status.EnabledAutostartTriggerCount -gt 0)
            Set-AutostartObjectProperty -Object $Item -Name 'TaskState' -Value ([string]$status.TaskState)
            Set-AutostartObjectProperty -Object $Item -Name 'TaskGloballyEnabled' -Value ([bool]$status.TaskGloballyEnabled)
            Set-AutostartObjectProperty -Object $Item -Name 'AutostartTriggerCount' -Value ([int]$status.AutostartTriggerCount)
            Set-AutostartObjectProperty -Object $Item -Name 'EnabledAutostartTriggerCount' -Value ([int]$status.EnabledAutostartTriggerCount)
            Set-AutostartObjectProperty -Object $Item -Name 'DisabledAutostartTriggerCount' -Value ([int]$status.DisabledAutostartTriggerCount)
            Set-AutostartObjectProperty -Object $Item -Name 'Details' -Value ([string]$status.Details)

            if (-not $status.TaskGloballyEnabled) {
                return [pscustomobject]@{ Ok=$true; Message="enabled scheduled task autostart trigger(s), but the task itself remains disabled: $($Item.DisplayName)" }
            }

            return [pscustomobject]@{ Ok=$true; Message="enabled scheduled task autostart trigger(s): $($Item.DisplayName)" }
        }

        if (-not $Item.Enabled) { return [pscustomobject]@{ Ok=$true; Message="already disabled: $($Item.DisplayName)" } }

        $status = Set-ScheduledTaskAutostartTriggerStatus -TaskName ([string]$Item.TaskName) -TaskPath ([string]$Item.TaskPath) -Enable:$false

        Set-AutostartObjectProperty -Object $Item -Name 'Enabled' -Value ($status.EnabledAutostartTriggerCount -gt 0)
        Set-AutostartObjectProperty -Object $Item -Name 'TaskState' -Value ([string]$status.TaskState)
        Set-AutostartObjectProperty -Object $Item -Name 'TaskGloballyEnabled' -Value ([bool]$status.TaskGloballyEnabled)
        Set-AutostartObjectProperty -Object $Item -Name 'AutostartTriggerCount' -Value ([int]$status.AutostartTriggerCount)
        Set-AutostartObjectProperty -Object $Item -Name 'EnabledAutostartTriggerCount' -Value ([int]$status.EnabledAutostartTriggerCount)
        Set-AutostartObjectProperty -Object $Item -Name 'DisabledAutostartTriggerCount' -Value ([int]$status.DisabledAutostartTriggerCount)
        Set-AutostartObjectProperty -Object $Item -Name 'Details' -Value ([string]$status.Details)

        return [pscustomobject]@{ Ok=$true; Message="disabled only scheduled task autostart trigger(s), leaving the task itself and other triggers unchanged: $($Item.DisplayName)" }
    }
    catch {
        return [pscustomobject]@{ Ok=$false; Message="$($Item.DisplayName) -> $($_.Exception.Message)" }
    }
}

function Set-AutostartItemStatus {
    param(
        [Parameter(Mandatory=$true)][object]$Item,
        [Parameter(Mandatory=$true)][bool]$Enable
    )

    switch ($Item.Kind) {
        'Registry' { return (Set-AutostartRegistryItemStatus -Item $Item -Enable:$Enable) }
        'StartupFolder' { return (Set-AutostartFolderItemStatus -Item $Item -Enable:$Enable) }
        'ScheduledTask' { return (Set-AutostartScheduledTaskStatus -Item $Item -Enable:$Enable) }
        default { return [pscustomobject]@{ Ok=$false; Message="unsupported autostart item type: $($Item.Kind)" } }
    }
}

function Invoke-AutostartManager {
    $items = @(Get-AutostartItems)
    [void](Invoke-AutostartFullListMenu -Title 'Autostart' -Items $items)
}

function ConvertTo-MenuGpuPlainName {
    param([AllowNull()][object]$Name)

    if ($null -eq $Name) { return '' }

    if (($Name -is [System.Collections.IEnumerable]) -and -not ($Name -is [string])) {
        foreach ($value in $Name) {
            $cleanValue = ConvertTo-MenuGpuPlainName $value
            if (-not [string]::IsNullOrWhiteSpace([string]$cleanValue)) { return [string]$cleanValue }
        }
        return ''
    }

    $text = ([string]$Name).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return '' }

    if ($text.IndexOf(';') -ge 0) {
        $parts = @($text -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        if ($parts.Count -gt 0) { $text = ([string]$parts[$parts.Count - 1]).Trim() }
    }

    $text = $text -replace '^"|"$', ''
    $text = [regex]::Replace($text, '(?i)\s*\[[0-9A-F]{4}(?::|&)[0-9A-F]{4}(?:(?::|&)[0-9A-F]{4}){0,2}\]\s*', ' ')
    $text = [regex]::Replace($text, '(?i)\s*\(?\bPCI\\VEN_[0-9A-F]{4}&DEV_[0-9A-F]{4}(?:&[A-Z0-9_]+)*(?:\\[A-Z0-9&]+)?\)?\s*', ' ')
    $text = [regex]::Replace($text, '(?i)\bVEN_[0-9A-F]{4}&DEV_[0-9A-F]{4}(?:&[A-Z0-9_]+)*\b', ' ')
    $text = [regex]::Replace($text, '\s+', ' ').Trim()
    $text = $text.Trim((" `t`r`n-:,.()").ToCharArray())

    if ([string]::IsNullOrWhiteSpace($text)) { return '' }
    if ($text -match '^(?i:PCI|VEN_|DEV_|SUBSYS_|REV_)') { return '' }
    return $text
}

function Test-MenuGpuNameToken {
    param([AllowNull()][object]$Value)

    $text = ConvertTo-MenuGpuPlainName $Value
    if ([string]::IsNullOrWhiteSpace($text)) { return $false }

    foreach ($token in @('AMD', 'NVIDIA', 'Radeon', 'GeForce', 'Intel', 'Arc', 'RTX', 'GTX')) {
        if ($text.IndexOf($token, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true }
    }

    return $false
}


function Normalize-MenuPciIdsDisplayText {
    param([AllowNull()][object]$Text)

    $value = ConvertTo-MenuGpuPlainName $Text
    if ([string]::IsNullOrWhiteSpace($value)) { return '' }

    $value = $value -replace '\s*\[[^\]]*\]\s*$', ''
    $value = $value -replace '\s*,?\s*(Corporation|Corp\.?|Incorporated|Inc\.?|Company|Co\.?,?\s*Ltd\.?|Co\.?,?\s*Limited|Ltd\.?|Limited|GmbH|S\.A\.|S\.p\.A\.|AG|KG|LLC|PLC)\s*$', ''
    $value = $value -replace '\s+', ' '
    return $value.Trim((" `t`r`n,.-").ToCharArray())
}

function Get-MenuPciIdsPath {
    try {
        $base = Get-OriginalScriptFolder
        if (-not [string]::IsNullOrWhiteSpace([string]$base)) { return (Join-Path -Path $base -ChildPath 'pci.ids') }
    } catch { }

    try { return (Join-Path -Path ([string](Get-Location)) -ChildPath 'pci.ids') } catch { return 'pci.ids' }
}

function Get-MenuPciIdentity {
    param(
        [AllowNull()][string]$InstanceId,
        [AllowNull()][string]$HardwareId
    )

    $text = (([string]$InstanceId) + ' ' + ([string]$HardwareId)).ToUpperInvariant()
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }

    $vendorId = ''
    $deviceId = ''
    $subVendorId = ''
    $subDeviceId = ''

    $vendorMatch = [regex]::Match($text, 'VEN_([0-9A-F]{4})', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($vendorMatch.Success) { $vendorId = $vendorMatch.Groups[1].Value.ToUpperInvariant() }

    $deviceMatch = [regex]::Match($text, 'DEV_([0-9A-F]{4})', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($deviceMatch.Success) { $deviceId = $deviceMatch.Groups[1].Value.ToUpperInvariant() }

    $subsysMatch = [regex]::Match($text, 'SUBSYS_([0-9A-F]{8})', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($subsysMatch.Success) {
        $subsys = $subsysMatch.Groups[1].Value.ToUpperInvariant()
        $subDeviceId = $subsys.Substring(0, 4)
        $subVendorId = $subsys.Substring(4, 4)
    }

    if ([string]::IsNullOrWhiteSpace($vendorId) -or [string]::IsNullOrWhiteSpace($deviceId)) { return $null }

    return [pscustomobject]@{
        VendorId    = $vendorId
        DeviceId    = $deviceId
        SubVendorId = $subVendorId
        SubDeviceId = $subDeviceId
    }
}

function Find-MenuPciIdsResolvedParts {
    param([AllowNull()][object]$Identity)

    if ($null -eq $Identity) { return $null }

    $vendorId = ([string]$Identity.VendorId).ToUpperInvariant()
    $deviceId = ([string]$Identity.DeviceId).ToUpperInvariant()
    $subVendorId = if ([string]::IsNullOrWhiteSpace([string]$Identity.SubVendorId)) { '' } else { ([string]$Identity.SubVendorId).ToUpperInvariant() }
    $subDeviceId = if ([string]::IsNullOrWhiteSpace([string]$Identity.SubDeviceId)) { '' } else { ([string]$Identity.SubDeviceId).ToUpperInvariant() }

    if ([string]::IsNullOrWhiteSpace($vendorId) -or [string]::IsNullOrWhiteSpace($deviceId)) { return $null }

    $pciIdsPath = Get-MenuPciIdsPath
    if (-not [System.IO.File]::Exists($pciIdsPath)) { return $null }

    $vendorName = ''
    $deviceName = ''
    $subVendorName = ''
    $subsystemName = ''
    $currentVendor = ''
    $currentDevice = ''

    try {
        foreach ($rawLine in [System.IO.File]::ReadLines($pciIdsPath)) {
            if ([string]::IsNullOrWhiteSpace($rawLine)) { continue }
            if ($rawLine[0] -eq '#') { continue }

            if ($rawLine[0] -ne "`t") {
                if ($rawLine.Length -ge 5 -and [char]::IsWhiteSpace($rawLine[4])) {
                    $possibleVendor = $rawLine.Substring(0,4).ToUpperInvariant()
                    if ($possibleVendor -match '^[0-9A-F]{4}$') {
                        $currentVendor = $possibleVendor
                        $currentDevice = ''

                        if ($currentVendor -eq $vendorId -and [string]::IsNullOrWhiteSpace($vendorName)) {
                            $vendorName = Normalize-MenuPciIdsDisplayText ($rawLine.Substring(5))
                        }
                        if (-not [string]::IsNullOrWhiteSpace($subVendorId) -and $currentVendor -eq $subVendorId -and [string]::IsNullOrWhiteSpace($subVendorName)) {
                            $subVendorName = Normalize-MenuPciIdsDisplayText ($rawLine.Substring(5))
                        }
                    } else {
                        $currentVendor = ''
                        $currentDevice = ''
                    }
                } else {
                    $currentVendor = ''
                    $currentDevice = ''
                }
                continue
            }

            if ($rawLine.Length -gt 1 -and $rawLine[1] -eq "`t") {
                if ($currentVendor -eq $vendorId -and $currentDevice -eq $deviceId -and -not [string]::IsNullOrWhiteSpace($subVendorId) -and -not [string]::IsNullOrWhiteSpace($subDeviceId)) {
                    $subLine = $rawLine.Substring(2).TrimStart()
                    if ($subLine.Length -ge 10) {
                        $parts = $subLine -split '\s+', 3
                        if ($parts.Count -ge 3) {
                            $sv = ([string]$parts[0]).ToUpperInvariant()
                            $sd = ([string]$parts[1]).ToUpperInvariant()
                            if ($sv -eq $subVendorId -and $sd -eq $subDeviceId) {
                                $subsystemName = Normalize-MenuPciIdsDisplayText $parts[2]
                            }
                        }
                    }
                }
                continue
            }

            if ($currentVendor -eq $vendorId) {
                $deviceLine = $rawLine.Substring(1).TrimStart()
                if ($deviceLine.Length -ge 6) {
                    $possibleDevice = $deviceLine.Substring(0,4).ToUpperInvariant()
                    if ($possibleDevice -match '^[0-9A-F]{4}$') {
                        $currentDevice = $possibleDevice
                        if ($currentDevice -eq $deviceId -and [string]::IsNullOrWhiteSpace($deviceName)) {
                            $deviceTextStart = 4
                            while ($deviceTextStart -lt $deviceLine.Length -and [char]::IsWhiteSpace($deviceLine[$deviceTextStart])) { $deviceTextStart++ }
                            if ($deviceTextStart -lt $deviceLine.Length) {
                                $deviceName = Normalize-MenuPciIdsDisplayText ($deviceLine.Substring($deviceTextStart))
                            }
                        }
                    } else {
                        $currentDevice = ''
                    }
                }
            }

            if (-not [string]::IsNullOrWhiteSpace($vendorName) -and
                -not [string]::IsNullOrWhiteSpace($deviceName) -and
                ([string]::IsNullOrWhiteSpace($subVendorId) -or -not [string]::IsNullOrWhiteSpace($subVendorName)) -and
                ([string]::IsNullOrWhiteSpace($subVendorId) -or [string]::IsNullOrWhiteSpace($subDeviceId) -or -not [string]::IsNullOrWhiteSpace($subsystemName))) {
                break
            }
        }

        return [pscustomobject]@{
            VendorName    = $vendorName
            DeviceName    = $deviceName
            SubVendorName = $subVendorName
            SubsystemName = $subsystemName
        }
    } catch {
        return $null
    }
}

function Remove-MenuLeadingVendorFromName {
    param(
        [AllowNull()][string]$Name,
        [AllowNull()][string]$VendorName
    )

    $nameText = ConvertTo-MenuGpuPlainName $Name
    $vendorText = Normalize-MenuPciIdsDisplayText $VendorName
    if ([string]::IsNullOrWhiteSpace($nameText) -or [string]::IsNullOrWhiteSpace($vendorText)) { return $nameText }

    $candidates = New-Object System.Collections.Generic.List[string]
    [void]$candidates.Add($vendorText)
    $vendorTokens = @($vendorText -split '\s+' | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($vendorTokens.Count -gt 0) { [void]$candidates.Add([string]$vendorTokens[0]) }

    foreach ($candidate in $candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        $pattern = '^' + [regex]::Escape($candidate) + '(\s+|[-:]+\s*)'
        $updated = [regex]::Replace($nameText, $pattern, '', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase).Trim()
        if ($updated -ne $nameText) { return $updated }
    }

    return $nameText
}

function Join-MenuGpuDisplayNameParts {
    param([AllowNull()][string[]]$Parts)

    $result = New-Object System.Collections.Generic.List[string]
    foreach ($part in @($Parts)) {
        $text = ConvertTo-MenuGpuPlainName $part
        if ([string]::IsNullOrWhiteSpace($text)) { continue }

        $already = $false
        foreach ($existing in $result) {
            if ([string]::Equals([string]$existing, $text, [System.StringComparison]::OrdinalIgnoreCase)) { $already = $true; break }
        }
        if (-not $already) { [void]$result.Add($text) }
    }

    return (($result.ToArray()) -join ' ').Trim()
}

function Resolve-MenuPciResolvedGpuName {
    param(
        [AllowNull()][string]$InstanceId,
        [AllowNull()][string]$HardwareId,
        [AllowNull()][object]$WindowsName
    )

    $baseName = ConvertTo-MenuGpuPlainName $WindowsName
    $identity = Get-MenuPciIdentity -InstanceId $InstanceId -HardwareId $HardwareId
    if ($null -eq $identity) { return $baseName }

    $parts = Find-MenuPciIdsResolvedParts -Identity $identity
    if ($null -eq $parts) { return $baseName }

    $vendorName = [string]$parts.VendorName
    $subVendorName = [string]$parts.SubVendorName
    $subsystemName = [string]$parts.SubsystemName

    if (-not [string]::IsNullOrWhiteSpace($subsystemName)) {
        if (-not [string]::IsNullOrWhiteSpace($subVendorName) -and $subsystemName.IndexOf($subVendorName, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
            $subVendorFirst = @($subVendorName -split '\s+' | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
            if ($subVendorFirst.Count -eq 0 -or $subsystemName.IndexOf([string]$subVendorFirst[0], [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
                return (Join-MenuGpuDisplayNameParts @($subVendorName, $subsystemName))
            }
        }
        return $subsystemName
    }

    if (-not [string]::IsNullOrWhiteSpace($subVendorName) -and -not [string]::IsNullOrWhiteSpace($baseName)) {
        $chipVendor = if (-not [string]::IsNullOrWhiteSpace($vendorName)) { $vendorName } else { $subVendorName }
        $chipSuffix = Remove-MenuLeadingVendorFromName -Name $baseName -VendorName $chipVendor
        if (-not [string]::IsNullOrWhiteSpace($chipSuffix) -and $subVendorName.IndexOf($chipVendor, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
            return (Join-MenuGpuDisplayNameParts @($subVendorName, $chipSuffix))
        }
    }

    return $baseName
}

function Get-MenuPciClassCode {
    param([AllowNull()][object[]]$Values)

    if ($null -eq $Values) { return '' }
    foreach ($value in $Values) {
        if ($null -eq $value) { continue }
        if (($value -is [System.Collections.IEnumerable]) -and -not ($value -is [string])) {
            foreach ($nestedValue in $value) {
                $nested = Get-MenuPciClassCode -Values @($nestedValue)
                if (-not [string]::IsNullOrWhiteSpace([string]$nested)) { return [string]$nested }
            }
            continue
        }

        $text = [string]$value
        if ([string]::IsNullOrWhiteSpace($text)) { continue }

        $rawMatch = [regex]::Match($text.Trim(), '^(?:CC_)?(?:0x)?([0-9A-Fa-f]{4,6})$')
        if ($rawMatch.Success) {
            $raw = $rawMatch.Groups[1].Value.ToUpperInvariant()
            if ($raw.Length -ge 4) { return $raw.Substring(0, 4) }
            return $raw
        }

        $match = [regex]::Match($text, 'CC_([0-9A-Fa-f]{4,6})', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($match.Success) {
            $raw = $match.Groups[1].Value.ToUpperInvariant()
            if ($raw.Length -ge 4) { return $raw.Substring(0, 4) }
            return $raw
        }
    }

    return ''
}

function Test-MenuPciDisplayControllerClassCode {
    param([AllowNull()][object]$ClassCode)

    if ($null -eq $ClassCode) { return $false }
    $text = ([string]$ClassCode).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return $false }
    if ($text.StartsWith('CC_', [System.StringComparison]::OrdinalIgnoreCase)) { $text = $text.Substring(3) }
    if ($text.StartsWith('0x', [System.StringComparison]::OrdinalIgnoreCase)) { $text = $text.Substring(2) }
    return ($text.Length -ge 2 -and $text.StartsWith('03', [System.StringComparison]::OrdinalIgnoreCase))
}

function Get-MenuPciLookupInstanceId {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return '' }
    $text = ([string]$Value).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return '' }

    $match = [regex]::Match($text, '(?i)PCI\\VEN_[0-9A-F]{4}&DEV_[0-9A-F]{4}[^\\]*\\[^\\]+')
    if ($match.Success) { return $match.Value.ToUpperInvariant() }

    return ''
}

function Get-MenuPciLookupHardwareId {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return '' }
    $text = ([string]$Value).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return '' }

    $match = [regex]::Match($text, '(?i)PCI\\(VEN_[0-9A-F]{4}&DEV_[0-9A-F]{4}[^\\\s]*)')
    if ($match.Success) { return ('PCI\' + $match.Groups[1].Value).ToUpperInvariant() }

    $match = [regex]::Match($text, '(?i)\b(VEN_[0-9A-F]{4}&DEV_[0-9A-F]{4}[^\\\s]*)')
    if ($match.Success) { return ('PCI\' + $match.Groups[1].Value).ToUpperInvariant() }

    return ''
}

function Add-MenuStringListUnique {
    param(
        [Parameter(Mandatory=$true)][object]$List,
        [AllowNull()][object]$Value
    )

    $text = ConvertTo-MenuGpuPlainName $Value
    if ([string]::IsNullOrWhiteSpace($text)) { return }

    foreach ($existing in $List) {
        if ([string]::Equals([string]$existing, $text, [System.StringComparison]::OrdinalIgnoreCase)) { return }
    }

    [void]$List.Add($text)
}

function Add-MenuGpuCandidate {
    param(
        [Parameter(Mandatory=$true)][object]$Candidates,
        [AllowNull()][object]$Name,
        [int]$Bonus = 0
    )

    $clean = ConvertTo-MenuGpuPlainName $Name
    if ([string]::IsNullOrWhiteSpace($clean)) { return }

    foreach ($candidate in $Candidates) {
        if ([string]::Equals([string]$candidate.Name, $clean, [System.StringComparison]::OrdinalIgnoreCase)) { return }
    }

    $score = $Bonus
    if (Test-MenuGpuNameToken $clean) { $score += 100 }
    if ($clean -match '(?i)(GeForce|Radeon|RTX|GTX|RX\s*\d|Arc|UHD|Iris)') { $score += 40 }
    if ($clean -match '(?i)(Basic Display|Remote Display|Render Driver|Microsoft)') { $score -= 120 }
    $score += [Math]::Min(30, $clean.Length)

    [void]$Candidates.Add([pscustomobject]@{ Name = $clean; Score = $score })
}

function Add-MenuNameMapValue {
    param(
        [Parameter(Mandatory=$true)][object]$Map,
        [AllowNull()][string]$Key,
        [AllowNull()][object]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Key)) { return }
    $clean = ConvertTo-MenuGpuPlainName $Name
    if ([string]::IsNullOrWhiteSpace($clean)) { return }

    if (-not $Map.ContainsKey($Key)) {
        $Map[$Key] = New-Object System.Collections.Generic.List[string]
    }

    Add-MenuStringListUnique -List $Map[$Key] -Value $clean
}

function Get-MenuDisplayPnpGpuDevices {
    $items = New-Object System.Collections.Generic.List[object]
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

    try {
        foreach ($device in @(Get-PnpDevice -Class Display -ErrorAction Stop)) {
            $instanceId = [string]$device.InstanceId
            if ([string]::IsNullOrWhiteSpace($instanceId)) { continue }
            if (-not $seen.Add($instanceId)) { continue }
            [void]$items.Add([pscustomobject]@{
                Name        = [string]$device.FriendlyName
                InstanceId  = $instanceId
                HardwareIds = @()
                Status      = [string]$device.Status
            })
        }
    } catch { }

    $pnpEntities = @()
    try {
        $pnpEntities = @(Get-CimInstance -ClassName Win32_PnPEntity -Filter "PNPClass='Display'" -ErrorAction Stop)
    } catch {
        try { $pnpEntities = @(Get-WmiObject -Class Win32_PnPEntity -Filter "PNPClass='Display'" -ErrorAction Stop) } catch { $pnpEntities = @() }
    }

    foreach ($device in $pnpEntities) {
        $instanceId = if ($device.PNPDeviceID) { [string]$device.PNPDeviceID } elseif ($device.DeviceID) { [string]$device.DeviceID } else { '' }
        if ([string]::IsNullOrWhiteSpace($instanceId)) { continue }
        if (-not $seen.Add($instanceId)) { continue }

        $hardwareIds = @()
        $hardwareProperty = $device.PSObject.Properties['HardwareID']
        if ($hardwareProperty -and $null -ne $hardwareProperty.Value) { $hardwareIds = @($hardwareProperty.Value) }

        [void]$items.Add([pscustomobject]@{
            Name        = [string]$device.Name
            InstanceId  = $instanceId
            HardwareIds = $hardwareIds
            Status      = [string]$device.Status
        })
    }

    $videoControllers = @()
    try {
        $videoControllers = @(Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop)
    } catch {
        try { $videoControllers = @(Get-WmiObject -Class Win32_VideoController -ErrorAction Stop) } catch { $videoControllers = @() }
    }

    foreach ($controller in $videoControllers) {
        $instanceId = if ($controller.PNPDeviceID) { [string]$controller.PNPDeviceID } else { 'VIDEO:' + [string]$controller.Name }
        if ([string]::IsNullOrWhiteSpace($instanceId)) { continue }
        if (-not $seen.Add($instanceId)) { continue }

        [void]$items.Add([pscustomobject]@{
            Name        = [string]$controller.Name
            InstanceId  = $instanceId
            HardwareIds = @()
            Status      = [string]$controller.Status
        })
    }

    return @($items.ToArray())
}

function Get-MenuPciEnumGpuRecords {
    $records = New-Object System.Collections.Generic.List[object]
    $root = 'HKLM:\SYSTEM\CurrentControlSet\Enum\PCI'
    if (-not (Test-Path -LiteralPath $root)) { return @() }

    foreach ($vendorKey in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
        foreach ($instanceKey in @(Get-ChildItem -LiteralPath $vendorKey.PSPath -ErrorAction SilentlyContinue)) {
            try { $props = Get-ItemProperty -LiteralPath $instanceKey.PSPath -ErrorAction Stop } catch { continue }

            $hardwareIds = @()
            $hardwareProperty = $props.PSObject.Properties['HardwareID']
            if ($hardwareProperty -and $null -ne $hardwareProperty.Value) { $hardwareIds = @($hardwareProperty.Value) }

            $compatibleIds = @()
            $compatibleProperty = $props.PSObject.Properties['CompatibleIDs']
            if ($compatibleProperty -and $null -ne $compatibleProperty.Value) { $compatibleIds = @($compatibleProperty.Value) }

            $instanceId = 'PCI\' + [string]$vendorKey.PSChildName + '\' + [string]$instanceKey.PSChildName
            $hardwareId = if ($hardwareIds.Count -gt 0) { Get-MenuPciLookupHardwareId $hardwareIds[0] } else { Get-MenuPciLookupHardwareId ('PCI\' + [string]$vendorKey.PSChildName) }
            $classCode = Get-MenuPciClassCode -Values @($hardwareIds, $compatibleIds, $instanceId, $hardwareId, $instanceKey.PSPath)
            $desc = ConvertTo-MenuGpuPlainName $props.DeviceDesc

            [void]$records.Add([pscustomobject]@{
                InstanceId       = (Get-MenuPciLookupInstanceId $instanceId)
                HardwareId       = $hardwareId
                DeviceDesc       = $desc
                ClassCode        = $classCode
                IsGpuDescription = (Test-MenuGpuNameToken $desc)
                IsGpuClassCode   = (Test-MenuPciDisplayControllerClassCode $classCode)
            })
        }
    }

    return @($records.ToArray())
}

function Add-MenuDisplayClassGpuNameCandidates {
    param(
        [Parameter(Mandatory=$true)][object]$Candidates,
        [AllowNull()][string]$InstanceId,
        [AllowNull()][string]$HardwareId
    )

    $roots = @(
        'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}',
        'HKLM:\SYSTEM\ControlSet001\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
    )

    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        foreach ($key in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
            try { $props = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction Stop } catch { continue }

            $matchingDeviceId = ''
            $matchingProperty = $props.PSObject.Properties['MatchingDeviceId']
            if ($matchingProperty -and $null -ne $matchingProperty.Value) { $matchingDeviceId = [string]$matchingProperty.Value }

            $driverDesc = ''
            $driverDescProperty = $props.PSObject.Properties['DriverDesc']
            if ($driverDescProperty -and $null -ne $driverDescProperty.Value) { $driverDesc = [string]$driverDescProperty.Value }

            $adapterString = ''
            $adapterProperty = $props.PSObject.Properties['HardwareInformation.AdapterString']
            if ($adapterProperty -and $null -ne $adapterProperty.Value) { $adapterString = [string]$adapterProperty.Value }

            $matchText = ($matchingDeviceId + ' ' + $driverDesc + ' ' + $adapterString)
            $matchesDevice = $false
            if (-not [string]::IsNullOrWhiteSpace($HardwareId) -and $matchText.IndexOf($HardwareId, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { $matchesDevice = $true }
            if (-not $matchesDevice -and -not [string]::IsNullOrWhiteSpace($InstanceId) -and $matchText.IndexOf($InstanceId, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { $matchesDevice = $true }
            if (-not $matchesDevice -and (Test-MenuGpuNameToken $matchText)) { $matchesDevice = $true }
            if (-not $matchesDevice) { continue }

            Add-MenuGpuCandidate -Candidates $Candidates -Name $adapterString -Bonus 25
            Add-MenuGpuCandidate -Candidates $Candidates -Name $driverDesc -Bonus 15
        }
    }
}


function Get-MenuNetworkText {
    param([object]$Value)

    if ($null -eq $Value) { return '' }

    if ($Value -is [System.Array]) {
        foreach ($item in $Value) {
            $text = Get-MenuNetworkText $item
            if (-not [string]::IsNullOrWhiteSpace($text)) { return $text }
        }
        return ''
    }

    return ([string]$Value).Trim()
}

function First-MenuNetworkText {
    foreach ($item in $args) {
        $text = Get-MenuNetworkText $item
        if (-not [string]::IsNullOrWhiteSpace($text)) { return $text }
    }
    return ''
}

function Get-MenuNetworkObjectPropertyValue {
    param(
        [object]$Object,
        [string]$Name
    )

    if ($null -eq $Object -or [string]::IsNullOrWhiteSpace($Name)) { return $null }

    try {
        $property = $Object.PSObject.Properties[$Name]
        if ($null -ne $property) { return $property.Value }
    } catch { }

    try {
        return $Object.$Name
    } catch {
        return $null
    }
}

function Get-MenuNetworkObjectPropertyText {
    param(
        [object]$Object,
        [string]$Name
    )

    return Get-MenuNetworkText (Get-MenuNetworkObjectPropertyValue -Object $Object -Name $Name)
}

function Invoke-MenuNetworkAdapterQuery {
    param(
        [string]$Namespace,
        [string]$ClassName,
        [string]$Filter
    )

    try {
        if (Get-Command Get-CimInstance -ErrorAction SilentlyContinue) {
            return @(Get-CimInstance -Namespace $Namespace -ClassName $ClassName -Filter $Filter -ErrorAction Stop)
        }
    } catch { }

    try {
        return @(Get-WmiObject -Namespace $Namespace -Class $ClassName -Filter $Filter -ErrorAction Stop)
    } catch { }

    return @()
}

function Test-MenuPhysicalNetworkAdapter {
    param([object]$Adapter)

    if ($null -eq $Adapter) { return $false }
    if ([string]::IsNullOrWhiteSpace((Get-MenuNetworkObjectPropertyText -Object $Adapter -Name 'PNPDeviceID'))) { return $false }

    try {
        $virtual = Get-MenuNetworkObjectPropertyValue -Object $Adapter -Name 'Virtual'
        if ($null -ne $virtual -and [bool]$virtual) { return $false }
    } catch { }

    try {
        $hardwareInterface = Get-MenuNetworkObjectPropertyValue -Object $Adapter -Name 'HardwareInterface'
        if ($null -ne $hardwareInterface -and -not [bool]$hardwareInterface) { return $false }
    } catch { }

    try {
        $physicalAdapter = Get-MenuNetworkObjectPropertyValue -Object $Adapter -Name 'PhysicalAdapter'
        if ($null -ne $physicalAdapter -and -not [bool]$physicalAdapter) { return $false }
    } catch { }

    return $true
}

function New-MenuPhysicalNetworkAdapterInfo {
    param(
        [object]$Adapter,
        [string]$Source = ''
    )

    $name = First-MenuNetworkText `
        (Get-MenuNetworkObjectPropertyText -Object $Adapter -Name 'InterfaceDescription') `
        (Get-MenuNetworkObjectPropertyText -Object $Adapter -Name 'Name') `
        (Get-MenuNetworkObjectPropertyText -Object $Adapter -Name 'NetConnectionID')

    [pscustomobject]@{
        Name                 = $name
        InterfaceDescription = First-MenuNetworkText (Get-MenuNetworkObjectPropertyText -Object $Adapter -Name 'InterfaceDescription') $name
        PNPDeviceID          = Get-MenuNetworkObjectPropertyText -Object $Adapter -Name 'PNPDeviceID'
        Source               = Get-MenuNetworkText $Source
    }
}

function Remove-MenuDuplicateNetworkAdaptersByPnpId {
    param([object[]]$Adapters)

    $seen = @{}
    $result = @()

    foreach ($adapter in @($Adapters)) {
        if ($null -eq $adapter) { continue }
        $pnp = Get-MenuNetworkText $adapter.PNPDeviceID
        if ([string]::IsNullOrWhiteSpace($pnp)) { continue }

        $key = $pnp.ToUpperInvariant()
        if ($seen.ContainsKey($key)) { continue }

        $seen[$key] = $true
        $result += $adapter
    }

    return @($result)
}

function Get-MenuPhysicalNetworkAdapters {
    $candidates = @()
    $win32Infos = @()

    $win32Adapters = Invoke-MenuNetworkAdapterQuery -Namespace 'root\cimv2' -ClassName 'Win32_NetworkAdapter' -Filter 'PhysicalAdapter=True'
    foreach ($adapter in @($win32Adapters)) {
        if (-not (Test-MenuPhysicalNetworkAdapter $adapter)) { continue }
        $win32Infos += New-MenuPhysicalNetworkAdapterInfo -Adapter $adapter -Source 'Win32_NetworkAdapter'
    }

    $msftAdapters = Invoke-MenuNetworkAdapterQuery -Namespace 'root\StandardCimv2' -ClassName 'MSFT_NetAdapter' -Filter 'Virtual=False'
    foreach ($adapter in @($msftAdapters)) {
        if (-not (Test-MenuPhysicalNetworkAdapter $adapter)) { continue }
        $candidates += New-MenuPhysicalNetworkAdapterInfo -Adapter $adapter -Source 'MSFT_NetAdapter'
    }

    $candidates = Remove-MenuDuplicateNetworkAdaptersByPnpId $candidates
    $win32Infos = Remove-MenuDuplicateNetworkAdaptersByPnpId $win32Infos

    if (@($candidates).Count -gt 0) {
        return @($candidates)
    }

    return @($win32Infos)
}

function Get-MenuRegistryStringValue {
    param(
        [string]$Path,
        [string]$Name
    )

    try {
        $item = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop
        return Get-MenuNetworkText $item.$Name
    } catch {
        return ''
    }
}

function Resolve-MenuNetworkDriverImagePath {
    param([string]$ImagePath)

    $resolved = Get-MenuNetworkText $ImagePath
    if ([string]::IsNullOrWhiteSpace($resolved)) { return '' }

    try { $resolved = [Environment]::ExpandEnvironmentVariables($resolved) } catch { }

    if ($resolved.StartsWith('"')) {
        $closing = $resolved.IndexOf('"', 1)
        if ($closing -gt 1) { $resolved = $resolved.Substring(1, $closing - 1) }
    } else {
        $sysIndex = $resolved.IndexOf('.sys', [StringComparison]::OrdinalIgnoreCase)
        if ($sysIndex -ge 0) {
            $resolved = $resolved.Substring(0, $sysIndex + 4)
        } elseif ($resolved.Contains(' ')) {
            $resolved = ($resolved -split '\s+', 2)[0]
        }
    }

    try {
        $systemRoot = [Environment]::GetFolderPath([Environment+SpecialFolder]::Windows)
        if ([string]::IsNullOrWhiteSpace($systemRoot)) { $systemRoot = $env:windir }

        if ($resolved.StartsWith('\SystemRoot', [StringComparison]::OrdinalIgnoreCase)) {
            $resolved = $systemRoot + $resolved.Substring('\SystemRoot'.Length)
        } elseif ($resolved.StartsWith('System32', [StringComparison]::OrdinalIgnoreCase)) {
            $resolved = Join-Path $systemRoot $resolved
        } elseif ($resolved.StartsWith('\??\', [StringComparison]::OrdinalIgnoreCase)) {
            $resolved = $resolved.Substring(4)
        }

        $resolved = $resolved.Replace('%SystemRoot%', $systemRoot).Replace('%systemroot%', $systemRoot)
    } catch { }

    return $resolved
}

function Get-MenuNetworkDriverTypeFromBinary {
    param([string]$ResolvedPath)

    if ([string]::IsNullOrWhiteSpace($ResolvedPath) -or -not (Test-Path -LiteralPath $ResolvedPath)) { return 'NDIS' }

    $stream = $null
    try {
        $stream = [System.IO.File]::Open($ResolvedPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $bytesToRead = [int][Math]::Min($stream.Length, 1048576L)
        if ($bytesToRead -le 0) { return 'NDIS' }

        $buffer = New-Object byte[] $bytesToRead
        $offset = 0
        while ($offset -lt $bytesToRead) {
            $read = $stream.Read($buffer, $offset, $bytesToRead - $offset)
            if ($read -le 0) { break }
            $offset += $read
        }

        $text = [System.Text.Encoding]::ASCII.GetString($buffer, 0, $offset)
        if ($text.IndexOf('NetAdapter', [StringComparison]::OrdinalIgnoreCase) -ge 0) { return 'NETADAPTERCX' }
    } catch {
    } finally {
        if ($null -ne $stream) { $stream.Close() }
    }

    return 'NDIS'
}

function Get-MenuPhysicalNetworkAdapterDriverType {
    param([object]$Adapter)

    $pnpId = Get-MenuNetworkText $Adapter.PNPDeviceID
    if ([string]::IsNullOrWhiteSpace($pnpId)) { return 'NDIS' }

    $enumPath = 'HKLM:\SYSTEM\CurrentControlSet\Enum\' + $pnpId
    $driver = Get-MenuRegistryStringValue -Path $enumPath -Name 'Driver'
    if ([string]::IsNullOrWhiteSpace($driver)) { return 'NDIS' }

    $classProviderPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\' + $driver
    if (-not (Test-Path -LiteralPath $classProviderPath)) { return 'NDIS' }

    $service = Get-MenuRegistryStringValue -Path ($classProviderPath + '\Ndi') -Name 'Service'
    if (-not [string]::IsNullOrWhiteSpace($service)) { $service = $service.TrimEnd('.').Trim() }
    if ([string]::IsNullOrWhiteSpace($service)) { return 'NDIS' }

    $servicePath = 'HKLM:\SYSTEM\CurrentControlSet\Services\' + $service
    $imagePath = Get-MenuRegistryStringValue -Path $servicePath -Name 'ImagePath'
    $resolvedImagePath = Resolve-MenuNetworkDriverImagePath -ImagePath $imagePath

    return Get-MenuNetworkDriverTypeFromBinary -ResolvedPath $resolvedImagePath
}

function Get-DetectedPhysicalNetworkAdapterInfo {
    if ($script:DetectedPhysicalNetworkAdapterInfoResolved) { return @($script:DetectedPhysicalNetworkAdapterInfo) }

    $script:DetectedPhysicalNetworkAdapterInfoResolved = $true
    $script:DetectedPhysicalNetworkAdapterInfo = @()

    try {
        $adapters = @(Get-MenuPhysicalNetworkAdapters | Sort-Object Name)
        if ($adapters.Count -eq 0) { return @() }

        $items = @()
        foreach ($adapter in $adapters) {
            $name = First-MenuNetworkText $adapter.Name $adapter.InterfaceDescription $adapter.PNPDeviceID
            $driverType = Get-MenuPhysicalNetworkAdapterDriverType -Adapter $adapter
            if ($driverType -ieq 'NetAdapterCx') { $driverType = 'NETADAPTERCX' }
            if ($driverType -ine 'NETADAPTERCX') { $driverType = 'NDIS' }

            if ([string]::IsNullOrWhiteSpace($name)) {
                $displayWithName = $driverType
            } else {
                $displayWithName = ('{0} ({1})' -f $name, $driverType)
            }

            $items += [pscustomobject]@{
                Name            = $name
                DriverType      = $driverType
                DisplayWithName = $displayWithName
            }
        }

        $script:DetectedPhysicalNetworkAdapterInfo = @($items)
    } catch {
        $script:DetectedPhysicalNetworkAdapterInfo = @()
    }

    return @($script:DetectedPhysicalNetworkAdapterInfo)
}

function Get-DetectedPhysicalNetworkAdapterMenuSuffix {
    $items = @(Get-DetectedPhysicalNetworkAdapterInfo)
    if ($items.Count -eq 0) { return '' }

    if ($items.Count -eq 1) {
        return [string]$items[0].DriverType
    }

    return [string]((@($items | ForEach-Object { $_.DisplayWithName })) -join ' / ')
}

function Get-DetectedPhysicalNetworkAdapterTitleSuffix {
    $items = @(Get-DetectedPhysicalNetworkAdapterInfo)
    if ($items.Count -eq 0) { return '' }

    return [string]((@($items | ForEach-Object { $_.DisplayWithName })) -join ' / ')
}

function Get-DetectedNetworkAdapterMenuEntryText {
    param([Parameter(Mandatory=$true)][string]$Base)

    $suffix = Get-DetectedPhysicalNetworkAdapterMenuSuffix
    if ([string]::IsNullOrWhiteSpace($suffix)) { return $Base }
    return ($Base + ' - ' + $suffix)
}

function Get-DetectedNetworkAdapterTitleText {
    param([Parameter(Mandatory=$true)][string]$Base)

    $suffix = Get-DetectedPhysicalNetworkAdapterTitleSuffix
    if ([string]::IsNullOrWhiteSpace($suffix)) { return $Base }
    return ($Base + ' - ' + $suffix)
}

function Get-DetectedGpuName {
    if ($script:DetectedGpuNameResolved) { return [string]$script:DetectedGpuName }

    $script:DetectedGpuNameResolved = $true
    $script:DetectedGpuName = ''

    try {
        $candidates = New-Object System.Collections.Generic.List[object]
        $pnpDevices = @(Get-MenuDisplayPnpGpuDevices)

        $gpuInstanceSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        $gpuHardwareSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        $nameByInstance = New-Object 'System.Collections.Generic.Dictionary[string,System.Collections.Generic.List[string]]' ([System.StringComparer]::OrdinalIgnoreCase)
        $nameByHardware = New-Object 'System.Collections.Generic.Dictionary[string,System.Collections.Generic.List[string]]' ([System.StringComparer]::OrdinalIgnoreCase)

        foreach ($device in $pnpDevices) {
            $name = ConvertTo-MenuGpuPlainName $device.Name
            if (-not (Test-MenuGpuNameToken $name)) { continue }

            Add-MenuGpuCandidate -Candidates $candidates -Name $name -Bonus 10

            $instanceKey = Get-MenuPciLookupInstanceId $device.InstanceId
            if (-not [string]::IsNullOrWhiteSpace($instanceKey)) {
                [void]$gpuInstanceSet.Add($instanceKey)
                Add-MenuNameMapValue -Map $nameByInstance -Key $instanceKey -Name $name
            }

            $hardwareKey = Get-MenuPciLookupHardwareId $device.InstanceId
            if (-not [string]::IsNullOrWhiteSpace($hardwareKey)) {
                [void]$gpuHardwareSet.Add($hardwareKey)
                Add-MenuNameMapValue -Map $nameByHardware -Key $hardwareKey -Name $name
            }

            foreach ($hardwareId in @($device.HardwareIds)) {
                $hardwareKey = Get-MenuPciLookupHardwareId $hardwareId
                if ([string]::IsNullOrWhiteSpace($hardwareKey)) { continue }
                [void]$gpuHardwareSet.Add($hardwareKey)
                Add-MenuNameMapValue -Map $nameByHardware -Key $hardwareKey -Name $name
            }
        }

        $pciRecords = @(Get-MenuPciEnumGpuRecords)
        $matchedRecords = New-Object System.Collections.Generic.List[object]
        $matchedPathSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

        foreach ($record in $pciRecords) {
            $matched = $false
            if (-not [string]::IsNullOrWhiteSpace([string]$record.InstanceId) -and $gpuInstanceSet.Contains([string]$record.InstanceId)) { $matched = $true }
            if (-not $matched -and -not [string]::IsNullOrWhiteSpace([string]$record.HardwareId) -and $gpuHardwareSet.Contains([string]$record.HardwareId) -and [bool]$record.IsGpuDescription) { $matched = $true }

            if ($matched -and $matchedPathSet.Add([string]$record.InstanceId)) { [void]$matchedRecords.Add($record) }
        }

        if ($matchedRecords.Count -eq 0) {
            foreach ($record in $pciRecords) {
                if (-not [bool]$record.IsGpuClassCode) { continue }
                if ($matchedPathSet.Add([string]$record.InstanceId)) { [void]$matchedRecords.Add($record) }
            }
        }

        foreach ($record in $matchedRecords) {
            if ($nameByInstance.ContainsKey([string]$record.InstanceId)) {
                foreach ($mappedName in $nameByInstance[[string]$record.InstanceId]) { Add-MenuGpuCandidate -Candidates $candidates -Name $mappedName -Bonus 35 }
            }

            if ($nameByHardware.ContainsKey([string]$record.HardwareId)) {
                foreach ($mappedName in $nameByHardware[[string]$record.HardwareId]) { Add-MenuGpuCandidate -Candidates $candidates -Name $mappedName -Bonus 30 }
            }

            Add-MenuGpuCandidate -Candidates $candidates -Name (Resolve-MenuPciResolvedGpuName -InstanceId ([string]$record.InstanceId) -HardwareId ([string]$record.HardwareId) -WindowsName $record.DeviceDesc) -Bonus 55
            Add-MenuDisplayClassGpuNameCandidates -Candidates $candidates -InstanceId ([string]$record.InstanceId) -HardwareId ([string]$record.HardwareId)
            Add-MenuGpuCandidate -Candidates $candidates -Name $record.DeviceDesc -Bonus 20
        }

        if ($candidates.Count -eq 0) {
            foreach ($device in $pnpDevices) {
                Add-MenuGpuCandidate -Candidates $candidates -Name $device.Name -Bonus 0
            }
        }

        $orderedCandidates = @($candidates | Sort-Object -Property @{ Expression = 'Score'; Descending = $true }, @{ Expression = 'Name'; Descending = $false })
        $finalNames = New-Object System.Collections.Generic.List[string]
        foreach ($candidate in $orderedCandidates) {
            if ($finalNames.Count -ge 2) { break }
            Add-MenuStringListUnique -List $finalNames -Value $candidate.Name
        }

        if ($finalNames.Count -gt 0) {
            $script:DetectedGpuName = (($finalNames.ToArray()) -join ' / ')
        }
    } catch {
        $script:DetectedGpuName = ''
    }

    return [string]$script:DetectedGpuName
}

function Get-DetectedGpuMenuEntryText {
    param([Parameter(Mandatory=$true)][string]$Base)

    $name = Get-DetectedGpuName
    if ([string]::IsNullOrWhiteSpace($name)) { return $Base }
    return ($Base + ' - ' + $name)
}


function Invoke-RegistrySetAuto {
    param(
        [Parameter(Mandatory=$true)][string]$Title,
        [Parameter(Mandatory=$true)][object[]]$Items,
        [Parameter(Mandatory=$false)][AllowEmptyString()][string]$AfterMessage = ''
    )

    Write-Host ''
    Write-BoxTitle -Title $Title
    Write-Host ''

    $failed = 0
    foreach ($item in @($Items)) {
        $create = $false
        if ($item.PSObject.Properties.Name -contains 'CreateKey') { $create = [bool]$item.CreateKey }

        $type = 'DWord'
        if ($item.PSObject.Properties.Name -contains 'Type') { $type = [string]$item.Type }

        switch -Regex ($type) {
            '^(DWord|REG_DWORD)$' {
                $result = Set-RegistryDword -Key $item.Key -Name $item.Name -Value $item.Value -CreateKey:$create
                break
            }
            '^(String|REG_SZ)$' {
                $result = Set-RegistryString -Key $item.Key -Name $item.Name -Value ([string]$item.Value) -CreateKey:$create
                break
            }
            '^(DefaultString|DefaultValue|REG_SZ_DEFAULT|REG_DEFAULT_SZ)$' {
                $value = ''
                if ($item.PSObject.Properties.Name -contains 'Value') { $value = [string]$item.Value }
                $result = Set-RegistryDefaultString -Key $item.Key -Value $value -CreateKey:$create
                break
            }
            '^(Binary|REG_BINARY)$' {
                $result = Set-RegistryBinary -Key $item.Key -Name $item.Name -Value $item.Value -CreateKey:$create
                break
            }
            '^(Delete|DeleteValue|Remove|RemoveValue|REG_DELETE)$' {
                $result = Remove-RegistryValue -Key $item.Key -Name $item.Name
                break
            }
            default {
                $result = [pscustomobject]@{ Ok = $false; Message = "unsupported registry value type '$type' for $($item.Key)\$($item.Name)" }
                break
            }
        }

        if (-not $result.Ok) { $failed++ }
        $isWarning = $false
        if ($result.PSObject.Properties.Name -contains 'Warning') { $isWarning = [bool]$result.Warning }
        Write-StatusLine -Ok $result.Ok -Text $result.Message -Warning:$isWarning
    }

    Write-Host ''
    if ($failed -eq 0) {
        Write-Host 'OVERALL: SUCCESS' -ForegroundColor Green
    } else {
        Write-Host "OVERALL: FAILED - $failed item(s) failed." -ForegroundColor Red
    }

    if (-not [string]::IsNullOrWhiteSpace($AfterMessage)) {
        Write-Host ''
        Write-Host $AfterMessage
    }

    return ($failed -eq 0)
}


function Initialize-MouseAccelerationNativeMethods {
    if ('WindowsTweaksMouseNativeMethods' -as [type]) { return }

    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class WindowsTweaksMouseNativeMethods
{
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SystemParametersInfo(int uiAction, int uiParam, int[] pvParam, int fWinIni);
}
"@ -ErrorAction Stop
}

function Set-MouseAccelerationLiveState {
    param(
        [Parameter(Mandatory=$true)][int[]]$Values
    )

    try {
        if ($Values.Count -ne 3) {
            return [pscustomobject]@{ Ok=$false; Message='live mouse acceleration state requires exactly 3 values: threshold1, threshold2, acceleration' }
        }

        Initialize-MouseAccelerationNativeMethods

        $spiGetMouse = 0x0003
        $spiSetMouse = 0x0004
        $spifUpdateIniFile = 0x0001
        $spifSendChange = 0x0002
        $flags = ($spifUpdateIniFile -bor $spifSendChange)

        $setOk = [WindowsTweaksMouseNativeMethods]::SystemParametersInfo($spiSetMouse, 0, $Values, $flags)
        if (-not $setOk) {
            $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
            return [pscustomobject]@{ Ok=$false; Message=("SystemParametersInfo(SPI_SETMOUSE) failed; Win32 error {0}" -f $errorCode) }
        }

        $verify = New-Object 'int[]' 3
        $getOk = [WindowsTweaksMouseNativeMethods]::SystemParametersInfo($spiGetMouse, 0, $verify, 0)
        if (-not $getOk) {
            $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
            return [pscustomobject]@{ Ok=$true; Warning=$true; Message=("live state applied, but verification with SPI_GETMOUSE failed; Win32 error {0}" -f $errorCode) }
        }

        if (($verify[0] -ne $Values[0]) -or ($verify[1] -ne $Values[1]) -or ($verify[2] -ne $Values[2])) {
            return [pscustomobject]@{ Ok=$false; Message=("live verification mismatch: expected [{0}, {1}, {2}], read [{3}, {4}, {5}]" -f $Values[0], $Values[1], $Values[2], $verify[0], $verify[1], $verify[2]) }
        }

        return [pscustomobject]@{ Ok=$true; Message=("live SPI_SETMOUSE applied: threshold1={0}, threshold2={1}, acceleration={2}" -f $Values[0], $Values[1], $Values[2]) }
    }
    catch {
        return [pscustomobject]@{ Ok=$false; Message=("live mouse acceleration update failed: {0}" -f $_.Exception.Message) }
    }
}

function Invoke-MouseAccelerationSetting {
    param(
        [switch]$Auto
    )

    $title = 'Mouse Acceleration - Disable'
    $items = $mouseAccelerationDisable
    $liveValues = [int[]](0, 0, 0)
    $stateText = 'fully disabled'

    if (-not $Auto) {
        Clear-ConsoleScreen
    } else {
        Write-Host ''
    }

    Write-BoxTitle -Title $title
    Write-Host ''

    $failed = 0
    foreach ($item in @($items)) {
        $result = Set-RegistryString -Key $item.Key -Name $item.Name -Value ([string]$item.Value) -CreateKey:([bool]$item.CreateKey)
        if (-not $result.Ok) { $failed++ }
        $isWarning = $false
        if ($result.PSObject.Properties.Name -contains 'Warning') { $isWarning = [bool]$result.Warning }
        Write-StatusLine -Ok $result.Ok -Text $result.Message -Warning:$isWarning
    }

    $liveResult = Set-MouseAccelerationLiveState -Values $liveValues
    if (-not $liveResult.Ok) { $failed++ }
    $liveWarning = $false
    if ($liveResult.PSObject.Properties.Name -contains 'Warning') { $liveWarning = [bool]$liveResult.Warning }
    Write-StatusLine -Ok $liveResult.Ok -Text $liveResult.Message -Warning:$liveWarning

    Write-Host ''
    if ($failed -eq 0) {
        Write-Host ("OVERALL: SUCCESS - Windows mouse acceleration is {0}." -f $stateText) -ForegroundColor Green
    } else {
        Write-Host ("OVERALL: FAILED - {0} item(s) failed." -f $failed) -ForegroundColor Red
    }

    Write-Host ''
if (-not $Auto) {
        Write-Host ''
        Wait-ForEnterToContinue
    }

    if ($Auto) { return ($failed -eq 0) }
    return
}

function Invoke-PowerPlanImportAndActivateAuto {
    Write-Host ''
    Write-BoxTitle -Title 'Power Plan - Import and Activate'
    Write-Host ''

    $powerPlanPath = Resolve-ScriptResourcePath -RelativePath 'Resources\POWER-PLAN\LLC-CERTIFIED.pow'
    $schemeGuid = '8b24b027-1dee-4c65-8f35-5d5d91e51d87'

    if (Test-Path -LiteralPath $powerPlanPath -PathType Leaf) {
        Write-Host "Power plan file: $powerPlanPath" -ForegroundColor Green
    } else {
        Write-Host "Power plan file: $powerPlanPath" -ForegroundColor DarkGray
    }
    Write-Host "Power scheme GUID: $schemeGuid" -ForegroundColor Green
    Write-Host ''

    $ok = Enable-LlcCertifiedPowerPlan -PowerPlanPath $powerPlanPath -SchemeGuid $schemeGuid

    Write-Host ''
    if ($ok) {
        Write-Host 'OVERALL: SUCCESS' -ForegroundColor Green
        return $true
    }

    Write-Host 'OVERALL: FAILED' -ForegroundColor Red
    return $false
}

function Invoke-DisableDevicePowerSavingAuto {
    Write-Host ''
    Write-BoxTitle -Title 'Powersaving - Disable device powersaving'
    Write-Host ''

    $rc = Invoke-EmbeddedPowerShellPayload -Title 'Disable device powersaving' -Payload $DisableDevicePowerSavingPayload

    Write-Host ''
    if ($rc -eq 0) {
        Write-Host 'OVERALL: SUCCESS' -ForegroundColor Green
        return $true
    } elseif ($rc -eq 10) {
        Write-Host 'OVERALL: WARNING - Partial success. Check the per-device output above.' -ForegroundColor Yellow
        return $false
    }

    Write-Host ("OVERALL: FAILED - Exit code: {0}" -f $rc) -ForegroundColor Red
    return $false
}

function Invoke-NetworkOptimizationEnableAuto {
    Write-Host ''
    Write-BoxTitle -Title 'Network Optimization - Enable (wired Ethernet only)'
    Write-Host ''

    $rcPower = Invoke-EmbeddedPowerShellPayload -Title 'Disable network adapter powersaving' -Payload $DisablePowerSavingPayload
    Write-Host ''
    $rcNetwork = Invoke-EmbeddedPowerShellPayload -Title 'Optimize networking' -Payload $OptimizeNetworkingPayload

    Write-Host ''
    if (($rcPower -eq 0) -and ($rcNetwork -eq 0)) {
        Write-Host 'OVERALL: SUCCESS' -ForegroundColor Green
        return $true
    }

    if (($rcPower -eq 10) -and ($rcNetwork -eq 0)) {
        Write-Host 'OVERALL: SUCCESS WITH WARNINGS - Optional adapter powersaving entries were not present on this system.' -ForegroundColor Yellow
        return $true
    }

    Write-Host ("OVERALL: FAILED - Disable powersaving exit code={0}, Optimize networking exit code={1}" -f $rcPower, $rcNetwork) -ForegroundColor Red
    return $false
}

function Invoke-ExternalExecutableLauncherAuto {
    param(
        [Parameter(Mandatory=$true)][string]$Title,
        [Parameter(Mandatory=$true)][string]$RelativePath,
        [string[]]$Arguments = @(),
        [string[]]$RelativeArgumentPaths = @(),
        [switch]$WaitForExit
    )

    Write-Host ''
    Write-BoxTitle -Title $Title
    Write-Host ''

    $exePath = Resolve-ScriptResourcePath -RelativePath $RelativePath
    if (-not (Test-Path -LiteralPath $exePath -PathType Leaf)) {
        Write-StatusLine -Ok $false -Text "executable not found: $exePath"
        return $false
    }

    $resolvedArguments = @()

    foreach ($argument in @($Arguments)) {
        if (-not [string]::IsNullOrWhiteSpace($argument)) {
            $resolvedArguments += $argument
        }
    }

    foreach ($relativeArgumentPath in @($RelativeArgumentPaths)) {
        if ([string]::IsNullOrWhiteSpace($relativeArgumentPath)) { continue }

        $argumentPath = Resolve-ScriptResourcePath -RelativePath $relativeArgumentPath
        if (-not (Test-Path -LiteralPath $argumentPath -PathType Leaf)) {
            Write-StatusLine -Ok $false -Text "argument file not found: $argumentPath"
            return $false
        }

        $resolvedArguments += $argumentPath
    }

    Write-Host "Launching: $exePath"
    if ($resolvedArguments.Count -gt 0) {
        Write-Host ("Arguments: {0}" -f ($resolvedArguments -join ' '))
    }
    Write-Host ''

    $workingDirectory = Split-Path -Parent $exePath
    $startArguments = @{}
    $startArguments['FilePath'] = $exePath
    $startArguments['WorkingDirectory'] = $workingDirectory
    $startArguments['ErrorAction'] = 'Stop'

    if ($resolvedArguments.Count -gt 0) {
        $startArguments['ArgumentList'] = @($resolvedArguments | ForEach-Object { Format-ProcessArgument -Argument $_ })
    }

    if ($WaitForExit) {
        $startArguments['Wait'] = $true
        $startArguments['PassThru'] = $true
    }

    try {
        $process = Start-Process @startArguments
    }
    catch {
        Write-StatusLine -Ok $false -Text $_.Exception.Message
        Write-Host ''
        Write-Host 'OVERALL: FAILED' -ForegroundColor Red
        return $false
    }

    Write-Host ''
    if ($WaitForExit) {
        if ($process.ExitCode -eq 0) {
            Write-StatusLine -Ok $true -Text "$Title completed"
            Write-Host ''
            Write-Host 'OVERALL: SUCCESS' -ForegroundColor Green
            return $true
        }

        Write-StatusLine -Ok $false -Text "$Title exited with code $($process.ExitCode)"
        Write-Host ''
        Write-Host 'OVERALL: FAILED' -ForegroundColor Red
        return $false
    }

    Write-StatusLine -Ok $true -Text "$Title completed"
    Write-Host ''
    Write-Host 'OVERALL: SUCCESS' -ForegroundColor Green
    return $true
}

function Get-DetectedGpuVendorAuto {
    $gpuName = Get-DetectedGpuName
    $hasNvidia = $false
    $hasAmd = $false

    if (-not [string]::IsNullOrWhiteSpace($gpuName)) {
        if ($gpuName -match '(?i)\b(NVIDIA|GeForce|RTX|GTX|Quadro|Tesla)\b') { $hasNvidia = $true }
        if ($gpuName -match '(?i)\b(AMD|Radeon|Radeon\s+RX|RX\s*[0-9]|Vega)\b') { $hasAmd = $true }
    }

    if ($hasNvidia -and -not $hasAmd) { return 'NVIDIA' }
    if ($hasAmd -and -not $hasNvidia) { return 'AMD' }
    if ($hasNvidia -and $hasAmd) { return 'BOTH' }
    return ''
}

function Invoke-NvidiaProfileInspectorImportAuto {
    $gpuVendor = Get-DetectedGpuVendorAuto
    if ($gpuVendor -ne 'NVIDIA' -and $gpuVendor -ne 'BOTH') {
        Write-Host ''
        Write-BoxTitle -Title 'Nvidia Profile Inspector - Import .nip'
        Write-Host ''
        Write-Host 'SKIPPED: NVIDIA GPU was not detected; .nip import was not applied.' -ForegroundColor Yellow
        return $true
    }

    return (Invoke-ExternalExecutableLauncherAuto -Title 'Nvidia Profile Inspector - Import .nip' -RelativePath 'Resources\NVIDIA-PROFILE-INSPECTOR\NVIDIA-PROFILE-INSPECTOR.exe' -RelativeArgumentPaths @('Resources\NVIDIA-PROFILE-INSPECTOR\LLC-OPTIMIZED-V3.nip') -WaitForExit)
}

function Invoke-MmcssAuto {
    $adapterInfo = @(Get-DetectedPhysicalNetworkAdapterInfo)

    Write-Host ''
    Write-BoxTitle -Title (Get-DetectedNetworkAdapterTitleText -Base 'MMCSS - Auto')
    Write-Host ''

    if ($adapterInfo.Count -eq 0) {
        Write-Host 'SKIPPED: No physical network adapter was detected; MMCSS was not changed.' -ForegroundColor Yellow
        return $true
    }

    foreach ($adapter in $adapterInfo) {
        Write-Host ('Adapter   : {0}' -f $adapter.DisplayWithName) -ForegroundColor Green
    }

    $driverTypes = @($adapterInfo | ForEach-Object { [string]$_.DriverType } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
    $targetMode = ''

    if (($driverTypes -contains 'NDIS') -and ($driverTypes -contains 'NETADAPTERCX')) {
        Write-Host ''
        Write-Host 'Both NDIS and NetAdapterCx adapters were detected. Choose which MMCSS behavior to apply.' -ForegroundColor Yellow
        $choice = Invoke-Menu -Title 'MMCSS - Auto adapter choice' -Items @(
            'NDIS behavior - Enable + Optimize MMCSS',
            'NetAdapterCx behavior - Disable MMCSS',
            'Skip MMCSS'
        )

        if ($choice -eq 0) {
            $targetMode = 'NDIS'
        } elseif ($choice -eq 1) {
            $targetMode = 'NETADAPTERCX'
        } else {
            Write-Host ''
            Write-BoxTitle -Title 'MMCSS - Auto'
            Write-Host ''
            Write-Host 'SKIPPED: MMCSS was not changed by user choice.' -ForegroundColor Yellow
            return $true
        }
    } elseif ($driverTypes -contains 'NDIS') {
        $targetMode = 'NDIS'
    } elseif ($driverTypes -contains 'NETADAPTERCX') {
        $targetMode = 'NETADAPTERCX'
    } else {
        Write-Host 'SKIPPED: Adapter driver type was not detected; MMCSS was not changed.' -ForegroundColor Yellow
        return $true
    }

    if ($targetMode -eq 'NDIS') {
        Write-Host ''
        Write-Host 'Applying NDIS behavior: Enable + Optimize MMCSS.' -ForegroundColor Cyan
        $okEnable = Invoke-RegistrySetAuto -Title 'MMCSS - Enable' -Items $mmcssEnable -AfterMessage ''
        $okOptimize = Invoke-RegistrySetAuto -Title 'MMCSS - Optimize' -Items $mmcssOptimize -AfterMessage ''
        return ($okEnable -and $okOptimize)
    }

    Write-Host ''
    Write-Host 'Applying NetAdapterCx behavior: Disable MMCSS.' -ForegroundColor Cyan
    return (Invoke-RegistrySetAuto -Title 'MMCSS - Disable' -Items $mmcssDisable -AfterMessage '')
}

function Invoke-GpuTweaksAuto {
    $gpuName = Get-DetectedGpuName
    $gpuVendor = Get-DetectedGpuVendorAuto

    Write-Host ''
    Write-BoxTitle -Title (Get-DetectedGpuMenuEntryText -Base 'GPU - Auto')
    Write-Host ''

    if ([string]::IsNullOrWhiteSpace($gpuName)) {
        Write-Host 'SKIPPED: No supported NVIDIA or AMD GPU was detected; GPU tweaks were not applied.' -ForegroundColor Yellow
        return $true
    }

    Write-Host ('Detected GPU: {0}' -f $gpuName) -ForegroundColor Green

    if ($gpuVendor -eq 'NVIDIA') {
        return (Invoke-RegistrySetAuto -Title 'Optimize NVIDIA GPU' -Items $nvidiaGpuOptimize -AfterMessage '')
    }

    if ($gpuVendor -eq 'AMD') {
        return (Invoke-RegistrySetAuto -Title 'Optimize AMD GPU' -Items $amdGpuOptimize -AfterMessage '')
    }

    if ($gpuVendor -eq 'BOTH') {
        Write-Host ''
        Write-Host 'Both NVIDIA and AMD GPU identifiers were detected. Choose which GPU tweaks to apply.' -ForegroundColor Yellow
        $choice = Invoke-Menu -Title 'GPU - Auto vendor choice' -Items @(
            'Apply NVIDIA GPU tweaks',
            'Apply AMD GPU tweaks',
            'Skip GPU tweaks'
        )

        if ($choice -eq 0) {
            return (Invoke-RegistrySetAuto -Title 'Optimize NVIDIA GPU' -Items $nvidiaGpuOptimize -AfterMessage '')
        }
        if ($choice -eq 1) {
            return (Invoke-RegistrySetAuto -Title 'Optimize AMD GPU' -Items $amdGpuOptimize -AfterMessage '')
        }

        Write-Host ''
        Write-BoxTitle -Title 'GPU - Auto'
        Write-Host ''
        Write-Host 'SKIPPED: GPU tweaks were not changed by user choice.' -ForegroundColor Yellow
        return $true
    }

    Write-Host 'SKIPPED: Detected GPU is neither NVIDIA nor AMD; GPU tweaks were not applied.' -ForegroundColor Yellow
    return $true
}


function Initialize-LlcDisplayNative {
    if (([System.Management.Automation.PSTypeName]'LLC.DisplayNative').Type) { return $true }

    try {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace LLC {
    public static class DisplayNative {
        public const int ENUM_CURRENT_SETTINGS = -1;
        public const int ENUM_REGISTRY_SETTINGS = -2;

        public const int DISPLAY_DEVICE_ATTACHED_TO_DESKTOP = 0x00000001;
        public const int DISPLAY_DEVICE_PRIMARY_DEVICE = 0x00000004;
        public const int DISPLAY_DEVICE_MIRRORING_DRIVER = 0x00000008;

        public const int DM_BITSPERPEL = 0x00040000;
        public const int DM_PELSWIDTH = 0x00080000;
        public const int DM_PELSHEIGHT = 0x00100000;
        public const int DM_DISPLAYFLAGS = 0x00200000;
        public const int DM_DISPLAYFREQUENCY = 0x00400000;

        public const uint CDS_UPDATEREGISTRY = 0x00000001;
        public const uint CDS_TEST = 0x00000002;

        public const int DISP_CHANGE_SUCCESSFUL = 0;
        public const int DISP_CHANGE_RESTART = 1;
        public const int DISP_CHANGE_FAILED = -1;
        public const int DISP_CHANGE_BADMODE = -2;
        public const int DISP_CHANGE_NOTUPDATED = -3;
        public const int DISP_CHANGE_BADFLAGS = -4;
        public const int DISP_CHANGE_BADPARAM = -5;
        public const int DISP_CHANGE_BADDUALVIEW = -6;

        [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
        public struct DISPLAY_DEVICE {
            public int cb;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string DeviceName;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string DeviceString;
            public int StateFlags;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string DeviceID;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string DeviceKey;
        }

        [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
        public struct DEVMODE {
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string dmDeviceName;
            public short dmSpecVersion;
            public short dmDriverVersion;
            public short dmSize;
            public short dmDriverExtra;
            public int dmFields;
            public int dmPositionX;
            public int dmPositionY;
            public int dmDisplayOrientation;
            public int dmDisplayFixedOutput;
            public short dmColor;
            public short dmDuplex;
            public short dmYResolution;
            public short dmTTOption;
            public short dmCollate;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string dmFormName;
            public short dmLogPixels;
            public int dmBitsPerPel;
            public int dmPelsWidth;
            public int dmPelsHeight;
            public int dmDisplayFlags;
            public int dmDisplayFrequency;
            public int dmICMMethod;
            public int dmICMIntent;
            public int dmMediaType;
            public int dmDitherType;
            public int dmReserved1;
            public int dmReserved2;
            public int dmPanningWidth;
            public int dmPanningHeight;
        }

        public static int SizeOfDisplayDevice() {
            return Marshal.SizeOf(typeof(DISPLAY_DEVICE));
        }

        public static int SizeOfDevMode() {
            return Marshal.SizeOf(typeof(DEVMODE));
        }

        [DllImport("user32.dll", CharSet=CharSet.Unicode, EntryPoint="EnumDisplayDevicesW")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool EnumDisplayDevices(string lpDevice, uint iDevNum, ref DISPLAY_DEVICE lpDisplayDevice, uint dwFlags);

        [DllImport("user32.dll", CharSet=CharSet.Unicode, EntryPoint="EnumDisplaySettingsW")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool EnumDisplaySettings(string lpszDeviceName, int iModeNum, ref DEVMODE lpDevMode);

        [DllImport("user32.dll", CharSet=CharSet.Unicode, EntryPoint="ChangeDisplaySettingsExW")]
        public static extern int ChangeDisplaySettingsEx(string lpszDeviceName, ref DEVMODE lpDevMode, IntPtr hwnd, uint dwflags, IntPtr lParam);

        [DllImport("user32.dll", CharSet=CharSet.Unicode, EntryPoint="ChangeDisplaySettingsExW")]
        public static extern int ChangeDisplaySettingsExNull(string lpszDeviceName, IntPtr lpDevMode, IntPtr hwnd, uint dwflags, IntPtr lParam);
    }
}
'@ -ErrorAction Stop
        return $true
    }
    catch {
        Write-StatusLine -Ok $false -Text "Display Mode Auto: could not initialize Win32 display API wrapper -> $($_.Exception.Message)"
        return $false
    }
}

function New-LlcDisplayDeviceStruct {
    $device = New-Object 'LLC.DisplayNative+DISPLAY_DEVICE'
    $device.cb = [int][LLC.DisplayNative]::SizeOfDisplayDevice()
    return $device
}

function New-LlcDevModeStruct {
    $mode = New-Object 'LLC.DisplayNative+DEVMODE'
    $mode.dmSize = [int16][LLC.DisplayNative]::SizeOfDevMode()
    return $mode
}

function Get-LlcDisplayChangeResultText {
    param([int]$Code)

    switch ($Code) {
        0 { return 'DISP_CHANGE_SUCCESSFUL' }
        1 { return 'DISP_CHANGE_RESTART' }
        -1 { return 'DISP_CHANGE_FAILED' }
        -2 { return 'DISP_CHANGE_BADMODE' }
        -3 { return 'DISP_CHANGE_NOTUPDATED' }
        -4 { return 'DISP_CHANGE_BADFLAGS' }
        -5 { return 'DISP_CHANGE_BADPARAM' }
        -6 { return 'DISP_CHANGE_BADDUALVIEW' }
        default { return "UNKNOWN($Code)" }
    }
}

function Get-LlcAttachedDesktopDisplays {
    $attachedDisplays = New-Object System.Collections.ArrayList
    $activeModeFallbackDisplays = New-Object System.Collections.ArrayList
    $seenNames = @{}

    for ($index = 0; $index -lt 32; $index++) {
        $device = New-LlcDisplayDeviceStruct
        $ok = [LLC.DisplayNative]::EnumDisplayDevices($null, [uint32]$index, [ref]$device, 0)
        if (-not $ok) { break }

        $mirror = (($device.StateFlags -band [LLC.DisplayNative]::DISPLAY_DEVICE_MIRRORING_DRIVER) -ne 0)
        if ($mirror) { continue }

        $name = [string]$device.DeviceName
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        if ($seenNames.ContainsKey($name)) { continue }
        $seenNames[$name] = $true

        $attached = (($device.StateFlags -band [LLC.DisplayNative]::DISPLAY_DEVICE_ATTACHED_TO_DESKTOP) -ne 0)
        $isPrimary = (($device.StateFlags -band [LLC.DisplayNative]::DISPLAY_DEVICE_PRIMARY_DEVICE) -ne 0)

        $record = [pscustomobject]@{
            Index = $index
            DeviceName = $name
            DeviceString = [string]$device.DeviceString
            IsPrimary = $isPrimary
            DiscoverySource = 'EnumDisplayDevices'
        }

        if ($attached) {
            [void]$attachedDisplays.Add($record)
            continue
        }

        $current = Get-LlcDisplayCurrentModeRecord -DeviceName $name
        if ($null -ne $current) {
            $record.DiscoverySource = 'EnumDisplayDevices-current-mode-fallback'
            [void]$activeModeFallbackDisplays.Add($record)
        }
    }

    if ($attachedDisplays.Count -gt 0) {
        return @($attachedDisplays)
    }

    if ($activeModeFallbackDisplays.Count -gt 0) {
        Write-StatusLine -Ok $true -Warning -Text 'Display Mode Auto: attached-desktop flag not reported; using active display devices verified by current-mode read'
        return @($activeModeFallbackDisplays)
    }

    $knownNameFallbackDisplays = New-Object System.Collections.ArrayList
    for ($displayIndex = 1; $displayIndex -le 32; $displayIndex++) {
        $name = ('\\.\DISPLAY{0}' -f $displayIndex)
        if ($seenNames.ContainsKey($name)) { continue }

        $current = Get-LlcDisplayCurrentModeRecord -DeviceName $name
        if ($null -eq $current) { continue }

        [void]$knownNameFallbackDisplays.Add([pscustomobject]@{
            Index = (1000 + $displayIndex)
            DeviceName = $name
            DeviceString = 'active display mode fallback'
            IsPrimary = ($displayIndex -eq 1)
            DiscoverySource = 'known-display-name-current-mode-fallback'
        })
    }

    if ($knownNameFallbackDisplays.Count -gt 0) {
        Write-StatusLine -Ok $true -Warning -Text 'Display Mode Auto: EnumDisplayDevices reported no attached desktop displays; using active \\.\DISPLAY# devices verified by current-mode read'
        return @($knownNameFallbackDisplays)
    }

    return @()
}

function Get-LlcDisplayCurrentModeRecord {
    param([Parameter(Mandatory=$true)][string]$DeviceName)

    $current = New-LlcDevModeStruct
    if (-not [LLC.DisplayNative]::EnumDisplaySettings($DeviceName, [LLC.DisplayNative]::ENUM_CURRENT_SETTINGS, [ref]$current)) {
        return $null
    }

    return [pscustomobject]@{
        Width = [int]$current.dmPelsWidth
        Height = [int]$current.dmPelsHeight
        Refresh = [int]$current.dmDisplayFrequency
        Bits = [int]$current.dmBitsPerPel
        Flags = [int]$current.dmDisplayFlags
    }
}

function New-LlcDevModeFromDisplayModeRecord {
    param([Parameter(Mandatory=$true)][object]$Record)

    $mode = New-LlcDevModeStruct
    $mode.dmFields = [LLC.DisplayNative]::DM_BITSPERPEL -bor [LLC.DisplayNative]::DM_PELSWIDTH -bor [LLC.DisplayNative]::DM_PELSHEIGHT -bor [LLC.DisplayNative]::DM_DISPLAYFLAGS -bor [LLC.DisplayNative]::DM_DISPLAYFREQUENCY
    $mode.dmBitsPerPel = [int]$Record.Bits
    $mode.dmPelsWidth = [int]$Record.Width
    $mode.dmPelsHeight = [int]$Record.Height
    $mode.dmDisplayFlags = [int]$Record.Flags
    $mode.dmDisplayFrequency = [int]$Record.Refresh
    return $mode
}

function Get-LlcDisplayModeCandidates {
    param([Parameter(Mandatory=$true)][string]$DeviceName)

    $records = New-Object System.Collections.ArrayList
    $seen = @{}

    for ($modeIndex = 0; $modeIndex -lt 4096; $modeIndex++) {
        $mode = New-LlcDevModeStruct
        $ok = [LLC.DisplayNative]::EnumDisplaySettings($DeviceName, [int]$modeIndex, [ref]$mode)
        if (-not $ok) { break }

        $width = [int]$mode.dmPelsWidth
        $height = [int]$mode.dmPelsHeight
        $refresh = [int]$mode.dmDisplayFrequency
        $bits = [int]$mode.dmBitsPerPel
        $flags = [int]$mode.dmDisplayFlags

        if ($width -lt 640 -or $height -lt 480) { continue }
        if ($refresh -lt 1) { continue }
        if ($bits -lt 24) { continue }

        $key = '{0}x{1}@{2}:{3}:{4}' -f $width, $height, $refresh, $bits, $flags
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true

        $progressiveScore = 1
        if (($flags -band 2) -ne 0) { $progressiveScore = 0 }

        [void]$records.Add([pscustomobject]@{
            Width = $width
            Height = $height
            Refresh = $refresh
            Bits = $bits
            Flags = $flags
            Pixels = ($width * $height)
            ProgressiveScore = $progressiveScore
        })
    }

    return @($records | Sort-Object `
        @{ Expression = 'Refresh'; Descending = $true }, `
        @{ Expression = 'Pixels'; Descending = $true }, `
        @{ Expression = 'ProgressiveScore'; Descending = $true }, `
        @{ Expression = 'Width'; Descending = $true }, `
        @{ Expression = 'Height'; Descending = $true }, `
        @{ Expression = 'Bits'; Descending = $true })
}

function Test-LlcDisplayModeAlreadyActive {
    param(
        [AllowNull()][object]$Current,
        [Parameter(Mandatory=$true)][object]$Candidate
    )

    if ($null -eq $Current) { return $false }
    return (([int]$Current.Width -eq [int]$Candidate.Width) -and ([int]$Current.Height -eq [int]$Candidate.Height) -and ([int]$Current.Refresh -eq [int]$Candidate.Refresh))
}

function Invoke-LlcDisplayModeApply {
    param(
        [Parameter(Mandatory=$true)][string]$DeviceName,
        [Parameter(Mandatory=$true)][object]$Candidate
    )

    $testMode = New-LlcDevModeFromDisplayModeRecord -Record $Candidate
    $testResult = [LLC.DisplayNative]::ChangeDisplaySettingsEx($DeviceName, [ref]$testMode, [IntPtr]::Zero, [LLC.DisplayNative]::CDS_TEST, [IntPtr]::Zero)
    if ($testResult -ne [LLC.DisplayNative]::DISP_CHANGE_SUCCESSFUL) {
        return [pscustomobject]@{ Ok=$false; Changed=$false; Message="mode rejected by driver during test: $(Get-LlcDisplayChangeResultText -Code $testResult)" }
    }

    $applyMode = New-LlcDevModeFromDisplayModeRecord -Record $Candidate
    $applyResult = [LLC.DisplayNative]::ChangeDisplaySettingsEx($DeviceName, [ref]$applyMode, [IntPtr]::Zero, [LLC.DisplayNative]::CDS_UPDATEREGISTRY, [IntPtr]::Zero)
    if ($applyResult -ne [LLC.DisplayNative]::DISP_CHANGE_SUCCESSFUL -and $applyResult -ne [LLC.DisplayNative]::DISP_CHANGE_RESTART) {
        return [pscustomobject]@{ Ok=$false; Changed=$false; Message="apply failed: $(Get-LlcDisplayChangeResultText -Code $applyResult)" }
    }

    try { [LLC.DisplayNative]::ChangeDisplaySettingsExNull($null, [IntPtr]::Zero, [IntPtr]::Zero, 0, [IntPtr]::Zero) | Out-Null } catch { }
    Start-Sleep -Milliseconds 750

    $after = Get-LlcDisplayCurrentModeRecord -DeviceName $DeviceName
    $verified = Test-LlcDisplayModeAlreadyActive -Current $after -Candidate $Candidate
    if ($verified) {
        if ($applyResult -eq [LLC.DisplayNative]::DISP_CHANGE_RESTART) {
            return [pscustomobject]@{ Ok=$true; Warning=$true; Changed=$true; Message='mode applied and verified, but driver also returned DISP_CHANGE_RESTART' }
        }
        return [pscustomobject]@{ Ok=$true; Changed=$true; Message='mode applied and verified active immediately' }
    }

    $afterText = 'unknown current mode'
    if ($null -ne $after) { $afterText = ('current after apply: {0}x{1}@{2}Hz' -f $after.Width, $after.Height, $after.Refresh) }

    if ($applyResult -eq [LLC.DisplayNative]::DISP_CHANGE_RESTART) {
        return [pscustomobject]@{ Ok=$true; Warning=$true; Changed=$true; Message="mode saved, but the driver requested restart before verification matched ($afterText)" }
    }

    return [pscustomobject]@{ Ok=$false; Changed=$true; Message="Windows reported success, but verification did not match target ($afterText)" }
}

function Invoke-DisplayModeHighestRefreshAuto {
    Write-Host ''
    Write-BoxTitle -Title 'Display Mode - Highest Refresh Rate First / Resolution Tie-Breaker'
    Write-Host ''
    Write-Host 'Scanning active desktop monitor PC display modes. Selection priority: highest refresh rate first; resolution is only used as the tie-breaker.' -ForegroundColor White
    Write-Host ''

    if (-not (Initialize-LlcDisplayNative)) { return $false }

    $displays = @(Get-LlcAttachedDesktopDisplays)
    if ($displays.Count -lt 1) {
        Write-StatusLine -Ok $true -Warning -Text 'Display Mode Auto: no attached desktop displays found; skipped safely'
        return $true
    }

    $failed = 0
    $changed = 0

    foreach ($display in @($displays)) {
        $label = $display.DeviceName
        if (-not [string]::IsNullOrWhiteSpace($display.DeviceString)) { $label = "$($display.DeviceName) ($($display.DeviceString))" }
        if ($display.IsPrimary) { $label = "$label [primary]" }

        $current = Get-LlcDisplayCurrentModeRecord -DeviceName $display.DeviceName
        if ($null -eq $current) {
            $failed++
            Write-StatusLine -Ok $false -Text "Display Mode Auto | $label | could not read current mode"
            continue
        }

        $candidates = @(Get-LlcDisplayModeCandidates -DeviceName $display.DeviceName)
        if ($candidates.Count -lt 1) {
            Write-StatusLine -Ok $true -Warning -Text "Display Mode Auto | $label | no usable 24-bit+ display modes were reported; skipped safely"
            continue
        }

        $selected = $null
        $lastReject = ''
        foreach ($candidate in @($candidates)) {
            $testMode = New-LlcDevModeFromDisplayModeRecord -Record $candidate
            $testResult = [LLC.DisplayNative]::ChangeDisplaySettingsEx($display.DeviceName, [ref]$testMode, [IntPtr]::Zero, [LLC.DisplayNative]::CDS_TEST, [IntPtr]::Zero)
            if ($testResult -eq [LLC.DisplayNative]::DISP_CHANGE_SUCCESSFUL) {
                $selected = $candidate
                break
            }
            $lastReject = ('{0}x{1}@{2}Hz -> {3}' -f $candidate.Width, $candidate.Height, $candidate.Refresh, (Get-LlcDisplayChangeResultText -Code $testResult))
        }

        if ($null -eq $selected) {
            $failed++
            if ([string]::IsNullOrWhiteSpace($lastReject)) { $lastReject = 'all candidates rejected or unavailable' }
            Write-StatusLine -Ok $false -Text "Display Mode Auto | $label | no driver-accepted mode found ($lastReject)"
            continue
        }

        $currentText = '{0}x{1}@{2}Hz' -f $current.Width, $current.Height, $current.Refresh
        $targetText = '{0}x{1}@{2}Hz' -f $selected.Width, $selected.Height, $selected.Refresh

        if (Test-LlcDisplayModeAlreadyActive -Current $current -Candidate $selected) {
            Write-StatusLine -Ok $true -Text "Display Mode Auto | $label | already active: $currentText; skipped safely"
            continue
        }

        $apply = Invoke-LlcDisplayModeApply -DeviceName $display.DeviceName -Candidate $selected
        if ($apply.Changed) { $changed++ }
        if (-not $apply.Ok) { $failed++ }
        Write-StatusLine -Ok $apply.Ok -Text "Display Mode Auto | $label | $currentText -> $targetText | $($apply.Message)" -Warning:($apply.PSObject.Properties.Name -contains 'Warning' -and [bool]$apply.Warning)
    }

    if ($failed -eq 0) {
        if ($changed -gt 0) {
            Write-Host ''
            Write-Host ("OVERALL: SUCCESS - Display Mode Auto changed {0} display(s) and activated the selected mode(s)." -f $changed) -ForegroundColor Green
        } else {
            Write-Host ''
            Write-Host 'OVERALL: SUCCESS - Display Mode Auto found the best mode already active or skipped unavailable displays safely.' -ForegroundColor Green
        }
    } else {
        Write-Host ''
        Write-Host ("OVERALL: FAILED/WARNING - {0} display mode step(s) reported a failure." -f $failed) -ForegroundColor Red
    }

    Write-Host ''
    return ($failed -eq 0)
}

function Invoke-AutoRegistryStepSafely {
    param(
        [Parameter(Mandatory=$true)][string]$Title,
        [Parameter(Mandatory=$true)][scriptblock]$Action
    )

    try {
        return [bool](& $Action)
    }
    catch {
        Write-Host ''
        Write-BoxTitle -Title $Title
        Write-Host ''
        Write-StatusLine -Ok $false -Text ("Unhandled error: {0}" -f $_.Exception.Message)

        if ($_.InvocationInfo -and -not [string]::IsNullOrWhiteSpace($_.InvocationInfo.PositionMessage)) {
            Write-Host ''
            Write-Host $_.InvocationInfo.PositionMessage -ForegroundColor DarkGray
        }

        Write-Host ''
        Write-Host 'OVERALL: FAILED - The error was handled; the menu will remain open.' -ForegroundColor Red
        return $false
    }
}

function Invoke-AutoRegistryTweaks {
    if (-not (Confirm-LlcBroadChanges -Scope Auto)) { return }
    try {
        Clear-ConsoleScreen
        Write-BoxTitle -Title 'Auto Registry Tweaks'
        Write-Host ''
        Write-Host 'Auto-mode will apply these entries in order:' -ForegroundColor White
        Write-Host 'UAC Disable -> QOL Optimize (includes full classic context menu, Explorer-only taskbar, and OneDrive full disable without uninstall) -> Hardware-Accelerated GPU Scheduling Enable -> Display Mode Highest Refresh First / Resolution Tie-Breaker -> Fullscreen Optimization Disable -> Gamebar/Game Mode Disable -> Services Disable -> Power Plan Import/Activate -> Powersaving Disable -> Network Optimization Enable (wired Ethernet only) -> MMCSS Auto -> Win32PrioritySeparation 18 hex -> Clock Interrupts Core 0 -> Nvidia Profile Inspector .nip import -> GPU Auto' -ForegroundColor DarkGray

        $failures = 0

        if (-not (Invoke-AutoRegistryStepSafely -Title 'UAC - Disable' -Action { Invoke-RegistrySetAuto -Title 'UAC - Disable' -Items $uacDisable -AfterMessage '' })) { $failures++ }
        if (-not (Invoke-AutoRegistryStepSafely -Title 'QOL - Optimize' -Action { Invoke-QolOptimizeAuto })) { $failures++ }
        if (-not (Invoke-AutoRegistryStepSafely -Title 'Hardware-Accelerated GPU Scheduling - Enable' -Action { Invoke-RegistrySetAuto -Title 'Hardware-Accelerated GPU Scheduling - Enable' -Items $hagsEnable })) { $failures++ }
        if (-not (Invoke-AutoRegistryStepSafely -Title 'Display Mode - Highest Refresh Rate First / Resolution Tie-Breaker' -Action { Invoke-DisplayModeHighestRefreshAuto })) { $failures++ }
        if (-not (Invoke-AutoRegistryStepSafely -Title 'Fullscreen Optimization - Disable' -Action { Invoke-RegistrySetAuto -Title 'Fullscreen Optimization - Disable' -Items $fsoDisable -AfterMessage '' })) { $failures++ }
        if (-not (Invoke-AutoRegistryStepSafely -Title 'Game Bar - Disable' -Action { Invoke-RegistrySetAuto -Title 'Game Bar - Disable' -Items $gameBarDisable -AfterMessage '' })) { $failures++ }
        if (-not (Invoke-AutoRegistryStepSafely -Title 'Game Mode - Disable' -Action { Invoke-RegistrySetAuto -Title 'Game Mode - Disable' -Items $gameModeDisable -AfterMessage '' })) { $failures++ }
        if (-not (Invoke-AutoRegistryStepSafely -Title 'Services - Disable' -Action { Invoke-RegistrySetAuto -Title 'Services - Disable' -Items $servicesToDisable -AfterMessage '' })) { $failures++ }
        if (-not (Invoke-AutoRegistryStepSafely -Title 'Power Plan - Import and Activate' -Action { Invoke-PowerPlanImportAndActivateAuto })) { $failures++ }
        if (-not (Invoke-AutoRegistryStepSafely -Title 'Powersaving - Disable' -Action { Invoke-DisableDevicePowerSavingAuto })) { $failures++ }
        if (-not (Invoke-AutoRegistryStepSafely -Title 'Network Optimization - Enable' -Action { Invoke-NetworkOptimizationEnableAuto })) { $failures++ }
        if (-not (Invoke-AutoRegistryStepSafely -Title 'MMCSS - Auto' -Action { Invoke-MmcssAuto })) { $failures++ }
        if (-not (Invoke-AutoRegistryStepSafely -Title 'Win32PrioritySeparation - 18 (hex)' -Action { Invoke-RegistrySetAuto -Title 'Win32PrioritySeparation - 18 (hex)' -Items $win32PrioritySeparation18Hex -AfterMessage '' })) { $failures++ }
        if (-not (Invoke-AutoRegistryStepSafely -Title 'Clock Interrupts - Core 0' -Action { Invoke-RegistrySetAuto -Title 'Clock Interrupts - Core 0' -Items $clockInterruptsCore0 -AfterMessage '' })) { $failures++ }
        if (-not (Invoke-AutoRegistryStepSafely -Title 'Nvidia Profile Inspector - Import .nip' -Action { Invoke-NvidiaProfileInspectorImportAuto })) { $failures++ }
        if (-not (Invoke-AutoRegistryStepSafely -Title 'GPU - Auto' -Action { Invoke-GpuTweaksAuto })) { $failures++ }

        Write-Host ''
        Write-BoxTitle -Title 'Auto Registry Tweaks - Completed'
        Write-Host ''
        if ($failures -eq 0) {
            Write-Host 'OVERALL: SUCCESS - Auto Registry Tweaks completed.' -ForegroundColor Green
        } else {
            Write-Host ("OVERALL: FAILED/WARNING - {0} auto step(s) reported a failure or warning. Review the output above." -f $failures) -ForegroundColor Red
        }
    }
    catch {
        Write-Host ''
        Write-BoxTitle -Title 'Auto Registry Tweaks - Error'
        Write-Host ''
        Write-StatusLine -Ok $false -Text ("Unhandled auto registry error: {0}" -f $_.Exception.Message)

        if ($_.InvocationInfo -and -not [string]::IsNullOrWhiteSpace($_.InvocationInfo.PositionMessage)) {
            Write-Host ''
            Write-Host $_.InvocationInfo.PositionMessage -ForegroundColor DarkGray
        }

        Write-Host ''
        Write-Host 'The error was handled; press Enter to return to the menu.' -ForegroundColor Yellow
    }
    finally {
        Write-Host ''
        Wait-ForEnterToContinue
    }
}



function Get-QolRegistryItemBooleanProperty {
    param(
        [AllowNull()][object]$Item,
        [Parameter(Mandatory=$true)][string]$Name
    )

    if ($null -eq $Item) { return $false }
    if (-not ($Item.PSObject.Properties.Name -contains $Name)) { return $false }
    try { return [bool]$Item.$Name } catch { return $false }
}

function Get-QolRegistryItemStringProperty {
    param(
        [AllowNull()][object]$Item,
        [Parameter(Mandatory=$true)][string]$Name,
        [string]$Default = ''
    )

    if ($null -eq $Item) { return $Default }
    if (-not ($Item.PSObject.Properties.Name -contains $Name)) { return $Default }
    try {
        $value = [string]$Item.$Name
        if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }
    } catch { }
    return $Default
}

function Get-QolRegistryItemDisplayText {
    param([AllowNull()][object]$Item)

    $description = Get-QolRegistryItemStringProperty -Item $Item -Name 'Description'
    if (-not [string]::IsNullOrWhiteSpace($description)) { return $description }

    $key = Get-QolRegistryItemStringProperty -Item $Item -Name 'Key'
    if ([string]::IsNullOrWhiteSpace($key)) { $key = Get-QolRegistryItemStringProperty -Item $Item -Name 'SubKey' }
    $name = Get-QolRegistryItemStringProperty -Item $Item -Name 'Name'

    if ([string]::IsNullOrWhiteSpace($key) -and [string]::IsNullOrWhiteSpace($name)) { return 'registry item' }
    if ([string]::IsNullOrWhiteSpace($name)) { return $key }
    if ([string]::IsNullOrWhiteSpace($key)) { return $name }
    return "$key\$name"
}

function Get-QolRegistryItemPolicyFallbackText {
    param([AllowNull()][object]$Item)

    $fallback = Get-QolRegistryItemStringProperty -Item $Item -Name 'PolicyFallback'
    if (-not [string]::IsNullOrWhiteSpace($fallback)) { return $fallback }
    return 'a machine-wide policy fallback covers this setting'
}

function Convert-QolRegistryItemResultForBestEffort {
    param(
        [AllowNull()][object]$Item,
        [Parameter(Mandatory=$true)][object]$Result
    )

    if ($Result.Ok) { return $Result }
    if (-not (Get-QolRegistryItemBooleanProperty -Item $Item -Name 'BestEffort')) { return $Result }

    $display = Get-QolRegistryItemDisplayText -Item $Item
    $fallback = Get-QolRegistryItemPolicyFallbackText -Item $Item
    return [pscustomobject]@{
        Ok      = $true
        Warning = $true
        Message = "${display} | best-effort per-user registry preference was blocked; continuing because ${fallback}"
    }
}

function Test-QolSkipUserHiveSweepRegistryItem {
    param([AllowNull()][object]$Item)

    return (Get-QolRegistryItemBooleanProperty -Item $Item -Name 'SkipUserHiveSweep')
}

function Invoke-RegistryItemsInline {
    param(
        [Parameter(Mandatory=$true)][object[]]$Items
    )

    $failed = 0
    foreach ($item in @(Select-QolUniqueRegistryItems -Items $Items)) {
        $create = $false
        if ($item.PSObject.Properties.Name -contains 'CreateKey') { $create = [bool]$item.CreateKey }

        $type = 'DWord'
        if ($item.PSObject.Properties.Name -contains 'Type') { $type = [string]$item.Type }

        switch -Regex ($type) {
            '^(DWord|REG_DWORD)$' {
                $result = Set-RegistryDword -Key $item.Key -Name $item.Name -Value $item.Value -CreateKey:$create
                break
            }
            '^(String|REG_SZ)$' {
                $result = Set-RegistryString -Key $item.Key -Name $item.Name -Value ([string]$item.Value) -CreateKey:$create
                break
            }
            '^(DefaultString|DefaultValue|REG_SZ_DEFAULT|REG_DEFAULT_SZ)$' {
                $value = ''
                if ($item.PSObject.Properties.Name -contains 'Value') { $value = [string]$item.Value }
                $result = Set-RegistryDefaultString -Key $item.Key -Value $value -CreateKey:$create
                break
            }
            '^(Binary|REG_BINARY)$' {
                $result = Set-RegistryBinary -Key $item.Key -Name $item.Name -Value $item.Value -CreateKey:$create
                break
            }
            '^(Delete|DeleteValue|Remove|RemoveValue|REG_DELETE)$' {
                $result = Remove-RegistryValue -Key $item.Key -Name $item.Name
                break
            }
            default {
                $result = [pscustomobject]@{ Ok = $false; Message = "unsupported registry value type '$type' for $($item.Key)\$($item.Name)" }
                break
            }
        }

        $result = Convert-QolRegistryItemResultForBestEffort -Item $item -Result $result
        if (-not $result.Ok) { $failed++ }
        $isWarning = $false
        if ($result.PSObject.Properties.Name -contains 'Warning') { $isWarning = [bool]$result.Warning }
        $label = $result.Message
        if ($item.PSObject.Properties.Name -contains 'Description') { $label = $item.Description + ' | ' + $result.Message }
        Write-StatusLine -Ok $result.Ok -Text $label -Warning:$isWarning
    }

    return ($failed -eq 0)
}

function New-WindowsShortcutFile {
    param(
        [Parameter(Mandatory=$true)][string]$ShortcutPath,
        [Parameter(Mandatory=$true)][string]$TargetPath,
        [string]$Arguments = '',
        [string]$WorkingDirectory = '',
        [string]$IconLocation = ''
    )

    try {
        $shortcutDirectory = Split-Path -Parent $ShortcutPath
        if (-not (Test-Path -LiteralPath $shortcutDirectory)) {
            New-Item -Path $shortcutDirectory -ItemType Directory -Force | Out-Null
        }

        $shell = New-Object -ComObject WScript.Shell
        try {
            $shortcut = $shell.CreateShortcut($ShortcutPath)
            $shortcut.TargetPath = $TargetPath
            $shortcut.Arguments = $Arguments
            if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) { $shortcut.WorkingDirectory = $WorkingDirectory }
            if (-not [string]::IsNullOrWhiteSpace($IconLocation)) { $shortcut.IconLocation = $IconLocation }
            $shortcut.Save()
        }
        finally {
            if ($null -ne $shortcut) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shortcut) }
            if ($null -ne $shell) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell) }
        }

        if (Test-Path -LiteralPath $ShortcutPath -PathType Leaf) {
            return [pscustomobject]@{ Ok = $true; Message = "created shortcut: $ShortcutPath" }
        }

        return [pscustomobject]@{ Ok = $false; Message = "shortcut was not created: $ShortcutPath" }
    }
    catch {
        return [pscustomobject]@{ Ok = $false; Message = "shortcut creation failed: $($_.Exception.Message)" }
    }
}

function Get-QolExplorerOnlyTaskbarLayoutXml {
    return @"
<?xml version="1.0" encoding="utf-8"?>
<LayoutModificationTemplate
    xmlns="http://schemas.microsoft.com/Start/2014/LayoutModification"
    xmlns:defaultlayout="http://schemas.microsoft.com/Start/2014/FullDefaultLayout"
    xmlns:start="http://schemas.microsoft.com/Start/2014/StartLayout"
    xmlns:taskbar="http://schemas.microsoft.com/Start/2014/TaskbarLayout"
    Version="1">
  <CustomTaskbarLayoutCollection PinListPlacement="Replace">
    <defaultlayout:TaskbarLayout>
      <taskbar:TaskbarPinList>
        <taskbar:DesktopApp DesktopApplicationID="Microsoft.Windows.Explorer" />
      </taskbar:TaskbarPinList>
    </defaultlayout:TaskbarLayout>
  </CustomTaskbarLayoutCollection>
</LayoutModificationTemplate>
"@
}

function Write-QolExplorerOnlyTaskbarLayoutFile {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$LayoutXml,
        [string]$Label = 'taskbar layout XML'
    )

    try {
        $directory = Split-Path -Parent $Path
        if (-not [string]::IsNullOrWhiteSpace($directory) -and -not (Test-Path -LiteralPath $directory)) {
            New-Item -Path $directory -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }

        Set-Content -LiteralPath $Path -Value $LayoutXml -Encoding UTF8 -Force -ErrorAction Stop
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            Write-StatusLine -Ok $true -Text "$Label | wrote: $Path"
            return $true
        }

        Write-StatusLine -Ok $false -Text "$Label | file was not created: $Path"
        return $false
    }
    catch {
        Write-StatusLine -Ok $false -Text "$Label | could not write $Path -> $($_.Exception.Message)"
        return $false
    }
}

function Write-QolExplorerOnlyTaskbarLayoutForProfilePath {
    param(
        [Parameter(Mandatory=$true)][string]$ProfilePath,
        [string]$Label = 'taskbar layout XML'
    )

    if ([string]::IsNullOrWhiteSpace($ProfilePath)) { return $true }
    if (-not (Test-Path -LiteralPath $ProfilePath -PathType Container)) {
        Write-StatusLine -Ok $true -Warning -Text "$Label | profile path not found, skipped: $ProfilePath"
        return $true
    }

    $layoutXml = Get-QolExplorerOnlyTaskbarLayoutXml
    $failed = 0
    $targetFolders = @(
        (Join-Path $ProfilePath 'AppData\Local\Microsoft\Windows\Shell'),
        (Join-Path $ProfilePath 'AppData\Roaming\Microsoft\Windows\Shell')
    ) | Select-Object -Unique

    foreach ($folder in @($targetFolders)) {
        foreach ($name in @('LayoutModification.xml', 'TaskbarLayoutModification.xml')) {
            $target = Join-Path $folder $name
            if (-not (Write-QolExplorerOnlyTaskbarLayoutFile -Path $target -LayoutXml $layoutXml -Label $Label)) { $failed++ }
        }
    }

    return ($failed -eq 0)
}

function Write-QolExplorerOnlyTaskbarLayoutSystemFiles {
    $layoutXml = Get-QolExplorerOnlyTaskbarLayoutXml
    $failed = 0
    $policyPath = Join-Path $env:ProgramData 'LowLatencyCorp\Taskbar\ExplorerOnlyTaskbarLayout.xml'

    $targets = New-Object System.Collections.ArrayList
    [void]$targets.Add($policyPath)
    [void]$targets.Add((Join-Path $env:ProgramData 'LowLatencyCorp\Taskbar\TaskbarLayoutModification.xml'))

    $windowsDirectory = $env:WINDIR
    if ([string]::IsNullOrWhiteSpace($windowsDirectory)) { $windowsDirectory = Join-Path $env:SystemDrive 'Windows' }
    if (-not [string]::IsNullOrWhiteSpace($windowsDirectory)) {
        [void]$targets.Add((Join-Path $windowsDirectory 'OEM\TaskbarLayoutModification.xml'))
    }

    if (-not [string]::IsNullOrWhiteSpace($env:SystemDrive)) {
        [void]$targets.Add((Join-Path $env:SystemDrive 'Recovery\AutoApply\TaskbarLayoutModification.xml'))
    }

    foreach ($target in @($targets | Select-Object -Unique)) {
        if (-not (Write-QolExplorerOnlyTaskbarLayoutFile -Path $target -LayoutXml $layoutXml -Label 'system taskbar layout XML')) { $failed++ }
    }

    return [pscustomobject]@{ Ok = ($failed -eq 0); PolicyPath = $policyPath }
}

function Set-QolExplorerOnlyTaskbarLayoutPolicy {
    param([Parameter(Mandatory=$true)][string]$LayoutFile)

    if ([string]::IsNullOrWhiteSpace($LayoutFile) -or -not (Test-Path -LiteralPath $LayoutFile -PathType Leaf)) {
        Write-StatusLine -Ok $false -Text "Taskbar layout policy | layout XML missing: $LayoutFile"
        return $false
    }

    $items = @(
        [pscustomobject]@{ Key='HKEY_CURRENT_USER\Software\Policies\Microsoft\Windows\Explorer'; Name='StartLayoutFile'; Value=$LayoutFile; Type='String'; CreateKey=$true; Description='Taskbar layout policy: Explorer-only XML path for current user' },
        [pscustomobject]@{ Key='HKEY_CURRENT_USER\Software\Policies\Microsoft\Windows\Explorer'; Name='LockedStartLayout'; Value=1; Type='DWord'; CreateKey=$true; Description='Taskbar layout policy: force Explorer-only replacement layout for current user' },
        [pscustomobject]@{ Key='HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\Explorer'; Name='StartLayoutFile'; Value=$LayoutFile; Type='String'; CreateKey=$true; Description='Taskbar layout policy: Explorer-only XML path machine-wide' },
        [pscustomobject]@{ Key='HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\Explorer'; Name='LockedStartLayout'; Value=1; Type='DWord'; CreateKey=$true; Description='Taskbar layout policy: force Explorer-only replacement layout machine-wide' }
    )

    return (Invoke-RegistryItemsInline -Items $items)
}

function Invoke-QolBestEffortTaskbarPinVerb {
    param([Parameter(Mandatory=$true)][string]$ShortcutPath)

    try {
        if (-not (Test-Path -LiteralPath $ShortcutPath -PathType Leaf)) {
            return [pscustomobject]@{ Ok=$true; Warning=$true; Message="Explorer taskbar pin verb skipped; shortcut not found: $ShortcutPath" }
        }

        $folderPath = Split-Path -Parent $ShortcutPath
        $leafName = Split-Path -Leaf $ShortcutPath
        $shell = New-Object -ComObject Shell.Application
        try {
            $folder = $shell.Namespace($folderPath)
            if ($null -eq $folder) { return [pscustomobject]@{ Ok=$true; Warning=$true; Message="Explorer taskbar pin verb unavailable for folder: $folderPath" } }
            $item = $folder.ParseName($leafName)
            if ($null -eq $item) { return [pscustomobject]@{ Ok=$true; Warning=$true; Message="Explorer taskbar pin verb unavailable for shortcut: $leafName" } }

            try {
                $item.InvokeVerb('taskbarpin')
                return [pscustomobject]@{ Ok=$true; Message='requested Explorer pin through taskbarpin shell verb' }
            }
            catch { }

            foreach ($verb in @($item.Verbs())) {
                $verbName = ''
                try { $verbName = ([string]$verb.Name) -replace '&','' } catch { }
                if ($verbName -match '(?i)pin.*taskbar') {
                    try {
                        $verb.DoIt()
                        return [pscustomobject]@{ Ok=$true; Message="requested Explorer pin through shell verb: $verbName" }
                    }
                    catch { }
                }
            }

            return [pscustomobject]@{ Ok=$true; Warning=$true; Message='Explorer taskbar pin verb was not exposed by this Windows build; XML/policy pinning remains active' }
        }
        finally {
            if ($null -ne $shell) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell) }
        }
    }
    catch {
        return [pscustomobject]@{ Ok=$true; Warning=$true; Message="Explorer taskbar pin verb failed best-effort; XML/policy pinning remains active: $($_.Exception.Message)" }
    }
}


function Send-TaskbarOptimizeSettingRefresh {
    try {
        if (-not ('LowLatencySettingRefreshNativeMethods' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class LowLatencySettingRefreshNativeMethods
{
    [DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    public static extern IntPtr SendMessageTimeout(
        IntPtr hWnd,
        UInt32 Msg,
        UIntPtr wParam,
        string lParam,
        UInt32 fuFlags,
        UInt32 uTimeout,
        out UIntPtr lpdwResult);

    [DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool SendNotifyMessage(
        IntPtr hWnd,
        UInt32 Msg,
        UIntPtr wParam,
        string lParam);
}
'@ -ErrorAction Stop
        }

        $hwndBroadcast = [IntPtr]65535
        $wmSettingChange = [uint32]0x001A
        $smtoAbortIfHung = [uint32]0x0002
        $timeoutMilliseconds = [uint32]2500
        $targets = @(
            'ImmersiveColorSet',
            'WindowsThemeElement',
            'UserPreferences',
            'Policy',
            'Environment',
            'Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
        )

        $sentCount = 0
        $warnings = New-Object System.Collections.Generic.List[string]

        foreach ($target in $targets) {
            try {
                $messageResult = [UIntPtr]::Zero
                $sendResult = [LowLatencySettingRefreshNativeMethods]::SendMessageTimeout(
                    $hwndBroadcast,
                    $wmSettingChange,
                    [UIntPtr]::Zero,
                    $target,
                    $smtoAbortIfHung,
                    $timeoutMilliseconds,
                    [ref]$messageResult)

                if ($sendResult -ne [IntPtr]::Zero) {
                    $sentCount++
                } else {
                    $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
                    if ($err -ne 1460) { [void]$warnings.Add(("{0}: SendMessageTimeout Win32 error {1}" -f $target, $err)) }
                }
            }
            catch {
                [void]$warnings.Add(("{0}: SendMessageTimeout exception: {1}" -f $target, $_.Exception.Message))
            }

            try {
                if ([LowLatencySettingRefreshNativeMethods]::SendNotifyMessage($hwndBroadcast, $wmSettingChange, [UIntPtr]::Zero, $target)) {
                    $sentCount++
                } else {
                    $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
                    if ($err -ne 0) { [void]$warnings.Add(("{0}: SendNotifyMessage Win32 error {1}" -f $target, $err)) }
                }
            }
            catch {
                [void]$warnings.Add(("{0}: SendNotifyMessage exception: {1}" -f $target, $_.Exception.Message))
            }
        }

        if ($sentCount -gt 0) {
            if ($warnings.Count -gt 0) {
                return [pscustomobject]@{ Ok = $true; Warning = $true; Message = ("requested Windows personalization refresh via setting-change broadcasts; {0} broadcast(s) sent; non-fatal detail: {1}" -f $sentCount, (($warnings | Select-Object -First 3) -join '; ')) }
            }

            return [pscustomobject]@{ Ok = $true; Message = ("requested Windows personalization refresh via setting-change broadcasts; {0} broadcast(s) sent" -f $sentCount) }
        }

        return [pscustomobject]@{ Ok = $true; Warning = $true; Message = ("requested Windows personalization refresh, but no setting-change broadcasts completed; changes are written and may apply after sign-out or Explorer restart. Detail: {0}" -f (($warnings | Select-Object -First 5) -join '; ')) }
    }
    catch {
        return [pscustomobject]@{ Ok = $true; Warning = $true; Message = "requested Windows personalization refresh; setting-change broadcast exception ignored as best-effort: $($_.Exception.Message)" }
    }
}

function Set-TaskbarPinnedAppsToExplorerOnly {
    $failed = 0

    try {
        $windowsDirectory = $env:WINDIR
        if ([string]::IsNullOrWhiteSpace($windowsDirectory)) { $windowsDirectory = 'C:\Windows' }

        $explorerExe = Join-Path $windowsDirectory 'explorer.exe'
        if (-not (Test-Path -LiteralPath $explorerExe -PathType Leaf)) {
            Write-StatusLine -Ok $false -Text "explorer.exe not found: $explorerExe"
            return $false
        }

        $pinnedFolder = Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'
        if (-not (Test-Path -LiteralPath $pinnedFolder)) {
            New-Item -Path $pinnedFolder -ItemType Directory -Force | Out-Null
        }

        $startMenuProgramsFolder = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
        $startMenuExplorerShortcut = Join-Path $startMenuProgramsFolder 'File Explorer.lnk'
        $taskbarExplorerShortcut = Join-Path $pinnedFolder 'File Explorer.lnk'

        try {
            Get-ChildItem -LiteralPath $pinnedFolder -Force -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction Stop
            Write-StatusLine -Ok $true -Text "removed existing taskbar pinned shortcuts from: $pinnedFolder"
        }
        catch {
            $failed++
            Write-StatusLine -Ok $false -Text "could not clear taskbar pinned shortcut folder: $($_.Exception.Message)"
        }

        foreach ($shortcutPath in @($startMenuExplorerShortcut, $taskbarExplorerShortcut)) {
            $shortcutResult = New-WindowsShortcutFile -ShortcutPath $shortcutPath -TargetPath $explorerExe -WorkingDirectory $windowsDirectory -IconLocation ("{0},0" -f $explorerExe)
            if (-not $shortcutResult.Ok) { $failed++ }
            Write-StatusLine -Ok $shortcutResult.Ok -Text $shortcutResult.Message
        }

        $taskbandKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband'
        try {
            if (Test-Path -LiteralPath $taskbandKey) {
                Remove-Item -LiteralPath $taskbandKey -Recurse -Force -ErrorAction Stop
                Write-StatusLine -Ok $true -Text 'removed Explorer Taskband binary pin cache'
            } else {
                Write-StatusLine -Ok $true -Text 'Explorer Taskband key was already absent'
            }
        }
        catch {
            $failed++
            Write-StatusLine -Ok $false -Text "could not remove Explorer Taskband cache: $($_.Exception.Message)"
        }

        foreach ($userShellFolder in (@(
            (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Shell'),
            (Join-Path $env:APPDATA 'Microsoft\Windows\Shell')
        ) | Select-Object -Unique)) {
            try {
                if (-not (Test-Path -LiteralPath $userShellFolder)) {
                    New-Item -Path $userShellFolder -ItemType Directory -Force | Out-Null
                }

                Get-ChildItem -LiteralPath $userShellFolder -Filter '*.dat' -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
                Write-StatusLine -Ok $true -Text "cleared current-user Shell layout cache files: $userShellFolder"
            }
            catch {
                Write-StatusLine -Ok $true -Text "could not clear Shell layout cache files, but taskbar cleanup continues: $($_.Exception.Message)" -Warning
            }
        }

        if (-not (Write-QolExplorerOnlyTaskbarLayoutForProfilePath -ProfilePath $env:USERPROFILE -Label 'current-user Explorer-only taskbar layout XML')) { $failed++ }

        $systemLayout = Write-QolExplorerOnlyTaskbarLayoutSystemFiles
        if (-not $systemLayout.Ok) { $failed++ }
        if (-not (Set-QolExplorerOnlyTaskbarLayoutPolicy -LayoutFile $systemLayout.PolicyPath)) { $failed++ }

        $pinVerb = Invoke-QolBestEffortTaskbarPinVerb -ShortcutPath $startMenuExplorerShortcut
        Write-StatusLine -Ok $pinVerb.Ok -Text $pinVerb.Message -Warning:($pinVerb.PSObject.Properties.Name -contains 'Warning' -and [bool]$pinVerb.Warning)

        Write-StatusLine -Ok $true -Text 'Explorer-only taskbar layout is staged in LocalAppData, Roaming fallback, ProgramData policy XML, OEM fallback, and Default-profile-capable locations'
        Write-StatusLine -Ok $true -Text 'Explorer was not restarted; taskbar layout changes may require sign-out or reboot to fully apply'

        return ($failed -eq 0)
    }
    catch {
        Write-StatusLine -Ok $false -Text "taskbar pin cleanup failed: $($_.Exception.Message)"
        return $false
    }
}

function Invoke-TaskbarOptimize {
    param(
        [switch]$Auto
    )

    if (-not $Auto) {
        Clear-ConsoleScreen
    } else {
        Write-Host ''
    }

    Write-BoxTitle -Title 'Taskbar - Optimize'
    Write-Host ''
    Write-Host 'Optimizing taskbar pins, weather/widgets, dark theme, and transparency.' -ForegroundColor White
    Write-Host 'Explorer will not be restarted; some taskbar changes may require sign-out or reboot to fully apply.' -ForegroundColor DarkGray
    Write-Host ''

    $failures = 0

    Write-BoxTitle -Title 'Taskbar Pins'
    Write-Host ''
    if (-not (Set-TaskbarPinnedAppsToExplorerOnly)) { $failures++ }

    Write-Host ''
    Write-BoxTitle -Title 'Weather / Widgets'
    Write-Host ''
    $weatherItems = @(
        [pscustomobject]@{ Key='HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name='TaskbarDa'; Value=0; CreateKey=$true; BestEffort=$true; PolicyFallback='machine policies HKLM\SOFTWARE\Policies\Microsoft\Dsh AllowNewsAndInterests=0 and HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds EnableFeeds=0 are applied by this script' },
        [pscustomobject]@{ Key='HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Feeds'; Name='ShellFeedsTaskbarViewMode'; Value=2; CreateKey=$true; BestEffort=$true; PolicyFallback='machine policies HKLM\SOFTWARE\Policies\Microsoft\Dsh AllowNewsAndInterests=0 and HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds EnableFeeds=0 are applied by this script' },
        [pscustomobject]@{ Key='HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Feeds'; Name='ShellFeedsTaskbarOpenOnHover'; Value=0; CreateKey=$true; BestEffort=$true; PolicyFallback='machine policies HKLM\SOFTWARE\Policies\Microsoft\Dsh AllowNewsAndInterests=0 and HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds EnableFeeds=0 are applied by this script' },
        [pscustomobject]@{ Key='HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Dsh'; Name='AllowNewsAndInterests'; Value=0; CreateKey=$true },
        [pscustomobject]@{ Key='HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds'; Name='EnableFeeds'; Value=0; CreateKey=$true }
    )
    if (-not (Invoke-RegistryItemsInline -Items $weatherItems)) { $failures++ }

    Write-Host ''
    Write-BoxTitle -Title 'Windows Dark Theme / Transparency'
    Write-Host ''
    $personalizationItems = @(
        [pscustomobject]@{ Key='HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; Name='AppsUseLightTheme'; Value=0; CreateKey=$true },
        [pscustomobject]@{ Key='HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; Name='SystemUsesLightTheme'; Value=0; CreateKey=$true },
        [pscustomobject]@{ Key='HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; Name='EnableTransparency'; Value=0; CreateKey=$true }
    )
    if (-not (Invoke-RegistryItemsInline -Items $personalizationItems)) { $failures++ }

    Write-Host ''
    $refreshResult = Send-TaskbarOptimizeSettingRefresh
    if (-not $refreshResult.Ok) { $failures++ }
    Write-StatusLine -Ok $refreshResult.Ok -Text $refreshResult.Message -Warning:($refreshResult.PSObject.Properties.Name -contains 'Warning' -and [bool]$refreshResult.Warning)

    Write-StatusLine -Ok $true -Text 'Explorer was not restarted; taskbar changes may require sign-out or reboot to fully apply'

    Write-Host ''
    if ($failures -eq 0) {
        Write-Host 'OVERALL: SUCCESS - Taskbar Optimize completed.' -ForegroundColor Green
    } else {
        Write-Host ("OVERALL: FAILED/WARNING - {0} taskbar optimize step(s) reported a failure. Review the output above." -f $failures) -ForegroundColor Red
    }

    Write-Host ''
    if ($Auto) { return ($failures -eq 0) }

    Wait-ForEnterToContinue
}


function Join-QolRegistryKey {
    param(
        [Parameter(Mandatory=$true)][string]$Root,
        [string]$SubKey = ''
    )

    $cleanRoot = $Root.TrimEnd('\')
    if ([string]::IsNullOrWhiteSpace($SubKey)) { return $cleanRoot }
    return ($cleanRoot + '\' + $SubKey.TrimStart('\'))
}

function Invoke-QolSearchModeMenu {
    $selection = Invoke-Menu -Title 'QOL - Search Taskbar Mode' -Items @(
        'Hidden',
        'Icon',
        'Icon + label',
        'Box',
        'Back'
    )

    switch ($selection) {
        0 { return [pscustomobject]@{ Continue=$true; Label='Hidden'; UserMode=0; PolicyMode=0 } }
        1 { return [pscustomobject]@{ Continue=$true; Label='Icon'; UserMode=1; PolicyMode=1 } }
        2 { return [pscustomobject]@{ Continue=$true; Label='Icon + label'; UserMode=3; PolicyMode=2 } }
        3 { return [pscustomobject]@{ Continue=$true; Label='Box'; UserMode=2; PolicyMode=3 } }
        default { return [pscustomobject]@{ Continue=$false; Label='Back'; UserMode=1; PolicyMode=1 } }
    }
}


function Get-QolPerformanceOptionsVisualEffectCatalog {
    return @(
        [pscustomobject]@{ SubKey='AnimateMinMax'; DesiredValue=0; Label='Animate windows when minimizing and maximizing' },
        [pscustomobject]@{ SubKey='ComboBoxAnimation'; DesiredValue=0; Label='Slide open combo boxes' },
        [pscustomobject]@{ SubKey='ControlAnimations'; DesiredValue=0; Label='Animate controls and elements inside windows' },
        [pscustomobject]@{ SubKey='CursorShadow'; DesiredValue=0; Label='Show shadows under mouse pointer' },
        [pscustomobject]@{ SubKey='GradientCaptions'; DesiredValue=0; Label='Use gradient effect for window title bars' },
        [pscustomobject]@{ SubKey='DragFullWindows'; DesiredValue=0; Label='Show window contents while dragging' },
        [pscustomobject]@{ SubKey='DropShadow'; DesiredValue=0; Label='Show shadows under windows' },
        [pscustomobject]@{ SubKey='DWMAeroPeekEnabled'; DesiredValue=0; Label='Enable Peek' },
        [pscustomobject]@{ SubKey='DWMSaveThumbnailEnabled'; DesiredValue=0; Label='Save taskbar thumbnail previews' },
        [pscustomobject]@{ SubKey='FontSmoothing'; DesiredValue=1; Label='Smooth edges of screen fonts - kept enabled' },
        [pscustomobject]@{ SubKey='ListBoxSmoothScrolling'; DesiredValue=0; Label='Smooth-scroll list boxes' },
        [pscustomobject]@{ SubKey='ListviewAlphaSelect'; DesiredValue=0; Label='Show translucent selection rectangle' },
        [pscustomobject]@{ SubKey='ListviewShadow'; DesiredValue=0; Label='Use drop shadows for icon labels on the desktop' },
        [pscustomobject]@{ SubKey='MenuAnimation'; DesiredValue=0; Label='Fade or slide menus into view' },
        [pscustomobject]@{ SubKey='SelectionFade'; DesiredValue=0; Label='Fade out menu items after clicking' },
        [pscustomobject]@{ SubKey='TaskbarAnimations'; DesiredValue=0; Label='Animations in the taskbar' },
        [pscustomobject]@{ SubKey='ThumbnailsOrIcon'; DesiredValue=0; Label='Show thumbnails instead of icons' },
        [pscustomobject]@{ SubKey='TooltipAnimation'; DesiredValue=0; Label='Fade or slide ToolTips into view' },
        [pscustomobject]@{ SubKey='DWMEnabled'; DesiredValue=0; Label='Enable desktop composition - legacy visual effect' },
        [pscustomobject]@{ SubKey='TransparentGlass'; DesiredValue=0; Label='Enable transparent glass - legacy visual effect' },
        [pscustomobject]@{ SubKey='Themes'; DesiredValue=0; Label='Use visual styles on windows and buttons - legacy visual effect' }
    )
}

function Get-QolPerformanceOptionsUserRegistryItems {
    $items = @(
        [pscustomobject]@{ SubKey='Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'; Name='VisualFXSetting'; Value=3; Type='DWord'; CreateKey=$true; Description='Performance Options / Visual Effects: set Custom mode so individual checkboxes are honored' },

        [pscustomobject]@{ SubKey='Control Panel\Desktop\WindowMetrics'; Name='MinAnimate'; Value='0'; Type='String'; CreateKey=$true; Description='Performance Options: uncheck Animate windows when minimizing and maximizing' },
        [pscustomobject]@{ SubKey='Control Panel\Desktop'; Name='DragFullWindows'; Value='0'; Type='String'; CreateKey=$true; Description='Performance Options: uncheck Show window contents while dragging' },
        [pscustomobject]@{ SubKey='Control Panel\Desktop'; Name='FontSmoothing'; Value='2'; Type='String'; CreateKey=$true; Description='Performance Options: keep Smooth edges of screen fonts enabled' },
        [pscustomobject]@{ SubKey='Control Panel\Desktop'; Name='FontSmoothingType'; Value=2; Type='DWord'; CreateKey=$true; Description='Performance Options: keep ClearType font smoothing enabled' },
        [pscustomobject]@{ SubKey='Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name='TaskbarAnimations'; Value=0; Type='DWord'; CreateKey=$true; Description='Performance Options: uncheck Animations in the taskbar' },
        [pscustomobject]@{ SubKey='Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name='ListviewAlphaSelect'; Value=0; Type='DWord'; CreateKey=$true; Description='Performance Options: uncheck Show translucent selection rectangle' },
        [pscustomobject]@{ SubKey='Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name='ListviewShadow'; Value=0; Type='DWord'; CreateKey=$true; Description='Performance Options: uncheck Use drop shadows for icon labels on the desktop' },
        [pscustomobject]@{ SubKey='Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name='IconsOnly'; Value=1; Type='DWord'; CreateKey=$true; Description='Performance Options: uncheck Show thumbnails instead of icons' },
        [pscustomobject]@{ SubKey='Software\Microsoft\Windows\DWM'; Name='EnableAeroPeek'; Value=0; Type='DWord'; CreateKey=$true; Description='Performance Options: uncheck Enable Peek' },
        [pscustomobject]@{ SubKey='Software\Microsoft\Windows\DWM'; Name='AlwaysHibernateThumbnails'; Value=0; Type='DWord'; CreateKey=$true; Description='Performance Options: uncheck Save taskbar thumbnail previews' }
    )

    foreach ($effect in @(Get-QolPerformanceOptionsVisualEffectCatalog)) {
        $effectSubKey = 'Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects\' + $effect.SubKey
        $stateText = if ([int]$effect.DesiredValue -eq 1) { 'check/enable' } else { 'uncheck/disable' }

        $items += [pscustomobject]@{ SubKey=$effectSubKey; Name='DefaultValue'; Value=[int]$effect.DesiredValue; Type='DWord'; CreateKey=$true; Description=("Performance Options default: {0} {1}" -f $stateText, $effect.Label) }
        $items += [pscustomobject]@{ SubKey=$effectSubKey; Name='DefaultApplied'; Value=1; Type='DWord'; CreateKey=$true; Description=("Performance Options apply-state: mark default applied for {0}" -f $effect.Label) }
        $items += [pscustomobject]@{ SubKey=$effectSubKey; Name='DefaultByAlphaTest'; Value=[int]$effect.DesiredValue; Type='DWord'; CreateKey=$true; Description=("Performance Options alpha-test default: {0} {1}" -f $stateText, $effect.Label) }
    }

    $items += [pscustomobject]@{ SubKey='Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects\FontSmoothing'; Name='NoApplyDefault'; Type='Delete'; CreateKey=$true; Description='Performance Options font smoothing: remove blocker so the enabled font-smoothing default can apply' }

    return $items
}

function Get-QolPerformanceOptionsMachineDefaultRegistryItems {
    $items = @()
    foreach ($effect in @(Get-QolPerformanceOptionsVisualEffectCatalog)) {
        $effectKey = 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects\' + $effect.SubKey
        $stateText = if ([int]$effect.DesiredValue -eq 1) { 'enable/check' } else { 'disable/uncheck' }
        $items += [pscustomobject]@{ Key=$effectKey; Name='DefaultValue'; Value=[int]$effect.DesiredValue; Type='DWord'; CreateKey=$true; Description=("Machine default Performance Options: {0} {1}" -f $stateText, $effect.Label) }
        $items += [pscustomobject]@{ Key=$effectKey; Name='DefaultByAlphaTest'; Value=[int]$effect.DesiredValue; Type='DWord'; CreateKey=$true; Description=("Machine alpha-test Performance Options default: {0} {1}" -f $stateText, $effect.Label) }
    }
    return $items
}

function Get-QolWindowsBuildInfo {
    try {
        $cv = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
        [pscustomobject]@{
            Build          = [int]$cv.CurrentBuildNumber
            UBR            = if ($null -ne $cv.UBR) { [int]$cv.UBR } else { 0 }
            DisplayVersion = [string]$cv.DisplayVersion
            ProductName    = [string]$cv.ProductName
        }
    } catch {
        [pscustomobject]@{
            Build          = [Environment]::OSVersion.Version.Build
            UBR            = 0
            DisplayVersion = ''
            ProductName    = ''
        }
    }
}

function Ensure-QolNativeMethods {
    if ('QolNativeMethods' -as [type]) { return $true }

    $source = @'
using System;
using System.Runtime.InteropServices;

public static class QolNativeMethods
{
    [StructLayout(LayoutKind.Sequential)]
    public struct ANIMATIONINFO
    {
        public UInt32 cbSize;
        public Int32 iMinAnimate;
    }

    public struct UInt32SpiResult
    {
        public bool Ok;
        public UInt32 Value;
        public UInt32 Error;
    }

    [DllImport("user32.dll", EntryPoint="SystemParametersInfo", SetLastError=true)]
    public static extern bool SystemParametersInfoUInt(UInt32 uiAction, UInt32 uiParam, IntPtr pvParam, UInt32 fWinIni);

    [DllImport("user32.dll", EntryPoint="SystemParametersInfo", SetLastError=true)]
    public static extern bool SystemParametersInfoUIntRef(UInt32 uiAction, UInt32 uiParam, ref UInt32 pvParam, UInt32 fWinIni);

    [DllImport("user32.dll", EntryPoint="SystemParametersInfo", SetLastError=true)]
    public static extern bool SystemParametersInfoAnimation(UInt32 uiAction, UInt32 uiParam, ref ANIMATIONINFO pvParam, UInt32 fWinIni);

    public static UInt32SpiResult ReadSystemParameterUInt32(UInt32 uiAction)
    {
        UInt32SpiResult result = new UInt32SpiResult();
        IntPtr buffer = IntPtr.Zero;

        try
        {
            buffer = Marshal.AllocHGlobal(4);
            Marshal.WriteInt32(buffer, 0);
            result.Ok = SystemParametersInfoUInt(uiAction, 0, buffer, 0);
            result.Value = unchecked((UInt32)Marshal.ReadInt32(buffer));
            if (!result.Ok)
            {
                result.Error = unchecked((UInt32)Marshal.GetLastWin32Error());
            }
        }
        finally
        {
            if (buffer != IntPtr.Zero)
            {
                Marshal.FreeHGlobal(buffer);
            }
        }

        return result;
    }

    public static UInt32SpiResult SetSystemParameterUInt32ByPointer(UInt32 uiAction, UInt32 value, UInt32 flags)
    {
        UInt32SpiResult result = new UInt32SpiResult();
        IntPtr buffer = IntPtr.Zero;

        try
        {
            buffer = Marshal.AllocHGlobal(4);
            Marshal.WriteInt32(buffer, unchecked((Int32)value));
            result.Ok = SystemParametersInfoUInt(uiAction, 0, buffer, flags);
            result.Value = unchecked((UInt32)Marshal.ReadInt32(buffer));
            if (!result.Ok)
            {
                result.Error = unchecked((UInt32)Marshal.GetLastWin32Error());
            }
        }
        finally
        {
            if (buffer != IntPtr.Zero)
            {
                Marshal.FreeHGlobal(buffer);
            }
        }

        return result;
    }

    [DllImport("user32.dll", SetLastError=true)]
    public static extern bool SetCaretBlinkTime(UInt32 uMSeconds);

    [DllImport("user32.dll", SetLastError=true)]
    public static extern UInt32 GetCaretBlinkTime();
}
'@

    try {
        Add-Type -TypeDefinition $source -ErrorAction Stop
        return $true
    }
    catch {
        Write-StatusLine -Ok $false -Text "could not load SystemParametersInfo helper: $($_.Exception.Message)"
        return $false
    }
}

function Read-QolSystemParameterUInt32 {
    param(
        [Parameter(Mandatory=$true)][uint32]$Action,
        [Parameter(Mandatory=$true)][string]$Name
    )

    try {
        $native = [QolNativeMethods]::ReadSystemParameterUInt32($Action)
        if (-not $native.Ok) {
            return [pscustomobject]@{ Ok=$false; Value=$null; Message=("{0} failed; Win32 error {1}" -f $Name, [uint32]$native.Error) }
        }
        return [pscustomobject]@{ Ok=$true; Value=[uint32]$native.Value; Message=("{0} returned {1}" -f $Name, [uint32]$native.Value) }
    }
    catch {
        return [pscustomobject]@{ Ok=$false; Value=$null; Message=("{0} failed: {1}" -f $Name, $_.Exception.Message) }
    }
}

function Read-QolSystemParameterBool {
    param(
        [Parameter(Mandatory=$true)][uint32]$Action,
        [Parameter(Mandatory=$true)][string]$Name
    )

    $result = Read-QolSystemParameterUInt32 -Action $Action -Name $Name
    if (-not $result.Ok) { return $result }
    return [pscustomobject]@{ Ok=$true; Value=([uint32]$result.Value -ne 0); RawValue=[uint32]$result.Value; Message=("{0} returned {1}" -f $Name, ([uint32]$result.Value -ne 0)) }
}

function Set-QolCurrentUserCursorDword {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][uint32]$Value
    )

    try {
        $path = 'HKCU:\Control Panel\Cursors'
        if (-not (Test-Path -LiteralPath $path)) {
            New-Item -Path 'HKCU:\Control Panel' -Name 'Cursors' -Force | Out-Null
        }
        New-ItemProperty -LiteralPath $path -Name $Name -Value ([int]$Value) -PropertyType DWord -Force | Out-Null
        return [pscustomobject]@{ Ok=$true; Message=("HKCU\Control Panel\Cursors\{0} set to {1}" -f $Name, [uint32]$Value) }
    }
    catch {
        return [pscustomobject]@{ Ok=$false; Message=("HKCU\Control Panel\Cursors\{0} write failed: {1}" -f $Name, $_.Exception.Message) }
    }
}

function Confirm-QolCurrentUserCursorDword {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][uint32]$DesiredValue,
        [Parameter(Mandatory=$true)][string]$Description
    )

    try {
        $path = 'HKCU:\Control Panel\Cursors'
        $item = Get-ItemProperty -LiteralPath $path -Name $Name -ErrorAction Stop
        $raw = $item.$Name
        $actual = [uint32]$raw
        if ($actual -eq [uint32]$DesiredValue) {
            Write-StatusLine -Ok $true -Text ("{0}; verified HKCU\Control Panel\Cursors\{1}={2}" -f $Description, $Name, [uint32]$DesiredValue)
            return $true
        }
        Write-StatusLine -Ok $false -Text ("{0} verification mismatch: HKCU\Control Panel\Cursors\{1} returned {2}, expected {3}" -f $Description, $Name, $actual, [uint32]$DesiredValue)
        return $false
    }
    catch {
        Write-StatusLine -Ok $false -Text ("{0} verification failed: HKCU\Control Panel\Cursors\{1} could not be read: {2}" -f $Description, $Name, $_.Exception.Message)
        return $false
    }
}

function Get-QolVisualizationParameterInfo {
    param([Parameter(Mandatory=$true)][string]$RegistryName)

    switch ($RegistryName) {
        'ContactVisualization' {
            return [pscustomobject]@{ RegistryName=$RegistryName; GetAction=[uint32]0x2018; VerifyName='SPI_GETCONTACTVISUALIZATION' }
        }
        'GestureVisualization' {
            return [pscustomobject]@{ RegistryName=$RegistryName; GetAction=[uint32]0x201A; VerifyName='SPI_GETGESTUREVISUALIZATION' }
        }
        'PenVisualization' {
            return [pscustomobject]@{ RegistryName=$RegistryName; GetAction=[uint32]0x201E; VerifyName='SPI_GETPENVISUALIZATION' }
        }
        default {
            return $null
        }
    }
}

function Confirm-QolVisualizationParameterOff {
    param(
        [Parameter(Mandatory=$true)][string]$RegistryName,
        [Parameter(Mandatory=$true)][string]$Description
    )

    $info = Get-QolVisualizationParameterInfo -RegistryName $RegistryName
    if ($null -eq $info) {
        Write-StatusLine -Ok $false -Text ("{0} verification failed: no SPI_GET mapping for HKCU\Control Panel\Cursors\{1}" -f $Description, $RegistryName)
        return $false
    }

    return (Confirm-QolSystemParameterUInt32 -GetAction ([uint32]$info.GetAction) -DesiredValue 0 -Description $Description -VerifyName $info.VerifyName)
}

function Confirm-QolSystemParameterUInt32 {
    param(
        [Parameter(Mandatory=$true)][uint32]$GetAction,
        [Parameter(Mandatory=$true)][uint32]$DesiredValue,
        [Parameter(Mandatory=$true)][string]$Description,
        [Parameter(Mandatory=$true)][string]$VerifyName
    )

    $verify = Read-QolSystemParameterUInt32 -Action $GetAction -Name $VerifyName
    if (-not $verify.Ok) {
        Write-StatusLine -Ok $false -Text ("{0} applied but verification failed: {1}" -f $Description, $verify.Message)
        return $false
    }

    if ([uint32]$verify.Value -ne [uint32]$DesiredValue) {
        Write-StatusLine -Ok $false -Text ("{0} verification mismatch: {1} returned {2}, expected {3}" -f $Description, $VerifyName, [uint32]$verify.Value, [uint32]$DesiredValue)
        return $false
    }

    Write-StatusLine -Ok $true -Text ("{0}; verified {1}={2}" -f $Description, $VerifyName, [uint32]$DesiredValue)
    return $true
}

function Confirm-QolMouseTrailsDisabled {
    param([Parameter(Mandatory=$true)][string]$Description)

    $verify = Read-QolSystemParameterUInt32 -Action 0x005E -Name 'SPI_GETMOUSETRAILS'
    if (-not $verify.Ok) {
        Write-StatusLine -Ok $false -Text ("{0} applied but verification failed: {1}" -f $Description, $verify.Message)
        return $false
    }

    if ([uint32]$verify.Value -le 1) {
        Write-StatusLine -Ok $true -Text ("{0}; verified SPI_GETMOUSETRAILS={1} (disabled)" -f $Description, [uint32]$verify.Value)
        return $true
    }

    Write-StatusLine -Ok $false -Text ("{0} verification mismatch: SPI_GETMOUSETRAILS returned {1}, expected 0 or 1 disabled" -f $Description, [uint32]$verify.Value)
    return $false
}

function Invoke-QolMouseTrailsOff {
    if (-not (Invoke-QolSystemParameterUInt -Action 0x005D -Value 0 -Description 'disabled mouse pointer trails via SPI_SETMOUSETRAILS')) { return $false }
    return (Confirm-QolMouseTrailsDisabled -Description 'disabled mouse pointer trails via SPI_SETMOUSETRAILS')
}

function Confirm-QolSystemParameterBool {
    param(
        [Parameter(Mandatory=$true)][uint32]$GetAction,
        [Parameter(Mandatory=$true)][bool]$DesiredValue,
        [Parameter(Mandatory=$true)][string]$Description,
        [Parameter(Mandatory=$true)][string]$VerifyName
    )

    $verify = Read-QolSystemParameterBool -Action $GetAction -Name $VerifyName
    if (-not $verify.Ok) {
        Write-StatusLine -Ok $false -Text ("{0} applied but verification failed: {1}" -f $Description, $verify.Message)
        return $false
    }

    if ([bool]$verify.Value -ne [bool]$DesiredValue) {
        $raw = ''
        if ($verify.PSObject.Properties.Name -contains 'RawValue') { $raw = (" raw={0}" -f [uint32]$verify.RawValue) }
        Write-StatusLine -Ok $false -Text ("{0} verification mismatch: {1} returned {2}{3}, expected {4}" -f $Description, $VerifyName, [bool]$verify.Value, $raw, [bool]$DesiredValue)
        return $false
    }

    Write-StatusLine -Ok $true -Text ("{0}; verified {1}={2}" -f $Description, $VerifyName, [bool]$DesiredValue)
    return $true
}

function Invoke-QolSystemParameterUInt {
    param(
        [Parameter(Mandatory=$true)][uint32]$Action,
        [Parameter(Mandatory=$true)][uint32]$Value,
        [Parameter(Mandatory=$true)][string]$Description,
        [Parameter()][uint32]$VerifyAction = [uint32]::MaxValue,
        [Parameter()][string]$VerifyName = '',
        [switch]$VerifyAsBool
    )

    $flags = [uint32](0x01 -bor 0x02)
    try {
        $ok = [QolNativeMethods]::SystemParametersInfoUInt($Action, $Value, [IntPtr]::Zero, $flags)
        if ($ok) {
            if ($VerifyAction -ne [uint32]::MaxValue) {
                if ([string]::IsNullOrWhiteSpace($VerifyName)) { $VerifyName = ("SPI_GET 0x{0:X}" -f $VerifyAction) }
                if ($VerifyAsBool) {
                    return (Confirm-QolSystemParameterBool -GetAction $VerifyAction -DesiredValue ([bool]($Value -ne 0)) -Description $Description -VerifyName $VerifyName)
                }
                return (Confirm-QolSystemParameterUInt32 -GetAction $VerifyAction -DesiredValue $Value -Description $Description -VerifyName $VerifyName)
            }
            Write-StatusLine -Ok $true -Text $Description
            return $true
        }
        $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        Write-StatusLine -Ok $false -Text "$Description failed; Win32 error $err"
        return $false
    }
    catch {
        Write-StatusLine -Ok $false -Text "$Description failed: $($_.Exception.Message)"
        return $false
    }
}

function Invoke-QolSystemParameterBool {
    param(
        [Parameter(Mandatory=$true)][uint32]$Action,
        [Parameter(Mandatory=$true)][bool]$Value,
        [Parameter(Mandatory=$true)][string]$Description,
        [Parameter()][uint32]$VerifyAction = [uint32]::MaxValue,
        [Parameter()][string]$VerifyName = ''
    )

    $flags = [uint32](0x01 -bor 0x02)

    $pvParam = if ([bool]$Value) { [IntPtr]1 } else { [IntPtr]::Zero }

    try {
        $ok = [QolNativeMethods]::SystemParametersInfoUInt($Action, 0, $pvParam, $flags)
        if ($ok) {
            if ($VerifyAction -ne [uint32]::MaxValue) {
                if ([string]::IsNullOrWhiteSpace($VerifyName)) { $VerifyName = ("SPI_GET 0x{0:X}" -f $VerifyAction) }
                return (Confirm-QolSystemParameterBool -GetAction $VerifyAction -DesiredValue $Value -Description $Description -VerifyName $VerifyName)
            }
            Write-StatusLine -Ok $true -Text $Description
            return $true
        }
        $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        Write-StatusLine -Ok $false -Text "$Description failed; Win32 error $err"
        return $false
    }
    catch {
        Write-StatusLine -Ok $false -Text "$Description failed: $($_.Exception.Message)"
        return $false
    }
}

function Invoke-QolSystemParameterUIntPointer {
    param(
        [Parameter(Mandatory=$true)][uint32]$Action,
        [Parameter(Mandatory=$true)][uint32]$Value,
        [Parameter(Mandatory=$true)][string]$Description,
        [Parameter()][uint32]$VerifyAction = [uint32]::MaxValue,
        [Parameter()][string]$VerifyName = ''
    )

    $flags = [uint32](0x01 -bor 0x02)
    $buffer = [IntPtr]::Zero

    try {
        $buffer = [Runtime.InteropServices.Marshal]::AllocHGlobal(4)
        [Runtime.InteropServices.Marshal]::WriteInt32($buffer, [int]$Value)

        $ok = [QolNativeMethods]::SystemParametersInfoUInt($Action, 0, $buffer, $flags)
        if ($ok) {
            if ($VerifyAction -ne [uint32]::MaxValue) {
                if ([string]::IsNullOrWhiteSpace($VerifyName)) { $VerifyName = ("SPI_GET 0x{0:X}" -f $VerifyAction) }
                return (Confirm-QolSystemParameterUInt32 -GetAction $VerifyAction -DesiredValue $Value -Description $Description -VerifyName $VerifyName)
            }
            Write-StatusLine -Ok $true -Text $Description
            return $true
        }

        $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        Write-StatusLine -Ok $false -Text "$Description failed; Win32 error $err"
        return $false
    }
    catch {
        Write-StatusLine -Ok $false -Text "$Description failed: $($_.Exception.Message)"
        return $false
    }
    finally {
        if ($buffer -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::FreeHGlobal($buffer)
        }
    }
}

function Invoke-QolVisualizationParameterOff {
    param(
        [Parameter(Mandatory=$true)][uint32]$Action,
        [Parameter(Mandatory=$true)][string]$RegistryName,
        [Parameter(Mandatory=$true)][string]$Description
    )

    $flags = [uint32](0x01 -bor 0x02)

    try {
        $scalarOk = [QolNativeMethods]::SystemParametersInfoUInt($Action, 0, [IntPtr]::Zero, $flags)
        if ($scalarOk) {
            $reg = Set-QolCurrentUserCursorDword -Name $RegistryName -Value 0
            if (-not $reg.Ok) {
                Write-StatusLine -Ok $true -Warning -Text ("{0} applied via SystemParametersInfo scalar value, but HKCU reinforcement failed: {1}" -f $Description, $reg.Message)
            }

            if (Confirm-QolVisualizationParameterOff -RegistryName $RegistryName -Description $Description) {
                return $true
            }

            Write-StatusLine -Ok $true -Warning -Text ("{0}: scalar SET succeeded but live verification did not read 0; retrying documented pointer form" -f $Description)
        }
        else {
            $scalarErr = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
            Write-StatusLine -Ok $true -Warning -Text ("{0}: scalar SET form was not accepted; Win32 error {1}; retrying documented pointer form" -f $Description, $scalarErr)
        }

        $native = [QolNativeMethods]::SetSystemParameterUInt32ByPointer($Action, 0, $flags)
        if (-not $native.Ok) {
            Write-StatusLine -Ok $false -Text ("{0} failed; pointer fallback Win32 error {1}" -f $Description, [uint32]$native.Error)
            return $false
        }

        $reg = Set-QolCurrentUserCursorDword -Name $RegistryName -Value 0
        if (-not $reg.Ok) {
            Write-StatusLine -Ok $true -Warning -Text ("{0} applied via SystemParametersInfo pointer fallback, but HKCU reinforcement failed: {1}" -f $Description, $reg.Message)
        }

        return (Confirm-QolVisualizationParameterOff -RegistryName $RegistryName -Description $Description)
    }
    catch {
        Write-StatusLine -Ok $false -Text "$Description failed: $($_.Exception.Message)"
        return $false
    }
}

function Confirm-QolCaretBlinkOff {
    param([Parameter(Mandatory=$true)][string]$Description)

    try {
        $current = [QolNativeMethods]::GetCaretBlinkTime()
        if ([uint32]$current -eq [uint32]::MaxValue) {
            Write-StatusLine -Ok $true -Text ("{0}; verified GetCaretBlinkTime=INFINITE" -f $Description)
            return $true
        }
        Write-StatusLine -Ok $false -Text ("{0} verification mismatch: GetCaretBlinkTime returned {1}, expected INFINITE" -f $Description, [uint32]$current)
        return $false
    }
    catch {
        Write-StatusLine -Ok $false -Text ("{0} verification failed: {1}" -f $Description, $_.Exception.Message)
        return $false
    }
}

function Invoke-QolCaretBlinkOff {
    try {
        $infinite = [uint32]::MaxValue
        $ok = [QolNativeMethods]::SetCaretBlinkTime($infinite)
        if ($ok) {
            return (Confirm-QolCaretBlinkOff -Description 'disabled text caret blinking via SetCaretBlinkTime(INFINITE)')
        }

        $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        Write-StatusLine -Ok $false -Text "text caret blink disable failed; Win32 error $err"
        return $false
    }
    catch {
        Write-StatusLine -Ok $false -Text "text caret blink disable failed: $($_.Exception.Message)"
        return $false
    }
}

function Confirm-QolWindowAnimationState {
    param([Parameter(Mandatory=$true)][int]$DesiredValue)

    try {
        $verifyInfo = New-Object QolNativeMethods+ANIMATIONINFO
        $verifyInfo.cbSize = [uint32][Runtime.InteropServices.Marshal]::SizeOf($verifyInfo)
        $verifyInfo.iMinAnimate = -1
        $ok = [QolNativeMethods]::SystemParametersInfoAnimation(0x0048, $verifyInfo.cbSize, [ref]$verifyInfo, 0)
        if (-not $ok) {
            $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
            Write-StatusLine -Ok $false -Text "window animation verification failed: SPI_GETANIMATION failed; Win32 error $err"
            return $false
        }
        if ([int]$verifyInfo.iMinAnimate -ne [int]$DesiredValue) {
            Write-StatusLine -Ok $false -Text ("window animation verification mismatch: SPI_GETANIMATION returned iMinAnimate={0}, expected {1}" -f [int]$verifyInfo.iMinAnimate, [int]$DesiredValue)
            return $false
        }
        Write-StatusLine -Ok $true -Text ("disabled window minimize/maximize animations via SystemParametersInfo; verified SPI_GETANIMATION iMinAnimate={0}" -f [int]$DesiredValue)
        return $true
    }
    catch {
        Write-StatusLine -Ok $false -Text "window animation verification failed: $($_.Exception.Message)"
        return $false
    }
}

function Invoke-QolWindowAnimationOff {
    $flags = [uint32](0x01 -bor 0x02)
    try {
        $animationInfo = New-Object QolNativeMethods+ANIMATIONINFO
        $animationInfo.cbSize = [uint32][Runtime.InteropServices.Marshal]::SizeOf($animationInfo)
        $animationInfo.iMinAnimate = 0
        $ok = [QolNativeMethods]::SystemParametersInfoAnimation(0x0049, $animationInfo.cbSize, [ref]$animationInfo, $flags)
        if ($ok) {
            return (Confirm-QolWindowAnimationState -DesiredValue 0)
        }
        $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        Write-StatusLine -Ok $false -Text "window animation disable failed; Win32 error $err"
        return $false
    }
    catch {
        Write-StatusLine -Ok $false -Text "window animation disable failed: $($_.Exception.Message)"
        return $false
    }
}

function Test-QolSystemParametersApplied {
    $failed = 0

    $uintChecks = @(
        [pscustomobject]@{ GetAction=0x006A; Desired=0; Description='final live verification: MenuShowDelay'; VerifyName='SPI_GETMENUSHOWDELAY' },
        [pscustomobject]@{ GetAction=0x0066; Desired=10; Description='final live verification: MouseHoverTime'; VerifyName='SPI_GETMOUSEHOVERTIME' }
    )

    foreach ($check in $uintChecks) {
        if (-not (Confirm-QolSystemParameterUInt32 -GetAction ([uint32]$check.GetAction) -DesiredValue ([uint32]$check.Desired) -Description $check.Description -VerifyName $check.VerifyName)) { $failed++ }
    }

    if (-not (Confirm-QolVisualizationParameterOff -RegistryName 'ContactVisualization' -Description 'final live verification: touch contact visualization')) { $failed++ }
    if (-not (Confirm-QolVisualizationParameterOff -RegistryName 'GestureVisualization' -Description 'final live verification: gesture visualization')) { $failed++ }
    if (-not (Confirm-QolVisualizationParameterOff -RegistryName 'PenVisualization' -Description 'final live verification: pen visualization')) { $failed++ }

    $boolChecks = @(
        [pscustomobject]@{ GetAction=0x0026; Desired=$false; Description='final live verification: Show window contents while dragging'; VerifyName='SPI_GETDRAGFULLWINDOWS' },
        [pscustomobject]@{ GetAction=0x004A; Desired=$true; Description='final live verification: Smooth edges of screen fonts'; VerifyName='SPI_GETFONTSMOOTHING' },
        [pscustomobject]@{ GetAction=0x1042; Desired=$false; Description='final live verification: client-area animations / Windows 11 Animation effects'; VerifyName='SPI_GETCLIENTAREAANIMATION' },
        [pscustomobject]@{ GetAction=0x1002; Desired=$false; Description='final live verification: menu animation'; VerifyName='SPI_GETMENUANIMATION' },
        [pscustomobject]@{ GetAction=0x1012; Desired=$false; Description='final live verification: menu fade'; VerifyName='SPI_GETMENUFADE' },
        [pscustomobject]@{ GetAction=0x1016; Desired=$false; Description='final live verification: tooltip animation'; VerifyName='SPI_GETTOOLTIPANIMATION' },
        [pscustomobject]@{ GetAction=0x1018; Desired=$false; Description='final live verification: tooltip fade'; VerifyName='SPI_GETTOOLTIPFADE' },
        [pscustomobject]@{ GetAction=0x1004; Desired=$false; Description='final live verification: combo-box animation'; VerifyName='SPI_GETCOMBOBOXANIMATION' },
        [pscustomobject]@{ GetAction=0x1008; Desired=$false; Description='final live verification: gradient captions / gradient window title bars'; VerifyName='SPI_GETGRADIENTCAPTIONS' },
        [pscustomobject]@{ GetAction=0x1014; Desired=$false; Description='final live verification: selection fade / fade-out menu items'; VerifyName='SPI_GETSELECTIONFADE' },
        [pscustomobject]@{ GetAction=0x1006; Desired=$false; Description='final live verification: listbox smooth scrolling'; VerifyName='SPI_GETLISTBOXSMOOTHSCROLLING' },
        [pscustomobject]@{ GetAction=0x101A; Desired=$false; Description='final live verification: mouse pointer shadow'; VerifyName='SPI_GETCURSORSHADOW' },
        [pscustomobject]@{ GetAction=0x1024; Desired=$false; Description='final live verification: window shadows'; VerifyName='SPI_GETDROPSHADOW' },
        [pscustomobject]@{ GetAction=0x103E; Desired=$false; Description='final live verification: UI effects master switch'; VerifyName='SPI_GETUIEFFECTS' },
        [pscustomobject]@{ GetAction=0x100E; Desired=$false; Description='final live verification: hot-tracking disabled'; VerifyName='SPI_GETHOTTRACKING' }
    )

    foreach ($check in $boolChecks) {
        if (-not (Confirm-QolSystemParameterBool -GetAction ([uint32]$check.GetAction) -DesiredValue ([bool]$check.Desired) -Description $check.Description -VerifyName $check.VerifyName)) { $failed++ }
    }

    if (-not (Confirm-QolMouseTrailsDisabled -Description 'final live verification: mouse pointer trails disabled')) { $failed++ }
    if (-not (Confirm-QolCaretBlinkOff -Description 'final live verification: text caret blinking disabled')) { $failed++ }
    if (-not (Confirm-QolWindowAnimationState -DesiredValue 0)) { $failed++ }

    return ($failed -eq 0)
}

function Invoke-QolSystemParameters {
    if (-not (Ensure-QolNativeMethods)) { return $false }

    $failed = 0
    if (-not (Invoke-QolSystemParameterUInt -Action 0x006B -Value 0 -Description 'set MenuShowDelay to 0 via SystemParametersInfo' -VerifyAction 0x006A -VerifyName 'SPI_GETMENUSHOWDELAY')) { $failed++ }
    if (-not (Invoke-QolSystemParameterUInt -Action 0x0067 -Value 10 -Description 'set MouseHoverTime to 10 via SystemParametersInfo' -VerifyAction 0x0066 -VerifyName 'SPI_GETMOUSEHOVERTIME')) { $failed++ }
    if (-not (Invoke-QolSystemParameterUInt -Action 0x0025 -Value 0 -Description 'disabled Show window contents while dragging via SystemParametersInfo' -VerifyAction 0x0026 -VerifyName 'SPI_GETDRAGFULLWINDOWS' -VerifyAsBool)) { $failed++ }
    if (-not (Invoke-QolSystemParameterUInt -Action 0x004B -Value 1 -Description 'kept Smooth edges of screen fonts enabled via SystemParametersInfo' -VerifyAction 0x004A -VerifyName 'SPI_GETFONTSMOOTHING' -VerifyAsBool)) { $failed++ }
    if (-not (Invoke-QolMouseTrailsOff)) { $failed++ }

    if (-not (Invoke-QolVisualizationParameterOff -Action 0x2019 -RegistryName 'ContactVisualization' -Description 'disabled touch contact visualization via SPI_SETCONTACTVISUALIZATION')) { $failed++ }
    if (-not (Invoke-QolVisualizationParameterOff -Action 0x201B -RegistryName 'GestureVisualization' -Description 'disabled gesture visualization via SPI_SETGESTUREVISUALIZATION')) { $failed++ }
    if (-not (Invoke-QolVisualizationParameterOff -Action 0x201F -RegistryName 'PenVisualization' -Description 'disabled pen visualization via SPI_SETPENVISUALIZATION')) { $failed++ }

    $offSettings = @(
        [pscustomobject]@{ SetAction=0x1043; GetAction=0x1042; VerifyName='SPI_GETCLIENTAREAANIMATION'; Description='disabled client-area animations / Windows 11 Animation effects' },

        [pscustomobject]@{ SetAction=0x1003; GetAction=0x1002; VerifyName='SPI_GETMENUANIMATION'; Description='disabled menu animation' },
        [pscustomobject]@{ SetAction=0x1013; GetAction=0x1012; VerifyName='SPI_GETMENUFADE'; Description='disabled menu fade' },
        [pscustomobject]@{ SetAction=0x1017; GetAction=0x1016; VerifyName='SPI_GETTOOLTIPANIMATION'; Description='disabled tooltip animation' },
        [pscustomobject]@{ SetAction=0x1019; GetAction=0x1018; VerifyName='SPI_GETTOOLTIPFADE'; Description='disabled tooltip fade' },
        [pscustomobject]@{ SetAction=0x1005; GetAction=0x1004; VerifyName='SPI_GETCOMBOBOXANIMATION'; Description='disabled combo-box animation' },
        [pscustomobject]@{ SetAction=0x1009; GetAction=0x1008; VerifyName='SPI_GETGRADIENTCAPTIONS'; Description='disabled gradient captions / gradient window title bars' },
        [pscustomobject]@{ SetAction=0x1015; GetAction=0x1014; VerifyName='SPI_GETSELECTIONFADE'; Description='disabled selection fade / fade-out menu items' },
        [pscustomobject]@{ SetAction=0x1007; GetAction=0x1006; VerifyName='SPI_GETLISTBOXSMOOTHSCROLLING'; Description='disabled listbox smooth scrolling' },
        [pscustomobject]@{ SetAction=0x101B; GetAction=0x101A; VerifyName='SPI_GETCURSORSHADOW'; Description='disabled mouse pointer shadow' },
        [pscustomobject]@{ SetAction=0x1025; GetAction=0x1024; VerifyName='SPI_GETDROPSHADOW'; Description='disabled window shadows' },
        [pscustomobject]@{ SetAction=0x103F; GetAction=0x103E; VerifyName='SPI_GETUIEFFECTS'; Description='disabled UI effects master switch' }
    )

    foreach ($setting in $offSettings) {
        if (-not (Invoke-QolSystemParameterBool -Action ([uint32]$setting.SetAction) -Value $false -Description $setting.Description -VerifyAction ([uint32]$setting.GetAction) -VerifyName $setting.VerifyName)) { $failed++ }
    }

    if (-not (Invoke-QolSystemParameterBool -Action 0x100F -Value $false -Description 'disabled hot-tracking via SPI_SETHOTTRACKING' -VerifyAction 0x100E -VerifyName 'SPI_GETHOTTRACKING')) { $failed++ }
    if (-not (Invoke-QolCaretBlinkOff)) { $failed++ }

    if (-not (Invoke-QolWindowAnimationOff)) { $failed++ }

    Write-Host ''
    Write-Host 'Running final live SPI_GET verification sweep for the current interactive session...' -ForegroundColor Cyan
    if (-not (Test-QolSystemParametersApplied)) { $failed++ }

    return ($failed -eq 0)
}

function Get-QolUserRegistryItems {
    param([Parameter(Mandatory=$true)][int]$SearchUserMode)

    $items = @(
        [pscustomobject]@{ SubKey='Control Panel\Accessibility\StickyKeys'; Name='Flags'; Value='506'; Type='String'; CreateKey=$true; Description='Disable Sticky Keys shortcut popup' },
        [pscustomobject]@{ SubKey='Control Panel\Accessibility\Keyboard Response'; Name='Flags'; Value='2'; Type='String'; CreateKey=$true; Description='Disable Filter Keys shortcut popup' },
        [pscustomobject]@{ SubKey='Control Panel\Accessibility\MouseKeys'; Name='Flags'; Value='62'; Type='String'; CreateKey=$true; Description='Disable Mouse Keys shortcut' },
        [pscustomobject]@{ SubKey='Control Panel\Accessibility\HighContrast'; Name='Flags'; Value='4218'; Type='String'; CreateKey=$true; Description='Disable High Contrast shortcut' },
        [pscustomobject]@{ SubKey='Control Panel\Desktop'; Name='MenuShowDelay'; Value='0'; Type='String'; CreateKey=$true; Description='Menu show delay -> 0' },
        [pscustomobject]@{ SubKey='Control Panel\Mouse'; Name='MouseHoverTime'; Value='10'; Type='String'; CreateKey=$true; Description='Mouse hover time -> 10' },
        [pscustomobject]@{ SubKey='Control Panel\Mouse'; Name='MouseSpeed'; Value='0'; Type='String'; CreateKey=$true; Description='Reinforce QOL: disable mouse acceleration speed flag for this hive' },
        [pscustomobject]@{ SubKey='Control Panel\Mouse'; Name='MouseThreshold1'; Value='0'; Type='String'; CreateKey=$true; Description='Reinforce QOL: disable mouse acceleration threshold 1 for this hive' },
        [pscustomobject]@{ SubKey='Control Panel\Mouse'; Name='MouseThreshold2'; Value='0'; Type='String'; CreateKey=$true; Description='Reinforce QOL: disable mouse acceleration threshold 2 for this hive' },
        [pscustomobject]@{ SubKey='Control Panel\Mouse'; Name='MouseTrails'; Value='0'; Type='String'; CreateKey=$true; Description='Disable mouse pointer trails for this hive' },
        [pscustomobject]@{ SubKey='Control Panel\Desktop'; Name='CursorBlinkRate'; Value='-1'; Type='String'; CreateKey=$true; Description='Disable text caret blinking for this hive' },
        [pscustomobject]@{ SubKey='Control Panel\Desktop'; Name='CaretTimeout'; Value=0; Type='DWord'; CreateKey=$true; Description='Set text caret blink timeout to immediate stop for this hive' },
        [pscustomobject]@{ SubKey='Control Panel\Cursors'; Name='ContactVisualization'; Value=0; Type='DWord'; CreateKey=$true; Description='Disable touch contact visualization for this hive' },
        [pscustomobject]@{ SubKey='Control Panel\Cursors'; Name='GestureVisualization'; Value=0; Type='DWord'; CreateKey=$true; Description='Disable gesture visualization for this hive' },
        [pscustomobject]@{ SubKey='Control Panel\Cursors'; Name='PenVisualization'; Value=0; Type='DWord'; CreateKey=$true; Description='Disable pen visualization for this hive' },
        [pscustomobject]@{ SubKey='Control Panel\Accessibility'; Name='DynamicScrollbars'; Value=0; Type='DWord'; CreateKey=$true; Description='Always show scrollbars: disable auto-hide / fade-in scrollbar behavior' },
        [pscustomobject]@{ SubKey='Software\Microsoft\Wisp\Touch'; Name='Bouncing'; Value=0; Type='DWord'; CreateKey=$true; Description='Disable touch-screen overscroll bounce animation' },
        [pscustomobject]@{ SubKey='Software\Microsoft\Office\16.0\Common\Graphics'; Name='DisableAnimations'; Value=1; Type='DWord'; CreateKey=$true; Description='Disable Microsoft Office / Microsoft 365 app animations' }
    )

    $items += @(Get-QolPerformanceOptionsUserRegistryItems)
    $items += @(
        [pscustomobject]@{ SubKey='Software\Policies\Microsoft\OneDrive'; Name='DisablePersonalSync'; Value=1; Type='DWord'; CreateKey=$true; Description='OneDrive full disable: block personal OneDrive sync for this hive' },
        [pscustomobject]@{ SubKey='Software\Policies\Microsoft\OneDrive'; Name='EnableAutoStart'; Value=0; Type='DWord'; CreateKey=$true; Description='OneDrive full disable: policy-disable OneDrive automatic start for this hive' },
        [pscustomobject]@{ SubKey='Software\Policies\Microsoft\OneDrive'; Name='DisableFREAnimation'; Value=1; Type='DWord'; CreateKey=$true; Description='OneDrive full disable: suppress OneDrive setup first-run animation for this hive' },
        [pscustomobject]@{ SubKey='Software\Microsoft\Windows\CurrentVersion\Run'; Name='OneDrive'; Type='Delete'; Description='OneDrive full disable: remove per-user OneDrive Run startup entry' },
        [pscustomobject]@{ SubKey='Software\Microsoft\Windows\CurrentVersion\Run'; Name='OneDriveSetup'; Type='Delete'; Description='OneDrive full disable: remove per-user OneDrive setup Run startup entry' },
        [pscustomobject]@{ SubKey='Software\Microsoft\Windows\CurrentVersion\Run'; Name='Microsoft OneDrive'; Type='Delete'; Description='OneDrive full disable: remove alternate per-user Microsoft OneDrive Run startup entry' },
        [pscustomobject]@{ SubKey='Software\Microsoft\Windows\CurrentVersion\RunOnce'; Name='OneDrive'; Type='Delete'; Description='OneDrive full disable: remove per-user OneDrive RunOnce startup entry' },
        [pscustomobject]@{ SubKey='Software\Microsoft\Windows\CurrentVersion\RunOnce'; Name='OneDriveSetup'; Type='Delete'; Description='OneDrive full disable: remove per-user OneDrive setup RunOnce startup entry' },
        [pscustomobject]@{ SubKey='Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'; Name='OneDrive'; Type='Delete'; Description='OneDrive full disable: remove StartupApproved OneDrive marker for this hive' },
        [pscustomobject]@{ SubKey='Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'; Name='OneDriveSetup'; Type='Delete'; Description='OneDrive full disable: remove StartupApproved OneDrive setup marker for this hive' },
        [pscustomobject]@{ SubKey='Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'; Name='Microsoft OneDrive'; Type='Delete'; Description='OneDrive full disable: remove alternate StartupApproved Microsoft OneDrive marker for this hive' },
        [pscustomobject]@{ SubKey='Software\Classes\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}'; Name='System.IsPinnedToNameSpaceTree'; Value=0; Type='DWord'; CreateKey=$true; Description='OneDrive full disable: hide OneDrive Explorer namespace for this hive' },
        [pscustomobject]@{ SubKey='Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32'; Value=''; Type='DefaultString'; CreateKey=$true; Description='Restore full classic Windows 11 right-click context menu for this hive' },
        [pscustomobject]@{ SubKey='Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name='HideFileExt'; Value=0; Type='DWord'; CreateKey=$true; Description='Show file extensions' },
        [pscustomobject]@{ SubKey='Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name='Hidden'; Value=1; Type='DWord'; CreateKey=$true; Description='Show hidden files' },
        [pscustomobject]@{ SubKey='Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name='ShowSuperHidden'; Value=1; Type='DWord'; CreateKey=$true; Description='Show protected OS files' },
        [pscustomobject]@{ SubKey='Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name='Start_TrackProgs'; Value=0; Type='DWord'; CreateKey=$true; Description='Disable app launch tracking / most-used apps' },
        [pscustomobject]@{ SubKey='Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name='Start_TrackDocs'; Value=0; Type='DWord'; CreateKey=$true; Description='Disable recently opened items tracking' },
        [pscustomobject]@{ SubKey='Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name='Start_NotifyNewApps'; Value=0; Type='DWord'; CreateKey=$true; Description='Disable recently added apps badge/list' },
        [pscustomobject]@{ SubKey='Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name='Start_IrisRecommendations'; Value=0; Type='DWord'; CreateKey=$true; Description='Disable Start recommendations' },
        [pscustomobject]@{ SubKey='Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name='Start_Recommendations'; Value=0; Type='DWord'; CreateKey=$true; Description='Disable Start recommendations fallback value' },
        [pscustomobject]@{ SubKey='Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name='Start_AccountNotifications'; Value=0; Type='DWord'; CreateKey=$true; Description='Disable Start account/recommendation notifications' },
        [pscustomobject]@{ SubKey='Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name='TaskbarFlashing'; Value=0; Type='DWord'; CreateKey=$true; Description='Disable Taskbar flashing' },
        [pscustomobject]@{ SubKey='Control Panel\Desktop'; Name='ForegroundFlashCount'; Value=0; Type='DWord'; CreateKey=$true; Description='Reinforce QOL: suppress foreground/taskbar flashing count' },
        [pscustomobject]@{ SubKey='Control Panel\Desktop'; Name='ForegroundLockTimeout'; Value=0; Type='DWord'; CreateKey=$true; Description='Reinforce QOL: suppress foreground/taskbar flashing timeout' },
        [pscustomobject]@{ SubKey='Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name='ShowCopilotButton'; Value=0; Type='DWord'; CreateKey=$true; Description='Disable Copilot taskbar affordance' },
        [pscustomobject]@{ SubKey='Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name='TaskbarAnimations'; Value=0; Type='DWord'; CreateKey=$true; Description='Disable taskbar animations' },
        [pscustomobject]@{ SubKey='Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name='ListviewAlphaSelect'; Value=0; Type='DWord'; CreateKey=$true; Description='Disable translucent Explorer/list-view selection rectangle' },
        [pscustomobject]@{ SubKey='Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name='ListviewShadow'; Value=0; Type='DWord'; CreateKey=$true; Description='Disable desktop icon-label shadows' },
        [pscustomobject]@{ SubKey='Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name='ShowTypeOverlay'; Value=0; Type='DWord'; CreateKey=$true; Description='Disable file-type overlay on thumbnails' },
        [pscustomobject]@{ SubKey='Software\Microsoft\Windows\CurrentVersion\Search'; Name='SearchboxTaskbarMode'; Value=$SearchUserMode; Type='DWord'; CreateKey=$true; Description='Set Search taskbar mode' },
        [pscustomobject]@{ SubKey='Software\Microsoft\Windows\CurrentVersion\Explorer'; Name='LaunchTo'; Value=1; Type='DWord'; CreateKey=$true; Description='Open File Explorer to This PC instead of Home' },
        [pscustomobject]@{ SubKey='Software\Microsoft\Windows\CurrentVersion\Explorer'; Name='ShowCloudFilesInQuickAccess'; Value=0; Type='DWord'; CreateKey=$true; Description='Hide cloud/account files from Quick Access/Home for this user' },
        [pscustomobject]@{ SubKey='Software\Microsoft\Windows\CurrentVersion\Explorer'; Name='ShowRecent'; Value=0; Type='DWord'; CreateKey=$true; Description='Disable recent files in Explorer Home' },
        [pscustomobject]@{ SubKey='Software\Microsoft\Windows\CurrentVersion\Explorer'; Name='ShowFrequent'; Value=0; Type='DWord'; CreateKey=$true; Description='Disable frequent folders in Explorer Home' },
        [pscustomobject]@{ SubKey='Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'; Name='NoRecentDocsHistory'; Value=1; Type='DWord'; CreateKey=$true; Description='Disable recently opened documents history' },
        [pscustomobject]@{ SubKey='Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'; Name='NoRecentDocsMenu'; Value=1; Type='DWord'; CreateKey=$true; Description='Disable recent documents menu' },
        [pscustomobject]@{ SubKey='Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'; Name='ClearRecentDocsOnExit'; Value=1; Type='DWord'; CreateKey=$true; Description='Clear recent docs on exit' },
        [pscustomobject]@{ SubKey='Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'; Name='HideFileExt'; Value=0; Type='DWord'; CreateKey=$true; Description='Reinforce QOL: policy mirror to show file extensions' },
        [pscustomobject]@{ SubKey='Software\Microsoft\Windows\CurrentVersion\PushNotifications'; Name='ToastEnabled'; Value=0; Type='DWord'; CreateKey=$true; Description='Reinforce QOL: disable toast notifications for this hive' },
        [pscustomobject]@{ SubKey='Software\Microsoft\Windows\CurrentVersion\Notifications\Settings'; Name='NOC_GLOBAL_SETTING_TOASTS_ENABLED'; Value=0; Type='DWord'; CreateKey=$true; Description='Reinforce QOL: disable global toast notifications for this hive' },
        [pscustomobject]@{ SubKey='Software\Policies\Microsoft\Windows\CurrentVersion\PushNotifications'; Name='NoToastApplicationNotification'; Value=1; Type='DWord'; CreateKey=$true; Description='Reinforce QOL: user policy disables app toast notifications' },
        [pscustomobject]@{ SubKey='Software\Policies\Microsoft\Windows\CurrentVersion\PushNotifications'; Name='NoToastApplicationNotificationOnLockScreen'; Value=1; Type='DWord'; CreateKey=$true; Description='Reinforce QOL: user policy disables lock-screen toast notifications' },
        [pscustomobject]@{ SubKey='Software\Policies\Microsoft\Windows\CurrentVersion\PushNotifications'; Name='NoTileApplicationNotification'; Value=1; Type='DWord'; CreateKey=$true; Description='Reinforce QOL: user policy disables tile/app notification traffic' },
        [pscustomobject]@{ SubKey='Software\Policies\Microsoft\Windows\CurrentVersion\PushNotifications'; Name='DisallowNotificationMirroring'; Value=1; Type='DWord'; CreateKey=$true; Description='Reinforce QOL: user policy disables notification mirroring' },
        [pscustomobject]@{ SubKey='Software\Policies\Microsoft\Windows\Explorer'; Name='DisableNotificationCenter'; Value=1; Type='DWord'; CreateKey=$true; Description='Reinforce QOL: user policy disables Notification Center' },
        [pscustomobject]@{ SubKey='Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'; Name='TaskbarNoNotification'; Value=1; Type='DWord'; CreateKey=$true; Description='Reinforce QOL: legacy policy hides taskbar notifications' },
        [pscustomobject]@{ SubKey='Software\Policies\Microsoft\Windows\CurrentVersion\AccountNotifications'; Name='DisableAccountNotifications'; Value=1; Type='DWord'; CreateKey=$true; Description='Reinforce QOL: user policy disables account notifications' },
        [pscustomobject]@{ SubKey='Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name='TaskbarDa'; Value=0; Type='DWord'; CreateKey=$true; BestEffort=$true; SkipUserHiveSweep=$true; PolicyFallback='machine policies HKLM\SOFTWARE\Policies\Microsoft\Dsh AllowNewsAndInterests=0 and HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds EnableFeeds=0 are applied by this script'; Description='Reinforce QOL: disable Widgets/weather taskbar affordance for this hive' },
        [pscustomobject]@{ SubKey='Software\Microsoft\Windows\CurrentVersion\Feeds'; Name='ShellFeedsTaskbarViewMode'; Value=2; Type='DWord'; CreateKey=$true; BestEffort=$true; SkipUserHiveSweep=$true; PolicyFallback='machine policies HKLM\SOFTWARE\Policies\Microsoft\Dsh AllowNewsAndInterests=0 and HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds EnableFeeds=0 are applied by this script'; Description='Reinforce QOL: hide News and Interests / Feeds taskbar entry' },
        [pscustomobject]@{ SubKey='Software\Microsoft\Windows\CurrentVersion\Feeds'; Name='ShellFeedsTaskbarOpenOnHover'; Value=0; Type='DWord'; CreateKey=$true; BestEffort=$true; SkipUserHiveSweep=$true; PolicyFallback='machine policies HKLM\SOFTWARE\Policies\Microsoft\Dsh AllowNewsAndInterests=0 and HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds EnableFeeds=0 are applied by this script'; Description='Reinforce QOL: disable Feeds open-on-hover' },
        [pscustomobject]@{ SubKey='Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; Name='AppsUseLightTheme'; Value=0; Type='DWord'; CreateKey=$true; Description='Reinforce QOL: set app theme to dark for this hive' },
        [pscustomobject]@{ SubKey='Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; Name='SystemUsesLightTheme'; Value=0; Type='DWord'; CreateKey=$true; Description='Reinforce QOL: set system theme to dark for this hive' },
        [pscustomobject]@{ SubKey='Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; Name='EnableTransparency'; Value=0; Type='DWord'; CreateKey=$true; Description='Reinforce QOL: disable transparency effects for this hive' },
        [pscustomobject]@{ SubKey='Software\Policies\Microsoft\Windows\Explorer'; Name='HideRecommendedSection'; Value=1; Type='DWord'; CreateKey=$true; Description='Hide Recommended section policy' },
        [pscustomobject]@{ SubKey='Software\Policies\Microsoft\Windows\Explorer'; Name='HideRecentlyAddedApps'; Value=1; Type='DWord'; CreateKey=$true; Description='Disable recently added apps policy' },
        [pscustomobject]@{ SubKey='Software\Policies\Microsoft\Windows\Explorer'; Name='HideRecentJumplists'; Value=1; Type='DWord'; CreateKey=$true; Description='Disable recent Jump Lists policy' },
        [pscustomobject]@{ SubKey='Software\Policies\Microsoft\Windows\Explorer'; Name='HideRecommendedPersonalizedSites'; Value=1; Type='DWord'; CreateKey=$true; Description='Disable personalized Start recommendations policy' },
        [pscustomobject]@{ SubKey='Software\Policies\Microsoft\Windows\Explorer'; Name='HideFrequentlyUsedApps'; Value=1; Type='DWord'; CreateKey=$true; Description='Disable frequently used apps policy' },
        [pscustomobject]@{ SubKey='Software\Policies\Microsoft\Windows\Explorer'; Name='ShowOrHideMostUsedApps'; Value=2; Type='DWord'; CreateKey=$true; Description='Force-hide most-used apps policy' },
        [pscustomobject]@{ SubKey='Software\Policies\Microsoft\Windows\CloudContent'; Name='DisableWindowsConsumerFeatures'; Value=1; Type='DWord'; CreateKey=$true; Description='Disable Consumer/Suggested content' },
        [pscustomobject]@{ SubKey='Software\Policies\Microsoft\Windows\CloudContent'; Name='DisableCloudOptimizedContent'; Value=1; Type='DWord'; CreateKey=$true; Description='Disable cloud optimized content' },
        [pscustomobject]@{ SubKey='Software\Policies\Microsoft\Windows\CloudContent'; Name='DisableConsumerAccountStateContent'; Value=1; Type='DWord'; CreateKey=$true; Description='Disable consumer account state content' },
        [pscustomobject]@{ SubKey='Software\Policies\Microsoft\Windows\CloudContent'; Name='DisableSoftLanding'; Value=1; Type='DWord'; CreateKey=$true; Description='Disable Windows tips/soft landing' },
        [pscustomobject]@{ SubKey='Software\Policies\Microsoft\Windows\CloudContent'; Name='DisableWindowsSpotlightFeatures'; Value=1; Type='DWord'; CreateKey=$true; Description='Disable Windows Spotlight suggestions' },
        [pscustomobject]@{ SubKey='Software\Policies\Microsoft\Windows\CloudContent'; Name='DisableThirdPartySuggestions'; Value=1; Type='DWord'; CreateKey=$true; Description='Disable third-party suggestions' },
        [pscustomobject]@{ SubKey='Software\Policies\Microsoft\Windows\WindowsCopilot'; Name='TurnOffWindowsCopilot'; Value=1; Type='DWord'; CreateKey=$true; Description='Disable Copilot policy' },
        [pscustomobject]@{ SubKey='Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name='SubscribedContent-338389Enabled'; Value=0; Type='DWord'; CreateKey=$true; Description='Disable Windows tips/suggestions' },
        [pscustomobject]@{ SubKey='Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name='SubscribedContent-338393Enabled'; Value=0; Type='DWord'; CreateKey=$true; Description='Disable suggested content in Settings' },
        [pscustomobject]@{ SubKey='Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name='SubscribedContent-353694Enabled'; Value=0; Type='DWord'; CreateKey=$true; Description='Disable Settings app recommendations' },
        [pscustomobject]@{ SubKey='Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name='SubscribedContent-353696Enabled'; Value=0; Type='DWord'; CreateKey=$true; Description='Disable Settings app recommendations and offers' },
        [pscustomobject]@{ SubKey='Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name='SystemPaneSuggestionsEnabled'; Value=0; Type='DWord'; CreateKey=$true; Description='Disable Settings app suggestions' },
        [pscustomobject]@{ SubKey='Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement'; Name='ScoobeSystemSettingEnabled'; Value=0; Type='DWord'; CreateKey=$true; Description='Disable post-update Windows tips/suggestions' },
        [pscustomobject]@{ SubKey='Software\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked'; Name='{CB3B0003-8088-4EDE-8769-8B354AB2FF8C}'; Value='Ask Copilot - OLD'; Type='String'; CreateKey=$true; Description='Remove old Ask Copilot context item' },
        [pscustomobject]@{ SubKey='Software\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked'; Name='{ED215C26-C810-49CE-929E-31D7E83A82E9}'; Value='Ask Copilot - NEW'; Type='String'; CreateKey=$true; Description='Remove new Ask Copilot context item' }
    )

    return @($items)
}

function Get-QolMachineRegistryItems {
    param([Parameter(Mandatory=$true)][int]$SearchPolicyMode)

    $buildInfo = Get-QolWindowsBuildInfo
    $build = [int]$buildInfo.Build

    $items = @(
        [pscustomobject]@{ Key='HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\CloudContent'; Name='DisableWindowsConsumerFeatures'; Value=1; Type='DWord'; CreateKey=$true; Description='Disable Consumer/Suggested content' },
        [pscustomobject]@{ Key='HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\CloudContent'; Name='DisableCloudOptimizedContent'; Value=1; Type='DWord'; CreateKey=$true; Description='Disable cloud optimized content' },
        [pscustomobject]@{ Key='HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\CloudContent'; Name='DisableConsumerAccountStateContent'; Value=1; Type='DWord'; CreateKey=$true; Description='Disable consumer account state content' },
        [pscustomobject]@{ Key='HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\CloudContent'; Name='DisableSoftLanding'; Value=1; Type='DWord'; CreateKey=$true; Description='Disable Windows tips/soft landing' },
        [pscustomobject]@{ Key='HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\CloudContent'; Name='DisableWindowsSpotlightFeatures'; Value=1; Type='DWord'; CreateKey=$true; Description='Disable Windows Spotlight suggestions' },
        [pscustomobject]@{ Key='HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\CloudContent'; Name='DisableThirdPartySuggestions'; Value=1; Type='DWord'; CreateKey=$true; Description='Disable third-party suggestions' },
        [pscustomobject]@{ Key='HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot'; Name='TurnOffWindowsCopilot'; Value=1; Type='DWord'; CreateKey=$true; Description='Disable Copilot policy' },
        [pscustomobject]@{ Key='HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\PushNotifications'; Name='NoToastApplicationNotification'; Value=1; Type='DWord'; CreateKey=$true; Description='Reinforce QOL: machine policy disables app toast notifications' },
        [pscustomobject]@{ Key='HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\PushNotifications'; Name='NoCloudApplicationNotification'; Value=1; Type='DWord'; CreateKey=$true; Description='Reinforce QOL: machine policy disables cloud toast notifications' },
        [pscustomobject]@{ Key='HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\Explorer'; Name='DisableNotificationCenter'; Value=1; Type='DWord'; CreateKey=$true; Description='Reinforce QOL: machine policy disables Notification Center' },
        [pscustomobject]@{ Key='HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Notifications'; Name='DisableNotifications'; Value=1; Type='DWord'; CreateKey=$true; Description='Reinforce QOL: machine policy disables Windows Security notifications' },
        [pscustomobject]@{ Key='HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Notifications'; Name='DisableEnhancedNotifications'; Value=1; Type='DWord'; CreateKey=$true; Description='Reinforce QOL: machine policy disables enhanced Windows Security notifications' },
        [pscustomobject]@{ Key='HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Dsh'; Name='AllowNewsAndInterests'; Value=0; Type='DWord'; CreateKey=$true; Description='Reinforce QOL: machine policy disables Widgets / News and Interests' },
        [pscustomobject]@{ Key='HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds'; Name='EnableFeeds'; Value=0; Type='DWord'; CreateKey=$true; Description='Reinforce QOL: machine policy disables Windows Feeds' },
        [pscustomobject]@{ Key='HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'; Name='HideFileExt'; Value=0; Type='DWord'; CreateKey=$true; Description='Reinforce QOL: machine policy mirror to show file extensions' },
        [pscustomobject]@{ Key='HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\Dwm'; Name='ForceDisableModeChangeAnimation'; Value=1; Type='DWord'; CreateKey=$true; Description='Disable Windows 11 display mode / monitor-change animation' },
        [pscustomobject]@{ Key='HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; Name='EnableFirstLogonAnimation'; Value=0; Type='DWord'; CreateKey=$true; Description='Disable first sign-in / first logon animation' },
        [pscustomobject]@{ Key='HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'; Name='EnableFirstLogonAnimation'; Value=0; Type='DWord'; CreateKey=$true; Description='Disable first sign-in / first logon animation compatibility location' },
        [pscustomobject]@{ Key='HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\OneDrive'; Name='DisableFileSyncNGSC'; Value=1; Type='DWord'; CreateKey=$true; Description='OneDrive full disable: machine policy prevents the OneDrive sync client from starting' },
        [pscustomobject]@{ Key='HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\OneDrive'; Name='DisableFileSync'; Value=1; Type='DWord'; CreateKey=$true; Description='OneDrive full disable: legacy machine policy disables OneDrive file sync' },
        [pscustomobject]@{ Key='HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\OneDrive'; Name='DisableLibrariesDefaultSaveToOneDrive'; Value=1; Type='DWord'; CreateKey=$true; Description='OneDrive full disable: prevent libraries from defaulting saves to OneDrive' },
        [pscustomobject]@{ Key='HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\OneDrive'; Name='DisableNewAccountDetection'; Value=1; Type='DWord'; CreateKey=$true; Description='OneDrive full disable: suppress account-detected OneDrive sign-in prompts' },
        [pscustomobject]@{ Key='HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\OneDrive'; Name='DisableAutoConfig'; Value=3; Type='DWord'; CreateKey=$true; Description='OneDrive full disable: block automatic sign-in for AAD and Microsoft accounts' },
        [pscustomobject]@{ Key='HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'; Name='OneDrive'; Type='Delete'; Description='OneDrive full disable: remove machine OneDrive Run startup entry' },
        [pscustomobject]@{ Key='HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'; Name='OneDriveSetup'; Type='Delete'; Description='OneDrive full disable: remove machine OneDrive setup Run startup entry' },
        [pscustomobject]@{ Key='HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'; Name='Microsoft OneDrive'; Type='Delete'; Description='OneDrive full disable: remove alternate machine Microsoft OneDrive Run startup entry' },
        [pscustomobject]@{ Key='HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Name='OneDrive'; Type='Delete'; Description='OneDrive full disable: remove 32-bit machine OneDrive Run startup entry' },
        [pscustomobject]@{ Key='HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Name='OneDriveSetup'; Type='Delete'; Description='OneDrive full disable: remove 32-bit machine OneDrive setup Run startup entry' },
        [pscustomobject]@{ Key='HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Name='Microsoft OneDrive'; Type='Delete'; Description='OneDrive full disable: remove alternate 32-bit machine Microsoft OneDrive Run startup entry' },
        [pscustomobject]@{ Key='HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'; Name='OneDrive'; Type='Delete'; Description='OneDrive full disable: remove machine OneDrive RunOnce startup entry' },
        [pscustomobject]@{ Key='HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'; Name='OneDriveSetup'; Type='Delete'; Description='OneDrive full disable: remove machine OneDrive setup RunOnce startup entry' },
        [pscustomobject]@{ Key='HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'; Name='OneDrive'; Type='Delete'; Description='OneDrive full disable: remove machine StartupApproved OneDrive marker' },
        [pscustomobject]@{ Key='HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'; Name='OneDriveSetup'; Type='Delete'; Description='OneDrive full disable: remove machine StartupApproved OneDrive setup marker' },
        [pscustomobject]@{ Key='HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'; Name='Microsoft OneDrive'; Type='Delete'; Description='OneDrive full disable: remove alternate machine StartupApproved Microsoft OneDrive marker' },
        [pscustomobject]@{ Key='HKEY_LOCAL_MACHINE\SOFTWARE\Classes\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}'; Name='System.IsPinnedToNameSpaceTree'; Value=0; Type='DWord'; CreateKey=$true; Description='OneDrive full disable: hide OneDrive Explorer namespace machine-wide' },
        [pscustomobject]@{ Key='HKEY_LOCAL_MACHINE\SOFTWARE\Classes\Wow6432Node\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}'; Name='System.IsPinnedToNameSpaceTree'; Value=0; Type='DWord'; CreateKey=$true; Description='OneDrive full disable: hide 32-bit OneDrive Explorer namespace machine-wide' },
        [pscustomobject]@{ Key='HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked'; Name='{CB3B0003-8088-4EDE-8769-8B354AB2FF8C}'; Value='Ask Copilot - OLD'; Type='String'; CreateKey=$true; Description='Remove old Ask Copilot context item' },
        [pscustomobject]@{ Key='HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked'; Name='{ED215C26-C810-49CE-929E-31D7E83A82E9}'; Value='Ask Copilot - NEW'; Type='String'; CreateKey=$true; Description='Remove new Ask Copilot context item' }
    )

    $items += @(Get-QolPerformanceOptionsMachineDefaultRegistryItems)

    if ($build -ge 22621) {
        $items += @(
            [pscustomobject]@{ Key='HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\Explorer'; Name='DisableGraphRecentItems'; Value=1; Type='DWord'; CreateKey=$true; Description='Disable Explorer Home cloud/recent/recommended account metadata' },
            [pscustomobject]@{ Key='HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\Explorer'; Name='HideRecommendedSection'; Value=1; Type='DWord'; CreateKey=$true; Description='Hide Start Recommended section where supported' },
            [pscustomobject]@{ Key='HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\Explorer'; Name='HideRecentlyAddedApps'; Value=1; Type='DWord'; CreateKey=$true; Description='Disable recently added apps policy' },
            [pscustomobject]@{ Key='HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\Explorer'; Name='HideRecentJumplists'; Value=1; Type='DWord'; CreateKey=$true; Description='Disable recent Jump Lists policy' },
            [pscustomobject]@{ Key='HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\Explorer'; Name='HideRecommendedPersonalizedSites'; Value=1; Type='DWord'; CreateKey=$true; Description='Hide recommended personalized sites where supported' },
            [pscustomobject]@{ Key='HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\Explorer'; Name='HideFrequentlyUsedApps'; Value=1; Type='DWord'; CreateKey=$true; Description='Disable frequently used apps policy' },
            [pscustomobject]@{ Key='HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\Explorer'; Name='ShowOrHideMostUsedApps'; Value=2; Type='DWord'; CreateKey=$true; Description='Force-hide most-used apps policy' }
        )
    }

    if ($build -ge 26100) {
        $items += @(
            [pscustomobject]@{ Key='HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\Windows Search'; Name='ConfigureSearchOnTaskbarMode'; Value=$SearchPolicyMode; Type='DWord'; CreateKey=$true; Description='Configure Search taskbar mode on Windows 11 24H2+' }
        )
    }

    return $items
}
function Expand-QolRegistryItemList {
    param([AllowNull()][object]$Items)

    foreach ($entry in @($Items)) {
        if ($null -eq $entry) { continue }
        if (($entry -is [System.Array]) -and -not ($entry -is [byte[]])) {
            foreach ($nested in @(Expand-QolRegistryItemList -Items $entry)) { $nested }
            continue
        }
        $entry
    }
}

function Convert-QolRegistrySignatureValue {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return '<null>' }
    if ($Value -is [byte[]]) { return ([BitConverter]::ToString($Value)).ToUpperInvariant() }
    if (($Value -is [System.Array]) -and -not ($Value -is [byte[]])) {
        $parts = New-Object System.Collections.ArrayList
        foreach ($part in @($Value)) { [void]$parts.Add((Convert-QolRegistrySignatureValue -Value $part)) }
        return ($parts -join ',')
    }
    return ([string]$Value)
}

function Get-QolRegistryItemSignature {
    param(
        [AllowNull()][object]$Item,
        [AllowEmptyString()][string]$HiveRoot = ''
    )

    if ($null -eq $Item) { return '' }

    $key = ''
    if ($Item.PSObject.Properties.Name -contains 'Key') {
        $key = [string]$Item.Key
    } elseif ($Item.PSObject.Properties.Name -contains 'SubKey') {
        $subKey = [string]$Item.SubKey
        if (-not [string]::IsNullOrWhiteSpace($HiveRoot)) {
            $key = Join-QolRegistryKey -Root $HiveRoot -SubKey $subKey
        } else {
            $key = $subKey
        }
    }

    $name = ''
    if ($Item.PSObject.Properties.Name -contains 'Name') { $name = [string]$Item.Name }

    $type = 'DWord'
    if ($Item.PSObject.Properties.Name -contains 'Type') { $type = [string]$Item.Type }

    $value = '<missing>'
    if ($Item.PSObject.Properties.Name -contains 'Value') { $value = Convert-QolRegistrySignatureValue -Value $Item.Value }

    return ((($key.TrimEnd('\')) + '|' + $name + '|' + $type + '|' + $value).ToUpperInvariant())
}

function Select-QolUniqueRegistryItems {
    param(
        [AllowNull()][object]$Items,
        [AllowEmptyString()][string]$HiveRoot = ''
    )

    $seen = @{}
    foreach ($item in @(Expand-QolRegistryItemList -Items $Items)) {
        $signature = Get-QolRegistryItemSignature -Item $item -HiveRoot $HiveRoot
        if ([string]::IsNullOrWhiteSpace($signature)) {
            $item
            continue
        }
        if ($seen.ContainsKey($signature)) { continue }
        $seen[$signature] = $true
        $item
    }
}

function Invoke-QolRegistryItemsForHive {
    param(
        [Parameter(Mandatory=$true)][string]$HiveRoot,
        [Parameter(Mandatory=$true)][object[]]$Items
    )

    $failed = 0
    foreach ($item in @(Select-QolUniqueRegistryItems -Items $Items -HiveRoot $HiveRoot)) {
        if ($null -eq $item -or -not ($item.PSObject.Properties.Name -contains 'SubKey')) {
            $failed++
            Write-StatusLine -Ok $false -Text 'invalid QOL registry item: missing SubKey'
            continue
        }

        $subKeyValue = $item.SubKey
        if (($subKeyValue -is [System.Array]) -and -not ($subKeyValue -is [byte[]])) {
            $subKeyValues = @($subKeyValue)
            if ($subKeyValues.Count -eq 1) {
                $subKeyValue = $subKeyValues[0]
            } else {
                $failed++
                Write-StatusLine -Ok $false -Text ("invalid QOL registry item: SubKey resolved to {0} values" -f $subKeyValues.Count)
                continue
            }
        }

        if (Test-QolSkipUserHiveSweepRegistryItem -Item $item) {
            continue
        }

        $key = Join-QolRegistryKey -Root $HiveRoot -SubKey ([string]$subKeyValue)
        $create = $false
        if ($item.PSObject.Properties.Name -contains 'CreateKey') { $create = [bool]$item.CreateKey }
        $type = 'DWord'
        if ($item.PSObject.Properties.Name -contains 'Type') { $type = [string]$item.Type }

        switch -Regex ($type) {
            '^(DWord|REG_DWORD)$' { $result = Set-RegistryDword -Key $key -Name $item.Name -Value $item.Value -CreateKey:$create; break }
            '^(String|REG_SZ)$' { $result = Set-RegistryString -Key $key -Name $item.Name -Value ([string]$item.Value) -CreateKey:$create; break }
            '^(DefaultString|DefaultValue|REG_SZ_DEFAULT|REG_DEFAULT_SZ)$' {
                $value = ''
                if ($item.PSObject.Properties.Name -contains 'Value') { $value = [string]$item.Value }
                $result = Set-RegistryDefaultString -Key $key -Value $value -CreateKey:$create
                break
            }
            '^(Binary|REG_BINARY)$' { $result = Set-RegistryBinary -Key $key -Name $item.Name -Value $item.Value -CreateKey:$create; break }
            '^(Delete|DeleteValue|Remove|RemoveValue|REG_DELETE)$' { $result = Remove-RegistryValue -Key $key -Name $item.Name; break }
            default { $result = [pscustomobject]@{ Ok=$false; Message="unsupported registry value type '$type' for $key\$($item.Name)" }; break }
        }

        $result = Convert-QolRegistryItemResultForBestEffort -Item $item -Result $result
        if (-not $result.Ok) { $failed++ }
        $isWarning = $false
        if ($result.PSObject.Properties.Name -contains 'Warning') { $isWarning = [bool]$result.Warning }
        $label = $result.Message
        if ($item.PSObject.Properties.Name -contains 'Description') { $label = $item.Description + ' | ' + $result.Message }
        Write-StatusLine -Ok $result.Ok -Text $label -Warning:$isWarning
    }

    return ($failed -eq 0)
}

function Remove-QolRegistryTree {
    param(
        [Parameter(Mandatory=$true)][string]$Key,
        [Parameter(Mandatory=$true)][string]$Label
    )

    $psPath = "Registry::$Key"
    try {
        if (Test-Path -LiteralPath $psPath) {
            Remove-Item -LiteralPath $psPath -Recurse -Force -ErrorAction Stop
            Write-StatusLine -Ok $true -Text "$Label | removed $Key"
        } else {
            Write-StatusLine -Ok $true -Text "$Label | already absent: $Key"
        }
        return $true
    }
    catch {
        Write-StatusLine -Ok $false -Text "$Label | $Key -> $($_.Exception.Message)"
        return $false
    }
}

function Invoke-QolApplyUserHive {
    param(
        [Parameter(Mandatory=$true)][string]$HiveRoot,
        [Parameter(Mandatory=$true)][int]$SearchUserMode,
        [Parameter(Mandatory=$true)][string]$Label
    )

    Write-Host ''
    Write-BoxTitle -Title $Label
    Write-Host ''

    $failed = 0
    $items = Get-QolUserRegistryItems -SearchUserMode $SearchUserMode
    if (-not (Invoke-QolRegistryItemsForHive -HiveRoot $HiveRoot -Items $items)) { $failed++ }

    $shellRoot = Join-QolRegistryKey -Root $HiveRoot -SubKey 'Software\Classes\Local Settings\Software\Microsoft\Windows\Shell'
    if (-not (Remove-QolRegistryTree -Key (Join-QolRegistryKey -Root $shellRoot -SubKey 'Bags') -Label 'Reset Explorer folder view Bags')) { $failed++ }
    if (-not (Remove-QolRegistryTree -Key (Join-QolRegistryKey -Root $shellRoot -SubKey 'BagMRU') -Label 'Reset Explorer folder view BagMRU')) { $failed++ }

    $folderTypeResult = Set-RegistryString -Key (Join-QolRegistryKey -Root $shellRoot -SubKey 'Bags\AllFolders\Shell') -Name 'FolderType' -Value 'NotSpecified' -CreateKey
    if (-not $folderTypeResult.Ok) { $failed++ }
    Write-StatusLine -Ok $folderTypeResult.Ok -Text ('Disable automatic folder type discovery | ' + $folderTypeResult.Message)

    if (-not (Remove-QolRegistryTree -Key (Join-QolRegistryKey -Root $HiveRoot -SubKey 'Software\Microsoft\Windows\CurrentVersion\Explorer\RecentDocs') -Label 'Clear Explorer RecentDocs registry history')) { $failed++ }
    if (-not (Remove-QolRegistryTree -Key (Join-QolRegistryKey -Root $HiveRoot -SubKey 'Software\Microsoft\Windows\CurrentVersion\Explorer\TypedPaths') -Label 'Clear Explorer TypedPaths history')) { $failed++ }
    if (-not (Remove-QolRegistryTree -Key (Join-QolRegistryKey -Root $HiveRoot -SubKey 'Software\Microsoft\Windows\CurrentVersion\Explorer\RunMRU') -Label 'Clear Explorer RunMRU history')) { $failed++ }
    if (-not (Remove-QolRegistryTree -Key (Join-QolRegistryKey -Root $HiveRoot -SubKey 'Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband') -Label 'Reset taskbar pinned-app binary cache')) { $failed++ }

    return ($failed -eq 0)
}

function Add-QolProfilePath {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter()]
        [AllowEmptyCollection()]
        [System.Collections.ArrayList]$List
    )

    if ($null -eq $List) { return }
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    try { $expanded = [Environment]::ExpandEnvironmentVariables($Path) } catch { $expanded = $Path }
    if ([string]::IsNullOrWhiteSpace($expanded)) { return }
    if (-not ($List -contains $expanded)) { [void]$List.Add($expanded) }
}

function Get-QolProfilePaths {
    $profiles = New-Object System.Collections.ArrayList

    if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) { Add-QolProfilePath -Path $env:USERPROFILE -List $profiles }

    $profileListPath = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
    try {
        if (Test-Path -LiteralPath $profileListPath) {
            foreach ($profileKey in Get-ChildItem -LiteralPath $profileListPath -ErrorAction SilentlyContinue) {
                $sid = $profileKey.PSChildName
                if ($sid -notmatch '^S-1-5-21-') { continue }
                $props = Get-ItemProperty -LiteralPath $profileKey.PSPath -ErrorAction SilentlyContinue
                if ($null -ne $props -and -not [string]::IsNullOrWhiteSpace($props.ProfileImagePath)) {
                    Add-QolProfilePath -Path $props.ProfileImagePath -List $profiles
                }
            }
        }
    }
    catch { }

    $defaultUser = Join-Path $env:SystemDrive 'Users\Default'
    Add-QolProfilePath -Path $defaultUser -List $profiles
    return @($profiles)
}

function Set-QolTaskbarPinnedAppsForProfilePath {
    param([Parameter(Mandatory=$true)][string]$ProfilePath)

    $failed = 0
    try {
        if ([string]::IsNullOrWhiteSpace($ProfilePath)) { return $true }
        if (-not (Test-Path -LiteralPath $ProfilePath -PathType Container)) {
            Write-StatusLine -Ok $true -Warning -Text "taskbar profile path not found, skipped: $ProfilePath"
            return $true
        }

        $windowsDirectory = $env:WINDIR
        if ([string]::IsNullOrWhiteSpace($windowsDirectory)) { $windowsDirectory = 'C:\Windows' }
        $explorerExe = Join-Path $windowsDirectory 'explorer.exe'
        if (-not (Test-Path -LiteralPath $explorerExe -PathType Leaf)) {
            Write-StatusLine -Ok $false -Text "explorer.exe not found: $explorerExe"
            return $false
        }

        $roaming = Join-Path $ProfilePath 'AppData\Roaming'
        $pinnedFolder = Join-Path $roaming 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'
        $startMenuProgramsFolder = Join-Path $roaming 'Microsoft\Windows\Start Menu\Programs'
        $startMenuExplorerShortcut = Join-Path $startMenuProgramsFolder 'File Explorer.lnk'
        $taskbarExplorerShortcut = Join-Path $pinnedFolder 'File Explorer.lnk'

        if (-not (Test-Path -LiteralPath $pinnedFolder)) {
            New-Item -Path $pinnedFolder -ItemType Directory -Force | Out-Null
        }

        try {
            Get-ChildItem -LiteralPath $pinnedFolder -Force -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction Stop
            Write-StatusLine -Ok $true -Text "QOL all-profile taskbar pins | cleared pinned shortcuts: $pinnedFolder"
        }
        catch {
            $failed++
            Write-StatusLine -Ok $false -Text "QOL all-profile taskbar pins | could not clear $pinnedFolder -> $($_.Exception.Message)"
        }

        foreach ($shortcutPath in @($startMenuExplorerShortcut, $taskbarExplorerShortcut)) {
            $shortcutResult = New-WindowsShortcutFile -ShortcutPath $shortcutPath -TargetPath $explorerExe -WorkingDirectory $windowsDirectory -IconLocation ("{0},0" -f $explorerExe)
            if (-not $shortcutResult.Ok) { $failed++ }
            Write-StatusLine -Ok $shortcutResult.Ok -Text ("QOL all-profile taskbar pins | $ProfilePath | " + $shortcutResult.Message)
        }

        if (-not (Write-QolExplorerOnlyTaskbarLayoutForProfilePath -ProfilePath $ProfilePath -Label "QOL all-profile Explorer-only taskbar layout XML | $ProfilePath")) { $failed++ }
    }
    catch {
        $failed++
        Write-StatusLine -Ok $false -Text "QOL all-profile taskbar pins failed for $($ProfilePath): $($_.Exception.Message)"
    }

    return ($failed -eq 0)
}

function Set-QolTaskbarPinnedAppsForAllProfiles {
    $failed = 0
    foreach ($profile in @(Get-QolProfilePaths)) {
        if (-not (Set-QolTaskbarPinnedAppsForProfilePath -ProfilePath $profile)) { $failed++ }
    }

    $systemLayout = Write-QolExplorerOnlyTaskbarLayoutSystemFiles
    if (-not $systemLayout.Ok) { $failed++ }
    if (-not (Set-QolExplorerOnlyTaskbarLayoutPolicy -LayoutFile $systemLayout.PolicyPath)) { $failed++ }

    return ($failed -eq 0)
}

function Clear-QolExplorerRecentHistoryFiles {
    $failed = 0
    $profiles = Get-QolProfilePaths
    foreach ($profile in @($profiles)) {
        $recentRoot = Join-Path $profile 'AppData\Roaming\Microsoft\Windows\Recent'
        if (-not (Test-Path -LiteralPath $recentRoot)) { continue }

        foreach ($relative in @('', 'AutomaticDestinations', 'CustomDestinations')) {
            $target = if ([string]::IsNullOrWhiteSpace($relative)) { $recentRoot } else { Join-Path $recentRoot $relative }
            if (-not (Test-Path -LiteralPath $target)) { continue }

            try {
                Get-ChildItem -LiteralPath $target -Force -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction Stop
                Write-StatusLine -Ok $true -Text "cleared Explorer recent history files: $target"
            }
            catch {
                $failed++
                Write-StatusLine -Ok $false -Text "could not clear Explorer recent history files: $target -> $($_.Exception.Message)"
            }
        }
    }

    return ($failed -eq 0)
}

function Get-QolCurrentUserSid {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        if ($null -ne $identity -and $null -ne $identity.User) { return [string]$identity.User.Value }
    }
    catch { }
    return ''
}

function Get-QolLoadedUserHiveRoots {
    $roots = New-Object System.Collections.ArrayList
    foreach ($sid in @('.DEFAULT')) { [void]$roots.Add("HKEY_USERS\$sid") }
    $currentSid = Get-QolCurrentUserSid

    try {
        foreach ($key in Get-ChildItem -LiteralPath 'Registry::HKEY_USERS' -ErrorAction SilentlyContinue) {
            $sid = $key.PSChildName
            if ($sid -match '^S-1-5-21-' -and $sid -notmatch '_Classes$') {
                if (-not [string]::IsNullOrWhiteSpace($currentSid) -and $sid -ieq $currentSid) { continue }
                [void]$roots.Add("HKEY_USERS\$sid")
            }
        }
    }
    catch { }

    return @($roots | Select-Object -Unique)
}

function Invoke-QolApplyLoadedUserHives {
    param([Parameter(Mandatory=$true)][int]$SearchUserMode)

    Write-StatusLine -Ok $true -Warning -Text 'loaded non-current user hives receive registry-default changes only; live SystemParametersInfo applies only to the current interactive session'

    $failed = 0
    foreach ($root in @(Get-QolLoadedUserHiveRoots)) {
        $label = "QOL User Hive - $root"
        if (-not (Invoke-QolApplyUserHive -HiveRoot $root -SearchUserMode $SearchUserMode -Label $label)) { $failed++ }
    }
    return ($failed -eq 0)
}

function Invoke-QolApplyUnloadedProfileHives {
    param([Parameter(Mandatory=$true)][int]$SearchUserMode)

    Write-StatusLine -Ok $true -Warning -Text 'unloaded and Default profile hives receive registry-default changes only; live SystemParametersInfo cannot run for users who are not in the current interactive session'

    $failed = 0
    $seenNtUser = New-Object System.Collections.ArrayList
    $profileListPath = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'

    $profileRows = @()
    try {
        if (Test-Path -LiteralPath $profileListPath) {
            foreach ($profileKey in Get-ChildItem -LiteralPath $profileListPath -ErrorAction SilentlyContinue) {
                $sid = $profileKey.PSChildName
                if ($sid -notmatch '^S-1-5-21-') { continue }
                if (Test-Path -LiteralPath ("Registry::HKEY_USERS\$sid")) { continue }

                $props = Get-ItemProperty -LiteralPath $profileKey.PSPath -ErrorAction SilentlyContinue
                if ($null -eq $props -or [string]::IsNullOrWhiteSpace($props.ProfileImagePath)) { continue }
                $profilePath = [Environment]::ExpandEnvironmentVariables($props.ProfileImagePath)
                $ntUserPath = Join-Path $profilePath 'NTUSER.DAT'
                $profileRows += [pscustomobject]@{ Sid=$sid; NtUserPath=$ntUserPath; Label="Unloaded profile $sid" }
            }
        }
    }
    catch {
        Write-StatusLine -Ok $true -Warning -Text "could not enumerate unloaded user profile hives: $($_.Exception.Message)"
    }

    $defaultHive = Join-Path (Join-Path $env:SystemDrive 'Users\Default') 'NTUSER.DAT'
    if (Test-Path -LiteralPath $defaultHive) {
        $profileRows += [pscustomobject]@{ Sid='_DEFAULTPROFILE'; NtUserPath=$defaultHive; Label='Default user profile template' }
    }

    foreach ($row in @($profileRows)) {
        if (-not (Test-Path -LiteralPath $row.NtUserPath -PathType Leaf)) { continue }
        if ($seenNtUser -contains $row.NtUserPath) { continue }
        [void]$seenNtUser.Add($row.NtUserPath)

        $safeName = ($row.Sid -replace '[^A-Za-z0-9_\-]', '_')
        $mountName = "LLC_QOL_$safeName"
        $mountRoot = "HKEY_USERS\$mountName"

        try {
            $loadResult = Invoke-QolNativeCommandCaptured -FilePath 'reg.exe' -Arguments @('load', $mountRoot, $row.NtUserPath) -TimeoutSeconds 60
            $loadOutput = $loadResult.Output
            if ($loadResult.ExitCode -ne 0) {
                $failed++
                Write-StatusLine -Ok $false -Text "could not load $($row.Label) hive $($row.NtUserPath): $($loadOutput -join ' ')"
                continue
            }

            try {
                if (-not (Invoke-QolApplyUserHive -HiveRoot $mountRoot -SearchUserMode $SearchUserMode -Label ("QOL User Hive - $($row.Label)"))) { $failed++ }
            }
            finally {
                [GC]::Collect()
                [GC]::WaitForPendingFinalizers()
                $unloadResult = Invoke-QolNativeCommandCaptured -FilePath 'reg.exe' -Arguments @('unload', $mountRoot) -TimeoutSeconds 60
                $unloadOutput = $unloadResult.Output
                if ($unloadResult.ExitCode -ne 0) {
                    $failed++
                    Write-StatusLine -Ok $false -Text "could not unload $($row.Label) hive: $($unloadOutput -join ' ')"
                } else {
                    Write-StatusLine -Ok $true -Text "unloaded $($row.Label) hive"
                }
            }
        }
        catch {
            $failed++
            Write-StatusLine -Ok $false -Text "unloaded-profile hive processing failed for $($row.Label): $($_.Exception.Message)"
            try { Invoke-QolNativeCommandCaptured -FilePath 'reg.exe' -Arguments @('unload', $mountRoot) -TimeoutSeconds 60 | Out-Null } catch { }
        }
    }

    return ($failed -eq 0)
}


function Test-QolTextLooksLikeOneDrive {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return $false }
    try {
        $text = [string]$Value
        if ([string]::IsNullOrWhiteSpace($text)) { return $false }
        return ($text -match '(?i)\bOneDrive\b|Microsoft\\OneDrive')
    }
    catch { }
    return $false
}

function Get-QolScheduledTaskFullName {
    param([Parameter(Mandatory=$true)][object]$Task)

    $taskPath = ''
    $taskName = ''
    try { $taskPath = [string]$Task.TaskPath } catch { }
    try { $taskName = [string]$Task.TaskName } catch { }
    if ([string]::IsNullOrWhiteSpace($taskPath)) { $taskPath = '\' }
    return ($taskPath + $taskName)
}

function Test-QolScheduledTaskIsOneDrive {
    param([Parameter(Mandatory=$true)][object]$Task)

    if (Test-QolTextLooksLikeOneDrive -Value (Get-QolScheduledTaskFullName -Task $Task)) { return $true }

    foreach ($action in @($Task.Actions)) {
        if ($null -eq $action) { continue }
        try { if (Test-QolTextLooksLikeOneDrive -Value $action.Execute) { return $true } } catch { }
        try { if (Test-QolTextLooksLikeOneDrive -Value $action.Arguments) { return $true } } catch { }
    }

    return $false
}

function Invoke-QolDisableOneDriveScheduledTasks {
    $failed = 0
    $found = 0

    try {
        $tasks = @(Get-ScheduledTask -ErrorAction Stop | Where-Object { Test-QolScheduledTaskIsOneDrive -Task $_ })
    }
    catch {
        Write-StatusLine -Ok $true -Warning -Text "OneDrive full disable: could not enumerate scheduled tasks; skipping task disable pass -> $($_.Exception.Message)"
        return $true
    }

    foreach ($task in @($tasks)) {
        $found++
        $fullName = Get-QolScheduledTaskFullName -Task $task
        $taskName = ''
        $taskPath = ''
        try { $taskName = [string]$task.TaskName } catch { }
        try { $taskPath = [string]$task.TaskPath } catch { }
        if ([string]::IsNullOrWhiteSpace($taskPath)) { $taskPath = '\' }

        try { Stop-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction SilentlyContinue | Out-Null } catch { }

        $disabled = $false
        try {
            $current = Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction Stop
            if ([string]$current.State -eq 'Disabled') {
                $disabled = $true
                Write-StatusLine -Ok $true -Text "OneDrive full disable: scheduled task already disabled: $fullName"
            } else {
                Disable-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction Stop | Out-Null
                $disabled = $true
                Write-StatusLine -Ok $true -Text "OneDrive full disable: disabled scheduled task: $fullName"
            }
        }
        catch {
            $primaryError = $_.Exception.Message
            try {
                $fallback = Invoke-QolNativeCommandCaptured -FilePath 'schtasks.exe' -Arguments @('/Change', '/TN', $fullName, '/Disable') -TimeoutSeconds 30
                if ($fallback.ExitCode -eq 0) {
                    $disabled = $true
                    Write-StatusLine -Ok $true -Text "OneDrive full disable: disabled scheduled task via schtasks.exe: $fullName"
                } else {
                    $failed++
                    Write-StatusLine -Ok $false -Text "OneDrive full disable: could not disable scheduled task $fullName -> $primaryError | $($fallback.Output -join ' ')"
                }
            }
            catch {
                $failed++
                Write-StatusLine -Ok $false -Text "OneDrive full disable: could not disable scheduled task $fullName -> $primaryError | fallback: $($_.Exception.Message)"
            }
        }

        if ($disabled) {
            try { Stop-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction SilentlyContinue | Out-Null } catch { }
        }
    }

    if ($found -eq 0) {
        Write-StatusLine -Ok $true -Text 'OneDrive full disable: no OneDrive scheduled tasks found'
    }

    return ($failed -eq 0)
}

function Invoke-QolDisableOneDriveServices {
    $failed = 0
    $found = 0

    try {
        $services = @(Get-Service -ErrorAction Stop | Where-Object { ([string]$_.Name -match '(?i)OneDrive') -or ([string]$_.DisplayName -match '(?i)OneDrive') })
    }
    catch {
        Write-StatusLine -Ok $true -Warning -Text "OneDrive full disable: could not enumerate services; skipping service disable pass -> $($_.Exception.Message)"
        return $true
    }

    foreach ($svc in @($services)) {
        $found++
        $name = [string]$svc.Name
        try {
            if ([string]$svc.Status -ne 'Stopped') {
                Stop-Service -Name $name -Force -ErrorAction SilentlyContinue
            }
        }
        catch { }

        try {
            Set-Service -Name $name -StartupType Disabled -ErrorAction Stop
            Write-StatusLine -Ok $true -Text "OneDrive full disable: disabled service: $name"
        }
        catch {
            $primaryError = $_.Exception.Message
            try {
                $fallback = Invoke-QolNativeCommandCaptured -FilePath 'sc.exe' -Arguments @('config', $name, 'start=', 'disabled') -TimeoutSeconds 30
                if ($fallback.ExitCode -eq 0) {
                    Write-StatusLine -Ok $true -Text "OneDrive full disable: disabled service via sc.exe: $name"
                } else {
                    $failed++
                    Write-StatusLine -Ok $false -Text "OneDrive full disable: could not disable service $name -> $primaryError | $($fallback.Output -join ' ')"
                }
            }
            catch {
                $failed++
                Write-StatusLine -Ok $false -Text "OneDrive full disable: could not disable service $name -> $primaryError | fallback: $($_.Exception.Message)"
            }
        }
    }

    if ($found -eq 0) {
        Write-StatusLine -Ok $true -Text 'OneDrive full disable: no OneDrive services found'
    }

    return ($failed -eq 0)
}

function Test-QolStartupFileIsOneDrive {
    param([Parameter(Mandatory=$true)][System.IO.FileInfo]$File)

    if (Test-QolTextLooksLikeOneDrive -Value $File.Name) { return $true }
    if ($File.Extension -notmatch '(?i)^\.lnk$') { return $false }

    try {
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($File.FullName)
        if (Test-QolTextLooksLikeOneDrive -Value $shortcut.TargetPath) { return $true }
        if (Test-QolTextLooksLikeOneDrive -Value $shortcut.Arguments) { return $true }
    }
    catch { }

    return $false
}

function Get-QolOneDriveStartupFolders {
    $folders = New-Object System.Collections.ArrayList

    foreach ($profilePath in @(Get-QolProfilePaths)) {
        if ([string]::IsNullOrWhiteSpace($profilePath)) { continue }
        $folder = Join-Path $profilePath 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup'
        if (-not ($folders -contains $folder)) { [void]$folders.Add($folder) }
    }

    $commonStartup = ''
    try { $commonStartup = [Environment]::GetFolderPath('CommonStartup') } catch { }
    if ([string]::IsNullOrWhiteSpace($commonStartup) -and -not [string]::IsNullOrWhiteSpace($env:ProgramData)) {
        $commonStartup = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Startup'
    }
    if (-not [string]::IsNullOrWhiteSpace($commonStartup) -and -not ($folders -contains $commonStartup)) { [void]$folders.Add($commonStartup) }

    return @($folders)
}

function Invoke-QolDisableOneDriveStartupShortcuts {
    $failed = 0
    $found = 0

    foreach ($folder in @(Get-QolOneDriveStartupFolders)) {
        if ([string]::IsNullOrWhiteSpace($folder)) { continue }
        if (-not (Test-Path -LiteralPath $folder -PathType Container)) { continue }

        try {
            $files = @(Get-ChildItem -LiteralPath $folder -File -Force -ErrorAction SilentlyContinue | Where-Object { Test-QolStartupFileIsOneDrive -File $_ })
            foreach ($file in @($files)) {
                $found++
                $disabledFolder = Join-Path $folder 'LowLatencyCorp_Disabled_Startup'
                try {
                    if (-not (Test-Path -LiteralPath $disabledFolder -PathType Container)) {
                        New-Item -Path $disabledFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
                    }

                    $target = Join-Path $disabledFolder $file.Name
                    if (Test-Path -LiteralPath $target) {
                        $base = [IO.Path]::GetFileNameWithoutExtension($file.Name)
                        $ext = [IO.Path]::GetExtension($file.Name)
                        $target = Join-Path $disabledFolder ("{0}_{1:yyyyMMdd_HHmmss}{2}" -f $base, (Get-Date), $ext)
                    }

                    Move-Item -LiteralPath $file.FullName -Destination $target -Force -ErrorAction Stop
                    Write-StatusLine -Ok $true -Text "OneDrive full disable: moved startup shortcut out of Startup: $($file.FullName)"
                }
                catch {
                    $failed++
                    Write-StatusLine -Ok $false -Text "OneDrive full disable: could not move startup shortcut $($file.FullName) -> $($_.Exception.Message)"
                }
            }
        }
        catch {
            $failed++
            Write-StatusLine -Ok $false -Text "OneDrive full disable: could not inspect Startup folder $folder -> $($_.Exception.Message)"
        }
    }

    if ($found -eq 0) {
        Write-StatusLine -Ok $true -Text 'OneDrive full disable: no OneDrive Startup-folder shortcuts found'
    }

    return ($failed -eq 0)
}

function Invoke-QolStopOneDriveProcesses {
    $failed = 0

    try {
        $processes = @()
        foreach ($name in @('OneDrive', 'OneDriveSetup', 'OneDriveStandaloneUpdater')) {
            $processes += @(Get-Process -Name $name -ErrorAction SilentlyContinue)
        }

        try {
            $processes += @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
                $path = ''
                try { $path = [string]$_.Path } catch { }
                (Test-QolTextLooksLikeOneDrive -Value $_.ProcessName) -or (Test-QolTextLooksLikeOneDrive -Value $path)
            })
        }
        catch { }

        $processes = @($processes | Where-Object { $null -ne $_ } | Sort-Object Id -Unique)
        if ($processes.Count -lt 1) {
            Write-StatusLine -Ok $true -Text 'OneDrive full disable: no running OneDrive processes found'
            return $true
        }

        foreach ($proc in @($processes)) {
            $label = ''
            try { $label = ('{0} (PID {1})' -f $proc.ProcessName, $proc.Id) } catch { $label = 'OneDrive process' }
            try {
                Stop-Process -Id $proc.Id -Force -ErrorAction Stop
                Write-StatusLine -Ok $true -Text "OneDrive full disable: stopped process $label"
            }
            catch {
                $failed++
                Write-StatusLine -Ok $false -Text "OneDrive full disable: could not stop process $label -> $($_.Exception.Message)"
            }
        }
    }
    catch {
        $failed++
        Write-StatusLine -Ok $false -Text "OneDrive full disable: process cleanup failed -> $($_.Exception.Message)"
    }

    return ($failed -eq 0)
}

function Invoke-QolFullyDisableOneDriveRuntime {
    Write-Host 'Applying OneDrive full disable without uninstalling it: policies are already written above; this pass disables live background launch paths.' -ForegroundColor Cyan
    Write-Host ''

    $failed = 0
    if (-not (Invoke-QolDisableOneDriveScheduledTasks)) { $failed++ }
    if (-not (Invoke-QolDisableOneDriveServices)) { $failed++ }
    if (-not (Invoke-QolDisableOneDriveStartupShortcuts)) { $failed++ }
    if (-not (Invoke-QolStopOneDriveProcesses)) { $failed++ }

    return ($failed -eq 0)
}



function Invoke-QolOptimizeAuto {
    Write-Host ''
    Write-BoxTitle -Title 'QOL - Optimize'
    Write-Host ''
    Write-Host 'This applies Windows 11 quality-of-life registry, policy, Explorer, classic context menu, Start, Search, accessibility, animation, and OneDrive no-uninstall disablement tweaks.' -ForegroundColor White
    Write-Host 'It writes registry defaults to HKCU, loaded user hives, unloaded local profile hives, the Default profile template, and machine-wide policies where available.' -ForegroundColor DarkGray
    Write-Host 'Live SystemParametersInfo changes and SPI_GET verification are performed only for the current interactive session.' -ForegroundColor DarkGray
    Write-Host ''

    $searchMode = [pscustomobject]@{ Continue=$true; Label='Hidden'; UserMode=0; PolicyMode=0 }
    Write-Host ("Auto Search taskbar mode: {0}" -f $searchMode.Label) -ForegroundColor Cyan
    Write-Host ''

    $failures = 0


    Write-Host ''
    Write-BoxTitle -Title 'Current User Hive'
    Write-Host ''
    if (-not (Invoke-QolApplyUserHive -HiveRoot 'HKEY_CURRENT_USER' -SearchUserMode $searchMode.UserMode -Label 'QOL User Hive - HKEY_CURRENT_USER')) { $failures++ }

    Write-Host ''
    Write-BoxTitle -Title 'Loaded User Hives'
    Write-Host ''
    if (-not (Invoke-QolApplyLoadedUserHives -SearchUserMode $searchMode.UserMode)) { $failures++ }

    Write-Host ''
    Write-BoxTitle -Title 'Unloaded / Default Profile Hives'
    Write-Host ''
    if (-not (Invoke-QolApplyUnloadedProfileHives -SearchUserMode $searchMode.UserMode)) { $failures++ }

    Write-Host ''
    Write-BoxTitle -Title 'Machine-Wide Policies / Shell Extensions'
    Write-Host ''
    if (-not (Invoke-RegistryItemsInline -Items (Get-QolMachineRegistryItems -SearchPolicyMode $searchMode.PolicyMode))) { $failures++ }

    Write-Host ''
    Write-BoxTitle -Title 'OneDrive - Full Disable (No Uninstall)'
    Write-Host ''
    if (-not (Invoke-QolFullyDisableOneDriveRuntime)) { $failures++ }

    Write-Host ''
    Write-BoxTitle -Title 'Explorer Recent History Files'
    Write-Host ''
    if (-not (Clear-QolExplorerRecentHistoryFiles)) { $failures++ }

    Write-Host ''
    Write-BoxTitle -Title 'Taskbar Pins - All Profiles'
    Write-Host ''
    if (-not (Set-QolTaskbarPinnedAppsForAllProfiles)) { $failures++ }

    if (-not (Invoke-MouseAccelerationSetting -Auto)) { $failures++ }

    Write-Host ''
    Write-BoxTitle -Title 'Live UI Timing / Animation Settings'
    Write-Host ''
    if (-not (Invoke-QolSystemParameters)) { $failures++ }

    Write-Host ''
    $refreshResult = Send-TaskbarOptimizeSettingRefresh
    if (-not $refreshResult.Ok) { $failures++ }
    Write-StatusLine -Ok $refreshResult.Ok -Text $refreshResult.Message -Warning:($refreshResult.PSObject.Properties.Name -contains 'Warning' -and [bool]$refreshResult.Warning)

    Write-Host ''
    if ($failures -eq 0) {
        Write-Host 'OVERALL: SUCCESS - QOL Optimize completed.' -ForegroundColor Green
    } else {
        Write-Host ("OVERALL: FAILED/WARNING - {0} QOL optimize step(s) reported a failure. Review the output above." -f $failures) -ForegroundColor Red
    }

    Write-Host ''
    return ($failures -eq 0)
}


function Invoke-QolOptimize {
    if (-not (Confirm-LlcBroadChanges -Scope QOL)) { return }
    Clear-ConsoleScreen
    Write-BoxTitle -Title 'QOL - Optimize'
    Write-Host ''
    Write-Host 'This applies Windows 11 quality-of-life registry, policy, Explorer, classic context menu, Start, Search, accessibility, animation, and OneDrive no-uninstall disablement tweaks.' -ForegroundColor White
    Write-Host 'It writes registry defaults to HKCU, loaded user hives, unloaded local profile hives, the Default profile template, and machine-wide policies where available.' -ForegroundColor DarkGray
    Write-Host 'Live SystemParametersInfo changes and SPI_GET verification are performed only for the current interactive session.' -ForegroundColor DarkGray
    Write-Host ''

    $searchMode = Invoke-QolSearchModeMenu
    if (-not $searchMode.Continue) { return }

    Clear-ConsoleScreen
    Write-BoxTitle -Title 'QOL - Optimize'
    Write-Host ''
    Write-Host ("Selected Search taskbar mode: {0}" -f $searchMode.Label) -ForegroundColor Cyan
    Write-Host ''

    $failures = 0


    Write-Host ''
    Write-BoxTitle -Title 'Current User Hive'
    Write-Host ''
    if (-not (Invoke-QolApplyUserHive -HiveRoot 'HKEY_CURRENT_USER' -SearchUserMode $searchMode.UserMode -Label 'QOL User Hive - HKEY_CURRENT_USER')) { $failures++ }

    Write-Host ''
    Write-BoxTitle -Title 'Loaded User Hives'
    Write-Host ''
    if (-not (Invoke-QolApplyLoadedUserHives -SearchUserMode $searchMode.UserMode)) { $failures++ }

    Write-Host ''
    Write-BoxTitle -Title 'Unloaded / Default Profile Hives'
    Write-Host ''
    if (-not (Invoke-QolApplyUnloadedProfileHives -SearchUserMode $searchMode.UserMode)) { $failures++ }

    Write-Host ''
    Write-BoxTitle -Title 'Machine-Wide Policies / Shell Extensions'
    Write-Host ''
    if (-not (Invoke-RegistryItemsInline -Items (Get-QolMachineRegistryItems -SearchPolicyMode $searchMode.PolicyMode))) { $failures++ }

    Write-Host ''
    Write-BoxTitle -Title 'OneDrive - Full Disable (No Uninstall)'
    Write-Host ''
    if (-not (Invoke-QolFullyDisableOneDriveRuntime)) { $failures++ }

    Write-Host ''
    Write-BoxTitle -Title 'Explorer Recent History Files'
    Write-Host ''
    if (-not (Clear-QolExplorerRecentHistoryFiles)) { $failures++ }

    Write-Host ''
    Write-BoxTitle -Title 'Taskbar Pins - All Profiles'
    Write-Host ''
    if (-not (Set-QolTaskbarPinnedAppsForAllProfiles)) { $failures++ }

    if (-not (Invoke-MouseAccelerationSetting -Auto)) { $failures++ }

    Write-Host ''
    Write-BoxTitle -Title 'Live UI Timing / Animation Settings'
    Write-Host ''
    if (-not (Invoke-QolSystemParameters)) { $failures++ }

    Write-Host ''
    $refreshResult = Send-TaskbarOptimizeSettingRefresh
    if (-not $refreshResult.Ok) { $failures++ }
    Write-StatusLine -Ok $refreshResult.Ok -Text $refreshResult.Message -Warning:($refreshResult.PSObject.Properties.Name -contains 'Warning' -and [bool]$refreshResult.Warning)

    Write-Host ''
    if ($failures -eq 0) {
        Write-Host 'OVERALL: SUCCESS - QOL Optimize completed.' -ForegroundColor Green
    } else {
        Write-Host ("OVERALL: FAILED/WARNING - {0} QOL optimize step(s) reported a failure. Review the output above." -f $failures) -ForegroundColor Red
    }

    Write-Host ''
    Wait-ForEnterToContinue
}




if (-not (Test-Admin)) {
    Clear-ConsoleScreen
    Write-Host "FAILED: This tool must run as Administrator." -ForegroundColor Red
    Wait-ForEnterToContinue -Prompt 'Press Enter to exit'
    exit 1
}

try {
    Initialize-TrustedInstallerToken
} catch {
    Write-Host "WARNING: TrustedInstaller init failed ($($_.Exception.Message)) - some protected keys may fail." -ForegroundColor Yellow
}

while ($true) {
    $mainMenuItems = @(Get-LlcMainMenuItems -GpuText (Get-DetectedGpuMenuEntryText -Base 'GPU') -DriverText (Get-DetectedGpuMenuEntryText -Base 'Drivers') -MmcssText (Get-DetectedNetworkAdapterMenuEntryText -Base 'MMCSS'))
    $choice = Invoke-Menu -Title 'Low Latency Corp Menu v2' -Items $mainMenuItems

    switch ($choice) {
        'preflight' {
            Clear-ConsoleScreen
            Write-LlcPreflightReport -Result (Get-LlcPreflightResult)
            Write-Host 'Auto and QOL still apply broad system changes after explicit confirmation.' -ForegroundColor Yellow
            Wait-ForEnterToContinue
        }
        'autoRegistryTweaks' {
            Invoke-AutoRegistryTweaks
        }
        'fullscreenOptimization' {
            while ($true) {
                $sub = Invoke-Menu -Title 'Fullscreen Optimization' -Items @(
                    'Disable FSO',
                    'Enable FSO',
                    'Back'
                )

                if ($sub -eq 0) {
                    Invoke-RegistrySet -Title 'Disable Fullscreen Optimization' -Items $fsoDisable -AfterMessage ''
                } elseif ($sub -eq 1) {
                    Invoke-RegistrySet -Title 'Enable Fullscreen Optimization' -Items $fsoEnable -AfterMessage ''
                } else {
                    break
                }
            }
        }
        'services' {
            while ($true) {
                $sub = Invoke-Menu -Title 'Services' -Items @(
                    'Disable services',
                    'Enable services - restore Start defaults',
                    'Back'
                )

                if ($sub -eq 0) {
                    Invoke-RegistrySet -Title 'Disable Services' -Items $servicesToDisable -AfterMessage ''
                } elseif ($sub -eq 1) {
                    Invoke-RegistrySet -Title 'Enable Services - Restore Start Defaults' -Items $servicesToEnable -AfterMessage ''
                } else {
                    break
                }
            }
        }
        'networkOptimization' {
            while ($true) {
                $sub = Invoke-Menu -Title 'Network Optimization' -Items @(
                    'Enable',
                    'Disable',
                    'Back'
                )

                if ($sub -eq 0) {
                    Invoke-NetworkOptimizationEnable
                } elseif ($sub -eq 1) {
                    Invoke-NetworkOptimizationDisable
                } else {
                    break
                }
            }
        }
        'mmcss' {
            while ($true) {
                $sub = Invoke-Menu -Title (Get-DetectedNetworkAdapterTitleText -Base 'MMCSS') -Items @(
                    'Enable',
                    'Disable',
                    'Optimize MMCSS',
                    'Fix Audio Stutters',
                    'Back'
                )

                if ($sub -eq 0) {
                    Invoke-RegistrySet -Title 'MMCSS - Enable' -Items $mmcssEnable -AfterMessage ''
                } elseif ($sub -eq 1) {
                    Invoke-RegistrySet -Title 'MMCSS - Disable' -Items $mmcssDisable -AfterMessage ''
                } elseif ($sub -eq 2) {
                    Invoke-RegistrySet -Title 'Optimize MMCSS' -Items $mmcssOptimize -AfterMessage ''
                } elseif ($sub -eq 3) {
                    Invoke-RegistrySet -Title 'Fix Audio Stutters' -Items $mmcssFixAudioStutters -AfterMessage ''
                } else {
                    break
                }
            }
        }
        'gamebarAndGameMode' {
            while ($true) {
                $sub = Invoke-Menu -Title 'Gamebar and Game Mode' -Items @(
                    'Disable Game Bar',
                    'Disable Game Mode',
                    'Enable Game Bar',
                    'Enable Game Mode',
                    'Back'
                )

                if ($sub -eq 0) {
                    Invoke-RegistrySet -Title 'Disable Game Bar' -Items $gameBarDisable -AfterMessage ''
                } elseif ($sub -eq 1) {
                    Invoke-RegistrySet -Title 'Disable Game Mode' -Items $gameModeDisable -AfterMessage ''
                } elseif ($sub -eq 2) {
                    Invoke-RegistrySet -Title 'Enable Game Bar' -Items $gameBarEnable -AfterMessage ''
                } elseif ($sub -eq 3) {
                    Invoke-RegistrySet -Title 'Enable Game Mode' -Items $gameModeEnable -AfterMessage ''
                } else {
                    break
                }
            }
        }
        'clockInterrupts' {
            while ($true) {
                $sub = Invoke-Menu -Title 'Clock Interrupts' -Items @(
                    'Core 0',
                    'Back'
                )

                if ($sub -eq 0) {
                    Invoke-RegistrySet -Title 'Clock Interrupts - Core 0' -Items $clockInterruptsCore0 -AfterMessage ''
                } else {
                    break
                }
            }
        }
        'win32PrioritySeparation' {
            while ($true) {
                $sub = Invoke-Menu -Title 'Win32PrioritySeparation' -Items @(
                    '18 (hex)',
                    'Back'
                )

                if ($sub -eq 0) {
                    Invoke-RegistrySet -Title 'Win32PrioritySeparation - 18 (hex)' -Items $win32PrioritySeparation18Hex -AfterMessage ''
                } else {
                    break
                }
            }
        }
        'powerPlan' {
            while ($true) {
                $sub = Invoke-Menu -Title 'Power Plan' -Items @(
                    'Import and Activate',
                    'Back'
                )

                if ($sub -eq 0) {
                    Invoke-PowerPlanImportAndActivate
                } else {
                    break
                }
            }
        }
        'uac' {
            while ($true) {
                $sub = Invoke-Menu -Title 'UAC' -Items @(
                    'Enable',
                    'Disable',
                    'Back'
                )

                if ($sub -eq 0) {
                    Invoke-RegistrySet -Title 'UAC - Enable' -Items $uacEnable -AfterMessage ''
                } elseif ($sub -eq 1) {
                    Invoke-RegistrySet -Title 'UAC - Disable' -Items $uacDisable -AfterMessage ''
                } else {
                    break
                }
            }
        }
        'qol' {
            while ($true) {
                $sub = Invoke-Menu -Title 'QOL' -Items @(
                    'Optimize',
                    'Back'
                )

                if ($sub -eq 0) {
                    Invoke-QolOptimize
                } else {
                    break
                }
            }
        }
        'hags' {
            while ($true) {
                $sub = Invoke-Menu -Title 'Hardware-Accelerated GPU Scheduling' -Items @(
                    'Enable',
                    'Disable',
                    'Back'
                )

                if ($sub -eq 0) {
                    Invoke-RegistrySet -Title 'Hardware-Accelerated GPU Scheduling - Enable' -Items $hagsEnable
                } elseif ($sub -eq 1) {
                    Invoke-RegistrySet -Title 'Hardware-Accelerated GPU Scheduling - Disable' -Items $hagsDisable
                } else {
                    break
                }
            }
        }
        'autostart' {
            Invoke-AutostartManager
        }
        'apps' {
            while ($true) {
                $apps = Invoke-Menu -Title 'Apps' -Items @(
                    'Device Tweaker',
                    'Windows Defender Switcher',
                    'Windows Update Blocker',
                    'Nvidia Profile Inspector',
                    'HIDUSBF',
                    '7-Zip',
                    'Chrome',
                    'Power Scheme Manager',
                    'PresentMon CSV Plotter',
                    'Back'
                )

                if ($apps -eq 0) {
                    while ($true) {
                        $sub = Invoke-Menu -Title 'Device Tweaker' -Items @(
                            'Launch DT',
                            'Back'
                        )

                        if ($sub -eq 0) {
                            Invoke-ExternalBatchLauncher -Title 'Device Tweaker - Launch DT' -RelativePath 'Resources\DEVICE-TWEAKER\RUN-DEVICE-TWEAKER.bat'
                        } else {
                            break
                        }
                    }
                } elseif ($apps -eq 1) {
                    while ($true) {
                        $sub = Invoke-Menu -Title 'Windows Defender Switcher' -Items @(
                            'Launch WDS',
                            'Back'
                        )

                        if ($sub -eq 0) {
                            Invoke-ExternalBatchLauncher -Title 'Windows Defender Switcher - Launch WDS' -RelativePath 'Resources\WINDOWS-DEFENDER\RUN-WDS.bat'
                        } else {
                            break
                        }
                    }
                } elseif ($apps -eq 2) {
                    while ($true) {
                        $sub = Invoke-Menu -Title 'Windows Update Blocker' -Items @(
                            'Launch WUB',
                            'Back'
                        )

                        if ($sub -eq 0) {
                            Invoke-ExternalBatchLauncher -Title 'Windows Update Blocker - Launch WUB' -RelativePath 'Resources\WINDOWS-UPDATES\RUN-WUB.bat'
                        } else {
                            break
                        }
                    }
                } elseif ($apps -eq 3) {
                    while ($true) {
                        $sub = Invoke-Menu -Title 'Nvidia Profile Inspector' -Items @(
                            'Import .nip',
                            'Launch NPI',
                            'Back'
                        )

                        if ($sub -eq 0) {
                            Invoke-ExternalExecutableLauncher -Title 'Nvidia Profile Inspector - Import .nip' -RelativePath 'Resources\NVIDIA-PROFILE-INSPECTOR\NVIDIA-PROFILE-INSPECTOR.exe' -RelativeArgumentPaths @('Resources\NVIDIA-PROFILE-INSPECTOR\LLC-OPTIMIZED-V3.nip') -WaitForExit
                        } elseif ($sub -eq 1) {
                            Invoke-ExternalExecutableLauncher -Title 'Nvidia Profile Inspector - Launch NPI' -RelativePath 'Resources\NVIDIA-PROFILE-INSPECTOR\NVIDIA-PROFILE-INSPECTOR.exe'
                        } else {
                            break
                        }
                    }
                } elseif ($apps -eq 4) {
                    while ($true) {
                        $sub = Invoke-Menu -Title 'HIDUSBF' -Items @(
                            'Launch HIDUSBF',
                            'Back'
                        )

                        if ($sub -eq 0) {
                            Invoke-ExternalExecutableLauncher -Title 'HIDUSBF - Launch HIDUSBF' -RelativePath 'Resources\HIDUSBF\DRIVER\SETUP.exe'
                        } else {
                            break
                        }
                    }
                } elseif ($apps -eq 5) {
                    while ($true) {
                        $sub = Invoke-Menu -Title '7-Zip' -Items @(
                            'Install 7-Zip',
                            'Back'
                        )

                        if ($sub -eq 0) {
                            Invoke-ExternalExecutableLauncher -Title '7-Zip - Install 7-Zip' -RelativePath 'Resources\7ZIP\7-Zip.exe'
                        } else {
                            break
                        }
                    }
                } elseif ($apps -eq 6) {
                    while ($true) {
                        $sub = Invoke-Menu -Title 'Chrome' -Items @(
                            'Install Chrome',
                            'Back'
                        )

                        if ($sub -eq 0) {
                            Invoke-ExternalExecutableLauncher -Title 'Chrome - Install Chrome' -RelativePath 'Resources\CHROME\Chrome.exe'
                        } else {
                            break
                        }
                    }
                } elseif ($apps -eq 7) {
                    while ($true) {
                        $sub = Invoke-Menu -Title 'Power Scheme Manager' -Items @(
                            'Launch PSM',
                            'Back'
                        )

                        if ($sub -eq 0) {
                            Invoke-ExternalExecutableLauncher -Title 'Power Scheme Manager - Launch PSM' -RelativePath 'Resources\POWER-SCHEME-MANAGER\POWER-SCHEME-MANAGER.exe'
                        } else {
                            break
                        }
                    }
                } elseif ($apps -eq 8) {
                    while ($true) {
                        $sub = Invoke-Menu -Title 'PresentMon CSV Plotter' -Items @(
                            'Launch PMCSVP',
                            'Back'
                        )

                        if ($sub -eq 0) {
                            Invoke-ExternalExecutableLauncher -Title 'PresentMon CSV Plotter - Launch PMCSVP' -RelativePath 'Resources\PRESENTMON-CSV-PLOTTER\PRESENTMON-CSV-PLOTTER.exe'
                        } else {
                            break
                        }
                    }
                } else {
                    break
                }
            }
        }
        'drivers' {
            while ($true) {
                $drivers = Invoke-Menu -Title 'Drivers' -Items @(
                    [pscustomobject]@{ Text=(Get-DetectedGpuMenuEntryText -Base 'GPU'); Value='gpuDrivers' },
                    'NIC',
                    'Back'
                )

                if ($drivers -eq 'gpuDrivers') {
                    while ($true) {
                        $gpu = Invoke-Menu -Title (Get-DetectedGpuMenuEntryText -Base 'GPU') -Items @(
                            'NVIDIA',
                            'AMD',
                            'Display Driver Uninstaller',
                            'Back'
                        )

                        if ($gpu -eq 0) {
                            while ($true) {
                                $nvidia = Invoke-Menu -Title 'NVIDIA' -Items @(
                                    'NvCleanstall',
                                    'Install driver',
                                    'Download Nvidia Driver',
                                    'Back'
                                )

                                if ($nvidia -eq 0) {
                                    while ($true) {
                                        $nc = Invoke-Menu -Title 'NvCleanstall' -Items @(
                                            'Launch NC',
                                            'Back'
                                        )

                                        if ($nc -eq 0) {
                                            Invoke-ExternalExecutableLauncher -Title 'NvCleanstall - Launch NC' -RelativePath 'Resources\NVCLEANSTALL\NVCleanstall.exe'
                                        } else {
                                            break
                                        }
                                    }
                                } elseif ($nvidia -eq 1) {
                                    while ($true) {
                                        $driverInstall = Invoke-Menu -Title 'Install driver' -Items @(
                                            '<=10 series (581.80)',
                                            '>=16 Series (596.21)',
                                            'Back'
                                        )

                                        if ($driverInstall -eq 0) {
                                            Invoke-ExternalExecutableLauncher -Title 'Install Nvidia Driver - <=10 series (581.80)' -RelativePath 'Resources\NVIDIA-DRIVERS\10-Series\NVCleanstall_NVIDIA_581.80_Setup.exe' -Arguments @('-y') -WaitForExit
                                        } elseif ($driverInstall -eq 1) {
                                            Invoke-ExternalExecutableLauncher -Title 'Install Nvidia Driver - >=16 Series (596.21)' -RelativePath 'Resources\NVIDIA-DRIVERS\16+-Series\NVCleanstall_NVIDIA_596.21_Setup.exe' -Arguments @('-y') -WaitForExit
                                        } else {
                                            break
                                        }
                                    }
                                } elseif ($nvidia -eq 2) {
                                    while ($true) {
                                        $driverDownload = Invoke-Menu -Title 'Download Nvidia Driver' -Items @(
                                            '<=10 Series (581.80)',
                                            '>=16 Series (596.21)',
                                            'Back'
                                        )

                                        if ($driverDownload -eq 0) {
                                            Invoke-NvidiaDriverDownload -Title 'Download Nvidia Driver - <=10 Series' -Url 'https://us.download.nvidia.com/Windows/581.80/581.80-desktop-win10-win11-64bit-international-dch-whql.exe' -FileName '581.80-desktop-win10-win11-64bit-international-dch-whql.exe' -ProbeContentLength
                                        } elseif ($driverDownload -eq 1) {
                                            Invoke-NvidiaDriverDownload -Title 'Download Nvidia Driver - >=16 Series' -Url 'https://us.download.nvidia.com/Windows/596.21/596.21-desktop-win10-win11-64bit-international-dch-whql.exe' -FileName '596.21-desktop-win10-win11-64bit-international-dch-whql.exe' -ProbeContentLength
                                        } else {
                                            break
                                        }
                                    }
                                } else {
                                    break
                                }
                            }
                        } elseif ($gpu -eq 1) {
                            while ($true) {
                                $amd = Invoke-Menu -Title 'AMD' -Items @(
                                    'Radeon Software Slimmer',
                                    'Install driver',
                                    'Download AMD Driver',
                                    'Back'
                                )

                                if ($amd -eq 0) {
                                    while ($true) {
                                        $rss = Invoke-Menu -Title 'Radeon Software Slimmer' -Items @(
                                            'Launch RSS',
                                            'Back'
                                        )

                                        if ($rss -eq 0) {
                                            Invoke-ExternalExecutableLauncher -Title 'Radeon Software Slimmer - Launch RSS' -RelativePath 'Resources\RadeonSoftwareSlimmer\RadeonSoftwareSlimmer.exe'
                                        } else {
                                            break
                                        }
                                    }
                                } elseif ($amd -eq 1) {
                                    while ($true) {
                                        $amdDriverInstall = Invoke-Menu -Title 'Install driver' -Items @(
                                            '400/500 series (26.5.2)',
                                            '>500 series (26.6.1)',
                                            'Back'
                                        )

                                        if ($amdDriverInstall -eq 0) {
                                            Invoke-ExternalExecutableLauncher -Title 'Install AMD Driver - 400/500 series (26.5.2)' -RelativePath 'Resources\AMD-DRIVERS\400-500-series\whql-amd-software-adrenalin-edition-26.5.2-win11-may-vega-polaris\Setup.exe' -Arguments @('-INSTALL') -WaitForExit
                                        } elseif ($amdDriverInstall -eq 1) {
                                            Invoke-ExternalExecutableLauncher -Title 'Install AMD Driver - >500 series (26.6.1)' -RelativePath 'Resources\AMD-DRIVERS\500+-series\whql-amd-software-adrenalin-edition-26.6.1-win11-c\Setup.exe' -Arguments @('-INSTALL') -WaitForExit
                                        } else {
                                            break
                                        }
                                    }
                                } elseif ($amd -eq 2) {
                                    while ($true) {
                                        $amdDriverDownload = Invoke-Menu -Title 'Download AMD Driver' -Items @(
                                            '400/500 series (26.5.2)',
                                            '>500 series (26.6.1)',
                                            'Back'
                                        )

                                        if ($amdDriverDownload -eq 0) {
                                            Invoke-NvidiaDriverDownload -Title 'Download AMD Driver - 400/500 series (26.5.2)' -Url 'https://drivers.amd.com/drivers/whql-amd-software-adrenalin-edition-26.5.2-win11-may-vega-polaris.exe' -FileName 'whql-amd-software-adrenalin-edition-26.5.2-win11-may-vega-polaris.exe' -ProbeContentLength -Referer 'https://www.amd.com/en/resources/support-articles/release-notes/RN-RAD-WIN-26-5-2-POLARIS-VEGA.html'
                                        } elseif ($amdDriverDownload -eq 1) {
                                            Invoke-NvidiaDriverDownload -Title 'Download AMD Driver - >500 series' -Url 'https://drivers.amd.com/drivers/whql-amd-software-adrenalin-edition-26.6.1-win11-c.exe' -FileName 'whql-amd-software-adrenalin-edition-26.6.1-win11-c.exe' -ProbeContentLength -Referer 'https://www.amd.com/en/resources/support-articles/release-notes/RN-RAD-WIN-26-6-1.html'
                                        } else {
                                            break
                                        }
                                    }
                                } else {
                                    break
                                }
                            }
                        } elseif ($gpu -eq 2) {
                            while ($true) {
                                $ddu = Invoke-Menu -Title 'Display Driver Uninstaller' -Items @(
                                    'Launch DDU',
                                    'Back'
                                )

                                if ($ddu -eq 0) {
                                    Invoke-ExternalExecutableLauncher -Title 'Display Driver Uninstaller - Launch DDU' -RelativePath 'Resources\DISPLAY-DRIVER-UNINSTALLER\DISPLAY-DRIVER-UNINSTALLER.exe'
                                } else {
                                    break
                                }
                            }
                        } else {
                            break
                        }
                    }
                } elseif ($drivers -eq 1) {
                    while ($true) {
                        $nic = Invoke-Menu -Title 'NIC' -Items @(
                            'Realtek',
                            'Intel',
                            'Back'
                        )

                        if ($nic -eq 0) {
                            while ($true) {
                                $reaaltek = Invoke-Menu -Title 'Reaaltek' -Items @(
                                    'NDIS',
                                    'NetAdapterCx',
                                    'Back'
                                )

                                if ($reaaltek -eq 0) {
                                    while ($true) {
                                        $ndis = Invoke-Menu -Title 'NDIS' -Items @(
                                            'Install NDIS',
                                            'Back'
                                        )

                                        if ($ndis -eq 0) {
                                            Invoke-ExternalExecutableLauncher -Title 'Reaaltek NDIS - Install NDIS' -RelativePath 'Resources\NETWORK-DRIVERS\REALTEK-NDIS\Install_Win11_Win10_10079_20_DMAROFF_01262026.exe'
                                        } else {
                                            break
                                        }
                                    }
                                } elseif ($reaaltek -eq 1) {
                                    while ($true) {
                                        $netAdapterCx = Invoke-Menu -Title 'NetAdapterCx' -Items @(
                                            'Install NetCx',
                                            'Back'
                                        )

                                        if ($netAdapterCx -eq 0) {
                                            Invoke-ExternalExecutableLauncher -Title 'Reaaltek NetAdapterCx - Install NetCx' -RelativePath 'Resources\NETWORK-DRIVERS\REALTEK-NETADAPTERCX\Install_PCIE_Win11_11028_20_DMAROFF_01262026.exe'
                                        } else {
                                            break
                                        }
                                    }
                                } else {
                                    break
                                }
                            }
                        } elseif ($nic -eq 1) {
                            while ($true) {
                                $intel = Invoke-Menu -Title 'Intel' -Items @(
                                    'Install driver',
                                    'Back'
                                )

                                if ($intel -eq 0) {
                                    Invoke-ExternalExecutableLauncher -Title 'Intel - Install driver' -RelativePath ('Resources\NETWORK-DRIVERS\INTEL-NETADAPTERCX-' + [char]0x0418 + '-NDIS\SetupBD.exe')
                                } else {
                                    break
                                }
                            }
                        } else {
                            break
                        }
                    }
                } else {
                    break
                }
            }
        }
        'gpu' {
            while ($true) {
                $gpu = Invoke-Menu -Title (Get-DetectedGpuMenuEntryText -Base 'GPU') -Items @(
                    'AMD',
                    'NVIDIA',
                    'Back'
                )

                if ($gpu -eq 0) {
                    while ($true) {
                        $amdGpu = Invoke-Menu -Title 'AMD' -Items @(
                            'Optimize AMD GPU',
                            'Revert AMD GPU Optimization.',
                            'Back'
                        )

                        if ($amdGpu -eq 0) {
                            Invoke-RegistrySet -Title 'Optimize AMD GPU' -Items $amdGpuOptimize -AfterMessage ''
                        } elseif ($amdGpu -eq 1) {
                            Invoke-RegistrySet -Title 'Revert AMD GPU Optimization' -Items $amdGpuRevert -AfterMessage ''
                        } else {
                            break
                        }
                    }
                } elseif ($gpu -eq 1) {
                    while ($true) {
                        $nvidiaGpu = Invoke-Menu -Title 'NVIDIA' -Items @(
                            'Optimize NVIDIA GPU',
                            'Revert NVIDIA GPU Optimization',
                            'Back'
                        )

                        if ($nvidiaGpu -eq 0) {
                            Invoke-RegistrySet -Title 'Optimize NVIDIA GPU' -Items $nvidiaGpuOptimize -AfterMessage ''
                        } elseif ($nvidiaGpu -eq 1) {
                            Invoke-RegistrySet -Title 'Revert NVIDIA GPU Optimization' -Items $nvidiaGpuRevert -AfterMessage ''
                        } else {
                            break
                        }
                    }
                } else {
                    break
                }
            }
        }
        'powersaving' {
            while ($true) {
                $sub = Invoke-Menu -Title 'Powersaving' -Items @(
                    'Disable device powersaving',
                    'Back'
                )

                if ($sub -eq 0) {
                    Invoke-DisableDevicePowerSaving
                } else {
                    break
                }
            }
        }
        'activateWindows' {
            while ($true) {
                $sub = Invoke-Menu -Title 'Activate Windows' -Items @(
                    'Activate WIN',
                    'Back'
                )

                if ($sub -eq 0) {
                    Invoke-WindowsActivationSettings
                } else {
                    break
                }
            }
        }
        'exit' { Cleanup-TrustedInstallerToken; exit 0 }
        default { Cleanup-TrustedInstallerToken; exit 0 }
    }
}
