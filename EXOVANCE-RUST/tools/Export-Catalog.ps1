# Extract declarations only, as in the existing isolated tests. Do not execute the CMD.
param([switch]$Check)
$ErrorActionPreference='Stop'
$folder=Split-Path -Parent $PSScriptRoot
$cmd=Join-Path (Split-Path -Parent $folder) 'Low-Latency-Corp-Menu_v2.cmd'
$source=[IO.File]::ReadAllText($cmd)
$marker='### POWERSHELL STARTS HERE ###'
$payload=$source.Substring($source.LastIndexOf($marker)+$marker.Length)
$t=$null;$e=$null
$ast=[Management.Automation.Language.Parser]::ParseInput($payload,[ref]$t,[ref]$e)
if($e.Count){throw ($e -join '; ')}
foreach($name in @('Get-LlcMainMenuItems','Get-LlcMenuEntries','Get-LlcMenuHelp','Get-LlcRegistryHelpLines')) {
    $fn=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
    . ([scriptblock]::Create($fn.Extent.Text))
}
$entries=@(Get-LlcMenuEntries -Items @(Get-LlcMainMenuItems))
$data=@($entries | ForEach-Object {
    [ordered]@{index=$_.Index;text=$_.Text;selectable=$_.Selectable;value=$_.Value;help=(Get-LlcMenuHelp 'Exovance Optimizer v2' $_)}
})
$json=(ConvertTo-Json -InputObject $data -Depth 10)+[Environment]::NewLine
$path=Join-Path $folder 'assets/catalog.json'
if($Check) {
    $expected=ConvertFrom-Json $json
    $actual=ConvertFrom-Json ([IO.File]::ReadAllText($path))
    if((ConvertTo-Json -InputObject $expected -Depth 10 -Compress) -cne (ConvertTo-Json -InputObject $actual -Depth 10 -Compress)){throw 'Rust catalog differs from the CMD. Run Export-Catalog.ps1.'}
    Write-Host ('PASS: all {0} selectable CMD sections and their Russian help are preserved.' -f @($entries|Where-Object Selectable).Count)
} else { [IO.File]::WriteAllText($path,$json,[Text.UTF8Encoding]::new($false)) }
