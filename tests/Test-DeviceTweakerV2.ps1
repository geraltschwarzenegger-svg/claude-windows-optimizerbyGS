# No GUI or system tweaks. Extract actual app functions; mock only registry I/O.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$folder = Join-Path $repo 'DEVICE-TWEAKER-V2'
. (Join-Path $folder 'Exovance.Core.ps1')
$script:Passed = 0
function Assert-True { param([bool]$Condition, [string]$Message) if (-not $Condition) { throw $Message } }
function Test-Case {
    param([string]$Name, [scriptblock]$Body)
    try { & $Body; $script:Passed++; Write-Host ('PASS: ' + $Name) }
    catch {
        $detail=($_.Exception.Message -replace '[\r\n]+',' ')
        Write-Host ('::error title={0}::{1}' -f $Name,$detail)
        if($env:GITHUB_STEP_SUMMARY){@('### '+$Name,'```text',$_.ToString(),$_.ScriptStackTrace,'```') | Out-File -LiteralPath $env:GITHUB_STEP_SUMMARY -Encoding utf8 -Append}
        throw
    }
}
function Assert-Throws { param([scriptblock]$Body) $caught=$false; try { & $Body } catch {$caught=$true}; Assert-True $caught 'Expected exception.' }
$t=$null; $e=$null
$app = [Management.Automation.Language.Parser]::ParseFile((Join-Path $folder 'Exovance-DeviceTweaker-v2.ps1'),[ref]$t,[ref]$e)
Assert-True ($e.Count -eq 0) ('App syntax: '+($e -join '; '))
$source=$app.Extent.Text
foreach ($name in @('Set-DeviceAffinity','Clear-DeviceAffinity','CoreMaskFromIndex','Get-AffinityHexForCore','Convert-DeviceTweakerAffinityMaskToUInt64','Get-DeviceTweakerDirectoryCandidates')) {
    $f=@($app.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true))
    Assert-True ($f.Count -eq 1) ('Missing function: '+$name)
    . ([scriptblock]::Create($f[0].Extent.Text))
}

for ($cpu=0; $cpu -lt 64; $cpu++) {
    Test-Case ('64-bit affinity CPU '+$cpu) {
        $bytes = [byte[]]::new(8)
        $bytes[[int][Math]::Floor($cpu/8)] = [byte][Math]::Pow(2,$cpu%8)
        [uint64]$expected = [BitConverter]::ToUInt64($bytes,0)
        Assert-True ((ConvertTo-ExovanceAffinityMask @($cpu)) -eq $expected) 'Wrong mask.'
        Assert-True ((CoreMaskFromIndex $cpu) -eq $expected.ToString('X16')) 'App mask helper differs.'
        Assert-True ((Get-AffinityHexForCore $cpu 64) -eq $expected.ToString('X16')) 'App formatting helper differs.'
    }
}
Test-Case 'affinity rejects processors outside one group' {
    Assert-Throws { ConvertTo-ExovanceAffinityMask @(-1) }
    Assert-Throws { ConvertTo-ExovanceAffinityMask @(64) }
    Assert-True ((ConvertTo-ExovanceAffinityMask @(0,31,32,63)) -eq [Convert]::ToUInt64('8000000180000001',16)) 'Combined mask incorrect.'
}
Test-Case 'multiple processor groups are rejected before changes' {
    Assert-ExovanceProcessorGroups 1
    Assert-Throws { Assert-ExovanceProcessorGroups 2 }
    Assert-Throws { Assert-ExovanceProcessorGroups 0 }
}
Test-Case 'RSS follows actual physical core mapping instead of uniform SMT arithmetic' {
    $plan = Get-ExovanceRssPlan 1 3 8 @{0=0;1=0;2=1;3=2;4=2;5=3;6=4;7=4}
    Assert-True (($plan.Processors -join ',') -eq '1,2,3' -and $plan.MaxProcessor -eq 3) 'Incorrect heterogeneous topology plan.'
    $plan = Get-ExovanceRssPlan 4 2 16 @{4=2;5=2;6=3;7=3}
    Assert-True (($plan.Processors -join ',') -eq '4,6' -and $plan.MaxProcessor -eq 6) 'RSS upper bound must include the second processor.'
}
Test-Case 'RSS rejects overflow, missing processors and empty queue selection before writes' {
    Assert-Throws { Get-ExovanceRssPlan 15 2 16 @{} }
    Assert-Throws { Get-ExovanceRssPlan 0 0 16 @{} }
    Assert-Throws { Get-ExovanceRssPlan 64 1 64 @{} }
    Assert-Throws { Get-ExovanceRssPlan 0 1 65 @{} }
    $last = Get-ExovanceRssPlan 63 1 64 @{}
    Assert-True ($last.MaxProcessor -eq 63) 'Last valid processor rejected.'
}

