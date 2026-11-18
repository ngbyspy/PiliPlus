param(
    [Parameter(Mandatory)][string]$RepoPath,
    [Parameter(Mandatory)][string]$PersonalKitWorktree
)

. (Join-Path $PSScriptRoot 'common.ps1')

$repo = Get-CanonicalPath $RepoPath
$personal = Get-CanonicalPath $PersonalKitWorktree
if ((Get-GitOutput $repo @('remote', 'get-url', 'origin')) -notmatch 'ngbyspy/PiliPlus(\.git)?$') {
    throw 'origin is not the expected user fork.'
}
if ((Get-GitOutput $repo @('remote', 'get-url', 'upstream')) -notmatch 'bggRGjQaUbCoE/PiliPlus(\.git)?$') {
    throw 'upstream is not the expected authoritative repository.'
}
$branch = Get-GitOutput $personal @('symbolic-ref', '--short', 'HEAD')
if ($branch -cne 'personal/main') { throw "Personal kit worktree is on unexpected branch: $branch" }
$worktrees = @(Get-RegisteredWorktrees $repo)
if (@($worktrees | Where-Object { $_.path -ieq $repo }).Count -ne 1) { throw 'Contribution checkout is not registered exactly once.' }
if (@($worktrees | Where-Object { $_.path -ieq $personal }).Count -ne 1) { throw 'Personal kit worktree is not registered exactly once.' }
$fvmrc = Get-Content -LiteralPath (Join-Path $repo '.fvmrc') -Raw | ConvertFrom-Json
$pubspecFlutter = (Select-String -LiteralPath (Join-Path $repo 'pubspec.yaml') -Pattern '^  flutter:\s*(\S+)' | Select-Object -First 1).Matches.Groups[1].Value
if ($fvmrc.flutter -ne $pubspecFlutter) {
    throw "Repository Flutter pins disagree: .fvmrc=$($fvmrc.flutter), pubspec=$pubspecFlutter"
}
[ordered]@{
    repo = $repo
    personalKitWorktree = $personal
    contribution = Get-CheckoutFingerprint $repo
    flutterVersion = $fvmrc.flutter
    worktrees = $worktrees
} | ConvertTo-Json -Depth 10
