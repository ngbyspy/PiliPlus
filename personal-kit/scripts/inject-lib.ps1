Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ExactMatchCount {
    param([Parameter(Mandatory)][string]$Text, [Parameter(Mandatory)][string]$Needle)
    if ($Needle.Length -eq 0) { throw 'Injection needle must not be empty.' }
    $count = 0
    $offset = 0
    while (($position = $Text.IndexOf($Needle, $offset, [StringComparison]::Ordinal)) -ge 0) {
        $count++
        $offset = $position + $Needle.Length
    }
    return $count
}

function Assert-MarkerState {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$BeginMarker,
        [Parameter(Mandatory)][string]$EndMarker,
        [Parameter(Mandatory)][string]$RuleId
    )
    $beginCount = Get-ExactMatchCount $Text $BeginMarker
    $endCount = Get-ExactMatchCount $Text $EndMarker
    if ($beginCount -ne $endCount -or $beginCount -gt 1) {
        throw "Rule $RuleId has malformed partial/duplicate markers (begin=$beginCount, end=$endCount)."
    }
    return $beginCount
}

function Invoke-GuardedTextInjection {
    param(
        [Parameter(Mandatory)][string]$TargetPath,
        [Parameter(Mandatory)][string]$RuleId,
        [Parameter(Mandatory)][string]$Anchor,
        [Parameter(Mandatory)][int]$ExpectedMatches,
        [Parameter(Mandatory)][string]$BeginMarker,
        [Parameter(Mandatory)][string]$EndMarker,
        [Parameter(Mandatory)][string]$InjectedText,
        [Parameter(Mandatory)][ValidateSet('Before', 'After')][string]$Position,
        [Parameter(Mandatory)][string]$Diagnostic
    )
    if (-not (Test-Path -LiteralPath $TargetPath -PathType Leaf)) {
        throw "Rule $RuleId target is missing: $TargetPath"
    }
    $text = [IO.File]::ReadAllText($TargetPath)
    $newline = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $Anchor = $Anchor.Replace("`r`n", "`n").Replace("`n", $newline)
    $InjectedText = $InjectedText.Replace("`r`n", "`n").Replace("`n", $newline)
    $markerCount = Assert-MarkerState $text $BeginMarker $EndMarker $RuleId
    $expectedBlock = "$BeginMarker$newline$InjectedText$newline$EndMarker"
    if ($markerCount -eq 1) {
        if ((Get-ExactMatchCount $text $expectedBlock) -ne 1) {
            throw "Rule $RuleId markers exist but content differs from the exact expected injection. Refusing partial repair."
        }
        return $false
    }
    $anchorCount = Get-ExactMatchCount $text $Anchor
    if ($anchorCount -ne $ExpectedMatches) {
        throw "Rule $RuleId expected $ExpectedMatches exact anchor match(es), found $anchorCount. $Diagnostic"
    }
    $replacement = if ($Position -eq 'After') {
        "$Anchor$newline$expectedBlock"
    } else {
        "$expectedBlock$newline$Anchor"
    }
    $updated = $text.Replace($Anchor, $replacement)
    if ((Get-ExactMatchCount $updated $expectedBlock) -ne 1) {
        throw "Rule $RuleId postcondition failed: expected injection block count is not one."
    }
    [IO.File]::WriteAllText($TargetPath, $updated, [Text.UTF8Encoding]::new($false))
    return $true
}

function Copy-GuardedModuleTree {
    param(
        [Parameter(Mandatory)][string]$ModuleRoot,
        [Parameter(Mandatory)][string]$DestinationRoot
    )
    if (-not (Test-Path -LiteralPath $ModuleRoot -PathType Container)) {
        throw "Private module source is missing: $ModuleRoot"
    }
    $sourceFiles = @(Get-ChildItem -LiteralPath $ModuleRoot -Recurse -File | Where-Object { $_.Name -ne 'module-manifest.json' })
    if ($sourceFiles.Count -eq 0) { throw "Private module contains no implementation files: $ModuleRoot" }
    if (Test-Path -LiteralPath $DestinationRoot) {
        $unexpected = @(Get-ChildItem -LiteralPath $DestinationRoot -Recurse -File | Where-Object {
            $relative = $_.FullName.Substring($DestinationRoot.Length).TrimStart([char]'\', [char]'/')
            -not (Test-Path -LiteralPath (Join-Path $ModuleRoot $relative) -PathType Leaf)
        })
        if ($unexpected.Count -gt 0) {
            throw "Unexpected pre-existing private module file(s): $($unexpected.FullName -join ', ')"
        }
    }
    foreach ($source in $sourceFiles) {
        $relative = $source.FullName.Substring($ModuleRoot.Length).TrimStart([char]'\', [char]'/')
        $destination = Join-Path $DestinationRoot $relative
        $parent = Split-Path -Parent $destination
        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent | Out-Null }
        if (Test-Path -LiteralPath $destination) {
            $sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $source.FullName).Hash
            $destinationHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $destination).Hash
            if ($sourceHash -cne $destinationHash) {
                throw "Private module destination differs from kit source: $relative"
            }
        } else {
            Copy-Item -LiteralPath $source.FullName -Destination $destination
        }
    }
}
