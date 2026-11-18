# PiliPlus-SPY

基于 PiliPlus 的个人发行版，包含与 B 站官方网页、客户端互通的放映厅功能。
当前功能基线已在 Android、Windows、iPad 完成人工验收。

本地发行入口为 `PiliPlusAbout/Releases/index.html`，像 GitHub Releases 一样按版本和
平台展示安装包。Windows 提供解压即用的 `windows-x64-portable.zip`；Android 提供
APK 的正式发行目前暂缓（缺少官方签名）；iPad / iPhone 提供待自签 IPA。某个平台
稍后完成时，补充到对应版本。

## 应用身份与数据

正式版沿用原版 PiliPlus：Windows 程序为 `piliplus.exe`，公司/产品标识及数据目录
与原版相同；iOS Bundle ID 为 `com.example.piliplus`。只隔离开发测试版。
iPad 自签时需保持已安装版本的 Bundle ID 和签名配置，才能覆盖并沿用数据。

Android 覆盖安装还要求签名与官方相同。上游使用私有签名，现有自签密钥不匹配，
因此按用户决定暂缓正式 Android 包，保留官方安装与数据。自签旧隔离版留作历史测试包。

## 版本规则

| 类型 | 显示版本示例 | 内部构建号 |
| --- | --- | --- |
| 仅新增自己的功能（平行） | `2.2.1` | 沿用对应上游基线，例如 `5655` |
| 同时修复原版问题（垂直） | `2.2.1.1`、`2.2.1.5` | 同样沿用基线，不放大、不按自用提交数递增 |

当前含历史记录溢出修复，显示为 `2.2.1.1`。iOS 原生营销版本保持三段，完整修订号
在应用“关于”和本地发行页显示。后续上游的新构建号可继续被识别为更新。

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
./tool/spy/build.ps1 -Platform Android -ValidateOnly
```

本地缓存放在 `PiliPlusAbout/.cache`。发行目录按“版本 → 平台”整理，构建报告和
校验值收在 `_metadata`，通过本地页面取用文件，无需逐个辨认报告与安装包。
Flutter 版本、框架补丁和依赖提交均固定并经过检查。现有签名及独立备份保留在本机。
生成新密钥不能获得官方签名，不能因此声称可与官方 APK 相互覆盖。

Windows、Android 构建共用生成的依赖配置，须串行执行。开发时可在 `spy/dev`
使用 `-ValidateOnly`，报告放在源码目录的 `.spy-build/validation`；发行包只允许从
干净的 `spy/main` 构建。Windows 调试配置和 iOS Debug 标识与正式版隔离。

正常构建会校验并登记安装包、更新本地发行页。指定 `-OutputRoot` 的云端或临时构建
保留原始输出，不自动登记；下载 IPA 后可用 `tool/spy/register-release.ps1`，传入
`-ReportPath` 和本地 `-ArtifactPath` 追加到同一版本。`render-releases.ps1` 可重新生成页面。

iPad 使用 `.github/workflows/spy-ipad.yml` 的 GitHub macOS 构建，生成待自签的
arm64 IPA。没有 Apple 证书也可以完成构建，安装由用户自行签名。

原先错误隔离的 SPY 安装包保留在发行页历史区，正式发行使用原版应用身份。

## 验证与范围

放映厅支持创建、加入、邀请、聊天、跟随放映员、播放/暂停/进度和换集同步，
并随可用窗口尺寸调整布局。内嵌标签、全屏侧板和聊天草稿共用跨平台实现。
源码测试与构建记录随发行产物保存；覆盖安装与数据继承的验收单独记录，避免将构建成功
等同于所有原生场景已验收。Linux 和断网恢复联机测试继续后置。

上游仓库：<https://github.com/bggRGjQaUbCoE/PiliPlus>。
本 fork 的发行不依赖上游是否接受放映厅 PR。
