import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:PiliPlus/utils/android/glass_appearance.dart';

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:material_ui/material_ui.dart';

/// Includes popup routes, so the native sibling never covers Flutter dialogs.
class KyantNavigationRoutes extends NavigatorObserver {
  static final instance = KyantNavigationRoutes();
  final changes = ValueNotifier(0);
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      changes.value++;
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      changes.value++;
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      changes.value++;
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      changes.value++;
}

@immutable
class KyantDestination {
  const KyantDestination({required this.id, required this.label, this.badge});
  final String id;
  final String label;
  final String? badge;
  Map<String, Object?> toMap() => {'id': id, 'label': label, 'badge': badge};
}

class NativeKyantNavigationBar extends StatefulWidget {
  const NativeKyantNavigationBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    required this.fallback,
    required this.clarity,
    this.blur = GlassAppearance.defaultBlur,
  });
  static const channelName = 'com.ngbyspy.piliplus/kyant_navigation';
  final List<KyantDestination> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final Widget fallback;
  final double clarity;
  final double blur;
  @override
  State<NativeKyantNavigationBar> createState() =>
      _NativeKyantNavigationBarState();
}

class _NativeKyantNavigationBarState extends State<NativeKyantNavigationBar>
    with WidgetsBindingObserver {
  static int _nextOwner = 0;
  static const _channel = MethodChannel(NativeKyantNavigationBar.channelName);
  static const _frames = BasicMessageChannel<ByteData?>(
    'com.ngbyspy.piliplus/kyant_navigation/frame',
    BinaryCodec(),
  );
  final _owner = ++_nextOwner;
  final _anchor = GlobalKey();
  bool _supported = false, _failed = false, _queued = false, _visible = false;
  String? _lastConfig;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    KyantNavigationRoutes.instance.changes.addListener(_routeChanged);
    _channel.setMethodCallHandler(_handleNative);
    unawaited(_checkSupport());
  }

  Future<void> _checkSupport() async {
    try {
      final supported =
          await _channel.invokeMethod<bool>('isSupported') ?? false;
      if (mounted) setState(() => _supported = supported);
    } on PlatformException {
      // Unsupported SDKs/builds retain existing navigation.
    } on MissingPluginException {
      // Also covers software/widget-test engines.
    }
  }

  Future<void> _handleNative(MethodCall call) async {
    final args = call.arguments as Map<Object?, Object?>?;
    if (!mounted || args?['owner'] != _owner) return;
    if (call.method == 'selected' && _visible) {
      final index = widget.items.indexWhere((item) => item.id == args?['id']);
      if (index >= 0) widget.onSelected(index);
    } else if (call.method == 'failed') {
      await _hide();
      if (mounted) {
        setState(() => _failed = true);
        try {
          SmartDialog.showToast('原生玻璃暂不可用，已恢复原底栏');
        } catch (_) {
          /* Minimal test hosts may not have a dialog overlay. */
        }
      }
    }
  }

  void _routeChanged() {
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) unawaited(_hide());
    _lastConfig = null;
    _queueSync();
  }

  bool _canShow() {
    if (!_supported || _failed || !TickerMode.valuesOf(context).enabled) {
      return false;
    }
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    if (MediaQuery.highContrastOf(context) ||
        MediaQuery.disableAnimationsOf(context)) {
      return false;
    }
    return !SmartDialog.checkExist();
  }

  void _queueSync() {
    if (_queued || !mounted) return;
    _queued = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _queued = false;
      if (mounted) unawaited(_sync());
    });
  }

  Future<void> _sync() async {
    if (!_canShow()) {
      await _hide();
      return;
    }
    final box = _anchor.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) return;
    final rect = MatrixUtils.transformRect(
      box.getTransformTo(null),
      Offset.zero & box.size,
    );
    if (!rect.isFinite || rect.isEmpty) return;
    final colors = ColorScheme.of(context);
    final config = <String, Object?>{
      'owner': _owner,
      'left': rect.left,
      'top': rect.top,
      'width': rect.width,
      'height': rect.height,
      'dpr': MediaQuery.devicePixelRatioOf(context),
      'items': widget.items.map((item) => item.toMap()).toList(),
      'selected': widget.selectedIndex,
      'dark': Theme.of(context).brightness == Brightness.dark,
      'tint': colors.primary.toARGB32(),
      'foreground': colors.onSurface.toARGB32(),
      'opacity': 1 - widget.clarity.clamp(0.0, 1.0),
      'blurRadius': GlassAppearance.nativeBlurRadius(widget.blur),
      'fontScale': MediaQuery.textScalerOf(context).scale(12) / 12,
      'visible': true,
    };
    try {
      final encoded = jsonEncode(config);
      if (_lastConfig != encoded || !_visible) {
        _lastConfig = encoded;
        _visible = true;
        await _channel.invokeMethod<void>('update', config);
      } else {
        // A dirty-frame signal only; pixels stay native.
        await _frames.send(ByteData(0));
      }
    } on PlatformException {
      if (mounted) {
        await _hide();
        setState(() => _failed = true);
      }
    } on MissingPluginException {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _hide() async {
    if (!_visible) return;
    _visible = false;
    _lastConfig = null;
    try {
      await _channel.invokeMethod<void>('hide', {'owner': _owner});
    } on PlatformException {
      /* Activity may already have detached. */
    } on MissingPluginException {
      /* No native host. */
    }
  }

  @override
  void didUpdateWidget(covariant NativeKyantNavigationBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _lastConfig = null;
    _queueSync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _lastConfig = null;
    _queueSync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _lastConfig = null;
      _queueSync();
    } else {
      unawaited(_hide());
    }
  }

  @override
  void dispose() {
    KyantNavigationRoutes.instance.changes.removeListener(_routeChanged);
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_hide());
    _channel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_supported ||
        _failed ||
        MediaQuery.highContrastOf(context) ||
        MediaQuery.disableAnimationsOf(context)) {
      return widget.fallback;
    }
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(24, 14, 24, 10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: _NativeBarAnchor(
          key: _anchor,
          onScene: _queueSync,
          child: const SizedBox(width: double.infinity, height: 64),
        ),
      ),
    );
  }
}

/// Resolve after retained compositing too: ancestors can translate cached bars.
class _NativeBarAnchor extends SingleChildRenderObjectWidget {
  const _NativeBarAnchor({
    super.key,
    required this.onScene,
    required super.child,
  });
  final VoidCallback onScene;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _NativeAnchorRenderBox(onScene);
  @override
  void updateRenderObject(
    BuildContext context,
    covariant _NativeAnchorRenderBox renderObject,
  ) => renderObject.onScene = onScene;
}

class _NativeAnchorRenderBox extends RenderProxyBox {
  _NativeAnchorRenderBox(this.onScene);
  VoidCallback onScene;
  @override
  bool get alwaysNeedsCompositing => true;
  @override
  void paint(PaintingContext context, Offset offset) {
    final anchorLayer = ((layer ??= _NativeAnchorLayer()) as _NativeAnchorLayer)
      ..onScene = onScene;
    context.pushLayer(anchorLayer, super.paint, offset);
  }
}

class _NativeAnchorLayer extends OffsetLayer {
  VoidCallback? onScene;
  @override
  bool get alwaysNeedsAddToScene => true;
  @override
  void addToScene(ui.SceneBuilder builder) {
    super.addToScene(builder);
    onScene?.call();
  }
}
