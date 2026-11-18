param(
    [Parameter(Mandatory)][string]$SourceRoot,
    [Parameter(Mandatory)][string]$BuildManifest,
    [Parameter()][string]$NativeToolsPath,
    [switch]$SkipNativeDependency
)

. (Join-Path $PSScriptRoot 'common.ps1')
. (Join-Path $PSScriptRoot 'inject-lib.ps1')

$kitRoot = Get-CanonicalPath (Join-Path $PSScriptRoot '..')
$manifestPath = Get-CanonicalPath $BuildManifest
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$source = Assert-GeneratedWorktree `
    -RepoPath $manifest.repoPath `
    -SourceRoot $SourceRoot `
    -ExpectedCommit $manifest.upstreamCommit `
    -ProtectedRoots @($manifest.contributionCheckout, $manifest.personalKitWorktree)
if ($source -ine (Get-CanonicalPath $manifest.generatedWorktree)) {
    throw 'Verification SourceRoot does not match build manifest.'
}

$target = Join-Path $source 'lib\models_new\download\bili_download_entry_info.dart'
$text = [IO.File]::ReadAllText($target)
$newline = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
$expected = @(
    [ordered]@{
        id = 'download-entry-cache-export-import'
        begin = '// PILIPLUS_PRIVATE_CACHE_EXPORT_BEGIN import-v1'
        end = '// PILIPLUS_PRIVATE_CACHE_EXPORT_END import-v1'
        content = "// PILIPLUS_PRIVATE_CACHE_EXPORT_BEGIN import-v1`nimport 'package:PiliPlus/private/cache_exporter/launcher.dart';`n// PILIPLUS_PRIVATE_CACHE_EXPORT_END import-v1"
    },
    [ordered]@{
        id = 'download-entry-cache-export-menu'
        begin = '        // PILIPLUS_PRIVATE_CACHE_EXPORT_BEGIN menu-v2'
        end = '        // PILIPLUS_PRIVATE_CACHE_EXPORT_END menu-v2'
        content = @'
        // PILIPLUS_PRIVATE_CACHE_EXPORT_BEGIN menu-v2
        PopupMenuItem(
          height: 38,
          child: const Text('导出缓存', style: TextStyle(fontSize: 13)),
          onTap: () {
            final context = Get.context;
            if (context != null) {
              CacheExportLauncher.open(context, this);
            }
          },
        ),
        // PILIPLUS_PRIVATE_CACHE_EXPORT_END menu-v2
'@.TrimEnd()
    }
)
foreach ($rule in $expected) {
    [void](Assert-MarkerState $text $rule.begin $rule.end $rule.id)
    $content = $rule.content.Replace("`r`n", "`n").Replace("`n", $newline)
    if ((Get-ExactMatchCount $text $content) -ne 1) {
        throw "Verification failed for $($rule.id): exact injected block is missing or duplicated."
    }
}

$moduleRoot = Join-Path $kitRoot 'modules\cache_exporter'
$destinationRoot = Join-Path $source 'lib\private\cache_exporter'
$sourceFiles = @(Get-ChildItem -LiteralPath $moduleRoot -Recurse -File | Where-Object { $_.Name -ne 'module-manifest.json' })
foreach ($module in $sourceFiles) {
    $relative = $module.FullName.Substring($moduleRoot.Length).TrimStart([char]'\', [char]'/')
    $destination = Join-Path $destinationRoot $relative
    if (-not (Test-Path -LiteralPath $destination -PathType Leaf)) {
        throw "Verification failed: injected module is missing: $relative"
    }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $module.FullName).Hash -cne
        (Get-FileHash -Algorithm SHA256 -LiteralPath $destination).Hash) {
        throw "Verification failed: injected module hash differs: $relative"
    }
}
$testRoot = Join-Path $kitRoot 'tests'
$testDestination = Join-Path $source 'test\private_cache_exporter'
$testFiles = @(Get-ChildItem -LiteralPath $testRoot -Recurse -File)
foreach ($test in $testFiles) {
    $relative = $test.FullName.Substring($testRoot.Length).TrimStart([char]'\', [char]'/')
    $destination = Join-Path $testDestination $relative
    if (-not (Test-Path -LiteralPath $destination -PathType Leaf)) {
        throw "Verification failed: injected test is missing: $relative"
    }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $test.FullName).Hash -cne
        (Get-FileHash -Algorithm SHA256 -LiteralPath $destination).Hash) {
        throw "Verification failed: injected test hash differs: $relative"
    }
}
if (-not $SkipNativeDependency) {
    if (-not $NativeToolsPath) { throw 'NativeToolsPath is required unless SkipNativeDependency is set.' }
    $tools = Get-CanonicalPath $NativeToolsPath
    foreach ($name in @('ffmpeg.exe', 'ffprobe.exe')) {
        $file = Join-Path $tools $name
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
            throw "Verification failed: required native dependency is missing: $file"
        }
        & $file -version *> $null
        if ($LASTEXITCODE -ne 0) { throw "Verification failed: native dependency is not executable: $file" }
    }
}

$statusLines = @((Get-GitOutput $source @('status', '--porcelain', '--untracked-files=all')) -split "`n" | Where-Object { $_ })
$unexpected = @($statusLines | Where-Object {
    $_ -notmatch 'lib/private/cache_exporter/' -and
    $_ -notmatch 'lib/models_new/download/bili_download_entry_info.dart$' -and
    $_ -notmatch 'test/private_cache_exporter/'
})
if ($unexpected.Count -gt 0) {
    throw "Verification failed: unexpected generated worktree changes: $($unexpected -join '; ')"
}
$manifest | Add-Member -NotePropertyName verification -NotePropertyValue ([ordered]@{
    passed = $true
    verifiedAt = (Get-Date).ToString('o')
    moduleFileCount = $sourceFiles.Count
    testFileCount = $testFiles.Count
    nativeDependencies = -not $SkipNativeDependency
}) -Force
Write-JsonFile $manifest $manifestPath
Write-Output "Verified guarded private injection at $source"
