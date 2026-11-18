# Exercise real upstream patches without modifying the shared Flutter source.
. (Join-Path $PSScriptRoot '../support.ps1')
$source = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$context = Get-SpyContext $source ''
$before = Get-SpyGit $source @('status','--porcelain','--untracked-files=all')
foreach ($attempt in 1..2) {
    $result = Prepare-SpyIosSource $context -CheckOnly
    foreach ($file in $result.files) {
        $staged = Join-Path $context.cache "spy/ios-source-reference/$($file.path)"
        if (-not (Test-Path -LiteralPath $staged -PathType Leaf)) { throw 'Native patch resolved to a directory or missing file' }
        if ((Get-SpyHash $staged) -cne $file.sha256) { throw 'Staged native source hash mismatch' }
    }
    $plugin = Join-Path $context.cache 'spy/ios-source-reference/lib/pages/login/geetest/geetest_plugin.dart'
    if (-not (Test-Path -LiteralPath $plugin -PathType Leaf)) { throw 'Native login plugin was not staged' }
}
if ((Get-SpyGit $source @('status','--porcelain','--untracked-files=all')) -cne $before) { throw 'Check-only preparation changed application source' }
Write-Output 'Native iOS source preparation passed twice without changing application source.'
