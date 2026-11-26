import 'package:PiliPlus/utils/android/glass_appearance.dart';
import 'package:flutter_liquid_glasses/flutter_liquid_glasses.dart';
import 'package:material_ui/material_ui.dart';

class GlassClaritySetting extends StatefulWidget {
  const GlassClaritySetting({
    super.key,
    required this.value,
    required this.onChanged,
    required this.onSaved,
    this.blurValue = GlassAppearance.defaultBlur,
    this.onBlurChanged,
    this.onBlurSaved,
    this.isButton = false,
    this.tint = GlassTint.automatic,
    this.onTintChanged,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onSaved;
  final double blurValue;
  final ValueChanged<double>? onBlurChanged;
  final ValueChanged<double>? onBlurSaved;
  final bool isButton;
  final GlassTint tint;
  final ValueChanged<GlassTint>? onTintChanged;

  @override
  State<GlassClaritySetting> createState() => _GlassClaritySettingState();
}

class _GlassClaritySettingState extends State<GlassClaritySetting> {
  late double _value = _normalizeClarity(widget.value);
  double get _defaultClarity => widget.isButton
      ? GlassAppearance.defaultButtonClarity
      : GlassAppearance.defaultClarity;
  double _normalizeClarity(Object? value) => widget.isButton
      ? GlassAppearance.normalizeButtonClarity(value)
      : GlassAppearance.normalize(value);
  String get _clarityTitle => widget.isButton ? '按钮通透程度' : '底栏通透程度';
  String get _blurTitle => widget.isButton ? '按钮模糊程度' : '底栏模糊程度';
  bool _dirty = false;
  late double _blurValue = GlassAppearance.normalizeBlur(widget.blurValue);
  bool _blurDirty = false;
  late GlassTint _tint = widget.tint;

  void _changeBlur(double value) {
    final normalized = GlassAppearance.normalizeBlur(value);
    setState(() {
      _blurValue = normalized;
      _blurDirty = true;
    });
    widget.onBlurChanged?.call(normalized);
  }

  void _saveBlur(double value) {
    widget.onBlurSaved?.call(GlassAppearance.normalizeBlur(value));
    _blurDirty = false;
  }

  void _change(double value) {
    final normalized = _normalizeClarity(value);
    setState(() {
      _value = normalized;
      _dirty = true;
    });
    widget.onChanged(normalized);
  }

  void _save(double value) {
    widget.onSaved(_normalizeClarity(value));
    _dirty = false;
  }

  @override
  void didUpdateWidget(covariant GlassClaritySetting oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && !_dirty) {
      _value = _normalizeClarity(widget.value);
    }
    if (oldWidget.blurValue != widget.blurValue && !_blurDirty) {
      _blurValue = GlassAppearance.normalizeBlur(widget.blurValue);
    }
    if (oldWidget.tint != widget.tint) _tint = widget.tint;
  }

  void _reset() {
    _change(_defaultClarity);
    _save(_value);
  }

  @override
  void dispose() {
    // Persist an in-flight drag if the settings route closes/cancels it.
    if (_dirty) _save(_value);
    if (_blurDirty) _saveBlur(_blurValue);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ColorScheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.onTintChanged != null) ...[
            Row(
              children: [
                Expanded(child: Text(widget.isButton ? '按钮底色' : '底栏底色')),
                DropdownButton<GlassTint>(
                  key: ValueKey(
                    widget.isButton ? 'glass-button-tint' : 'glass-bar-tint',
                  ),
                  value: _tint,
                  items: [
                    for (final tint in GlassTint.values)
                      DropdownMenuItem(value: tint, child: Text(tint.label)),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _tint = value);
                    widget.onTintChanged!(value);
                  },
                ),
              ],
            ),
            Text(
              widget.isButton
                  ? '仅原生底栏生效。自动：浅色主题用黑底，深色主题用白底。按住时按钮底色消退。'
                  : '底色选择仅原生底栏生效。自动：浅色主题用白底，深色主题用黑底。',
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Icon(Icons.opacity, color: colors.onSurfaceVariant),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  _clarityTitle,
                  style: TextTheme.of(context).titleMedium,
                ),
              ),
              Text('${(_value * 100).round()}%'),
              IconButton(
                tooltip: widget.isButton ? '恢复默认按钮通透程度' : '恢复默认',
                icon: const Icon(Icons.restore),
                onPressed: _value == _defaultClarity ? null : _reset,
              ),
            ],
          ),
          if (!widget.isButton)
            ExcludeSemantics(
              child: IgnorePointer(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    height: 96,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Row(
                          children: [
                            for (final color in const [
                              Color(0xFF9DDCF4),
                              Color(0xFFF2D28A),
                              Color(0xFFE6B1CF),
                            ])
                              Expanded(
                                child: ColoredBox(
                                  color: color,
                                  child: const Center(
                                    child: Text(
                                      'Aa',
                                      style: TextStyle(
                                        color: Color(0xFF3B3442),
                                        fontSize: 28,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: ReducedTransparencyScope(
                              reduceTransparency: MediaQuery.highContrastOf(
                                context,
                              ),
                              child: GlassTheme(
                                data: GlassThemeData(
                                  menuSurface: colors.surface,
                                  fallbackSurface: colors.surface,
                                ),
                                child: GlassSegmentedControl<String>(
                                  height: 64,
                                  inset: 4,
                                  blurSigma: GlassAppearance.flutterBlurSigma(
                                    _blurValue,
                                  ),
                                  surfaceOpacity:
                                      GlassAppearance.surfaceOpacity(
                                        _value,
                                      ),
                                  selected: 'home',
                                  segments: const [
                                    GlassSegment(value: 'home', label: '首页'),
                                    GlassSegment(
                                      value: 'dynamics',
                                      label: '动态',
                                    ),
                                    GlassSegment(value: 'mine', label: '我的'),
                                  ],
                                  itemBuilder: (_, segment, active) => Icon(
                                    switch (segment.value) {
                                      'home' =>
                                        active
                                            ? Icons.home
                                            : Icons.home_outlined,
                                      'dynamics' =>
                                        Icons.motion_photos_on_outlined,
                                      _ => Icons.person_outline,
                                    },
                                    size: 23,
                                    color: active
                                        ? colors.primary
                                        : colors.onSurface,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Slider(
            key: ValueKey(
              widget.isButton
                  ? 'glass-button-clarity-slider'
                  : 'glass-clarity-slider',
            ),
            value: _value,
            divisions: 100,
            label: '${(_value * 100).round()}%',
            semanticFormatterCallback: (value) =>
                '$_clarityTitle ${(value * 100).round()}%',
            onChanged: _change,
            onChangeEnd: _save,
          ),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [Text('更有底色'), Text('更清透')],
          ),
          if (widget.onBlurChanged != null) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.blur_on, color: colors.onSurfaceVariant),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    _blurTitle,
                    style: TextTheme.of(context).titleMedium,
                  ),
                ),
                Text('${(_blurValue * 100).round()}%'),
                IconButton(
                  tooltip: widget.isButton ? '恢复默认按钮模糊程度' : '恢复默认模糊程度',
                  icon: const Icon(Icons.restore),
                  onPressed: _blurValue == GlassAppearance.defaultBlur
                      ? null
                      : () {
                          _changeBlur(GlassAppearance.defaultBlur);
                          _saveBlur(_blurValue);
                        },
                ),
              ],
            ),
            Slider(
              key: ValueKey(
                widget.isButton
                    ? 'glass-button-blur-slider'
                    : 'glass-blur-slider',
              ),
              value: _blurValue,
              divisions: 100,
              label: '${(_blurValue * 100).round()}%',
              semanticFormatterCallback: (value) =>
                  '$_blurTitle ${(value * 100).round()}%',
              onChanged: _changeBlur,
              onChangeEnd: _saveBlur,
            ),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [Text('清晰'), Text('柔和')],
            ),
            Text(
              widget.isButton
                  ? '仅原生底栏生效：按钮效果叠加在底栏上，0% 不额外模糊。按住只减淡按钮自身，底栏保持原样。'
                  : '0% 关闭底栏背景模糊，折射与高光保留；50% 为默认效果',
            ),
          ],
        ],
      ),
    );
  }
}
