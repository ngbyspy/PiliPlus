. (Join-Path $PSScriptRoot '../support.ps1')
$source = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$release = Get-Content -LiteralPath (Join-Path $source 'tool/spy/release.json') -Raw | ConvertFrom-Json
$android = Get-SpyPackageProfile $release Android $true
if ($android.mode -cne 'debug' -or $android.applicationId -cne 'com.ngbyspy.piliplus.spy.debug' -or $android.applicationId -in @($release.androidApplicationId,'com.example.piliplus')) { throw 'Android acceptance could replace a formal installation' }
$ios = Get-SpyPackageProfile $release iOS $true
if ($ios.applicationId -cne 'com.spy.piliPlus.dev') { throw 'iOS acceptance identity has incorrect spelling or case' }
if ((Get-SpyPackageProfile $release iOS $false).applicationId -cne 'com.spy.piliPlus') { throw 'Formal IPA identity changed' }
if ((Get-SpyPackageProfile $release Windows $true).mode -cne 'release') { throw 'Windows acceptance must use the upstream-compatible release profile' }
$projectPath = Join-Path $source 'ios/Runner.xcodeproj/project.pbxproj'
$original = [IO.File]::ReadAllText($projectPath)
$prepared = Get-SpyIosAcceptanceProject $original $release
if ([regex]::Matches($prepared,'PRODUCT_BUNDLE_IDENTIFIER = com\.spy\.piliPlus\.dev;').Count -ne 3 -or $prepared.Contains('PRODUCT_BUNDLE_IDENTIFIER = com.spy.piliPlus;')) { throw 'Release/Profile iOS configurations were not isolated for acceptance' }
if ([IO.File]::ReadAllText($projectPath) -cne $original) { throw 'Profile check modified the source project' }
$release.iosDevelopmentBundleId = 'com.spy.piliplus.dev'
$rejected = $false
try { Get-SpyIosAcceptanceProject $original $release | Out-Null } catch { $rejected = $true }
if (-not $rejected) { throw 'Incorrect Bundle ID case was accepted' }
Write-Output 'Acceptance profiles preserve formal apps and isolate all iOS configurations.'
