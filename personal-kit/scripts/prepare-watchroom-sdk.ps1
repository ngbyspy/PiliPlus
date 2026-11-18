param(
    [Parameter(Mandatory)][string]$BuildManifest,
    [ValidateSet('Android','Windows','iOS')][string]$Platform = 'Android',
    [string]$SdkRoot
)
. (Join-Path $PSScriptRoot 'common.ps1')
$manifestPath = Get-CanonicalPath $BuildManifest
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$kitRoot = Get-CanonicalPath (Join-Path $PSScriptRoot '..')
$configName = switch ($Platform) {
    'Windows' { 'watchroom-toolchain-windows.json' }
    'iOS' { 'watchroom-toolchain-ios.json' }
    default { 'watchroom-toolchain.json' }
}
$config = Get-Content -LiteralPath (Join-Path $kitRoot "config/$configName") -Raw | ConvertFrom-Json
$source = Assert-GeneratedWorktree $manifest.repoPath $manifest.generatedWorktree $manifest.upstreamCommit @($manifest.contributionCheckout,$manifest.personalKitWorktree)
$pubspec = [IO.File]::ReadAllText((Join-Path $source 'pubspec.yaml'))
$pin = [regex]::Match($pubspec,'(?m)^\s+flutter: (\d+\.\d+\.\d+)\s*$').Groups[1].Value
if ($pin -ne $config.flutterVersion) { throw "Upstream Flutter pin changed to $pin; update the watchroom toolchain configuration." }
$driver = Join-Path $source 'lib/scripts/patch.ps1'
$driverHash = if ($Platform -eq 'iOS') {
    Get-StringSha256 ([IO.File]::ReadAllText($driver).Replace("`r`n","`n"))
} else { (Get-FileHash -LiteralPath $driver).Hash.ToLowerInvariant() }
if ($driverHash -ne $config.upstreamPatchDriverSha256) { throw 'Upstream patch order changed; inspect the current driver before preparing the SDK.' }
$cache = Join-Path $kitRoot '.cache/flutter'
New-Item -ItemType Directory -Path $cache -Force | Out-Null
$sdkContainer = Join-Path $cache $(if ($Platform -eq 'Windows') { "flutter-$pin-windows" } elseif ($Platform -eq 'iOS') { "flutter-$pin-ios" } else { "flutter-$pin" })
$sdk = Join-Path $sdkContainer 'flutter'
if ($SdkRoot) {
    if ($Platform -ne 'iOS') { throw 'An explicit SDK root is supported only by the isolated iOS build' }
    $sdk = Get-CanonicalPath $SdkRoot
}
if (-not $SdkRoot -and $Platform -in @('Windows','iOS') -and -not (Test-Path -LiteralPath $sdk)) {
    $base = Join-Path $cache "flutter-$pin/flutter"
    if ((Get-GitOutput $base @('rev-parse','HEAD')) -ne $config.frameworkCommit) { throw 'Base SDK identity mismatch' }
    New-Item -ItemType Directory -Path $sdkContainer -Force | Out-Null
    Invoke-Native git @('-c','core.longpaths=true','-C',$base,'worktree','add','--detach',$sdk,$config.frameworkCommit)
    New-Item -ItemType Junction -Path (Join-Path $sdk 'bin/cache') -Target (Join-Path $base 'bin/cache') | Out-Null
}
$flutterExecutable = if ($IsWindows) { 'bin/flutter.bat' } else { 'bin/flutter' }
if (-not (Test-Path -LiteralPath (Join-Path $sdk $flutterExecutable))) {
    if ($SdkRoot -or $Platform -eq 'iOS') { throw 'Prepare the pinned Flutter SDK before building iOS' }
    if (Test-Path -LiteralPath $sdkContainer) { throw 'Partial SDK extraction exists; inspect it before retrying.' }
    $archive = Join-Path $cache "flutter_windows_$pin-stable.zip"
    if (-not (Test-Path -LiteralPath $archive)) {
        Invoke-Native curl.exe @('--fail','--location','--retry','3','--output',$archive,$config.archiveUrl)
    }
    if ((Get-Item -LiteralPath $archive).Length -ne $config.archiveSize -or (Get-FileHash -LiteralPath $archive).Hash.ToLowerInvariant() -ne $config.archiveSha256) { throw 'SDK archive identity mismatch' }
    New-Item -ItemType Directory -Path $sdkContainer | Out-Null
    Invoke-Native tar @('-xf',$archive,'-C',$sdkContainer)
}
$sdk = Get-CanonicalPath $sdk
if ((Get-CanonicalPath (Get-GitOutput $sdk @('rev-parse','--show-toplevel'))) -ine $sdk -or
    (Get-GitOutput $sdk @('rev-parse','HEAD')) -ne $config.frameworkCommit) { throw 'Private SDK repository identity mismatch' }
