. (Join-Path $PSScriptRoot '../support.ps1')
if ((Get-SpyDisplayVersion '2.2.1' 'parallel' 0 @()) -cne '2.2.1') { throw 'Parallel version changed upstream number' }
if ((Get-SpyDisplayVersion '2.2.1' 'vertical' 5 @('upstream-bug')) -cne '2.2.1.5') { throw 'Vertical version suffix is incorrect' }
$source = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$release = Get-Content -LiteralPath (Join-Path $source 'tool/spy/release.json') -Raw | ConvertFrom-Json
Assert-SpyReleasePolicy $source $release
$release.androidVersionCode *= 100
$rejected = $false
try { Assert-SpyReleasePolicy $source $release } catch { $rejected = $true }
if (-not $rejected) { throw 'An inflated Android versionCode could block later upstream updates' }
$release = Get-Content -LiteralPath (Join-Path $source 'tool/spy/release.json') -Raw | ConvertFrom-Json
$release.iosDevelopmentBundleId = $release.iosBundleId.ToLowerInvariant()
$rejected = $false
try { Assert-SpyReleasePolicy $source $release } catch { $rejected = $true }
if (-not $rejected) { throw 'Development and release need distinct effective defaults' }
Write-Output 'Parallel/vertical display rules and upstream native build-number guards passed.'
