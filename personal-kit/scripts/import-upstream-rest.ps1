param(
    [Parameter(Mandatory)][string]$RepoPath,
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{40}$')][string]$CommitSha,
    [Parameter()][string]$CacheRoot
)

. (Join-Path $PSScriptRoot 'common.ps1')

$repo = Get-CanonicalPath $RepoPath
Write-Output "stage=metadata commit=$CommitSha"
if (-not $CacheRoot) {
    $CacheRoot = Join-Path (Get-CanonicalPath (Join-Path $PSScriptRoot '..')) '.cache\upstream-import'
}
if (-not (Test-Path -LiteralPath $CacheRoot)) { New-Item -ItemType Directory -Path $CacheRoot | Out-Null }
$cache = Get-CanonicalPath $CacheRoot
$headers = @{Accept = 'application/vnd.github+json'; 'X-GitHub-Api-Version' = '2022-11-28'}
$apiBase = 'https://api.github.com/repos/bggRGjQaUbCoE/PiliPlus'
$commit = Invoke-RestMethod -Headers $headers -Uri "$apiBase/git/commits/$CommitSha"
if ($commit.sha -cne $CommitSha) { throw "GitHub commit API returned unexpected SHA: $($commit.sha)" }
$expectedTree = $commit.tree.sha
$treeResponse = Invoke-RestMethod -Headers $headers -Uri "$apiBase/git/trees/$expectedTree`?recursive=1"
if ($treeResponse.sha -cne $expectedTree -or $treeResponse.truncated) {
    throw "GitHub tree response is incomplete or mismatched for $expectedTree"
}
$blobEntries = @($treeResponse.tree | Where-Object { $_.type -eq 'blob' })
$unsupported = @($treeResponse.tree | Where-Object { $_.type -notin @('blob', 'tree') })
if ($unsupported.Count -gt 0) {
    throw "REST fallback refuses unsupported Git tree entries: $($unsupported.path -join ', ')"
}
Write-Output "stage=metadata-complete tree=$expectedTree blobs=$($blobEntries.Count)"

$archive = Join-Path $cache "$CommitSha.zip"
if (-not (Test-Path -LiteralPath $archive -PathType Leaf)) {
    $download = "$archive.download"
    if (Test-Path -LiteralPath $download) { throw "Partial upstream archive preserved: $download" }
    Invoke-WebRequest -UseBasicParsing -Uri "https://codeload.github.com/bggRGjQaUbCoE/PiliPlus/zip/$CommitSha" -OutFile $download
    Move-Item -LiteralPath $download -Destination $archive
}
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$extract = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $repo) "PiliPlus-rest-import-$($CommitSha.Substring(0, 12))-$stamp"))
if (Test-Path -LiteralPath $extract) { throw "REST import extraction candidate already exists: $extract" }
New-Item -ItemType Directory -Path $extract | Out-Null
Invoke-Native tar @('-xf', $archive, '-C', $extract)
Write-Output "stage=archive-extracted path=$extract"
$roots = @(Get-ChildItem -LiteralPath $extract -Directory)
if ($roots.Count -ne 1) { throw "Upstream archive must contain exactly one root directory; found $($roots.Count). Diagnostic extraction: $extract" }
$source = $roots[0].FullName

$archiveFiles = @(Get-ChildItem -LiteralPath $source -Recurse -File -Force)
if ($archiveFiles.Count -ne $blobEntries.Count) {
    throw "Archive/blob count mismatch (archive=$($archiveFiles.Count), tree=$($blobEntries.Count)). Diagnostic extraction: $extract"
}
$validated = @()
foreach ($entry in $blobEntries) {
    $relative = $entry.path
    if ([IO.Path]::IsPathRooted($relative) -or $relative -match '(^|/)\.\.(/|$)') {
        throw "Unsafe path in upstream tree: $relative"
    }
    $file = Join-Path $source ($relative.Replace('/', [IO.Path]::DirectorySeparatorChar))
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Archive is missing upstream blob: $relative" }
    if ($relative.Contains("`n") -or $relative.Contains("`r")) { throw "REST fallback refuses newline in path: $relative" }
    $validated += [pscustomobject]@{path=$relative;mode=$entry.mode;sha=$entry.sha;file=$file}
}
Write-Output "stage=archive-mapped files=$($validated.Count)"

