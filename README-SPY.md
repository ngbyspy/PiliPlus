# PiliPlus-SPY

基于 PiliPlus 的个人发行版，包含与 B 站官方网页、客户端互通的放映厅功能。
当前功能基线已在 Android、Windows、iPad 完成人工验收。

本地发行入口为 `PiliPlusAbout/Releases/index.html`，像 GitHub Releases 一样按版本和
平台展示安装包。Windows 提供解压即用的 `windows-x64-portable.zip`；Android 提供
签名 APK；iPad / iPhone 提供待自签 IPA。某个平台稍后完成时，补充到对应版本。

发行源码：[spy/main](https://github.com/ngbyspy/PiliPlus/tree/spy/main)。
上游放映厅贡献：[Draft PR #3679](https://github.com/bggRGjQaUbCoE/PiliPlus/pull/3679)，关联 #3639。

维护采用固定的三个源码目录：

| 目录 | 分支 | 用途 |
| --- | --- | --- |
| `PiliPlusAbout/PiliPlus` | `codex/*` | 向上游提 issue / PR |
| `PiliPlusAbout/PiliPlus-personal-kit` | `spy/dev` | 开发和测试新功能 |
| `PiliPlusAbout/PiliPlus-SPY` | `spy/main` | 已验证源码及发行构建 |

版本通过 Git 提交、分支和标签保存，不再为每次改动建立平行项目。
历史工具包和早期版本保存在 `personal/main`、`archive/*` 分支及本地恢复档案中。

## 构建

PowerShell 7：

```powershell
./tool/spy/build.ps1 -Platform Windows
./tool/spy/build.ps1 -Platform Android
```

本地缓存放在 `PiliPlusAbout/.cache`。发行目录按“版本 → 平台”整理，构建报告和
校验值收在 `_metadata`，通过本地页面取用文件，无需逐个辨认报告与安装包。
Flutter 版本、框架补丁和依赖提交均固定并经过检查。首次 Android 发行通过
`tool/spy/init-signing.ps1` 创建自己的稳定签名，随后版本必须保留同一签名；密钥及其
独立备份仅保存在本机，不上传到 GitHub。

Windows、Android 构建共用生成的依赖配置，须串行执行。开发时可在 `spy/dev`
使用 `-ValidateOnly`，报告放在源码目录的 `.spy-build/validation`；发行包只允许从
干净的 `spy/main` 构建。Windows 调试配置和 iOS Debug 标识与正式版隔离。

正常构建会校验并登记安装包、更新本地发行页。指定 `-OutputRoot` 的云端或临时构建
保留原始输出，不自动登记；下载 IPA 后可用 `tool/spy/register-release.ps1`，传入
`-ReportPath` 和本地 `-ArtifactPath` 追加到同一版本。`render-releases.ps1` 可重新生成页面。

iPad 使用 `.github/workflows/spy-ipad.yml` 的 GitHub macOS 构建，生成待自签的
arm64 IPA。没有 Apple 证书也可以完成构建，安装由用户自行签名。

应用显示名为 `PiliPlus SPY`；Android / iOS 标识为 `com.ngbyspy.piliplus.spy`，
Windows 可执行文件为 `piliplus_spy.exe`。首次由旧测试版迁移时需要在 SPY 中登录，
后续 SPY 更新沿用自身数据和签名。

## 验证与范围

放映厅支持创建、加入、邀请、聊天、跟随放映员、播放/暂停/进度和换集同步，
并随可用窗口尺寸调整布局。内嵌标签、全屏侧板和聊天草稿共用跨平台实现。
源码测试与构建记录随发行产物保存；新身份的首次安装结果单独记录，避免将构建成功
等同于所有原生场景已验收。Linux 和断网恢复联机测试继续后置。

上游仓库：<https://github.com/bggRGjQaUbCoE/PiliPlus>。
本 fork 的发行不依赖上游是否接受放映厅 PR。
