param(
    [Parameter(Mandatory)][string]$ReportPath,
    [string]$ArtifactPath,
    [string]$ReleaseRoot = (Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) 'Releases')
)
$ErrorActionPreference = 'Stop'
$report = Get-Content -LiteralPath $ReportPath -Raw | ConvertFrom-Json
if ($report.PSObject.Properties['failure']) { throw 'Cannot register a failed build' }
if (-not $report.validation.analysis -or -not $report.validation.tests) { throw 'Build validation is incomplete' }
if (-not $ArtifactPath) { $ArtifactPath = $report.artifact.path }
if ((Get-FileHash -LiteralPath $ArtifactPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $report.artifact.sha256) { throw 'Release package checksum mismatch' }
$platform = switch ($report.platform) { 'Windows' {'Windows'} 'Android' {'Android'} 'iOS' {'iPad'} default {throw 'Unsupported platform'} }
$tag = $report.release.tag
if ($tag -notmatch '^spy-v[0-9A-Za-z._-]+$') { throw 'Unsafe version directory' }
$directory = Join-Path $ReleaseRoot $tag
$assets = Join-Path $directory $platform
$metadata = Join-Path $directory '_metadata'
New-Item -ItemType Directory -Path $assets,$metadata -Force | Out-Null
$name = Split-Path -Leaf $ArtifactPath
$destination = Join-Path $assets $name
if (Test-Path -LiteralPath $destination) {
    if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant() -cne $report.artifact.sha256) { throw 'Existing release asset differs; use a new version instead of replacing it' }
} else { Copy-Item -LiteralPath $ArtifactPath -Destination $destination }
$manifestPath = Join-Path $metadata 'release-manifest.json'
if (Test-Path -LiteralPath $manifestPath) { $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json }
else {
    $manifest = [pscustomobject]@{product='PiliPlus-SPY';version=$report.release.displayVersion;title=$report.release.displayVersion;date=[DateTime]::Now.ToString('yyyy-MM-dd');historical=$false;highlights=@('与 B 站官方网页、客户端互通的放映厅。','首次安装 SPY 需登录；IPA 由用户自行签名。');pendingPlatforms=@();artifacts=@()}
}
$entry = [pscustomobject]@{platform=$platform;file="$platform/$name";sha256=$report.artifact.sha256;bytes=(Get-Item -LiteralPath $destination).Length;sourceCommit=$report.sourceCommit}
$manifest.artifacts = @($manifest.artifacts | Where-Object platform -ne $platform) + @($entry)
$completed = @($manifest.artifacts | ForEach-Object platform)
$manifest.pendingPlatforms = @(@('Windows','Android','iPad') | Where-Object { $_ -notin $completed })
$encoding = [Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText($manifestPath,($manifest | ConvertTo-Json -Depth 30)+"`n",$encoding)
$report.artifact.path = $destination
[IO.File]::WriteAllText((Join-Path $metadata "build-$($report.platform.ToLowerInvariant()).json"),($report | ConvertTo-Json -Depth 30)+"`n",$encoding)
$hashes = @($manifest.artifacts | ForEach-Object { "$($_.sha256)  $($_.file)" })
[IO.File]::WriteAllText((Join-Path $metadata 'SHA256SUMS.txt'),($hashes -join "`n")+"`n",$encoding)
& (Join-Path $PSScriptRoot 'render-releases.ps1') -ReleaseRoot $ReleaseRoot
Write-Output "Registered $platform $($manifest.version) in the local release page."