function Invoke-BlobBatches {
    param([Parameter(Mandatory)]$Entries, [switch]$Write)
    $result = @()
    for ($offset = 0; $offset -lt $Entries.Count; $offset += 20) {
        $last = [Math]::Min($offset + 19, $Entries.Count - 1)
        $batch = @($Entries[$offset..$last])
        $arguments = @('-C', $repo, 'hash-object')
        if ($Write) { $arguments += '-w' }
        $arguments += @('--no-filters', '--')
        $arguments += @($batch | ForEach-Object file)
        $output = @(& git @arguments)
        if ($LASTEXITCODE -ne 0) { throw "Git blob batch failed at offset $offset (write=$Write)." }
        if ($output.Count -ne $batch.Count) { throw "Git blob batch count mismatch at offset $offset." }
        for ($index = 0; $index -lt $batch.Count; $index++) {
            $actual = $output[$index].Trim()
            if ($actual -cne $batch[$index].sha) {
                throw "Upstream blob mismatch for $($batch[$index].path). Expected $($batch[$index].sha), found $actual. Diagnostic extraction: $extract"
            }
            $result += $actual
        }
    }
    return $result
}

Write-Output 'stage=blob-validation-start'
[void](Invoke-BlobBatches -Entries $validated)
Write-Output 'stage=blob-validation-complete'

function Invoke-GitWithInputLines {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][string[]]$Lines,
        [Parameter(Mandatory)][string]$WorkingDirectory
    )
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = 'git'
    $start.WorkingDirectory = $WorkingDirectory
    $start.Arguments = ($Arguments | ForEach-Object { if ($_ -match '\s') { '"' + $_.Replace('"', '\"') + '"' } else { $_ } }) -join ' '
    $start.UseShellExecute = $false
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    if ($start.PSObject.Properties.Name -contains 'StandardInputEncoding') {
        $start.StandardInputEncoding = [Text.UTF8Encoding]::new($false)
    }
    $process = [Diagnostics.Process]::Start($start)
    foreach ($line in $Lines) { $process.StandardInput.WriteLine($line) }
    $process.StandardInput.Close()
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) { throw "git $($Arguments -join ' ') failed: $stderr" }
    return $stdout
}

Write-Output 'stage=blob-write-start'
[void](Invoke-BlobBatches -Entries $validated -Write)
Write-Output 'stage=blob-write-complete'
$indexPath = Join-Path $cache "index-$CommitSha-$stamp"
if (Test-Path -LiteralPath $indexPath) { throw "Temporary import index already exists: $indexPath" }
try {
    $env:GIT_INDEX_FILE = $indexPath
    Invoke-Native git @('-C', $repo, 'read-tree', '--empty')
    for ($offset = 0; $offset -lt $validated.Count; $offset += 20) {
        $last = [Math]::Min($offset + 19, $validated.Count - 1)
        $batch = @($validated[$offset..$last])
        $arguments = @('-C', $repo, 'update-index', '--add')
        foreach ($entry in $batch) {
            $arguments += @('--cacheinfo', "$($entry.mode),$($entry.sha),$($entry.path)")
        }
        Invoke-Native git $arguments
    }
    $actualTree = (Get-GitOutput $repo @('write-tree')).Trim()
} finally {
    Remove-Item Env:GIT_INDEX_FILE -ErrorAction SilentlyContinue
}
Write-Output "stage=tree-reconstructed actual=$actualTree"
if ($actualTree -cne $expectedTree) {
    throw "Reconstructed upstream tree mismatch. Expected $expectedTree, found $actualTree. Diagnostic extraction: $extract"
}

