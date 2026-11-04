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
        else {
            Write-Host ('[Exovance] Read only: {0} (virtual, non-PCI or unverified network adapter; no IRQ/MSI/RSS writes).' -f $device.DisplayName) -ForegroundColor DarkYellow
            Write-ExovanceLogEvent -Code NetworkWriteSkipped -Stage Plan -DevicePath ([string]$device.ConfigPath) -Message ([string]$device.DisplayName+': запись пропущена — адаптер только для просмотра')
        }
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
    param([string]$Message, [string]$DevicePath='', [string]$Setting='')
    if ($null -eq $script:ExovanceWriteFailures) { Reset-ExovanceWriteFailures }
    $script:ExovanceWriteFailures.Add($Message)
    Write-ExovanceLogEvent -Level Error -Code WriteFailure -Stage Write -DevicePath $DevicePath -Message $Message -Data ([ordered]@{Setting=$Setting})
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
        Write-ExovanceSettingAccepted -DevicePath $RegistryPath -Setting 'RSS' -Value ('base='+$plan.BaseProcessor+'; max='+$plan.MaxProcessor+'; queues='+$plan.QueueCount)
        return $plan
    } catch { Add-ExovanceWriteFailure -DevicePath $RegistryPath -Setting 'RSS' ('RSS: ' + $_.Exception.Message); throw }
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

# Structured diagnostics only. These functions never change device settings.
function Initialize-ExovanceLogSession {
    param([string]$Directory, [string]$AppPath, [switch]$Disabled)
    $script:ExovanceLogSession=$null
    if($Disabled){return}
    try {
        $id=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)
        $sessionDirectory=Join-Path $Directory $id
        $null=[IO.Directory]::CreateDirectory($sessionDirectory)
        $latest=Join-Path $Directory 'logging.txt'
        if([IO.File]::Exists($latest)) {
            $reader=[IO.File]::OpenText($latest)
            try {$first=$reader.ReadLine()} finally {$reader.Dispose()}
            if($first -notlike 'EXOVANCE LOG V2 | *') {
                # Keep the old append-only discovery log on the first upgrade.
                [IO.File]::Move($latest,(Join-Path $sessionDirectory 'legacy-logging.txt'))
            }
        }
        $hash='unknown';$coreHash='unknown'
        if($AppPath -and [IO.File]::Exists($AppPath)){
            $hash=(Get-FileHash -LiteralPath $AppPath -Algorithm SHA256).Hash
            $corePath=Join-Path (Split-Path -Parent $AppPath) 'Exovance.Core.ps1'
            if([IO.File]::Exists($corePath)){$coreHash=(Get-FileHash -LiteralPath $corePath -Algorithm SHA256).Hash}
        }
        $script:ExovanceLogSession=[pscustomobject]@{
            Host=([Environment]::OSVersion.VersionString+' | PowerShell '+$PSVersionTable.PSVersion+' '+$PSVersionTable.PSEdition+' | x64='+[Environment]::Is64BitProcess);Id=$id;Started=[DateTimeOffset]::Now.ToString('o');Updated='';AppHash=$hash;CoreHash=$coreHash
            Directory=$sessionDirectory;LatestPath=$latest;ReportPath=(Join-Path $sessionDirectory 'report.txt')
            EventsPath=(Join-Path $sessionDirectory 'events.jsonl');DiscoveryPath=(Join-Path $sessionDirectory 'discovery.txt')
            Events=[Collections.Generic.List[object]]::new();Actions=[Collections.Generic.List[object]]::new()
            ActiveAction=$null;Devices=@();LogicalCount=0;PhysicalCount=0;DiscoveryComplete=$false;Closed=$false;IoWarningShown=$false;IoError='';SeenDiscoveryLogErrors=[Collections.Generic.HashSet[string]]::new()
        }
        Write-ExovanceLogEvent -Level Info -Code SessionStarted -Stage Startup -Message 'Программа запущена. Применение настроек ещё не запускалось.'
        Save-ExovanceLogReport -ClaimLatest
    } catch {
        $script:ExovanceLogSession=$null
        Write-Warning ('Не удалось создать журнал Exovance: '+$_.Exception.Message)
    }
}

