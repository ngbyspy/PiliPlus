# Kyant Bottom Tabs：原版、r12 与源码修正的变换链

2026-11-27。只做源码调查、Git 比较和源码修改；没有编译、Flutter 测试、打包、设备/ADB 或 Actions 操作。本次修正在 `spy/dev`；`spy/main` 保持 `c40f39e569651e309b9071facd28a64672786d8e`。最新 APK 仍为 r12、565511，不含本次修改。

## 结论与证据等级

**源码确定的事实：** 当前底栏是原生 Compose；Flutter 提供页面背景。原版和 r12 在进入移动按钮的透镜前，已使用不同的材质图像、裁剪几何和按压阶段。r12 不是原版组件的完整照抄。

**源码支持的因果解释：** 原版按钮取样独立的56dp隐藏材质，其自身透镜随按压变化；r12取样已经按压放大的64dp可见底栏，失去了该隐藏透镜阶段。消费者逆变换抵消的是自身仿射缩放，不会把源图中的64dp胶囊、已画入的按压变换、裁剪及滤镜还原成原版隐藏材质。因此不同的源轮廓进入相同的按钮透镜，改变内部轮廓的位置和可见范围。这支持修正取样来源与材质阶段，不支持另加56/78补偿。

**尚待真实渲染核实：** 各差异对用户所见放大的贡献；修正后的二维轮廓、色散、透明边缘及动画是否达到用户期望；与iPad的主观相似度。本次没有原生渲染/用户验收证据，不能宣布问题已解决。

此前“隐藏Row高56dp，所以原版取样内容不随按压放大/变化”的推断不成立。原版图标本身从1放大到1.2；隐藏透镜和按钮透镜也随按压改变映射。固定布局高度不能推出最终成像大小。已撤回的56/78补偿从未编译、从未真机验收，其视觉结果未知，不是已被真机证明失败的方案。

## 原版与实际依赖核对

