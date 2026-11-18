function Get-WatchroomSourceHash {
    param([Parameter(Mandatory)]$Manifest)
    $source = Get-CanonicalPath $Manifest.generatedWorktree
    $paths = @($Manifest.watchroomIntegrationRules.target | Sort-Object -Unique)
    $paths += @('pubspec.yaml','pubspec.lock','pubspec_overrides.yaml')
    if ($Manifest.PSObject.Properties.Name -contains 'watchroomIosSource') {
        $paths += @($Manifest.watchroomIosSource.files.path)
        $paths += @('macos/Flutter/Flutter-Debug.xcconfig','macos/Flutter/Flutter-Release.xcconfig')
    }
    foreach ($folder in @('lib/private/watchroom','test/private_watchroom')) {
        $paths += @(Get-ChildItem -LiteralPath (Join-Path $source $folder) -File -Recurse | ForEach-Object {
            $_.FullName.Substring($source.Length + 1).Replace('\','/')
        })
    }
    $hashes = foreach ($relative in $paths | Sort-Object -Unique) {
        $file = Join-Path $source $relative
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing build input: $relative" }
        "$relative=$((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant())"
    }
    Get-StringSha256 ($hashes -join "`n")
}
