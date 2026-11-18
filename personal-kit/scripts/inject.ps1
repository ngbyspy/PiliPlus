param(
    [Parameter(Mandatory)][string]$SourceRoot,
    [Parameter(Mandatory)][string]$BuildManifest
)

. (Join-Path $PSScriptRoot 'common.ps1')
. (Join-Path $PSScriptRoot 'inject-lib.ps1')

$kitRoot = Get-CanonicalPath (Join-Path $PSScriptRoot '..')
$personalWorktree = Get-CanonicalPath (Join-Path $kitRoot '..')
$manifestPath = Get-CanonicalPath $BuildManifest
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$source = Assert-GeneratedWorktree `
    -RepoPath $manifest.repoPath `
    -SourceRoot $SourceRoot `
    -ExpectedCommit $manifest.upstreamCommit `
    -ProtectedRoots @($manifest.contributionCheckout, $manifest.personalKitWorktree)
if ($source -ine (Get-CanonicalPath $manifest.generatedWorktree)) {
    throw 'Explicit SourceRoot does not match the build manifest generatedWorktree.'
}

$status = Get-GitOutput $source @('status', '--porcelain', '--untracked-files=all')
$alreadyInjected = $status -match 'lib/private/cache_exporter/' -or $status -match 'bili_download_entry_info.dart'
if ($status -and -not $alreadyInjected) {
    throw "Generated source worktree was not clean before first injection: $status"
}
if ($status) {
    $unexpectedStatus = @($status -split "`n" | Where-Object {
        $_ -and
        $_ -notmatch 'lib/private/cache_exporter/' -and
        $_ -notmatch 'lib/models_new/download/bili_download_entry_info.dart$' -and
        $_ -notmatch 'test/private_cache_exporter/'
    })
    if ($unexpectedStatus.Count -gt 0) {
        throw "Generated source worktree contains changes outside explicit injection outputs: $($unexpectedStatus -join '; ')"
    }
}

$moduleRoot = Join-Path $kitRoot 'modules\cache_exporter'
$destinationRoot = Join-Path $source 'lib\private\cache_exporter'
Copy-GuardedModuleTree -ModuleRoot $moduleRoot -DestinationRoot $destinationRoot
$testRoot = Join-Path $kitRoot 'tests'
$testDestination = Join-Path $source 'test\private_cache_exporter'
Copy-GuardedModuleTree -ModuleRoot $testRoot -DestinationRoot $testDestination

$target = Join-Path $source 'lib\models_new\download\bili_download_entry_info.dart'
$preInjectionText = [IO.File]::ReadAllText($target)
foreach ($legacy in @('PILIPLUS_PRIVATE_CACHE_EXPORT_BEGIN menu-v1', 'PILIPLUS_PRIVATE_CACHE_EXPORT_END menu-v1')) {
    if ($preInjectionText.Contains($legacy)) {
        throw "Legacy or unexpected private marker found ($legacy). Refusing to layer a new injection over an old generated tree."
    }
}
$importAnchor = "import 'package:PiliPlus/pages/common/multi_select/base.dart'`n    show MultiSelectData;"
$importText = "import 'package:PiliPlus/private/cache_exporter/launcher.dart';"
[void](Invoke-GuardedTextInjection `
    -TargetPath $target `
    -RuleId 'download-entry-cache-export-import' `
    -Anchor $importAnchor `
    -ExpectedMatches 1 `
    -BeginMarker '// PILIPLUS_PRIVATE_CACHE_EXPORT_BEGIN import-v1' `
    -EndMarker '// PILIPLUS_PRIVATE_CACHE_EXPORT_END import-v1' `
    -InjectedText $importText `
    -Position After `
    -Diagnostic 'The download entry imports changed; inspect the selected upstream commit.')

$menuAnchor = "      itemBuilder: (_) => ["
$menuText = @'
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
'@.TrimEnd()
[void](Invoke-GuardedTextInjection `
    -TargetPath $target `
    -RuleId 'download-entry-cache-export-menu' `
    -Anchor $menuAnchor `
    -ExpectedMatches 1 `
    -BeginMarker '        // PILIPLUS_PRIVATE_CACHE_EXPORT_BEGIN menu-v2' `
    -EndMarker '        // PILIPLUS_PRIVATE_CACHE_EXPORT_END menu-v2' `
    -InjectedText $menuText `
    -Position After `
    -Diagnostic 'The completed-download popup menu changed; inspect the narrow UI entry point.')

$integration = @(
    [ordered]@{ id = 'download-entry-cache-export-import'; version = 1; target = 'lib/models_new/download/bili_download_entry_info.dart' },
    [ordered]@{ id = 'download-entry-cache-export-menu'; version = 2; target = 'lib/models_new/download/bili_download_entry_info.dart' }
)
$manifest | Add-Member -NotePropertyName injectionRules -NotePropertyValue $integration -Force
$manifest | Add-Member -NotePropertyName injectionCompletedAt -NotePropertyValue (Get-Date).ToString('o') -Force
Write-JsonFile $manifest $manifestPath
Write-Output "Private cache exporter injected and idempotently verified at $source"