function Write-ExovanceLogEvent {
    param([ValidateSet('Info','Warning','Error')][string]$Level='Info', [string]$Code, [string]$Stage='Action', [string]$Message, [string]$DevicePath='', $Data=$null)
    $session=$script:ExovanceLogSession
    if($null -eq $session){return}
    try {
        $actionId=if($session.ActiveAction){$session.ActiveAction.Id}else{''}
        $event=[pscustomobject][ordered]@{Time=[DateTimeOffset]::Now.ToString('o');Session=$session.Id;Action=$actionId;Level=$Level;Code=$Code;Stage=$Stage;DevicePath=$DevicePath;Message=($Message -replace '[\x00-\x1f\x7f]',' ');Data=$Data}
        $session.Events.Add($event)
        if($session.ActiveAction -and $Code -eq 'SettingWriteAccepted'){$session.ActiveAction.Writes++}
        # Each run has its own file. No errors inferred from the word "failed" in discovery text.
        [IO.File]::AppendAllText($session.EventsPath,((ConvertTo-Json -InputObject $event -Depth 12 -Compress)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))
    } catch { Show-ExovanceLogIoWarning $_.Exception.Message }
}

function Show-ExovanceLogIoWarning {
    param([string]$Message)
    if($null -eq $script:ExovanceLogSession -or -not $script:ExovanceLogSession.IoWarningShown) {
        if($null -ne $script:ExovanceLogSession){$script:ExovanceLogSession.IoWarningShown=$true;$script:ExovanceLogSession.IoError=$Message}
        Write-Warning ('Журнал Exovance недоступен: '+$Message)
        if($null -ne $script:ExovanceLogBadge){try{$script:ExovanceLogBadge.Text='Логи: ошибка сохранения';$script:ExovanceLogBadge.ForeColor=[Drawing.Color]::FromArgb(255,126,145)}catch{}}
    }
}

function Start-ExovanceLoggedAction {
    param([string]$Name)
    $s=$script:ExovanceLogSession
    if($null -eq $s){return}
    if($s.ActiveAction){Complete-ExovanceLoggedAction -State Error -Text 'Предыдущее действие не завершено.'}
    Save-ExovanceLogReport # Drain diagnostics from the previous action before assigning a new ID.
    $action=[pscustomobject]@{Id=[guid]::NewGuid().ToString('N').Substring(0,8);Name=$Name;Started=[DateTimeOffset]::Now.ToString('o');Finished='';Outcome='Выполняется';State='Working';Message='';Writes=0;Before=@();Changes=@()}
    $s.Actions.Add($action);$s.ActiveAction=$action
    Write-ExovanceLogEvent -Code ActionStarted -Message ('Начато: '+$Name)
    Save-ExovanceLogReport
}

function Complete-ExovanceLoggedAction {
    param([string]$State, [string]$Text)
    $s=$script:ExovanceLogSession
    if($null -eq $s -or $null -eq $s.ActiveAction){return}
    $action=$s.ActiveAction
    $errors=@($s.Events | Where-Object {$_.Action -eq $action.Id -and $_.Level -eq 'Error'})
    $action.State=$State;$action.Message=$Text;$action.Finished=[DateTimeOffset]::Now.ToString('o')
    $level='Info'
    if($State -eq 'Error' -or $errors.Count -gt 0){$action.Outcome='Завершено с ошибками; возможны частичные изменения';$level='Error'}
    elseif($State -eq 'Applied'){$action.Outcome='Действие завершено без зарегистрированных ошибок'}
    elseif($action.Writes -gt 0 -or $action.Changes.Count -gt 0){$action.Outcome='Результат не подтверждён; часть записей выполнена';$level='Warning'}
    else{$action.Outcome='Отменено / настройки устройств не записывались'}
    Write-ExovanceLogEvent -Level $level -Code ActionFinished -Message ($action.Name+': '+$action.Outcome) -Data ([ordered]@{State=$State;WriteRequests=$action.Writes;DriverVerified=$false;Details=$Text;Changes=$action.Changes})
    $s.ActiveAction=$null
    Save-ExovanceLogReport
}

