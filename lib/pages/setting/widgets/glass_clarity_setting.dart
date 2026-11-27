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
    this.title = '玻璃',
    this.showPreview = true,
    this.tint = GlassTint.automatic,
    this.onTintChanged,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onSaved;
  final double blurValue;
  final ValueChanged<double>? onBlurChanged;
  final ValueChanged<double>? onBlurSaved;
  final String title;
  final bool showPreview;
  final GlassTint tint;
  final ValueChanged<GlassTint>? onTintChanged;

  @override
  State<GlassClaritySetting> createState() => _GlassClaritySettingState();
}

class _GlassClaritySettingState extends State<GlassClaritySetting> {
  late double _value = GlassAppearance.normalize(widget.value);
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
    final normalized = GlassAppearance.normalize(value);
    setState(() {
      _value = normalized;
      _dirty = true;
    });
    widget.onChanged(normalized);
  }

  void _save(double value) {
    widget.onSaved(GlassAppearance.normalize(value));
    _dirty = false;
  }

  @override
  void didUpdateWidget(covariant GlassClaritySetting oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && !_dirty) {
      _value = GlassAppearance.normalize(widget.value);
    }
    if (oldWidget.blurValue != widget.blurValue && !_blurDirty) {
      _blurValue = GlassAppearance.normalizeBlur(widget.blurValue);
    }
    if (oldWidget.tint != widget.tint) _tint = widget.tint;
  }

  void _reset() {
    _change(GlassAppearance.defaultClarity);
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
          Row(
            children: [
              Icon(Icons.opacity, color: colors.onSurfaceVariant),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  '${widget.title}通透程度',
                  style: TextTheme.of(context).titleMedium,
                ),
              ),
              Text('${(_value * 100).round()}%'),
              IconButton(
                tooltip: '恢复默认',
                icon: const Icon(Icons.restore),
                onPressed: _value == GlassAppearance.defaultClarity
                    ? null
                    : _reset,
              ),
            ],
          ),
          if (widget.showPreview)
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
            key: const ValueKey('glass-clarity-slider'),
            value: _value,
            divisions: 100,
            label: '${(_value * 100).round()}%',
            semanticFormatterCallback: (value) =>
                '${widget.title}通透程度 ${(value * 100).round()}%',
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
                    '${widget.title}模糊程度',
                    style: TextTheme.of(context).titleMedium,
                  ),
                ),
                Text('${(_blurValue * 100).round()}%'),
                IconButton(
                  tooltip: '恢复默认模糊程度',
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
              key: const ValueKey('glass-blur-slider'),
              value: _blurValue,
              divisions: 100,
              label: '${(_blurValue * 100).round()}%',
              semanticFormatterCallback: (value) =>
                  '${widget.title}模糊程度 ${(value * 100).round()}%',
              onChanged: _changeBlur,
              onChangeEnd: _saveBlur,
            ),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [Text('清晰'), Text('柔和')],
            ),
            const Text('0% 关闭背景模糊，折射与高光保留；50% 为默认效果'),
          ],
          if (widget.onTintChanged != null) ...[
            const SizedBox(height: 12),
            Text('${widget.title}底色'),
            const SizedBox(height: 8),
            SegmentedButton<GlassTint>(
              showSelectedIcon: false,
              segments: [
                for (final tint in GlassTint.values)
                  ButtonSegment(value: tint, label: Text(tint.label)),
              ],
              selected: {_tint},
              onSelectionChanged: (selection) {
                final tint = selection.single;
                setState(() => _tint = tint);
                widget.onTintChanged!(tint);
              },
            ),
          ],
        ],
      ),
    );
  }
}
