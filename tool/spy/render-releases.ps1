param(
    [string]$ReleaseRoot = (Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) 'Releases')
)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Path $ReleaseRoot -Force | Out-Null
$releases = @()
foreach ($directory in Get-ChildItem -LiteralPath $ReleaseRoot -Directory) {
    $manifestPath = Join-Path $directory.FullName '_metadata/release-manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath)) { $manifestPath = Join-Path $directory.FullName 'release-manifest.json' }
    if (-not (Test-Path -LiteralPath $manifestPath)) { continue }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $assets = @()
    foreach ($artifact in $manifest.artifacts) {
        $relative = $artifact.file.Replace('\','/')
        if ($relative.StartsWith('/') -or '..' -in ($relative -split '/')) { throw 'Unsafe release asset path' }
        $file = Join-Path $directory.FullName $relative
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Release asset missing: $relative" }
        $href = (($directory.Name + '/' + $relative) -split '/' | ForEach-Object { [uri]::EscapeDataString($_) }) -join '/'
        $assets += @{platform=$artifact.platform;name=(Split-Path -Leaf $file);href=$href;bytes=(Get-Item -LiteralPath $file).Length;sha256=$artifact.sha256;sourceCommit=$artifact.sourceCommit}
    }
    $releases += @{version=$manifest.version;title=$manifest.title;date=$manifest.date;historical=[bool]$manifest.historical;highlights=@($manifest.highlights);pendingPlatforms=@($manifest.pendingPlatforms);assets=$assets}
}
$releases = @($releases | Sort-Object @{Expression={ $_.historical };Ascending=$true},@{Expression={ $_.date };Descending=$true})
$data = ConvertTo-Json -InputObject $releases -Depth 20 -Compress
$data = $data.Replace('<','\u003c').Replace('>','\u003e').Replace('&','\u0026')
$template = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'release-page.html'))
$output = Join-Path $ReleaseRoot 'index.html'
[IO.File]::WriteAllText($output,$template.Replace('__RELEASE_DATA__',$data),[Text.UTF8Encoding]::new($false))
Write-Output "Local release page: $output ($($releases.Count) versions)"