$targets = [Collections.Generic.HashSet[string]]::new()
foreach ($patch in $config.patches) {
    $file = Join-Path $source $patch.path
    if ((Get-FileHash -LiteralPath $file).Hash.ToLowerInvariant() -ne $patch.sha256) { throw "Upstream SDK patch changed: $($patch.path)" }
    foreach ($line in Get-Content -LiteralPath $file) {
        if ($line -match '^diff --git a/(.+) b/(.+)$') {
            if ($Matches[1] -ne $Matches[2] -or -not $Matches[1].StartsWith('packages/flutter/') -or $Matches[1].Contains('..')) { throw 'Unexpected SDK patch target' }
            [void]$targets.Add($Matches[1])
        }
    }
}
# Independently reproduce the patch chain on original Git blobs. This detects
# partial application and git apply's silent skipping from a parent repository.
$fixture = Join-Path $kitRoot ('.cache/watchroom-sdk-verify-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
$tar = Join-Path $fixture 'original.tar'
$arguments = @('-C',$sdk,'archive','--format=tar',"--output=$tar",$config.frameworkCommit) + @($targets)
Invoke-Native git $arguments
Invoke-Native tar @('-xf',$tar,'-C',$fixture)
Invoke-Native git @('-C',$fixture,'init','--quiet')
$baseHashes = @{}
foreach ($target in $targets) { $baseHashes[$target] = (Get-FileHash -LiteralPath (Join-Path $fixture $target)).Hash }
foreach ($patch in $config.patches) {
    $file = Join-Path $source $patch.path
    Invoke-Native git @('-C',$fixture,'apply','--check','--whitespace=nowarn',$file)
    Invoke-Native git @('-C',$fixture,'apply','--whitespace=nowarn',$file)
}
$allBase = $true; $allPatched = $true; $outputs = @()
foreach ($target in $targets) {
    $actual = (Get-FileHash -LiteralPath (Join-Path $sdk $target)).Hash
    $expected = (Get-FileHash -LiteralPath (Join-Path $fixture $target)).Hash
    if ($actual -ne $baseHashes[$target]) { $allBase = $false }
    if ($actual -ne $expected) { $allPatched = $false }
    $outputs += @{path=$target;sha256=$expected.ToLowerInvariant()}
}
if (-not $allBase -and -not $allPatched) { throw 'The private SDK contains partial or unexpected modifications; preserve it for diagnosis.' }
if (-not $allPatched) {
    foreach ($patch in $config.patches) {
        $file = Join-Path $source $patch.path
        Invoke-Native git @('-C',$sdk,'apply','--check','--whitespace=nowarn',$file)
        Invoke-Native git @('-C',$sdk,'apply','--whitespace=nowarn',$file)
    }
}
foreach ($output in $outputs) {
    if ((Get-FileHash -LiteralPath (Join-Path $sdk $output.path)).Hash.ToLowerInvariant() -ne $output.sha256) { throw "Patched SDK file mismatch: $($output.path)" }
}
$manifest | Add-Member -NotePropertyName watchroomFlutter -NotePropertyValue @{root=$sdk;version=$pin;commit=$config.frameworkCommit;archiveSha256=$config.archiveSha256;patchedFiles=$outputs} -Force
Write-JsonFile $manifest $manifestPath
Write-Output "Verified current upstream $Platform SDK patch chain: $($config.patches.Count) patches, $($targets.Count) files."
