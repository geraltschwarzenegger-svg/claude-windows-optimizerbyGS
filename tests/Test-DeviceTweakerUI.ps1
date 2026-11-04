# Theme/feedback checks run without starting WinForms or touching the registry.
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$folder=Join-Path $repo 'DEVICE-TWEAKER-V2'
. (Join-Path $folder 'Exovance.Core.ps1')
$source=[IO.File]::ReadAllText((Join-Path $folder 'Exovance-DeviceTweaker-v2.ps1'))
$match=[regex]::Match($source,'(?s)public static class ExovancePalette\s*\{.*?\n\}')
if(-not $match.Success){throw 'Missing palette in actual application.'}
if([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT){Add-Type -TypeDefinition ("using System.Drawing;`n"+$match.Value) -ReferencedAssemblies System.Drawing}
else{Add-Type -TypeDefinition ("using System.Drawing;`n"+$match.Value)}
$script:Passed=0
function Test-Case {param([string]$Name,[scriptblock]$Body) & $Body;$script:Passed++;Write-Host ('PASS: '+$Name)}
function Assert-True {param([bool]$Condition,[string]$Message)if(-not $Condition){throw $Message}}
function Luminance {param($Color)$v=@($Color.R,$Color.G,$Color.B)|ForEach-Object {$c=$_/255.0;if($c -le 0.04045){$c/12.92}else{[Math]::Pow(($c+0.055)/1.055,2.4)}};return 0.2126*$v[0]+0.7152*$v[1]+0.0722*$v[2]}
function Contrast {param($A,$B)$x=Luminance $A;$y=Luminance $B;return ([Math]::Max($x,$y)+0.05)/([Math]::Min($x,$y)+0.05)}
Test-Case 'body, muted and primary-button text meet 4.5:1 contrast' {
    Assert-True ((Contrast ([ExovancePalette]::Text) ([ExovancePalette]::Card)) -ge 4.5) 'Body contrast too low.'
    Assert-True ((Contrast ([ExovancePalette]::Muted) ([ExovancePalette]::Card)) -ge 4.5) 'Muted text contrast too low.'
    Assert-True ((Contrast ([ExovancePalette]::Background) ([ExovancePalette]::Accent)) -ge 4.5) 'Primary action contrast too low.'
}
Test-Case 'selected and hovered CPU states have distinct fills and a visible outline' {
    $normal=[ExovancePalette]::CpuFill($false,$false)
    $hover=[ExovancePalette]::CpuFill($false,$true)
    $selected=[ExovancePalette]::CpuFill($true,$false)
    Assert-True ($normal.ToArgb() -ne $hover.ToArgb() -and $hover.ToArgb() -ne $selected.ToArgb()) 'Selection states share the same fill.'
    Assert-True ((Contrast ([ExovancePalette]::CpuBorder($true,$false)) $selected) -ge 3) 'Selected outline contrast too low.'
    Assert-True ((Contrast ([ExovancePalette]::Accent) $selected) -ge 4.5) 'Selected CPU text contrast too low.'
}
Test-Case 'selection does not report applied and error replaces the applied state' {
    $script:ExovanceFeedbackItem=[pscustomobject]@{Text='';ForeColor=[System.Drawing.Color]::Empty}
    Set-ExovanceUiFeedback Changed 'Selection updated'
    Assert-True ($script:ExovanceUiState -eq 'Changed') 'Selection falsely reported applied.'
    Set-ExovanceUiFeedback Working 'Working'
    Assert-True ($script:ExovanceUiState -eq 'Working') 'Working state lost.'
    Set-ExovanceUiFeedback Applied 'Applied'
    $success=$script:ExovanceFeedbackItem.ForeColor
    Add-ExovanceWriteFailure 'Simulated apply failure'
    Assert-True ($script:ExovanceUiState -eq 'Error' -and $script:ExovanceFeedbackItem.ForeColor.ToArgb() -ne $success.ToArgb()) 'Failure retained success styling.'
    Assert-True (-not $script:ExovanceFeedbackItem.Text.Contains('Applied')) 'Failure retained success message.'
    Set-ExovanceUiFeedback Applied 'Must not report success'
    Assert-True ($script:ExovanceUiState -eq 'Error') 'Unresolved errors can be painted as success.'
}
Test-Case 'custom CPU grid retains keyboard selection and settings remain owned by Apply' {
    Assert-True ($source.Contains('Space changes the selection without applying settings.')) 'Missing keyboard/accessibility description.'
    Assert-True ($source.Contains('Keys.Space || e.KeyCode == Keys.Enter') -and $source.Contains('Keys.Right')) 'Missing keyboard interactions.'
    $a=$source.IndexOf('public static class ExovanceInteractionState')
    $b=$source.IndexOf('public static class ExovanceVisuals',$a)
    $selection=$source.Substring($a,$b-$a)
    Assert-True (-not ($selection -match 'Registry|Set-Device|SetValue')) 'Selection event applies settings.'
    Assert-True ($source.Contains('if ($script:ExovanceUiState -eq ''Working'')')) 'Cancellation cannot return to ready.'
}
Write-Host ('Exovance UI checks: {0} passed. No window or hardware settings were started.' -f $script:Passed)
exit 0
