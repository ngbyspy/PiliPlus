param(
    [Parameter(Mandatory)][string]$SourceRoot,
    [Parameter(Mandatory)][string]$BuildManifest,
    [switch]$VerifyOnly
)
. (Join-Path $PSScriptRoot 'common.ps1')
. (Join-Path $PSScriptRoot 'inject-lib.ps1')
$kitRoot = Get-CanonicalPath (Join-Path $PSScriptRoot '..')
$manifestPath = Get-CanonicalPath $BuildManifest
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$source = Assert-GeneratedWorktree -RepoPath $manifest.repoPath -SourceRoot $SourceRoot `
    -ExpectedCommit $manifest.upstreamCommit -ProtectedRoots @($manifest.contributionCheckout, $manifest.personalKitWorktree)
if ($source -ine (Get-CanonicalPath $manifest.generatedWorktree)) { throw 'SourceRoot differs from the explicit generated worktree manifest.' }
Assert-FingerprintEqual $manifest.contributionFingerprint (Get-CheckoutFingerprint $manifest.contributionCheckout)

$rules = [Collections.Generic.List[object]]::new()
function Add-Rule([string]$id, [string]$target, [string]$anchor, [string]$text, [string]$position = 'After') {
    $rules.Add([pscustomobject]@{ id=$id; target=$target; anchor=$anchor; text=$text; position=$position })
}
$import = "import 'package:PiliPlus/private/watchroom/piliplus_adapter.dart';"
foreach ($target in @('lib/pages/mine/view.dart','lib/utils/app_scheme.dart','lib/pages/video/controller.dart','lib/plugin/pl_player/controller.dart','lib/pages/video/widgets/header_control.dart','lib/pages/video/view.dart','lib/pages/video/introduction/pgc/view.dart')) {
    Add-Rule ('import-' + $target.Replace('/','-').Replace('.','-')) $target "import 'package:get/get.dart';" $import
}
Add-Rule 'mine-entry' 'lib/pages/mine/view.dart' "            icon: const Icon(Icons.settings_outlined),`n          )," @'
          WatchroomAdapter.instance.entryButton(),
'@
Add-Rule 'room-link' 'lib/utils/app_scheme.dart' '    switch (area) {' @'
      case 'watchroom':
        if (const {'www.bilibili.com', 'm.bilibili.com', 'bilibili.com'}
            .contains(uri.host)) {
          WatchroomAdapter.open(link: uri.toString());
          return true;
        }
        launchURL();
        return false;
'@
Add-Rule 'room-invite-link' 'lib/utils/app_scheme.dart' '    switch (area) {' @'
    if (const {'www.bilibili.com', 'm.bilibili.com', 'bilibili.com'}
            .contains(uri.host) &&
        uri.path == '/bangumi/theatre/invite') {
      WatchroomAdapter.open(link: uri.toString());
      return true;
    }
'@ 'Before'
Add-Rule 'app-room-link' 'lib/utils/app_scheme.dart' "          case 'pgc':" @'
            if (path == '/room') {
              WatchroomAdapter.open(link: uri.toString());
              return true;
            }
'@
Add-Rule 'force-player-init' 'lib/pages/video/controller.dart' '    if (_autoPlay.value ||' @'
        WatchroomAdapter.instance.shouldInitialize(epId) ||
'@
Add-Rule 'room-player-visible' 'lib/pages/video/controller.dart' "    epId = args['epId'];" @'
    if (WatchroomAdapter.instance.shouldInitialize(epId)) {
      _autoPlay.value = true;
    }
'@
Add-Rule 'player-initial-state' 'lib/pages/video/controller.dart' '    Duration? seek = defaultST ?? playedTime;' @'
    WatchroomAdapter.instance.suspend(heroTag);
    autoplay ??= WatchroomAdapter.instance.initialPlaying(epId);
    seek = WatchroomAdapter.instance.startPosition(epId) ?? seek;
'@
Add-Rule 'room-seek-priority' 'lib/pages/video/controller.dart' '    seek ??= getFirstSegment();' @'
    seek = WatchroomAdapter.instance.startPosition(epId) ?? seek;
