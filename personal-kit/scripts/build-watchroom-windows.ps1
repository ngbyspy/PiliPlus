param(
    [Parameter(Mandatory)][string]$BuildManifest,
    [string]$ProxyUrl,
    [switch]$SkipValidatedChecks
)
. (Join-Path $PSScriptRoot 'common.ps1')
. (Join-Path $PSScriptRoot 'watchroom-source.ps1')
$kitRoot = Get-CanonicalPath (Join-Path $PSScriptRoot '..')
$manifestPath = Get-CanonicalPath $BuildManifest
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($manifest.platform -ne 'windows') { throw 'Expected a Windows watchroom manifest' }
$source = Assert-GeneratedWorktree $manifest.repoPath $manifest.generatedWorktree $manifest.upstreamCommit @($manifest.contributionCheckout,$manifest.personalKitWorktree)
Assert-FingerprintEqual $manifest.contributionFingerprint (Get-CheckoutFingerprint $manifest.contributionCheckout)
if ($ProxyUrl) {
    $proxy = [uri]$ProxyUrl
    if ($proxy.Scheme -ne 'http' -or $proxy.UserInfo) { throw 'Expected an HTTP proxy without credentials' }
    $env:HTTP_PROXY = $ProxyUrl; $env:HTTPS_PROXY = $ProxyUrl
    $env:GIT_CONFIG_COUNT='1'; $env:GIT_CONFIG_KEY_0='http.proxy'; $env:GIT_CONFIG_VALUE_0=$ProxyUrl
}
& (Join-Path $PSScriptRoot 'prepare-watchroom-windows-tools.ps1') -ProxyUrl $ProxyUrl
& (Join-Path $PSScriptRoot 'prepare-watchroom-sdk.ps1') -BuildManifest $manifestPath -Platform Windows
& (Join-Path $PSScriptRoot 'inject-watchroom.ps1') -SourceRoot $source -BuildManifest $manifestPath -VerifyOnly
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$flutter = Join-Path $manifest.watchroomFlutter.root 'bin/flutter.bat'
Invoke-Native $flutter @('pub','get','--offline') -WorkingDirectory $source
& (Join-Path $PSScriptRoot 'prepare-watchroom-material.ps1') -SourceRoot $source -BuildManifest $manifestPath -Platform Windows
Invoke-Native $flutter @('pub','get','--offline') -WorkingDirectory $source
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$inputHash = Get-WatchroomSourceHash $manifest
if ($SkipValidatedChecks) {
    if (-not $manifest.validation.focusedAnalyze -or -not $manifest.validation.tests -or
        $manifest.validation.sourceSha256 -cne $inputHash) { throw 'The current source has no matching successful validation; do not skip checks' }
} else {
    Invoke-Native $flutter @('analyze','--no-pub','--no-fatal-infos','lib/private/watchroom','lib/main.dart','lib/utils/cache_manager.dart','lib/utils/desktop/window_controller.dart','lib/pages/mine/view.dart','lib/utils/app_scheme.dart','lib/pages/video/controller.dart','lib/pages/video/view.dart','lib/pages/video/introduction/pgc/view.dart','lib/pages/video/introduction/pgc/controller.dart','lib/models_new/pgc/pgc_info_model/result.dart','lib/plugin/pl_player/controller.dart','lib/pages/video/widgets/header_control.dart','lib/pages/video/widgets/player_focus.dart','lib/pages/history/view.dart','lib/pages/history/widgets/item.dart','test/private_watchroom') -WorkingDirectory $source
    Invoke-Native $flutter @('test','--no-pub','test/private_watchroom') -WorkingDirectory $source
    $manifest.validation = @{focusedAnalyze=$true;tests=$true;sourceSha256=$inputHash}
}
$version = [regex]::Match([IO.File]::ReadAllText((Join-Path $source 'pubspec.yaml')),'(?m)^version:\s*([^+\s]+)').Groups[1].Value
if (-not $version) { throw 'Missing upstream application version' }
$defines = Join-Path $kitRoot ".cache/$($manifest.buildId)-release.json"
Write-JsonFile @{'pili.name'="$version-watchroom";'pili.code'=[int](Get-GitOutput $source @('rev-list','--count','HEAD'));'pili.hash'=$manifest.upstreamCommit;'pili.time'=[DateTimeOffset]::Now.ToUnixTimeSeconds()} $defines
Write-JsonFile $manifest $manifestPath
Invoke-Native $flutter @('build','windows','--release','--no-pub',"--dart-define-from-file=$defines") -WorkingDirectory $source
$bundle = Join-Path $source 'build/windows/x64/runner/Release'
$exe = Join-Path $bundle 'piliplus_watchroom.exe'
if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw 'Windows build did not produce the private executable' }
$output = Join-Path $kitRoot "dist/watchroom/windows/$($manifest.buildId)"
if (Test-Path -LiteralPath $output) { throw 'Artifact directory exists; preserve it and choose a new buildId' }
New-Item -ItemType Directory -Path $output -Force | Out-Null
Copy-Item -Path (Join-Path $bundle '*') -Destination $output -Recurse
$zip = "$output.zip"
Compress-Archive -Path (Join-Path $output '*') -DestinationPath $zip
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$manifest | Add-Member -NotePropertyName personalKitIdentity -NotePropertyValue (Get-KitIdentity $manifest.personalKitWorktree) -Force
$manifest | Add-Member -NotePropertyName watchroomWindowsBuild -NotePropertyValue @{
    builtOn=(Get-Date -Format 'yyyy-MM-dd');flutterVersion='3.47.9';configuration='release';version="$version-watchroom";
    directory=$output;executable=(Join-Path $output 'piliplus_watchroom.exe');executableSha256=(Get-FileHash -LiteralPath (Join-Path $output 'piliplus_watchroom.exe')).Hash.ToLowerInvariant();
    zip=$zip;zipSha256=(Get-FileHash -LiteralPath $zip).Hash.ToLowerInvariant();dependencyLockSha256=(Get-FileHash -LiteralPath (Join-Path $source 'pubspec.lock')).Hash.ToLowerInvariant();
    sourceSha256=$inputHash;launched=$false;realRoomValidationCompleted=$false;profileSubdirectory='watchroom-windows'
} -Force
Assert-FingerprintEqual $manifest.contributionFingerprint (Get-CheckoutFingerprint $manifest.contributionCheckout)
Write-JsonFile $manifest $manifestPath
& (Join-Path $PSScriptRoot 'verify-watchroom-windows.ps1') -BuildManifest $manifestPath
Write-Output "Windows watchroom portable: $zip"
