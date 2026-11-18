param(
    [Parameter(Mandatory)][string]$BuildManifest,
    [string]$FlutterRoot,
    [string]$ProxyUrl,
    [switch]$Install
)
. (Join-Path $PSScriptRoot 'common.ps1')
$manifestPath = Get-CanonicalPath $BuildManifest
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$kitRoot = Get-CanonicalPath (Join-Path $PSScriptRoot '..')
$source = Assert-GeneratedWorktree $manifest.repoPath $manifest.generatedWorktree $manifest.upstreamCommit @($manifest.contributionCheckout,$manifest.personalKitWorktree)
& (Join-Path $PSScriptRoot 'prepare-watchroom-sdk.ps1') -BuildManifest $manifestPath
$pubspec = [IO.File]::ReadAllText((Join-Path $source 'pubspec.yaml'))
$version = [regex]::Match($pubspec,'(?m)^\s+flutter: (\d+\.\d+\.\d+)\s*$').Groups[1].Value
if (-not $version) { throw 'Cannot identify the current upstream Flutter pin' }
if (-not $FlutterRoot) { $FlutterRoot = Join-Path $kitRoot ".cache/flutter/flutter-$version/flutter" }
$flutter = Join-Path (Get-CanonicalPath $FlutterRoot) 'bin/flutter.bat'
$info = @(& $flutter --version --machine)
if ($LASTEXITCODE -ne 0) { throw 'Cannot read Flutter toolchain identity' }
$start = 0
while($start -lt $info.Count -and -not $info[$start].TrimStart().StartsWith('{')) { $start++ }
if ($start -ge $info.Count) { throw 'Flutter identity is not JSON' }
$machine = ($info[$start..($info.Count-1)] -join "`n") | ConvertFrom-Json
if ($machine.frameworkVersion -ne $version) { throw "Flutter pin mismatch: upstream requires $version" }
if ($ProxyUrl) {
    $proxy = [uri]$ProxyUrl
    if ($proxy.Scheme -ne 'http' -or $proxy.UserInfo) { throw 'Use an HTTP proxy without credentials' }
    $env:HTTP_PROXY = $ProxyUrl; $env:HTTPS_PROXY = $ProxyUrl
    $env:GIT_CONFIG_COUNT='1'; $env:GIT_CONFIG_KEY_0='http.proxy'; $env:GIT_CONFIG_VALUE_0=$ProxyUrl
    $env:JAVA_TOOL_OPTIONS="-Dhttps.proxyHost=$($proxy.Host) -Dhttps.proxyPort=$($proxy.Port) -Dhttp.proxyHost=$($proxy.Host) -Dhttp.proxyPort=$($proxy.Port) -Dhttp.nonProxyHosts=localhost|*.aliyun.com -Dhttps.nonProxyHosts=localhost|*.aliyun.com"
}
$gradleRoot = Join-Path $kitRoot '.cache/watchroom-gradle'
New-Item -ItemType Directory -Path (Join-Path $gradleRoot 'init.d') -Force | Out-Null
foreach ($directory in @('caches','wrapper')) {
    $link = Join-Path $gradleRoot $directory
    $target = Join-Path (Join-Path $env:USERPROFILE '.gradle') $directory
    if (-not (Test-Path -LiteralPath $link) -and (Test-Path -LiteralPath $target)) {
        New-Item -ItemType Junction -Path $link -Target $target | Out-Null
    }
}
Copy-Item -LiteralPath (Join-Path $kitRoot 'config/watchroom-gradle.init.gradle') -Destination (Join-Path $gradleRoot 'init.d/watchroom-mirrors.gradle')
$env:GRADLE_USER_HOME = $gradleRoot
& (Join-Path $PSScriptRoot 'inject-watchroom.ps1') -SourceRoot $source -BuildManifest $manifestPath -VerifyOnly
Invoke-Native $flutter @('pub','get') -WorkingDirectory $source
& (Join-Path $PSScriptRoot 'prepare-watchroom-material.ps1') -SourceRoot $source -BuildManifest $manifestPath
& (Join-Path $PSScriptRoot 'prepare-watchroom-webview.ps1') -SourceRoot $source -BuildManifest $manifestPath
Invoke-Native $flutter @('pub','get','--offline') -WorkingDirectory $source
Invoke-Native $flutter @('analyze','--no-pub','--no-fatal-infos','lib/private/watchroom','lib/pages/mine/view.dart','lib/utils/app_scheme.dart','lib/pages/video/controller.dart','lib/pages/video/view.dart','lib/pages/video/introduction/pgc/view.dart','lib/pages/video/introduction/pgc/controller.dart','lib/models_new/pgc/pgc_info_model/result.dart','lib/plugin/pl_player/controller.dart','lib/pages/video/widgets/header_control.dart','lib/pages/video/widgets/player_focus.dart','lib/pages/history/view.dart','lib/pages/history/widgets/item.dart','test/private_watchroom') -WorkingDirectory $source
Invoke-Native $flutter @('test','--no-pub','test/private_watchroom') -WorkingDirectory $source
Invoke-Native $flutter @('build','apk','--debug','--target-platform','android-arm64','--android-project-arg=kotlin.incremental=false','--no-pub') -WorkingDirectory $source
$apk = Join-Path $source 'build/app/outputs/flutter-apk/app-debug.apk'
if (-not (Test-Path -LiteralPath $apk)) { throw 'Android build did not produce the expected APK' }
$output = Join-Path $kitRoot 'dist/watchroom/PiliPlus-watchroom-arm64-debug.apk'
Copy-Item -LiteralPath $apk -Destination $output
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$manifest | Add-Member -NotePropertyName personalKitIdentity -NotePropertyValue (Get-KitIdentity $manifest.personalKitWorktree) -Force
$manifest | Add-Member -NotePropertyName watchroomBuild -NotePropertyValue @{
    flutterVersion=$machine.frameworkVersion;flutterCommit=$machine.frameworkRevision;
    dartVersion=$machine.dartSdkVersion;applicationId='com.example.piliplus.debug';
    apk=$output;apkSha256=(Get-FileHash -LiteralPath $output).Hash.ToLowerInvariant();
    dependencyLockSha256=(Get-FileHash -LiteralPath (Join-Path $source 'pubspec.lock')).Hash.ToLowerInvariant();
    tests='passed';analysis='no errors or warnings; style infos remain'
} -Force
Assert-FingerprintEqual $manifest.contributionFingerprint (Get-CheckoutFingerprint $manifest.contributionCheckout)
Write-JsonFile $manifest $manifestPath
if ($Install) { Invoke-Native adb @('install','-r',$output) }
Write-Output "Android watchroom APK: $output"
