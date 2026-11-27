param([string]$TestRoot)
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'support.ps1')
if (-not $TestRoot) {
    $workspace = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    $TestRoot = Join-Path (Split-Path -Parent $workspace) '.state/spy-output-path-tests'
}
$TestRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($TestRoot)
$location = Get-Location
$processDirectory = [Environment]::CurrentDirectory
try {
    $shellDirectory = Join-Path $TestRoot 'powershell'
    $otherDirectory = Join-Path $TestRoot 'process'
    New-Item -ItemType Directory -Path $shellDirectory,$otherDirectory -Force | Out-Null
    Set-Location -LiteralPath $shellDirectory
    [Environment]::CurrentDirectory = $otherDirectory
    $relativePaths = @('./reports/build-android.json', '../experiment/Android/build-android.json')
    foreach ($relative in $relativePaths) {
        Write-SpyJson @{status='path-test';versionCode=565512} $relative
        $expected = Join-Path $shellDirectory $relative
        if (-not (Test-Path -LiteralPath $expected)) { throw "Report missing at PowerShell-relative path: $relative" }
        $report = Get-Content -LiteralPath $expected -Raw | ConvertFrom-Json
        if ($report.status -cne 'path-test' -or $report.versionCode -ne 565512) { throw 'Report content differs' }
    }
    $absolute = Join-Path $TestRoot 'absolute/build-android.json'
    Write-SpyJson @{status='absolute-test'} $absolute
    if ((Get-Content -LiteralPath $absolute -Raw | ConvertFrom-Json).status -cne 'absolute-test') { throw 'Absolute path failed' }
    if (Test-Path -LiteralPath (Join-Path $otherDirectory 'reports/build-android.json')) { throw 'Report leaked into the process working directory' }
    Write-Output 'PASS: relative reports use PowerShell location despite a different System.IO working directory; absolute reports retained.'
} finally {
    [Environment]::CurrentDirectory = $processDirectory
    Set-Location -LiteralPath $location
}