'@
Add-Rule 'player-ready-state' 'lib/pages/video/controller.dart' "      rotate: _rotate,`n    );" @'
    WatchroomAdapter.instance.observeNativeState(plPlayerController);
'@
Add-Rule 'native-playing-state' 'lib/plugin/pl_player/controller.dart' "        for (final element in _statusListeners) {`n          element(playing ? .playing : .paused);`n        }" @'
        WatchroomAdapter.instance.observeNativeState(this);
'@
Add-Rule 'bind-player' 'lib/pages/video/controller.dart' '        setSubtitle(vttSubtitlesIndex.value);' @'
        WatchroomAdapter.instance.bind(
          identity: heroTag,
          episodeId: epId,
          seasonId: seasonId,
          player: plPlayerController,
        );
'@
Add-Rule 'unbind-player' 'lib/pages/video/controller.dart' "  void onClose() {`n    cid.close();" @'
    WatchroomAdapter.instance.suspend(heroTag);
'@
Add-Rule 'seek-event' 'lib/plugin/pl_player/controller.dart' "      await _videoPlayerController?.seek(position);`n      _updateIOSPip(position);" @'
      WatchroomAdapter.instance.observe(this, 'seek');
'@
Add-Rule 'play-event' 'lib/plugin/pl_player/controller.dart' "    audioSessionHandler?.setActive(true);`n`n    playerStatus = .playing;" @'
    WatchroomAdapter.instance.observe(this, 'play');
'@
Add-Rule 'pause-event' 'lib/plugin/pl_player/controller.dart' "    await _videoPlayerController?.pause();`n    playerStatus = .paused;" @'
    WatchroomAdapter.instance.observe(this, 'pause');
'@
Add-Rule 'player-room-button' 'lib/pages/video/widgets/header_control.dart' "            right: Row(`n              mainAxisSize: .min,`n              children: [" @'
                if (!isFileSource && !videoDetailCtr.isUgc)
                  WatchroomAdapter.instance.playerButton(
                    context,
                    identity: heroTag,
                    episodeId: videoDetailCtr.epId,
                    seasonId: videoDetailCtr.seasonId,
                    supported: videoDetailCtr.pgcIntroCtr.pgcItem.supportsWatchroom,
                    title: videoDetailCtr.pgcIntroCtr.pgcItem.title ?? '当前剧集',
                  ),
'@
Add-Rule 'room-pop-pause' 'lib/plugin/pl_player/controller.dart' '    if (didPop) {' @'
      WatchroomAdapter.instance.onPlayerExit(this);
'@
Add-Rule 'room-page-state' 'lib/pages/video/view.dart' '  Widget buildTabBar({' ([IO.File]::ReadAllText((Join-Path $kitRoot 'integration/common/watchroom_page_state.dart.txt')).TrimEnd()) 'Before'
Add-Rule 'room-page-attach' 'lib/pages/video/view.dart' '    introController = _initIntroCtr();' '    _attachWatchroomPage();'
Add-Rule 'room-page-detach' 'lib/pages/video/view.dart' '    Get.delete<HorizontalMemberPageController>(' '    _detachWatchroomPage();' 'Before'
Add-Rule 'room-tab-title' 'lib/pages/video/view.dart' '    final tabs = [' "      if (_showWatchroomTab) '放映厅',"
Add-Rule 'room-tab-controller' 'lib/pages/video/view.dart' '    if (videoDetailController.tabCtr.length != tabs.length) {' '    _syncWatchroomTabs(tabs);' 'Before'
Add-Rule 'room-portrait-tab' 'lib/pages/video/view.dart' '                        videoIntro(isHorizontal: false, needCtr: false),' '                        if (_showWatchroomTab) _watchroomPanel,' 'Before'
Add-Rule 'room-split-tab' 'lib/pages/video/view.dart' "                        videoIntro(`n                          width: introWidth," '                        if (_showWatchroomTab) _watchroomPanel,' 'Before'
Add-Rule 'room-vertical-tab' 'lib/pages/video/view.dart' "                          child: tabBarView(`n                            controller: videoDetailController.tabCtr,`n                            children: [" '                              if (_showWatchroomTab) _watchroomPanel,'
Add-Rule 'room-wide-tab' 'lib/pages/video/view.dart' "                        if (videoDetailController.isFileSource)`n                          localIntroPanel()" '                        if (_showWatchroomTab) _watchroomPanel,' 'Before'
Add-Rule 'room-square-tabs' 'lib/pages/video/view.dart' "                  Expanded(`n                    child: Row(`n                      crossAxisAlignment: CrossAxisAlignment.start,`n                      children: [`n                        Expanded(`n                          child: videoIntro(" @'
                  if (_showWatchroomTab)
                    Expanded(child: _watchroomSquareTabs(bottomHeight))
                  else
