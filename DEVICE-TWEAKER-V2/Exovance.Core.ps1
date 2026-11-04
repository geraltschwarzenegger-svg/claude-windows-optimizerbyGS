# Exovance Device Tweaker v2: testable affinity, RSS and registry support.
# Loading this file defines functions only; it never applies settings.
function Test-ExovanceNetworkWritable {
    param($Device)
    if ($null -eq $Device -or $Device.Category -ne 'Network') { return $false }
    # Names and the NDIS/NetAdapterCx driver model do not establish physicality.
    # IRQ/MSI editing currently supports physical PCI/PCIe adapters only.
    foreach ($flag in @('Virtual','SoftwareInterface')) {
        if ($Device.$flag -eq $true) { return $false }
    }
    foreach ($flag in @('HardwareInterface','PhysicalAdapter')) {
        if ($null -ne $Device.$flag -and $Device.$flag -eq $false) { return $false }
    }
    $physical = $false
    foreach ($field in @('PNPID','ConfigPath','RegistryPath')) {
        $path = [string]$Device.$field
        if ($path -match '(?i)(?:^|\\Enum\\)(?:SWD|ROOT|VMBUS|USB|BTH)\\') { return $false }
        if ($path -match '(?i)(?:^|\\Enum\\)PCI\\VEN_[0-9A-F]{4}&DEV_[0-9A-F]{4}(?:&|\\|$)') { $physical = $true }
    }
    return $physical
}

function Get-ExovanceWritableDevices {
    param([System.Collections.IEnumerable]$Devices)
    foreach ($device in $Devices) {
        if ($null -eq $device) { continue }
        if ($device.Category -ne 'Network' -or (Test-ExovanceNetworkWritable $device)) { $device }
        else { Write-Host ('[Exovance] Read only: {0} (virtual, non-PCI or unverified network adapter; no IRQ/MSI/RSS writes).' -f $device.DisplayName) -ForegroundColor DarkYellow }
    }
}

function Resolve-ExovanceNdisMode {
    param([string]$DialogResult, [string]$SelectedMode)
    if ($DialogResult -eq 'OK' -and @('RSS','IRQ','BOTH') -contains $SelectedMode) { return $SelectedMode.ToUpperInvariant() }
    return $null
}

function ConvertTo-ExovanceAffinityMask {
    param([int[]]$Processors)
    [uint64]$mask = 0
    foreach ($processor in $Processors) {
        if ($processor -lt 0 -or $processor -ge 64) { throw 'Processor index must be in group 0, range 0..63.' }
        $mask = $mask -bor ([uint64]1 -shl $processor)
    }
    return $mask
}

function Assert-ExovanceAffinityMask {
    param([uint64]$Mask, [int]$LogicalCount)
    if ($LogicalCount -lt 1 -or $LogicalCount -gt 64) { throw 'Cannot validate affinity against the active CPU topology.' }
    [uint64]$allowed = [uint64]::MaxValue -shr (64 - $LogicalCount)
    if (($Mask -band $allowed) -ne $Mask) { throw 'Affinity mask contains processors outside the active topology.' }
}

function Get-ExovanceProcessorGroupCount {
    if (-not ('ExovancePlatform' -as [type])) {
        Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
public static class ExovancePlatform {
    [DllImport("kernel32.dll")] public static extern ushort GetActiveProcessorGroupCount();
}
'@ -ErrorAction Stop
    }
    return [int][ExovancePlatform]::GetActiveProcessorGroupCount()
}

function Assert-ExovanceProcessorGroups {
    param([int]$GroupCount)
    if ($GroupCount -ne 1) { throw 'Multiple processor groups are not supported by this version. No settings were changed.' }
}

function Assert-ExovanceHost {
    param([switch]$RequireAdministrator)
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
        $PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion -lt [version]'5.1' -or
        -not [Environment]::Is64BitProcess) { throw 'Use Windows PowerShell 5.1 x64 on Windows. No settings were changed.' }
    Assert-ExovanceProcessorGroups -GroupCount (Get-ExovanceProcessorGroupCount)
    if ($RequireAdministrator) {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run Exovance Device Tweaker v2 as Administrator.' }
    }
}