# Mock boundary keeps real plan, snapshot, rollback, and app affinity functions intact.
function Test-RegistryFixture {
    param([scriptblock]$FixtureBody)
    $script:Values=@{}
    $script:Writes=0
    $script:FailOnWrite=0
    $script:cachedLogicalCount=16
    $script:PhysicalCoreIdByLogicalProcessor=@{4=2;5=2;6=3;7=3}
    Reset-ExovanceWriteFailures
    function Get-ExovanceRegistryState {
        param($RegistryPath,$Name)
        if($script:Values.ContainsKey($Name)){return $script:Values[$Name]}
        return [pscustomobject]@{Name=$Name;Present=$false;Kind=$null;Value=$null}
    }
    function Set-ExovanceRegistryState {
        param($RegistryPath,$State)
        $script:Writes++
        if($script:Writes -eq $script:FailOnWrite){throw 'Simulated access denied'}
        if($State.Present){$script:Values[$State.Name]=[pscustomobject]@{Name=$State.Name;Present=$true;Kind=$State.Kind;Value=$State.Value}}
        else{$script:Values.Remove($State.Name)}
    }
    & $FixtureBody
}
Test-Case 'actual app writes a little-endian mask and SpecCPU DWORD policy' {
    Test-RegistryFixture {
        $script:cachedLogicalCount=64
        Assert-True (Set-DeviceAffinity 'HKLM:\FAKE' '8000000100000000') 'Affinity write failed.'
        $state=$script:Values['AssignmentSetOverride']
        Assert-True ($state.Kind -eq 'Binary' -and [BitConverter]::ToString($state.Value) -eq '00-00-00-00-01-00-00-80') 'Wrong registry byte representation.'
        Assert-True ($script:Values['DevicePolicy'].Kind -eq 'DWord' -and $script:Values['DevicePolicy'].Value -eq 4) 'Wrong policy.'
    }
}
Test-Case 'out-of-topology affinity is rejected before registry writes' {
    Test-RegistryFixture {
        Assert-True (-not (Set-DeviceAffinity 'HKLM:\FAKE' '10000')) 'CPU 16 should be invalid on a 16-CPU topology.'
        Assert-True ($script:Writes -eq 0) 'Invalid topology mask wrote registry values.'
        Assert-ExovanceAffinityMask -Mask ([uint64]::MaxValue) -LogicalCount 64
        foreach($case in @(@(1,'1'),@(31,'7FFFFFFF'),@(32,'FFFFFFFF'),@(63,'7FFFFFFFFFFFFFFF'))) {
            Assert-ExovanceAffinityMask -Mask ([Convert]::ToUInt64($case[1],16)) -LogicalCount $case[0]
            Assert-Throws { Assert-ExovanceAffinityMask -Mask ([uint64]1 -shl $case[0]) -LogicalCount $case[0] }
        }
    }
}
Test-Case 'empty affinity actually deletes the override and resets policy' {
    Test-RegistryFixture {
        $null=Set-DeviceAffinity 'HKLM:\FAKE' '1'
        Assert-True (Set-DeviceAffinity 'HKLM:\FAKE' '0x0') 'Reset failed.'
        Assert-True (-not $script:Values.ContainsKey('AssignmentSetOverride')) 'Stale affinity retained.'
        Assert-True ($script:Values['DevicePolicy'].Value -eq 0) 'Policy still SpecCPU.'
    }
}
Test-Case 'write failure prevents a false success summary even when caller ignores bool' {
    Test-RegistryFixture {
        $script:FailOnWrite=1
        Assert-True (-not (Set-DeviceAffinity 'HKLM:\FAKE' '1')) 'False affinity success.'
        Assert-Throws { Assert-ExovanceWritesSucceeded }
        Reset-ExovanceWriteFailures
        Assert-ExovanceWritesSucceeded
    }
}
Test-Case 'RSS writes correct range and preserves NUMA preference' {
    Test-RegistryFixture {
        $script:Values['*NumaNodeId']=[pscustomobject]@{Name='*NumaNodeId';Present=$true;Kind='DWord';Value=2}
        $p=Set-ExovanceRssConfiguration 'HKLM:\FAKE' 4 2
        Assert-True ($script:Values['*RssMaxProcNumber'].Value -eq '6') 'Range ends at base.'
        Assert-True ($script:Values['*MaxRssProcessors'].Value -eq '2') 'Wrong processor count.'
        Assert-True ($script:Values['*NumaNodeId'].Value -eq 2 -and $script:Values['*NumaNodeId'].Kind -eq 'DWord') 'NUMA preference overwritten.'
        Assert-ExovanceWritesSucceeded
    }
}
Test-Case 'RSS backup roundtrip preserves types, values and absence through JSON' {
    Test-RegistryFixture {
        $script:Values['*RssBaseProcNumber']=[pscustomobject]@{Name='*RssBaseProcNumber';Present=$true;Kind='DWord';Value=2}
        $script:Values['*NumaNodeId']=[pscustomobject]@{Name='*NumaNodeId';Present=$true;Kind='String';Value='-1'}
        $snapshot=@(Get-ExovanceRssSnapshot 'HKLM:\FAKE')
        $json=ConvertTo-Json -InputObject $snapshot -Depth 8
        # WinPS 5.1 emits a top-level JSON array as one pipeline object;
        # PS 7 enumerates it. Direct assignment preserves its seven entries in both.
        $restored=ConvertFrom-Json -InputObject $json
        Assert-True ($restored.Count -eq 7) 'Top-level JSON lost RSS entries.'
        # Exercise the application's actual nested Devices/ExovanceRss schema too.
        $documentJson=ConvertTo-Json -InputObject ([pscustomobject]@{Devices=@([pscustomobject]@{ExovanceRss=$snapshot})}) -Depth 10
        $document=ConvertFrom-Json -InputObject $documentJson
        $restored=@($document.Devices[0].ExovanceRss)
        Assert-True ($restored.Count -eq 7) 'Full backup JSON lost RSS entries.'
        $null=Set-ExovanceRssConfiguration 'HKLM:\FAKE' 4 2
        Restore-ExovanceRssSnapshot 'HKLM:\FAKE' $restored
        Assert-True ($script:Values.Count -eq 2) 'Previously absent values were not removed.'
        Assert-True ($script:Values['*RssBaseProcNumber'].Kind -eq 'DWord' -and $script:Values['*RssBaseProcNumber'].Value -eq 2) 'Original type/value lost.'
        Assert-True ($script:Values['*NumaNodeId'].Value -eq '-1') 'Original special driver default lost.'
    }
}
Test-Case 'RSS partial write failure rolls back the complete snapshot' {
    Test-RegistryFixture {
        $script:Values['*NumRssQueues']=[pscustomobject]@{Name='*NumRssQueues';Present=$true;Kind='String';Value='8'}
        $script:FailOnWrite=3
        Assert-Throws { Set-ExovanceRssConfiguration 'HKLM:\FAKE' 4 2 }
        Assert-True ($script:Values.Count -eq 1 -and $script:Values['*NumRssQueues'].Value -eq '8') 'Partial RSS writes were left behind.'
        Assert-Throws { Assert-ExovanceWritesSucceeded }
    }
}
Test-Case 'invalid RSS range and Balanced profile cause zero writes' {
    Test-RegistryFixture {
        Assert-Throws { Set-ExovanceRssConfiguration 'HKLM:\FAKE' 15 2 }
        Assert-True ($script:Writes -eq 0) 'Invalid range wrote settings.'
        $script:Values['*RSSProfile']=[pscustomobject]@{Name='*RSSProfile';Present=$true;Kind='String';Value='6'}
        Assert-Throws { Set-ExovanceRssConfiguration 'HKLM:\FAKE' 4 1 }
        Assert-True ($script:Writes -eq 0) 'Balanced driver profile was overridden.'
    }
}
Test-Case 'incomplete or foreign RSS snapshot is rejected before any write' {
    Test-RegistryFixture {
        Assert-Throws { Restore-ExovanceRssSnapshot 'HKLM:\FAKE' @() }
        $bad=@(Get-ExovanceRssSnapshot 'HKLM:\FAKE')
        $bad[0].Name='ForeignSetting'
        Assert-Throws { Restore-ExovanceRssSnapshot 'HKLM:\FAKE' $bad }
        Assert-True ($script:Writes -eq 0) 'Invalid backup wrote settings.'
    }
}
Test-Case 'original source is unchanged and v2 never ships another PCs backup/logs' {
    $original=Join-Path $repo 'DEVICE-TWEAKER/DEVICE-TWEAKER-UPDATE-2026-LLG-X-LLC-UPDATED.ps1'
    Assert-True ((Get-FileHash $original -Algorithm SHA256).Hash -eq 'B5D1E620A7574F26DDA8F7641372B6B47EABB26E9C9C57202A780632A65457A9') 'Original modified.'
    Assert-True (-not (Test-Path (Join-Path $folder 'exovance_v2_device_settings_backup.json'))) 'Backup should not be bundled.'
    Assert-True (-not (Test-Path (Join-Path $folder 'device_settings_backup.json'))) 'Original backup was copied.'
    $script:cachedScriptDir=$folder
    Assert-True (@(Get-DeviceTweakerDirectoryCandidates).Count -eq 1 -and @(Get-DeviceTweakerDirectoryCandidates)[0] -eq $folder) 'Backup lookup escapes v2 folder.'
}
Test-Case 'branding, companion separation and full RSS backup are wired into the app' {
    Assert-True ($source.Contains('EXOVANCE') -and $source.Contains('ALTERNATE PLAN')) 'New branding missing.'
    Assert-True (-not ($source -match 'boosty\.to|BEYOND PERFORMANCE|BYND_PERF|SECRET-TWEAK -')) 'Promotional header remains.'
    Assert-True (-not $source.Contains('Enable-HardwareAcceleratedGpuScheduling')) 'Alternate Plan still forces HAGS.'
    Assert-True ($source.Contains("['ExovanceRss'] = @(Get-ExovanceRssSnapshot")) 'Full RSS backup not wired.'
    Assert-True ($source.Contains('Restore-ExovanceRssSnapshot -RegistryPath $matchingDevice.RegistryPath')) 'Full RSS restore not wired.'
    $calls=@($app.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Set-ExovanceRssConfiguration'},$true))
    Assert-True ($calls.Count -eq 5) 'Manual/Auto/Alternate RSS branches not centralized.'
    Assert-True (-not ($source -match '(?<!\])\b1 -shl \$(?:assignmentCore|coreIndex|secretGroupCore|ecore|core|c)\b')) 'Int32 logical-processor shift remains.'
}
Test-Case 'main menu includes separate v2 and original launch paths' {
    $cmd=[IO.File]::ReadAllText((Join-Path $repo 'Low-Latency-Corp-Menu_v2.cmd'))
    Assert-True ($cmd.Contains('Launch Exovance v2') -and $cmd.Contains('Launch original Device Tweaker')) 'Missing launch choices.'
    Assert-True ($cmd.Contains("'DEVICE-TWEAKER-V2\RUN-EXOVANCE-V2.bat'")) 'Wrong v2 launcher path.'
}
# In Windows, compile all embedded C# without starting its WinForms application.
if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
    Test-Case 'Windows launcher check works from a path with spaces without starting GUI' {
        $fixture=Join-Path ([IO.Path]::GetTempPath()) ('Exovance install '+[guid]::NewGuid().ToString('N'))
        $null=New-Item -ItemType Directory -Path $fixture
        try {
            foreach($file in @('RUN-EXOVANCE-V2.bat','Exovance-DeviceTweaker-v2.ps1','Exovance.Core.ps1')) {
                Copy-Item -LiteralPath (Join-Path $folder $file) -Destination $fixture
            }
            $launcher=Join-Path $fixture 'RUN-EXOVANCE-V2.bat'
            # Match Invoke-ExternalBatchLauncher: PowerShell handles BAT paths
            # with spaces directly; an extra cmd /c layer double-quotes on WinPS.
            $output=@(& $launcher /check 2>&1)
            Assert-True ($LASTEXITCODE -eq 0) ('Launcher check failed: '+($output -join "`n"))
            Assert-True (($output -join "`n").Contains('PASS: Exovance v2 syntax')) 'No check result.'
            Assert-True (-not (Test-Path (Join-Path $fixture 'logs'))) 'Check initialized application logs.'
        } finally { Remove-Item -LiteralPath $fixture -Recurse -Force }
    }
    Test-Case 'full embedded WinForms C# compiles on Windows' {
        $fn=$app.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Add-DeviceTweakerMergedTypesFromSource'},$true)
        . ([scriptblock]::Create($fn.Extent.Text))
        function Test-DeviceTweakerMergedTypesAvailable { return $false }
        Add-Type -AssemblyName System.Windows.Forms,System.Drawing,System.Management
        Add-DeviceTweakerMergedTypesFromSource -CacheAssemblyPath $null
        Assert-True ($null -ne ('DeviceTweakerFormFactory' -as [type])) 'Embedded C# types missing.'
    }
    Test-Case 'native CPU grid keyboard selection and paint preserve high mask bits' {
        $grid=New-Object CpuAffinityGrid
        $grid.LogicalCount=64
        $grid.Font=New-Object System.Drawing.Font('Segoe UI',9)
        $grid.SetLayoutMetrics(8,8,86,25,0)
        $grid.Size=New-Object System.Drawing.Size(700,210)
        try {
            $method=$grid.GetType().GetMethod('OnKeyDown',[Reflection.BindingFlags]'Instance,NonPublic')
            $null=$method.Invoke($grid,@((New-Object System.Windows.Forms.KeyEventArgs([System.Windows.Forms.Keys]::End))))
            $null=$method.Invoke($grid,@((New-Object System.Windows.Forms.KeyEventArgs([System.Windows.Forms.Keys]::Space))))
            Assert-True ($grid.Mask -eq [Convert]::ToUInt64('8000000000000000',16)) 'Keyboard lost bit 63.'
            # Shrinking a dynamically rebuilt grid must reset its keyboard focus index.
            $grid.LogicalCount=16
            $null=$method.Invoke($grid,@((New-Object System.Windows.Forms.KeyEventArgs([System.Windows.Forms.Keys]::Space))))
            Assert-True ($grid.GetCpuChecked(15) -and $grid.Mask -eq 32768) 'Focus or mask was not clamped after topology change.'
            $grid.Mask=1
            $bitmap=New-Object System.Drawing.Bitmap($grid.Width,$grid.Height)
            try {
                $grid.DrawToBitmap($bitmap,(New-Object System.Drawing.Rectangle(0,0,$grid.Width,$grid.Height)))
                $selected=$grid.GetCpuBounds(0);$normal=$grid.GetCpuBounds(1)
                $a=$bitmap.GetPixel($selected.Left+20,$selected.Top+2)
                $b=$bitmap.GetPixel($normal.Left+20,$normal.Top+2)
                Assert-True ($a.ToArgb() -ne $b.ToArgb()) 'Selected CPU is visually indistinguishable.'
            } finally {$bitmap.Dispose()}
        } finally {$grid.Font.Dispose();$grid.Dispose()}
    }
} else {
    Test-Case 'check mode rejects Linux before starting native UI or applying settings' {
        $engine=(Get-Process -Id $PID).Path
        $output=@(& $engine -NoLogo -NoProfile -File (Join-Path $folder 'Exovance-DeviceTweaker-v2.ps1') -Check 2>&1)
        Assert-True ($LASTEXITCODE -eq 2) 'Unsupported host must return 2.'
        Assert-True (($output -join "`n").Contains('Use Windows PowerShell 5.1 x64')) 'Missing host diagnostic.'
    }
}
Write-Host ('Exovance checks: {0} passed. No hardware settings were applied.' -f $script:Passed)
exit 0
