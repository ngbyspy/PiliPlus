import 'package:PiliPlus/utils/android/glass_appearance.dart';
import 'package:flutter_liquid_glasses/flutter_liquid_glasses.dart';
import 'package:material_ui/material_ui.dart';

class GlassClaritySetting extends StatefulWidget {
  const GlassClaritySetting({
    super.key,
    required this.value,
    required this.onChanged,
    required this.onSaved,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onSaved;

  @override
  State<GlassClaritySetting> createState() => _GlassClaritySettingState();
}

class _GlassClaritySettingState extends State<GlassClaritySetting> {
  late double _value = GlassAppearance.normalize(widget.value);
  bool _dirty = false;

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
  }

  void _reset() {
    _change(GlassAppearance.defaultClarity);
    _save(_value);
  }

  @override
  void dispose() {
    // Persist an in-flight drag if the settings route closes/cancels it.
    if (_dirty) _save(_value);
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
                child: Text('玻璃通透程度', style: TextTheme.of(context).titleMedium),
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
                                blurSigma: 2,
                                surfaceOpacity: GlassAppearance.surfaceOpacity(
                                  _value,
                                ),
                                selected: 'home',
                                segments: const [
                                  GlassSegment(value: 'home', label: '首页'),
                                  GlassSegment(value: 'dynamics', label: '动态'),
                                  GlassSegment(value: 'mine', label: '我的'),
                                ],
                                itemBuilder: (_, segment, active) => Icon(
                                  switch (segment.value) {
                                    'home' =>
                                      active ? Icons.home : Icons.home_outlined,
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
            value: _value,
            divisions: 100,
            label: '${(_value * 100).round()}%',
            semanticFormatterCallback: (value) =>
                '玻璃通透程度 ${(value * 100).round()}%',
            onChanged: _change,
            onChangeEnd: _save,
          ),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [Text('更有底色'), Text('更清透')],
          ),
        ],
      ),
    );
  }
}