- [kmp组件及同目录LiquidBottomTab](https://github.com/Kyant0/AndroidLiquidGlass/blob/eb4a0ea2e17542ea28c2e71088f7dd9acf77aad5/app/src/commonMain/kotlin/com/kyant/backdrop/catalog/components/LiquidBottomTabs.kt)
- [android组件](https://github.com/Kyant0/AndroidLiquidGlass/blob/896a94a3ade1cc1a940b92365f942a34971fecda/catalog/src/main/java/com/kyant/backdrop/catalog/components/LiquidBottomTabs.kt)
- 两文件blob均为 `21067726b258c7fb1a3b29463c38f1df1c3439ee`；本次通过固定提交的GitHub tree/文件重新取得并核对。
- [DampedDragAnimation](https://github.com/Kyant0/AndroidLiquidGlass/blob/eb4a0ea2e17542ea28c2e71088f7dd9acf77aad5/app/src/commonMain/kotlin/com/kyant/backdrop/catalog/utils/DampedDragAnimation.kt) 和 [InteractiveHighlight](https://github.com/Kyant0/AndroidLiquidGlass/blob/eb4a0ea2e17542ea28c2e71088f7dd9acf77aad5/app/src/commonMain/kotlin/com/kyant/backdrop/catalog/utils/InteractiveHighlight.kt) 已全文阅读；保留取消手势、重选等现有接入修改，未改弹簧参数。
- 实际依赖仍为 `backdrop:2.0.1`、`shapes:1.2.1`。重新取得Maven的 `backdrop-android-2.0.1-sources.jar`，SHA256为 `23a987f64d7de69cc1f6751da96712030bc4bc488a5f48d8244935264b0ec5d6`。所追踪的DrawBackdrop、LayerBackdrop、CombinedBackdrop、InverseLayerScope、effects、Android RenderEffect链与固定kmp提交对应实现一致。
- Maven shader与kmp不完全相同：Maven用 `radiusAt(coord,...)`，kmp用 `radiusAt(centeredCoord,...)`。shapes 1.2.1的 `Capsule.corners()` 给四角相同的 `min(width,height)/2`，故这里三个Capsule透镜不会因选择不同象限而得到不同半径。不能将此差异当成本问题根因，也未修改shader。
- android分支的逆变换、定位逻辑与kmp相同；DrawBackdrop/Lens主要为包名、Android API和平台封装差异。android shader的圆角选择方式同Maven，不改变上述Capsule判断。

本地材料在 `D:/Projects/PiliPlusAbout/.state/kyant-transform-chain-20261127/`：固定提交源文件、Maven源码、来源清单、历史diff、本次前后diff、静态核对结果。旧研究只作历史，不作光学定律。

## 原版背景入口检查

[BottomTabsContent](https://github.com/Kyant0/AndroidLiquidGlass/blob/eb4a0ea2e17542ea28c2e71088f7dd9acf77aad5/app/src/commonMain/kotlin/com/kyant/backdrop/catalog/destinations/BottomTabsContent.kt) 把同一个backdrop传给三/四标签示例。Android的 [BackdropDemoScaffold](https://github.com/Kyant0/AndroidLiquidGlass/blob/eb4a0ea2e17542ea28c2e71088f7dd9acf77aad5/app/src/androidMain/kotlin/com/kyant/backdrop/catalog/BackdropDemoScaffold.kt) 把壁纸/选取图片以ContentScale.Crop绘到全屏Image，再由layerBackdrop捕获。Crop用于壁纸适配，与按压无关。

SPY将背景入口换成Flutter SurfaceView的实时图像；组件、光学与shader仍由Compose/Android绘制。背景内容和刷新时序可影响观感，但不能据此称为Flutter仿制，更不能跳过已发生的原生材质改写。

## 捕获、布局坐标与绘制坐标检查

[LayerBackdropModifier](https://github.com/Kyant0/AndroidLiquidGlass/blob/eb4a0ea2e17542ea28c2e71088f7dd9acf77aad5/backdrop/src/commonMain/kotlin/com/kyant/backdrop/backdrops/LayerBackdropModifier.kt) 先drawContent，再recordLayer，默认onDraw再次画下游内容。它记录该modifier下游完整绘制，不限于图标，也不是整个屏幕截图。

原版隐藏Row顺序为 `alpha(0) → layerBackdrop → translation → drawBackdrop → InteractiveHighlight → 56dp/全宽/水平4dp padding → 图标颜色层`。因此屏幕不直接显示隐藏Row，记录层不含外侧零透明度，却含下游平移、材质、裁剪、高光、图标。alpha(0)不等于导出图像全透明。

BoxWithConstraints的CenterStart使64dp可见Row、56dp隐藏Row及移动Box竖直居中。忽略取整时，隐藏材质上沿相对可见材质内移4dp，两者同宽。移动Box另有水平4dp padding和标签索引平移。实际像素取整、LTR/RTL及全局位置由LayoutCoordinates参与计算。

可见底栏绘制缩放 `s_b=1+p*16dp/W`，绕可见底栏中心，布局仍64dp。隐藏材质没有这个layerBlock，但有 `lens(24p,24p)`；隐藏图标另有 `g=1+0.2p`。按钮布局仍56dp，绘制缩放来自独立的scaleX/scaleY动画，静止全按住时目标为78/56，速度还会引入非等比形变。

p、scaleX/scaleY、交互高光不是一条线性动画：按压进度弹簧(1,1000)，X/Y缩放分别(0.6,250)/(0.7,250)，交互高光(0.5,300)。中间帧时序与缩放过冲不同，不能由p=0.5推算缩放走完一半。原版和当前均如此。

## scale与inverseTransform检查

[DrawBackdropModifier](https://github.com/Kyant0/AndroidLiquidGlass/blob/eb4a0ea2e17542ea28c2e71088f7dd9acf77aad5/backdrop/src/commonMain/kotlin/com/kyant/backdrop/DrawBackdropModifier.kt#L80) 将layerBlock同时用于外部graphicsLayer与背景绘制调用。[LayerBackdrop](https://github.com/Kyant0/AndroidLiquidGlass/blob/eb4a0ea2e17542ea28c2e71088f7dd9acf77aad5/backdrop/src/commonMain/kotlin/com/kyant/backdrop/backdrops/LayerBackdrop.kt#L46) 先应用消费者layerBlock的逆变换，再用sourceCoordinates.localPositionOf(targetCoordinates)定位目标原点并平移其负值，最后画源层。

[InverseLayerScope](https://github.com/Kyant0/AndroidLiquidGlass/blob/eb4a0ea2e17542ea28c2e71088f7dd9acf77aad5/backdrop/src/commonMain/kotlin/com/kyant/backdrop/internal/InverseLayerScope.kt#L51) 在这里执行 `scale(1/scaleX,1/scaleY,Offset.Zero)`，不是再绕按钮中心缩小源胶囊。中心pivot导致的目标原点位移已进入坐标定位。当前layerBlock没有旋转/透视；不能推广为任意三维变换的完整逆矩阵。

令源层已绘图像为F、源原点a、消费者绘制后原点t、实际轴向缩放矩阵S。消费者局部点u的屏幕位置为 `q=t+S*u`。源图在背景缓冲中的取样位置为 `S*u+(t-a)`；无透镜时最终为 `F(q-a)`。所以按钮外形放大不会机械地把整个背景放大同样倍数。

加入按钮二维透镜映射L_p后：

```text
F(t + S * L_p(S^-1 * (q-t)) - a)
```

F已含源材质绘制、源clip和源图标变换。逆变换不取消F内部已经画入的可见底栏缩放或源透镜。r12的F=页面+可见64dp材质，原版的F=页面+隐藏56dp材质/图标；不能只比较外层S或lens数字。

库在localPositionOf抛异常时退到窗口原点相减，并有外部变换TODO。源码没有证明当前设备走该分支，本轮不将其认定为根因或另加位置补偿。

## clip、alpha、滤镜与图标顺序检查

DrawBackdrop先记录背景，RenderEffect按调用顺序组成 `vibrancy → blur → lens`；Android的createChainEffect(other,previous)让后加lens读取前面的滤镜输出。blur增加工作区padding；lens按折射高度扣减非负padding，给shader设置offset=-padding。这不是修改布局高度或缩放。

onDrawSurface在背景滤镜之后画底色，再画内容/图标。内部LayoutModifier用placeWithLayer(clip=true,shape=Capsule,Offscreen)裁剪下游交互光和内容。阴影在背景/内容之前，高光在内容之后，内阴影最后叠加；这些装饰不改背景坐标。消费者外层graphicsLayer再缩放整套绘制。

InteractiveHighlight在drawContent之前画白色Plus矩形光与径向光，并有独立动画。原版有材质形状裁剪；r9删除隐藏drawBackdrop后留下矩形光，曾产生未受该形状限制的额外内容。该旧问题不是r12当前放大的已证实原因。

原版隐藏Row的accent颜色层只覆盖内层图标，不染材质。LiquidBottomTab自身还有clip和g缩放。基础blur不模糊图标；最终按钮lens仍会对清晰图标折射/色散。

[Lens](https://github.com/Kyant0/AndroidLiquidGlass/blob/eb4a0ea2e17542ea28c2e71088f7dd9acf77aad5/backdrop/src/commonMain/kotlin/com/kyant/backdrop/effects/Lens.kt#L45) 给AGSL传负的refractionAmount。实际 [shader](https://github.com/Kyant0/AndroidLiquidGlass/blob/eb4a0ea2e17542ea28c2e71088f7dd9acf77aad5/backdrop/src/commonMain/kotlin/com/kyant/backdrop/internal/Shaders.kt) 根据二维圆角SDF、边缘深度、法线计算coord+d*grad；深处直接取原坐标。色散版在其两侧取七组样本再合成颜色/alpha。负取样位移不等于最终轮廓缩小。最终轮廓由源mask、非线性映射、目标clip和S共同决定，边缘可有折叠/混色。

## 按压开始、中间、完全按住检查

开始指刚按下且动画未推进的极限；完全按住指静止且弹簧收敛。拖动另计速度与平移。

| 阶段 | 原版可见材质 | 原版隐藏材质/图标 | 按钮及取样 | r12的不同 |
| --- | --- | --- | --- | --- |
| 开始p≈0 | 64dp，s_b≈1，基础blur、固定lens24/24、底色 | 56dp，基础blur，隐藏lens≈0，高光≈0，g≈1 | 外形≈56dp、按钮lens≈0，页面+隐藏材质/图标，原版0.1按钮底色 | 从开始已用64dp/固定lens24源；额外按钮blur/tint最强 |
| 中间0<p<1 | 64dp绘制按s_b放大，基础lens不变 | 布局56dp；lens24p/24p、独立交互光、g变化 | Sx/Sy独立动画；lens10p/14p+色散，逆变换/定位跟随实际S | 源轮廓含s_b，源lens恒24/24，缺少56dp渐变透镜阶段；追加滤镜淡出 |
| 完全按住p≈1 | 64dp，s_b≈1+16dp/W | 56dp独立材质，lens24/24，g≈1.2 | 外形高度目标78dp；lens10/14；逆变换仍工作 | 追加滤镜虽为0，仍是64dp可见源+按钮lens，不会自动变回原版56dp源+按钮lens |

全按住时，隐藏源的基础直边位于中心上下约28dp，可见源约32dp*s_b；曲率、clip和光边亦不同。这是进入按钮二维映射之前的差异，不是最终轮廓高度的计算结果。轮廓出现的位置要求L_p映射点落在源mask边界；更外侧的mask会令部分按钮边缘持续取到材质内部，改变内部轮廓是否出现及位置。这支持用户所见“外圈撑大”的解释，但不证明完整二维画面必然匹配原版。

## Flutter PixelCopy到Compose Canvas检查

Flutter桥接用getTransformTo(null)获得含滚动/祖先位移的逻辑矩形，原生乘dpr得到物理几何；该值不随原生按压动画变化。

capture的源rect与目标Bitmap宽高相同，没有因目标尺寸而重采样。背景Canvas用无dstSize参数的drawImage(bitmap)在(0,0)按位图像素绘制，没有绘图scale。Canvas与overlay均占crop的物理尺寸；crop原点、surface/window位置差及barX/barY负责平移。

LocalDensity=c.height/64把64dp组件适配为实际底栏像素高度；它改变组件dp几何，不会给drawImage再乘dpr。按压不改变capture rect/dpr，也不驱动Flutter捕获循环。未发现随按压放大/缩小页面背景位图的源码路径。

floor/ceil/round取整、surface实际尺寸/定位及PixelCopy时延仍有运行时影响；本轮没有量化它们，也未做真机1:1像素校准。不能用这些未知量替代Git已经证明的材质来源变化。

## Git差异：从哪里开始不同

| 比较 | 确定的变化 | 含义 |
| --- | --- | --- |
| 原版→r8 d811063d8 | 背景/业务/主题适配、可调基础材质；隐藏完整drawBackdrop仍在 | 已有接入改动，仍保留独立隐藏材质及两级透镜角色 |
| r8→r9 d36f252fc | 删除隐藏完整drawBackdrop，增加可见材质内部导出与PressBackdrop | 首次删除关键56dp/lens24p阶段；曾按压转向原始页面 |
| r9→r10 978fe6542 | 新增另一64dp材质胶囊和导出、按钮blur/tint；删除PressBackdrop | 基础来源仍非原版隐藏材质，增加源几何/边界 |
| r10→r11 1681abe18 | 导出clip、独立底色选择 | 未恢复隐藏阶段，也非显示外层变换的完整捕获 |
| r11→r12 9c6216743 | 捕获实际可见64dp变换/裁剪/光边；图标分离、页面合成+ButtonBackdrop | 用户确认多轮廓消失，但按钮改采可见底栏，隐藏渐变透镜仍缺失 |
| r12→本次 | 可见Row恢复原形态；捕获移到独立隐藏56dp，恢复lens24p/24p及光边 | 修正源几何/材质阶段偏差，不加经验缩放、不改shader符号 |

复查命令：`git diff d811063d8 d36f252fc -- android/app/src/main/kotlin/com/kyant/backdrop/catalog/components/LiquidBottomTabs.kt`；其余相邻版本同理。本地保存原版→r12、r12→修正、原版→修正完整diff。仍用Compose或保留lens数字，不等于未经改写的原版。

## 最小源码修正与四项设置保留检查

1. 可见64dp回到完整Row：基础材质、裁剪、交互光与图标共同经过原版可见底栏变换；不再作为按钮源捕获。
2. 隐藏材质恢复56dp、同一基础blur/底色、lens24p/24p、高光/阴影/交互光。alpha0在捕获之外，平移在内，不套可见底栏缩放。
3. 为使追加blur/tint不模糊或染色图标，把原版隐藏Row的材质与glyph分开捕获。glyph保留同位置/尺寸/平移、原版自身1→1.2动画和全宽56dp Capsule clip，不含矩形交互光。两者在按钮透镜前合成。
4. ButtonBackdrop保持 `页面+隐藏材质 → 追加blur → 追加底色 → 清晰glyph → 原版按钮lens/色散`。其矩形工作缓冲仅为blur padding，不增加胶囊或几何缩放。alpha/tint是颜色层，不是背景切换。

| 设置 | 修正后的接入位置 | 按住时 |
| --- | --- | --- |
| 底栏通透、自动/白/黑底色 | 可见64dp及隐藏56dp基础材质，共用已保存参数 | 保留基础底色 |
| 底栏模糊0..16dp | 两份基础材质的blur阶段 | 保留基础blur；0仅关该blur |
| 按钮通透、自动/白/黑底色 | ButtonBackdrop追加底色 | alpha乘clamp(1-p,0,1) |
| 按钮追加模糊0..32dp | 已完成隐藏基础材质后、glyph前 | 半径乘同一权重；全按住跳过追加滤镜 |

preference key、默认值、保存值、设置页及桥接映射不变。全按住没有切为仅页面的分支，基础材质仍在。按原版设计，隐藏胶囊之外由页面填充后再折射；不等于整块底栏切成原始页面。

这是有设置扩展的原版材质阶段恢复，不能称逐字照抄或像素等价：分离捕获后glyph与隐藏材质光边的覆盖顺序有区别；非零追加blur/tint为原版所无；原版按钮在透镜后画0.1淡出底色及按住3%黑膜，当前保留用户要求的透镜前底色并按压归零，没有恢复3%黑膜。阴影/文字边缘合成仍需真实渲染对照。

未改NativeKyantNavigation、Flutter桥接/设置/生命周期/滚动同步，保留R8-safe类型查找和最近任务恢复；未改iOS/Windows、版本、构建配置；N01/N02及停止/放弃功能未恢复。未向正式分支提升未验收实现；未push，避免任何CI触发。

## 验证范围与仍缺的证据

已核对固定原版文件/blob、实际Maven源码、完整变换/滤镜调用、历史diff、修改diff、git diff --check和源码静态边界。这只证明源码阶段恢复与约束保留，不证明Kotlin可编译或画面已修复。没有运行Flutter/Gradle/Kotlin编译或测试。

以后获准构建后，仍需同背景/主题/尺寸/设置下对比原版、r12、修正版本的按压开始/过渡/全按住帧，覆盖直边、圆角、色散、拖动形变和材质极值。先用按钮追加blur=0、底色alpha=0隔离基础光学，再检查四项设置及生命周期/滚动回归。目前缺少这组原生渲染证据，也缺少与iPad等价的证据。

此前12组一维检查仅验证已撤回模型；r12的216项Flutter回归是旧版非光学证据。均不计为本次修复通过。最新可安装包仍是r12，SHA256 `51dff7a6e80279d3d23bc999b24cb5481208b2cf2fdcd8b784938b36395c8198`。
