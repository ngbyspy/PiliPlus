param([Parameter(Mandatory)][string]$BuildManifest)
. (Join-Path $PSScriptRoot 'common.ps1')
$manifestPath = Get-CanonicalPath $BuildManifest
$build = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$kitRoot = Get-CanonicalPath (Join-Path $PSScriptRoot '..')
$fixture = Join-Path (Split-Path -Parent $build.repoPath) ('PiliPlus-private-build-watchroom-test-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
if (Test-Path -LiteralPath $fixture) { throw 'Test fixture path already exists' }
Invoke-Native git @('-C',$build.repoPath,'worktree','add','--detach',$fixture,$build.upstreamCommit)
$testManifest = Join-Path $kitRoot 'dist/watchroom/injection-test-manifest.json'
$data = $build | ConvertTo-Json -Depth 25 | ConvertFrom-Json
$data.generatedWorktree = $fixture
Write-JsonFile $data $testManifest
$source = Assert-GeneratedWorktree $build.repoPath $fixture $build.upstreamCommit @($build.contributionCheckout,$build.personalKitWorktree,$build.generatedWorktree)
$injector = Join-Path $PSScriptRoot 'inject-watchroom.ps1'
$mine = Join-Path $source 'lib/pages/mine/view.dart'
$original = [IO.File]::ReadAllText($mine)
$mutated = $original.Replace('icon: const Icon(Icons.settings_outlined),','icon: const Icon(Icons.settings),')
if ($mutated -ceq $original) { throw 'Anchor drift mutation did not change the expected fixture' }
[IO.File]::WriteAllText($mine,$mutated,[Text.UTF8Encoding]::new($false))
$failed = $false
try { & $injector -SourceRoot $source -BuildManifest $testManifest } catch { $failed = $_.Exception.Message -like '*anchor drift*' }
if (-not $failed -or (Test-Path -LiteralPath (Join-Path $source 'lib/private/watchroom'))) { throw 'Anchor drift did not fail before module writes' }
[IO.File]::WriteAllText($mine,$original,[Text.UTF8Encoding]::new($false))
& $injector -SourceRoot $source -BuildManifest $testManifest
if ($build.platform -eq 'ios') {
    $iosPreparer = Join-Path $PSScriptRoot 'prepare-watchroom-ios-source.ps1'
    & $iosPreparer -BuildManifest $testManifest
    $plist = Join-Path $source 'ios/Runner/Info.plist'
    $expectedPlist = [IO.File]::ReadAllText($plist)
    $changedPlist = $expectedPlist.Replace('PiliPlus 放映厅测试','Unexpected app name')
    if ($changedPlist -ceq $expectedPlist) { throw 'iOS drift fixture did not change the app metadata' }
    [IO.File]::WriteAllText($plist,$changedPlist,[Text.UTF8Encoding]::new($false))
    try {
        $rejected = $false
        try { & $iosPreparer -BuildManifest $testManifest } catch { $rejected = $_.Exception.Message -like '*Unexpected iOS source content*' }
        if (-not $rejected) { throw 'Unexpected iOS metadata was accepted' }
        if ([IO.File]::ReadAllText($plist) -cne $changedPlist) { throw 'Rejected iOS patch attempt modified the unexpected metadata' }
    } finally { [IO.File]::WriteAllText($plist,$expectedPlist,[Text.UTF8Encoding]::new($false)) }
}
function Output-Fingerprint {
    $files = @(Get-GitOutput $source @('ls-files','--modified','--others','--exclude-standard')) -split "`n"
    $hashes = foreach ($relative in $files | Where-Object { $_ } | Sort-Object -Unique) {
        "$relative=$((Get-FileHash -LiteralPath (Join-Path $source $relative)).Hash)"
    }
    return Get-StringSha256 ($hashes -join "`n")
}
$first = Output-Fingerprint
if ($build.platform -eq 'ios') { & $iosPreparer -BuildManifest $testManifest }
& $injector -SourceRoot $source -BuildManifest $testManifest
if ((Output-Fingerprint) -cne $first) { throw 'Reinjection changed generated source bytes' }
$module = Join-Path $source 'lib/private/watchroom/wire.dart'
$backup = Join-Path $kitRoot ('dist/watchroom/omitted-wire-' + [guid]::NewGuid().ToString('N') + '.dart')
if (-not $module.StartsWith($source + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe omitted-module path' }
Move-Item -LiteralPath $module -Destination $backup
try {
    $failed = $false
    try { & $injector -SourceRoot $source -BuildManifest $testManifest -VerifyOnly } catch { $failed = $_.Exception.Message -like '*Missing private module*' }
    if (-not $failed) { throw 'Verification accepted an omitted module' }
} finally { Move-Item -LiteralPath $backup -Destination $module }
& $injector -SourceRoot $source -BuildManifest $testManifest -VerifyOnly
Assert-FingerprintEqual $build.contributionFingerprint (Get-CheckoutFingerprint $build.contributionCheckout)
$result = @{cleanInjection=$true;idempotentReinjection=$true;anchorDriftRejected=$true;missingModuleRejected=$true;contributionCheckoutUnchanged=$true;upstreamCommit=$build.upstreamCommit}
if ($build.platform -eq 'ios') { $result.iosAppPatchDriftRejected = $true; $result.iosAppPatchReinjection = $true }
Write-JsonFile $result (Join-Path $kitRoot 'dist/watchroom/injection-tests.json')
# The disposable fixture contains only this script's verified injection outputs.
$verified = Assert-GeneratedWorktree $build.repoPath $source $build.upstreamCommit @($build.contributionCheckout,$build.personalKitWorktree,$build.generatedWorktree)
if ($verified -ine (Get-CanonicalPath $data.generatedWorktree) -or (Split-Path -Leaf $verified) -notlike 'PiliPlus-private-build-watchroom-test-*') { throw 'Fixture cleanup path mismatch' }
Invoke-Native git @('-C',$build.repoPath,'worktree','remove','--force',$verified)
$result | ConvertTo-Json -Compress
