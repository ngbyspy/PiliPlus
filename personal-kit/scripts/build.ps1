param(
    [Parameter()][string]$RepoPath = 'D:\Projects\PiliPlus',
    [Parameter()][string]$UpstreamRevision = 'upstream/main',
    [switch]$KeepWorktree,
    [switch]$SkipFetch,
    [switch]$SkipBuild
)

. (Join-Path $PSScriptRoot 'common.ps1')

$kitRoot = Get-CanonicalPath (Join-Path $PSScriptRoot '..')
$personal = Get-CanonicalPath (Join-Path $kitRoot '..')
$repo = Get-CanonicalPath $RepoPath
$stateRoot = Join-Path $kitRoot '.state'
$distRoot = Join-Path $kitRoot 'dist'
foreach ($directory in @($stateRoot, $distRoot)) {
    if (-not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory | Out-Null }
}
$preflight = & (Join-Path $PSScriptRoot 'preflight.ps1') -RepoPath $repo -PersonalKitWorktree $personal | ConvertFrom-Json
$baseline = $preflight.contribution
$fetch = [ordered]@{attempted = -not $SkipFetch; succeeded = $false; method = $null; error = $null; fallback = $null}
if (-not $SkipFetch) {
    try {
        Invoke-Native git @('-C', $repo, '-c', 'http.version=HTTP/1.1', 'fetch', 'upstream', 'main', '--prune')
        $fetch.succeeded = $true
        $fetch.method = 'git-smart-http'
    } catch {
        $fetch.error = $_.Exception.Message
        $headers = @{Accept = 'application/vnd.github+json'; 'X-GitHub-Api-Version' = '2022-11-28'}
        $latest = Invoke-RestMethod -Headers $headers -Uri 'https://api.github.com/repos/bggRGjQaUbCoE/PiliPlus/commits/main'
        if ($latest.sha -notmatch '^[0-9a-f]{40}$') { throw "Git fetch failed and GitHub REST returned an invalid main SHA. $($fetch.error)" }
        $fallbackOutput = @(& (Join-Path $PSScriptRoot 'import-upstream-rest.ps1') -RepoPath $repo -CommitSha $latest.sha)
        $fallbackOutput | Select-Object -SkipLast 1 | ForEach-Object { Write-Output $_ }
        $fallback = $fallbackOutput[-1] | ConvertFrom-Json
        $fetch.succeeded = $true
        $fetch.method = 'github-rest-content-addressed-import'
        $fetch.fallback = $fallback
    }
}
$upstreamCommit = Get-GitOutput $repo @('rev-parse', "$UpstreamRevision^{commit}")
$selectedFvmrc = Get-GitOutput $repo @('show', "$upstreamCommit`:.fvmrc") | ConvertFrom-Json
$selectedPubspec = Get-GitOutput $repo @('show', "$upstreamCommit`:pubspec.yaml")
$selectedPubspecFlutter = ([regex]::Match($selectedPubspec, '(?m)^  flutter:\s*(\S+)')).Groups[1].Value
if (-not $selectedFvmrc.flutter -or $selectedFvmrc.flutter -ne $selectedPubspecFlutter) {
    throw "Selected upstream Flutter pins disagree: .fvmrc=$($selectedFvmrc.flutter), pubspec=$selectedPubspecFlutter"
}
$dependencyConfig = Get-Content -LiteralPath (Join-Path $kitRoot 'config\native-dependencies.json') -Raw | ConvertFrom-Json
if ($dependencyConfig.flutter.version -ne $selectedFvmrc.flutter) {
    throw "Pinned Flutter archive does not match selected upstream: configured=$($dependencyConfig.flutter.version), selected=$($selectedFvmrc.flutter)"
}
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$generated = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $repo) "PiliPlus-private-build-$timestamp"))
if (Test-Path -LiteralPath $generated) { throw "Generated worktree candidate already exists: $generated" }
$kitIdentity = Get-KitIdentity $personal
$manifestPath = Join-Path $stateRoot "build-$timestamp.json"
$manifest = [ordered]@{
    schemaVersion = 1
    buildId = $timestamp
    platform = 'windows'
    repoPath = $repo
    contributionCheckout = $repo
    contributionFingerprint = $baseline
    personalKitWorktree = $personal
    personalKitIdentity = $kitIdentity
    upstreamRevision = $UpstreamRevision
    upstreamCommit = $upstreamCommit
    upstreamFetch = $fetch
    generatedWorktree = $generated
    flutterVersion = $selectedFvmrc.flutter
    nativeDependencyHashes = [ordered]@{}
    validation = [ordered]@{
        preflight = $true
        generatedWorktree = $false
        injection = $false
        reinjection = $false
        driftFixture = $false
        missingModuleFixture = $false
        missingNativeDependencyFixture = $false
        nativeDependencies = $false
        flutterPatches = $false
        pubGet = $false
        format = $false
        focusedAnalyze = $false
        fullAnalyze = $false
        tests = $false
        windowsRelease = $false
        contributionCheckoutUnchanged = $false
    }
    artifacts = @()
}
Write-JsonFile $manifest $manifestPath
$succeeded = $false
try {
    Invoke-Native git @('-C', $repo, 'worktree', 'add', '--detach', $generated, $upstreamCommit)
    [void](Assert-GeneratedWorktree $repo $generated $upstreamCommit @($repo, $personal))
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $manifest.validation.generatedWorktree = $true
    Write-JsonFile $manifest $manifestPath
    Write-Host "[private-build] Injecting and testing guarded integration in $generated"
    & (Join-Path $PSScriptRoot 'inject.ps1') -SourceRoot $generated -BuildManifest $manifestPath
    $injectionTestOutput = @(& (Join-Path $PSScriptRoot 'test-injection.ps1') -SourceRoot $generated -BuildManifest $manifestPath)
    if ($injectionTestOutput.Count -eq 0) { throw 'Injection test script produced no result.' }
    $injectionTests = $injectionTestOutput[-1] | ConvertFrom-Json
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $manifest.validation.injection = [bool]$injectionTests.cleanInjection
    $manifest.validation.reinjection = [bool]$injectionTests.idempotentReinjection
    $manifest.validation.driftFixture = [bool]$injectionTests.changedAnchorFails
    $manifest.validation.missingModuleFixture = [bool]$injectionTests.missingModuleFails
    $manifest.validation.missingNativeDependencyFixture = [bool]$injectionTests.missingNativeDependencyFails
    Write-JsonFile $manifest $manifestPath

    Write-Host '[private-build] Verifying pinned FFmpeg and Flutter dependencies'
    $native = & (Join-Path $PSScriptRoot 'prepare-native.ps1') | ConvertFrom-Json
    $flutterInfo = & (Join-Path $PSScriptRoot 'prepare-flutter.ps1') | ConvertFrom-Json
    $baseFlutterRoot = Get-CanonicalPath (Join-Path (Split-Path -Parent $flutterInfo.flutter) '..')
    $patchedFlutterInfo = & (Join-Path $PSScriptRoot 'prepare-patched-flutter.ps1') `
        -SourceRoot $generated `
        -BuildManifest $manifestPath `
        -BaseFlutterRoot $baseFlutterRoot | ConvertFrom-Json
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $manifest.nativeDependencyHashes = [ordered]@{
        ffmpegArchive = $native.archiveSha256
        ffmpegExe = $native.ffmpegSha256
        ffprobeExe = $native.ffprobeSha256
        flutterArchive = $flutterInfo.archiveSha256
        flutterFrameworkCommit = $flutterInfo.frameworkCommit
    }
    $manifest.validation.nativeDependencies = $true
    $manifest.validation.flutterPatches = $true
    Write-JsonFile $manifest $manifestPath
    & (Join-Path $PSScriptRoot 'verify.ps1') -SourceRoot $generated -BuildManifest $manifestPath -NativeToolsPath $native.toolsDirectory

    $flutter = $patchedFlutterInfo.flutter
    $dart = $patchedFlutterInfo.dart
    if (-not (Test-Path -LiteralPath $dart -PathType Leaf)) { throw "Pinned Dart executable is missing: $dart" }
    $changedDart = @(
        Get-ChildItem -LiteralPath (Join-Path $generated 'lib\private\cache_exporter') -File -Filter '*.dart' | ForEach-Object FullName
        Get-ChildItem -LiteralPath (Join-Path $generated 'test\private_cache_exporter') -File -Filter '*.dart' | ForEach-Object FullName
        Join-Path $generated 'lib\models_new\download\bili_download_entry_info.dart'
    )
    $kitDart = @(
        Get-ChildItem -LiteralPath (Join-Path $kitRoot 'modules\cache_exporter') -File -Filter '*.dart' | ForEach-Object FullName
        Get-ChildItem -LiteralPath (Join-Path $kitRoot 'tests') -File -Filter '*.dart' | ForEach-Object FullName
    )
    Invoke-Native $dart (@(
        'format',
        '--language-version', '3.12',
        '--trailing-commas', 'preserve',
        '--output=none',
        '--set-exit-if-changed'
    ) + $kitDart) $kitRoot
    Write-Host '[private-build] Resolving packages and formatting injected Dart sources'
    Invoke-Native $flutter (@('pub', 'get')) $generated
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $manifest.validation.pubGet = $true
    Write-JsonFile $manifest $manifestPath
    Invoke-Native $dart (@('format') + $changedDart) $generated
    Invoke-Native $dart (@('format', '--output=none', '--set-exit-if-changed') + $changedDart) $generated
    & (Join-Path $PSScriptRoot 'verify.ps1') -SourceRoot $generated -BuildManifest $manifestPath -NativeToolsPath $native.toolsDirectory
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $manifest.validation.format = $true
    Write-JsonFile $manifest $manifestPath
    Write-Host '[private-build] Running strict focused static analysis'
    Invoke-Native $flutter @(
        'analyze', '--no-pub', '--fatal-infos',
        'lib/private/cache_exporter',
        'lib/models_new/download/bili_download_entry_info.dart',
        'test/private_cache_exporter'
    ) $generated
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $manifest.validation.focusedAnalyze = $true
    Write-JsonFile $manifest $manifestPath
    Write-Host '[private-build] Running full static analysis (upstream info diagnostics are non-fatal)'
    Invoke-Native $flutter @('analyze', '--no-pub', '--no-fatal-infos') $generated
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $manifest.validation.fullAnalyze = $true
    $manifest | Add-Member -NotePropertyName analysisPolicy -NotePropertyValue ([ordered]@{
        focused = 'fatal errors, warnings, and infos'
        fullRepository = 'fatal errors and warnings; upstream infos reported but non-fatal'
    }) -Force
    Write-JsonFile $manifest $manifestPath
    Write-Host '[private-build] Running private cache exporter tests'
    Invoke-Native $flutter @('test', '--no-pub', 'test/private_cache_exporter') $generated
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $manifest.validation.tests = $true
    Write-JsonFile $manifest $manifestPath

    if (-not $SkipBuild) {
        Write-Host '[private-build] Compiling Windows release'
        Invoke-Native $flutter @('build', 'windows', '--release', '--no-pub') $generated
        $release = Join-Path $generated 'build\windows\x64\runner\Release'
        if (-not (Test-Path -LiteralPath $release -PathType Container)) { throw "Windows release output is missing: $release" }
        $privateTools = Join-Path $release 'private_tools'
        if (-not (Test-Path -LiteralPath $privateTools)) { New-Item -ItemType Directory -Path $privateTools | Out-Null }
        Copy-Item -LiteralPath (Join-Path $native.toolsDirectory 'ffmpeg.exe') -Destination $privateTools
        Copy-Item -LiteralPath (Join-Path $native.toolsDirectory 'ffprobe.exe') -Destination $privateTools
        $artifactRoot = Join-Path $distRoot "windows-$timestamp-$($upstreamCommit.Substring(0, 12))"
        if (Test-Path -LiteralPath $artifactRoot) { throw "Artifact output already exists: $artifactRoot" }
        Copy-Item -LiteralPath $release -Destination $artifactRoot -Recurse
        $zipPath = "$artifactRoot.zip"
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $manifest.validation.windowsRelease = $true
        $manifest.artifacts = @(
            [ordered]@{path=$artifactRoot;type='windows-release-directory'},
            [ordered]@{path=$zipPath;type='windows-portable-zip'}
        )
        $reportPath = Join-Path $artifactRoot 'private-build-report.json'
        $manifest.validation.contributionCheckoutUnchanged = $true
        $manifest.completedAt = (Get-Date).ToString('o')
        Write-JsonFile $manifest $reportPath
        Compress-Archive -LiteralPath $artifactRoot -DestinationPath $zipPath
        $manifest.artifacts[1] | Add-Member -NotePropertyName sha256 -NotePropertyValue ((Get-FileHash -Algorithm SHA256 -LiteralPath $zipPath).Hash.ToLowerInvariant()) -Force
        $externalReportPath = "$artifactRoot-private-build-report.json"
        $manifest | Add-Member -NotePropertyName buildReport -NotePropertyValue $externalReportPath -Force
        Write-JsonFile $manifest $externalReportPath
        Write-JsonFile $manifest $manifestPath
    }
    Assert-FingerprintEqual $baseline (Get-CheckoutFingerprint $repo)
    if ($SkipBuild) {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $manifest.validation.contributionCheckoutUnchanged = $true
        $manifest.completedAt = (Get-Date).ToString('o')
        Write-JsonFile $manifest $manifestPath
    }
    $succeeded = $true
} finally {
    $actual = Get-CheckoutFingerprint $repo
    Assert-FingerprintEqual $baseline $actual
    if ($succeeded -and -not $KeepWorktree) {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $candidate = Assert-GeneratedWorktree $repo $manifest.generatedWorktree $manifest.upstreamCommit @($repo, $personal)
        if ($candidate -ine $generated) { throw 'Cleanup path does not match the in-memory generated path.' }
        Invoke-Native git @('-C', $repo, 'worktree', 'remove', $candidate)
    } else {
        Write-Warning "Generated worktree preserved: $generated"
    }
}

Write-Output "Build manifest: $manifestPath"
