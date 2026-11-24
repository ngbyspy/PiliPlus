import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

@immutable
class IosGlassDestination {
  const IosGlassDestination({
    required this.id,
    required this.label,
    required this.symbol,
    required this.selectedSymbol,
    this.badge,
  });

  final String id;
  final String label;
  final String symbol;
  final String selectedSymbol;
  final String? badge;

  Map<String, Object?> toMap() => {
    'id': id,
    'label': label,
    'symbol': symbol,
    'selectedSymbol': selectedSymbol,
    'badge': badge,
  };
}

/// Hosts the system tab bar. Called only on iOS when the preference is enabled.
/// UIKit owns the glass, press/slide interaction and accessibility behavior.
class IosLiquidGlassNavigationBar extends StatefulWidget {
  const IosLiquidGlassNavigationBar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    required this.fallback,
  }) : assert(destinations.length >= 2),
       assert(selectedIndex >= 0 && selectedIndex < destinations.length);

  static const channelName = 'com.ngbyspy.piliplus/liquid_glass_navigation';
  static const viewType = '$channelName/view';

  final List<IosGlassDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final Widget fallback;

  @override
  State<IosLiquidGlassNavigationBar> createState() =>
      _IosLiquidGlassNavigationBarState();
}

class _IosLiquidGlassNavigationBarState
    extends State<IosLiquidGlassNavigationBar> {
  late final Future<bool> _supported = _checkSupport();
  MethodChannel? _channel;
  double? _nativeHeight;
  bool _failed = false;

  Future<bool> _checkSupport() async {
    try {
      return await const MethodChannel(
            IosLiquidGlassNavigationBar.channelName,
          ).invokeMethod<bool>('isSupported') ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Map<String, Object?> _configuration(BuildContext context) => {
    'items': widget.destinations.map((item) => item.toMap()).toList(),
    'selectedId': widget.destinations[widget.selectedIndex].id,
    'isDark': Theme.of(context).brightness == Brightness.dark,
    'tint': ColorScheme.of(context).primary.toARGB32(),
    'rtl': Directionality.of(context) == TextDirection.rtl,
  };

  Future<void> _sync() async {
    final channel = _channel;
    if (channel == null || !mounted || _failed) return;
    try {
      await channel.invokeMethod<void>('update', _configuration(context));
    } on PlatformException {
      if (mounted) setState(() => _failed = true);
    } on MissingPluginException {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _created(int id) {
    if (!mounted) return;
    _channel?.setMethodCallHandler(null);
    _channel = MethodChannel('${IosLiquidGlassNavigationBar.channelName}/$id')
      ..setMethodCallHandler(_onNativeCall);
    // Read current state after asynchronous view creation, rather than replaying
    // selection/badges from the frame that initiated creation.
    _sync();
  }

  Future<void> _onNativeCall(MethodCall call) async {
    if (!mounted || _failed) return;
    final arguments = call.arguments;
    if (arguments is! Map) return;
    if (call.method == 'selected') {
      final id = arguments['id'];
      final index = widget.destinations.indexWhere((item) => item.id == id);
      if (index >= 0) widget.onSelected(index);
    } else if (call.method == 'metrics') {
      final value = arguments['height'];
      if (value is num && value.isFinite && value >= 49 && value <= 180) {
        final height = value.toDouble();
        if (_nativeHeight != height) setState(() => _nativeHeight = height);
      }
    }
  }

  @override
  void didUpdateWidget(IosLiquidGlassNavigationBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    _channel = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return widget.fallback;
    return FutureBuilder<bool>(
      future: _supported,
      builder: (context, snapshot) {
        if (snapshot.data != true) return widget.fallback;
        final padding = MediaQuery.viewPaddingOf(context);
        final width = math.min(
          widget.destinations.length * 112.0,
          math.max(0.0, MediaQuery.widthOf(context) - padding.horizontal - 16),
        );
        return Padding(
          padding: EdgeInsets.only(left: padding.left, right: padding.right),
          child: SizedBox(
            width: width,
            height: _nativeHeight ?? 64 + padding.bottom,
            child: UiKitView(
              viewType: IosLiquidGlassNavigationBar.viewType,
              layoutDirection: Directionality.of(context),
              // UIKit's glass recognizers must see the full touch sequence.
              // Flutter still synchronously blocks touches covered by overlays.
              gestureBlockingPolicy:
                  UiKitViewGestureBlockingPolicy.doNotBlockGesture,
              creationParams: _configuration(context),
              creationParamsCodec: const StandardMessageCodec(),
              onPlatformViewCreated: _created,
            ),
          ),
        );
      },
    );
  }
}