'@ 'Before'
Add-Rule 'pgc-room-capability-field' 'lib/models_new/pgc/pgc_info_model/result.dart' 'class PgcInfoModel {' @'
  bool? supportsWatchroom;
'@
Add-Rule 'pgc-room-capability-constructor' 'lib/models_new/pgc/pgc_info_model/result.dart' '    this.seasons,' '    this.supportsWatchroom,'
Add-Rule 'pgc-room-capability-json' 'lib/models_new/pgc/pgc_info_model/result.dart' '  factory PgcInfoModel.fromJson(Map<String, dynamic> json) => PgcInfoModel(' @'
    supportsWatchroom: switch ((json['freya'] as Map?)?['icon_show']) {
      1 || true => true,
      0 || false => false,
      _ => null,
    },
'@
Add-Rule 'pgc-create-room' 'lib/pages/video/introduction/pgc/view.dart' '          if (introController.isPgc) actionGrid(item.stat!, introController),' @'
          if (introController.isPgc)
            WatchroomAdapter.instance.creationCard(
              context,
              identity: widget.heroTag,
              episode: videoDetailCtr.epId,
              season: videoDetailCtr.seasonId,
              supported: item.supportsWatchroom,
              title: item.title ?? '当前剧集',
            ),
'@
Add-Rule 'room-input-import' 'lib/pages/video/widgets/player_focus.dart' "import 'package:material_ui/material_ui.dart';" $import
Add-Rule 'room-input-shortcuts' 'lib/pages/video/widgets/player_focus.dart' '      onKeyEvent: (node, event) {' @'
        if (WatchroomAdapter.textInputHasFocus()) return KeyEventResult.ignored;
'@
Add-Rule 'pgc-active-season' 'lib/pages/video/introduction/pgc/controller.dart' '        ..epId = epId' '        ..seasonId = seasonId'
Add-Rule 'history-adaptive-import' 'lib/pages/history/view.dart' "import 'package:get/get.dart';" "import 'package:PiliPlus/private/watchroom/history_layout.dart';"
Add-Rule 'history-adaptive-grid' 'lib/pages/history/view.dart' '  HistoryController currCtr([int? index]) {' @'
  @override
  get gridDelegate => Grid.videoCardHDelegate(mainAxisExtent: historyRowExtent(context));

