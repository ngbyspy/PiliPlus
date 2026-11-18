param(
    [Parameter(Mandatory)][string]$RepoPath,
    [Parameter(Mandatory)][string]$PersonalKitWorktree,
    [Parameter(Mandatory)][string]$SourceRoot,
    [Parameter(Mandatory)][string]$BuildManifest,
    [string]$BuildId = ('watchroom-ios-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
)
. (Join-Path $PSScriptRoot 'common.ps1')
$repo = Get-CanonicalPath $RepoPath
$kit = Get-CanonicalPath $PersonalKitWorktree
$source = Get-CanonicalPath $SourceRoot -AllowMissing
$config = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../config/watchroom-toolchain-ios.json') -Raw | ConvertFrom-Json
if ((Get-GitOutput $kit @('symbolic-ref','--short','HEAD')) -cne 'personal/main') { throw 'Expected personal/main kit worktree' }
if ((Get-GitOutput $repo @('remote','get-url','origin')) -notmatch 'ngbyspy/PiliPlus(\.git)?$') { throw 'Unexpected fork' }
if ((Get-GitOutput $repo @('remote','get-url','upstream')) -notmatch 'bggRGjQaUbCoE/PiliPlus(\.git)?$') { throw 'Unexpected upstream' }
if (Test-Path -LiteralPath $source) { throw 'SourceRoot already exists; preserve existing build trees' }
if (Test-Path -LiteralPath $BuildManifest) { throw 'Build manifest already exists; use a new path' }
$fingerprint = Get-CheckoutFingerprint $repo
Invoke-Native git @('-C',$repo,'fetch','upstream','main')
$latest = Get-GitOutput $repo @('rev-parse','upstream/main')
if ($latest -cne $config.upstreamCommit) { throw "Upstream moved to $latest; inspect drift before changing the accepted platform baseline" }
Invoke-Native git @('-C',$repo,'worktree','add','--detach',$source,$latest)
$manifest = @{
    schemaVersion=1;buildId=$BuildId;platform='ios';repoPath=$repo;contributionCheckout=$repo;
    personalKitWorktree=$kit;generatedWorktree=$source;upstreamCommit=$latest;
    contributionFingerprint=$fingerprint;personalKitIdentity=(Get-KitIdentity $kit);
    validation=@{};createdOn=[DateTimeOffset]::UtcNow.ToString('o')
}
Assert-FingerprintEqual $fingerprint (Get-CheckoutFingerprint $repo)
Write-JsonFile $manifest $BuildManifest
Write-Output "Created isolated iOS source at $source ($latest)"
