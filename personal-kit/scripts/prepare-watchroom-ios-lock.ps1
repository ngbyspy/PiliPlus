param([Parameter(Mandatory)][string]$BuildManifest, [switch]$VerifyOnly)
. (Join-Path $PSScriptRoot 'common.ps1')
$manifestPath = Get-CanonicalPath $BuildManifest
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($manifest.platform -ne 'ios') { throw 'Expected an iOS manifest' }
$kitRoot = Get-CanonicalPath (Join-Path $PSScriptRoot '..')
$source = Assert-GeneratedWorktree $manifest.repoPath $manifest.generatedWorktree $manifest.upstreamCommit @($manifest.contributionCheckout,$manifest.personalKitWorktree)
$pin = Join-Path $kitRoot 'integration/ios/pubspec.lock'
$lock = Join-Path $source 'pubspec.lock'
if (-not $VerifyOnly) {
    if (-not (Test-Path -LiteralPath (Join-Path $source 'pubspec_overrides.yaml'))) {
        Copy-Item -LiteralPath $pin -Destination $lock -Force
    }
    return
}
$expected = [IO.File]::ReadAllText($pin).Replace("`r`n","`n")
$actual = [IO.File]::ReadAllText($lock).Replace("`r`n","`n")
# Only these two hosted packages are replaced by independently verified copies.
foreach ($name in @('material_ui','cupertino_ui')) {
    $pattern = "(?ms)^  ${name}:`n.*?(?=^  [a-zA-Z0-9_]+:|^sdks:)"
    $left = [regex]::Match($expected,$pattern)
    $right = [regex]::Match($actual,$pattern)
    $versionPattern = '(?m)^    version: "([^"\r\n]+)"$'
    if (-not $left.Success -or -not $right.Success -or
        [regex]::Match($left.Value,$versionPattern).Value -cne [regex]::Match($right.Value,$versionPattern).Value) { throw "Patched package version changed: $name" }
    $expected = [regex]::Replace($expected,$pattern,'')
    $actual = [regex]::Replace($actual,$pattern,'')
}
if ($expected -cne $actual) { throw 'iOS dependencies differ from the reviewed lockfile; inspect drift before building' }
$manifest | Add-Member -NotePropertyName watchroomIosDependencyPin -NotePropertyValue @{path='integration/ios/pubspec.lock';sha256=(Get-FileHash -LiteralPath $pin).Hash.ToLowerInvariant();resolvedLockSha256=(Get-FileHash -LiteralPath $lock).Hash.ToLowerInvariant()} -Force
Write-JsonFile $manifest $manifestPath
Write-Output 'iOS hosted package versions/hashes and Git revisions match the pinned lockfile'
