param([string]$ProxyUrl)
. (Join-Path $PSScriptRoot 'common.ps1')
$kitRoot = Get-CanonicalPath (Join-Path $PSScriptRoot '..')
$config = Get-Content -LiteralPath (Join-Path $kitRoot 'config/watchroom-windows-tools.json') -Raw | ConvertFrom-Json
$directory = Join-Path $kitRoot '.cache/windows-build-tools'
New-Item -ItemType Directory -Path $directory -Force | Out-Null
$exe = Join-Path $directory 'nuget.exe'
if (-not (Test-Path -LiteralPath $exe)) {
    & curl.exe --fail --silent --show-error --location --retry 2 --noproxy '*' --output $exe $config.nugetUrl
    if ($LASTEXITCODE -ne 0 -and $ProxyUrl) {
        Invoke-Native curl.exe @('--fail','--silent','--show-error','--location','--retry','2','--proxy',$ProxyUrl,'--output',$exe,$config.nugetUrl)
    } elseif ($LASTEXITCODE -ne 0) { throw 'Official NuGet download failed' }
}
if ((Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant() -ne $config.nugetSha256) { throw 'NuGet content hash mismatch' }
$signature = Get-AuthenticodeSignature -LiteralPath $exe
if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') { throw 'NuGet Microsoft signature verification failed' }
$env:PATH = $directory + [IO.Path]::PathSeparator + $env:PATH
# This session's configured proxy cannot complete NuGet CDN TLS; direct HTTPS
# works. Keep this exception local to the build process.
$env:NO_PROXY = (@($env:NO_PROXY,'nuget.org','.nuget.org','api.nuget.org','globalcdn.nuget.org','dist.nuget.org','nuget.azure.cn','.azure.cn') | Where-Object { $_ }) -join ','
Write-Output "Verified Microsoft NuGet $($config.nugetVersion) in the private build tools cache."