function Get-GitObjectSha1 {
    param([Parameter(Mandatory)][byte[]]$Content, [Parameter(Mandatory)][string]$Type)
    $header = [Text.Encoding]::ASCII.GetBytes("$Type $($Content.Length)`0")
    $payload = New-Object byte[] ($header.Length + $Content.Length)
    [Array]::Copy($header, 0, $payload, 0, $header.Length)
    [Array]::Copy($Content, 0, $payload, $header.Length, $Content.Length)
    $sha = [Security.Cryptography.SHA1]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($payload))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

$authorSeconds = [DateTimeOffset]::Parse($commit.author.date).ToUnixTimeSeconds()
$committerSeconds = [DateTimeOffset]::Parse($commit.committer.date).ToUnixTimeSeconds()
$parentLines = @($commit.parents | ForEach-Object { "parent $($_.sha)" })
$offsets = @()
for ($minutes = -720; $minutes -le 840; $minutes += 15) {
    $sign = if ($minutes -lt 0) { '-' } else { '+' }
    $absolute = [Math]::Abs($minutes)
    $offsets += ('{0}{1:00}{2:00}' -f $sign, [Math]::Floor($absolute / 60), ($absolute % 60))
}
$rawCommit = $null
$matchedAuthorOffset = $null
$matchedCommitterOffset = $null
foreach ($authorOffset in $offsets) {
    foreach ($committerOffset in $offsets) {
        foreach ($trailingNewline in @($false, $true)) {
            $lines = @(
                "tree $expectedTree"
                $parentLines
                "author $($commit.author.name) <$($commit.author.email)> $authorSeconds $authorOffset"
                "committer $($commit.committer.name) <$($commit.committer.email)> $committerSeconds $committerOffset"
                ''
                $commit.message
            )
            $body = ($lines -join "`n") + $(if ($trailingNewline) { "`n" } else { '' })
            $bytes = [Text.UTF8Encoding]::new($false).GetBytes($body)
            if ((Get-GitObjectSha1 $bytes 'commit') -ceq $CommitSha) {
                $rawCommit = $bytes
                $matchedAuthorOffset = $authorOffset
                $matchedCommitterOffset = $committerOffset
                break
            }
        }
        if ($null -ne $rawCommit) { break }
    }
    if ($null -ne $rawCommit) { break }
}
if ($null -eq $rawCommit) {
    throw "Validated tree was reconstructed, but commit object metadata could not reproduce $CommitSha. No ref was updated. Diagnostic extraction: $extract"
}
Write-Output "stage=commit-reconstructed authorOffset=$matchedAuthorOffset committerOffset=$matchedCommitterOffset"

$startInfo = [Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = 'git'
$startInfo.Arguments = "-C `"$repo`" hash-object --literally -t commit -w --stdin"
$startInfo.UseShellExecute = $false
$startInfo.RedirectStandardInput = $true
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true
$process = [Diagnostics.Process]::Start($startInfo)
$process.StandardInput.BaseStream.Write($rawCommit, 0, $rawCommit.Length)
$process.StandardInput.Close()
$writtenCommit = $process.StandardOutput.ReadToEnd().Trim()
$writeError = $process.StandardError.ReadToEnd()
$process.WaitForExit()
if ($process.ExitCode -ne 0 -or $writtenCommit -cne $CommitSha) {
    throw "Failed writing verified upstream commit object: $writeError"
}
$commitHeader = Get-GitOutput $repo @('cat-file', 'commit', $CommitSha)
$catTree = ([regex]::Match($commitHeader, '(?m)^tree ([0-9a-f]{40})$')).Groups[1].Value
if ($catTree -cne $expectedTree) { throw "Written commit tree mismatch: $catTree" }
Invoke-Native git @('-C', $repo, 'update-ref', 'refs/remotes/upstream/main', $CommitSha)
[ordered]@{
    commit = $CommitSha
    tree = $expectedTree
    blobCount = $blobEntries.Count
    authorOffset = $matchedAuthorOffset
    committerOffset = $matchedCommitterOffset
    archive = $archive
    archiveSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $archive).Hash.ToLowerInvariant()
    diagnosticExtraction = $extract
    remoteTrackingRefUpdated = $true
} | ConvertTo-Json -Depth 5
