param(
    [Parameter(Mandatory)][string]$SourceRoot,
    [Parameter(Mandatory)][string]$BuildManifest,
    [Parameter(Mandatory)][string]$BaseFlutterRoot,
    [Parameter()][string]$WorktreePath
)

. (Join-Path $PSScriptRoot 'common.ps1')

$kitRoot = Get-CanonicalPath (Join-Path $PSScriptRoot '..')
$manifestPath = Get-CanonicalPath $BuildManifest
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$source = Assert-GeneratedWorktree `
    -RepoPath $manifest.repoPath `
    -SourceRoot $SourceRoot `
    -ExpectedCommit $manifest.upstreamCommit `
    -ProtectedRoots @($manifest.contributionCheckout, $manifest.personalKitWorktree)
if ($source -ine (Get-CanonicalPath $manifest.generatedWorktree)) {
    throw 'Patched Flutter preparation SourceRoot does not match the build manifest.'
}

$config = Get-Content -LiteralPath (Join-Path $kitRoot 'config\flutter-patches.json') -Raw | ConvertFrom-Json
if ($manifest.upstreamCommit -cne $config.lastVerifiedUpstreamCommit) {
    throw "Flutter patch rules were verified at $($config.lastVerifiedUpstreamCommit), not selected upstream $($manifest.upstreamCommit). Re-inspect upstream lib/scripts/patch.ps1 before updating the guarded rules."
}

$base = Get-CanonicalPath $BaseFlutterRoot
$baseCommit = Get-GitOutput $base @('rev-parse', 'HEAD')
if ($baseCommit -cne $config.flutterFrameworkCommit) {
    throw "Base Flutter SDK commit mismatch. Expected $($config.flutterFrameworkCommit), found $baseCommit."
}
$baseCache = Get-CanonicalPath (Join-Path $base 'bin\cache')
if (-not (Test-Path -LiteralPath (Join-Path $baseCache 'dart-sdk\bin\dart.exe') -PathType Leaf)) {
    throw "Base Flutter cache is incomplete: Dart is missing below $baseCache"
}

$driver = Join-Path $source $config.upstreamPatchDriver.path
if (-not (Test-Path -LiteralPath $driver -PathType Leaf)) {
    throw "Pinned upstream Flutter patch driver is missing: $driver"
}
$driverHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $driver).Hash.ToLowerInvariant()
if ($driverHash -cne $config.upstreamPatchDriver.sha256) {
    throw "Upstream Flutter patch driver drifted. Expected $($config.upstreamPatchDriver.sha256), found $driverHash. Re-inspect patch order before building."
}

$verifiedPatches = @()
foreach ($patch in $config.patches) {
    $patchPath = Join-Path $source $patch.path
    if (-not (Test-Path -LiteralPath $patchPath -PathType Leaf)) {
        throw "Required Flutter patch is missing: $($patch.path)"
    }
    $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $patchPath).Hash.ToLowerInvariant()
    if ($actualHash -cne $patch.sha256) {
        throw "Flutter patch drifted: $($patch.path). Expected $($patch.sha256), found $actualHash."
    }
    $verifiedPatches += [ordered]@{ path = $patch.path; sha256 = $actualHash }
}

if (-not $WorktreePath) {
    $WorktreePath = Join-Path (Split-Path -Parent $manifest.repoPath) "PiliPlus-private-flutter-$($manifest.buildId)"
}
$candidate = Get-CanonicalPath $WorktreePath -AllowMissing
if (Test-Path -LiteralPath $candidate) {
    throw "Patched Flutter worktree candidate already exists: $candidate"
}
foreach ($protected in @($manifest.contributionCheckout, $manifest.personalKitWorktree, $manifest.generatedWorktree, $base)) {
    if ($candidate -ieq (Get-CanonicalPath $protected)) {
        throw "Patched Flutter worktree overlaps a protected root: $candidate"
    }
}

Invoke-Native git @('-C', $base, 'worktree', 'add', '--quiet', '--detach', $candidate, $config.flutterFrameworkCommit)
$registered = Assert-GeneratedWorktree $base $candidate $config.flutterFrameworkCommit @(
    $manifest.contributionCheckout,
    $manifest.personalKitWorktree,
    $manifest.generatedWorktree,
    $base
)
$initialStatus = Get-GitOutput $registered @('status', '--porcelain', '--untracked-files=all')
if ($initialStatus) {
    throw "Fresh patched Flutter worktree is not clean: $initialStatus"
}

$worktreeCache = Join-Path $registered 'bin\cache'
if (Test-Path -LiteralPath $worktreeCache) {
    throw "Fresh Flutter worktree unexpectedly contains bin/cache: $worktreeCache"
}
New-Item -ItemType Junction -Path $worktreeCache -Target $baseCache | Out-Null
$cacheItem = Get-Item -LiteralPath $worktreeCache -Force
if ($cacheItem.LinkType -ne 'Junction' -or @($cacheItem.Target).Count -ne 1 -or
    (Get-CanonicalPath $cacheItem.Target[0]) -ine $baseCache) {
    throw "Flutter cache junction verification failed: $worktreeCache"
}

foreach ($patch in $verifiedPatches) {
    $patchPath = Join-Path $source $patch.path
    Invoke-Native git @('-C', $registered, 'apply', '--check', '--whitespace=nowarn', $patchPath)
    Invoke-Native git @('-C', $registered, 'apply', '--whitespace=nowarn', $patchPath)
}
Invoke-Native git @('-C', $registered, 'diff', '--check')
$patchedStatus = Get-GitOutput $registered @('status', '--porcelain', '--untracked-files=all')
if (-not $patchedStatus) {
    throw 'Flutter patch application produced no tracked changes.'
}

$flutter = Join-Path $registered 'bin\flutter.bat'
$dart = Join-Path $registered 'bin\cache\dart-sdk\bin\dart.exe'
if (-not (Test-Path -LiteralPath $flutter -PathType Leaf) -or
    -not (Test-Path -LiteralPath $dart -PathType Leaf)) {
    throw "Patched Flutter executables are missing below $registered"
}

$result = [ordered]@{
    frameworkCommit = $config.flutterFrameworkCommit
    worktree = $registered
    flutter = $flutter
    dart = $dart
    baseCache = $baseCache
    cacheReuse = 'windows-junction'
    patchDriver = [ordered]@{ path = $config.upstreamPatchDriver.path; sha256 = $driverHash }
    patches = $verifiedPatches
    patchedStatusSha256 = Get-StringSha256 $patchedStatus
}
$manifest | Add-Member -NotePropertyName patchedFlutter -NotePropertyValue $result -Force
Write-JsonFile $manifest $manifestPath
$result | ConvertTo-Json -Depth 8
