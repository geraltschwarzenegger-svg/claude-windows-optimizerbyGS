# Read-only metadata collection. Does not execute, import, or load the supplied EXE.
param([Parameter(Mandatory=$true)][string]$Path)
$ErrorActionPreference='Stop'
if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){throw 'Authenticode inspection requires Windows.'}
$file=Get-Item -LiteralPath $Path -ErrorAction Stop
if($file.PSIsContainer){throw 'Expected an EXE file, not a directory.'}
$hash=Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256
$signature=Get-AuthenticodeSignature -LiteralPath $file.FullName
$version=$file.VersionInfo
[pscustomobject][ordered]@{
    FileName=$file.Name
    Size=$file.Length
    SHA256=$hash.Hash
    ProductName=$version.ProductName
    ProductVersion=$version.ProductVersion
    FileVersion=$version.FileVersion
    CompanyName=$version.CompanyName
    OriginalFilename=$version.OriginalFilename
    SignatureStatus=[string]$signature.Status
    SignatureMessage=$signature.StatusMessage
    SignerSubject=$(if($signature.SignerCertificate){$signature.SignerCertificate.Subject}else{$null})
    SignerThumbprint=$(if($signature.SignerCertificate){$signature.SignerCertificate.Thumbprint}else{$null})
    Executed=$false
    Assessment='Metadata alone does not establish safety or correctness; compare with the original release and review the code.'
} | ConvertTo-Json -Depth 4
