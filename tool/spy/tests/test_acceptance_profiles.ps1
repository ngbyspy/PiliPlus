. (Join-Path $PSScriptRoot '../support.ps1')
$source = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$release = Get-Content -LiteralPath (Join-Path $source 'tool/spy/release.json') -Raw | ConvertFrom-Json
$android = Get-SpyPackageProfile $release Android $true
if ($android.mode -cne 'release' -or $android.displayName -cne 'PiliPlus SPY dev' -or $android.applicationId -cne 'com.ngbyspy.piliplus.spy.debug' -or $android.applicationId -in @($release.androidApplicationId,'com.example.piliplus')) { throw 'Android acceptance must be independent and default to Release' }
foreach ($mode in @('debug','profile')) {
    $diagnostic = Get-SpyPackageProfile $release Android $true $mode
    if ($diagnostic.mode -cne $mode -or $diagnostic.applicationId -cne $android.applicationId) { throw 'Explicit diagnostic mode must preserve the acceptance app identity' }
    $rejected = $false
    try { Get-SpyPackageProfile $release Android $false $mode | Out-Null } catch { $rejected = $true }
    if (-not $rejected) { throw 'Formal Android builds must reject Debug/Profile mode' }
}
$ios = Get-SpyPackageProfile $release iOS $true
if ($ios.applicationId -cne 'com.spy.piliPlus.dev' -or $ios.displayName -cne 'PiliPlus SPY Dev') { throw 'iOS acceptance identity/name has incorrect spelling or case' }
$formalIos = Get-SpyPackageProfile $release iOS $false
if ($formalIos.applicationId -cne 'com.spy.piliPlus' -or $formalIos.displayName -cne 'PiliPlus') { throw 'Formal IPA identity/name changed' }
if ((Get-SpyPackageProfile $release Windows $true).mode -cne 'release') { throw 'Windows acceptance must use the upstream-compatible release profile' }
$projectPath = Join-Path $source 'ios/Runner.xcodeproj/project.pbxproj'
$original = [IO.File]::ReadAllText($projectPath)
$prepared = Get-SpyIosAcceptanceProject $original $release
if ([regex]::Matches($prepared,'PRODUCT_BUNDLE_IDENTIFIER = com\.spy\.piliPlus\.dev;').Count -ne 3 -or $prepared.Contains('PRODUCT_BUNDLE_IDENTIFIER = com.spy.piliPlus;')) { throw 'Release/Profile iOS configurations were not isolated for acceptance' }
if ([regex]::Matches($prepared,[regex]::Escape('APP_DISPLAY_NAME = "' + $ios.displayName + '";')).Count -ne 2) { throw 'Prepared Release/Profile display names differ from the acceptance package profile' }
if ([IO.File]::ReadAllText($projectPath) -cne $original) { throw 'Profile check modified the source project' }
$release.iosDevelopmentBundleId = 'com.spy.piliplus.dev'
$rejected = $false
try { Get-SpyIosAcceptanceProject $original $release | Out-Null } catch { $rejected = $true }
if (-not $rejected) { throw 'Incorrect Bundle ID case was accepted' }
Write-Output 'Acceptance profiles preserve formal apps and isolate all iOS configurations.'
