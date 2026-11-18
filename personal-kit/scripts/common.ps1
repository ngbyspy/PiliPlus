Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-Native {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter()][string[]]$ArgumentList = @(),
        [Parameter()][string]$WorkingDirectory
    )

    $previous = Get-Location
    try {
        if ($WorkingDirectory) { Set-Location -LiteralPath $WorkingDirectory }
        & $FilePath @ArgumentList
        if ($LASTEXITCODE -ne 0) {
            throw "Native command failed ($LASTEXITCODE): $FilePath $($ArgumentList -join ' ')"
        }
    } finally {
        Set-Location -LiteralPath $previous
    }
}

function Get-CanonicalPath {
    param([Parameter(Mandatory)][string]$Path, [switch]$AllowMissing)
    if (Test-Path -LiteralPath $Path) {
        return [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Path).Path).TrimEnd([char]'\', [char]'/')
    }
    if (-not $AllowMissing) { throw "Path does not exist: $Path" }
    return [IO.Path]::GetFullPath($Path).TrimEnd([char]'\', [char]'/')
}

function Get-StringSha256 {
    param([AllowEmptyString()][string]$Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Get-GitOutput {
    param([Parameter(Mandatory)][string]$RepoPath, [Parameter(Mandatory)][string[]]$Arguments)
    $output = & git -C $RepoPath @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "git $($Arguments -join ' ') failed: $($output -join [Environment]::NewLine)" }
    return ($output -join "`n").TrimEnd()
}

function Get-CheckoutFingerprint {
    param([Parameter(Mandatory)][string]$RepoPath)
    $root = Get-CanonicalPath (Get-GitOutput $RepoPath @('rev-parse', '--show-toplevel'))
    $branch = Get-GitOutput $root @('symbolic-ref', '--short', 'HEAD')
    $head = Get-GitOutput $root @('rev-parse', 'HEAD')
    $status = Get-GitOutput $root @('status', '--porcelain=v2', '--branch', '--untracked-files=all')
    $trackedDiff = Get-GitOutput $root @('diff', '--binary', 'HEAD')
    $indexDiff = Get-GitOutput $root @('diff', '--cached', '--binary')
    $untracked = @((Get-GitOutput $root @('ls-files', '--others', '--exclude-standard')) -split "`n" | Where-Object { $_ })
    $untrackedData = @()
    foreach ($relative in $untracked) {
        $full = Join-Path $root $relative
        $untrackedData += [ordered]@{
            path = $relative.Replace('\\', '/')
            length = (Get-Item -LiteralPath $full).Length
            sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $full).Hash.ToLowerInvariant()
        }
    }
    return [ordered]@{
        root = $root
        branch = $branch
        head = $head
        statusSha256 = Get-StringSha256 $status
        trackedDiffSha256 = Get-StringSha256 $trackedDiff
        indexDiffSha256 = Get-StringSha256 $indexDiff
        untracked = $untrackedData
    }
}

function Assert-FingerprintEqual {
    param([Parameter(Mandatory)]$Expected, [Parameter(Mandatory)]$Actual)
    $left = $Expected | ConvertTo-Json -Depth 12 -Compress
    $right = $Actual | ConvertTo-Json -Depth 12 -Compress
    if ($left -cne $right) {
        throw "Contribution checkout changed. Expected: $left Actual: $right"
    }
}

function Get-KitIdentity {
    param([Parameter(Mandatory)][string]$KitWorktree)
    $head = $null
    $previousErrorPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & git -C $KitWorktree rev-parse --verify HEAD *> $null
    $hasHead = $LASTEXITCODE -eq 0
    $ErrorActionPreference = $previousErrorPreference
    if ($hasHead) { $head = (Get-GitOutput $KitWorktree @('rev-parse', 'HEAD')).Trim() }
    $diff = (& git -C $KitWorktree diff --binary 2>$null) -join "`n"
    $untracked = @(& git -C $KitWorktree ls-files --others --exclude-standard)
    $files = @()
    foreach ($relative in $untracked) {
        if (-not $relative) { continue }
        $full = Join-Path $KitWorktree $relative
        $files += [ordered]@{
            path = $relative.Replace('\\', '/')
            sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $full).Hash.ToLowerInvariant()
        }
    }
    return [ordered]@{
        commit = $head
        dirty = [bool]($diff.Length -gt 0 -or $untracked.Count -gt 0)
        diffSha256 = Get-StringSha256 $diff
        untrackedFiles = $files
    }
}

function Get-RegisteredWorktrees {
    param([Parameter(Mandatory)][string]$RepoPath)
    $lines = @((Get-GitOutput $RepoPath @('worktree', 'list', '--porcelain')) -split "`n")
    $items = @()
    $item = $null
    foreach ($line in $lines) {
        if ($line.StartsWith('worktree ')) {
            if ($null -ne $item) { $items += [pscustomobject]$item }
            $item = [ordered]@{ path = Get-CanonicalPath $line.Substring(9); head = $null; branch = $null; detached = $false }
        } elseif ($null -ne $item -and $line.StartsWith('HEAD ')) {
            $item.head = $line.Substring(5)
        } elseif ($null -ne $item -and $line.StartsWith('branch ')) {
            $item.branch = $line.Substring(7)
        } elseif ($null -ne $item -and $line -eq 'detached') {
            $item.detached = $true
        }
    }
    if ($null -ne $item) { $items += [pscustomobject]$item }
    return $items
}

function Assert-GeneratedWorktree {
    param(
        [Parameter(Mandatory)][string]$RepoPath,
        [Parameter(Mandatory)][string]$SourceRoot,
        [Parameter(Mandatory)][string]$ExpectedCommit,
        [Parameter(Mandatory)][string[]]$ProtectedRoots
    )
    $source = Get-CanonicalPath $SourceRoot
    foreach ($protected in $ProtectedRoots) {
        if ($source -ieq (Get-CanonicalPath $protected)) { throw "Generated worktree overlaps protected worktree: $source" }
    }
    $matches = @(Get-RegisteredWorktrees $RepoPath | Where-Object { $_.path -ieq $source })
    if ($matches.Count -ne 1) { throw "Expected exactly one registered generated worktree for $source; found $($matches.Count)." }
    $match = $matches[0]
    if (-not $match.detached -or $match.branch) { throw "Generated worktree is not detached: $source" }
    if ($match.head -ine $ExpectedCommit) { throw "Generated worktree commit mismatch. Expected $ExpectedCommit, found $($match.head)." }
    $actualHead = Get-GitOutput $source @('rev-parse', 'HEAD')
    if ($actualHead -ine $ExpectedCommit) { throw "Generated worktree HEAD mismatch: $actualHead" }
    return $source
}

function Write-JsonFile {
    param([Parameter(Mandatory)]$Value, [Parameter(Mandatory)][string]$Path)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent | Out-Null }
    $Value | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding utf8
}
