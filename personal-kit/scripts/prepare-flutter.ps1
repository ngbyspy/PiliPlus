param([Parameter()][string]$CacheRoot)

. (Join-Path $PSScriptRoot 'common.ps1')

$kitRoot = Get-CanonicalPath (Join-Path $PSScriptRoot '..')
$config = Get-Content -LiteralPath (Join-Path $kitRoot 'config\native-dependencies.json') -Raw | ConvertFrom-Json
$dependency = $config.flutter
if (-not $CacheRoot) { $CacheRoot = Join-Path $kitRoot '.cache\flutter' }
if (-not (Test-Path -LiteralPath $CacheRoot)) { New-Item -ItemType Directory -Path $CacheRoot | Out-Null }
$cache = Get-CanonicalPath $CacheRoot
$archive = Join-Path $cache $dependency.archiveName
$sdkRoot = Join-Path $cache "flutter-$($dependency.version)"
$flutter = Join-Path $sdkRoot 'flutter\bin\flutter.bat'

function Get-FlutterMachineInfo {
    param([Parameter(Mandatory)][string]$FlutterPath)
    $output = @(& $FlutterPath --version --machine)
    if ($LASTEXITCODE -ne 0) { throw "Flutter identity command failed with exit code ${LASTEXITCODE}: $FlutterPath" }
    $start = -1
    for ($index = 0; $index -lt $output.Count; $index++) {
        if ($output[$index].TrimStart().StartsWith('{')) { $start = $index; break }
    }
    if ($start -lt 0) { throw "Flutter identity command produced no JSON object: $($output -join ' | ')" }
    return ($output[$start..($output.Count - 1)] -join "`n") | ConvertFrom-Json
}

if (Test-Path -LiteralPath $flutter -PathType Leaf) {
    $machine = Get-FlutterMachineInfo $flutter
    if ($machine.frameworkVersion -ne $dependency.version -or
        $machine.frameworkRevision -ne $dependency.frameworkCommit -or
        $machine.dartSdkVersion -ne $dependency.dartVersion) {
        throw "Cached Flutter identity mismatch: $($machine | ConvertTo-Json -Compress)"
    }
    [ordered]@{
        version=$machine.frameworkVersion
        frameworkCommit=$machine.frameworkRevision
        dartVersion=$machine.dartSdkVersion
        flutter=$flutter
        archiveSha256=$dependency.sha256
    }|ConvertTo-Json
    exit 0
}
if (-not (Test-Path -LiteralPath $archive -PathType Leaf)) {
    $temporary = "$archive.download"
    $existingLength = if (Test-Path -LiteralPath $temporary) { (Get-Item -LiteralPath $temporary).Length } else { 0 }
    if ($existingLength -gt $dependency.archiveSize) {
        throw "Partial Flutter download is larger than the pinned archive size: $temporary"
    }
    $driveName = [IO.Path]::GetPathRoot($cache).Substring(0, 1)
    $drive = Get-PSDrive -Name $driveName
    $remainingDownload = $dependency.archiveSize - $existingLength
    $minimumFree = $remainingDownload + ($dependency.archiveSize * 3)
    if ($drive.Free -lt $minimumFree) {
        throw "Insufficient free space for the pinned Flutter download and extraction. Required at least $minimumFree bytes, available $($drive.Free)."
    }
    Invoke-Native curl.exe @(
        '--fail', '--location', '--continue-at', '-',
        '--retry', '12', '--retry-all-errors', '--retry-delay', '5',
        '--output', $temporary, $dependency.url
    )
    $downloadedLength = (Get-Item -LiteralPath $temporary).Length
    if ($downloadedLength -ne $dependency.archiveSize) {
        throw "Flutter archive length mismatch after resumable download. Expected $($dependency.archiveSize), found $downloadedLength. Partial file preserved: $temporary"
    }
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $temporary).Hash.ToLowerInvariant()
    if ($actual -cne $dependency.sha256) {
        throw "Flutter archive hash mismatch. Expected $($dependency.sha256), found $actual. Partial file preserved: $temporary"
    }
    Move-Item -LiteralPath $temporary -Destination $archive
}
$archiveHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $archive).Hash.ToLowerInvariant()
if ($archiveHash -cne $dependency.sha256) {
    throw "Cached Flutter archive hash mismatch. Refusing automatic replacement: $archive"
}
$extractTemporary = "$sdkRoot.extracting"
if (Test-Path -LiteralPath $extractTemporary) { throw "Partial Flutter extraction preserved: $extractTemporary" }
New-Item -ItemType Directory -Path $extractTemporary | Out-Null
Invoke-Native tar @('-xf', $archive, '-C', $extractTemporary)
Move-Item -LiteralPath $extractTemporary -Destination $sdkRoot
if (-not (Test-Path -LiteralPath $flutter -PathType Leaf)) { throw "Flutter archive layout is incompatible: $flutter is missing." }
$machine = Get-FlutterMachineInfo $flutter
if ($LASTEXITCODE -ne 0 -or $machine.frameworkVersion -ne $dependency.version -or $machine.frameworkRevision -ne $dependency.frameworkCommit) {
    throw "Extracted Flutter identity mismatch: $($machine | ConvertTo-Json -Compress)"
}
[ordered]@{
    version = $machine.frameworkVersion
    frameworkCommit = $machine.frameworkRevision
    dartVersion = $machine.dartSdkVersion
    flutter = $flutter
    archive = $archive
    archiveSha256 = $archiveHash
} | ConvertTo-Json -Depth 4
