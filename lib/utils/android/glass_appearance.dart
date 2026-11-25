abstract final class GlassAppearance {
  // Retain the accepted 0.4 track tint when no preference has been saved.
  static const defaultClarity = 0.6;

  static double normalize(Object? value) => value is num && value.isFinite
      ? value.toDouble().clamp(0.0, 1.0)
      : defaultClarity;

  static double surfaceOpacity(Object? clarity) => 1 - normalize(clarity);
}
