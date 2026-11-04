# Filesystem-only logging tests. No real registry, driver, or hardware writes.
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$folder=Join-Path $repo 'DEVICE-TWEAKER-V2'
. (Join-Path $folder 'Exovance.Core.ps1')
$script:Passed=0
function Assert-True {param([bool]$Condition,[string]$Message)if(-not $Condition){throw $Message}}
function Test-Case {
    param([string]$Name,[scriptblock]$Body)
    try{& $Body;$script:Passed++;Write-Host ('PASS: '+$Name)}
    catch{Write-Host ('::error title={0}::{1}' -f $Name,($_.Exception.Message -replace '[\r\n]+',' '));throw}
}
$t=$null;$e=$null
$app=[Management.Automation.Language.Parser]::ParseFile((Join-Path $folder 'Exovance-DeviceTweaker-v2.ps1'),[ref]$t,[ref]$e)
Assert-True ($e.Count -eq 0) ('App parse failed: '+($e -join ';'))
foreach($name in @('Set-DeviceAffinity','Clear-DeviceAffinity','Set-DevicePriority','Convert-DeviceTweakerAffinityMaskToUInt64')){
    $fn=$app.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
    . ([scriptblock]::Create($fn.Extent.Text))
}
function Test-LogFixture {
    param([scriptblock]$Body)
    $dir=Join-Path ([IO.Path]::GetTempPath()) ('Exovance logs '+[guid]::NewGuid().ToString('N'))
    $script:ExovanceLogBadge=$null;$script:ExovanceLogSession=$null
    $script:DeviceTweakerAsyncLogState=$null
    Reset-ExovanceWriteFailures
    try{& $Body $dir}
    finally{$script:ExovanceLogSession=$null;if([IO.Directory]::Exists($dir)){Remove-Item -LiteralPath $dir -Recurse -Force}}
}
Test-Case 'disabled logs create no files or directories' {
    Test-LogFixture {param($dir)
        Initialize-ExovanceLogSession $dir -Disabled
        Start-ExovanceLoggedAction 'Apply'
        Write-ExovanceLogEvent -Level Error -Code Fixture -Message 'Ignored'
        Close-ExovanceLogSession
        Assert-True (-not [IO.Directory]::Exists($dir)) 'Disabled diagnostics created files.'
    }
}
Test-Case 'startup reports no application instead of pretending optimization succeeded' {
    Test-LogFixture {param($dir)
        Initialize-ExovanceLogSession $dir
        $s=$script:ExovanceLogSession
        $report=[IO.File]::ReadAllText($s.LatestPath)
        Assert-True ($report.Contains('ТОЛЬКО ЗАПУСК') -and $report.Contains('не запускались')) 'Startup falsely reports applied settings.'
        $event=ConvertFrom-Json ([IO.File]::ReadAllText($s.EventsPath))
        Assert-True ($event.Code -eq 'SessionStarted' -and $event.Session -eq $s.Id) 'Invalid JSON event envelope.'
        Assert-True ($s.Id -match '^\d{8}-\d{6}-[a-f0-9]{8}$') 'Session identifier is ambiguous.'
    }
}
Test-Case 'legacy append-only log is preserved on migration' {
    Test-LogFixture {param($dir)
        $null=[IO.Directory]::CreateDirectory($dir)
        $legacy='[old] retained history'+[Environment]::NewLine+'second line'
        [IO.File]::WriteAllText((Join-Path $dir 'logging.txt'),$legacy)
        Initialize-ExovanceLogSession $dir
        Assert-True ([IO.File]::ReadAllText((Join-Path $script:ExovanceLogSession.Directory 'legacy-logging.txt')) -ceq $legacy) 'Legacy data lost.'
    }
}
Test-Case 'session files stay separate and older instances cannot overwrite latest summary' {
    Test-LogFixture {param($dir)
        Initialize-ExovanceLogSession $dir
        $first=$script:ExovanceLogSession
        Initialize-ExovanceLogSession $dir
        $second=$script:ExovanceLogSession
        Assert-True ($first.Id -ne $second.Id -and [IO.File]::Exists($first.ReportPath)) 'New session replaced history.'
        $expected=[IO.File]::ReadAllText($second.LatestPath)
        $script:ExovanceLogSession=$first
        Write-ExovanceLogEvent -Code OlderSession -Message 'Older session continues'
        Save-ExovanceLogReport
        Assert-True ([IO.File]::ReadAllText($second.LatestPath) -ceq $expected) 'Older instance stole latest summary.'
    }
}
Test-Case 'cancelled action records no successful write requests' {
    Test-LogFixture {param($dir)
        Initialize-ExovanceLogSession $dir
        Start-ExovanceLoggedAction 'Auto-Optimization'
        Complete-ExovanceLoggedAction Ready 'Cancelled'
        $action=$script:ExovanceLogSession.Actions[0]
        Assert-True ($action.Writes -eq 0 -and $action.Outcome.StartsWith('Отменено')) 'Cancel was reported as apply.'
    }
}
Test-Case 'real affinity setter records its target and mask without hardware writes' {
    Test-LogFixture {param($dir)
        Initialize-ExovanceLogSession $dir
        $script:cachedLogicalCount=16
        $script:FakeValues=@{}
        function Set-ExovanceRegistryState {param($RegistryPath,$State)$script:FakeValues[$State.Name]=$State}
        Start-ExovanceLoggedAction 'Apply'
        Assert-True (Set-DeviceAffinity 'HKLM:\FAKE-DEVICE' '500') 'Mock setter failed.'
        Complete-ExovanceLoggedAction Applied 'Done'
        $events=@($script:ExovanceLogSession.Events|Where-Object {$_.Code -eq 'SettingWriteAccepted'})
        Assert-True ($events.Count -eq 1 -and $events[0].DevicePath -eq 'HKLM:\FAKE-DEVICE' -and $events[0].Message.Contains('0x500')) 'Write target/mask missing.'
        Assert-True (-not $events[0].Data.DriverVerified -and -not $events[0].Data.RegistryCompared) 'Setter success falsely claims driver verification.'
        Assert-True ([BitConverter]::ToUInt64($script:FakeValues.AssignmentSetOverride.Value,0) -eq 1280) 'Instrumentation changed the actual mask.'
    }
}
Test-Case 'write errors remain visible even when a caller requests Applied' {
    Test-LogFixture {param($dir)
        Initialize-ExovanceLogSession $dir
        $script:cachedLogicalCount=16
        function Set-ExovanceRegistryState {param($RegistryPath,$State)throw 'Simulated access denied'}
        Start-ExovanceLoggedAction 'Apply'
        Assert-True (-not (Set-DeviceAffinity 'HKLM:\FAKE-DEVICE' '1')) 'Write failure became success.'
        Complete-ExovanceLoggedAction Applied 'Caller tried to report success'
        $s=$script:ExovanceLogSession
        Assert-True ($s.Actions[0].Outcome.Contains('ошибками')) 'Failure reported as clean completion.'
        $failure=@($s.Events|Where-Object {$_.Code -eq 'WriteFailure'})[0]
        Assert-True ($failure.Level -eq 'Error' -and $failure.DevicePath -eq 'HKLM:\FAKE-DEVICE') 'Error target missing.'
        Assert-True ([IO.File]::ReadAllText($s.LatestPath).Contains('ЕСТЬ ЗАРЕГИСТРИРОВАННЫЕ ОШИБКИ')) 'Latest file hides failure.'
    }
}
Test-Case 'snapshot preserves absent versus zero and marks virtual adapters read only' {
    Test-LogFixture {param($dir)
        Initialize-ExovanceLogSession $dir
        $script:ReadOnlyProbeWrites=0
        function Get-ExovanceRegistryState {
            param($RegistryPath,$Name)
            [pscustomobject]@{Name=$Name;Present=($Name -eq 'DevicePolicy');Kind='DWord';Value=0}
        }
        function Set-ExovanceRegistryState {param($RegistryPath,$State)$script:ReadOnlyProbeWrites++}
        $devices=@(
            [pscustomobject]@{DisplayName='Physical NIC';Category='Network';Role='NDIS';PNPID='PCI\VEN_10EC&DEV_8168\1';ConfigPath='HKLM:\SYSTEM\CurrentControlSet\Enum\PCI\VEN_10EC&DEV_8168\1';RegistryPath='HKLM:\FAKE-CLASS'},
            [pscustomobject]@{DisplayName='Happ Tunnel';Category='Network';Role='NDIS';PNPID='SWD\WINTUN\1';ConfigPath='HKLM:\SYSTEM\CurrentControlSet\Enum\SWD\WINTUN\1';RegistryPath='HKLM:\FAKE-CLASS2'}
        )
        Update-ExovanceDeviceLogSnapshot $devices 16 8 -Discovery
        $s=$script:ExovanceLogSession
        Assert-True ($s.Devices[0].Policy -eq '0' -and $s.Devices[0].Mask -eq '<не задано>') 'Missing value confused with zero.'
        Assert-True ($s.Devices[0].Writable -and -not $s.Devices[1].Writable) 'VPN incorrectly treated as writable hardware.'
        Assert-True (@($s.Events|Where-Object {$_.Level -eq 'Error'}).Count -eq 0) 'Expected virtual skip classified as error.'
        Assert-True ($script:ReadOnlyProbeWrites -eq 0) 'Snapshot changed settings.'
    }
}
Test-Case 'before and after snapshots report observed changes without claiming verified routing' {
    Test-LogFixture {param($dir)
        Initialize-ExovanceLogSession $dir
        $script:ObservedMask=[byte[]]@(1,0,0,0,0,0,0,0)
        function Get-ExovanceRegistryState {
            param($RegistryPath,$Name)
            [pscustomobject]@{Name=$Name;Present=($Name -eq 'AssignmentSetOverride');Kind='Binary';Value=$script:ObservedMask}
        }
        $devices=@([pscustomobject]@{DisplayName='GPU';Category='PCI';Role='GPU';RegistryPath='HKLM:\FAKE'})
        Start-ExovanceLoggedAction 'Apply'
        Update-ExovanceDeviceLogSnapshot $devices 16 8 -Phase Before
        $script:ObservedMask=[byte[]]@(0,5,0,0,0,0,0,0)
        Update-ExovanceDeviceLogSnapshot $devices 16 8 -Phase After
        Complete-ExovanceLoggedAction Applied 'Done'
        $change=$script:ExovanceLogSession.Actions[0].Changes[0]
        Assert-True ($change.Setting -eq 'Mask' -and $change.Before -eq '0x1' -and $change.After -eq '0x500') 'Registry diff is wrong.'
        Assert-True ((Get-ExovanceLogReport).Contains('не доказывают фактическую маршрутизацию')) 'Verification boundary missing.'
    }
}
Test-Case 'error dialog captures backup failure even without a registry failure' {
    Test-LogFixture {param($dir)
        Initialize-ExovanceLogSession $dir
        Start-ExovanceLoggedAction 'Backup'
        Write-ExovanceDialogLog -Icon Error -Title 'Backup Error' -Message 'Simulated disk full'
        Complete-ExovanceLoggedAction Ready 'No registry changes'
        Assert-True ($script:ExovanceLogSession.Actions[0].Outcome.Contains('ошибками')) 'Backup file error vanished.'
        Assert-True ((Get-ExovanceLogReport).Contains('Simulated disk full')) 'Detailed dialog message lost.'
    }
}
Test-Case 'classification text containing failed is information unless explicitly marked error' {
    Test-LogFixture {param($dir)
        Initialize-ExovanceLogSession $dir
        Write-ExovanceLogEvent -Code HidDiscovery -Stage Discovery -Message 'HIDClass check failed: expected ignored interface'
        Assert-True (@($script:ExovanceLogSession.Events|Where-Object {$_.Level -eq 'Error'}).Count -eq 0) 'Free-text keyword created a false error.'
    }
}
Test-Case 'JSONL uses valid UTF-8 and event messages cannot inject extra report lines' {
    Test-LogFixture {param($dir)
        Initialize-ExovanceLogSession $dir
        Write-ExovanceLogEvent -Level Warning -Code UnicodeFixture -Message "Клавиатура`nFAKE ERROR"
        $events=@([IO.File]::ReadAllLines($script:ExovanceLogSession.EventsPath)|ForEach-Object {ConvertFrom-Json $_})
        Assert-True ($events.Count -eq 2 -and $events[1].Message -eq 'Клавиатура FAKE ERROR') 'Message injected a report line or JSON broke.'
    }
}
Test-Case 'asynchronous discovery writer failures become visible diagnostics' {
    Test-LogFixture {param($dir)
        Initialize-ExovanceLogSession $dir
        $queue=[Collections.Concurrent.ConcurrentQueue[string]]::new()
        $queue.Enqueue('discovery.txt: simulated failure');$queue.Enqueue('discovery.txt: simulated failure')
        $script:DeviceTweakerAsyncLogState=@{Errors=$queue}
        Save-ExovanceLogReport
        $events=@($script:ExovanceLogSession.Events|Where-Object {$_.Code -eq 'DiscoveryLogWriteFailed'})
        Assert-True ($events.Count -eq 1 -and $events[0].Level -eq 'Warning') 'Async failure swallowed or duplicated.'
    }
}
Test-Case 'logging storage failure is visible and never throws into device operations' {
    Test-LogFixture {param($dir)
        Initialize-ExovanceLogSession $dir
        $s=$script:ExovanceLogSession
        $s.EventsPath=$s.Directory # Writing to a directory fails on Windows and Linux.
        Write-ExovanceSettingAccepted 'HKLM:\FAKE' 'MSI' '1'
        Assert-True $s.IoWarningShown 'Storage failure is silent.'
        Assert-True ((Get-ExovanceLogReport).Contains('НЕПОЛНЫЙ ЖУРНАЛ')) 'Broken logging is presented as healthy.'
    }
}
Test-Case 'clean close is logged and repeated close creates no duplicate events' {
    Test-LogFixture {param($dir)
        Initialize-ExovanceLogSession $dir
        Close-ExovanceLogSession;Close-ExovanceLogSession
        Assert-True (@($script:ExovanceLogSession.Events|Where-Object {$_.Code -eq 'SessionClosed'}).Count -eq 1) 'Session closed twice.'
        Assert-True (@(Get-ChildItem -LiteralPath $script:ExovanceLogSession.Directory -Filter '*.tmp').Count -eq 0) 'Atomic-write temporary files leaked.'
    }
}
Test-Case 'native exceptions become structured errors without invoking UI or hardware' {
    # Same queue contract as the embedded C# shield, without creating a window.
    Add-Type 'public static class WinFormsUnhandledExceptionShield { public static readonly System.Collections.Concurrent.ConcurrentQueue<string> Diagnostics = new System.Collections.Concurrent.ConcurrentQueue<string>(); }'
    Test-LogFixture {param($dir)
        Initialize-ExovanceLogSession $dir
        [WinFormsUnhandledExceptionShield]::Diagnostics.Enqueue('Simulated UI exception')
        Save-ExovanceLogReport
        Assert-True ((Get-ExovanceLogReport).Contains('Simulated UI exception')) 'Native exception lost.'
        Assert-True (@($script:ExovanceLogSession.Events|Where-Object {$_.Code -eq 'UnhandledUiException' -and $_.Level -eq 'Error'}).Count -eq 1) 'Native exception classified incorrectly.'
    }
}
Test-Case 'registry exceptions retain the actual cause and target' {
    Test-LogFixture {param($dir)
        Initialize-ExovanceLogSession $dir
        function Get-RelativeRegistryPath {param($Path)throw 'Simulated path lookup failure'}
        Assert-True (-not (Set-DevicePriority 'HKLM:\FAKE' 3)) 'Failed priority write became success.'
        $event=@($script:ExovanceLogSession.Events|Where-Object {$_.Code -eq 'WriteFailure'})[0]
        Assert-True ($event.DevicePath -eq 'HKLM:\FAKE' -and $event.Message.Contains('Simulated path lookup failure')) 'Actual exception replaced by generic failure.'
    }
}
Test-Case 'logical CPU display decodes high bits without wrapping' {
    Assert-True ((Convert-ExovanceLogMaskToCpuList '0x500') -eq '8, 10') 'Wrong CPU pair.'
    Assert-True ((Convert-ExovanceLogMaskToCpuList '0x8000000180000001') -eq '0, 31, 32, 63') 'CPU high bits wrapped.'
    Assert-True ((Convert-ExovanceLogMaskToCpuList '<не задано>') -eq '<не задано / недоступно>') 'Missing mask shown as CPU zero.'
}
Test-Case 'application routes discovery to the session and exposes a Logs link' {
    $source=$app.Extent.Text
    Assert-True ($source.Contains('$script:ExovanceLogSession.DiscoveryPath') -and $source.Contains('public HeaderSurfaceItem Logs;')) 'Application log integration missing.'
    Assert-True ($source.Contains('DescriptorPollingRate') -and -not $source.Contains('matched physical adapter')) 'Misleading discovery wording remains.'
    Assert-True ($source.Contains('Start-ExovanceLoggedAction -Name $Name') -and $source.Contains('Complete-ExovanceLoggedAction -State')) 'Action boundaries missing.'
}
Write-Host ('Device log checks: {0} passed. No real registry/hardware writes.' -f $script:Passed)
