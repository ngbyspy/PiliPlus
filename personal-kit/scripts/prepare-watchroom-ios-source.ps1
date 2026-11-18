param([Parameter(Mandatory)][string]$BuildManifest)
. (Join-Path $PSScriptRoot 'common.ps1')
$manifestPath = Get-CanonicalPath $BuildManifest
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($manifest.platform -ne 'ios') { throw 'Expected an iOS manifest' }
$kitRoot = Get-CanonicalPath (Join-Path $PSScriptRoot '..')
$source = Assert-GeneratedWorktree $manifest.repoPath $manifest.generatedWorktree $manifest.upstreamCommit @($manifest.contributionCheckout,$manifest.personalKitWorktree)
$config = Get-Content -LiteralPath (Join-Path $kitRoot 'config/watchroom-toolchain-ios.json') -Raw | ConvertFrom-Json
if ($manifest.upstreamCommit -cne $config.upstreamCommit) { throw 'Unsupported iOS source baseline' }
$fixture = Join-Path $kitRoot ('.cache/watchroom-ios-source-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture -Force | Out-Null
$archive = Join-Path $fixture 'base.tar'
Invoke-Native git @('-C',$source,'archive','--format=tar',"--output=$archive",$manifest.upstreamCommit)
Invoke-Native tar @('-xf',$archive,'-C',$fixture)
Invoke-Native git @('-C',$fixture,'init','--quiet')
$targets = [Collections.Generic.HashSet[string]]::new()
$patchFiles = @()
foreach ($patch in $config.applicationPatches) {
    $root = if ($patch.origin -eq 'kit') { $kitRoot } else { $source }
    $file = Join-Path $root $patch.path
    if ((Get-FileHash -LiteralPath $file).Hash.ToLowerInvariant() -cne $patch.sha256) { throw "iOS patch changed: $($patch.path)" }
    $patchFiles += $file
    foreach ($line in Get-Content -LiteralPath $file) {
        if ($line -match '^\+\+\+ b/(.+)$') {
            $relative = $Matches[1]
            if ($relative.Contains('..') -or $relative.StartsWith('/') -or $relative -notmatch '^(lib/|ios/|pubspec\.yaml$)') { throw 'Unsafe iOS app patch target' }
            [void]$targets.Add($relative)
        }
    }
}
$baseHashes = @{}
foreach ($target in $targets) {
    $path = Join-Path $fixture $target
    $baseHashes[$target] = if (Test-Path -LiteralPath $path) { (Get-FileHash -LiteralPath $path).Hash } else { $null }
}
foreach ($file in $patchFiles) {
    Invoke-Native git @('-C',$fixture,'apply','--check','--whitespace=nowarn',$file)
    Invoke-Native git @('-C',$fixture,'apply','--whitespace=nowarn',$file)
}
$outputs = @()
foreach ($target in $targets) {
    $destination = Join-Path $source $target
    $actual = if (Test-Path -LiteralPath $destination) { (Get-FileHash -LiteralPath $destination).Hash } else { $null }
    $expected = (Get-FileHash -LiteralPath (Join-Path $fixture $target)).Hash
    if ($actual -cne $baseHashes[$target] -and $actual -cne $expected) { throw "Unexpected iOS source content: $target" }
    $outputs += @{path=$target;sha256=$expected.ToLowerInvariant()}
}
# Every file must be original or exactly the independently reproduced output.
foreach ($output in $outputs) {
    $destination = Join-Path $source $output.path
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $fixture $output.path) -Destination $destination -Force
}
$manifest | Add-Member -NotePropertyName watchroomIosSource -NotePropertyValue @{patches=$config.applicationPatches;files=$outputs} -Force
Assert-FingerprintEqual $manifest.contributionFingerprint (Get-CheckoutFingerprint $manifest.contributionCheckout)
Write-JsonFile $manifest $manifestPath
Write-Output "Verified iOS application patches: $($config.applicationPatches.Count) patches, $($outputs.Count) files"
