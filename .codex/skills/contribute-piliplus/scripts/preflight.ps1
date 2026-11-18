[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$RepoPath = ".",

    [switch]$RequireFeatureBranch
)

$ErrorActionPreference = "Stop"

function Invoke-Git {
    param(
        [Parameter(Mandatory)]
        [string]$WorkingTree,

        [Parameter(Mandatory)]
        [string[]]$Arguments,

        [switch]$AllowFailure
    )

    $output = @(& git -C $WorkingTree @Arguments 2>$null)
    $exitCode = $LASTEXITCODE
    if (-not $AllowFailure -and $exitCode -ne 0) {
        throw "git $($Arguments -join ' ') failed with exit code $exitCode."
    }
    return [PSCustomObject]@{
        ExitCode = $exitCode
        Output   = $output
    }
}

$resolvedInput = (Resolve-Path -LiteralPath $RepoPath).Path
$rootResult = Invoke-Git -WorkingTree $resolvedInput -Arguments @(
    "rev-parse",
    "--show-toplevel"
)
$repoRoot = ($rootResult.Output -join "`n").Trim()

if (-not $repoRoot) {
    throw "Could not resolve a Git worktree from '$resolvedInput'."
}

$branch = ((Invoke-Git -WorkingTree $repoRoot -Arguments @(
    "branch",
    "--show-current"
)).Output -join "`n").Trim()

if (-not $branch) {
    throw "The checkout is in detached HEAD state. Create or switch to a feature branch."
}

$status = (Invoke-Git -WorkingTree $repoRoot -Arguments @(
    "status",
    "--porcelain"
)).Output
$origin = ((Invoke-Git -WorkingTree $repoRoot -Arguments @(
    "config",
    "--get",
    "remote.origin.url"
) -AllowFailure).Output -join "`n").Trim()
$upstream = ((Invoke-Git -WorkingTree $repoRoot -Arguments @(
    "config",
    "--get",
    "remote.upstream.url"
) -AllowFailure).Output -join "`n").Trim()
$tracking = ((Invoke-Git -WorkingTree $repoRoot -Arguments @(
    "rev-parse",
    "--abbrev-ref",
    "--symbolic-full-name",
    "@{upstream}"
) -AllowFailure).Output -join "`n").Trim()

$officialPattern = "(?i)(github\.com[:/])bggRGjQaUbCoE/PiliPlus(?:\.git)?$"
$forkPattern = "(?i)(github\.com[:/])(?!bggRGjQaUbCoE/)[^/]+/PiliPlus(?:\.git)?$"
$problems = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()

if (-not $origin) {
    $problems.Add("Remote 'origin' is missing.")
}
elseif ($origin -match $officialPattern) {
    $problems.Add(
        "Remote 'origin' points to upstream. Use the contributor fork as origin."
    )
}
elseif ($origin -notmatch $forkPattern) {
    $warnings.Add(
        "Remote 'origin' does not look like a GitHub PiliPlus fork: $origin"
    )
}

if (-not $upstream) {
    $warnings.Add(
        "Remote 'upstream' is missing. Add it with: git remote add upstream " +
        "https://github.com/bggRGjQaUbCoE/PiliPlus.git"
    )
}
elseif ($upstream -notmatch $officialPattern) {
    $problems.Add(
        "Remote 'upstream' does not point to bggRGjQaUbCoE/PiliPlus: $upstream"
    )
}

$protectedBranches = @("main", "dev", "dom", "personal/main", "spy/main", "spy/dev")
if ((Split-Path -Leaf $repoRoot) -in @('PiliPlus-SPY','PiliPlus-personal-kit')) {
    $problems.Add('Use PiliPlusAbout/PiliPlus for upstream contributions; this checkout belongs to SPY.')
}
if ($RequireFeatureBranch -and $branch -in $protectedBranches) {
    $problems.Add(
        "Current branch '$branch' is not a feature branch. Create a focused " +
        "branch from upstream/main before staging."
    )
}
elseif ($branch -in $protectedBranches) {
    $warnings.Add(
        "Current branch is '$branch'. Create a feature branch before editing."
    )
}

[PSCustomObject]@{
    RepoRoot = $repoRoot
    Branch   = $branch
    Tracking = $tracking
    Clean    = ($status.Count -eq 0)
    Origin   = $origin
    Upstream = $upstream
}

foreach ($warning in $warnings) {
    Write-Warning $warning
}

if ($status.Count -gt 0) {
    Write-Warning "The worktree has $($status.Count) changed path(s). Preserve unrelated work."
}

if ($problems.Count -gt 0) {
    foreach ($problem in $problems) {
        Write-Error $problem -ErrorAction Continue
    }
    exit 2
}

exit 0
