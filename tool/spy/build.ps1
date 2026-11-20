param(
    [Parameter(Mandatory)][ValidateSet('Windows','Android','iOS')][string]$Platform,
    [string]$SourceRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),
    [string]$CacheRoot,
    [string]$SdkRoot,
    [string]$OutputRoot,
    [string]$ProxyUrl,
    [switch]$ValidateOnly,
    [switch]$Offline
)
. (Join-Path $PSScriptRoot 'support.ps1')
if ($Platform -eq 'iOS' -and -not $IsMacOS) { throw 'Build iPad IPA on a GitHub macOS runner' }
$context = Get-SpyContext $SourceRoot $CacheRoot
if (-not $ValidateOnly -and $context.branch -ne 'spy/main') { throw 'Release packages must come from spy/main' }
$status = Get-SpyGit $context.source @('status','--porcelain','--untracked-files=all')
if (-not $ValidateOnly -and $status) { throw 'Release checkout has source changes; validate and commit them before packaging' }
if ($Platform -eq 'Android' -and -not $ValidateOnly -and -not $context.release.androidReleaseEnabled) { throw 'Android formal release is deferred: upstream private signing certificate is required for in-place updates. Do not uninstall the official app.' }
$registerLocalRelease = -not $OutputRoot -and -not $ValidateOnly
if (-not $OutputRoot) {
    $OutputRoot = if ($ValidateOnly) { Join-Path $context.source ".spy-build/validation/$Platform" } else { Join-Path (Split-Path -Parent $context.source) ".build/release-staging/$($context.release.tag)/$Platform" }
}
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
$reportPath = Join-Path $OutputRoot ("build-$($Platform.ToLowerInvariant()).json")
$report = @{product='PiliPlus-SPY';platform=$Platform;sourceCommit=$context.commit;sourceDirty=[bool]$status;upstreamCommit=$context.release.upstreamCommit;release=$context.release;startedOn=[DateTimeOffset]::UtcNow.ToString('o');nativeAcceptance='upstream-compatible identity restored; overwrite/data-retention acceptance pending';networkRecovery='deferred by user'}
if ($ProxyUrl) {
    $proxy = [uri]$ProxyUrl
    if ($proxy.Scheme -ne 'http' -or $proxy.UserInfo) { throw 'Use an HTTP proxy without credentials' }
    $env:HTTP_PROXY=$ProxyUrl; $env:HTTPS_PROXY=$ProxyUrl
    $env:GIT_CONFIG_COUNT='1';$env:GIT_CONFIG_KEY_0='http.proxy';$env:GIT_CONFIG_VALUE_0=$ProxyUrl
    $env:JAVA_TOOL_OPTIONS="-Dhttp.proxyHost=$($proxy.Host) -Dhttp.proxyPort=$($proxy.Port) -Dhttps.proxyHost=$($proxy.Host) -Dhttps.proxyPort=$($proxy.Port) -Dhttp.nonProxyHosts=localhost|*.aliyun.com -Dhttps.nonProxyHosts=localhost|*.aliyun.com"
}
$originalLock = [IO.File]::ReadAllBytes((Join-Path $context.source 'pubspec.lock'))
try {
    $sdk = Prepare-SpySdk $context $Platform $SdkRoot
    $report.sdk = $sdk
    if ($Platform -eq 'iOS') { $report.nativeSourcePatches = Prepare-SpyIosSource $context }
    $lock = Join-Path $context.source $(if ($Platform -eq 'iOS') { 'tool/spy/dependencies/ios.lock' } else { 'tool/spy/dependencies/base.lock' })
    Copy-Item -LiteralPath $lock -Destination (Join-Path $context.source 'pubspec.lock') -Force
    Set-SpyDependencyOverrides $context
    $arguments = @('pub','get','--enforce-lockfile');if ($Offline) { $arguments += '--offline' }
    Invoke-SpyNative $sdk.executable $arguments $context.source
    $report.uiDependencies = @(Prepare-SpyDependencies $context $Platform)
    Invoke-SpyNative $sdk.executable @('pub','get','--offline') $context.source
    $pathPackages = @('material_ui','cupertino_ui');if ($Platform -eq 'Android') { $pathPackages += 'flutter_inappwebview_android' }
    Assert-SpyDependencyLock $lock (Join-Path $context.source 'pubspec.lock') $pathPackages
    $report.resolvedLockSha256 = Get-SpyHash (Join-Path $context.source 'pubspec.lock')
    $paths = @('lib/features/watchroom','test/watchroom','test/release_identity_test.dart','lib/utils/runtime_identity.dart','lib/common/constants.dart','lib/main.dart','lib/utils/cache_manager.dart','lib/utils/desktop/window_controller.dart','lib/pages/mine/view.dart','lib/utils/app_scheme.dart','lib/pages/video/controller.dart','lib/pages/video/view.dart','lib/pages/video/introduction/pgc/view.dart','lib/pages/video/introduction/pgc/controller.dart','lib/models_new/pgc/pgc_info_model/result.dart','lib/plugin/pl_player/controller.dart','lib/pages/video/widgets/header_control.dart','lib/pages/video/widgets/player_focus.dart','lib/pages/history/view.dart','lib/pages/history/widgets/item.dart')
    $paths += @('lib/services/audio_session.dart','lib/services/playback_audio_session.dart','lib/services/service_locator.dart','lib/pages/audio/controller.dart','lib/pages/setting/models/play_settings.dart','lib/plugin/pl_player/view/view.dart','test/services')
    Invoke-SpyNative $sdk.executable (@('analyze','--no-pub','--no-fatal-infos') + $paths) $context.source
    Invoke-SpyNative $sdk.executable @('test','--no-pub','test/watchroom','test/services','test/release_identity_test.dart') $context.source
    $report.validation = @{analysis=$true;tests=$true}
    if ($ValidateOnly) { $report.configuration='validation-only'; Write-SpyJson $report $reportPath; return }
    $defines = Join-Path $context.source '.spy-build/release-defines.json'
    Write-SpyJson @{'pili.name'=$context.release.displayVersion;'pili.code'=$context.release.androidVersionCode;'pili.hash'=$context.commit;'pili.time'=[DateTimeOffset]::Now.ToUnixTimeSeconds()} $defines
    $common = @('--release','--no-pub',"--build-name=$($context.release.version)","--dart-define-from-file=$defines")
    switch ($Platform) {
        'Windows' {
            $tools = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'config/windows-tools.json') -Raw | ConvertFrom-Json
            $nugetRoot = Join-Path $context.cache 'windows-build-tools'
            $nuget = Join-Path $nugetRoot 'nuget.exe'
            if ((Get-SpyHash $nuget) -cne $tools.nugetSha256 -or (Get-AuthenticodeSignature -LiteralPath $nuget).Status -ne 'Valid') { throw 'Prepare the verified Microsoft NuGet build tool' }
            $env:PATH=$nugetRoot+[IO.Path]::PathSeparator+$env:PATH
            $env:NO_PROXY=(@($env:NO_PROXY,'.nuget.org','nuget.azure.cn','.azure.cn')|Where-Object {$_}) -join ','
            Invoke-SpyNative $sdk.executable (@('build','windows') + $common + @('--build-number',"$($context.release.androidVersionCode)")) $context.source
            $bundle = Join-Path $context.source 'build/windows/x64/runner/Release'
            if (-not (Test-Path -LiteralPath (Join-Path $bundle $context.release.windowsExecutable))) { throw 'Windows executable is missing' }
            $nativeIdentity = (Get-Item -LiteralPath (Join-Path $bundle $context.release.windowsExecutable)).VersionInfo
            if ($nativeIdentity.CompanyName -cne 'com.example' -or $nativeIdentity.ProductName -cne 'piliplus' -or $nativeIdentity.OriginalFilename -cne 'piliplus.exe') { throw 'Windows metadata would open a different upstream data directory' }
            if ($nativeIdentity.ProductVersion -cne "$($context.release.version)+$($context.release.androidVersionCode)") { throw 'Windows native build version differs from the upstream baseline' }
            $report.windowsProfile = @{company=$nativeIdentity.CompanyName;product=$nativeIdentity.ProductName;supportDirectory='%APPDATA%/com.example/piliplus';developmentSubdirectory='spy-dev'}
            $artifact = Join-Path $OutputRoot "PiliPlus-SPY-$($context.release.displayVersion)-windows-x64-portable.zip"
            if (Test-Path -LiteralPath $artifact) { throw 'Preserve the existing package; use a new release revision' }
            $files = @(Get-ChildItem -LiteralPath $bundle | Where-Object { $_.Extension -ne '.exe' -or $_.Name -ceq $context.release.windowsExecutable } | ForEach-Object FullName)
            Compress-Archive -LiteralPath $files -DestinationPath $artifact
        }
        'Android' {
            $report.nativeLibraries = @(Prepare-SpyAndroidNativeLibraries $context)
            $report.flutterArtifacts = @(Prepare-SpyAndroidFlutterArtifacts $context $sdk)
            $secrets = Join-Path (Split-Path -Parent $context.source) '.secrets'
            $identity = Get-Content -LiteralPath (Join-Path $secrets 'android-signing.json') -Raw | ConvertFrom-Json
            $key = Join-Path $secrets $identity.storeFile
            if ((Get-SpyHash $key) -cne $identity.keystoreSha256) { throw 'Android signing key changed' }
            $certificate = [Security.Cryptography.X509Certificates.X509Certificate2]::new($key,$identity.password,[Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet)
            try {
                if ($certificate.GetCertHashString([Security.Cryptography.HashAlgorithmName]::SHA256).ToLowerInvariant() -cne $context.release.androidCertificateSha256) { throw 'Signing certificate differs from official PiliPlus: in-place Android updates are impossible with this key' }
            } finally { $certificate.Dispose() }
            $properties = Join-Path $secrets 'android-key.properties'
            [IO.File]::WriteAllText($properties,"storeFile=$($key.Replace('\','/'))`nstorePassword=$($identity.password)`nkeyAlias=$($identity.keyAlias)`nkeyPassword=$($identity.password)`n",[Text.UTF8Encoding]::new($false))
            $env:PILIPLUS_SPY_KEY_PROPERTIES=$properties
            $env:GRADLE_USER_HOME=Join-Path $context.cache 'gradle'
            New-Item -ItemType Directory -Path (Join-Path $env:GRADLE_USER_HOME 'init.d') -Force | Out-Null
            Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'config/gradle.init.gradle') -Destination (Join-Path $env:GRADLE_USER_HOME 'init.d/spy-mirrors.gradle') -Force
            Invoke-SpyNative $sdk.executable (@('build','apk','--target-platform','android-arm64','--android-project-arg=kotlin.incremental=false','--android-project-arg=disable-abi-filtering=true') + $common + @('--build-number',"$($context.release.androidVersionCode)")) $context.source
            $builtApk = Join-Path $context.source 'build/app/outputs/flutter-apk/app-release.apk'
            $archive = [IO.Compression.ZipFile]::OpenRead($builtApk)
            try {
                $abis = @($archive.Entries | Where-Object FullName -Like 'lib/*/*.so' | ForEach-Object { ($_.FullName -split '/')[1] } | Sort-Object -Unique)
                if ($abis.Count -ne 1 -or $abis[0] -cne 'arm64-v8a') { throw 'Release APK advertises unsupported native architectures' }
                $report.architectures = $abis
            } finally { $archive.Dispose() }
            $artifact = Join-Path $OutputRoot "PiliPlus-SPY-$($context.release.displayVersion)-android-arm64.apk"
            if (Test-Path -LiteralPath $artifact) { throw 'Preserve the existing package; use a new release revision' }
            Copy-Item -LiteralPath $builtApk -Destination $artifact
            $report.signingKeystoreSha256=$identity.keystoreSha256
        }
        'iOS' {
            Invoke-SpyNative $sdk.executable (@('build','ios','--no-codesign') + $common + @('--build-number',"$($context.release.iosBuildNumber)")) $context.source
            $directory = Join-Path $OutputRoot 'ipad'
            Invoke-SpyNative python3 @((Join-Path $PSScriptRoot 'package-ios.py'),'--app',(Join-Path $context.source 'build/ios/iphoneos/Runner.app'),'--output',$directory,'--build-id',$context.release.displayVersion,'--expected-bundle-id',$context.release.iosBundleId)
            $native = Get-Content -LiteralPath (Join-Path $directory 'ipa-verification.json') -Raw | ConvertFrom-Json
            if ($native.bundleIdentifier -cne $context.release.iosBundleId -or $native.version -cne $context.release.version -or $native.buildNumber -cne $context.release.iosBuildNumber) { throw 'IPA identity/build version differs from the configured iOS release' }
            $artifact=$native.ipa;$report.ipaVerification=$native
        }
    }
    $report.artifact=@{path=$artifact;sha256=(Get-SpyHash $artifact);bytes=(Get-Item -LiteralPath $artifact).Length}
    $report.completedOn=[DateTimeOffset]::UtcNow.ToString('o')
    Write-SpyJson $report $reportPath
    if ($registerLocalRelease) { & (Join-Path $PSScriptRoot 'register-release.ps1') -ReportPath $reportPath }
    Write-Output "SPY package ready: $artifact"
} catch { $report.failure=$_.Exception.Message; Write-SpyJson $report $reportPath; throw }
finally {
    [IO.File]::WriteAllBytes((Join-Path $context.source 'pubspec.lock'),$originalLock)
    $env:PILIPLUS_SPY_KEY_PROPERTIES=$null
    $env:PILIPLUS_SPY_FLUTTER_MAVEN=$null
}
