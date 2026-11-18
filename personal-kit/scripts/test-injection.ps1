param(
    [Parameter(Mandatory)][string]$SourceRoot,
    [Parameter(Mandatory)][string]$BuildManifest
)

. (Join-Path $PSScriptRoot 'common.ps1')

$manifest = Get-Content -LiteralPath $BuildManifest -Raw | ConvertFrom-Json
$baseline = $manifest.contributionFingerprint
$inject = Join-Path $PSScriptRoot 'inject.ps1'
$verify = Join-Path $PSScriptRoot 'verify.ps1'
$source = Get-CanonicalPath $SourceRoot
$target = Join-Path $source 'lib\models_new\download\bili_download_entry_info.dart'
$module = Join-Path $source 'lib\private\cache_exporter\domain.dart'

& $inject -SourceRoot $source -BuildManifest $BuildManifest
if ($LASTEXITCODE -ne 0) { throw 'Clean injection failed.' }
& $verify -SourceRoot $source -BuildManifest $BuildManifest -SkipNativeDependency
if ($LASTEXITCODE -ne 0) { throw 'Clean injection verification failed.' }
$firstDiff = Get-GitOutput $source @('diff', '--binary')
$firstUntracked = Get-GitOutput $source @('ls-files', '--others', '--exclude-standard')
& $inject -SourceRoot $source -BuildManifest $BuildManifest
if ($LASTEXITCODE -ne 0) { throw 'Idempotent reinjection failed.' }
$secondDiff = Get-GitOutput $source @('diff', '--binary')
$secondUntracked = Get-GitOutput $source @('ls-files', '--others', '--exclude-standard')
if ((Get-StringSha256 $firstDiff) -cne (Get-StringSha256 $secondDiff) -or
    (Get-StringSha256 $firstUntracked) -cne (Get-StringSha256 $secondUntracked)) {
    throw 'Reinjection changed the generated source tree.'
}

$originalTarget = [IO.File]::ReadAllText($target)
$originalModule = [IO.File]::ReadAllBytes($module)
try {
    $newline = if ($originalTarget.Contains("`r`n")) { "`r`n" } else { "`n" }
    $drifted = $originalTarget.Replace("import 'package:PiliPlus/pages/common/multi_select/base.dart'$newline    show MultiSelectData;", "import 'package:PiliPlus/pages/common/multi_select/base.dart' show MultiSelectData;")
    $drifted = $drifted.Replace("// PILIPLUS_PRIVATE_CACHE_EXPORT_BEGIN import-v1$newline" + "import 'package:PiliPlus/private/cache_exporter/launcher.dart';$newline" + "// PILIPLUS_PRIVATE_CACHE_EXPORT_END import-v1$newline", '')
    [IO.File]::WriteAllText($target, $drifted, [Text.UTF8Encoding]::new($false))
    $failed = $false
    try { & $inject -SourceRoot $source -BuildManifest $BuildManifest } catch { $failed = $true }
    if (-not $failed) { throw 'Changed-anchor fixture did not fail closed.' }
} finally {
    [IO.File]::WriteAllText($target, $originalTarget, [Text.UTF8Encoding]::new($false))
}

try {
    Remove-Item -LiteralPath $module
    $failed = $false
    try { & $verify -SourceRoot $source -BuildManifest $BuildManifest -SkipNativeDependency } catch { $failed = $true }
    if (-not $failed) { throw 'Missing-module fixture did not fail verification.' }
} finally {
    [IO.File]::WriteAllBytes($module, $originalModule)
}

$missingTools = Join-Path $source '.fixture-missing-native-tools'
$failed = $false
try { & $verify -SourceRoot $source -BuildManifest $BuildManifest -NativeToolsPath $missingTools } catch { $failed = $true }
if (-not $failed) { throw 'Missing-native-dependency fixture did not fail verification.' }

& $verify -SourceRoot $source -BuildManifest $BuildManifest -SkipNativeDependency
Assert-FingerprintEqual $baseline (Get-CheckoutFingerprint $manifest.repoPath)
[ordered]@{
    cleanInjection = $true
    idempotentReinjection = $true
    changedAnchorFails = $true
    missingModuleFails = $true
    missingNativeDependencyFails = $true
    contributionCheckoutUnchanged = $true
} | ConvertTo-Json