function Write-ExovanceSettingAccepted {
    param([string]$DevicePath,[string]$Setting,[AllowNull()]$Value)
    if($null -eq $script:ExovanceLogSession){return}
    # API success is not presented as proof of effective ISR/DPC/RSS routing.
    $display=if($null -eq $Value){'<удалить / не задано>'}elseif($Value -is [byte[]]){'0x'+([BitConverter]::ToString($Value).Replace('-',''))}else{[string]$Value}
    Write-ExovanceLogEvent -Code SettingWriteAccepted -Stage Write -DevicePath $DevicePath -Message ($Setting+' = '+$display) -Data ([ordered]@{Setting=$Setting;Requested=$display;SetterReturnedSuccess=$true;RegistryCompared=$false;DriverVerified=$false})
}

function Format-ExovanceLogRegistryState {
    param([object]$State,[switch]$Affinity)
    if(-not $State.Present){return '<не задано>'}
    if($State.Value -is [byte[]]) {
        if($Affinity -and $State.Value.Length -le 8) {
            $bytes=[byte[]]::new(8);[Array]::Copy([byte[]]$State.Value,$bytes,$State.Value.Length)
            return '0x'+([BitConverter]::ToUInt64($bytes,0)).ToString('X')
        }
        return [BitConverter]::ToString($State.Value)
    }
    return [string]$State.Value
}

