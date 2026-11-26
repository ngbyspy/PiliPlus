# Kyant Bottom Tabs 原版绘制复核

复核日期：2026 年 11 月 27 日。此次只研究源码、撤回未经原版验证的取样缩小补偿，不编译、不打包，也不把源码推导当作原生观感通过。

## 原版来源

仓库默认分支为 `kmp`，另有 `android` 分支。两分支当前 Bottom Tabs 文件的 Git blob **完全相同**：`21067726b258c7fb1a3b29463c38f1df1c3439ee`。本次问题不能归因于选用了不同的 Bottom Tabs 实现。

- [KMP 原版组件](https://github.com/Kyant0/AndroidLiquidGlass/blob/eb4a0ea2e17542ea28c2e71088f7dd9acf77aad5/app/src/commonMain/kotlin/com/kyant/backdrop/catalog/components/LiquidBottomTabs.kt)
- [Android 原版组件](https://github.com/Kyant0/AndroidLiquidGlass/blob/896a94a3ade1cc1a940b92365f942a34971fecda/catalog/src/main/java/com/kyant/backdrop/catalog/components/LiquidBottomTabs.kt)
- [官方演示接入](https://github.com/Kyant0/AndroidLiquidGlass/blob/896a94a3ade1cc1a940b92365f942a34971fecda/catalog/src/main/java/com/kyant/backdrop/catalog/destinations/BottomTabsContent.kt)

## 三层各自负责什么

这三层是绘制结构，不代表屏幕上应出现三个底栏轮廓。第二层只录制供按钮取样，并不直接显示。

| 层 | 原版尺寸与变换 | 背景与材质 | 输出 |
| --- | --- | --- | --- |
| 可见底栏 Row | 高 64dp，内边距 4dp；按压时整体按 `1 + 16dp / width` 稍微放大 | 页面背景 → vibrancy → blur 8dp → lens 24/24；再加固定 0.4 底色、交互高光、普通图标 | 直接显示；原版没有导出它给按钮取样 |
| 隐藏材质 Row | 高 56dp，`alpha(0)`；只平移，不套上可见底栏的整体按压缩放；内部图标随按压从 1 放大到 1.2 | 同一页面背景 → vibrancy → blur 8dp → lens `24p/24p`；自有胶囊裁剪、高光、同一 0.4 底色、选中颜色图标 | `layerBackdrop(tabsBackdrop)` 录制完整的已绘制材质与图标，不是仅录制图标 |
| 移动按钮 Box | 原高 56dp；按压缩放 `78/56`，并受速度影响产生形变 | `rememberCombinedBackdrop(页面, tabsBackdrop)` → lens `10p/14p` 与色散；再有按钮高光、阴影、内阴影 | 仅在当前按钮形状内显示合成内容 |

这里 `p` 是按压进度。可见底栏的 lens 24/24 恒定，隐藏副本的 lens 从 0 渐变到 24/24，按钮再使用自己的 10/14 lens；这几个阶段不能因为名字相同而合并或删除。

原版按钮表面还叠加浅/深主题对应的 0.1 底色，随按压消退，并在按压时保留 0.03 的黑色薄层。它没有独立的按钮模糊、按钮底色偏好设置。

## 坐标与透镜

- [LayerBackdrop](https://github.com/Kyant0/AndroidLiquidGlass/blob/eb4a0ea2e17542ea28c2e71088f7dd9acf77aad5/backdrop/src/commonMain/kotlin/com/kyant/backdrop/backdrops/LayerBackdrop.kt#L53) 会先应用 `layerBlock` 的逆变换，再按布局坐标定位源图。
- [InverseLayerScope](https://github.com/Kyant0/AndroidLiquidGlass/blob/eb4a0ea2e17542ea28c2e71088f7dd9acf77aad5/backdrop/src/commonMain/kotlin/com/kyant/backdrop/internal/InverseLayerScope.kt) 已处理缩放的倒数。`78/56` 是按钮外形的按压动画参数，不能据此推出还应在材质上施加一次 `56/78`。
- [Lens](https://github.com/Kyant0/AndroidLiquidGlass/blob/eb4a0ea2e17542ea28c2e71088f7dd9acf77aad5/backdrop/src/commonMain/kotlin/com/kyant/backdrop/effects/Lens.kt#L48) 给 shader 传入负的折射量；[shader](https://github.com/Kyant0/AndroidLiquidGlass/blob/eb4a0ea2e17542ea28c2e71088f7dd9acf77aad5/backdrop/src/commonMain/kotlin/com/kyant/backdrop/internal/Shaders.kt) 根据圆角 SDF、边缘深度、法线与色散映射像素。整体观感取决于完整的材质副本、裁剪和嵌套滤镜，不能从一条中心截面就宣称匹配原版。

所以，按钮中看起来像“小底栏”的内容，来自专门绘制的 56dp 材质副本。原版并不是捕获屏幕上按压后已经放大的 64dp 底栏，再把截图等比缩小。

## SPY 在哪里偏离了原版

| 改动 | 原版 | SPY r12 |
| --- | --- | --- |
| 按钮的材质来源 | 独立绘制的 56dp 隐藏副本 | 捕获实际 64dp 可见底栏，包含其按压放大和高光 |
| 隐藏 Row | 有自己的完整 `drawBackdrop`、胶囊裁剪、渐变 lens 与图标 | 变成仅图标层，删除了该材质绘制阶段 |
| 额外按钮材质 | 原版没有独立模糊设置 | 自建 `ButtonBackdrop`，对页面与捕获底栏做额外模糊/底色后，再合成图标 |
| 原版光学结构 | 三个不同职责的原生绘制阶段 | 即使保留了 lens 的数字，也已改变阶段、形状、变换和取样内容 |

r10/r11 中图标层残留的矩形交互高光、额外胶囊与导出裁剪问题属于移植改写引入的问题。r12 消除了用户观察到的多个轮廓，但仍没有恢复原版隐藏材质层，不能称为“原版效果只改了几个参数”。

此前追加的 `56/78` 补偿没有原版依据，已经从开发和正式分支撤回。此前 12 组数值检查只说明所设模型的中心轮廓会缩小，不能验证原版三层绘制，更不能证明真实画面已经恢复；该验证结论不作为原生修复通过依据。

## 后续改动应遵守的边界

应先恢复原版的可见 Row、完整隐藏材质 Row、移动 Box 的顺序及变换，使用原版的组合背景。删除替代原版隐藏材质阶段的捕获/额外工作缓冲，而不是继续添加补偿比例、翻转 shader 符号或修改阴影掩盖轮廓。

现有四项材质与底色设置是用户已经要求的能力，不能静默删除。恢复原版结构时，必须逐项说明它们接入哪个已有阶段：可见底栏和隐藏副本共有的基础材质、按钮自身的追加模糊/底色、以及不受追加材质影响的图标。尤其原版的 3% 黑色薄层与“按钮完全清透”的要求，以及原版按钮末端底色对图标的影响，需要明确处理，不能假称原版天然支持四项独立设置。

本轮没有实施这次结构重建。当前运行代码已回到 r12 源码基线，已知的按压轮廓放大仍未解决；原版恢复也尚无编译或真机验证。已交付 r12 APK、版本号、签名与安装编号均未改变。
