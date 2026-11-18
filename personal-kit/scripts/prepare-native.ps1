param([Parameter()][string]$CacheRoot)

. (Join-Path $PSScriptRoot 'common.ps1')

$kitRoot = Get-CanonicalPath (Join-Path $PSScriptRoot '..')
$config = Get-Content -LiteralPath (Join-Path $kitRoot 'config\native-dependencies.json') -Raw | ConvertFrom-Json
$dependency = $config.ffmpeg
if (-not $CacheRoot) { $CacheRoot = Join-Path $kitRoot '.cache\native' }
if (-not (Test-Path -LiteralPath $CacheRoot)) { New-Item -ItemType Directory -Path $CacheRoot | Out-Null }
$cache = Get-CanonicalPath $CacheRoot
$archive = Join-Path $cache $dependency.archiveName
if (-not (Test-Path -LiteralPath $archive -PathType Leaf)) {
    $temporary = "$archive.download"
    if (Test-Path -LiteralPath $temporary) {
        throw "A partial dependency download already exists for diagnosis: $temporary"
    }
    try {
        Invoke-WebRequest -Uri $dependency.url -OutFile $temporary -UseBasicParsing
        $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $temporary).Hash.ToLowerInvariant()
        if ($actual -cne $dependency.sha256) {
            throw "Downloaded FFmpeg archive hash mismatch. Expected $($dependency.sha256), found $actual. Partial file preserved: $temporary"
        }
        Move-Item -LiteralPath $temporary -Destination $archive
    } catch {
        throw
    }
}
$archiveHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $archive).Hash.ToLowerInvariant()
if ($archiveHash -cne $dependency.sha256) {
    throw "Cached FFmpeg archive hash mismatch. Expected $($dependency.sha256), found $archiveHash. Refusing to replace it automatically: $archive"
}
$extractRoot = Join-Path $cache $dependency.version
if (-not (Test-Path -LiteralPath $extractRoot -PathType Container)) {
    $extractTemporary = "$extractRoot.extracting"
    if (Test-Path -LiteralPath $extractTemporary) {
        throw "A partial dependency extraction already exists for diagnosis: $extractTemporary"
    }
    New-Item -ItemType Directory -Path $extractTemporary | Out-Null
    Expand-Archive -LiteralPath $archive -DestinationPath $extractTemporary
    Move-Item -LiteralPath $extractTemporary -Destination $extractRoot
}
$ffmpeg = @(Get-ChildItem -LiteralPath $extractRoot -Recurse -File -Filter ffmpeg.exe)
$ffprobe = @(Get-ChildItem -LiteralPath $extractRoot -Recurse -File -Filter ffprobe.exe)
if ($ffmpeg.Count -ne 1 -or $ffprobe.Count -ne 1) {
    throw "Pinned archive layout is incompatible: expected one ffmpeg.exe and one ffprobe.exe under $extractRoot"
}
if ($ffmpeg[0].Directory.FullName -ine $ffprobe[0].Directory.FullName) {
    throw 'Pinned FFmpeg executables are not colocated.'
}
[ordered]@{
    version = $dependency.version
    sourceCommit = $dependency.sourceCommit
    archive = $archive
    archiveSha256 = $archiveHash
    toolsDirectory = $ffmpeg[0].Directory.FullName
    ffmpegSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $ffmpeg[0].FullName).Hash.ToLowerInvariant()
    ffprobeSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $ffprobe[0].FullName).Hash.ToLowerInvariant()
} | ConvertTo-Json -Depth 4

