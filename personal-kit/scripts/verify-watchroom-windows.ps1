param([Parameter(Mandatory)][string]$BuildManifest)
. (Join-Path $PSScriptRoot 'common.ps1')
$path = Get-CanonicalPath $BuildManifest
$m = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
if ($m.platform -ne 'windows') { throw 'Expected Windows manifest' }
$source = Assert-GeneratedWorktree $m.repoPath $m.generatedWorktree $m.upstreamCommit @($m.contributionCheckout,$m.personalKitWorktree)
$build = $m.watchroomWindowsBuild
$output = Get-CanonicalPath $build.directory
$original = Join-Path $source 'build/windows/x64/runner/Release'
$records = @()
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead($build.zip)
try {
    foreach ($file in Get-ChildItem -LiteralPath $output -File -Recurse) {
        $relative = $file.FullName.Substring($output.Length + 1).Replace('\','/')
        $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($hash -ne (Get-FileHash -LiteralPath (Join-Path $original $relative) -Algorithm SHA256).Hash.ToLowerInvariant()) { throw "Staged file differs from build: $relative" }
        $entry = $zip.GetEntry($relative)
        if ($null -eq $entry) { throw "ZIP missing file: $relative" }
        $stream = $entry.Open()
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $zipHash = [Convert]::ToHexString($sha.ComputeHash($stream)).ToLowerInvariant() }
        finally { $stream.Dispose(); $sha.Dispose() }
        if ($hash -ne $zipHash) { throw "ZIP file differs: $relative" }
        $records += @{path=$relative;length=$file.Length;sha256=$hash}
    }
} finally { $zip.Dispose() }
$aot = [Text.Encoding]::Latin1.GetString([IO.File]::ReadAllBytes((Join-Path $output 'data/app.so')))
$checks = [ordered]@{}
foreach ($feature in @('watchroom-windows','PiliPlus-watchroom-windows','pgc/freya/room/leave','prepareDesktopExit','WatchroomPanel')) {
    $checks[$feature] = $aot.Contains($feature)
    if (-not $checks[$feature]) { throw "Missing packaged feature: $feature" }
}
$aot = $null
$report = @{files=$records;packagedChecks=$checks;stagedFilesMatchBuild=$true;zipMatchesStagedFiles=$true;zipSha256=(Get-FileHash -LiteralPath $build.zip -Algorithm SHA256).Hash.ToLowerInvariant()}
$reportPath = Join-Path (Split-Path -Parent $path) ("windows-verification-$($m.buildId).json")
Write-JsonFile $report $reportPath
$m.watchroomWindowsBuild | Add-Member -NotePropertyName verificationReport -NotePropertyValue $reportPath -Force
Write-JsonFile $m $path
Assert-FingerprintEqual $m.contributionFingerprint (Get-CheckoutFingerprint $m.contributionCheckout)
Write-Output "Verified Windows release: $($records.Count) files, isolated profile/cache and room features, ZIP matches staged build."
