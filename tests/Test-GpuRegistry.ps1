# Isolated fixtures only: no real registry reads/writes, GPU tools or Windows changes.
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$passed=0
function Assert-True([bool]$Condition,[string]$Message) { if(-not $Condition){throw $Message} }
function Assert-Throws([scriptblock]$Body) {
    $caught=$false
    try { & $Body } catch { $caught=$true }
    Assert-True $caught 'Expected the action to fail before any write.'
}
function Test-Case([string]$Name,[scriptblock]$Body) {
    & $Body
    $script:passed++
    Write-Host ('PASS: '+$Name)
}
function Read-PayloadAst([string]$Name) {
    $s=[IO.File]::ReadAllText((Join-Path $repo $Name))
    $marker='### POWERSHELL STARTS HERE ###'
    $s=$s.Substring($s.LastIndexOf($marker)+$marker.Length)
    $t=$null;$e=$null
    $a=[Management.Automation.Language.Parser]::ParseInput($s,[ref]$t,[ref]$e)
    if($e.Count){throw ($e -join '; ')}
    return $a
}
$ast=Read-PayloadAst 'Low-Latency-Corp-Menu_v2.cmd'
foreach($name in @('Get-LlcPresentGpuDevices','Get-LlcGpuRegistryTargets','ConvertTo-LlcGpuRegistryItems','Invoke-LlcGpuRegistryPreset','Get-DetectedGpuVendorAuto','Get-LlcRegistryHelpLines','Invoke-GpuTweaksAuto')) {
    $fn=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
    . ([scriptblock]::Create($fn.Extent.Text))
}
$guid='{4d36e968-e325-11ce-bfc1-08002be10318}'
$base='HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Class\'+$guid+'\'
$nv='PCI\VEN_10DE&DEV_2882\4&AA&0&0008'
$nv2='PCI\VEN_10DE&DEV_2684\4&BB&0&0008'
$amd='PCI\VEN_1002&DEV_744C\4&CC&0&0008'
$fixtures=@{}
function Get-PnpDevice {
    param($Class,[switch]$PresentOnly,$ErrorAction)
    Assert-True ($Class -eq 'Display' -and $PresentOnly) 'Only present display adapters may be enumerated.'
    if($script:pnpFails){throw 'PnP fixture unavailable'}
    @($script:devices | ForEach-Object { [pscustomobject]@{FriendlyName=$_.Name;InstanceId=$_.InstanceId} })
}
function Get-CimInstance {
    param($ClassName,$Filter,$ErrorAction)
    Assert-True ($ClassName -eq 'Win32_VideoController' -and $Filter -eq 'ConfigManagerErrorCode=0') 'Unfiltered fallback enumeration.'
    $script:cimCalled=$true
    if($script:cimFails){throw 'CIM fixture unavailable'}
    @($script:devices | ForEach-Object { [pscustomobject]@{Name=$_.Name;PNPDeviceID=$_.InstanceId} })
}
function Get-WmiObject { param($Class,$Filter,$ErrorAction) throw 'WMI fixture unavailable' }
function Get-ItemProperty {
    param($LiteralPath,$ErrorAction)
    Assert-True ($LiteralPath.StartsWith('Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\PCI\')) 'Wrong registry hive/control set.'
    return $script:fixtures[$LiteralPath]
}
function Test-Path { param($LiteralPath,$PathType,$ErrorAction) return ($script:keys -contains $LiteralPath) }
function Write-StatusLine { param($Ok,$Text,[switch]$Warning) $script:messages+=@([pscustomobject]@{Ok=$Ok;Text=$Text}) }
function Write-BoxTitle { param($Title) }
function Clear-ConsoleScreen { }
function Wait-ForEnterToContinue { }
function Invoke-Menu { param($Title,$Items) return $script:choice }
function Invoke-RegistrySetAuto {
    param($Title,$Items,$AfterMessage)
    $script:writes+=@($Items)
    return $script:writeSuccess
}
function Reset-Fixture {
    $script:devices=@([pscustomobject]@{Name='GPU A';InstanceId=$nv},[pscustomobject]@{Name='GPU B';InstanceId=$nv2},[pscustomobject]@{Name='GPU C';InstanceId=$amd})
    $script:fixtures=@{}
    $script:fixtures['Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\'+$nv]=[pscustomobject]@{ClassGUID=$guid;Driver=$guid+'\0003'}
    $script:fixtures['Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\'+$nv2]=[pscustomobject]@{ClassGUID=$guid;Driver=$guid+'\0008'}
    $script:fixtures['Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\'+$amd]=[pscustomobject]@{ClassGUID=$guid;Driver=$guid+'\0001'}
    $script:keys=@(('Registry::'+$base+'0003'),('Registry::'+$base+'0008'),('Registry::'+$base+'0001'))
    $script:pnpFails=$false;$script:cimFails=$false;$script:cimCalled=$false;$script:choice=1;$script:writeSuccess=$true
    $script:writes=@();$script:messages=@()
}
$template=@([pscustomobject]@{Key='<GPU_DRIVER_KEY>';Name='Fixture';Value='0x00000001';Type='DWord';CreateKey=$true})
Test-Case 'targets follow PCI Driver mappings, not names, 0000 or vendor order' {
    Reset-Fixture
    $script:devices+=@($script:devices[0],[pscustomobject]@{Name='NVIDIA virtual';InstanceId='ROOT\DISPLAY\0000'})
    $targets=@(Get-LlcGpuRegistryTargets NVIDIA)
    Assert-True ($targets.Count -eq 2 -and $targets[0].Key -eq ($base+'0003') -and $targets[1].Key -eq ($base+'0008')) 'Wrong NVIDIA mapping or duplicates.'
    $targets=@(Get-LlcGpuRegistryTargets AMD)
    Assert-True ($targets.Count -eq 1 -and $targets[0].Key -eq ($base+'0001')) 'AMD mapped to another vendor.'
    Assert-True ((Get-DetectedGpuVendorAuto) -eq 'BOTH') 'Both vendors not detected by hardware IDs.'
}
Test-Case 'PnP failure uses a filtered CIM fallback' {
    Reset-Fixture;$script:pnpFails=$true
    $targets=@(Get-LlcGpuRegistryTargets NVIDIA)
    Assert-True ($script:cimCalled -and $targets.Count -eq 2) 'Fallback failed.'
    $script:cimFails=$true
    Assert-Throws { Get-DetectedGpuVendorAuto }
    Assert-True (-not (Invoke-LlcGpuRegistryPreset NVIDIA 'Fixture' $template -Auto)) 'Detection failure reported success.'
    Assert-True ($script:writes.Count -eq 0) 'Detection failure wrote settings.'
}
Test-Case 'invalid or absent driver mappings fail closed' {
    foreach($driver in @('',$guid+'\..\0000','{00000000-0000-0000-0000-000000000000}\0000',$guid+'\0002')) {
        Reset-Fixture
        $script:fixtures['Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\'+$nv].Driver=$driver
        Assert-Throws { Get-LlcGpuRegistryTargets NVIDIA }
    }
}
Test-Case 'wrong device class is rejected' {
    Reset-Fixture
    $script:fixtures['Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\'+$nv].ClassGUID='{00000000-0000-0000-0000-000000000000}'
    Assert-True (-not (Invoke-LlcGpuRegistryPreset NVIDIA 'Fixture' $template -Auto)) 'Invalid class accepted.'
    Assert-True ($script:writes.Count -eq 0) 'Wrote before verification.'
}
Test-Case 'multi GPU choice binds a copy of all items to the selected adapter' {
    Reset-Fixture
    Assert-True (Invoke-LlcGpuRegistryPreset NVIDIA 'Fixture' $template -Auto) 'Selection failed.'
    Assert-True ($script:writes.Count -eq 1 -and $script:writes[0].Key -eq ($base+'0008')) 'Wrong chosen target.'
    Assert-True (-not $script:writes[0].CreateKey) 'Class key creation must be disabled.'
    Assert-True ($template[0].Key -eq '<GPU_DRIVER_KEY>' -and $template[0].CreateKey) 'Template was mutated.'
}
Test-Case 'cancel, missing vendor and invalid selection write nothing' {
    Reset-Fixture;$script:choice=-1
    Assert-True (Invoke-LlcGpuRegistryPreset NVIDIA 'Fixture' $template -Auto) 'Cancel failed.'
    Assert-True ($script:writes.Count -eq 0) 'Cancel wrote settings.'
    $script:choice=99
    Assert-True (-not (Invoke-LlcGpuRegistryPreset NVIDIA 'Fixture' $template -Auto)) 'Out of bounds choice accepted.'
    $script:devices=@()
    Assert-True (-not (Invoke-LlcGpuRegistryPreset AMD 'Fixture' $template -Auto)) 'Missing vendor accepted.'
    Assert-True ($script:writes.Count -eq 0) 'Missing/invalid target wrote settings.'
}
Test-Case 'driver remapping while choosing cancels the write' {
    Reset-Fixture
    function Invoke-Menu {
        param($Title,$Items)
        $script:fixtures['Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\'+$nv2].Driver=$guid+'\0003'
        return 1
    }
    Assert-True (-not (Invoke-LlcGpuRegistryPreset NVIDIA 'Fixture' $template -Auto)) 'Changed target accepted.'
    Assert-True ($script:writes.Count -eq 0) 'Stale mapping wrote settings.'
}
Test-Case 'manual and auto calls preserve writer failures' {
    Reset-Fixture;$script:devices=@($script:devices[0]);$script:writeSuccess=$false
    Assert-True (-not (Invoke-LlcGpuRegistryPreset NVIDIA 'Fixture' $template -Auto)) 'Auto failure reported success.'
    Assert-True (-not (Invoke-LlcGpuRegistryPreset NVIDIA 'Fixture' $template)) 'Manual failure reported success.'
}
Test-Case 'unbound or foreign templates cannot reach the writer' {
    Reset-Fixture;$script:devices=@($script:devices[0])
    Assert-Throws { ConvertTo-LlcGpuRegistryItems $template 'HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Control\Class\0000' }
    $foreign=@([pscustomobject]@{Key='HKLM\Foreign';Name='Wrong';Type='DWord';Value=1})
    Assert-True (-not (Invoke-LlcGpuRegistryPreset NVIDIA 'Fixture' $foreign -Auto)) 'Foreign template accepted.'
    Assert-True ($script:writes.Count -eq 0) 'Foreign template wrote settings.'
}
function Get-PresetContent($Tree) {
    $names=@('gpuDisplayClassKey','nvidiaGpuOptimize','nvidiaGpuRevert','amdGpuOptimize','amdGpuRevert')
    foreach($statement in $Tree.EndBlock.Statements) {
        if($statement -is [Management.Automation.Language.AssignmentStatementAst] -and $statement.Left.Extent.Text.TrimStart('$') -in $names) {
            . ([scriptblock]::Create($statement.Extent.Text))
        }
    }
    foreach($name in $names[1..4]) {
        [pscustomobject]@{Name=$name;Items=@((Get-Variable $name -ValueOnly) | Select-Object Name,Value,Type)}
    }
}
Test-Case 'all four original GPU presets preserve names, values, types and order' {
    $original=Read-PayloadAst 'Low-Latency-Corp-Menu_SPI_24H2_VisualizationFix.cmd'
    $expected=ConvertTo-Json -InputObject @(Get-PresetContent $original) -Depth 8 -Compress
    $actual=ConvertTo-Json -InputObject @(Get-PresetContent $ast) -Depth 8 -Compress
    Assert-True ($expected -ceq $actual) 'GPU preset contents changed.'
}
Test-Case 'help resolves the template to an explicit dynamic path' {
    $preview=@(Get-LlcRegistryHelpLines -VariableNames 'template') -join "`n"
    Assert-True ($preview.Contains('CurrentControlSet') -and -not $preview.Contains('<GPU_DRIVER_KEY>')) 'Raw template leaked into help.'
}
Write-Host ('PASS: '+$passed+' GPU registry checks; no system settings applied.')
