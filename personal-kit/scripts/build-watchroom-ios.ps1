param(
    [Parameter(Mandatory)][string]$BuildManifest,
    [string]$SdkRoot,
    [switch]$ValidateOnly,
    [switch]$Offline
)
. (Join-Path $PSScriptRoot 'common.ps1')
. (Join-Path $PSScriptRoot 'watchroom-source.ps1')
if (-not $ValidateOnly -and -not $IsMacOS) { throw 'Build the IPA on a macOS runner; Windows supports -ValidateOnly' }
$manifestPath = Get-CanonicalPath $BuildManifest
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($manifest.platform -ne 'ios') { throw 'Expected an iOS watchroom manifest' }
$kitRoot = Get-CanonicalPath (Join-Path $PSScriptRoot '..')
$source = Assert-GeneratedWorktree $manifest.repoPath $manifest.generatedWorktree $manifest.upstreamCommit @($manifest.contributionCheckout,$manifest.personalKitWorktree)
& (Join-Path $PSScriptRoot 'prepare-watchroom-sdk.ps1') -BuildManifest $manifestPath -Platform iOS -SdkRoot $SdkRoot
& (Join-Path $PSScriptRoot 'prepare-watchroom-ios-source.ps1') -BuildManifest $manifestPath
& (Join-Path $PSScriptRoot 'inject-watchroom.ps1') -SourceRoot $source -BuildManifest $manifestPath
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$flutter = Join-Path $manifest.watchroomFlutter.root $(if ($IsWindows) { 'bin/flutter.bat' } else { 'bin/flutter' })
& (Join-Path $PSScriptRoot 'prepare-watchroom-ios-lock.ps1') -BuildManifest $manifestPath
$pubArguments = @('pub','get')
if ($Offline) { $pubArguments += '--offline' }
if (-not (Test-Path -LiteralPath (Join-Path $source 'pubspec_overrides.yaml'))) { $pubArguments += '--enforce-lockfile' }
Invoke-Native $flutter $pubArguments -WorkingDirectory $source
& (Join-Path $PSScriptRoot 'prepare-watchroom-material.ps1') -SourceRoot $source -BuildManifest $manifestPath -Platform iOS
Invoke-Native $flutter @('pub','get','--offline') -WorkingDirectory $source
& (Join-Path $PSScriptRoot 'prepare-watchroom-ios-lock.ps1') -BuildManifest $manifestPath -VerifyOnly
& (Join-Path $PSScriptRoot 'inject-watchroom.ps1') -SourceRoot $source -BuildManifest $manifestPath -VerifyOnly
Invoke-Native $flutter @('analyze','--no-pub','--no-fatal-infos','lib/private/watchroom','lib/pages/mine/view.dart','lib/utils/app_scheme.dart','lib/pages/video/controller.dart','lib/pages/video/view.dart','lib/pages/video/introduction/pgc/view.dart','lib/pages/video/introduction/pgc/controller.dart','lib/models_new/pgc/pgc_info_model/result.dart','lib/plugin/pl_player/controller.dart','lib/pages/video/widgets/header_control.dart','lib/pages/video/widgets/player_focus.dart','lib/pages/history/view.dart','lib/pages/history/widgets/item.dart','lib/pages/common/slide/common_slide_page.dart','lib/common/widgets/scaffold/mini_scaffold.dart','test/private_watchroom') -WorkingDirectory $source
Invoke-Native $flutter @('test','--no-pub','test/private_watchroom') -WorkingDirectory $source
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$manifest.validation = @{focusedAnalyze=$true;tests=$true;sourceSha256=(Get-WatchroomSourceHash $manifest);nativeIpadAcceptance='pending self-signing and user testing';networkRecovery='deferred by user'}
$manifest | Add-Member -NotePropertyName personalKitIdentity -NotePropertyValue (Get-KitIdentity $manifest.personalKitWorktree) -Force
Assert-FingerprintEqual $manifest.contributionFingerprint (Get-CheckoutFingerprint $manifest.contributionCheckout)
Write-JsonFile $manifest $manifestPath
if ($ValidateOnly) { Write-Output 'iOS shared code, patches and widget checks passed; no native IPA was built'; return }
$version = [regex]::Match([IO.File]::ReadAllText((Join-Path $source 'pubspec.yaml')),'(?m)^version:\s*([^+\s]+)').Groups[1].Value
if ($version -notmatch '^\d+\.\d+\.\d+$') { throw 'Invalid application version' }
$buildNumber = Get-GitOutput $source @('rev-list','--count','HEAD')
$defines = Join-Path $kitRoot ".cache/$($manifest.buildId)-release.json"
Write-JsonFile @{'pili.name'="$version-watchroom";'pili.code'=[int]$buildNumber;'pili.hash'=$manifest.upstreamCommit;'pili.time'=[DateTimeOffset]::Now.ToUnixTimeSeconds()} $defines
Invoke-Native $flutter @('build','ios','--release','--no-codesign','--no-pub',"--build-name=$version","--build-number=$buildNumber","--dart-define-from-file=$defines") -WorkingDirectory $source
$output = Join-Path $kitRoot "dist/watchroom/ios/$($manifest.buildId)"
Invoke-Native python3 @((Join-Path $PSScriptRoot 'package-watchroom-ios.py'),'--app',(Join-Path $source 'build/ios/iphoneos/Runner.app'),'--output',$output,'--build-id',$manifest.buildId)
$report = Get-Content -LiteralPath (Join-Path $output 'ipa-verification.json') -Raw | ConvertFrom-Json
$manifest | Add-Member -NotePropertyName watchroomIosBuild -NotePropertyValue $report -Force
Assert-FingerprintEqual $manifest.contributionFingerprint (Get-CheckoutFingerprint $manifest.contributionCheckout)
Write-JsonFile $manifest $manifestPath
Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $output 'build-manifest.json')
Write-Output "Self-signable iPad/iPhone IPA: $($report.ipa)"