'@ 'Before'
Add-Rule 'history-thumb-height' 'lib/pages/history/widgets/item.dart' '                  AspectRatio(' '                  SizedBox(height: 100, child:' 'Before'
Add-Rule 'history-thumb-height-end' 'lib/pages/history/widgets/item.dart' '                  const SizedBox(width: 10),' '                  ),' 'Before'
if ($manifest.platform -ne 'ios') {
Add-Rule 'debug-resource-feature' 'android/app/build.gradle.kts' '    buildFeatures {' '        resValues = true'
Add-Rule 'debug-app-name' 'android/app/build.gradle.kts' '            applicationIdSuffix = ".debug"' @'
            resValue("string", "app_name", "PiliPlus 放映室测试")
'@
}
if ($manifest.platform -eq 'windows') {
    Add-Rule 'windows-binary-name' 'windows/CMakeLists.txt' 'set(BINARY_NAME "piliplus")' 'set(BINARY_NAME "piliplus_watchroom")'
    Add-Rule 'windows-test-profile' 'lib/main.dart' '  appSupportDirPath = (await getApplicationSupportDirectory()).path;' @'
  if (Platform.isWindows) {
    appSupportDirPath = path.join((await getApplicationSupportDirectory()).path, 'watchroom-windows');
    return;
  }
'@ 'Before'
    Add-Rule 'windows-test-title' 'lib/main.dart' '        ..title = Constants.appName;' "      if (Platform.isWindows) window.title = 'PiliPlus 放映厅测试';"
    Add-Rule 'windows-cache-import' 'lib/utils/cache_manager.dart' "import 'dart:io' show Directory, File;" "import 'dart:io' as watchroomIo show Platform;"
    Add-Rule 'windows-test-cache' 'lib/utils/cache_manager.dart' '    return Directory(path.join(tmpDirPath, Constants.appName));' @'
    if (watchroomIo.Platform.isWindows) {
      return Directory(path.join(tmpDirPath, 'PiliPlus-watchroom-windows'));
    }
'@ 'Before'
    Add-Rule 'windows-exit-import' 'lib/utils/desktop/window_controller.dart' "import 'package:window_manager/window_manager.dart';" $import
    Add-Rule 'windows-room-exit' 'lib/utils/desktop/window_controller.dart' '  Future<void> onClose() async {' @'
    if (!await WatchroomAdapter.instance.prepareDesktopExit()) return;
'@
}

