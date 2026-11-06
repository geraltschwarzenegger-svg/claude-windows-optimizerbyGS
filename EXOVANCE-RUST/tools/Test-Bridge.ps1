# Real pipe transport tests in PowerShell 7 / Windows PowerShell 5.1.
# Only extracted UI helpers and mocked actions are executed; never load the legacy application.
$ErrorActionPreference='Stop'
trap {
    $record=$_
    $message=($record.Exception.Message -replace '[\r\n]+',' ')
    Write-Host ('::error title=PowerShell pipe transport::{0}' -f $message)
    Write-Host $record.ScriptStackTrace
    if($env:GITHUB_STEP_SUMMARY){@('### Pipe transport failure','```text',$record.ToString(),$record.ScriptStackTrace,'```') | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Encoding utf8 -Append}
    exit 1
}
$folder=Split-Path -Parent $PSScriptRoot
$repo=Split-Path -Parent $folder
$source=[IO.File]::ReadAllText((Join-Path $repo 'Low-Latency-Corp-Menu_v2.cmd')).Replace("`r`n","`n")
$marker='### POWERSHELL STARTS HERE ###'
$payload=$source.Substring($source.LastIndexOf($marker)+$marker.Length)
$t=$null;$e=$null
$ast=[Management.Automation.Language.Parser]::ParseInput($payload,[ref]$t,[ref]$e)
if($e.Count){throw ($e -join '; ')}
$helpers=@('Get-LlcMainMenuItems','Get-LlcMenuEntries','Get-LlcMenuHelp','Get-LlcRegistryHelpLines','Get-LlcAutostartHelp','Confirm-LlcBroadChanges')
$definitions=@(foreach($name in $helpers){
    $fn=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
    if($null -eq $fn){throw ('Missing fixture helper '+$name)}
    $fn.Extent.Text
}) -join "`n"
$bridge=[IO.File]::ReadAllText((Join-Path $folder 'bridge/terminal.ps1')).TrimStart([char]0xfeff)
$transport=[IO.File]::ReadAllText((Join-Path $folder 'bridge/transport.ps1')).TrimStart([char]0xfeff)
$fixture=$transport+"`n"+@'
$ErrorActionPreference='Stop'
$env:EXOVANCE_WIRE_PREFIX='@EXOVANCE-TEST@ '
$env:EXOVANCE_ROUTE='uac'
function Test-Admin {return $true}
'@ +"`n"+$definitions+"`n"+$bridge+"`n"+@'
$script:Touches=0
function Set-AutostartItemStatus {
    param($Item,[bool]$Enable)
    if($Item.DisplayName -ne 'Fixture only'){throw 'Foreign autostart target'}
    $script:Touches++;$Item.Enabled=$Enable
    [pscustomobject]@{Ok=$true;Message='In-memory fixture toggle'}
}
$root=Invoke-Menu 'Exovance Optimizer v2' @(Get-LlcMainMenuItems)
$items=@([pscustomobject]@{Text='Real item';Value=17},[pscustomobject]@{Text='Header';Selectable=$false},'Back')
$first=Invoke-Menu 'Fixture choices' $items
$cancel=Invoke-Menu 'Cancel fixture' $items
$text=Read-Host 'UTF-8 fixture'
$confirm=Confirm-LlcBroadChanges Auto
Wait-ForEnterToContinue
$item=[pscustomobject]@{Enabled=$true;DisplayName='Fixture only';Source='Mock';RegistryPath='HKLM:FAKE';Details=''}
Invoke-AutostartFullListMenu 'Autostart' @($item)
Write-StatusLine -Ok $false -Text 'Simulated error; no real writes'
$rootAfter=Invoke-Menu 'Exovance Optimizer v2' @(Get-LlcMainMenuItems)
[Console]::Out.WriteLine('@RESULT@'+(ConvertTo-Json -Compress -InputObject @{root=$root;first=$first;cancel=$cancel;text=$text;confirm=$confirm;touches=$script:Touches;enabled=$item.Enabled;rootAfter=$rootAfter}))
'@
$temp=Join-Path ([IO.Path]::GetTempPath()) ('Exovance pipe tests '+[guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory($temp)
try {
    $path=Join-Path $temp 'fixture.ps1'
    [IO.File]::WriteAllText($path,$fixture,[Text.UTF8Encoding]::new($true))
    foreach($mode in @('valid','bom','wrong-id','header','eof')) {
        $info=New-Object Diagnostics.ProcessStartInfo
        $info.FileName=[Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        $info.Arguments='-NoLogo -NoProfile -ExecutionPolicy Bypass -File "'+$path+'"'
        $info.UseShellExecute=$false;$info.CreateNoWindow=$true
        $info.RedirectStandardInput=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
        $info.StandardOutputEncoding=[Text.UTF8Encoding]::new($false)
        $info.StandardErrorEncoding=[Text.UTF8Encoding]::new($false)
        $process=New-Object Diagnostics.Process
        $process.StartInfo=$info
        $null=$process.Start()
        $writer=[IO.StreamWriter]::new($process.StandardInput.BaseStream,[Text.UTF8Encoding]::new($false),4096,$false)
        $result=$null;$requests=0;$errors=0
        try {
            while($true) {
                $task=$process.StandardOutput.ReadLineAsync()
                if(-not $task.Wait(20000)){throw ('Pipe test timed out: '+$mode)}
                $line=$task.Result
                if($null -eq $line){break}
                if($line.StartsWith('@RESULT@')){$result=ConvertFrom-Json $line.Substring(8);continue}
                if(-not $line.StartsWith('@EXOVANCE-TEST@ ')){continue}
                $request=ConvertFrom-Json $line.Substring(16)
                if($request.kind -eq 'status'){if($request.level -eq 'error'){$errors++};continue}
                $requests++
                if($mode -eq 'eof'){$writer.Close();continue}
                $reply=@{id=$request.id;index=0;cancelled=$false;text=''}
                if($mode -eq 'wrong-id'){$reply.id=999}
                if($mode -eq 'header'){$reply.index=1}
                if($mode -in @('valid','bom')) {
                    switch($request.id) {
                        1 {$reply.index=0}
                        2 {$reply.cancelled=$true}
                        3 {$reply.text='Тест & ; $() без выполнения'}
                        4 {$reply.cancelled=$true}
                        5 { }
                        6 {$reply.index=1}
                        7 {
                            if($null -eq $request.selected -or $request.selected -ne 1){throw 'Autostart focus jumped to Disable all after a toggle'}
                            $reply.index=[int]$request.selected
                        }
                        8 {
                            if($request.selected -ne 1){throw 'Autostart focus not preserved after reversing the toggle'}
                            $reply.index=2
                        }
                        default {throw ('Unexpected request '+$request.id)}
                    }
                }
                if($mode -eq 'bom' -and $requests -eq 1) {
                    $bom=[byte[]]@(239,187,191)
                    $writer.BaseStream.Write($bom,0,$bom.Length)
                    $writer.BaseStream.Flush()
                }
                $writer.WriteLine((ConvertTo-Json -Compress -InputObject $reply))
                $writer.Flush()
            }
            if(-not $process.WaitForExit(10000)){throw 'Fixture did not exit'}
            $errorText=$process.StandardError.ReadToEnd()
            if($mode -in @('valid','bom')) {
                if($process.ExitCode -ne 0 -or $null -eq $result){throw ('Fixture failed: '+$errorText)}
                if($result.root -cne 'uac' -or $result.rootAfter -cne 'exit' -or $result.first -ne 17 -or $result.cancel -ne -1){throw 'Typed navigation values changed'}
                if($result.text -cne 'Тест & ; $() без выполнения' -or $result.confirm){throw 'Input changed or Auto confirmation bypassed'}
                if($result.touches -ne 2 -or -not $result.enabled -or $requests -ne 8 -or $errors -ne 1){throw 'Autostart mock or typed error reporting failed'}
            } else {
                if($process.ExitCode -eq 0 -or $null -ne $result){throw ('Invalid reply did not stop execution: '+$mode)}
            }
            Write-Host ('PASS: real JSON pipe transport — '+$mode)
        } finally {
            if(-not $process.HasExited){$process.Kill();$process.WaitForExit()}
            $writer.Dispose()
            $process.Dispose()
        }
    }
} finally {Remove-Item -LiteralPath $temp -Recurse -Force}
# Build-script generated backend parses, but is never executed by this test.
$built=@(Get-ChildItem (Join-Path $folder 'target') -Recurse -Filter backend.ps1 | Where-Object {$_.Directory.Name -eq 'out'})
if($built.Count -eq 0){throw 'Run cargo build/test before Test-Bridge.ps1'}
foreach($file in $built) {
    $t=$null;$e=$null
    $text=[IO.File]::ReadAllText($file.FullName).Replace("`r`n","`n")
    $null=[Management.Automation.Language.Parser]::ParseInput($text,[ref]$t,[ref]$e)
    if($e.Count){throw ('Generated backend parse errors: '+($e -join '; '))}
    $start=$payload.IndexOf("`nif (-not (Test-Admin)) {`n    Clear-ConsoleScreen")
    if($start -lt 0){throw 'Legacy entry boundary missing'}
    $prefix=$payload.Substring(0,$start)
    $trapStart=$prefix.IndexOf("`ntrap {`n    " + '$err = $_')
    $trapEnd=$prefix.IndexOf("`nfunction Clear-ConsoleScreen",$trapStart)
    if($trapStart -lt 0 -or $trapEnd -lt 0){throw 'Legacy trap boundaries changed'}
    if(-not $text.Contains($prefix.Substring(0,$trapStart)) -or -not $text.Contains($prefix.Substring($trapEnd))){throw 'Legacy action bodies or presets changed during embedding'}
    if($text.Contains("FATAL ERROR - the script stopped unexpectedly.")){throw 'Blocking legacy trap remains in pipe backend'}
}
Write-Host 'PASS: generated backend parses and retains every original action body/preset. No Windows settings were modified.'
