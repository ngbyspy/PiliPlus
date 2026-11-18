param(
    [Parameter(Mandatory)][string]$SourceRoot,
    [Parameter(Mandatory)][string]$BuildManifest,
    [ValidateSet('Android','Windows','iOS')][string]$Platform = 'Android'
)
. (Join-Path $PSScriptRoot 'common.ps1')
$manifestPath = Get-CanonicalPath $BuildManifest
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$source = Assert-GeneratedWorktree -RepoPath $manifest.repoPath -SourceRoot $SourceRoot -ExpectedCommit $manifest.upstreamCommit `
    -ProtectedRoots @($manifest.contributionCheckout,$manifest.personalKitWorktree)
if ($source -ine (Get-CanonicalPath $manifest.generatedWorktree)) { throw 'Unexpected generated source root' }
$config = Get-Content -LiteralPath (Join-Path $source '.dart_tool/package_config.json') -Raw | ConvertFrom-Json
$package = @($config.packages | Where-Object name -eq 'material_ui')
if ($package.Count -ne 1) { throw 'Expected exactly one resolved material_ui package' }
$original = ([uri]$package[0].rootUri).LocalPath
$kitRoot = Get-CanonicalPath (Join-Path $PSScriptRoot '..')
$destination = Join-Path $kitRoot ('.cache/watchroom-material-' + $manifest.upstreamCommit.Substring(0,12))
if ($Platform -eq 'Windows') { $destination += '-windows' }
if ($Platform -eq 'iOS') { $destination += '-ios' }
$stamp = Join-Path $destination 'watchroom-patches.json'
$prepared = $null
if (Test-Path -LiteralPath $stamp) { $prepared = Get-Content -LiteralPath $stamp -Raw | ConvertFrom-Json }
if (-not $prepared -or -not ($prepared.PSObject.Properties.Name -contains 'schemaVersion') -or $prepared.schemaVersion -ne 2) {
    if (-not (Test-Path -LiteralPath $destination)) { Copy-Item -LiteralPath $original -Destination $destination -Recurse }
    # git apply from a subfolder of personal/main can silently skip every patch.
    # A private dependency checkout needs its own repository root.
    if (-not (Test-Path -LiteralPath (Join-Path $destination '.git'))) {
        Invoke-Native git @('-C',$destination,'init','--quiet')
    }
    if ((Get-CanonicalPath (Get-GitOutput $destination @('rev-parse','--show-toplevel'))) -ine (Get-CanonicalPath $destination)) { throw 'Unexpected material Git root' }
    $records = @()
    $patchNames = @('modal_barrier_material','navigation_drawer','popup_menu','fab','text_field','scaffold','refresh_indicator','tabs')
    if ($Platform -eq 'Android') { $patchNames += 'bottom_sheet_android' }
    if ($Platform -eq 'iOS') { $patchNames += 'bottom_sheet_ios_flutter_material' }
    foreach ($name in $patchNames) {
        $patch = Join-Path $source "lib/scripts/material/$name.patch"
        & git -C $destination apply --check --whitespace=nowarn $patch
        if ($LASTEXITCODE -ne 0) { throw "Current upstream material patch failed: $name" }
        & git -C $destination apply --whitespace=nowarn $patch
        if ($LASTEXITCODE -ne 0) { throw "Material patch failed: $name" }
        $records += @{path="lib/scripts/material/$name.patch";sha256=(Get-FileHash -LiteralPath $patch).Hash.ToLowerInvariant()}
    }
    $files = @()
    foreach ($record in $records) {
        $patch = Join-Path $source $record.path
        foreach ($line in Get-Content -LiteralPath $patch) {
            if ($line -match '^\+\+\+ b/(.+)$') {
                $relative = $Matches[1]
                if (-not $relative.StartsWith('lib/') -or $relative.Contains('..')) { throw 'Unsafe material patch target' }
                $files += @{path=$relative;sha256=(Get-FileHash -LiteralPath (Join-Path $destination $relative)).Hash.ToLowerInvariant()}
            }
        }
    }
    Write-JsonFile @{schemaVersion=2;patches=$records;files=$files} $stamp
}
$prepared = Get-Content -LiteralPath $stamp -Raw | ConvertFrom-Json
foreach ($file in $prepared.files) {
    if ((Get-FileHash -LiteralPath (Join-Path $destination $file.path)).Hash.ToLowerInvariant() -ne $file.sha256) { throw "Material patch output changed: $($file.path)" }
}
foreach ($patch in $prepared.patches) {
    if ((Get-FileHash -LiteralPath (Join-Path $source $patch.path)).Hash.ToLowerInvariant() -cne $patch.sha256) { throw "Material patch identity changed: $($patch.path)" }
}
$pubspec = [IO.File]::ReadAllText((Join-Path $source 'pubspec.yaml')).Replace("`r`n","`n")
$match = [regex]::Match($pubspec,'(?ms)^dependency_overrides:\n.*?(?=^[^\s#]|\z)')
if (-not $match.Success) { throw 'Cannot identify original dependency overrides' }
$text = $match.Value.TrimEnd() + "`n  material_ui:`n    path: " + ($destination.Replace('\','/')) + "`n"
if ($Platform -eq 'iOS') {
    $cupertino = @($config.packages | Where-Object name -eq 'cupertino_ui')
    if ($cupertino.Count -ne 1) { throw 'Expected exactly one cupertino_ui package' }
    $cupertinoRoot = Join-Path $kitRoot ('.cache/watchroom-cupertino-' + $manifest.upstreamCommit.Substring(0,12) + '-ios')
    $cupertinoStamp = Join-Path $cupertinoRoot 'watchroom-patches.json'
    $patchPath = 'lib/scripts/cupertino/bottom_sheet_ios_flutter.patch'
    $patch = Join-Path $source $patchPath
    $patchHash = (Get-FileHash -LiteralPath $patch).Hash.ToLowerInvariant()
    if (-not (Test-Path -LiteralPath $cupertinoStamp)) {
        if (Test-Path -LiteralPath $cupertinoRoot) { throw 'Partial Cupertino patch copy exists; inspect it before retrying' }
        Copy-Item -LiteralPath ([uri]$cupertino[0].rootUri).LocalPath -Destination $cupertinoRoot -Recurse
        Invoke-Native git @('-C',$cupertinoRoot,'init','--quiet')
        Invoke-Native git @('-C',$cupertinoRoot,'apply','--check','--whitespace=nowarn',$patch)
        Invoke-Native git @('-C',$cupertinoRoot,'apply','--whitespace=nowarn',$patch)
        $outputs = @(foreach ($line in Get-Content -LiteralPath $patch) {
            if ($line -match '^\+\+\+ b/(.+)$') {
                $relative = $Matches[1]
                if (-not $relative.StartsWith('lib/') -or $relative.Contains('..')) { throw 'Unsafe Cupertino patch target' }
                @{path=$relative;sha256=(Get-FileHash -LiteralPath (Join-Path $cupertinoRoot $relative)).Hash.ToLowerInvariant()}
            }
        })
        Write-JsonFile @{patchSha256=$patchHash;files=$outputs} $cupertinoStamp
    }
    $cupertinoPrepared = Get-Content -LiteralPath $cupertinoStamp -Raw | ConvertFrom-Json
    if ($cupertinoPrepared.patchSha256 -cne $patchHash) { throw 'Cupertino patch identity changed' }
    foreach ($file in $cupertinoPrepared.files) {
        if ((Get-FileHash -LiteralPath (Join-Path $cupertinoRoot $file.path)).Hash.ToLowerInvariant() -cne $file.sha256) { throw "Cupertino output changed: $($file.path)" }
    }
    $text += "  cupertino_ui:`n    path: " + $cupertinoRoot.Replace('\','/') + "`n"
    $manifest | Add-Member -NotePropertyName watchroomCupertino -NotePropertyValue @{root=$cupertinoRoot;verification=$cupertinoPrepared} -Force
}
[IO.File]::WriteAllText((Join-Path $source 'pubspec_overrides.yaml'),$text,[Text.UTF8Encoding]::new($false))
$manifest | Add-Member -NotePropertyName watchroomMaterial -NotePropertyValue @{root=$destination;verification=$prepared} -Force
Write-JsonFile $manifest $manifestPath
Write-Output 'Current upstream material patches prepared in a private package copy.'