$allowed = @($rules.target | Sort-Object -Unique) + @('pubspec.lock','pubspec_overrides.yaml')
if ($manifest.platform -eq 'ios') {
    # Flutter pub get on macOS adds these CocoaPods includes, including when
    # resolving dependencies for iOS. Accept only the SDK's exact migration.
    foreach ($mode in @('Debug','Release')) {
        $relative = "macos/Flutter/Flutter-$mode.xcconfig"
        $original = (Get-GitOutput $source @('show',"$($manifest.upstreamCommit):$relative")).Replace("`r`n","`n")
        $actual = [IO.File]::ReadAllText((Join-Path $source $relative)).Replace("`r`n","`n").TrimEnd([char]"`n")
        $include = '#include? "Pods/Target Support Files/Pods-Runner/Pods-Runner.' + $mode.ToLowerInvariant() + '.xcconfig"'
        if ($actual -cne $original -and $actual -cne "$include`n$original") { throw "Unexpected Flutter CocoaPods configuration: $relative" }
        $allowed += $relative
    }
    $iosConfig = Get-Content -LiteralPath (Join-Path $kitRoot 'config/watchroom-toolchain-ios.json') -Raw | ConvertFrom-Json
    foreach ($patch in $iosConfig.applicationPatches) {
        $root = if ($patch.origin -eq 'kit') { $kitRoot } else { $source }
        $patchFile = Join-Path $root $patch.path
        if ((Get-FileHash -LiteralPath $patchFile).Hash.ToLowerInvariant() -cne $patch.sha256) { throw "iOS patch identity mismatch: $($patch.path)" }
        foreach ($line in Get-Content -LiteralPath $patchFile) {
            if ($line -match '^\+\+\+ b/(.+)$') { $allowed += $Matches[1] }
        }
    }
}
$status = Get-GitOutput $source @('status','--porcelain','--untracked-files=all')
foreach ($line in @($status -split "`n" | Where-Object { $_ })) {
    $relative = $line.Substring(3).Trim('"').Replace('\','/')
    if ($relative -notin $allowed -and -not $relative.StartsWith('lib/private/watchroom/') -and
        -not $relative.StartsWith('test/private_watchroom/')) { throw "Unexpected generated source change: $relative" }
}
# Validate every integration anchor before making any source mutation.
foreach ($rule in $rules) {
    $path = Join-Path $source $rule.target
    $text = [IO.File]::ReadAllText($path).Replace("`r`n","`n")
    $prefix = if ($rule.target.EndsWith('.yaml') -or $rule.target.EndsWith('CMakeLists.txt')) { '#' } else { '//' }
    $begin = "$prefix PILIPLUS_PRIVATE_WATCHROOM_BEGIN $($rule.id)-v1"
    $end = "$prefix PILIPLUS_PRIVATE_WATCHROOM_END $($rule.id)-v1"
    $markerCount = Assert-MarkerState $text $begin $end $rule.id
    if ($markerCount -eq 0 -and (Get-ExactMatchCount $text $rule.anchor) -ne 1) { throw "Watchroom anchor drift: $($rule.id) in $($rule.target)" }
    if ($VerifyOnly -and $markerCount -ne 1) { throw "Missing watchroom integration: $($rule.id)" }
}
$copies = @(
    @{ from='modules/watchroom'; to='lib/private/watchroom' },
    @{ from='integration/common/watchroom'; to='lib/private/watchroom' },
    @{ from='tests/watchroom'; to='test/private_watchroom' }
)
# This module is assembled from two source folders, so verify the union instead
# of treating the narrow adapter as an unexpected pre-existing core file.
$expectedFiles = @{}
foreach ($copy in $copies) {
    $from = Join-Path $kitRoot $copy.from
    foreach ($file in Get-ChildItem -LiteralPath $from -File -Recurse) {
        $relative = $file.FullName.Substring($from.Length).TrimStart([char]'\',[char]'/')
        $destination = Join-Path (Join-Path $source $copy.to) $relative
        if ($expectedFiles.ContainsKey($destination)) { throw "Duplicate private module destination: $relative" }
        $expectedFiles[$destination] = $file.FullName
    }
}
foreach ($destination in $expectedFiles.Keys) {
    if (Test-Path -LiteralPath $destination) {
        if ((Get-FileHash -LiteralPath $destination).Hash -ne (Get-FileHash -LiteralPath $expectedFiles[$destination]).Hash) { throw "Private module content differs from kit: $destination" }
    } elseif ($VerifyOnly) { throw "Missing private module: $destination" }
}
foreach ($directory in @('lib/private/watchroom','test/private_watchroom')) {
    $path = Join-Path $source $directory
    if (Test-Path -LiteralPath $path) {
        foreach ($file in Get-ChildItem -LiteralPath $path -Recurse -File) {
            if (-not $expectedFiles.ContainsKey($file.FullName)) { throw "Unexpected private file: $($file.FullName)" }
        }
    }
}
if (-not $VerifyOnly) {
    foreach ($destination in $expectedFiles.Keys) {
        if (-not (Test-Path -LiteralPath $destination)) {
            New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
            Copy-Item -LiteralPath $expectedFiles[$destination] -Destination $destination
        }
    }
    foreach ($rule in $rules) {
        $prefix = if ($rule.target.EndsWith('.yaml') -or $rule.target.EndsWith('CMakeLists.txt')) { '#' } else { '//' }
        [void](Invoke-GuardedTextInjection -TargetPath (Join-Path $source $rule.target) -RuleId $rule.id `
            -Anchor $rule.anchor -ExpectedMatches 1 -BeginMarker "$prefix PILIPLUS_PRIVATE_WATCHROOM_BEGIN $($rule.id)-v1" `
            -EndMarker "$prefix PILIPLUS_PRIVATE_WATCHROOM_END $($rule.id)-v1" -InjectedText $rule.text.TrimEnd() `
            -Position $rule.position -Diagnostic 'Reinspect the selected upstream commit; do not weaken anchor validation.')
    }
    $manifest | Add-Member -NotePropertyName watchroomIntegrationRules -NotePropertyValue @($rules | ForEach-Object {
        @{id=$_.id; version=1; target=$_.target; anchorSha256=(Get-StringSha256 $_.anchor)}
    }) -Force
    $manifest | Add-Member -NotePropertyName personalKitIdentity -NotePropertyValue (Get-KitIdentity $manifest.personalKitWorktree) -Force
    Write-JsonFile $manifest $manifestPath
}
Assert-FingerprintEqual $manifest.contributionFingerprint (Get-CheckoutFingerprint $manifest.contributionCheckout)
Write-Output "Watchroom injection verified: $($rules.Count) guarded integrations at $source"
