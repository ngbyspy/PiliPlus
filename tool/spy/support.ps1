Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-SpyNative([string]$Command, [string[]]$Arguments, [string]$Directory) {
    $previous = Get-Location
    try {
        if ($Directory) { Set-Location -LiteralPath $Directory }
        & $Command @Arguments
        if ($LASTEXITCODE -ne 0) { throw "Command failed ($LASTEXITCODE): $Command $($Arguments -join ' ')" }
    } finally { Set-Location -LiteralPath $previous }
}

function Get-SpyGit([string]$Root, [string[]]$Arguments) {
    $result = & git -C $Root @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Git failed: $($Arguments -join ' ')" }
    ($result -join "`n").TrimEnd()
}

function Get-SpyHash([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Get-SpyTextHash([string]$Text) { [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Text))).ToLowerInvariant() }
function Write-SpyJson($Value, [string]$Path) {
    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    [IO.File]::WriteAllText($Path,($Value | ConvertTo-Json -Depth 30) + "`n",[Text.UTF8Encoding]::new($false))
}

function Get-SpyContext([string]$SourceRoot, [string]$CacheRoot) {
    $source = (Resolve-Path -LiteralPath $SourceRoot).Path
    if ((Get-SpyGit $source @('rev-parse','--show-toplevel')).Replace('/','\') -ine $source.Replace('/','\')) { throw 'SourceRoot must be the repository root' }
    $branch = Get-SpyGit $source @('branch','--show-current')
    if ($branch -notin @('spy/main','spy/dev')) { throw "Expected spy/main or spy/dev, found $branch" }
    if (-not $CacheRoot) {
        $parent = if ($env:GITHUB_ACTIONS -eq 'true') { Join-Path $env:RUNNER_TEMP 'PiliPlus-SPY' } else { Split-Path -Parent $source }
        $CacheRoot = Join-Path $parent '.cache'
    }
    New-Item -ItemType Directory -Path $CacheRoot -Force | Out-Null
    @{source=$source;branch=$branch;commit=(Get-SpyGit $source @('rev-parse','HEAD'));cache=(Resolve-Path -LiteralPath $CacheRoot).Path;release=(Get-Content -LiteralPath (Join-Path $source 'tool/spy/release.json') -Raw | ConvertFrom-Json)}
}

function Prepare-SpySdk($Context, [string]$Platform, [string]$SdkRoot) {
    $configPath = Join-Path $Context.source "tool/spy/config/flutter-$($Platform.ToLowerInvariant()).json"
    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    $pubspec = [IO.File]::ReadAllText((Join-Path $Context.source 'pubspec.yaml'))
    if ([regex]::Match($pubspec,'(?m)^  flutter: (\S+)').Groups[1].Value -cne $config.flutterVersion) { throw 'Flutter version pin drift' }
    $driver = [IO.File]::ReadAllText((Join-Path $Context.source 'lib/scripts/patch.ps1')).Replace("`r`n","`n")
    if ((Get-SpyTextHash $driver) -cne $config.upstreamPatchDriverSha256) { throw 'Upstream platform patch order changed' }
    if (-not $SdkRoot) {
        $suffix = if ($Platform -eq 'Android') { '' } else { '-' + $Platform.ToLowerInvariant() }
        $SdkRoot = Join-Path $Context.cache "flutter/flutter-$($config.flutterVersion)$suffix/flutter"
    }
    if (-not (Test-Path -LiteralPath $SdkRoot)) { throw 'Pinned SDK is missing; prepare Flutter 3.47.9 or provide -SdkRoot' }
    $sdk = (Resolve-Path -LiteralPath $SdkRoot).Path
    if ((Get-SpyGit $sdk @('rev-parse','HEAD')) -cne $config.frameworkCommit) { throw 'Unexpected Flutter framework commit' }
    $targets = [Collections.Generic.HashSet[string]]::new()
    foreach ($patch in $config.patches) {
        $file = Join-Path $Context.source $patch.path
        if ((Get-SpyHash $file) -cne $patch.sha256) { throw "SDK patch identity changed: $($patch.path)" }
        foreach ($line in Get-Content -LiteralPath $file) {
            if ($line -match '^diff --git a/(.+) b/(.+)$') {
                if ($Matches[1] -cne $Matches[2] -or -not $Matches[1].StartsWith('packages/flutter/') -or $Matches[1].Contains('..')) { throw 'Unexpected framework patch target' }
                [void]$targets.Add($Matches[1])
            }
        }
    }
    $fixture = Join-Path $Context.cache "spy/sdk-reference/$Platform"
    New-Item -ItemType Directory -Path $fixture -Force | Out-Null
    $archive = Join-Path $fixture 'base.tar'
    Invoke-SpyNative git (@('-C',$sdk,'archive','--format=tar',"--output=$archive",$config.frameworkCommit) + @($targets))
    Invoke-SpyNative tar @('-xf',$archive,'-C',$fixture)
    Invoke-SpyNative git @('-C',$fixture,'init','--quiet')
    $base = @{}
    foreach ($target in $targets) { $base[$target] = Get-SpyHash (Join-Path $fixture $target) }
    foreach ($patch in $config.patches) {
        $file = Join-Path $Context.source $patch.path
        Invoke-SpyNative git @('-C',$fixture,'apply','--check','--whitespace=nowarn',$file)
        Invoke-SpyNative git @('-C',$fixture,'apply','--whitespace=nowarn',$file)
    }
    $allBase = $true; $allPatched = $true; $files = @()
    foreach ($target in $targets) {
        $expected = Get-SpyHash (Join-Path $fixture $target)
        $actual = Get-SpyHash (Join-Path $sdk $target)
        if ($actual -cne $base[$target]) { $allBase = $false }
        if ($actual -cne $expected) { $allPatched = $false }
        $files += @{path=$target;sha256=$expected}
    }
    if (-not $allBase -and -not $allPatched) { throw 'SDK is partially or unexpectedly modified; preserve it for diagnosis' }
    if (-not $allPatched) {
        foreach ($patch in $config.patches) { Invoke-SpyNative git @('-C',$sdk,'apply','--whitespace=nowarn',(Join-Path $Context.source $patch.path)) }
    }
    foreach ($file in $files) { if ((Get-SpyHash (Join-Path $sdk $file.path)) -cne $file.sha256) { throw 'SDK output verification failed' } }
    $executable = Join-Path $sdk $(if ($IsWindows) { 'bin/flutter.bat' } else { 'bin/flutter' })
    Write-Output "Verified $Platform Flutter $($config.flutterVersion): $($config.patches.Count) patches" | Out-Host
    @{root=$sdk;executable=$executable;version=$config.flutterVersion;commit=$config.frameworkCommit;configSha256=(Get-SpyHash $configPath);patchedFiles=$files}
}

function Set-SpyDependencyOverrides($Context, [hashtable]$Packages = @{}) {
    $pubspec = [IO.File]::ReadAllText((Join-Path $Context.source 'pubspec.yaml')).Replace("`r`n","`n")
    $match = [regex]::Match($pubspec,'(?ms)^dependency_overrides:\n.*?(?=^[^\s#]|\z)')
    if (-not $match.Success) { throw 'Cannot identify upstream dependency overrides' }
    $text = "# Generated by tool/spy; machine-local dependency copies only.`n" + $match.Value.TrimEnd() + "`n"
    foreach ($name in $Packages.Keys | Sort-Object) { $text += "  ${name}:`n    path: " + $Packages[$name].Replace('\','/') + "`n" }
    [IO.File]::WriteAllText((Join-Path $Context.source 'pubspec_overrides.yaml'),$text,[Text.UTF8Encoding]::new($false))
}

function Prepare-SpyDependencies($Context, [string]$Platform) {
    $packages = Get-Content -LiteralPath (Join-Path $Context.source '.dart_tool/package_config.json') -Raw | ConvertFrom-Json
    $paths = @{}; $reports = @()
    $names = @('material_ui'); if ($Platform -eq 'iOS') { $names += 'cupertino_ui' }
    foreach ($name in $names) {
        $package = @($packages.packages | Where-Object name -eq $name)
        if ($package.Count -ne 1) { throw "Missing resolved package: $name" }
        $original = ([uri]$package[0].rootUri).LocalPath
        $version = [regex]::Match([IO.File]::ReadAllText((Join-Path $original 'pubspec.yaml')),'(?m)^version:\s*(\S+)').Groups[1].Value
        if (-not $version) { throw 'Resolved UI package has no version' }
        $destination = Join-Path $Context.cache "spy/dependencies/$Platform/$name-$version"
        $stamp = Join-Path $destination 'spy-patches.json'
        $patchNames = if ($name -eq 'cupertino_ui') { @('lib/scripts/cupertino/bottom_sheet_ios_flutter.patch') } else {
            @('modal_barrier_material','navigation_drawer','popup_menu','fab','text_field','scaffold','refresh_indicator','tabs') | ForEach-Object { "lib/scripts/material/$_.patch" }
            if ($Platform -eq 'Android') { 'lib/scripts/material/bottom_sheet_android.patch' }
            if ($Platform -eq 'iOS') { 'lib/scripts/material/bottom_sheet_ios_flutter_material.patch' }
        }
        if (-not (Test-Path -LiteralPath $stamp)) {
            if (Test-Path -LiteralPath $destination) { throw "Partial package copy: $destination" }
            New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
            Copy-Item -LiteralPath $original -Destination $destination -Recurse
            Invoke-SpyNative git @('-C',$destination,'init','--quiet')
            $files = [Collections.Generic.HashSet[string]]::new(); $patches = @()
            foreach ($relative in $patchNames) {
                $patch = Join-Path $Context.source $relative
                Invoke-SpyNative git @('-C',$destination,'apply','--check','--whitespace=nowarn',$patch)
                Invoke-SpyNative git @('-C',$destination,'apply','--whitespace=nowarn',$patch)
                $patches += @{path=$relative;sha256=(Get-SpyHash $patch)}
                foreach ($line in Get-Content -LiteralPath $patch) {
                    if ($line -match '^\+\+\+ b/(.+)$') {
                        if (-not $Matches[1].StartsWith('lib/') -or $Matches[1].Contains('..')) { throw 'Unsafe UI patch target' }
                        [void]$files.Add($Matches[1])
                    }
                }
            }
            Write-SpyJson @{patches=$patches;files=@($files | ForEach-Object { @{path=$_;sha256=(Get-SpyHash (Join-Path $destination $_))} })} $stamp
        }
        $report = Get-Content -LiteralPath $stamp -Raw | ConvertFrom-Json
        if (@($report.patches).Count -ne @($patchNames).Count) { throw 'Dependency patch set changed' }
        foreach ($patch in $report.patches) { if ((Get-SpyHash (Join-Path $Context.source $patch.path)) -cne $patch.sha256) { throw 'Dependency patch drift' } }
        foreach ($file in $report.files) { if ((Get-SpyHash (Join-Path $destination $file.path)) -cne $file.sha256) { throw 'Patched dependency drift' } }
        $paths[$name] = $destination; $reports += @{name=$name;root=$destination;verification=$report}
    }
    Set-SpyDependencyOverrides $Context $paths
    $reports
}

function Assert-SpyDependencyLock([string]$Expected, [string]$Actual) {
    $left = [IO.File]::ReadAllText($Expected).Replace("`r`n","`n")
    $right = [IO.File]::ReadAllText($Actual).Replace("`r`n","`n")
    foreach ($name in @('material_ui','cupertino_ui')) {
        $pattern = "(?ms)^  ${name}:`n.*?(?=^  [a-zA-Z0-9_]+:|^sdks:)"
        $a = [regex]::Match($left,$pattern); $b = [regex]::Match($right,$pattern)
        $version = '(?m)^    version: "([^"\r\n]+)"$'
        if (-not $a.Success -or -not $b.Success -or [regex]::Match($a.Value,$version).Value -cne [regex]::Match($b.Value,$version).Value) { throw 'Patched UI package version changed' }
        $left = [regex]::Replace($left,$pattern,''); $right = [regex]::Replace($right,$pattern,'')
    }
    if ($left -cne $right) { throw 'Dependency resolution differs from the reviewed lockfile' }
}

function Prepare-SpyIosSource($Context) {
    $config = Get-Content -LiteralPath (Join-Path $Context.source 'tool/spy/config/flutter-ios.json') -Raw | ConvertFrom-Json
    $fixture = Join-Path $Context.cache 'spy/ios-source-reference'
    New-Item -ItemType Directory -Path $fixture -Force | Out-Null
    $archive = Join-Path $fixture 'source.tar'
    Invoke-SpyNative git @('-C',$Context.source,'archive','--format=tar',"--output=$archive",$Context.commit)
    Invoke-SpyNative tar @('-xf',$archive,'-C',$fixture)
    Invoke-SpyNative git @('-C',$fixture,'init','--quiet')
    $targets = [Collections.Generic.HashSet[string]]::new()
    foreach ($patch in $config.sourcePatches) {
        $file = Join-Path $Context.source $patch.path
        if ((Get-SpyHash $file) -cne $patch.sha256) { throw 'Native iOS source patch changed' }
        foreach ($line in Get-Content -LiteralPath $file) {
            if ($line -match '^\+\+\+ b/(.+)$') {
                if ($Matches[1].Contains('..') -or $Matches[1] -notmatch '^(lib/|pubspec\.yaml$)') { throw 'Unexpected native iOS patch target' }
                [void]$targets.Add($Matches[1])
            }
        }
        Invoke-SpyNative git @('-C',$fixture,'apply','--check','--whitespace=nowarn',$file)
        Invoke-SpyNative git @('-C',$fixture,'apply','--whitespace=nowarn',$file)
    }
    $files = @()
    foreach ($target in $targets) {
        $actual = Join-Path $Context.source $target
        $expected = Join-Path $fixture $target
        if (Test-Path -LiteralPath $actual) {
            $content = [IO.File]::ReadAllText($actual).Replace("`r`n","`n").TrimEnd()
            $original = & git -C $Context.source show "$($Context.commit):$target" 2>$null
            if ($LASTEXITCODE -eq 0) {
                if ($content -cne ($original -join "`n").TrimEnd() -and $content -cne [IO.File]::ReadAllText($expected).Replace("`r`n","`n").TrimEnd()) { throw "Unexpected native source modification: $target" }
            } elseif ($content -cne [IO.File]::ReadAllText($expected).TrimEnd()) { throw "Unexpected new native source: $target" }
        }
        $files += @{path=$target;sha256=(Get-SpyHash $expected)}
    }
    foreach ($file in $files) { Copy-Item -LiteralPath (Join-Path $fixture $file.path) -Destination (Join-Path $Context.source $file.path) -Force }
    @{patches=$config.sourcePatches;files=$files}
}
