# PiliPlus contribution policy

Current workspace override (2026-11-18): use `D:/Projects/PiliPlusAbout/PiliPlus` for upstream contributions. The stable `PiliPlus-personal-kit` and `PiliPlus-SPY` directories use `spy/dev` and `spy/main`. Reuse these directories rather than creating sibling checkouts per task. Clean downstream features may be ported upstream; exclude SPY branding, private release infrastructure and old injection markers. Version/path observations below are historical; inspect current pins and policies.

Research snapshot: 2026-07-30.

## Repository and remote contract

- Upstream repository: `bggRGjQaUbCoE/PiliPlus`
- Upstream default branch: `main`
- Other upstream branches observed: `dev`, `dom`
- Connected account permissions on upstream: read/pull only; no push
- Personal fork: `ngbyspy/PiliPlus`
- Local checkout observed: `D:\Projects\PiliPlus`
- Local checkout state observed: clean `main`, tracking `origin/main`
- Local `origin`: `https://github.com/ngbyspy/PiliPlus.git`
- Local `upstream`: missing at research time

Interpret `git branch` carefully: it lists local branches only. Use `git branch -a` to see remote-tracking branches.

## Authoritative policy files

At snapshot time, the repository had no:

- `AGENTS.md`
- `CONTRIBUTING.md`
- `CODE_OF_CONDUCT.md`
- `.github/PULL_REQUEST_TEMPLATE.md`
- `.github/pull_request_template.md`

The `.github` directory contained build workflows and issue templates. Recheck these paths before every publication because a later formal policy overrides this snapshot.

## Observed PR conventions

Every sampled PR below targeted `main`:

| PR | Result at snapshot | Title | Head branch |
| --- | --- | --- | --- |
| #2448 | merged | `fix(macos): 🐛 restore opaque window background for title bar` | `fix/macos-titlebar-opaque` |
| #2454 | merged | `fix(webview): inApp 模式下拦截非 http(s) scheme...` | `pr/webview_smallfix` |
| #2452 | merged | `feat: 弹幕字体大小/不透明度支持1%精细调节` | `feat/danmaku-1pct-step` |
| #2458 | merged | `fix: resume history from the recording account progress` | fork `main` |
| #2446 | open | `fix: auto-recover from stream corruption errors` | `debug-stream-error` |
| #2442 | closed | `feat: iOS/iPadOS 原生 HDR / 杜比视界播放支持` | `feat/hdr-ios-main` |
| #2457 | closed | `fix: 修复不透明度的浮点误差以及滑动优化` | `fix/slider-clean` |
| #2464 | open | `视屏详情页加载中给作者和视屏信息部分添加骨架屏，避免闪烁` | `pr/video-detail-loading-skeleton` |

Conclusions:

- Base new work on `upstream/main`.
- Prefer `fix:`, `feat:`, or scoped forms such as `fix(ipados):`; the convention is common but not mechanically enforced.
- Chinese and English titles and descriptions are both accepted.
- Use a descriptive feature branch even though some contributors submit from a fork's `main`.
- Recent accepted changes are small and focused when possible.
- Merged changes commonly appear on `main` as a single squash commit with the PR number appended.
- Direct maintainer commits sometimes contain `Signed-off-by`, while sampled external contributor commits do not. No DCO policy was found.

Good PR descriptions explain the problem or context, the minimal change, affected files or scope, and actual testing. UI changes should include screenshots or recordings.

## Build and test reality

`pubspec.yaml` and `.fvmrc` pin Flutter `3.44.8`.

At snapshot time, pull requests triggered:

- Android release/dev APK build
- iOS release build with `--no-codesign`
- Windows x64 packaging build

macOS and Linux jobs were not triggered for ordinary pull requests. The workflow did not provide a dedicated `flutter analyze`, unit-test, or iPadOS behavioral test job. A green build therefore does not prove that the red/yellow/green window controls no longer overlap player actions.

The checkout had no `test/` or `integration_test/` directory.

## Recommended branch for the reported issue

```text
fix/ipados-window-player-controls
```

Recommended commit and PR title:

```text
fix(ipados): avoid window controls overlapping player actions
```

## PR body template for the reported issue

```markdown
## 问题

在 iPadOS 26 及以上版本中，应用处于窗口化状态时进入视频详情页，
系统左上角的窗口控制按钮会遮挡播放器的返回按钮和首页按钮。

## 触发条件

- iPadOS 26+
- 应用处于窗口化状态
- 进入视频详情页

## 修改

- 在满足上述平台、系统版本和窗口状态时，为播放器左侧关键操作区增加安全偏移
- 保持旧版 iPadOS、非窗口化状态及其他平台的原有布局

## 测试

- [ ] iPadOS 26+ 真机，窗口化状态
- [ ] 横屏与竖屏
- [ ] 不同窗口尺寸
- [ ] 全屏/非窗口化状态无回归
- [ ] iPadOS 26 以前版本无回归
- [ ] `dart format` 通过
- [ ] `flutter analyze` 通过

## 截图或录屏

附修改前/修改后的同尺寸窗口截图或录屏。
```

Delete irrelevant unchecked items only when they are genuinely outside scope. Do not mark unperformed tests as passed.
