# iPad / iPhone 放映厅构建

## 基线与范围

- 上游于 2026-11-18 重新 fetch，仍为 `217fb54f51f6764176319bbdedab2a7522d75401`（2.2.1）。
- 工具包仍在 `personal/main`，保持贡献目录及此前 Android / Windows 产物。
- Flutter 3.47.9，框架提交 `c197ca5199e9ee5661e865596c9c07294dfab51c`。
- Windows 本地检查使用独立 iOS SDK 源码 worktree；与已验收 SDK 的平台补丁隔离。
- iPad 与其他平台共享房间协议、邀请解析、聊天、放映员控制、跟随和原生播放器接入。
- 保持按可用窗口比例变化布局，支持窄窗标签、宽窗侧栏及全屏右侧弹出面板。
- 测试名为“PiliPlus 放映厅测试”，应用标识 `com.example.piliplus.watchroom`。
  用户自签工具可能重新指定标识；保持与正式版不同即可并存，测试版需自行登录主账号。

## 专用补丁与构建流程

配置位于 `config/watchroom-toolchain-ios.json`。
26 项 Flutter 补丁、9 项 Material 补丁及 1 项 Cupertino 补丁按上游 iOS 顺序处理。
应用侧先在独立 fixture 重现上游手势和极验登录补丁，再应用测试版标识补丁。
所有文件必须为原始内容或精确的重现输出；异常修改会中止流程。

`integration/ios/pubspec.lock` 固定 hosted 包版本、校验和及 Git 依赖提交。
仅 Material / Cupertino 使用已验证的本地补丁副本，其版本也须与锁文件一致。

GitHub workflow 为 `.github/workflows/watchroom-ios.yml`：

1. 仅在用户 fork 的 `personal/main` 上运行。
2. 获取并核对固定上游，新建 detached 生成树，不提交生成树。
3. 验证注入的幂等性、漂移拦截、遗漏模块拦截及原目录保护。
4. 应用平台补丁、固定依赖，执行分析、房间回归和 iPad 窗口/键盘测试。
5. `flutter build ios --release --no-codesign`。
6. 对 framework 进行 ad-hoc 签名并检查，打包 `Payload/Runner.app`。
7. 检查 arm64、ZIP 完整性、应用标识、iPad 支持、四方向和未强制全屏。
8. 上传 IPA 与构建/校验报告作为 Actions artifact，保留 14 天。

IPA 需要用户自签，不使用 CI 中的 Apple 身份或证书，也不发布 Release。
构建产物名称包含 run number 和 attempt，重试不会覆盖此前运行的产物。

## 本地检查

在 PowerShell 7 中运行：

```powershell
./personal-kit/scripts/new-watchroom-ios-source.ps1 `
  -RepoPath D:/Projects/PiliPlus `
  -PersonalKitWorktree D:/Projects/PiliPlus-personal-kit `
  -SourceRoot D:/Projects/PiliPlus-wr-ios `
  -BuildManifest ./personal-kit/dist/watchroom/build-manifest-ios-20261118.json `
  -BuildId watchroom-ios-20261118-01

./personal-kit/scripts/build-watchroom-ios.ps1 `
  -BuildManifest ./personal-kit/dist/watchroom/build-manifest-ios-20261118.json `
  -ValidateOnly
```

Windows 本地检查不产生原生 IPA；真正的 Xcode / CocoaPods 编译在云端执行。
云端运行和产物状态以实际 Actions 记录及构建报告为准，不用模拟测试代替实机验收。

2026-11-18 本地记录：45 项注入及重复注入通过，锚点漂移、遗漏模块及 iOS 元数据
漂移均被拦截，原贡献目录保持不变。全量 81 项房间回归通过，包含 iOS 目标平台下
1194×834、375×700、744×1133、1024×768 窗口与键盘变化的面板/草稿检查。
IPA 结构校验的 4 项合成 fixture 测试通过；定向分析无 error 或 warning，保留既有
非致命样式 info。iPad 实机验收待用户自签后进行。

首次云端发布范围预览在本地 `dist/watchroom/ios-publication-preview.json`。
仅包含放映厅实现、测试、iOS 依赖锁和构建所需的 44 个文本文件；不包括历史交接记录、
缓存导出功能、运行时账号数据、构建产物或缓存。相关代码 push 到 `personal/main`
后触发构建，文档更新本身不触发重复编译。

## 原生构建结果

2026-11-18：[Actions run 44268978087](https://github.com/ngbyspy/PiliPlus/actions/runs/44268978087)
成功，构建使用工具包提交 `d7427fcf81f4b8b80cc655473bd688c46f8f3785`，上游仍为
`217fb54f51f6764176319bbdedab2a7522d75401`，云端工具包工作区干净。

首轮在 Flutter 自动更新 macOS CocoaPods 配置时被保护检查拒绝。
修复仅接受两份 xcconfig 的准确标准 include；增加了正确配置通过和额外改动拒绝的检查。
未扩大到允许任意 macOS 文件变化。

- 云端定向分析无 error / warning，73 项非致命样式 info；81 项回归通过。
- Xcode release device build 成功，arm64；最终包最低系统版本为 iOS / iPadOS 15.0。
- 30 个 framework ad-hoc 签名和校验通过；主应用需用户自签。
- `PiliPlus-watchroom-ios-2-1-unsigned.ipa`：25,258,046 字节。
- SHA256：`a1148cca85c8699a122349304a9a2f9adfe6408bcf52866df8994b57f3e8b809`。
- 下载到 Windows 后再次检查 ZIP、应用标识、iPad 方向/窗口配置及 SHA256，均通过。
- Actions artifact `watchroom-ipad-self-signable-2-1` 包含 IPA、构建清单和结构校验报告。

原生设备上的播放、窗口交互、后台恢复及退房仍需用户自签后的人工验收。

## 自签后的人工验收

1. 登录测试版主账号。通过邀请链接加入朋友房间，检查播放和聊天。
2. 同一窗口由宽拖窄，再恢复宽窗；检查放映厅、简介、评论及当前标签，确认不退房。
3. 全屏后打开顶端放映厅按钮，弹出键盘输入草稿，收起并重开，检查输入可见及草稿保留。
4. 从支持的番剧简介就地创建放映厅，把复制的邀请交给好友；检查换集、跨季/跨剧和进度同步。
5. 侧滑离开播放页后从“我的”返回房间；短暂切后台再返回，检查恢复同步。
6. 关闭“同步我的播放操作”后明确退出，确认好友端及时移除成员。

网络断开恢复继续按用户要求暂缓。Linux 后置。
