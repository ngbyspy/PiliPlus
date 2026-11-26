# Kyant AndroidLiquidGlass 接入 PiliPlus Android 可行性

核查日期：2026-11-26。下文保留移植前的源码分析。随后已按用户授权在 spy/dev 完成原生 Kyant 底栏实验并编译隔离的 Release/AOT dev APK；N01 去除仍独立保留在 spy/main，原生实验未提升正式版。

当前实现保留 Flutter SurfaceView 主渲染，通过原生兄弟 ComposeView 显示 Kyant 底栏，并按实际 Flutter 场景更新进行局部 PixelCopy；固定尺寸三缓冲、合并在途请求，避免捕获玻璃自身，像素不跨 Dart 通道、不写入磁盘。此链路不是零拷贝，真机观感、延迟和性能仍待用户实测。

安装包对应源码为 `9fb1950ead3e9e869296b53a3f7b6d0f5b8a39ac`，本地入口为 `Releases/Testing/kyant-native/index.html`。打开「设置 → 外观设置 → Kyant 原生底栏（实验）」测试，关闭后恢复原设置。Android 13+，默认关闭；开发包沿用原独立 dev 身份/签名。205 项发行回归和 4 项新增桥接测试通过，不等同于用户真机验收。

## 判断与建议

可以移植。追求接近原演示的效果时，值得先在 dev 验证原生 Compose 底栏，但关键是让它实时折射真正的 Flutter 页面，不能只放进 ComposeView 就宣称移植完成。原生方案是否更快尚无实测依据。

另一个方案是在现 Flutter 渲染链路中，对照 Kyant 源码补齐光学和合成差异。它对整页影响较小，但仍是维护移植版，不能称为直接运行 Kyant 原生实现。

## 固定的来源