function Update-ExovanceDeviceLogSnapshot {
    param([System.Collections.IEnumerable]$Devices,[int]$LogicalCount,[int]$PhysicalCount,[switch]$Discovery,[ValidateSet('Before','After','Startup')][string]$Phase='Startup')
    $s=$script:ExovanceLogSession
    if($null -eq $s){return}
    $s.LogicalCount=$LogicalCount;$s.PhysicalCount=$PhysicalCount
    $rows=[Collections.Generic.List[object]]::new()
    foreach($device in $Devices) {
        if($null -eq $device){continue}
        $network=$device.Category -eq 'Network'
        $writable=-not $network -or (Test-ExovanceNetworkWritable $device)
        $path=if($network -and $device.ConfigPath){[string]$device.ConfigPath}else{[string]$device.RegistryPath}
        $row=[pscustomobject][ordered]@{Name=[string]$device.DisplayName;Category=[string]$device.Category;Role=$(if($device.Category -eq 'USB' -and $device.Roles){$device.Roles -join '/'}else{[string]$device.Role});Path=$path;Writable=$writable;Mask='<не прочитано>';CPUs='<не прочитано>';Policy='<не прочитано>';MSI='<не прочитано>';Limit='<не прочитано>';Priority='<не прочитано>';RSS='';ClassPath=$(if($network){[string]$device.RegistryPath}else{''});ReadError=''}
        try {
            $affinity=$path.TrimEnd('\')+'\Device Parameters\Interrupt Management\Affinity Policy'
            $msi=$path.TrimEnd('\')+'\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties'
            $row.Mask=Format-ExovanceLogRegistryState (Get-ExovanceRegistryState $affinity 'AssignmentSetOverride') -Affinity
            $row.CPUs=Convert-ExovanceLogMaskToCpuList $row.Mask
            $row.Policy=Format-ExovanceLogRegistryState (Get-ExovanceRegistryState $affinity 'DevicePolicy')
            $row.Priority=Format-ExovanceLogRegistryState (Get-ExovanceRegistryState $affinity 'DevicePriority')
            $row.MSI=Format-ExovanceLogRegistryState (Get-ExovanceRegistryState $msi 'MSISupported')
            $row.Limit=Format-ExovanceLogRegistryState (Get-ExovanceRegistryState $msi 'MessageNumberLimit')
            if($network) {
                $rssValues=foreach($keyword in (Get-ExovanceRssKeywords)) {
                    $keyword+'='+(Format-ExovanceLogRegistryState (Get-ExovanceRegistryState $device.RegistryPath $keyword))
                }
                $row.RSS='RSS: '+($rssValues -join '; ')
            }
        } catch {
            $row.ReadError=$_.Exception.Message
            Write-ExovanceLogEvent -Level Warning -Code SnapshotReadUnavailable -Stage Snapshot -DevicePath $path -Message ($row.Name+': не удалось полностью прочитать текущие значения') -Data $row.ReadError
        }
        $rows.Add($row)
        if($Discovery -and -not $writable) {
            Write-ExovanceLogEvent -Code NetworkReadOnly -Stage Discovery -DevicePath $path -Message ($row.Name+': виртуальный, не-PCI или неподтверждённый адаптер; новые IRQ/MSI/RSS записи исключены')
        }
    }
    $s.Devices=$rows.ToArray()
    if($null -ne $s.ActiveAction) {
        if($Phase -eq 'Before'){$s.ActiveAction.Before=$s.Devices}
        if($Phase -eq 'After'){$s.ActiveAction.Changes=@(Compare-ExovanceLogSnapshots -Before $s.ActiveAction.Before -After $s.Devices)}
    }
    if($Discovery){$s.DiscoveryComplete=$true}
    Write-ExovanceLogEvent -Code DeviceSnapshot -Stage Snapshot -Message 'Прочитаны значения реестра; это не подтверждение маршрутизации драйвером.' -Data ([ordered]@{Phase=$Phase;Devices=$s.Devices})
    Save-ExovanceLogReport
}

function Get-ExovanceLogReport {
    param([object]$Session=$script:ExovanceLogSession)
    if($null -eq $Session){return 'Журнал отключён или не был создан.'}
    $errors=@($Session.Events|Where-Object {$_.Level -eq 'Error'})
    $warnings=@($Session.Events|Where-Object {$_.Level -eq 'Warning'})
    $status=if($Session.IoWarningShown){'НЕПОЛНЫЙ ЖУРНАЛ — ОШИБКА СОХРАНЕНИЯ'}elseif($errors.Count -gt 0){'ЕСТЬ ЗАРЕГИСТРИРОВАННЫЕ ОШИБКИ'}elseif($Session.ActiveAction){'ДЕЙСТВИЕ ВЫПОЛНЯЕТСЯ'}elseif($warnings.Count -gt 0){'ЕСТЬ ЗАМЕЧАНИЯ — ПРОЧИТАЙ ПОДРОБНОСТИ'}elseif($Session.Actions.Count -eq 0){'ТОЛЬКО ЗАПУСК — ПРИМЕНЕНИЕ НЕ ЗАПУСКАЛОСЬ'}else{'ЗАРЕГИСТРИРОВАННЫХ ОШИБОК НЕТ'}
    $lines=[Collections.Generic.List[string]]::new()
    foreach($line in @(
        ('EXOVANCE LOG V2 | '+$Session.Id),('СОСТОЯНИЕ: '+$status),
        ('Записей уровня Ошибка: {0}; Предупреждение: {1}' -f $errors.Count,$warnings.Count),
        ('Начало: '+$Session.Started),('Обновлено: '+[DateTimeOffset]::Now.ToString('o')),
        ('Среда: '+$Session.Host),('SHA256 программы: '+$Session.AppHash),('SHA256 Core: '+$Session.CoreHash),('Ошибка сохранения журнала: '+$Session.IoError),
        ('CPU: логических={0}; физических={1}; снимок устройств завершён={2}' -f $Session.LogicalCount,$Session.PhysicalCount,$Session.DiscoveryComplete),
        '','ОШИБКИ И ПРЕДУПРЕЖДЕНИЯ'
    )){$lines.Add($line)}
    if($errors.Count+$warnings.Count -eq 0){$lines.Add('Нет зарегистрированных записей этих уровней.')}
    foreach($event in @($Session.Events|Where-Object {$_.Level -ne 'Info'})){$lines.Add(('[{0}] {1} | {2} | {3}' -f $event.Level,$event.Time,$event.Code,$event.Message));if($event.DevicePath){$lines.Add('  '+$event.DevicePath)}}
    $lines.Add('');$lines.Add('ДЕЙСТВИЯ ЭТОГО СЕАНСА')
    if($Session.Actions.Count -eq 0){$lines.Add('Apply / Auto / Alternate / Backup / Reset не запускались.')}
    foreach($action in $Session.Actions){$lines.Add(('{0} | {1} | успешных запросов: {2} | {3}' -f $action.Name,$action.Outcome,$action.Writes,$action.Message))}
    if($Session.Actions.Count -gt 0) {
        $latestAction=$Session.Actions[$Session.Actions.Count-1]
        $lines.Add('');$lines.Add('ИЗМЕНЕНИЯ ПОСЛЕДНЕГО ДЕЙСТВИЯ — по прочитанным значениям реестра')
        if($latestAction.Changes.Count -eq 0){$lines.Add('Различий в охваченных читаемых параметрах не зафиксировано. Это не доказательство отсутствия других изменений.')}
        foreach($change in $latestAction.Changes){$lines.Add(('{0} | {1}: {2} -> {3}' -f $change.Device,$change.Setting,$change.Before,$change.After))}
    }
    $lines.Add('');$lines.Add('СНИМОК УСТРОЙСТВ И ПРОЧИТАННЫХ ПАРАМЕТРОВ')
    foreach($device in $Session.Devices){
        $access=if($device.Writable){'доступен для настройки'}else{'ТОЛЬКО ПРОСМОТР — новые аппаратные записи запрещены'}
        $lines.Add(('{0} [{1}/{2}] — {3}' -f $device.Name,$device.Category,$device.Role,$access))
        $lines.Add(('  IRQ mask={0}; логические CPU={1}; policy={2}; priority={3}; MSI={4}; MessageNumberLimit={5}' -f $device.Mask,$device.CPUs,$device.Policy,$device.Priority,$device.MSI,$device.Limit))
        if($device.RSS){$lines.Add('  '+$device.RSS)}
        $lines.Add('  '+$device.Path)
        if($device.Category -eq 'Network'){$lines.Add('  RSS class path: '+$device.ClassPath)}
        if($device.ReadError){$lines.Add('  Не полностью прочитано: '+$device.ReadError)}
    }
    $lines.Add('');$lines.Add('СОБЫТИЯ И ПРИНЯТЫЕ ЗАПРОСЫ ЗАПИСИ')
    foreach($event in $Session.Events){if($event.Code -ne 'DeviceSnapshot'){$lines.Add(('{0} [{1}] {2}/{3} | {4} | {5}' -f $event.Time,$event.Level,$event.Stage,$event.Code,$event.DevicePath,$event.Message))}}
    $lines.Add('');$lines.Add('ПРИМЕЧАНИЯ')
    $lines.Add('Область отчёта: Apply / Auto / Alternate / Backup / Reset и обнаружение устройств. Другие служебные операции могут иметь собственную диагностику.')
    $lines.Add('Успех функции записи и значения реестра не доказывают фактическую маршрутизацию ISR/DPC/RSS драйвером. Проверка задержек и производительности не выполнялась.')
    $lines.Add('IRQ policy: 0=MachineDefault; 1=AllCloseProcessors; 2=OneCloseProcessor; 3=AllProcessors; 4=SpecCPU; 5=SpreadMessages. MSI: 1=включено, 0=выключено; <не задано> не равно 0.')
    $lines.Add('Пропуск виртуальных адаптеров и дополнительных HID-интерфейсов сам по себе не является ошибкой.')
    $lines.Add('Частота по bInterval — расчёт USB-дескриптора, а не измерение текущей частоты опроса.')
    $lines.Add('MessageNumberLimit=<не задано> означает отсутствие явного ограничения в реестре, а не бесконечное число векторов.')
    $lines.Add('JSON-события: '+$Session.EventsPath);$lines.Add('Полное обнаружение: '+$Session.DiscoveryPath);$lines.Add('Отчёт сеанса: '+$Session.ReportPath)
    return $lines -join [Environment]::NewLine
}

function Save-ExovanceLogReport {
    param([switch]$ClaimLatest)
    $s=$script:ExovanceLogSession
    if($null -eq $s){return}
    try {
        $queue=$null
        if($null -ne $script:DeviceTweakerAsyncLogState){$queue=$script:DeviceTweakerAsyncLogState.Errors}
        if($null -ne $queue) {
            $issue=$null
            while($queue.TryDequeue([ref]$issue)) {
                if($s.SeenDiscoveryLogErrors.Add([string]$issue)) { Write-ExovanceLogEvent -Level Warning -Code DiscoveryLogWriteFailed -Stage Logging -Message ('Часть подробного журнала могла не сохраниться: '+[string]$issue) }
                $issue=$null
            }
        }
        $shieldType='WinFormsUnhandledExceptionShield' -as [type]
        if($null -ne $shieldType) {
            $uiErrors=$shieldType::Diagnostics
            $uiIssue=$null
            while($uiErrors.TryDequeue([ref]$uiIssue)) {
                Write-ExovanceLogEvent -Level Error -Code UnhandledUiException -Stage UI -Message $uiIssue
                $uiIssue=$null
            }
        }
        $report=Get-ExovanceLogReport $s
        # Per-session history stays available even if another instance owns logging.txt.
        foreach($path in @($s.ReportPath,$s.LatestPath)) {
            if($path -eq $s.LatestPath -and -not $ClaimLatest -and [IO.File]::Exists($path)) {
                $reader=[IO.File]::OpenText($path)
                try{$owner=$reader.ReadLine()}finally{$reader.Dispose()}
                if($owner -ne ('EXOVANCE LOG V2 | '+$s.Id)){continue}
            }
            $temp=$path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
            $backup=$temp+'.bak'
            try {
                [IO.File]::WriteAllText($temp,$report,[Text.UTF8Encoding]::new($false))
                if([IO.File]::Exists($path)){[IO.File]::Replace($temp,$path,$backup)}else{[IO.File]::Move($temp,$path)}
            } finally {
                if([IO.File]::Exists($temp)){[IO.File]::Delete($temp)}
                if([IO.File]::Exists($backup)){[IO.File]::Delete($backup)}
            }
        }
        if($null -ne $script:ExovanceLogBadge) {
            $errors=@($s.Events|Where-Object {$_.Level -eq 'Error'}).Count
            $warnings=@($s.Events|Where-Object {$_.Level -eq 'Warning'}).Count
            $script:ExovanceLogBadge.Text=if($s.IoWarningShown){'Логи: ошибка сохранения'}elseif($s.ActiveAction){'Логи: выполняется'}elseif($errors){'Логи: есть ошибки'}elseif($warnings){'Логи: есть замечания'}elseif($s.Actions.Count -eq 0){'Логи: только запуск'}else{'Логи: без ошибок'}
            $script:ExovanceLogBadge.ForeColor=if($errors -or $s.IoWarningShown){[Drawing.Color]::FromArgb(255,126,145)}elseif($warnings){[Drawing.Color]::FromArgb(255,200,113)}else{[Drawing.Color]::FromArgb(83,235,195)}
        }
    } catch { Show-ExovanceLogIoWarning $_.Exception.Message }
}

function Close-ExovanceLogSession {
    $s=$script:ExovanceLogSession
    if($null -eq $s -or $s.Closed){return}
    if($s.ActiveAction){Complete-ExovanceLoggedAction Error 'Программа закрывается с незавершённым действием.'}
    Write-ExovanceLogEvent -Code SessionClosed -Stage Shutdown -Message 'Сеанс закрыт.'
    $s.Closed=$true
    Save-ExovanceLogReport
}

function Write-ExovanceDialogLog {
    param([object]$Icon,[string]$Title,[string]$Message)
    $level=if([string]$Icon -match '^(?i:Error|Hand|Stop|16)$'){'Error'}elseif([string]$Icon -match '^(?i:Warning|Exclamation|48)$'){'Warning'}else{''}
    if($level -ne '') {
        Write-ExovanceLogEvent -Level $level -Code DialogDiagnostic -Stage Dialog -Message ($Title+': '+$Message)
        Save-ExovanceLogReport
    }
}

function Compare-ExovanceLogSnapshots {
    param([object[]]$Before,[object[]]$After)
    $lookup=@{}
    foreach($row in $Before){$lookup[([string]$row.Path+'|'+[string]$row.Category+'|'+[string]$row.Name)]=$row}
    foreach($row in $After) {
        $old=$lookup[([string]$row.Path+'|'+[string]$row.Category+'|'+[string]$row.Name)]
        if($null -eq $old -or $old.ReadError -or $row.ReadError){continue}
        foreach($field in @('Mask','Policy','Priority','MSI','Limit','RSS')) {
            if([string]$old.$field -cne [string]$row.$field){[pscustomobject]@{Device=$row.Name;Path=$row.Path;Setting=$field;Before=[string]$old.$field;After=[string]$row.$field}}
        }
    }
}

function Convert-ExovanceLogMaskToCpuList {
    param([string]$Mask)
    if($Mask -notmatch '^0x[0-9a-fA-F]{1,16}$'){return '<не задано / недоступно>'}
    [uint64]$value=[Convert]::ToUInt64($Mask.Substring(2),16)
    $cpus=@(for($cpu=0;$cpu -lt 64;$cpu++){if(($value -band ([uint64]1 -shl $cpu)) -ne 0){$cpu}})
    if($cpus.Count -eq 0){return '<пустая маска>'}
    return $cpus -join ', '
}