function Reset-ExovanceWriteFailures {
    $script:ExovanceWriteFailures = [System.Collections.Generic.List[string]]::new()
}
function Add-ExovanceWriteFailure {
    param([string]$Message)
    if ($null -eq $script:ExovanceWriteFailures) { Reset-ExovanceWriteFailures }
    $script:ExovanceWriteFailures.Add($Message)
    Set-ExovanceUiFeedback -State Error -Text 'Action incomplete - review error details'
    Write-Warning $Message
}
function Assert-ExovanceWritesSucceeded {
    if ($null -ne $script:ExovanceWriteFailures -and $script:ExovanceWriteFailures.Count -gt 0) {
        throw ('One or more settings failed. Already applied changes were not rolled back. ' + ($script:ExovanceWriteFailures -join '; '))
    }
}

function Get-ExovanceRegistryState {
    param([string]$RegistryPath, [string]$Name)
    $relative = Get-RelativeRegistryPath $RegistryPath
    if ([string]::IsNullOrWhiteSpace($relative)) { throw 'Invalid registry path.' }
    $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($relative, $false)
    try {
        if ($null -eq $key -or $key.GetValueNames() -notcontains $Name) {
            return [pscustomobject]@{Name=$Name; Present=$false; Kind=$null; Value=$null}
        }
        return [pscustomobject]@{
            Name=$Name; Present=$true; Kind=$key.GetValueKind($Name).ToString()
            Value=$key.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        }
    } finally { if ($null -ne $key) { $key.Dispose() } }
}

