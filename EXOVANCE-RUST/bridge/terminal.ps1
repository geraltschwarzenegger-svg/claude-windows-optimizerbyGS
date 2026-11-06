# Exovance Rust bridge v1. Transport/UI only; legacy action bodies and presets stay unchanged.
$script:ExovanceWireId = [int64]0
$script:ExovanceRouteUsed = $false

function Send-ExovanceRustMessage {
    param([hashtable]$Message)
    $script:ExovancePipeWriter.WriteLine($env:EXOVANCE_WIRE_PREFIX + (ConvertTo-Json -InputObject $Message -Depth 14 -Compress))
    $script:ExovancePipeWriter.Flush()
}
function Read-ExovanceRustReply {
    param([hashtable]$Message)
    $script:ExovanceWireId++
    $Message.id = $script:ExovanceWireId
    Send-ExovanceRustMessage $Message
    $line = $script:ExovancePipeReader.ReadLine()
    if ($null -eq $line) { throw 'Rust frontend disconnected; no further action will be selected.' }
    $line = $line.TrimStart([char]0xfeff)
    try { $reply = ConvertFrom-Json -InputObject $line -ErrorAction Stop }
    catch {
        $leading = (($line.ToCharArray() | Select-Object -First 8 | ForEach-Object { 'U+{0:X4}' -f [int]$_ }) -join ' ')
        throw ('Invalid UTF-8 JSON reply (leading code points: '+$leading+'): '+$_.Exception.Message)
    }
    if ([int64]$reply.id -ne $script:ExovanceWireId) { throw 'Invalid frontend reply ID.' }
    return $reply
}
function Invoke-Menu {
    param([string]$Title, [AllowEmptyCollection()][object[]]$Items, [int]$SelectedIndex=-1)
    $entries = @(Get-LlcMenuEntries -Items $Items)
    if ($Title -eq 'Exovance Optimizer v2') {
        if ($script:ExovanceRouteUsed) { return 'exit' }
        $script:ExovanceRouteUsed = $true
        $valid = @($entries | Where-Object { $_.Selectable -and [string]$_.Value -ceq $env:EXOVANCE_ROUTE })
        if ($valid.Count -ne 1) { throw 'Unknown Exovance section.' }
        return $valid[0].Value
    }
    $wire = @($entries | ForEach-Object {
        $help = Get-LlcMenuHelp -Title $Title -Entry $_
        if ($Items[$_.Index].PSObject.Properties['RustHelp']) { $help=$Items[$_.Index].RustHelp }
        @{index=$_.Index; text=$_.Text; selectable=$_.Selectable; value=$_.Value; help=$help}
    })
    if (@($entries | Where-Object {$_.Selectable}).Count -eq 0) { return -1 }
    $reply = Read-ExovanceRustReply @{kind='menu'; title=$Title; entries=$wire; selected=$(if($SelectedIndex -ge 0){$SelectedIndex}else{$null})}
    if ($reply.cancelled) { return -1 }
    $selected = @($entries | Where-Object {$_.Selectable -and $_.Index -eq [int]$reply.index})
    if ($selected.Count -ne 1) { throw 'Invalid or non-selectable frontend entry.' }
    # Return the original typed value, never a command or expression supplied by the frontend.
    return $selected[0].Value
}
function Read-Host {
    param([string]$Prompt='', [switch]$AsSecureString, [switch]$MaskInput)
    if ($AsSecureString -or $MaskInput) { throw 'Secret prompts are not supported by this frontend and will not be logged.' }
    $reply = Read-ExovanceRustReply @{kind='input'; title=$Prompt}
    if ($reply.cancelled) { return '' }
    return [string]$reply.text
}
function Wait-ForEnterToContinue {
    param([string]$Prompt='Продолжить')
    $null = Read-ExovanceRustReply @{kind='pause'; title=$Prompt}
}
function Clear-ConsoleScreen { }
function Clear-ConsoleInputBuffer { param([int]$DelayMilliseconds=0) }
function Reset-LlcMenuInput { }
function Write-StatusLine {
    param([bool]$Ok, [string]$Text, [switch]$Warning)
    $level=if(-not $Ok){'error'}elseif($Warning){'warning'}else{'info'}
    Send-ExovanceRustMessage @{kind='status'; level=$level; title=$Text}
}
function Invoke-AutostartFullListMenu {
    param([string]$Title, [AllowEmptyCollection()][object[]]$Items)
    $selectedIndex=-1
    while ($true) {
        $entries=@([pscustomobject]@{Type='DisableAll'; Item=$null})
        $entries+=@($Items | ForEach-Object {[pscustomobject]@{Type='Item';Item=$_}})
        $choices=@(for($i=0;$i -lt $entries.Count;$i++) {
            $entry=$entries[$i]
            $text=if($entry.Type -eq 'DisableAll'){'Disable all'}else{
                '[{0}] {1} | {2}' -f $(if($entry.Item.Enabled){'ON'}else{'OFF'}),$entry.Item.DisplayName,$entry.Item.Source
            }
            [pscustomobject]@{Text=$text;Value=$i;RustHelp=(Get-LlcAutostartHelp -Entry $entry)}
        })
        $choices+=[pscustomobject]@{Text='Back';Value=-1}
        $selection=Invoke-Menu -Title $Title -Items $choices -SelectedIndex $selectedIndex
        if($selection -lt 0){return}
        $selectedIndex=[int]$selection
        $entry=$entries[$selection]
        if($entry.Type -eq 'DisableAll') {
            foreach($item in $Items) {
                if(-not $item.Enabled){continue}
                $result=Set-AutostartItemStatus -Item $item -Enable:$false
                Write-StatusLine -Ok $result.Ok -Text ([string]$result.Message)
            }
        } else {
            $result=Set-AutostartItemStatus -Item $entry.Item -Enable:(-not [bool]$entry.Item.Enabled)
            Write-StatusLine -Ok $result.Ok -Text ([string]$result.Message)
        }
    }
}
if (-not (Test-Admin)) { throw 'Запусти Exovance от имени администратора. Просмотр --demo не требует повышения прав.' }
