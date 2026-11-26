enum GlassTint {
  automatic('自动'),
  white('白色'),
  black('黑色');

  const GlassTint(this.label);
  final String label;

  static GlassTint fromPreference(Object? value) =>
      values.where((tint) => tint.name == value).firstOrNull ?? automatic;
}

abstract final class GlassAppearance {
  // Retain the accepted 0.4 track tint when no preference has been saved.
  static const defaultClarity = 0.6;
  static const defaultBlur = 0.5;
  static const defaultButtonClarity = 0.9;

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

  static double normalizeButtonClarity(Object? value) =>
      value is num && value.isFinite
      ? value.toDouble().clamp(0.0, 1.0)
      : defaultButtonClarity;
  static double buttonSurfaceOpacity(Object? value) =>
      1 - normalizeButtonClarity(value);
  // Extra blur of the bar material, never a replacement for the bar's blur.
  static double nativeButtonBlurRadius(Object? value) =>
      32 * normalizeBlur(value);
}