function Set-ExovanceRegistryState {
    param([string]$RegistryPath, [Parameter(Mandatory=$true)]$State)
    $relative = Get-RelativeRegistryPath $RegistryPath
    if ([string]::IsNullOrWhiteSpace($relative)) { throw 'Invalid registry path.' }
    # Deleting an absent value must not create a registry key.
    $key = if ($State.Present) { [Microsoft.Win32.Registry]::LocalMachine.CreateSubKey($relative) }
           else { [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($relative, $true) }
    try {
        if ($null -eq $key) {
            if ($State.Present) { throw ('Cannot open registry key: ' + $RegistryPath) }
            return
        }
        if (-not $State.Present) { $key.DeleteValue([string]$State.Name, $false); return }
        $kind = [Microsoft.Win32.RegistryValueKind][Enum]::Parse([Microsoft.Win32.RegistryValueKind], [string]$State.Kind, $true)
        $value = $State.Value
        switch ($kind) {
            DWord { $value = [int]$value }
            QWord { $value = [long]$value }
            Binary { $value = [byte[]]$value }
            MultiString { $value = [string[]]$value }
            default { $value = [string]$value }
        }
        $key.SetValue([string]$State.Name, $value, $kind)
    } finally { if ($null -ne $key) { $key.Dispose() } }
}

function Set-ExovanceRegistryValue {
    param([string]$RegistryPath, [string]$Name, $Value, [string]$Kind='String')
    Set-ExovanceRegistryState -RegistryPath $RegistryPath -State ([pscustomobject]@{Name=$Name; Present=$true; Kind=$Kind; Value=$Value})
}

function Get-ExovanceRssKeywords {
    return @('*RssBaseProcNumber','*NumRssQueues','*RssBaseProcGroup','*RssMaxProcNumber','*RssMaxProcGroup','*MaxRssProcessors','*NumaNodeId')
}
function Get-ExovanceRssSnapshot {
    param([string]$RegistryPath)
    foreach ($name in (Get-ExovanceRssKeywords)) { Get-ExovanceRegistryState -RegistryPath $RegistryPath -Name $name }
}
function Restore-ExovanceRssSnapshot {
    param([string]$RegistryPath, [object[]]$Snapshot)
    $expected = @(Get-ExovanceRssKeywords)
    $names = @($Snapshot | ForEach-Object { [string]$_.Name })
    if ($names.Count -ne $expected.Count -or @($names | Select-Object -Unique).Count -ne $expected.Count) { throw 'Incomplete RSS snapshot; nothing was restored.' }
    # Validate all entries before writing any value from an imported backup.
    foreach ($state in $Snapshot) {
        if ($expected -notcontains [string]$state.Name -or $state.Present -isnot [bool]) { throw 'Invalid RSS snapshot entry.' }
        if ($state.Present -and @('String','DWord') -notcontains [string]$state.Kind) { throw 'Unsupported RSS snapshot registry type.' }
        if ($state.Present -and $state.Kind -eq 'DWord') { $null = [int]$state.Value }
    }
    try {
        foreach ($state in $Snapshot) { Set-ExovanceRegistryState -RegistryPath $RegistryPath -State $state }
    } catch { Add-ExovanceWriteFailure ('RSS restore: ' + $_.Exception.Message); throw }
}

function Get-ExovanceRssPlan {
    param([int]$BaseProcessor, [int]$QueueCount, [int]$LogicalCount, [hashtable]$PhysicalCoreMap=@{})
    if ($LogicalCount -lt 1 -or $LogicalCount -gt 64 -or $BaseProcessor -lt 0 -or $BaseProcessor -ge $LogicalCount) { throw 'RSS processor is outside the supported group 0 topology.' }
    if ($QueueCount -lt 1) { throw 'RSS queue count must be positive.' }
    $processors = [System.Collections.Generic.List[int]]::new()
    $physical = @{}
    for ($cpu = $BaseProcessor; $cpu -lt $LogicalCount; $cpu++) {
        $unit = if ($PhysicalCoreMap.ContainsKey($cpu)) { [int]$PhysicalCoreMap[$cpu] } else { $cpu }
        if (-not $physical.ContainsKey($unit)) {
            $processors.Add($cpu); $physical[$unit]=$true
            if ($processors.Count -eq $QueueCount) { break }
        }
    }
    if ($processors.Count -lt $QueueCount) { throw 'Not enough physical cores at or above the selected RSS base. Reduce queues or choose an earlier base.' }
    return [pscustomobject]@{BaseProcessor=$BaseProcessor; MaxProcessor=$processors[$processors.Count-1]; Processors=$processors.ToArray(); QueueCount=$QueueCount}
}

function Set-ExovanceRssConfiguration {
    param([string]$RegistryPath, [int]$BaseProcessor, [int]$QueueCount=1)
    try {
        $plan = Get-ExovanceRssPlan -BaseProcessor $BaseProcessor -QueueCount $QueueCount -LogicalCount $script:cachedLogicalCount -PhysicalCoreMap $script:PhysicalCoreIdByLogicalProcessor
        # Preserve driver NUMA preferences instead of forcing NUMA node zero.
        $profile = Get-ExovanceRegistryState -RegistryPath $RegistryPath -Name '*RSSProfile'
        if ($profile.Present -and [int]$profile.Value -eq 6) { throw 'RSS Balanced manages processor selection; manual processor bounds are not supported. Choose a compatible RSS profile in adapter settings first.' }
        $before = @(Get-ExovanceRssSnapshot $RegistryPath)
        $values = [ordered]@{
            '*RssBaseProcNumber'=[string]$plan.BaseProcessor; '*NumRssQueues'=[string]$plan.QueueCount
            '*RssBaseProcGroup'='0'; '*RssMaxProcGroup'='0'
            '*MaxRssProcessors'=[string]$plan.Processors.Count; '*RssMaxProcNumber'=[string]$plan.MaxProcessor
        }
        try {
            foreach ($name in $values.Keys) { Set-ExovanceRegistryValue -RegistryPath $RegistryPath -Name $name -Value $values[$name] }
        } catch {
            $cause = $_.Exception.Message
            try { Restore-ExovanceRssSnapshot -RegistryPath $RegistryPath -Snapshot $before } catch { Add-ExovanceWriteFailure ('RSS rollback failed: ' + $_.Exception.Message) }
            throw ('RSS configuration failed: ' + $cause)
        }
        return $plan
    } catch { Add-ExovanceWriteFailure ('RSS: ' + $_.Exception.Message); throw }
}

function Set-ExovanceUiFeedback {
    param([ValidateSet('Ready','Changed','Working','Applied','Error')][string]$State, [string]$Text)
    if ($State -eq 'Applied' -and $null -ne $script:ExovanceWriteFailures -and $script:ExovanceWriteFailures.Count -gt 0) {
        $State = 'Error'; $Text = 'Action incomplete - review error details'
    }
    $script:ExovanceUiState = $State
    $script:ExovanceUiMessage = $Text
    if ($null -ne $script:ExovanceFeedbackItem) {
        $color = switch ($State) {
            'Changed' { [System.Drawing.Color]::FromArgb(255,200,113) }
            'Working' { [System.Drawing.Color]::FromArgb(166,150,255) }
            'Applied' { [System.Drawing.Color]::FromArgb(83,235,195) }
            'Error' { [System.Drawing.Color]::FromArgb(255,126,145) }
            default { [System.Drawing.Color]::FromArgb(154,173,194) }
        }
        $script:ExovanceFeedbackItem.Text = $Text
        $script:ExovanceFeedbackItem.ForeColor = $color
    }
}
