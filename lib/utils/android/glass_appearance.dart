import 'package:PiliPlus/utils/storage_key.dart';
import 'package:hive_ce/hive.dart';

enum GlassTint {
  automatic('自动'),
  white('白色'),
  black('黑色');

  const GlassTint(this.label);
  final String label;

  static GlassTint fromPreference(Object? value) => values.firstWhere(
    (tint) => tint.name == value,
    orElse: () => automatic,
  );
}

abstract final class GlassAppearance {
  // Retain the accepted 0.4 track tint when no preference has been saved.
  static const defaultClarity = 0.6;
  static const defaultBlur = 0.5;
  static const defaultBarWidth = 0.0; // Automatic: retain the accepted layout.
  static const minBarWidth = 200.0;
  static const maxBarWidth = 600.0;

  static double normalizeBarWidth(Object? value) =>
      value is num && value.isFinite && value > 0
      ? value.toDouble().clamp(minBarWidth, maxBarWidth)
      : defaultBarWidth;

  static double nativeBarMaxWidth(Object? value) {
    final width = normalizeBarWidth(value);
    return width == defaultBarWidth ? 480 : width;
  }

  static double normalize(Object? value) => value is num && value.isFinite
      ? value.toDouble().clamp(0.0, 1.0)
      : defaultClarity;

  static double surfaceOpacity(Object? clarity) => 1 - normalize(clarity);

  static double normalizeBlur(Object? value) => value is num && value.isFinite
      ? value.toDouble().clamp(0.0, 1.0)
      : defaultBlur;

  // The midpoint preserves each renderer's accepted blur exactly.
  static double nativeBlurRadius(Object? value) => 16 * normalizeBlur(value);
  static double flutterBlurSigma(Object? value) => 4 * normalizeBlur(value);

  // Snapshot the previous shared values once. Subsequent bar changes must not
  // move the button sliders, including after restarting or importing settings.
  // These are additive preferences; r13 continues to read its original keys.
  static Future<void> initializeNativeControls(Box<dynamic> settings) async {
    final initial = <String, Object>{
      if (!settings.containsKey(SettingBoxKey.androidGlassButtonClarity))
        SettingBoxKey.androidGlassButtonClarity: normalize(
          settings.get(SettingBoxKey.androidGlassClarity),
        ),
      if (!settings.containsKey(SettingBoxKey.androidGlassButtonBlur))
        SettingBoxKey.androidGlassButtonBlur: normalizeBlur(
          settings.get(SettingBoxKey.androidGlassBlur),
        ),
    };
    if (initial.isNotEmpty) await settings.putAll(initial);
  }
}
