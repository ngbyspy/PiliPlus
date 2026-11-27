import 'dart:math' as math;

import 'package:PiliPlus/utils/android/glass_appearance.dart';
import 'package:material_ui/material_ui.dart';

class GlassBarWidthSetting extends StatefulWidget {
  const GlassBarWidthSetting({
    super.key,
    required this.value,
    required this.onChanged,
    required this.onSaved,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onSaved;

  @override
  State<GlassBarWidthSetting> createState() => _GlassBarWidthSettingState();
}

class _GlassBarWidthSettingState extends State<GlassBarWidthSetting> {
  late double _value = GlassAppearance.normalizeBarWidth(widget.value);
  bool _dirty = false;

  void _change(double value) {
    final normalized = GlassAppearance.normalizeBarWidth(value);
    setState(() {
      _value = normalized;
      _dirty = true;
    });
    widget.onChanged(normalized);
  }

  void _save(double value) {
    widget.onSaved(GlassAppearance.normalizeBarWidth(value));
    _dirty = false;
  }

  @override
  void didUpdateWidget(covariant GlassBarWidthSetting oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && !_dirty) {
      _value = GlassAppearance.normalizeBarWidth(widget.value);
    }
  }

  @override
  void dispose() {
    if (_dirty) _save(_value);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final available = math.max(
      1.0,
      MediaQuery.sizeOf(context).width -
          MediaQuery.paddingOf(context).horizontal -
          48,
    );
    final maximum = math.min(GlassAppearance.maxBarWidth, available);
    final minimum = math.min(GlassAppearance.minBarWidth, maximum);
    final effective = GlassAppearance.nativeBarMaxWidth(_value)
        .clamp(minimum, maximum);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.swap_horiz),
              const SizedBox(width: 16),
              Expanded(
                child: Text('底栏宽度', style: TextTheme.of(context).titleMedium),
              ),
              Text('${_value == 0 ? '自动 · ' : ''}${effective.round()} dp'),
              IconButton(
                tooltip: '恢复自动宽度',
                onPressed: _value == 0
                    ? null
                    : () {
                        _change(GlassAppearance.defaultBarWidth);
                        _save(_value);
                      },
                icon: const Icon(Icons.restore),
              ),
            ],
          ),
          Slider(
            key: const ValueKey('glass-bar-width-slider'),
            value: effective,
            min: minimum,
            max: maximum,
            divisions: math.max(1, (maximum - minimum).round()),
            label: '${effective.round()} dp',
            semanticFormatterCallback: (value) => '底栏宽度 ${value.round()} 逻辑像素',
            onChanged: (value) => _change(value.roundToDouble()),
            onChangeEnd: (_) => _save(_value),
          ),
          const Text('保持居中和原有高度，各栏目等分宽度；超出可用屏幕时自动限制。'),
        ],
      ),
    );
  }
}
