# Use explicit UTF-8 pipe streams, independently of a console window/code page.
# .NET Framework's Process.StandardInput can emit an initial UTF-8 BOM.
$script:ExovanceUtf8 = [Text.UTF8Encoding]::new($false)
# Console-host output may use the console code page; pipe setup still works without a console.
try { [Console]::OutputEncoding = $script:ExovanceUtf8 } catch { }
$script:ExovancePipeReader = [IO.StreamReader]::new([Console]::OpenStandardInput(),$script:ExovanceUtf8,$true,4096,$true)
$script:ExovancePipeWriter = [IO.StreamWriter]::new([Console]::OpenStandardOutput(),$script:ExovanceUtf8,4096,$true)
$script:ExovancePipeWriter.AutoFlush = $true
$script:ExovancePipeErrorWriter = [IO.StreamWriter]::new([Console]::OpenStandardError(),$script:ExovanceUtf8,4096,$true)
$script:ExovancePipeErrorWriter.AutoFlush = $true
[Console]::SetIn($script:ExovancePipeReader)
[Console]::SetOut($script:ExovancePipeWriter)
[Console]::SetError($script:ExovancePipeErrorWriter)
$OutputEncoding = $script:ExovanceUtf8
