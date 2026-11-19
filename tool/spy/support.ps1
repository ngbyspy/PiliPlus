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

function Get-SpyDisplayVersion([string]$UpstreamVersion, [string]$Relationship, [int]$ImprovementRevision, [string[]]$UpstreamFixes) {
    if ($Relationship -eq 'parallel' -and $ImprovementRevision -eq 0 -and $UpstreamFixes.Count -eq 0) { return $UpstreamVersion }
    if ($Relationship -eq 'vertical' -and $ImprovementRevision -gt 0 -and $UpstreamFixes.Count -gt 0) { return "$UpstreamVersion.$ImprovementRevision" }
    throw 'Parallel versions keep the upstream number; vertical revisions require an upstream bug fix and positive suffix.'
}

function Assert-SpyReleasePolicy([string]$Source, $Release) {
    $pubspec = Get-SpyGit $Source @('show',"$($Release.upstreamCommit):pubspec.yaml")
    $version = [regex]::Match($pubspec,'(?m)^version:\s*([^+\s]+)').Groups[1].Value
    $code = [int](Get-SpyGit $Source @('rev-list','--count',$Release.upstreamCommit))
    $display = Get-SpyDisplayVersion $version $Release.relationship $Release.improvementRevision @($Release.upstreamFixes)
    if ($Release.version -cne $version -or $Release.displayVersion -cne $display) { throw 'Release version does not follow the upstream/parallel/vertical policy' }
    if ($Release.androidVersionCode -ne $code -or $Release.iosBuildNumber -cne "$code") { throw 'Native build numbers must retain the upstream baseline; do not multiply or count downstream commits' }
    if ($Release.applicationId -cne 'com.example.piliplus' -or $Release.windowsExecutable -cne 'piliplus.exe') { throw 'Windows/Android formal identity must match upstream; iOS defaults are configured separately' }
    foreach ($bundleId in @($Release.iosBundleId,$Release.iosDevelopmentBundleId)) {
        if ($bundleId -cnotmatch '^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$') { throw 'Invalid iOS default Bundle ID' }
    }
    if ($Release.iosBundleId -eq $Release.iosDevelopmentBundleId -or $Release.iosDevelopmentBundleId -cnotmatch '\.dev$') { throw 'iOS development identity must be distinct and end in .dev' }
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
    $release = Get-Content -LiteralPath (Join-Path $source 'tool/spy/release.json') -Raw | ConvertFrom-Json
    Assert-SpyReleasePolicy $source $release
    @{source=$source;branch=$branch;commit=(Get-SpyGit $source @('rev-parse','HEAD'));cache=(Resolve-Path -LiteralPath $CacheRoot).Path;release=$release}
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
    foreach ($name in $Packages.Keys | Sort-Object) {
        $replacement = "  ${name}:`n    path: " + $Packages[$name].Replace('\','/') + "`n"
        $pattern = "(?ms)^  ${name}:`n.*?(?=^  [A-Za-z_][A-Za-z0-9_]*:`n|\z)"
        if ([regex]::Matches($text,$pattern).Count -eq 1) { $text = [regex]::Replace($text,$pattern,$replacement) }
        elseif ([regex]::Matches($text,$pattern).Count -eq 0) { $text += $replacement }
        else { throw 'Ambiguous dependency override' }
    }
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
    if ($Platform -eq 'Android') {
        $webview = Prepare-SpyAndroidWebview $Context $packages
        $paths['flutter_inappwebview_android'] = $webview.root
        $reports += $webview
    }
    Set-SpyDependencyOverrides $Context $paths
    $reports
}

function Assert-SpyDependencyLock([string]$Expected, [string]$Actual, [string[]]$PathPackages = @('material_ui','cupertino_ui')) {
    $left = [IO.File]::ReadAllText($Expected).Replace("`r`n","`n")
    $right = [IO.File]::ReadAllText($Actual).Replace("`r`n","`n")
    foreach ($name in $PathPackages) {
        $pattern = "(?ms)^  ${name}:`n.*?(?=^  [a-zA-Z0-9_]+:|^sdks:)"
        $a = [regex]::Match($left,$pattern); $b = [regex]::Match($right,$pattern)
        $version = '(?m)^    version: "([^"\r\n]+)"$'
        if (-not $a.Success -or -not $b.Success -or [regex]::Match($a.Value,$version).Value -cne [regex]::Match($b.Value,$version).Value) { throw 'Patched UI package version changed' }
        $left = [regex]::Replace($left,$pattern,''); $right = [regex]::Replace($right,$pattern,'')
    }
    if ($left -cne $right) { throw 'Dependency resolution differs from the reviewed lockfile' }
}

function Prepare-SpyAndroidWebview($Context, $Packages) {
    $expected = '0bfa46dfff87f0d9e9d5e13cbd5c4a7c7310f8c9'
    $package = @($Packages.packages | Where-Object name -eq 'flutter_inappwebview_android')
    if ($package.Count -ne 1) { throw 'Expected exactly one Android WebView package' }
    $original = ([uri]$package[0].rootUri).LocalPath
    $repo = Get-SpyGit $original @('rev-parse','--show-toplevel')
    if ((Get-SpyGit $repo @('rev-parse','HEAD')) -cne $expected) { throw 'Android WebView revision changed; inspect the native path workaround' }
    $destination = Join-Path $Context.cache 'wv'
    $stamp = Join-Path $Context.cache 'spy/android-webview.json'
    $archive = Join-Path $Context.cache 'spy/android-webview.tar'
    Invoke-SpyNative git @('-C',$repo,'archive','--format=tar',"--output=$archive",$expected,'flutter_inappwebview_android')
    if (-not (Test-Path -LiteralPath $destination)) {
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
        Invoke-SpyNative tar @('-xf',$archive,'-C',$destination,'--strip-components=1')
    }
    $reference = Join-Path $Context.cache 'spy/webview-reference'
    New-Item -ItemType Directory -Path $reference -Force | Out-Null
    Invoke-SpyNative tar @('-xf',$archive,'-C',$reference,'--strip-components=1')
    $files = @()
    foreach ($file in Get-ChildItem -LiteralPath $reference -Recurse -File -Force) {
        $relative = $file.FullName.Substring($reference.Length+1).Replace('\','/')
        $copy = Join-Path $destination $relative
        if (-not (Test-Path -LiteralPath $copy) -or (Get-SpyHash $copy) -cne (Get-SpyHash $file.FullName)) { throw "Short-path WebView content drift: $relative" }
        $files += @{path=$relative;sha256=(Get-SpyHash $copy)}
    }
    if (@(Get-ChildItem -LiteralPath $destination -Recurse -File -Force).Count -ne $files.Count) { throw 'Unexpected file in short WebView dependency' }
    $report = @{name='flutter_inappwebview_android';root=$destination;commit=$expected;files=$files}
    Write-SpyJson $report $stamp
    $report
}

function Prepare-SpyAndroidNativeLibraries($Context) {
    $packages = Get-Content -LiteralPath (Join-Path $Context.source '.dart_tool/package_config.json') -Raw | ConvertFrom-Json
    $package = @($packages.packages | Where-Object name -eq 'media_kit_libs_android_video')
    if ($package.Count -ne 1) { throw 'Missing Android native video dependency' }
    $original = ([uri]$package[0].rootUri).LocalPath
    if ((Get-SpyGit $original @('rev-parse','HEAD')) -cne '73771ec38176be2d984a3049c28177bce23b54a0') { throw 'Native video dependency revision changed' }
    $gradle = [IO.File]::ReadAllText((Join-Path $original 'android/build.gradle'))
    $pattern = '\["url": "(https://github\.com/My-Responsitories/libmpv-android-video-build/releases/download/[^" ]+)", "sha256": "([0-9a-f]{64})", "destination": file\("\$buildDir/([^" ]+)"\)\]'
    $matches = [regex]::Matches($gradle,$pattern)
    if ($matches.Count -ne 3) { throw 'Native library download manifest changed' }
    $reports = @()
    foreach ($match in $matches) {
        $url=$match.Groups[1].Value;$hash=$match.Groups[2].Value;$relative=$match.Groups[3].Value
        if ($relative -notmatch '^20260906/default-(arm64-v8a|armeabi-v7a|x86_64)\.jar$') { throw 'Unexpected native library destination' }
        $cached = Join-Path $Context.cache "spy/native/$relative"
        New-Item -ItemType Directory -Path (Split-Path -Parent $cached) -Force | Out-Null
        if (-not (Test-Path -LiteralPath $cached)) {
            $partial = "$cached.partial"
            $curl = if ($IsWindows) { 'curl.exe' } else { 'curl' }
            if ($IsWindows) {
                $gitRoot = Split-Path -Parent (Split-Path -Parent (Get-Command git.exe).Source)
                $gitCurl = Join-Path $gitRoot 'mingw64/bin/curl.exe'
                if (Test-Path -LiteralPath $gitCurl) { $curl = $gitCurl }
            }
            Invoke-SpyNative $curl @('--http1.1','--fail','--silent','--show-error','--location','--retry','4','--retry-all-errors','--retry-delay','2','--connect-timeout','20','--max-time','180','--output',$partial,$url)
            if ((Get-SpyHash $partial) -cne $hash) { throw 'Downloaded native library checksum mismatch' }
            Move-Item -LiteralPath $partial -Destination $cached
        }
        if ((Get-SpyHash $cached) -cne $hash) { throw 'Native library cache checksum mismatch' }
        $output = Join-Path $Context.source "build/media_kit_libs_android_video/$relative"
        New-Item -ItemType Directory -Path (Split-Path -Parent $output) -Force | Out-Null
        Copy-Item -LiteralPath $cached -Destination $output -Force
        $reports += @{file=$relative;sha256=$hash;bytes=(Get-Item -LiteralPath $cached).Length}
    }
    $reports
}

function Prepare-SpyAndroidFlutterArtifacts($Context, $Sdk) {
    $engine = Get-SpyGit $Sdk.root @('show',"$($Sdk.commit):bin/internal/engine.version")
    if ($engine -notmatch '^[0-9a-f]{40}$' -or [IO.File]::ReadAllText((Join-Path $Sdk.root 'bin/internal/engine.version')).Trim() -cne $engine) { throw 'Flutter engine revision changed' }
    $version = "1.0.0-$engine"
    $root = Join-Path $Context.cache 'spy/flutter-maven'
    $reports = @()
    $curl = Join-Path (Split-Path -Parent (Split-Path -Parent (Get-Command git.exe).Source)) 'mingw64/bin/curl.exe'
    foreach ($module in @('flutter_embedding_release','arm64_v8a_release')) {
        foreach ($extension in @('pom','jar')) {
            $relative = "io/flutter/$module/$version/$module-$version.$extension"
            $path = Join-Path $root $relative
            $stamp = "$path.verified.json"
            New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
            if (-not (Test-Path -LiteralPath $stamp)) {
                $headers = "$path.headers"
                $url = "https://storage.googleapis.com/download.flutter.io/$relative"
                Invoke-SpyNative $curl @('--http1.1','--fail','--silent','--show-error','--location','--retry','4','--retry-all-errors','--retry-delay','2','--connect-timeout','20','--max-time','180','--dump-header',$headers,'--output',$path,$url)
                $expected = [regex]::Match([IO.File]::ReadAllText($headers),'(?im)^x-goog-hash:\s*md5=([A-Za-z0-9+/=]+)\s*$').Groups[1].Value
                $actual = [Convert]::ToBase64String([Convert]::FromHexString((Get-FileHash -LiteralPath $path -Algorithm MD5).Hash))
                if (-not $expected -or $actual -cne $expected) { throw 'Official Flutter artifact transfer integrity mismatch' }
                Write-SpyJson @{url=$url;sha256=(Get-SpyHash $path);googleStorageMd5=$expected;engineCommit=$engine;file=$relative} $stamp
            }
            $record = Get-Content -LiteralPath $stamp -Raw | ConvertFrom-Json
            if ($record.engineCommit -cne $engine -or (Get-SpyHash $path) -cne $record.sha256) { throw 'Cached Flutter artifact changed' }
            $reports += $record
        }
    }
    $env:PILIPLUS_SPY_FLUTTER_MAVEN = $root
    $reports
}

function Prepare-SpyIosSource($Context, [switch]$CheckOnly) {
    $config = Get-Content -LiteralPath (Join-Path $Context.source 'tool/spy/config/flutter-ios.json') -Raw | ConvertFrom-Json
    $fixture = Join-Path $Context.cache 'spy/ios-source-reference'
    if (Test-Path -LiteralPath $fixture) {
        $cachePath = [IO.Path]::GetFullPath($Context.cache).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
        $fixturePath = (Resolve-Path -LiteralPath $fixture).Path
        if (-not $fixturePath.StartsWith($cachePath,[StringComparison]::OrdinalIgnoreCase) -or (Get-Item -LiteralPath $fixture -Force).LinkType) { throw 'Unsafe native source reference directory' }
        Remove-Item -LiteralPath $fixturePath -Recurse -Force
    }
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
                $targetPath = $Matches[1]
                if ($targetPath.Contains('..') -or $targetPath -notmatch '^(lib/.+|pubspec\.yaml)$') { throw 'Unexpected native iOS patch target' }
                [void]$targets.Add($targetPath)
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
    if (-not $CheckOnly) {
        foreach ($file in $files) { Copy-Item -LiteralPath (Join-Path $fixture $file.path) -Destination (Join-Path $Context.source $file.path) -Force }
    }
    @{patches=$config.sourcePatches;files=$files}
}
