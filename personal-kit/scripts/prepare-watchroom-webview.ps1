param([Parameter(Mandatory)][string]$SourceRoot,[Parameter(Mandatory)][string]$BuildManifest)
. (Join-Path $PSScriptRoot 'common.ps1')
$manifestPath = Get-CanonicalPath $BuildManifest
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$source = Assert-GeneratedWorktree $manifest.repoPath $SourceRoot $manifest.upstreamCommit @($manifest.contributionCheckout,$manifest.personalKitWorktree)
$kitRoot = Get-CanonicalPath (Join-Path $PSScriptRoot '..')
$expected = '0bfa46dfff87f0d9e9d5e13cbd5c4a7c7310f8c9'
$destination = Join-Path $kitRoot '.cache/wv'
$stampPath = Join-Path $kitRoot '.cache/watchroom-webview.json'
if (-not (Test-Path -LiteralPath $stampPath)) {
    if (Test-Path -LiteralPath $destination) { throw 'Unexpected pre-existing short WebView dependency directory' }
    $packages = Get-Content -LiteralPath (Join-Path $source '.dart_tool/package_config.json') -Raw | ConvertFrom-Json
    $package = @($packages.packages | Where-Object name -eq 'flutter_inappwebview_android')
    if ($package.Count -ne 1) { throw 'Expected one Android WebView package' }
    $original = ([uri]$package[0].rootUri).LocalPath
    $repo = Get-CanonicalPath (Get-GitOutput $original @('rev-parse','--show-toplevel'))
    if ((Get-GitOutput $repo @('rev-parse','HEAD')) -ne $expected) { throw 'Android WebView Git commit changed; inspect before applying the Windows path workaround.' }
    $archive = Join-Path $kitRoot '.cache/watchroom-webview.tar'
    Invoke-Native git @('-C',$repo,'archive','--format=tar',"--output=$archive",$expected,'flutter_inappwebview_android')
    New-Item -ItemType Directory -Path $destination | Out-Null
    Invoke-Native tar @('-xf',$archive,'-C',$destination,'--strip-components=1')
    $tracked = @(Get-GitOutput $repo @('ls-tree','-r','--name-only',$expected,'--','flutter_inappwebview_android')) -split "`n" | Where-Object { $_ }
    $files = @(Get-ChildItem -LiteralPath $destination -Recurse -File -Force)
    if ($files.Count -ne $tracked.Count) { throw 'Short WebView extraction is incomplete' }
    $hashes = @()
    foreach ($file in $files) {
        $relative = $file.FullName.Substring($destination.Length).TrimStart([char]'\',[char]'/').Replace('\','/')
        $hashes += @{path=$relative;sha256=(Get-FileHash -LiteralPath $file.FullName).Hash.ToLowerInvariant()}
    }
    Write-JsonFile @{commit=$expected;root=$destination;archiveSha256=(Get-FileHash -LiteralPath $archive).Hash.ToLowerInvariant();files=$hashes} $stampPath
}
$stamp = Get-Content -LiteralPath $stampPath -Raw | ConvertFrom-Json
if ($stamp.commit -ne $expected -or (Get-CanonicalPath $stamp.root) -ine (Get-CanonicalPath $destination)) { throw 'Short WebView dependency identity mismatch' }
foreach ($file in $stamp.files) {
    if ((Get-FileHash -LiteralPath (Join-Path $destination $file.path)).Hash.ToLowerInvariant() -ne $file.sha256) { throw "Short WebView file changed: $($file.path)" }
}
$overrides = Join-Path $source 'pubspec_overrides.yaml'
$text = [IO.File]::ReadAllText($overrides).Replace("`r`n","`n")
$pattern = '(?ms)^  flutter_inappwebview_android:\n.*?(?=^  [A-Za-z_][A-Za-z0-9_]*:\n|\z)'
if ([regex]::Matches($text,$pattern).Count -ne 1) { throw 'Expected one Android WebView override block' }
$replacement = "  flutter_inappwebview_android:`n    path: $($destination.Replace('\','/'))`n"
[IO.File]::WriteAllText($overrides,[regex]::Replace($text,$pattern,$replacement),[Text.UTF8Encoding]::new($false))
$manifest | Add-Member -NotePropertyName watchroomWebview -NotePropertyValue $stamp -Force
Write-JsonFile $manifest $manifestPath
Write-Output "Verified short-path Android WebView copy: $($stamp.files.Count) files at original commit $expected"
