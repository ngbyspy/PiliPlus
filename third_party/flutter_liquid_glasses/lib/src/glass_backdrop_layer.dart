import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

/// Refresh window-space optics when a retained glass subtree moves.
///
/// Scroll/route transitions can composite a cached child without repainting it.
/// Bind the filter at scene submission so it sees the final ancestor transform,
/// including frames where the glass render object did not paint. This does not
/// schedule frames or create an animation while the screen is idle.
class GlassBackdropFilterLayer extends BackdropFilterLayer {
  GlassBackdropFilterLayer(this.resolveFilter);

  final ui.ImageFilter Function() resolveFilter;
  ui.ImageFilter? _resolvedFilter;

  @override
  bool get alwaysNeedsAddToScene => true;

  @override
  ui.ImageFilter? get filter => _resolvedFilter;

  @override
  void addToScene(ui.SceneBuilder builder) {
    _resolvedFilter = resolveFilter();
    super.addToScene(builder);
  }
}