- Kyant 当前默认分支是 kmp，本报告核查提交 [eb4a0ea2e17542ea28c2e71088f7dd9acf77aad5](https://github.com/Kyant0/AndroidLiquidGlass/commit/eb4a0ea2e17542ea28c2e71088f7dd9acf77aad5)。[README](https://github.com/Kyant0/AndroidLiquidGlass/blob/eb4a0ea2e17542ea28c2e71088f7dd9acf77aad5/README.md) 说明项目基于 Compose Multiplatform，库不附带现成的高层组件；LiquidBottomTabs 在示例 app，需要连同辅助组件迁移。
- [构建文件](https://github.com/Kyant0/AndroidLiquidGlass/blob/eb4a0ea2e17542ea28c2e71088f7dd9acf77aad5/backdrop/build.gradle.kts) 中的坐标为 io.github.kyant0:backdrop:2.0.1。本报告没有下载验证 Maven 产物，不能把源码坐标当作已经验证的二进制依赖。
- losewayy 当前 main 仍为 f67b4615fcd6a47d2ffde15246b8888f8383446e，与现 vendored 0.1.3 一致，没有发现一个直接升级就可解决差异的新版本。
- 两个项目都是 Apache-2.0；迁移时保留许可、来源及本地改动说明。

## 当前效果与原版的实际差异

对照 [LiquidBottomTabs.kt](https://github.com/Kyant0/AndroidLiquidGlass/blob/eb4a0ea2e17542ea28c2e71088f7dd9acf77aad5/app/src/commonMain/kotlin/com/kyant/backdrop/catalog/components/LiquidBottomTabs.kt)、[Lens.kt](https://github.com/Kyant0/AndroidLiquidGlass/blob/eb4a0ea2e17542ea28c2e71088f7dd9acf77aad5/backdrop/src/commonMain/kotlin/com/kyant/backdrop/effects/Lens.kt)、[InteractiveHighlight.kt](https://github.com/Kyant0/AndroidLiquidGlass/blob/eb4a0ea2e17542ea28c2e71088f7dd9acf77aad5/app/src/commonMain/kotlin/com/kyant/backdrop/catalog/utils/InteractiveHighlight.kt)，以及本地 third_party/flutter_liquid_glasses/lib/src/glass_segmented_control.dart。

| 项目 | Kyant 原组件 | 当前 PiliPlus Android 底栏 |
| --- | --- | --- |
| 底板模糊 | blur(8dp) | blurSigma=2；跨渲染器应实图校准，不能直接按数字推断强度比 |
| 底板法线 | lens 默认 depthEffect=false | trackParams.depthEffect=1，额外向径向偏折 |
| 按压跟随高光 | 整体提亮及随手指位置移动的光斑 | segmented control 未设置 glowAlpha/位置，默认 glowAlpha=0；其他 PressSurface 控件有此能力，但底栏未接 |
| 图标文字合成 | 普通内容 + 额外放大着色的 tabsBackdrop，通过选中透镜组合采样 | 一排内容整体缩放/按索引着色，再由顶层透镜采样，局部合成效果不同 |
| 按压过程中的色散 | 透镜幅度随 p，色散 uniform 固定为 1 | 幅度随 p，同时 chromatic=p，随按压变化的曲线不同 |
| 内外阴影 | 独立 Shadow/InnerShadow，选中块内阴影 radius=8dp*p | GlassParams 的同一组 shadow 字段控制装饰，未逐一保留原组件两套阴影配方 |
| 弹簧 | Compose Animatable/速度跟踪 | Dart 重实现，主要刚度/阻尼与按压尺寸参考原配方，但不等于逐帧完全相同 |

这些是源码差异，不能单凭参数断言每项都会让观感变差。现有黑块、外圈、颤抖和切页折射错位修复应保留，不直接用原库覆盖 vendored 文件。

## 接入的核心障碍

[LayerBackdrop.kt](https://github.com/Kyant0/AndroidLiquidGlass/blob/eb4a0ea2e17542ea28c2e71088f7dd9acf77aad5/backdrop/src/commonMain/kotlin/com/kyant/backdrop/backdrops/LayerBackdrop.kt) 重绘 Compose GraphicsLayer，并依赖 LayoutCoordinates。它不会自动获取任意窗口下方像素。[CanvasBackdrop.kt](https://github.com/Kyant0/AndroidLiquidGlass/blob/eb4a0ea2e17542ea28c2e71088f7dd9acf77aad5/backdrop/src/commonMain/kotlin/com/kyant/backdrop/backdrops/CanvasBackdrop.kt) 可接受自定义绘制，但背景源仍须我们提供。

Flutter PlatformView 可以承载 ComposeView，却不会自动把下方的 Flutter 内容变成 Compose backdrop。Flutter 默认的 SurfaceView 也不等于 Compose 可重绘的 GraphicsLayer。参见 [FlutterView](https://api.flutter.dev/javadoc/io/flutter/embedding/android/FlutterView.html) 与 [Platform Views 合成方式](https://docs.flutter.dev/platform-integration/android/platform-views)。HCPP 改善合成性能，不会自动解决背景采样。

| 路线 | 方法 | 优点 | 代价与待验证点 |
| --- | --- | --- | --- |
| 原生宿主与可重绘背景 | dev 验证 TextureView + Compose AndroidView/GraphicsLayer，再使用原生 LiquidBottomTabs | 有机会保留原版材质/交互且避免逐帧截图 | 此组合目前只是设计，未跑通；需检查整页性能、插件视图、音频生命周期、键盘和无障碍 |
| 局部 PixelCopy 输入 | 只复制底栏附近的 Flutter Surface 区域，复用缓冲，作为 CanvasBackdrop 输入 | 保留 Flutter 主渲染路径，适合短小的可行性验证 | 存在拷贝、缓冲和同步延迟；若源包含玻璃自身会产生反馈叠影；不能把低频截图当实时玻璃 |
| Flutter 内重建原版合成 | 补齐原高光、复合文字层、独立阴影及法线配方 | 沿用单渲染链路和真实 Flutter 背景，侵入较小 | 继续维护移植版，需在实际 GPU 上校准视觉与成本 |

[PixelCopy](https://developer.android.com/reference/android/view/PixelCopy) 将 Surface 区域拷贝到 Bitmap，不是零拷贝接口。[toImage](https://api.flutter.dev/flutter/rendering/RenderRepaintBoundary/toImage.html) 用于生成图像；逐帧 toImage → 编码 → MethodChannel → Bitmap 不作为高效正式实现。

## 系统与工程边界

- Kyant 库 minSdk=21，但 [Platform.kt](https://github.com/Kyant0/AndroidLiquidGlass/blob/eb4a0ea2e17542ea28c2e71088f7dd9acf77aad5/backdrop/src/androidMain/kotlin/com/kyant/backdrop/Platform.kt) 仅在 API 33+ 开启 RuntimeShader/真正透镜，RenderEffect 在 API 31+。低版本保留回退，不把“可安装”混为“完整折射可用”。
- 原项目 AGP 9.3.2、Kotlin 2.4.10、Compose 1.12.0、shapes 1.2.1；PiliPlus 目前 AGP 9.1.0、Kotlin 2.4.0、Flutter 3.47.9、compileSdk 37。需核对依赖/Compose 插件兼容，不能整套覆盖现有 Gradle 工程或全局 SDK。
- 保持 AudioServiceActivity、现有 FlutterEngine 和后台音频连接。原生宿主不是仅加一个控件，生命周期回归必须计入。
- Dart/Kotlin 交换栏目 ID/顺序、选中项、角标、主题/通透度、布局和选择事件；弹簧和按压高光在原生侧处理，不靠 MethodChannel 每帧控制。
- 保留 N02、线性部分收起、重复选择刷新和栏目排序/隐藏；不改 iOS/iPadOS 的已验收实现。
- 验证原生层与 Flutter 弹窗/键盘/全屏的遮挡、按压越界裁剪、半收起命中、安全区、旋转分屏和无障碍。

## dev 原型的验收顺序

2026-11-26 更新：用户已验收原生底栏，授权合入正式源码并直接构建 Android
正式包。原生库仍为 Backdrop 2.0.1，保留 Flutter SurfaceView 实时局部背景。
Release 混淆后的画面查找采用 FlutterSurfaceView 类型判断，避免依赖类名。
新增独立模糊滑杆：0% 跳过背景模糊，50% 保持原生 8dp / Flutter 2 sigma，
100% 分别为 16dp / 4 sigma；通透度仍独立控制底色。下列步骤保留为原型验证记录，
此前“仅 dev、未提升正式版”的结论由本次用户验收与正式提升取代。

1. 固定源提交，先证明底栏能连续折射真实 Flutter 封面/文字。独立 Compose 演示只能证明原库效果，不算接入完成。
2. 同页、同缓存条件下先测背景输入/合成成本，再加完整材质；不预设“原生一定更快”。
3. 可行后再仅在 spy/dev 接入可切换实验，保留现实现回退。若背景链路不达标，考虑 Flutter 内移植原配方。
4. 有对应构建/设备授权后，再提供隔离 Release 手感包；Profile 仅为具体采样准备。Raster P95 不等于 GPU 时间、掉帧率或功耗。
5. 用户验收后才讨论正式提升；本次 N01 的正式提交不包含 Kyant 原型或依赖。

